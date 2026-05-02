-- ============================================================
-- 01_query_optimization.sql
-- EXPLAIN analysis, query rewrites, optimization patterns
-- ============================================================
USE practice_db;

-- ── EXPLAIN basics ────────────────────────────────────────────
EXPLAIN SELECT * FROM users WHERE email = 'user100@example.com';
EXPLAIN SELECT * FROM users WHERE status = 'active' ORDER BY created_at DESC;
EXPLAIN SELECT * FROM users WHERE country = 'US' AND status = 'active';

-- ── EXPLAIN FORMAT=JSON (more detail) ────────────────────────
EXPLAIN FORMAT=JSON
SELECT u.user_id, u.email
FROM users u
WHERE u.status = 'active' AND u.country = 'US'
ORDER BY u.created_at DESC
LIMIT 10;

-- ── EXPLAIN ANALYZE (MySQL 8.0.18+) ──────────────────────────
EXPLAIN ANALYZE
SELECT u.user_id, u.email, u.country
FROM users u
WHERE u.status = 'active'
ORDER BY u.created_at DESC
LIMIT 20;

-- ── Optimization 1: Avoid function on indexed column ─────────
-- Bad (full scan):
EXPLAIN SELECT * FROM users WHERE YEAR(created_at) = 2024;

-- Good (range scan):
EXPLAIN SELECT * FROM users
WHERE created_at >= '2024-01-01' AND created_at < '2025-01-01';

-- ── Optimization 2: Covering index ───────────────────────────
-- Query: get user_id + email for active US users
-- Without covering index:
EXPLAIN SELECT user_id, email FROM users WHERE status = 'active' AND country = 'US';

-- Add covering index
ALTER TABLE users ADD INDEX IF NOT EXISTS idx_cov_status_country_id_email
    (status, country, user_id, email);

-- Now check Extra = "Using index"
EXPLAIN SELECT user_id, email FROM users WHERE status = 'active' AND country = 'US';

-- ── Optimization 3: Rewrite correlated subquery as JOIN ───────
-- Bad: correlated subquery (executes once per emp row)
EXPLAIN SELECT name, salary FROM emp e
WHERE salary = (SELECT MAX(salary) FROM emp WHERE dept_id = e.dept_id);

-- Good: JOIN with derived table
EXPLAIN SELECT e.name, e.salary
FROM emp e
JOIN (SELECT dept_id, MAX(salary) AS max_sal FROM emp GROUP BY dept_id) AS ms
ON e.dept_id = ms.dept_id AND e.salary = ms.max_sal;

-- ── Optimization 4: Pagination ────────────────────────────────
-- Bad: OFFSET pagination (gets slower as offset grows)
EXPLAIN SELECT user_id, email FROM users ORDER BY user_id LIMIT 10 OFFSET 500;

-- Good: keyset pagination
EXPLAIN SELECT user_id, email FROM users WHERE user_id > 500 ORDER BY user_id LIMIT 10;

-- ── Optimization 5: COUNT patterns ───────────────────────────
-- COUNT(*) vs COUNT(col) — different semantics
SELECT COUNT(*)       AS total_rows    FROM users;
SELECT COUNT(status)  AS non_null_status FROM users;  -- same if NOT NULL
SELECT COUNT(last_login) AS logged_in_count FROM users;  -- only non-NULL

-- Fast count approximation (for huge tables):
SELECT TABLE_ROWS FROM information_schema.TABLES
WHERE TABLE_SCHEMA = 'practice_db' AND TABLE_NAME = 'users';

-- ── Optimization 6: OR → UNION rewrite ───────────────────────
-- Bad: OR may not use indexes efficiently
EXPLAIN SELECT * FROM users WHERE status = 'active' OR country = 'UK';

-- Better: UNION (each branch can use its own index)
EXPLAIN
SELECT * FROM users WHERE status = 'active'
UNION
SELECT * FROM users WHERE country = 'UK' AND status != 'active';

-- ── Optimization 7: IN vs EXISTS for large sets ───────────────
-- IN: materializes subquery
EXPLAIN SELECT name FROM emp
WHERE dept_id IN (SELECT dept_id FROM dept WHERE location = 'NYC');

-- EXISTS: short-circuits
EXPLAIN SELECT name FROM emp e
WHERE EXISTS (SELECT 1 FROM dept d WHERE d.dept_id = e.dept_id AND d.location = 'NYC');

-- ── Optimizer hints (MySQL 8.0+) ──────────────────────────────
-- Force specific index
EXPLAIN SELECT /*+ INDEX(users idx_email) */ * FROM users WHERE email LIKE 'user1%';

-- Ignore an index
EXPLAIN SELECT /*+ NO_INDEX(users idx_status) */ * FROM users WHERE status = 'active';

-- ── Histograms (MySQL 8.0+) ───────────────────────────────────
ANALYZE TABLE users UPDATE HISTOGRAM ON status, country WITH 50 BUCKETS;

SELECT COLUMN_NAME, JSON_PRETTY(HISTOGRAM) AS histogram_data
FROM information_schema.COLUMN_STATISTICS
WHERE TABLE_SCHEMA = 'practice_db' AND TABLE_NAME = 'users';

-- ── Slow query simulation & analysis ─────────────────────────
-- Enable slow query log (requires SUPER privilege)
-- SET GLOBAL slow_query_log = 'ON';
-- SET GLOBAL long_query_time = 0.1;  -- log queries > 100ms
-- SET GLOBAL slow_query_log_file = '/var/log/mysql/slow.log';

-- Check slow query count
SHOW GLOBAL STATUS LIKE 'Slow_queries';
