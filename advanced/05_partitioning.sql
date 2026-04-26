-- ============================================================
-- 05_partitioning.sql
-- RANGE, LIST, HASH, KEY partitioning + partition pruning
-- ============================================================
USE practice_db;

-- ════════════════════════════════════════════════════════════
-- RANGE PARTITIONING — partition by value ranges
-- ════════════════════════════════════════════════════════════
-- Best for: time-series data, archiving old partitions

CREATE TABLE IF NOT EXISTS events_range (
    event_id    INT NOT NULL,
    event_type  VARCHAR(50),
    created_at  DATETIME NOT NULL,
    payload     JSON,
    PRIMARY KEY (event_id, created_at)  -- partition key must be in PK
)
PARTITION BY RANGE (YEAR(created_at)) (
    PARTITION p2022 VALUES LESS THAN (2023),
    PARTITION p2023 VALUES LESS THAN (2024),
    PARTITION p2024 VALUES LESS THAN (2025),
    PARTITION p_future VALUES LESS THAN MAXVALUE
);

-- Insert data
INSERT INTO events_range (event_id, event_type, created_at) VALUES
    (1, 'login',   '2022-06-15 10:00:00'),
    (2, 'purchase','2023-03-20 14:30:00'),
    (3, 'logout',  '2024-01-05 09:15:00'),
    (4, 'signup',  '2024-11-01 16:45:00');

-- Partition pruning: only scans p2024
EXPLAIN SELECT * FROM events_range WHERE created_at >= '2024-01-01';
-- partitions=p2024 ✅

-- Add new partition
ALTER TABLE events_range REORGANIZE PARTITION p_future INTO (
    PARTITION p2025 VALUES LESS THAN (2026),
    PARTITION p_future VALUES LESS THAN MAXVALUE
);

-- Drop old partition (instant — no row-by-row delete)
ALTER TABLE events_range DROP PARTITION p2022;

-- ════════════════════════════════════════════════════════════
-- LIST PARTITIONING — partition by discrete values
-- ════════════════════════════════════════════════════════════
-- Best for: region-based, category-based data

CREATE TABLE IF NOT EXISTS orders_list (
    order_id   INT NOT NULL,
    region     VARCHAR(10) NOT NULL,
    amount     DECIMAL(10,2),
    PRIMARY KEY (order_id, region)
)
PARTITION BY LIST COLUMNS (region) (
    PARTITION p_americas VALUES IN ('US', 'CA', 'MX', 'BR'),
    PARTITION p_europe    VALUES IN ('UK', 'DE', 'FR', 'IT'),
    PARTITION p_apac      VALUES IN ('AU', 'JP', 'SG', 'IN')
);

INSERT INTO orders_list VALUES (1,'US',100),(2,'UK',200),(3,'JP',300),(4,'AU',150);

-- Only scans p_europe
EXPLAIN SELECT * FROM orders_list WHERE region IN ('UK', 'DE');

-- ════════════════════════════════════════════════════════════
-- HASH PARTITIONING — distribute evenly
-- ════════════════════════════════════════════════════════════
-- Best for: even distribution, no natural range/list

CREATE TABLE IF NOT EXISTS sessions_hash (
    session_id  BIGINT NOT NULL,
    user_id     INT NOT NULL,
    data        TEXT,
    PRIMARY KEY (session_id)
)
PARTITION BY HASH (session_id)
PARTITIONS 8;

-- ════════════════════════════════════════════════════════════
-- KEY PARTITIONING — MySQL manages the hash function
-- ════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS cache_key (
    cache_key   VARCHAR(100) NOT NULL,
    value       TEXT,
    expires_at  DATETIME,
    PRIMARY KEY (cache_key)
)
PARTITION BY KEY (cache_key)
PARTITIONS 4;

-- ════════════════════════════════════════════════════════════
-- RANGE COLUMNS — partition by date column directly
-- ════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS logs_range_col (
    log_id      INT NOT NULL,
    log_date    DATE NOT NULL,
    message     TEXT,
    PRIMARY KEY (log_id, log_date)
)
PARTITION BY RANGE COLUMNS (log_date) (
    PARTITION p_q1_2024 VALUES LESS THAN ('2024-04-01'),
    PARTITION p_q2_2024 VALUES LESS THAN ('2024-07-01'),
    PARTITION p_q3_2024 VALUES LESS THAN ('2024-10-01'),
    PARTITION p_q4_2024 VALUES LESS THAN ('2025-01-01'),
    PARTITION p_future  VALUES LESS THAN (MAXVALUE)
);

-- ── Partition metadata ────────────────────────────────────────
SELECT
    PARTITION_NAME,
    PARTITION_METHOD,
    PARTITION_EXPRESSION,
    TABLE_ROWS
FROM information_schema.PARTITIONS
WHERE TABLE_SCHEMA = 'practice_db'
  AND TABLE_NAME = 'events_range'
ORDER BY PARTITION_ORDINAL_POSITION;

-- ── Partition pruning verification ───────────────────────────
EXPLAIN SELECT * FROM events_range
WHERE created_at BETWEEN '2023-01-01' AND '2023-12-31';
-- Should show: partitions=p2023 only

-- ── Partition maintenance ─────────────────────────────────────
-- Check partition sizes
SELECT PARTITION_NAME, TABLE_ROWS, AVG_ROW_LENGTH,
       ROUND(DATA_LENGTH/1024/1024, 2) AS data_mb
FROM information_schema.PARTITIONS
WHERE TABLE_SCHEMA = 'practice_db' AND TABLE_NAME = 'events_range';

-- Rebuild a partition (defragment)
-- ALTER TABLE events_range REBUILD PARTITION p2023;

-- Analyze partition statistics
-- ALTER TABLE events_range ANALYZE PARTITION p2023;
