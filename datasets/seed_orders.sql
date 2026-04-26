-- ============================================================
-- datasets/seed_orders.sql
-- Realistic orders dataset (50,000 rows)
-- ============================================================
USE practice_db;

-- Seed orders (requires users table to be populated)
INSERT INTO orders (customer_id, status, amount, created_at)
SELECT
    1 + FLOOR(RAND() * (SELECT COUNT(*) FROM users)) AS customer_id,
    ELT(1+FLOOR(RAND()*7),
        'pending','confirmed','processing','shipped','delivered','cancelled','refunded') AS status,
    ROUND(5 + RAND() * 2995, 2) AS amount,
    DATE_SUB(NOW(), INTERVAL FLOOR(RAND()*365) DAY) AS created_at
FROM (
    WITH RECURSIVE nums AS (SELECT 1 AS n UNION ALL SELECT n+1 FROM nums WHERE n < 50000)
    SELECT n FROM nums
) AS seq;

SELECT COUNT(*) AS total_orders FROM orders;
SELECT status, COUNT(*) AS cnt, ROUND(AVG(amount),2) AS avg_amount
FROM orders GROUP BY status ORDER BY cnt DESC;
