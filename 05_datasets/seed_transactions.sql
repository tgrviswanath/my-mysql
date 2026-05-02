-- ============================================================
-- datasets/seed_transactions.sql + seed_logs.sql
-- Financial transactions and application logs
-- ============================================================
USE practice_db;

-- ── Transactions (100,000 rows) ───────────────────────────────
CREATE TABLE IF NOT EXISTS financial_transactions (
    txn_id      BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    user_id     BIGINT UNSIGNED NOT NULL,
    type        ENUM('purchase','refund','transfer','withdrawal','deposit') NOT NULL,
    amount      DECIMAL(15,2) NOT NULL,
    currency    CHAR(3) NOT NULL DEFAULT 'USD',
    status      ENUM('pending','completed','failed','reversed') NOT NULL DEFAULT 'completed',
    created_at  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_user_created (user_id, created_at),
    INDEX idx_type_status (type, status),
    INDEX idx_created_at (created_at)
) PARTITION BY RANGE (YEAR(created_at)) (
    PARTITION p2023 VALUES LESS THAN (2024),
    PARTITION p2024 VALUES LESS THAN (2025),
    PARTITION p_future VALUES LESS THAN MAXVALUE
);

INSERT INTO financial_transactions (user_id, type, amount, currency, status, created_at)
SELECT
    1 + FLOOR(RAND() * 1000) AS user_id,
    ELT(1+FLOOR(RAND()*5), 'purchase','refund','transfer','withdrawal','deposit') AS type,
    ROUND(1 + RAND() * 9999, 2) AS amount,
    ELT(1+FLOOR(RAND()*3), 'USD','EUR','GBP') AS currency,
    ELT(1+FLOOR(RAND()*4), 'pending','completed','failed','reversed') AS status,
    DATE_SUB(NOW(), INTERVAL FLOOR(RAND()*365) DAY) AS created_at
FROM (
    WITH RECURSIVE nums AS (SELECT 1 AS n UNION ALL SELECT n+1 FROM nums WHERE n < 100000)
    SELECT n FROM nums
) AS seq;

-- ── Application logs (500,000 rows) ──────────────────────────
CREATE TABLE IF NOT EXISTS app_logs (
    log_id      BIGINT UNSIGNED AUTO_INCREMENT,
    level       ENUM('DEBUG','INFO','WARN','ERROR','FATAL') NOT NULL,
    service     VARCHAR(50) NOT NULL,
    message     VARCHAR(500) NOT NULL,
    user_id     BIGINT UNSIGNED,
    request_id  VARCHAR(36),
    duration_ms INT,
    created_at  DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    PRIMARY KEY (log_id, created_at)
) PARTITION BY RANGE (TO_DAYS(created_at)) (
    PARTITION p_old    VALUES LESS THAN (TO_DAYS('2024-01-01')),
    PARTITION p_2024_q1 VALUES LESS THAN (TO_DAYS('2024-04-01')),
    PARTITION p_2024_q2 VALUES LESS THAN (TO_DAYS('2024-07-01')),
    PARTITION p_future  VALUES LESS THAN MAXVALUE
);

INSERT INTO app_logs (level, service, message, user_id, duration_ms, created_at)
SELECT
    ELT(1+FLOOR(RAND()*5), 'DEBUG','INFO','INFO','WARN','ERROR') AS level,
    ELT(1+FLOOR(RAND()*4), 'api','auth','payment','notification') AS service,
    ELT(1+FLOOR(RAND()*5),
        'Request processed successfully',
        'User authenticated',
        'Cache miss — fetching from DB',
        'Slow query detected',
        'Connection timeout') AS message,
    CASE WHEN RAND() > 0.2 THEN FLOOR(RAND()*10000) ELSE NULL END AS user_id,
    FLOOR(1 + RAND() * 5000) AS duration_ms,
    DATE_SUB(NOW(), INTERVAL FLOOR(RAND()*180) DAY) AS created_at
FROM (
    WITH RECURSIVE nums AS (SELECT 1 AS n UNION ALL SELECT n+1 FROM nums WHERE n < 500000)
    SELECT n FROM nums
) AS seq;

-- ── Verification ──────────────────────────────────────────────
SELECT COUNT(*) AS total_transactions FROM financial_transactions;
SELECT COUNT(*) AS total_logs FROM app_logs;

-- Log level distribution
SELECT level, COUNT(*) AS cnt, ROUND(COUNT(*)*100.0/(SELECT COUNT(*) FROM app_logs),2) AS pct
FROM app_logs GROUP BY level ORDER BY cnt DESC;

-- Slow requests (> 2 seconds)
SELECT service, COUNT(*) AS slow_count, AVG(duration_ms) AS avg_ms
FROM app_logs WHERE duration_ms > 2000
GROUP BY service ORDER BY slow_count DESC;
