-- ============================================================
-- 04_locking_concurrency.sql
-- Locking, deadlocks, optimistic locking, monitoring
-- ============================================================
USE practice_db;

-- ── Setup: inventory table ────────────────────────────────────
CREATE TABLE IF NOT EXISTS inventory (
    product_id  INT PRIMARY KEY,
    name        VARCHAR(100) NOT NULL,
    stock       INT NOT NULL DEFAULT 0,
    version     INT NOT NULL DEFAULT 0,
    CHECK (stock >= 0)
);

INSERT INTO inventory VALUES
    (1, 'Laptop',  50, 0),
    (2, 'Mouse',  200, 0),
    (3, 'Webcam',  80, 0);

-- ── Pessimistic locking: reserve stock ───────────────────────
DELIMITER $$
CREATE PROCEDURE IF NOT EXISTS reserve_stock_pessimistic(
    IN p_product_id INT,
    IN p_qty        INT
)
BEGIN
    DECLARE v_stock INT;
    DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN ROLLBACK; RESIGNAL; END;

    START TRANSACTION;
        -- Lock the row before reading
        SELECT stock INTO v_stock FROM inventory
        WHERE product_id = p_product_id FOR UPDATE;

        IF v_stock < p_qty THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Insufficient stock';
        END IF;

        UPDATE inventory SET stock = stock - p_qty WHERE product_id = p_product_id;
    COMMIT;
    SELECT ROW_COUNT() AS rows_updated;
END$$

-- ── Optimistic locking: reserve stock ────────────────────────
CREATE PROCEDURE IF NOT EXISTS reserve_stock_optimistic(
    IN p_product_id INT,
    IN p_qty        INT,
    IN p_version    INT
)
BEGIN
    DECLARE v_affected INT;

    UPDATE inventory
    SET stock = stock - p_qty, version = version + 1
    WHERE product_id = p_product_id
      AND version = p_version
      AND stock >= p_qty;

    SET v_affected = ROW_COUNT();

    IF v_affected = 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Conflict or insufficient stock — retry';
    END IF;
END$$

DELIMITER ;

-- Test pessimistic
CALL reserve_stock_pessimistic(1, 5);
SELECT * FROM inventory WHERE product_id = 1;

-- Test optimistic (read version first, then update)
SELECT stock, version FROM inventory WHERE product_id = 2;
CALL reserve_stock_optimistic(2, 10, 0);  -- version=0 from above read
SELECT * FROM inventory WHERE product_id = 2;

-- ── Simulate deadlock scenario ────────────────────────────────
-- Run these in two separate sessions simultaneously:

-- Session 1:
-- START TRANSACTION;
-- UPDATE inventory SET stock = stock - 1 WHERE product_id = 1;  -- locks product 1
-- SELECT SLEEP(2);
-- UPDATE inventory SET stock = stock - 1 WHERE product_id = 2;  -- waits for product 2

-- Session 2:
-- START TRANSACTION;
-- UPDATE inventory SET stock = stock - 1 WHERE product_id = 2;  -- locks product 2
-- UPDATE inventory SET stock = stock - 1 WHERE product_id = 1;  -- waits for product 1 → DEADLOCK

-- InnoDB detects and rolls back one transaction
-- Check: SHOW ENGINE INNODB STATUS\G

-- ── Deadlock prevention: consistent lock order ────────────────
-- Always lock in ascending product_id order to prevent deadlock
DELIMITER $$
CREATE PROCEDURE IF NOT EXISTS reserve_multi_stock(
    IN p_product1 INT, IN p_qty1 INT,
    IN p_product2 INT, IN p_qty2 INT
)
BEGIN
    DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN ROLLBACK; RESIGNAL; END;
    START TRANSACTION;
        -- Lock in consistent order (lower ID first)
        IF p_product1 < p_product2 THEN
            SELECT stock FROM inventory WHERE product_id = p_product1 FOR UPDATE;
            SELECT stock FROM inventory WHERE product_id = p_product2 FOR UPDATE;
        ELSE
            SELECT stock FROM inventory WHERE product_id = p_product2 FOR UPDATE;
            SELECT stock FROM inventory WHERE product_id = p_product1 FOR UPDATE;
        END IF;

        UPDATE inventory SET stock = stock - p_qty1 WHERE product_id = p_product1;
        UPDATE inventory SET stock = stock - p_qty2 WHERE product_id = p_product2;
    COMMIT;
END$$
DELIMITER ;

-- ── Lock monitoring ───────────────────────────────────────────
-- Active transactions
SELECT trx_id, trx_state, trx_started, trx_query
FROM information_schema.INNODB_TRX;

-- Current data locks (MySQL 8.0+)
SELECT ENGINE_LOCK_ID, OBJECT_NAME, LOCK_TYPE, LOCK_MODE, LOCK_STATUS
FROM performance_schema.data_locks;

-- Lock waits
SELECT * FROM performance_schema.data_lock_waits;

-- ── Isolation level effects ───────────────────────────────────
-- Check current level
SELECT @@transaction_isolation;

-- READ COMMITTED: no gap locks, phantom reads possible
SET SESSION TRANSACTION ISOLATION LEVEL READ COMMITTED;
START TRANSACTION;
    SELECT * FROM inventory WHERE stock > 10 FOR UPDATE;
    -- Only record locks, no gap locks
ROLLBACK;

-- REPEATABLE READ: gap locks prevent phantoms
SET SESSION TRANSACTION ISOLATION LEVEL REPEATABLE READ;
START TRANSACTION;
    SELECT * FROM inventory WHERE stock > 10 FOR UPDATE;
    -- Record + gap locks
ROLLBACK;

-- ── SKIP LOCKED / NOWAIT (MySQL 8.0+) ────────────────────────
-- Skip locked rows (useful for job queues)
START TRANSACTION;
    SELECT * FROM inventory WHERE stock > 0 LIMIT 1 FOR UPDATE SKIP LOCKED;
    -- Returns first unlocked row — great for concurrent workers
ROLLBACK;

-- Fail immediately if locked (instead of waiting)
START TRANSACTION;
    SELECT * FROM inventory WHERE product_id = 1 FOR UPDATE NOWAIT;
ROLLBACK;
