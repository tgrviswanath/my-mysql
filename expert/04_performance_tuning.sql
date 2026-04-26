-- ============================================================
-- 04_performance_tuning.sql
-- Slow query analysis, performance_schema, sys schema, tuning
-- ============================================================
USE practice_db;

-- ════════════════════════════════════════════════════════════
-- SLOW QUERY LOG
-- ════════════════════════════════════════════════════════════

-- Enable slow query log
SET GLOBAL slow_query_log = 'ON';
SET GLOBAL long_query_time = 0.1;          -- log queries > 100ms
SET GLOBAL log_queries_not_using_indexes = 'ON';
-- SET GLOBAL slow_query_log_file = '/var/log/mysql/slow.log';

-- Check slow query count
SHOW GLOBAL STATUS LIKE 'Slow_queries';

-- ════════════════════════════════════════════════════════════
-- PERFORMANCE_SCHEMA
-- ════════════════════════════════════════════════════════════

-- Top 10 slowest queries (by total execution time)
SELECT
    DIGEST_TEXT,
    COUNT_STAR                              AS exec_count,
    ROUND(SUM_TIMER_WAIT/1e12, 3)          AS total_sec,
    ROUND(AVG_TIMER_WAIT/1e12, 3)          AS avg_sec,
    ROUND(MAX_TIMER_WAIT/1e12, 3)          AS max_sec,
    SUM_ROWS_EXAMINED                       AS rows_examined,
    SUM_ROWS_SENT                           AS rows_sent,
    SUM_NO_INDEX_USED                       AS no_index_count
FROM performance_schema.events_statements_summary_by_digest
ORDER BY SUM_TIMER_WAIT DESC
LIMIT 10;

-- Queries with full table scans
SELECT DIGEST_TEXT, COUNT_STAR, SUM_NO_INDEX_USED
FROM performance_schema.events_statements_summary_by_digest
WHERE SUM_NO_INDEX_USED > 0
ORDER BY SUM_NO_INDEX_USED DESC
LIMIT 10;

-- Table I/O statistics
SELECT OBJECT_NAME, COUNT_READ, COUNT_WRITE,
       ROUND(SUM_TIMER_READ/1e12, 3)  AS read_sec,
       ROUND(SUM_TIMER_WRITE/1e12, 3) AS write_sec
FROM performance_schema.table_io_waits_summary_by_table
WHERE OBJECT_SCHEMA = 'practice_db'
ORDER BY SUM_TIMER_READ + SUM_TIMER_WRITE DESC;

-- Index usage statistics
SELECT OBJECT_NAME, INDEX_NAME, COUNT_FETCH, COUNT_INSERT, COUNT_UPDATE, COUNT_DELETE
FROM performance_schema.table_io_waits_summary_by_index_usage
WHERE OBJECT_SCHEMA = 'practice_db'
ORDER BY OBJECT_NAME, COUNT_FETCH DESC;

-- Unused indexes
SELECT OBJECT_NAME, INDEX_NAME
FROM performance_schema.table_io_waits_summary_by_index_usage
WHERE OBJECT_SCHEMA = 'practice_db'
  AND INDEX_NAME IS NOT NULL
  AND COUNT_STAR = 0
  AND INDEX_NAME != 'PRIMARY';

-- ════════════════════════════════════════════════════════════
-- SYS SCHEMA (human-readable views over performance_schema)
-- ════════════════════════════════════════════════════════════

-- Top queries by total latency
SELECT query, exec_count, total_latency, avg_latency, rows_examined_avg
FROM sys.statement_analysis
ORDER BY total_latency DESC
LIMIT 10;

-- Tables with full table scans
SELECT table_name, rows_full_scanned, latency
FROM sys.schema_tables_with_full_table_scans
WHERE table_schema = 'practice_db';

-- Redundant indexes
SELECT * FROM sys.schema_redundant_indexes
WHERE table_schema = 'practice_db';

-- Unused indexes
SELECT * FROM sys.schema_unused_indexes
WHERE object_schema = 'practice_db';

-- Memory usage by component
SELECT event_name, current_alloc, high_alloc
FROM sys.memory_global_by_current_bytes
LIMIT 20;

-- ════════════════════════════════════════════════════════════
-- KEY INNODB VARIABLES TO TUNE
-- ════════════════════════════════════════════════════════════

-- Buffer pool (most important — set to 70-80% of RAM)
SHOW VARIABLES LIKE 'innodb_buffer_pool_size';
-- SET GLOBAL innodb_buffer_pool_size = 4 * 1024 * 1024 * 1024;  -- 4GB

-- Buffer pool instances (1 per GB, max 64)
SHOW VARIABLES LIKE 'innodb_buffer_pool_instances';

-- Redo log size (larger = fewer checkpoints = better write throughput)
SHOW VARIABLES LIKE 'innodb_log_file_size';

-- Flush method (O_DIRECT avoids double buffering with OS cache)
SHOW VARIABLES LIKE 'innodb_flush_method';
-- Recommended: O_DIRECT on Linux

-- I/O capacity (set to IOPS of your storage)
SHOW VARIABLES LIKE 'innodb_io_capacity';
SHOW VARIABLES LIKE 'innodb_io_capacity_max';
-- SSD: 2000-10000, NVMe: 10000-50000

-- Dirty page flush threshold
SHOW VARIABLES LIKE 'innodb_max_dirty_pages_pct';  -- default 90%

-- ════════════════════════════════════════════════════════════
-- BUFFER POOL HIT RATIO
-- ════════════════════════════════════════════════════════════
SELECT
    ROUND(
        (1 - (
            (SELECT VARIABLE_VALUE FROM performance_schema.global_status WHERE VARIABLE_NAME = 'Innodb_buffer_pool_reads') /
            (SELECT VARIABLE_VALUE FROM performance_schema.global_status WHERE VARIABLE_NAME = 'Innodb_buffer_pool_read_requests')
        )) * 100, 4
    ) AS buffer_pool_hit_ratio_pct;
-- Target: > 99%

-- ════════════════════════════════════════════════════════════
-- CONNECTION & THREAD TUNING
-- ════════════════════════════════════════════════════════════
SHOW VARIABLES LIKE 'max_connections';          -- default 151
SHOW VARIABLES LIKE 'thread_cache_size';        -- reuse threads
SHOW STATUS LIKE 'Threads_connected';
SHOW STATUS LIKE 'Threads_running';
SHOW STATUS LIKE 'Connection_errors_max_connections';  -- > 0 means max_connections too low

-- ════════════════════════════════════════════════════════════
-- SORT & JOIN BUFFER TUNING
-- ════════════════════════════════════════════════════════════
SHOW VARIABLES LIKE 'sort_buffer_size';         -- per-thread, for filesort
SHOW VARIABLES LIKE 'join_buffer_size';         -- per-thread, for BNL joins
SHOW VARIABLES LIKE 'read_rnd_buffer_size';     -- for ORDER BY on full scans
-- Note: these are per-thread — don't set too high (max_connections × buffer_size)

-- ════════════════════════════════════════════════════════════
-- INNODB STATUS
-- ════════════════════════════════════════════════════════════
SHOW ENGINE INNODB STATUS\G
-- Key sections to review:
-- BUFFER POOL AND MEMORY: hit ratio, dirty pages
-- LOG: LSN, checkpoint age
-- TRANSACTIONS: active transactions, lock waits
-- LATEST DETECTED DEADLOCK: deadlock details
-- ROW OPERATIONS: rows read/inserted/updated/deleted per second
