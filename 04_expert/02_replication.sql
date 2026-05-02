-- ============================================================
-- 02_replication.sql
-- Binary log inspection, GTID operations, replication monitoring
-- ============================================================

-- ════════════════════════════════════════════════════════════
-- BINARY LOG INSPECTION
-- ════════════════════════════════════════════════════════════

-- Check if binary logging is enabled
SHOW VARIABLES LIKE 'log_bin';
SHOW VARIABLES LIKE 'binlog_format';
SHOW VARIABLES LIKE 'binlog_row_image';  -- FULL, MINIMAL, NOBLOB

-- List binary log files
SHOW BINARY LOGS;

-- Current binary log position
SHOW MASTER STATUS\G

-- Read binary log events
SHOW BINLOG EVENTS IN 'binlog.000001' LIMIT 20;
SHOW BINLOG EVENTS IN 'binlog.000001' FROM 4 LIMIT 10;

-- Purge old binary logs (keep last 7 days)
-- PURGE BINARY LOGS BEFORE DATE_SUB(NOW(), INTERVAL 7 DAY);
-- Or by filename:
-- PURGE BINARY LOGS TO 'binlog.000010';

-- ════════════════════════════════════════════════════════════
-- GTID OPERATIONS
-- ════════════════════════════════════════════════════════════

SHOW VARIABLES LIKE 'gtid_mode';
SHOW VARIABLES LIKE 'enforce_gtid_consistency';

-- All committed GTIDs on this server
SELECT @@global.gtid_executed;

-- GTIDs purged from binary logs
SELECT @@global.gtid_purged;

-- Check if a specific GTID has been executed
-- SELECT GTID_SUBSET('source_uuid:1-100', @@global.gtid_executed);

-- Find GTIDs on source not yet on replica
-- On source: SELECT @@global.gtid_executed AS source_gtids;
-- On replica: SELECT GTID_SUBTRACT('source_gtids', @@global.gtid_executed) AS missing;

-- ════════════════════════════════════════════════════════════
-- REPLICA STATUS & MONITORING
-- ════════════════════════════════════════════════════════════

-- Full replica status
SHOW REPLICA STATUS\G

-- Key metrics from performance_schema (MySQL 8.0+)
SELECT
    CHANNEL_NAME,
    SERVICE_STATE AS io_state,
    LAST_ERROR_MESSAGE AS io_error,
    LAST_HEARTBEAT_TIMESTAMP
FROM performance_schema.replication_connection_status;

SELECT
    CHANNEL_NAME,
    SERVICE_STATE AS sql_state,
    LAST_ERROR_MESSAGE AS sql_error,
    LAST_APPLIED_TRANSACTION,
    LAST_APPLIED_TRANSACTION_ORIGINAL_COMMIT_TIMESTAMP,
    LAST_APPLIED_TRANSACTION_APPLY_TIMESTAMP
FROM performance_schema.replication_applier_status_by_coordinator;

-- Per-worker status (parallel replication)
SELECT
    WORKER_ID,
    SERVICE_STATE,
    LAST_APPLIED_TRANSACTION,
    LAST_ERROR_MESSAGE,
    APPLYING_TRANSACTION
FROM performance_schema.replication_applier_status_by_worker;

-- Replica lag calculation
SELECT
    TIMESTAMPDIFF(SECOND,
        LAST_APPLIED_TRANSACTION_ORIGINAL_COMMIT_TIMESTAMP,
        NOW()
    ) AS lag_seconds
FROM performance_schema.replication_applier_status_by_worker
WHERE CHANNEL_NAME = ''
LIMIT 1;

-- ════════════════════════════════════════════════════════════
-- REPLICATION FILTERS
-- ════════════════════════════════════════════════════════════

-- View current replication filters
SHOW REPLICA STATUS\G
-- Look for: Replicate_Do_DB, Replicate_Ignore_DB, Replicate_Do_Table

-- Dynamic filter (MySQL 8.0+)
-- CHANGE REPLICATION FILTER REPLICATE_DO_DB = (production_db);
-- CHANGE REPLICATION FILTER REPLICATE_IGNORE_TABLE = (production_db.audit_log);

-- ════════════════════════════════════════════════════════════
-- SEMI-SYNC STATUS
-- ════════════════════════════════════════════════════════════

SHOW STATUS LIKE 'Rpl_semi_sync%';
-- Rpl_semi_sync_source_clients: number of semi-sync replicas
-- Rpl_semi_sync_source_yes_tx: transactions committed with semi-sync
-- Rpl_semi_sync_source_no_tx: transactions that fell back to async

-- ════════════════════════════════════════════════════════════
-- BINLOG BASED POINT-IN-TIME RECOVERY
-- ════════════════════════════════════════════════════════════

-- Step 1: Restore from last full backup
-- mysql -u root -p < backup_20240101.sql

-- Step 2: Apply binary logs from backup time to target time
-- mysqlbinlog --start-datetime="2024-01-01 00:00:00" \
--             --stop-datetime="2024-01-01 14:30:00" \
--             /var/lib/mysql/binlog.000001 | mysql -u root -p

-- Step 3: Verify data
-- SELECT COUNT(*) FROM orders WHERE created_at <= '2024-01-01 14:30:00';
