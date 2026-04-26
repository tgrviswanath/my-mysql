-- ============================================================
-- 03_indexes_basics.sql
-- Index creation, EXPLAIN analysis, index usage patterns
-- ============================================================
USE practice_db;

-- ── Setup: large-ish table for index demos ────────────────────
CREATE TABLE IF NOT EXISTS users (
    user_id    INT AUTO_INCREMENT PRIMARY KEY,
    email      VARCHAR(100) NOT NULL,
    username   VARCHAR(50)  NOT NULL,
    status     ENUM('active','inactive','banned') NOT NULL DEFAULT 'active',
    country    CHAR(2)      NOT NULL DEFAULT 'US',
    created_at DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    last_login DATETIME
);

-- Seed 1000 rows for realistic EXPLAIN output
INSERT INTO users (email, username, status, country, created_at)
SELECT
    CONCAT('user', seq, '@example.com'),
    CONCAT('user_', seq),
    ELT(1 + FLOOR(RAND() * 3), 'active', 'inactive', 'banned'),
    ELT(1 + FLOOR(RAND() * 4), 'US', 'UK', 'CA', 'AU'),
    DATE_SUB(NOW(), INTERVAL FLOOR(RAND() * 365) DAY)
FROM (
    WITH RECURSIVE s AS (SELECT 1 AS seq UNION ALL SELECT seq+1 FROM s WHERE seq < 1000)
    SELECT seq FROM s
) AS nums;

-- ── EXPLAIN before indexes ────────────────────────────────────
EXPLAIN SELECT * FROM users WHERE email = 'user100@example.com';
-- type=ALL → full table scan (bad)

EXPLAIN SELECT * FROM users WHERE status = 'active';
-- type=ALL → full table scan

-- ── Create indexes ────────────────────────────────────────────
-- Unique index on email
ALTER TABLE users ADD UNIQUE INDEX idx_email (email);

-- Regular index on status (low cardinality — for demo)
ALTER TABLE users ADD INDEX idx_status (status);

-- Composite index on (country, status)
ALTER TABLE users ADD INDEX idx_country_status (country, status);

-- Index on created_at for range queries
ALTER TABLE users ADD INDEX idx_created_at (created_at);

-- ── EXPLAIN after indexes ─────────────────────────────────────
EXPLAIN SELECT * FROM users WHERE email = 'user100@example.com';
-- type=const → single row lookup via unique index ✅

EXPLAIN SELECT * FROM users WHERE status = 'active';
-- type=ref → index lookup, but may still scan many rows

EXPLAIN SELECT * FROM users WHERE country = 'US' AND status = 'active';
-- type=ref → uses composite index idx_country_status ✅

-- ── Index usage patterns ──────────────────────────────────────
-- Leftmost prefix rule: composite index (country, status)
EXPLAIN SELECT * FROM users WHERE country = 'US';           -- ✅ uses index
EXPLAIN SELECT * FROM users WHERE status = 'active';        -- ❌ can't use (not leftmost)
EXPLAIN SELECT * FROM users WHERE country = 'US' AND status = 'active'; -- ✅ full index

-- Range query on indexed column
EXPLAIN SELECT * FROM users
WHERE created_at BETWEEN '2024-01-01' AND '2024-06-30';
-- type=range → uses idx_created_at ✅

-- ── Cases where index is NOT used ────────────────────────────
-- Function on indexed column
EXPLAIN SELECT * FROM users WHERE YEAR(created_at) = 2024;
-- type=ALL → can't use index ❌

-- Fix: use range instead
EXPLAIN SELECT * FROM users
WHERE created_at >= '2024-01-01' AND created_at < '2025-01-01';
-- type=range ✅

-- Leading wildcard
EXPLAIN SELECT * FROM users WHERE email LIKE '%@example.com';
-- type=ALL ❌

-- Prefix match works:
EXPLAIN SELECT * FROM users WHERE email LIKE 'user1%';
-- type=range ✅

-- ── Covering index demo ───────────────────────────────────────
-- Add covering index for a common query
ALTER TABLE users ADD INDEX idx_covering_status_country (status, country, user_id, email);

EXPLAIN SELECT user_id, email FROM users WHERE status = 'active' AND country = 'US';
-- Extra: "Using index" → covered by index, no table access ✅

-- ── Check index statistics ────────────────────────────────────
SHOW INDEX FROM users;

SELECT INDEX_NAME, COLUMN_NAME, CARDINALITY, NON_UNIQUE
FROM information_schema.STATISTICS
WHERE TABLE_SCHEMA = 'practice_db' AND TABLE_NAME = 'users'
ORDER BY INDEX_NAME, SEQ_IN_INDEX;

-- ── Update statistics ─────────────────────────────────────────
ANALYZE TABLE users;

-- ── Find unused indexes (after workload) ─────────────────────
SELECT object_schema, object_name, index_name, count_star
FROM performance_schema.table_io_waits_summary_by_index_usage
WHERE object_schema = 'practice_db'
  AND index_name IS NOT NULL
  AND count_star = 0
ORDER BY object_name, index_name;

-- ── Drop an index ─────────────────────────────────────────────
-- ALTER TABLE users DROP INDEX idx_status;
