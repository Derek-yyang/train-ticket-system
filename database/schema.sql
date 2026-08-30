-- 行程站火车订票系统：MySQL 8.0+ 数据库结构
-- 执行顺序：schema.sql -> routines.sql -> seed.sql

CREATE DATABASE IF NOT EXISTS train_ticket_db
  DEFAULT CHARACTER SET utf8mb4
  COLLATE utf8mb4_0900_ai_ci;
USE train_ticket_db;

CREATE TABLE IF NOT EXISTS app_users (
  user_id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  username VARCHAR(32) NOT NULL,
  password_hash VARCHAR(255) NOT NULL,
  real_name VARCHAR(32) NOT NULL,
  id_number VARCHAR(18) NULL,
  phone VARCHAR(20) NULL,
  email VARCHAR(100) NULL,
  role ENUM('PASSENGER', 'ADMIN') NOT NULL DEFAULT 'PASSENGER',
  user_status ENUM('ACTIVE', 'DISABLED') NOT NULL DEFAULT 'ACTIVE',
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (user_id),
  UNIQUE KEY uk_users_username (username),
  UNIQUE KEY uk_users_id_number (id_number),
  CONSTRAINT ck_users_username CHECK (CHAR_LENGTH(username) BETWEEN 3 AND 32)
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS stations (
  station_id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  station_code VARCHAR(12) NOT NULL,
  station_name VARCHAR(50) NOT NULL,
  city_name VARCHAR(50) NOT NULL,
  station_status ENUM('ACTIVE', 'DISABLED') NOT NULL DEFAULT 'ACTIVE',
  PRIMARY KEY (station_id),
  UNIQUE KEY uk_stations_code (station_code),
  UNIQUE KEY uk_stations_city_name (city_name, station_name)
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS trains (
  train_id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  train_code VARCHAR(12) NOT NULL,
  train_name VARCHAR(80) NOT NULL,
  train_status ENUM('ACTIVE', 'DISABLED') NOT NULL DEFAULT 'ACTIVE',
  PRIMARY KEY (train_id),
  UNIQUE KEY uk_trains_code (train_code)
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS train_stops (
  train_id BIGINT UNSIGNED NOT NULL,
  station_id BIGINT UNSIGNED NOT NULL,
  stop_sequence SMALLINT UNSIGNED NOT NULL,
  arrival_time TIME NULL,
  departure_time TIME NULL,
  day_offset TINYINT UNSIGNED NOT NULL DEFAULT 0,
  PRIMARY KEY (train_id, station_id),
  UNIQUE KEY uk_train_stops_sequence (train_id, stop_sequence),
  CONSTRAINT fk_train_stops_train FOREIGN KEY (train_id) REFERENCES trains(train_id),
  CONSTRAINT fk_train_stops_station FOREIGN KEY (station_id) REFERENCES stations(station_id),
  CONSTRAINT ck_train_stops_sequence CHECK (stop_sequence > 0),
  CONSTRAINT ck_train_stops_times CHECK (arrival_time IS NOT NULL OR departure_time IS NOT NULL)
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS carriages (
  carriage_id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  train_id BIGINT UNSIGNED NOT NULL,
  carriage_no SMALLINT UNSIGNED NOT NULL,
  seat_type ENUM('SECOND_CLASS', 'FIRST_CLASS', 'BUSINESS') NOT NULL,
  PRIMARY KEY (carriage_id),
  UNIQUE KEY uk_carriages_train_no (train_id, carriage_no),
  CONSTRAINT fk_carriages_train FOREIGN KEY (train_id) REFERENCES trains(train_id),
  CONSTRAINT ck_carriages_no CHECK (carriage_no BETWEEN 1 AND 20)
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS train_seats (
  seat_id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  carriage_id BIGINT UNSIGNED NOT NULL,
  seat_no VARCHAR(8) NOT NULL,
  PRIMARY KEY (seat_id),
  UNIQUE KEY uk_train_seats_carriage_no (carriage_id, seat_no),
  CONSTRAINT fk_train_seats_carriage FOREIGN KEY (carriage_id) REFERENCES carriages(carriage_id)
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS train_schedules (
  schedule_id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  train_id BIGINT UNSIGNED NOT NULL,
  travel_date DATE NOT NULL,
  schedule_status ENUM('ON_SALE', 'CANCELED', 'CLOSED') NOT NULL DEFAULT 'ON_SALE',
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (schedule_id),
  UNIQUE KEY uk_schedules_train_date (train_id, travel_date),
  CONSTRAINT fk_schedules_train FOREIGN KEY (train_id) REFERENCES trains(train_id),
  CONSTRAINT ck_schedules_date CHECK (travel_date >= '2020-01-01')
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS schedule_seats (
  schedule_seat_id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  schedule_id BIGINT UNSIGNED NOT NULL,
  seat_id BIGINT UNSIGNED NOT NULL,
  seat_type ENUM('SECOND_CLASS', 'FIRST_CLASS', 'BUSINESS') NOT NULL,
  fare DECIMAL(10,2) NOT NULL,
  seat_status ENUM('AVAILABLE', 'SOLD', 'LOCKED') NOT NULL DEFAULT 'AVAILABLE',
  PRIMARY KEY (schedule_seat_id),
  UNIQUE KEY uk_schedule_seats_schedule_seat (schedule_id, seat_id),
  KEY idx_schedule_seats_search (schedule_id, seat_type, seat_status),
  CONSTRAINT fk_schedule_seats_schedule FOREIGN KEY (schedule_id) REFERENCES train_schedules(schedule_id),
  CONSTRAINT fk_schedule_seats_seat FOREIGN KEY (seat_id) REFERENCES train_seats(seat_id),
  CONSTRAINT ck_schedule_seats_fare CHECK (fare > 0)
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS orders (
  order_id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  order_no VARCHAR(32) NOT NULL,
  user_id BIGINT UNSIGNED NOT NULL,
  schedule_id BIGINT UNSIGNED NOT NULL,
  departure_station_id BIGINT UNSIGNED NOT NULL,
  arrival_station_id BIGINT UNSIGNED NOT NULL,
  order_status ENUM('PENDING', 'CONFIRMED', 'CANCELED') NOT NULL DEFAULT 'PENDING',
  total_amount DECIMAL(10,2) NOT NULL,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  canceled_at DATETIME NULL,
  PRIMARY KEY (order_id),
  UNIQUE KEY uk_orders_order_no (order_no),
  KEY idx_orders_user_created (user_id, created_at),
  KEY idx_orders_schedule_status (schedule_id, order_status),
  CONSTRAINT fk_orders_user FOREIGN KEY (user_id) REFERENCES app_users(user_id),
  CONSTRAINT fk_orders_schedule FOREIGN KEY (schedule_id) REFERENCES train_schedules(schedule_id),
  CONSTRAINT fk_orders_departure FOREIGN KEY (departure_station_id) REFERENCES stations(station_id),
  CONSTRAINT fk_orders_arrival FOREIGN KEY (arrival_station_id) REFERENCES stations(station_id),
  CONSTRAINT ck_orders_route CHECK (departure_station_id <> arrival_station_id),
  CONSTRAINT ck_orders_amount CHECK (total_amount > 0)
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS order_passengers (
  order_passenger_id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  order_id BIGINT UNSIGNED NOT NULL,
  schedule_seat_id BIGINT UNSIGNED NOT NULL,
  passenger_name VARCHAR(32) NOT NULL,
  passenger_id_number VARCHAR(18) NOT NULL,
  ticket_price DECIMAL(10,2) NOT NULL,
  PRIMARY KEY (order_passenger_id),
  UNIQUE KEY uk_order_passengers_schedule_seat (schedule_seat_id),
  KEY idx_order_passengers_order (order_id),
  CONSTRAINT fk_order_passengers_order FOREIGN KEY (order_id) REFERENCES orders(order_id),
  CONSTRAINT fk_order_passengers_schedule_seat FOREIGN KEY (schedule_seat_id) REFERENCES schedule_seats(schedule_seat_id),
  CONSTRAINT ck_order_passengers_price CHECK (ticket_price > 0)
) ENGINE=InnoDB;

DROP VIEW IF EXISTS v_train_schedule_search;
CREATE VIEW v_train_schedule_search AS
SELECT
  sch.schedule_id,
  sch.travel_date,
  sch.schedule_status,
  tr.train_id,
  tr.train_code,
  tr.train_name,
  origin.station_id AS departure_station_id,
  origin.station_name AS departure_station_name,
  origin.city_name AS departure_city_name,
  origin_stop.departure_time,
  origin_stop.day_offset AS departure_day_offset,
  destination.station_id AS arrival_station_id,
  destination.station_name AS arrival_station_name,
  destination.city_name AS arrival_city_name,
  destination_stop.arrival_time,
  destination_stop.day_offset AS arrival_day_offset,
  COUNT(CASE WHEN ss.seat_status = 'AVAILABLE' THEN 1 END) AS available_seats,
  MIN(CASE WHEN ss.seat_status = 'AVAILABLE' THEN ss.fare END) AS lowest_fare
FROM train_schedules sch
JOIN trains tr ON tr.train_id = sch.train_id
JOIN train_stops origin_stop ON origin_stop.train_id = tr.train_id
JOIN stations origin ON origin.station_id = origin_stop.station_id
JOIN train_stops destination_stop
  ON destination_stop.train_id = tr.train_id
 AND destination_stop.stop_sequence > origin_stop.stop_sequence
JOIN stations destination ON destination.station_id = destination_stop.station_id
LEFT JOIN schedule_seats ss ON ss.schedule_id = sch.schedule_id
WHERE sch.schedule_status = 'ON_SALE' AND tr.train_status = 'ACTIVE'
GROUP BY
  sch.schedule_id, sch.travel_date, sch.schedule_status,
  tr.train_id, tr.train_code, tr.train_name,
  origin.station_id, origin.station_name, origin.city_name,
  origin_stop.departure_time, origin_stop.day_offset, origin_stop.stop_sequence,
  destination.station_id, destination.station_name, destination.city_name,
  destination_stop.arrival_time, destination_stop.day_offset, destination_stop.stop_sequence;

DROP VIEW IF EXISTS v_daily_sales;
CREATE VIEW v_daily_sales AS
SELECT
  DATE(o.created_at) AS sales_date,
  tr.train_code,
  tr.train_name,
  COUNT(DISTINCT o.order_id) AS confirmed_orders,
  COUNT(op.order_passenger_id) AS sold_tickets,
  COALESCE(SUM(op.ticket_price), 0) AS sales_amount
FROM orders o
JOIN train_schedules sch ON sch.schedule_id = o.schedule_id
JOIN trains tr ON tr.train_id = sch.train_id
LEFT JOIN order_passengers op ON op.order_id = o.order_id
WHERE o.order_status = 'CONFIRMED'
GROUP BY DATE(o.created_at), tr.train_id, tr.train_code, tr.train_name;

DROP TRIGGER IF EXISTS trg_order_passengers_before_insert;
DELIMITER $$
CREATE TRIGGER trg_order_passengers_before_insert
BEFORE INSERT ON order_passengers
FOR EACH ROW
BEGIN
  DECLARE seat_state VARCHAR(12);
  SELECT seat_status INTO seat_state
  FROM schedule_seats
  WHERE schedule_seat_id = NEW.schedule_seat_id;

  IF seat_state IS NULL OR seat_state <> 'SOLD' THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = '座位未锁定，不能生成车票';
  END IF;
END$$
DELIMITER ;

DROP TRIGGER IF EXISTS trg_orders_before_update;
DELIMITER $$
CREATE TRIGGER trg_orders_before_update
BEFORE UPDATE ON orders
FOR EACH ROW
BEGIN
  IF OLD.order_status = 'CANCELED' AND NEW.order_status <> 'CANCELED' THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = '已取消订单不能恢复';
  END IF;
  IF NEW.order_status = 'CANCELED' AND OLD.order_status = 'CANCELED' THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = '订单已取消';
  END IF;
END$$
DELIMITER ;

DROP TRIGGER IF EXISTS trg_orders_after_update;
DELIMITER $$
CREATE TRIGGER trg_orders_after_update
AFTER UPDATE ON orders
FOR EACH ROW
BEGIN
  IF NEW.order_status = 'CANCELED' AND OLD.order_status <> 'CANCELED' THEN
    UPDATE schedule_seats ss
    JOIN order_passengers op ON op.schedule_seat_id = ss.schedule_seat_id
    SET ss.seat_status = 'AVAILABLE'
    WHERE op.order_id = NEW.order_id;
  END IF;
END$$
DELIMITER ;
