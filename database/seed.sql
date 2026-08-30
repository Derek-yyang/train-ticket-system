USE train_ticket_db;

-- 演示账号：管理员 admin / Admin@123；乘客 demo / Demo@123
INSERT INTO app_users (username, password_hash, real_name, id_number, phone, email, role)
VALUES
  ('admin', 'scrypt:32768:8:1$QxPMcwETyw6Y5WXi$8c124305e0af2875a03b12adb8b548c71263659049e9e5bf6e1ef10a5cfd98e9d22b925cff4f6ad1dc2bef06cec22092e46d0ee86fb3c559f3902784029b05ba', '系统管理员', '440100199001010011', '13800000001', 'admin@example.com', 'ADMIN'),
  ('demo', 'scrypt:32768:8:1$WRX1Xh20MKL1qI4m$48e12d085ceb404f6afeaf60b0982c29b39f014a79e1ef6c065bf5ac8c73751305ff2a975e2c2d6de9d34e022ef0e4b1ff008b095d31aacf296b9aa8294a4f5a', '演示乘客', '440100199512120022', '13800000002', 'demo@example.com', 'PASSENGER')
ON DUPLICATE KEY UPDATE real_name = VALUES(real_name), phone = VALUES(phone), role = VALUES(role);

INSERT INTO stations (station_code, station_name, city_name)
VALUES
  ('GZNS', '广州南', '广州'),
  ('SZB', '深圳北', '深圳'),
  ('CSN', '长沙南', '长沙'),
  ('WH', '武汉', '武汉'),
  ('BJX', '北京西', '北京'),
  ('SHA', '上海虹桥', '上海')
ON DUPLICATE KEY UPDATE station_status = 'ACTIVE';

INSERT INTO trains (train_code, train_name)
VALUES
  ('G1001', '复兴号高速列车'),
  ('G6012', '南方城市快线'),
  ('D2305', '沿海动卧列车')
ON DUPLICATE KEY UPDATE train_status = 'ACTIVE';

INSERT INTO train_stops (train_id, station_id, stop_sequence, arrival_time, departure_time, day_offset)
SELECT t.train_id, s.station_id, x.stop_sequence, x.arrival_time, x.departure_time, x.day_offset
FROM (
  SELECT 'G1001' AS train_code, 'GZNS' AS station_code, 1 AS stop_sequence, NULL AS arrival_time, '07:20:00' AS departure_time, 0 AS day_offset
  UNION ALL SELECT 'G1001', 'CSN', 2, '09:35:00', '09:40:00', 0
  UNION ALL SELECT 'G1001', 'WH', 3, '11:05:00', '11:10:00', 0
  UNION ALL SELECT 'G1001', 'BJX', 4, '15:25:00', NULL, 0
  UNION ALL SELECT 'G6012', 'GZNS', 1, NULL, '08:10:00', 0
  UNION ALL SELECT 'G6012', 'SZB', 2, '08:42:00', NULL, 0
  UNION ALL SELECT 'D2305', 'GZNS', 1, NULL, '20:15:00', 0
  UNION ALL SELECT 'D2305', 'SZB', 2, '21:05:00', '21:12:00', 0
  UNION ALL SELECT 'D2305', 'SHA', 3, '06:50:00', NULL, 1
) x
JOIN trains t ON t.train_code = x.train_code
JOIN stations s ON s.station_code = x.station_code
ON DUPLICATE KEY UPDATE arrival_time = VALUES(arrival_time), departure_time = VALUES(departure_time), day_offset = VALUES(day_offset);

INSERT INTO carriages (train_id, carriage_no, seat_type)
SELECT t.train_id, x.carriage_no, x.seat_type
FROM (
  SELECT 'G1001' AS train_code, 1 AS carriage_no, 'BUSINESS' AS seat_type
  UNION ALL SELECT 'G1001', 2, 'FIRST_CLASS'
  UNION ALL SELECT 'G1001', 3, 'SECOND_CLASS'
  UNION ALL SELECT 'G6012', 1, 'FIRST_CLASS'
  UNION ALL SELECT 'G6012', 2, 'SECOND_CLASS'
  UNION ALL SELECT 'D2305', 1, 'FIRST_CLASS'
  UNION ALL SELECT 'D2305', 2, 'SECOND_CLASS'
) x
JOIN trains t ON t.train_code = x.train_code
ON DUPLICATE KEY UPDATE seat_type = VALUES(seat_type);

INSERT INTO train_seats (carriage_id, seat_no)
SELECT c.carriage_id, n.seat_no
FROM carriages c
JOIN trains t ON t.train_id = c.train_id
JOIN (
  SELECT '01A' AS seat_no UNION ALL SELECT '01B' UNION ALL SELECT '02A' UNION ALL SELECT '02B'
  UNION ALL SELECT '03A' UNION ALL SELECT '03B' UNION ALL SELECT '04A' UNION ALL SELECT '04B'
) n
WHERE NOT EXISTS (
  SELECT 1 FROM train_seats existing_seat
  WHERE existing_seat.carriage_id = c.carriage_id AND existing_seat.seat_no = n.seat_no
);

INSERT INTO train_schedules (train_id, travel_date, schedule_status)
SELECT t.train_id, CURDATE() + INTERVAL x.days_after DAY, 'ON_SALE'
FROM (
  SELECT 'G1001' AS train_code, 1 AS days_after UNION ALL SELECT 'G1001', 2
  UNION ALL SELECT 'G6012', 1 UNION ALL SELECT 'G6012', 2
  UNION ALL SELECT 'D2305', 1 UNION ALL SELECT 'D2305', 2
) x
JOIN trains t ON t.train_code = x.train_code
ON DUPLICATE KEY UPDATE schedule_status = 'ON_SALE';

INSERT INTO schedule_seats (schedule_id, seat_id, seat_type, fare, seat_status)
SELECT
  sch.schedule_id,
  seat.seat_id,
  carriage.seat_type,
  CASE
    WHEN train.train_code = 'G1001' AND carriage.seat_type = 'BUSINESS' THEN 1280.00
    WHEN train.train_code = 'G1001' AND carriage.seat_type = 'FIRST_CLASS' THEN 860.00
    WHEN train.train_code = 'G1001' THEN 520.00
    WHEN train.train_code = 'G6012' AND carriage.seat_type = 'FIRST_CLASS' THEN 168.00
    WHEN train.train_code = 'G6012' THEN 98.00
    WHEN carriage.seat_type = 'FIRST_CLASS' THEN 680.00
    ELSE 388.00
  END,
  'AVAILABLE'
FROM train_schedules sch
JOIN trains train ON train.train_id = sch.train_id
JOIN carriages carriage ON carriage.train_id = train.train_id
JOIN train_seats seat ON seat.carriage_id = carriage.carriage_id
WHERE NOT EXISTS (
  SELECT 1 FROM schedule_seats existing_seat
  WHERE existing_seat.schedule_id = sch.schedule_id AND existing_seat.seat_id = seat.seat_id
);

-- 预置一笔已确认订单，用于管理员统计与订单演示。
SET @demo_user_id := (SELECT user_id FROM app_users WHERE username = 'demo');
SET @demo_schedule_id := (SELECT sch.schedule_id FROM train_schedules sch JOIN trains t ON t.train_id = sch.train_id WHERE t.train_code = 'G1001' AND sch.travel_date = CURDATE() + INTERVAL 1 DAY LIMIT 1);
SET @demo_departure_id := (SELECT station_id FROM stations WHERE station_code = 'GZNS');
SET @demo_arrival_id := (SELECT station_id FROM stations WHERE station_code = 'BJX');
SET @existing_demo_schedule_seat_id := (
  SELECT op.schedule_seat_id
  FROM order_passengers op
  JOIN orders o ON o.order_id = op.order_id
  WHERE o.order_no = 'TTDEMO000001'
  LIMIT 1
);
SET @demo_schedule_seat_id := COALESCE(@existing_demo_schedule_seat_id, (
  SELECT ss.schedule_seat_id FROM schedule_seats ss
  WHERE ss.schedule_id = @demo_schedule_id AND ss.seat_type = 'SECOND_CLASS' AND ss.seat_status = 'AVAILABLE'
  ORDER BY ss.schedule_seat_id LIMIT 1
));
UPDATE schedule_seats SET seat_status = 'SOLD' WHERE schedule_seat_id = @demo_schedule_seat_id;
INSERT INTO orders (order_no, user_id, schedule_id, departure_station_id, arrival_station_id, order_status, total_amount)
SELECT 'TTDEMO000001', @demo_user_id, @demo_schedule_id, @demo_departure_id, @demo_arrival_id, 'CONFIRMED', 520.00
WHERE NOT EXISTS (SELECT 1 FROM orders WHERE order_no = 'TTDEMO000001');
SET @confirmed_order_id := (SELECT order_id FROM orders WHERE order_no = 'TTDEMO000001');
INSERT INTO order_passengers (order_id, schedule_seat_id, passenger_name, passenger_id_number, ticket_price)
SELECT @confirmed_order_id, @demo_schedule_seat_id, '演示乘客', '440100199512120022', 520.00
WHERE NOT EXISTS (SELECT 1 FROM order_passengers WHERE order_id = @confirmed_order_id);
