USE train_ticket_db;

DROP PROCEDURE IF EXISTS sp_create_order;
DELIMITER $$
CREATE PROCEDURE sp_create_order(
  IN p_user_id BIGINT UNSIGNED,
  IN p_schedule_id BIGINT UNSIGNED,
  IN p_departure_station_id BIGINT UNSIGNED,
  IN p_arrival_station_id BIGINT UNSIGNED,
  IN p_seat_type VARCHAR(20),
  IN p_passenger_name VARCHAR(32),
  IN p_passenger_id_number VARCHAR(18)
)
BEGIN
  DECLARE v_schedule_seat_id BIGINT UNSIGNED;
  DECLARE v_fare DECIMAL(10,2);
  DECLARE v_order_id BIGINT UNSIGNED;
  DECLARE v_order_no VARCHAR(32);
  DECLARE v_route_count INT DEFAULT 0;

  DECLARE EXIT HANDLER FOR SQLEXCEPTION
  BEGIN
    ROLLBACK;
    RESIGNAL;
  END;

  START TRANSACTION;

  SELECT COUNT(*) INTO v_route_count
  FROM v_train_schedule_search
  WHERE schedule_id = p_schedule_id
    AND departure_station_id = p_departure_station_id
    AND arrival_station_id = p_arrival_station_id;

  IF v_route_count = 0 THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = '车次不存在、已停售或区间无效';
  END IF;

  SELECT schedule_seat_id, fare
  INTO v_schedule_seat_id, v_fare
  FROM schedule_seats
  WHERE schedule_id = p_schedule_id
    AND seat_type = p_seat_type
    AND seat_status = 'AVAILABLE'
  ORDER BY schedule_seat_id
  LIMIT 1
  FOR UPDATE;

  IF v_schedule_seat_id IS NULL THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = '该席别余票不足';
  END IF;

  SET v_order_no = CONCAT('TT', DATE_FORMAT(NOW(), '%Y%m%d%H%i%s'), LPAD(FLOOR(RAND() * 1000), 3, '0'));
  INSERT INTO orders (
    order_no, user_id, schedule_id, departure_station_id, arrival_station_id, order_status, total_amount
  ) VALUES (
    v_order_no, p_user_id, p_schedule_id, p_departure_station_id, p_arrival_station_id, 'CONFIRMED', v_fare
  );
  SET v_order_id = LAST_INSERT_ID();

  UPDATE schedule_seats
  SET seat_status = 'SOLD'
  WHERE schedule_seat_id = v_schedule_seat_id AND seat_status = 'AVAILABLE';

  IF ROW_COUNT() <> 1 THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = '座位状态已变化，请重新查询';
  END IF;

  INSERT INTO order_passengers (
    order_id, schedule_seat_id, passenger_name, passenger_id_number, ticket_price, seat_lease_key
  ) VALUES (
    v_order_id, v_schedule_seat_id, p_passenger_name, p_passenger_id_number, v_fare, v_schedule_seat_id
  );

  COMMIT;
  SELECT v_order_id AS order_id, v_order_no AS order_no;
END$$
DELIMITER ;

DROP PROCEDURE IF EXISTS sp_cancel_order;
DELIMITER $$
CREATE PROCEDURE sp_cancel_order(
  IN p_order_id BIGINT UNSIGNED,
  IN p_user_id BIGINT UNSIGNED
)
BEGIN
  DECLARE v_order_status VARCHAR(12);
  DECLARE EXIT HANDLER FOR SQLEXCEPTION
  BEGIN
    ROLLBACK;
    RESIGNAL;
  END;

  START TRANSACTION;
  SELECT order_status INTO v_order_status
  FROM orders
  WHERE order_id = p_order_id AND user_id = p_user_id
  FOR UPDATE;

  IF v_order_status IS NULL THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = '订单不存在或无权取消';
  END IF;
  IF v_order_status = 'CANCELED' THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = '订单已取消';
  END IF;

  UPDATE orders
  SET order_status = 'CANCELED', canceled_at = NOW()
  WHERE order_id = p_order_id;
  COMMIT;
END$$
DELIMITER ;
