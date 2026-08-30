"""Render representative UI pages without a live MySQL service for visual QA and report figures."""

from datetime import date, time, timedelta
from pathlib import Path
import sys

from flask import g, render_template

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from app import create_app


OUT_DIR = ROOT / "docs" / "rendered" / "html"

STATIONS = [
    {"station_id": 1, "station_name": "广州南", "city_name": "广州"},
    {"station_id": 2, "station_name": "深圳北", "city_name": "深圳"},
    {"station_id": 5, "station_name": "北京西", "city_name": "北京"},
]
TRIP = {
    "schedule_id": 1,
    "travel_date": date.today() + timedelta(days=1),
    "train_code": "G1001",
    "train_name": "复兴号高速列车",
    "departure_station_id": 1,
    "departure_station_name": "广州南",
    "arrival_station_id": 5,
    "arrival_station_name": "北京西",
    "departure_time": time(7, 20),
    "arrival_time": time(15, 25),
    "available_seats": 21,
    "lowest_fare": 520.0,
}
SEAT_SUMMARY = [
    {"seat_type": "SECOND_CLASS", "total_count": 8, "available_count": 6, "fare": 520.0},
    {"seat_type": "FIRST_CLASS", "total_count": 8, "available_count": 8, "fare": 860.0},
    {"seat_type": "BUSINESS", "total_count": 8, "available_count": 7, "fare": 1280.0},
]


def write_page(app, name: str, template: str, **context):
    with app.test_request_context("/"):
        g.current_user = context.pop("current_user", None)
        (OUT_DIR / name).write_text(render_template(template, **context), encoding="utf-8")


def main():
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    app = create_app()
    write_page(app, "home.html", "home.html", stations=STATIONS, highlights=[TRIP])
    write_page(
        app,
        "search.html",
        "search.html",
        stations=STATIONS,
        trains=[TRIP],
        searched=True,
        selected={"departure_station_id": 1, "arrival_station_id": 5, "travel_date": TRIP["travel_date"].isoformat()},
    )
    write_page(app, "trip-detail.html", "trip_detail.html", trip=TRIP, seat_summary=SEAT_SUMMARY)
    write_page(
        app,
        "admin-dashboard.html",
        "admin/dashboard.html",
        current_user={"real_name": "系统管理员", "role": "ADMIN"},
        summary={"users": 18, "on_sale_schedules": 6, "confirmed_orders": 12, "sales_amount": 5640.0},
        daily_sales=[{"sales_date": date.today(), "train_code": "G1001", "train_name": "复兴号高速列车", "confirmed_orders": 8, "sold_tickets": 8, "sales_amount": 4160.0}],
        recent_orders=[{"order_no": "TTDEMO000001", "order_status": "CONFIRMED", "total_amount": 520.0, "created_at": date.today(), "real_name": "演示乘客", "train_code": "G1001", "departure_station_name": "广州南", "arrival_station_name": "北京西"}],
    )
    print(f"Rendered mock pages to {OUT_DIR}")


if __name__ == "__main__":
    main()
