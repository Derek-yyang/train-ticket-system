from __future__ import annotations

import os
from datetime import date, datetime, timedelta
from functools import wraps

import pymysql
from dotenv import load_dotenv
from flask import Flask, abort, flash, g, redirect, render_template, request, session, url_for
from pymysql.cursors import DictCursor
from werkzeug.security import check_password_hash, generate_password_hash

from config import Config

load_dotenv()

SEAT_TYPE_LABELS = {
    "SECOND_CLASS": "二等座",
    "FIRST_CLASS": "一等座",
    "BUSINESS": "商务座",
}
ORDER_STATUS_LABELS = {
    "PENDING": "待确认",
    "CONFIRMED": "已确认",
    "CANCELED": "已取消",
}


def create_app() -> Flask:
    app = Flask(__name__)
    app.config.from_object(Config)

    def get_db():
        if "db" not in g:
            g.db = pymysql.connect(
                host=app.config["MYSQL_HOST"],
                port=app.config["MYSQL_PORT"],
                user=app.config["MYSQL_USER"],
                password=app.config["MYSQL_PASSWORD"],
                database=app.config["MYSQL_DATABASE"],
                charset="utf8mb4",
                cursorclass=DictCursor,
                autocommit=True,
            )
        return g.db

    @app.teardown_appcontext
    def close_db(_error=None):
        db = g.pop("db", None)
        if db is not None:
            db.close()

    def query_all(sql: str, params: tuple = ()) -> list[dict]:
        with get_db().cursor() as cursor:
            cursor.execute(sql, params)
            return cursor.fetchall()

    def query_one(sql: str, params: tuple = ()) -> dict | None:
        with get_db().cursor() as cursor:
            cursor.execute(sql, params)
            return cursor.fetchone()

    def execute(sql: str, params: tuple = ()) -> int:
        with get_db().cursor() as cursor:
            return cursor.execute(sql, params)

    def login_required(view):
        @wraps(view)
        def wrapped(*args, **kwargs):
            if not g.get("current_user"):
                flash("请先登录后再进行该操作。", "warning")
                return redirect(url_for("login", next=request.full_path))
            return view(*args, **kwargs)

        return wrapped

    def admin_required(view):
        @wraps(view)
        def wrapped(*args, **kwargs):
            if not g.get("current_user"):
                flash("请先登录管理员账号。", "warning")
                return redirect(url_for("login"))
            if g.current_user["role"] != "ADMIN":
                abort(403)
            return view(*args, **kwargs)

        return wrapped

    @app.before_request
    def load_current_user():
        user_id = session.get("user_id")
        g.current_user = None
        if user_id:
            g.current_user = query_one(
                """
                SELECT user_id, username, real_name, role, user_status
                FROM app_users
                WHERE user_id = %s AND user_status = 'ACTIVE'
                """,
                (user_id,),
            )
            if g.current_user is None:
                session.clear()

    @app.context_processor
    def inject_template_values():
        return {
            "current_user": g.get("current_user"),
            "seat_type_labels": SEAT_TYPE_LABELS,
            "order_status_labels": ORDER_STATUS_LABELS,
            "today": date.today().isoformat(),
            "default_date": (date.today() + timedelta(days=1)).isoformat(),
        }

    @app.template_filter("cn_datetime")
    def cn_datetime(value):
        if not value:
            return "-"
        if isinstance(value, datetime):
            return value.strftime("%Y-%m-%d %H:%M")
        return str(value)

    @app.get("/")
    def home():
        stations = query_all(
            "SELECT station_id, station_name, city_name FROM stations WHERE station_status = 'ACTIVE' ORDER BY city_name, station_name"
        )
        highlights = query_all(
            """
            SELECT * FROM v_train_schedule_search
            WHERE travel_date >= CURDATE()
            ORDER BY travel_date, departure_time
            LIMIT 6
            """
        )
        return render_template("home.html", stations=stations, highlights=highlights)

    @app.get("/search")
    def search():
        stations = query_all(
            "SELECT station_id, station_name, city_name FROM stations WHERE station_status = 'ACTIVE' ORDER BY city_name, station_name"
        )
        departure_station_id = request.args.get("departure_station_id", type=int)
        arrival_station_id = request.args.get("arrival_station_id", type=int)
        travel_date = request.args.get("travel_date") or (date.today() + timedelta(days=1)).isoformat()
        trains = []
        searched = departure_station_id is not None and arrival_station_id is not None

        if searched:
            if departure_station_id == arrival_station_id:
                flash("出发站和到达站不能相同。", "error")
            else:
                trains = query_all(
                    """
                    SELECT * FROM v_train_schedule_search
                    WHERE departure_station_id = %s
                      AND arrival_station_id = %s
                      AND travel_date = %s
                    ORDER BY departure_time, lowest_fare
                    """,
                    (departure_station_id, arrival_station_id, travel_date),
                )
        return render_template(
            "search.html",
            stations=stations,
            trains=trains,
            searched=searched,
            selected={
                "departure_station_id": departure_station_id,
                "arrival_station_id": arrival_station_id,
                "travel_date": travel_date,
            },
        )

    @app.get("/trips/<int:schedule_id>")
    def trip_detail(schedule_id: int):
        departure_station_id = request.args.get("departure_station_id", type=int)
        arrival_station_id = request.args.get("arrival_station_id", type=int)
        if not departure_station_id or not arrival_station_id:
            abort(400)

        trip = query_one(
            """
            SELECT * FROM v_train_schedule_search
            WHERE schedule_id = %s
              AND departure_station_id = %s
              AND arrival_station_id = %s
            """,
            (schedule_id, departure_station_id, arrival_station_id),
        )
        if not trip:
            abort(404)
        seat_summary = query_all(
            """
            SELECT seat_type, COUNT(*) AS total_count,
                   SUM(seat_status = 'AVAILABLE') AS available_count,
                   MIN(CASE WHEN seat_status = 'AVAILABLE' THEN fare END) AS fare
            FROM schedule_seats
            WHERE schedule_id = %s
            GROUP BY seat_type
            ORDER BY FIELD(seat_type, 'SECOND_CLASS', 'FIRST_CLASS', 'BUSINESS')
            """,
            (schedule_id,),
        )
        return render_template("trip_detail.html", trip=trip, seat_summary=seat_summary)

    @app.route("/login", methods=["GET", "POST"])
    def login():
        if g.current_user:
            return redirect(url_for("home"))
        if request.method == "POST":
            username = request.form.get("username", "").strip()
            password = request.form.get("password", "")
            user = query_one("SELECT * FROM app_users WHERE username = %s", (username,))
            if not user or user["user_status"] != "ACTIVE" or not check_password_hash(user["password_hash"], password):
                flash("用户名或密码错误。", "error")
            else:
                session.clear()
                session["user_id"] = user["user_id"]
                flash(f"欢迎回来，{user['real_name']}。", "success")
                next_url = request.args.get("next")
                return redirect(next_url if next_url and next_url.startswith("/") else url_for("home"))
        return render_template("login.html")

    @app.route("/register", methods=["GET", "POST"])
    def register():
        if g.current_user:
            return redirect(url_for("home"))
        if request.method == "POST":
            username = request.form.get("username", "").strip()
            password = request.form.get("password", "")
            real_name = request.form.get("real_name", "").strip()
            id_number = request.form.get("id_number", "").strip()
            phone = request.form.get("phone", "").strip()
            if len(username) < 3 or len(password) < 6 or not real_name or len(id_number) not in (15, 18):
                flash("请填写有效信息：用户名至少 3 位、密码至少 6 位、身份证号为 15 或 18 位。", "error")
            else:
                try:
                    execute(
                        """
                        INSERT INTO app_users (username, password_hash, real_name, id_number, phone)
                        VALUES (%s, %s, %s, %s, %s)
                        """,
                        (username, generate_password_hash(password), real_name, id_number, phone or None),
                    )
                    flash("注册成功，请使用新账号登录。", "success")
                    return redirect(url_for("login"))
                except pymysql.MySQLError:
                    flash("用户名或身份证号已被使用。", "error")
        return render_template("register.html")

    @app.post("/logout")
    def logout():
        session.clear()
        flash("已退出登录。", "success")
        return redirect(url_for("home"))

    @app.post("/orders")
    @login_required
    def create_order():
        schedule_id = request.form.get("schedule_id", type=int)
        departure_station_id = request.form.get("departure_station_id", type=int)
        arrival_station_id = request.form.get("arrival_station_id", type=int)
        seat_type = request.form.get("seat_type", "")
        passenger_name = request.form.get("passenger_name", "").strip()
        passenger_id_number = request.form.get("passenger_id_number", "").strip()
        if not all((schedule_id, departure_station_id, arrival_station_id, passenger_name, passenger_id_number)):
            flash("请完整填写乘车人信息。", "error")
            return redirect(request.referrer or url_for("home"))
        try:
            with get_db().cursor() as cursor:
                cursor.callproc(
                    "sp_create_order",
                    (
                        g.current_user["user_id"],
                        schedule_id,
                        departure_station_id,
                        arrival_station_id,
                        seat_type,
                        passenger_name,
                        passenger_id_number,
                    ),
                )
                result = cursor.fetchone()
            flash(f"订票成功，订单号：{result['order_no']}。", "success")
            return redirect(url_for("orders"))
        except pymysql.MySQLError as error:
            flash(f"订票失败：{error.args[1] if len(error.args) > 1 else '请稍后重试'}", "error")
            return redirect(request.referrer or url_for("home"))

    @app.get("/orders")
    @login_required
    def orders():
        order_rows = query_all(
            """
            SELECT o.*, tr.train_code, tr.train_name, sch.travel_date,
                   departure.station_name AS departure_station_name,
                   arrival.station_name AS arrival_station_name,
                   origin_stop.departure_time, destination_stop.arrival_time,
                   op.passenger_name, op.passenger_id_number,
                   carriage.carriage_no, seat.seat_no, ss.seat_type
            FROM orders o
            JOIN train_schedules sch ON sch.schedule_id = o.schedule_id
            JOIN trains tr ON tr.train_id = sch.train_id
            JOIN stations departure ON departure.station_id = o.departure_station_id
            JOIN stations arrival ON arrival.station_id = o.arrival_station_id
            JOIN train_stops origin_stop ON origin_stop.train_id = tr.train_id AND origin_stop.station_id = o.departure_station_id
            JOIN train_stops destination_stop ON destination_stop.train_id = tr.train_id AND destination_stop.station_id = o.arrival_station_id
            JOIN order_passengers op ON op.order_id = o.order_id
            JOIN schedule_seats ss ON ss.schedule_seat_id = op.schedule_seat_id
            JOIN train_seats seat ON seat.seat_id = ss.seat_id
            JOIN carriages carriage ON carriage.carriage_id = seat.carriage_id
            WHERE o.user_id = %s
            ORDER BY o.created_at DESC
            """,
            (g.current_user["user_id"],),
        )
        return render_template("orders.html", orders=order_rows)

    @app.post("/orders/<int:order_id>/cancel")
    @login_required
    def cancel_order(order_id: int):
        try:
            with get_db().cursor() as cursor:
                cursor.callproc("sp_cancel_order", (order_id, g.current_user["user_id"]))
            flash("订单已取消，座位已释放。", "success")
        except pymysql.MySQLError as error:
            flash(f"取消失败：{error.args[1] if len(error.args) > 1 else '请稍后重试'}", "error")
        return redirect(url_for("orders"))

    @app.get("/admin")
    @admin_required
    def admin_dashboard():
        summary = {
            "users": query_one("SELECT COUNT(*) AS count FROM app_users WHERE role = 'PASSENGER'")["count"],
            "on_sale_schedules": query_one("SELECT COUNT(*) AS count FROM train_schedules WHERE schedule_status = 'ON_SALE'")["count"],
            "confirmed_orders": query_one("SELECT COUNT(*) AS count FROM orders WHERE order_status = 'CONFIRMED'")["count"],
            "sales_amount": query_one("SELECT COALESCE(SUM(total_amount), 0) AS total FROM orders WHERE order_status = 'CONFIRMED'")["total"],
        }
        daily_sales = query_all("SELECT * FROM v_daily_sales ORDER BY sales_date DESC, sales_amount DESC LIMIT 10")
        recent_orders = query_all(
            """
            SELECT o.order_no, o.order_status, o.total_amount, o.created_at, u.real_name,
                   tr.train_code, departure.station_name AS departure_station_name, arrival.station_name AS arrival_station_name
            FROM orders o
            JOIN app_users u ON u.user_id = o.user_id
            JOIN train_schedules sch ON sch.schedule_id = o.schedule_id
            JOIN trains tr ON tr.train_id = sch.train_id
            JOIN stations departure ON departure.station_id = o.departure_station_id
            JOIN stations arrival ON arrival.station_id = o.arrival_station_id
            ORDER BY o.created_at DESC LIMIT 8
            """
        )
        return render_template("admin/dashboard.html", summary=summary, daily_sales=daily_sales, recent_orders=recent_orders)

    @app.route("/admin/stations", methods=["GET", "POST"])
    @admin_required
    def admin_stations():
        if request.method == "POST":
            code = request.form.get("station_code", "").strip().upper()
            name = request.form.get("station_name", "").strip()
            city = request.form.get("city_name", "").strip()
            if not code or not name or not city:
                flash("请完整填写车站编号、名称和城市。", "error")
            else:
                try:
                    execute(
                        "INSERT INTO stations (station_code, station_name, city_name) VALUES (%s, %s, %s)",
                        (code, name, city),
                    )
                    flash("车站已新增。", "success")
                    return redirect(url_for("admin_stations"))
                except pymysql.MySQLError:
                    flash("车站编号或城市内名称重复。", "error")
        station_rows = query_all("SELECT * FROM stations ORDER BY city_name, station_name")
        return render_template("admin/stations.html", stations=station_rows)

    @app.post("/admin/stations/<int:station_id>/toggle")
    @admin_required
    def toggle_station(station_id: int):
        execute(
            "UPDATE stations SET station_status = IF(station_status = 'ACTIVE', 'DISABLED', 'ACTIVE') WHERE station_id = %s",
            (station_id,),
        )
        flash("车站状态已更新。", "success")
        return redirect(url_for("admin_stations"))

    @app.post("/admin/stations/<int:station_id>/delete")
    @admin_required
    def delete_station(station_id: int):
        try:
            affected = execute("DELETE FROM stations WHERE station_id = %s", (station_id,))
            flash("车站已删除。" if affected else "未找到该车站。", "success")
        except pymysql.MySQLError:
            flash("该车站已被车次或订单引用，不能删除；可改为停用。", "warning")
        return redirect(url_for("admin_stations"))

    @app.get("/admin/schedules")
    @admin_required
    def admin_schedules():
        schedule_rows = query_all(
            """
            SELECT sch.*, tr.train_code, tr.train_name,
                   SUM(ss.seat_status = 'AVAILABLE') AS available_seats,
                   COUNT(ss.schedule_seat_id) AS total_seats
            FROM train_schedules sch
            JOIN trains tr ON tr.train_id = sch.train_id
            LEFT JOIN schedule_seats ss ON ss.schedule_id = sch.schedule_id
            GROUP BY sch.schedule_id
            ORDER BY sch.travel_date DESC, tr.train_code
            """
        )
        return render_template("admin/schedules.html", schedules=schedule_rows)

    @app.post("/admin/schedules/<int:schedule_id>/toggle")
    @admin_required
    def toggle_schedule(schedule_id: int):
        execute(
            """
            UPDATE train_schedules
            SET schedule_status = IF(schedule_status = 'ON_SALE', 'CLOSED', 'ON_SALE')
            WHERE schedule_id = %s
            """,
            (schedule_id,),
        )
        flash("车次开售状态已更新。", "success")
        return redirect(url_for("admin_schedules"))

    @app.get("/health")
    def health():
        query_one("SELECT 1 AS ok")
        return {"status": "ok", "database": app.config["MYSQL_DATABASE"]}

    return app


app = create_app()

if __name__ == "__main__":
    app.run(host="127.0.0.1", port=int(os.getenv("PORT", "5000")), debug=True)
