-- ============================================================
-- 02_execution_plans.sql
-- Reading EXPLAIN output, identifying bottlenecks, fixing them
-- ============================================================
USE practice_db;

-- ════════════════════════════════════════════════════════════
-- EXPLAIN OUTPUT REFERENCE
-- ════════════════════════════════════════════════════════════
-- type column (best → worst):
--   system → const → eq_ref → ref → range → index → ALL
--
-- Extra column (watch for):
--   "Using index"        → covering index ✅
--   "Using where"        → filter after index
--   "Using filesort"     → sort not from index ⚠️
--   "Using temporary"    → temp table ⚠️
--   "Using join buffer"  → BNL join, no index ⚠️

-- ── type=const: PK or unique index with constant ──────────────
EXPLAIN SELECT * FROM users WHERE user_id = 1;
-- type=const, rows=1 ✅

-- ── type=eq_ref: unique index join ───────────────────────────
EXPLAIN SELECT e.name, d.name FROM emp e JOIN dept d ON e.dept_id = d.dept_id;
-- dept: type=eq_ref (PK lookup per emp row) ✅

-- ── type=ref: non-unique index ────────────────────────────────
EXPLAIN SELECT * FROM users WHERE status = 'active';
-- type=ref (multiple rows match) ✅

-- ── type=range: index range scan ─────────────────────────────
EXPLAIN SELECT * FROM users WHERE created_at > '2024-01-01';
-- type=range ✅

-- ── type=ALL: full table scan ─────────────────────────────────
EXPLAIN SELECT * FROM users WHERE username LIKE '%admin%';
-- type=ALL ❌ — leading wildcard prevents index use

-- ── Using filesort ────────────────────────────────────────────
EXPLAIN SELECT * FROM users ORDER BY username DESC LIMIT 10;
-- Extra: Using filesort ⚠️ (no index on username)

-- Fix: add index
ALTER TABLE users ADD INDEX idx_username (username);
EXPLAIN SELECT * FROM users ORDER BY username DESC LIMIT 10;
-- Extra: Using index ✅

-- ── Using temporary ───────────────────────────────────────────
EXPLAIN SELECT status, COUNT(*) FROM users GROUP BY status ORDER BY COUNT(*) DESC;
-- May show: Using temporary; Using filesort

-- Fix: add covering index for GROUP BY
ALTER TABLE users ADD INDEX idx_status_cover (status, user_id);
EXPLAIN SELECT status, COUNT(*) FROM users GROUP BY status;
-- Extra: Using index ✅

-- ── Using join buffer (BNL) ───────────────────────────────────
-- Create a table without index for demo
CREATE TABLE IF NOT EXISTS no_index_table (id INT, val VARCHAR(50));
INSERT INTO no_index_table SELECT user_id, email FROM users LIMIT 100;

EXPLAIN SELECT u.email, n.val FROM users u JOIN no_index_table n ON u.email = n.val;
-- Extra: Using join buffer (Block Nested Loop) ⚠️

-- Fix: add index on join column
ALTER TABLE no_index_table ADD INDEX idx_val (val);
EXPLAIN SELECT u.email, n.val FROM users u JOIN no_index_table n ON u.email = n.val;
-- type=ref ✅

-- ── key_len interpretation ────────────────────────────────────
-- key_len tells you how many bytes of the index are used
-- For composite index (status ENUM=1byte, country CHAR(2)=8bytes utf8mb4):
EXPLAIN SELECT * FROM users WHERE status = 'active' AND country = 'US';
-- key_len = 9 → both columns used

EXPLAIN SELECT * FROM users WHERE status = 'active';
-- key_len = 1 → only status used (leftmost prefix)

-- ── rows × filtered = actual rows examined ───────────────────
EXPLAIN SELECT * FROM users WHERE status = 'active' AND username LIKE 'user1%';
-- rows=N, filtered=X% → actual rows ≈ N × X/100

-- ── EXPLAIN FORMAT=TREE (MySQL 8.0+) ─────────────────────────
EXPLAIN FORMAT=TREE
SELECT u.email, COUNT(o.order_id) AS order_count
FROM users u
LEFT JOIN orders o ON u.user_id = o.customer_id
WHERE u.status = 'active'
GROUP BY u.user_id, u.email
ORDER BY order_count DESC
LIMIT 10;

-- ── EXPLAIN ANALYZE (executes query, shows actual vs estimated) ─
EXPLAIN ANALYZE
SELECT u.email, COUNT(o.order_id) AS order_count
FROM users u
LEFT JOIN orders o ON u.user_id = o.customer_id
WHERE u.status = 'active'
GROUP BY u.user_id, u.email
ORDER BY order_count DESC
LIMIT 10;
-- Look for: actual time=X..Y rows=N loops=N
-- Compare actual rows vs estimated rows — large discrepancy = stale statistics

-- ── Fix stale statistics ──────────────────────────────────────
ANALYZE TABLE users, orders;
-- Re-run EXPLAIN ANALYZE to see improved estimates
