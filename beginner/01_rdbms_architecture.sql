-- ============================================================
-- 01_rdbms_architecture.sql
-- Exploring MySQL architecture via system databases
-- ============================================================

-- 1. Check MySQL version and engine
SELECT VERSION();
SHOW ENGINES;

-- 2. List all databases
SHOW DATABASES;

-- 3. Explore information_schema — list all tables in a DB
SELECT TABLE_NAME, TABLE_TYPE, ENGINE, TABLE_ROWS
FROM information_schema.TABLES
WHERE TABLE_SCHEMA = 'practice_db'
ORDER BY TABLE_NAME;

-- 4. Check current connection thread info
SHOW STATUS LIKE 'Threads%';
SHOW STATUS LIKE 'Max_used_connections';

-- 5. Key InnoDB settings
SHOW VARIABLES LIKE 'innodb_buffer_pool_size';
SHOW VARIABLES LIKE 'max_connections';
SHOW VARIABLES LIKE 'thread_cache_size';

-- 6. Check global status counters
SHOW GLOBAL STATUS LIKE 'Questions';
SHOW GLOBAL STATUS LIKE 'Slow_queries';
SHOW GLOBAL STATUS LIKE 'Innodb_buffer_pool_read_requests';
SHOW GLOBAL STATUS LIKE 'Innodb_buffer_pool_reads';
-- Buffer pool hit ratio = 1 - (Innodb_buffer_pool_reads / Innodb_buffer_pool_read_requests)
-- Target: > 99%

-- 7. View active processes
SHOW FULL PROCESSLIST;

-- 8. Check storage engine for a specific table
SELECT ENGINE FROM information_schema.TABLES
WHERE TABLE_SCHEMA = 'practice_db' AND TABLE_NAME = 'orders';

-- 9. Alter table engine (use with caution in production)
-- ALTER TABLE orders ENGINE = InnoDB;

-- 10. Check index statistics
SELECT TABLE_NAME, INDEX_NAME, CARDINALITY
FROM information_schema.STATISTICS
WHERE TABLE_SCHEMA = 'practice_db'
ORDER BY TABLE_NAME, INDEX_NAME;
