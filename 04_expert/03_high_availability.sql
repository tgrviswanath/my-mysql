-- ============================================================
-- 03_high_availability.sql
-- Replication setup, monitoring, Group Replication concepts
-- ============================================================

-- ════════════════════════════════════════════════════════════
-- REPLICATION MONITORING
-- ════════════════════════════════════════════════════════════

-- Check replication status on replica
SHOW REPLICA STATUS\G
-- Key fields:
--   Replica_IO_Running: Yes       → I/O thread connected to source
--   Replica_SQL_Running: Yes      → SQL thread applying events
--   Seconds_Behind_Source: 0      → no lag (0 = caught up)
--   Last_Error: ''                → no errors
--   Executed_Gtid_Set              → GTIDs applied on this replica
--   Retrieved_Gtid_Set             → GTIDs received from source

-- Check binary log position on source
SHOW MASTER STATUS\G
-- File: binlog.000001, Position: 12345
-- Executed_Gtid_Set: uuid:1-1000

-- List binary logs
SHOW BINARY LOGS;

-- Read binary log events
SHOW BINLOG EVENTS IN 'binlog.000001' FROM 4 LIMIT 20;

-- ════════════════════════════════════════════════════════════
-- REPLICATION SETUP (run on source)
-- ════════════════════════════════════════════════════════════

-- Create replication user
CREATE USER IF NOT EXISTS 'repl'@'%'
    IDENTIFIED WITH mysql_native_password BY 'Repl_Strong_Pass_2024!';
GRANT REPLICATION SLAVE ON *.* TO 'repl'@'%';
FLUSH PRIVILEGES;

-- Verify GTID mode
SHOW VARIABLES LIKE 'gtid_mode';
SHOW VARIABLES LIKE 'enforce_gtid_consistency';

-- ════════════════════════════════════════════════════════════
-- REPLICATION SETUP (run on replica)
-- ════════════════════════════════════════════════════════════

-- Configure source connection (GTID-based)
CHANGE REPLICATION SOURCE TO
    SOURCE_HOST = '192.168.1.100',
    SOURCE_PORT = 3306,
    SOURCE_USER = 'repl',
    SOURCE_PASSWORD = 'Repl_Strong_Pass_2024!',
    SOURCE_AUTO_POSITION = 1,
    SOURCE_SSL = 1;

-- Start replication
START REPLICA;

-- Stop replication (for maintenance)
STOP REPLICA;

-- Reset replication (start fresh)
-- RESET REPLICA ALL;

-- ════════════════════════════════════════════════════════════
-- PARALLEL REPLICATION (MySQL 5.7+)
-- ════════════════════════════════════════════════════════════
SET GLOBAL replica_parallel_workers = 4;
SET GLOBAL replica_parallel_type = 'LOGICAL_CLOCK';
SET GLOBAL replica_preserve_commit_order = ON;

-- ════════════════════════════════════════════════════════════
-- REPLICATION FILTERS
-- ════════════════════════════════════════════════════════════

-- Replicate only specific databases
-- In my.cnf:
-- replicate-do-db = production_db
-- replicate-ignore-db = test_db

-- Skip a specific error (use with caution)
-- SET GLOBAL replica_skip_errors = '1062';  -- skip duplicate key errors

-- Skip one event (when stuck on an error)
-- STOP REPLICA;
-- SET GLOBAL SQL_REPLICA_SKIP_COUNTER = 1;
-- START REPLICA;

-- ════════════════════════════════════════════════════════════
-- GTID OPERATIONS
-- ════════════════════════════════════════════════════════════

-- Check executed GTIDs
SELECT @@global.gtid_executed;

-- Check purged GTIDs (no longer in binlog)
SELECT @@global.gtid_purged;

-- Find GTID gaps between source and replica
-- On source: SELECT @@global.gtid_executed AS source_gtids;
-- On replica: SELECT @@global.gtid_executed AS replica_gtids;
-- Gap = source_gtids - replica_gtids

-- Inject empty transaction to skip a GTID (advanced recovery)
-- SET GTID_NEXT = 'source_uuid:N';
-- BEGIN; COMMIT;
-- SET GTID_NEXT = 'AUTOMATIC';

-- ════════════════════════════════════════════════════════════
-- SEMI-SYNCHRONOUS REPLICATION
-- ════════════════════════════════════════════════════════════

-- Install plugins (source)
-- INSTALL PLUGIN rpl_semi_sync_source SONAME 'semisync_source.so';
SET GLOBAL rpl_semi_sync_source_enabled = 1;
SET GLOBAL rpl_semi_sync_source_timeout = 1000;  -- fallback to async after 1s

-- Install plugins (replica)
-- INSTALL PLUGIN rpl_semi_sync_replica SONAME 'semisync_replica.so';
SET GLOBAL rpl_semi_sync_replica_enabled = 1;

-- Monitor semi-sync
SHOW STATUS LIKE 'Rpl_semi_sync%';

-- ════════════════════════════════════════════════════════════
-- REPLICATION HEALTH CHECKS
-- ════════════════════════════════════════════════════════════

-- Check replica lag
SELECT
    CHANNEL_NAME,
    SERVICE_STATE,
    LAST_ERROR_MESSAGE,
    LAST_HEARTBEAT_TIMESTAMP
FROM performance_schema.replication_connection_status;

SELECT
    CHANNEL_NAME,
    SERVICE_STATE,
    LAST_APPLIED_TRANSACTION,
    APPLYING_TRANSACTION,
    LAST_ERROR_MESSAGE
FROM performance_schema.replication_applier_status_by_worker;

-- Replica lag in seconds
SELECT
    TIMESTAMPDIFF(SECOND,
        LAST_APPLIED_TRANSACTION_ORIGINAL_COMMIT_TIMESTAMP,
        NOW()) AS lag_seconds
FROM performance_schema.replication_applier_status_by_worker
WHERE CHANNEL_NAME = '';
