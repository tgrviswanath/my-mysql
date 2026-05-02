-- ============================================================
-- 03_indexing_deep_dive.sql
-- Composite, covering, prefix, functional indexes + ICP
-- ============================================================
USE practice_db;

-- ── Setup: orders table for index experiments ─────────────────
CREATE TABLE IF NOT EXISTS orders (
    order_id    INT AUTO_INCREMENT PRIMARY KEY,
    customer_id INT NOT NULL,
    status      ENUM('pending','paid','shipped','cancelled') NOT NULL DEFAULT 'pending',
    amount      DECIMAL(10,2) NOT NULL,
    created_at  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    INDEX fk_customer (customer_id)
);

-- Seed 5000 orders
INSERT INTO orders (customer_id, status, amount, created_at)
SELECT
    1 + FLOOR(RAND() * 100),
    ELT(1 + FLOOR(RAND() * 4), 'pending','paid','shipped','cancelled'),
    ROUND(10 + RAND() * 990, 2),
    DATE_SUB(NOW(), INTERVAL FLOOR(RAND() * 730) DAY)
FROM (
    WITH RECURSIVE s AS (SELECT 1 AS n UNION ALL SELECT n+1 FROM s WHERE n < 5000)
    SELECT n FROM s
) AS nums;

-- ── Composite index: equality + range ────────────────────────
-- Query pattern: filter by customer + status, range on date
EXPLAIN SELECT order_id, amount, created_at
FROM orders
WHERE customer_id = 42 AND status = 'paid' AND created_at > '2024-01-01';

-- Add composite index (equality cols first, range col last)
ALTER TABLE orders ADD INDEX idx_cust_status_date (customer_id, status, created_at);

EXPLAIN SELECT order_id, amount, created_at
FROM orders
WHERE customer_id = 42 AND status = 'paid' AND created_at > '2024-01-01';
-- type=range, key=idx_cust_status_date ✅

-- ── Leftmost prefix rule demo ─────────────────────────────────
EXPLAIN SELECT * FROM orders WHERE customer_id = 42;                    -- ✅ uses index
EXPLAIN SELECT * FROM orders WHERE customer_id = 42 AND status = 'paid'; -- ✅ uses index
EXPLAIN SELECT * FROM orders WHERE status = 'paid';                     -- ❌ no leftmost
EXPLAIN SELECT * FROM orders WHERE created_at > '2024-01-01';           -- ❌ no leftmost

-- ── Covering index ────────────────────────────────────────────
-- Query: dashboard — count paid orders per customer
EXPLAIN SELECT customer_id, COUNT(*) AS paid_count
FROM orders
WHERE status = 'paid'
GROUP BY customer_id;

-- Add covering index
ALTER TABLE orders ADD INDEX idx_cover_status_cust (status, customer_id);

EXPLAIN SELECT customer_id, COUNT(*) AS paid_count
FROM orders WHERE status = 'paid' GROUP BY customer_id;
-- Extra: "Using index" ✅

-- ── Covering index with ORDER BY ─────────────────────────────
ALTER TABLE orders ADD INDEX idx_cover_full (customer_id, status, created_at, order_id, amount);

EXPLAIN SELECT order_id, amount FROM orders
WHERE customer_id = 42 AND status = 'paid'
ORDER BY created_at DESC
LIMIT 10;
-- Extra: "Using index" — no filesort, no table access ✅

-- ── Prefix index ─────────────────────────────────────────────
-- Find optimal prefix length for email
SELECT
    COUNT(DISTINCT LEFT(email, 5))  / COUNT(*) AS sel_5,
    COUNT(DISTINCT LEFT(email, 10)) / COUNT(*) AS sel_10,
    COUNT(DISTINCT LEFT(email, 20)) / COUNT(*) AS sel_20,
    COUNT(DISTINCT email)           / COUNT(*) AS sel_full
FROM users;

ALTER TABLE users ADD INDEX idx_email_prefix (email(15));
EXPLAIN SELECT * FROM users WHERE email = 'user100@example.com';
-- Uses prefix index but may need to verify full value (not covering)

-- ── Functional index (MySQL 8.0.13+) ─────────────────────────
ALTER TABLE users ADD INDEX idx_email_lower ((LOWER(email)));
EXPLAIN SELECT * FROM users WHERE LOWER(email) = 'user100@example.com';
-- Uses functional index ✅

-- ── Invisible index (MySQL 8.0+) ─────────────────────────────
ALTER TABLE users ALTER INDEX idx_status INVISIBLE;
EXPLAIN SELECT * FROM users WHERE status = 'active';
-- Optimizer ignores idx_status — may use different plan or full scan

ALTER TABLE users ALTER INDEX idx_status VISIBLE;  -- restore

-- ── Index Condition Pushdown (ICP) ───────────────────────────
EXPLAIN SELECT * FROM users WHERE status = 'active' AND username LIKE 'user1%';
-- Extra: "Using index condition" → ICP pushes LIKE filter to index level

-- ── Index merge ───────────────────────────────────────────────
EXPLAIN SELECT * FROM users WHERE status = 'active' OR country = 'UK';
-- May show type=index_merge if both columns are indexed separately

-- ── Fragmentation check & rebuild ────────────────────────────
SELECT TABLE_NAME,
       ROUND(DATA_LENGTH/1024/1024, 2)  AS data_mb,
       ROUND(INDEX_LENGTH/1024/1024, 2) AS index_mb,
       ROUND(DATA_FREE/1024/1024, 2)    AS free_mb
FROM information_schema.TABLES
WHERE TABLE_SCHEMA = 'practice_db'
ORDER BY data_mb DESC;

-- Rebuild to defragment (locks table in older MySQL)
-- OPTIMIZE TABLE orders;
-- ALTER TABLE orders ENGINE=InnoDB;  -- online in MySQL 5.6+ with InnoDB

-- ── Show all indexes on a table ───────────────────────────────
SHOW INDEX FROM orders;
SHOW INDEX FROM users;
