-- ============================================================
-- utils/common_snippets.sql
-- Reusable SQL patterns for daily use
-- ============================================================

-- ════════════════════════════════════════════════════════════
-- SCHEMA INSPECTION
-- ════════════════════════════════════════════════════════════

-- List all tables with row counts and sizes
SELECT
    TABLE_NAME,
    TABLE_ROWS,
    ROUND(DATA_LENGTH/1024/1024, 2)  AS data_mb,
    ROUND(INDEX_LENGTH/1024/1024, 2) AS index_mb,
    ENGINE
FROM information_schema.TABLES
WHERE TABLE_SCHEMA = DATABASE()
ORDER BY DATA_LENGTH + INDEX_LENGTH DESC;

-- List all indexes on all tables
SELECT TABLE_NAME, INDEX_NAME, COLUMN_NAME, NON_UNIQUE, CARDINALITY
FROM information_schema.STATISTICS
WHERE TABLE_SCHEMA = DATABASE()
ORDER BY TABLE_NAME, INDEX_NAME, SEQ_IN_INDEX;

-- Find tables without a PRIMARY KEY
SELECT TABLE_NAME FROM information_schema.TABLES
WHERE TABLE_SCHEMA = DATABASE()
  AND TABLE_NAME NOT IN (
      SELECT TABLE_NAME FROM information_schema.TABLE_CONSTRAINTS
      WHERE TABLE_SCHEMA = DATABASE() AND CONSTRAINT_TYPE = 'PRIMARY KEY'
  );

-- Find all foreign keys
SELECT
    TABLE_NAME, COLUMN_NAME,
    REFERENCED_TABLE_NAME, REFERENCED_COLUMN_NAME,
    CONSTRAINT_NAME
FROM information_schema.KEY_COLUMN_USAGE
WHERE TABLE_SCHEMA = DATABASE()
  AND REFERENCED_TABLE_NAME IS NOT NULL
ORDER BY TABLE_NAME;

-- ════════════════════════════════════════════════════════════
-- PERFORMANCE DIAGNOSTICS
-- ════════════════════════════════════════════════════════════

-- Current running queries
SELECT id, user, host, db, command, time, state, LEFT(info, 100) AS query
FROM information_schema.PROCESSLIST
WHERE command != 'Sleep'
ORDER BY time DESC;

-- Kill a specific query
-- KILL QUERY <process_id>;

-- Buffer pool hit ratio
SELECT ROUND(
    (1 - (
        (SELECT VARIABLE_VALUE FROM performance_schema.global_status WHERE VARIABLE_NAME = 'Innodb_buffer_pool_reads') /
        NULLIF((SELECT VARIABLE_VALUE FROM performance_schema.global_status WHERE VARIABLE_NAME = 'Innodb_buffer_pool_read_requests'), 0)
    )) * 100, 4
) AS buffer_pool_hit_pct;

-- Top 10 queries by total time
SELECT DIGEST_TEXT, COUNT_STAR, ROUND(SUM_TIMER_WAIT/1e12,3) AS total_sec
FROM performance_schema.events_statements_summary_by_digest
ORDER BY SUM_TIMER_WAIT DESC LIMIT 10;

-- ════════════════════════════════════════════════════════════
-- DATA QUALITY CHECKS
-- ════════════════════════════════════════════════════════════

-- Find NULL values in all columns of a table
SELECT
    SUM(CASE WHEN email IS NULL THEN 1 ELSE 0 END)      AS null_email,
    SUM(CASE WHEN username IS NULL THEN 1 ELSE 0 END)   AS null_username,
    SUM(CASE WHEN country IS NULL THEN 1 ELSE 0 END)    AS null_country,
    COUNT(*) AS total_rows
FROM users;

-- Find duplicate rows
SELECT email, COUNT(*) AS cnt FROM users GROUP BY email HAVING cnt > 1;

-- Orphaned records (FK violation check)
SELECT oi.order_id FROM order_items_2nf oi
LEFT JOIN orders_2nf o ON oi.order_id = o.order_id
WHERE o.order_id IS NULL;

-- ════════════════════════════════════════════════════════════
-- COMMON PATTERNS
-- ════════════════════════════════════════════════════════════

-- Upsert pattern
INSERT INTO table_name (id, col1, col2)
VALUES (1, 'val1', 'val2')
ON DUPLICATE KEY UPDATE col1 = VALUES(col1), col2 = VALUES(col2);

-- Safe pagination (keyset)
-- SELECT * FROM orders WHERE order_id > :last_id ORDER BY order_id LIMIT :page_size;

-- Batch delete (avoid long transactions)
-- REPEAT
--   DELETE FROM logs WHERE created_at < '2023-01-01' LIMIT 1000;
-- UNTIL ROW_COUNT() = 0 END REPEAT;

-- JSON operations (MySQL 5.7+)
SELECT JSON_EXTRACT('{"name":"Alice","age":30}', '$.name') AS name;
SELECT JSON_UNQUOTE(JSON_EXTRACT(properties, '$.page')) AS page FROM events LIMIT 5;
SELECT * FROM events WHERE JSON_EXTRACT(properties, '$.amount') > 100;

-- Generated column from JSON (indexed)
-- ALTER TABLE events ADD COLUMN event_page VARCHAR(200)
--     GENERATED ALWAYS AS (JSON_UNQUOTE(JSON_EXTRACT(properties, '$.page'))) STORED;
-- ALTER TABLE events ADD INDEX idx_event_page (event_page);

-- ════════════════════════════════════════════════════════════
-- MAINTENANCE
-- ════════════════════════════════════════════════════════════

-- Update table statistics
ANALYZE TABLE users, orders, products;

-- Check table for errors
CHECK TABLE users;

-- Rebuild table (defragment, update statistics)
-- OPTIMIZE TABLE users;  -- locks table in older MySQL

-- Show table status
SHOW TABLE STATUS LIKE 'users'\G

-- Reset auto_increment
-- ALTER TABLE users AUTO_INCREMENT = 1;

-- ════════════════════════════════════════════════════════════
-- USEFUL VARIABLES
-- ════════════════════════════════════════════════════════════
SHOW VARIABLES LIKE 'innodb_buffer_pool_size';
SHOW VARIABLES LIKE 'max_connections';
SHOW VARIABLES LIKE 'slow_query_log%';
SHOW VARIABLES LIKE 'long_query_time';
SHOW VARIABLES LIKE 'binlog_format';
SHOW VARIABLES LIKE 'transaction_isolation';
SHOW VARIABLES LIKE 'innodb_flush_log_at_trx_commit';
SHOW VARIABLES LIKE 'sync_binlog';
