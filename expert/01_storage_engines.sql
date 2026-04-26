-- ============================================================
-- 01_storage_engines.sql
-- InnoDB internals: buffer pool, MVCC, undo/redo monitoring
-- ============================================================

-- ════════════════════════════════════════════════════════════
-- BUFFER POOL MONITORING
-- ════════════════════════════════════════════════════════════

-- Buffer pool size and usage
SHOW VARIABLES LIKE 'innodb_buffer_pool_size';
SHOW VARIABLES LIKE 'innodb_buffer_pool_instances';

-- Buffer pool hit ratio (target > 99%)
SELECT
    VARIABLE_NAME,
    VARIABLE_VALUE
FROM performance_schema.global_status
WHERE VARIABLE_NAME IN (
    'Innodb_buffer_pool_read_requests',
    'Innodb_buffer_pool_reads',
    'Innodb_buffer_pool_write_requests',
    'Innodb_buffer_pool_pages_total',
    'Innodb_buffer_pool_pages_dirty',
    'Innodb_buffer_pool_pages_free'
);

-- Computed hit ratio
SELECT
    ROUND(
        (1 - bp_reads.val / NULLIF(bp_req.val, 0)) * 100, 4
    ) AS hit_ratio_pct,
    ROUND(bp_dirty.val / bp_total.val * 100, 2) AS dirty_pages_pct
FROM
    (SELECT VARIABLE_VALUE + 0 AS val FROM performance_schema.global_status WHERE VARIABLE_NAME = 'Innodb_buffer_pool_reads') bp_reads,
    (SELECT VARIABLE_VALUE + 0 AS val FROM performance_schema.global_status WHERE VARIABLE_NAME = 'Innodb_buffer_pool_read_requests') bp_req,
    (SELECT VARIABLE_VALUE + 0 AS val FROM performance_schema.global_status WHERE VARIABLE_NAME = 'Innodb_buffer_pool_pages_dirty') bp_dirty,
    (SELECT VARIABLE_VALUE + 0 AS val FROM performance_schema.global_status WHERE VARIABLE_NAME = 'Innodb_buffer_pool_pages_total') bp_total;

-- ════════════════════════════════════════════════════════════
-- REDO LOG MONITORING
-- ════════════════════════════════════════════════════════════

SHOW VARIABLES LIKE 'innodb_log_file_size';
SHOW VARIABLES LIKE 'innodb_log_files_in_group';
SHOW VARIABLES LIKE 'innodb_flush_log_at_trx_commit';

-- Redo log usage (checkpoint age)
SELECT
    VARIABLE_NAME, VARIABLE_VALUE
FROM performance_schema.global_status
WHERE VARIABLE_NAME IN (
    'Innodb_os_log_written',
    'Innodb_log_writes',
    'Innodb_log_write_requests'
);

-- ════════════════════════════════════════════════════════════
-- UNDO LOG MONITORING
-- ════════════════════════════════════════════════════════════

-- Undo log segments
SELECT * FROM information_schema.INNODB_METRICS
WHERE NAME LIKE '%undo%'
ORDER BY NAME;

-- History list length (undo log backlog — should be < 1000)
SELECT NAME, COUNT FROM information_schema.INNODB_METRICS
WHERE NAME = 'trx_rseg_history_len';
-- High value = long-running transactions preventing undo purge

-- ════════════════════════════════════════════════════════════
-- MVCC MONITORING
-- ════════════════════════════════════════════════════════════

-- Active transactions (long-running = MVCC bloat)
SELECT
    trx_id,
    trx_state,
    trx_started,
    TIMESTAMPDIFF(SECOND, trx_started, NOW()) AS age_seconds,
    trx_rows_locked,
    trx_rows_modified,
    LEFT(trx_query, 100) AS query
FROM information_schema.INNODB_TRX
ORDER BY trx_started ASC;

-- ════════════════════════════════════════════════════════════
-- CHANGE BUFFER MONITORING
-- ════════════════════════════════════════════════════════════

SHOW VARIABLES LIKE 'innodb_change_buffer_max_size';
SHOW VARIABLES LIKE 'innodb_change_buffering';

SELECT NAME, COUNT FROM information_schema.INNODB_METRICS
WHERE NAME LIKE '%ibuf%'
ORDER BY NAME;

-- ════════════════════════════════════════════════════════════
-- ADAPTIVE HASH INDEX
-- ════════════════════════════════════════════════════════════

SHOW VARIABLES LIKE 'innodb_adaptive_hash_index';

SELECT NAME, COUNT FROM information_schema.INNODB_METRICS
WHERE NAME LIKE '%adaptive_hash%'
ORDER BY NAME;

-- Disable if causing contention (check: mutex waits on AHI)
-- SET GLOBAL innodb_adaptive_hash_index = OFF;

-- ════════════════════════════════════════════════════════════
-- FULL INNODB STATUS
-- ════════════════════════════════════════════════════════════
SHOW ENGINE INNODB STATUS\G
-- Sections to review:
-- BACKGROUND THREAD: purge lag
-- SEMAPHORES: mutex/rw-lock waits
-- TRANSACTIONS: active txns, lock waits, history list
-- FILE I/O: pending reads/writes
-- INSERT BUFFER AND ADAPTIVE HASH INDEX: change buffer stats
-- LOG: LSN, checkpoint age, log sequence
-- BUFFER POOL AND MEMORY: pages, hit ratio, dirty pages
-- ROW OPERATIONS: rows read/inserted/updated/deleted per second
