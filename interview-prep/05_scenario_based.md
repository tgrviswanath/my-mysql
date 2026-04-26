# 05 — Scenario-Based Interview Questions

## Scenario 1: Design a URL Shortener Database

**Question**: Design the MySQL schema for a URL shortener like bit.ly. Handle millions of URLs, track click analytics, support custom aliases, and allow expiration.

**Answer**:

```sql
CREATE TABLE short_urls (
    id          BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    short_code  VARCHAR(10) NOT NULL,
    long_url    TEXT NOT NULL,
    user_id     BIGINT UNSIGNED,
    clicks      INT UNSIGNED NOT NULL DEFAULT 0,
    expires_at  DATETIME,
    created_at  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE INDEX idx_short_code (short_code),
    INDEX idx_user (user_id),
    INDEX idx_expires (expires_at)
);

CREATE TABLE url_clicks (
    click_id    BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    short_code  VARCHAR(10) NOT NULL,
    ip_address  VARCHAR(45),
    referrer    VARCHAR(500),
    user_agent  VARCHAR(500),
    country     CHAR(2),
    clicked_at  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_short_code_time (short_code, clicked_at)
) PARTITION BY RANGE (TO_DAYS(clicked_at)) (
    -- Monthly partitions for easy archiving
    PARTITION p_2024_01 VALUES LESS THAN (TO_DAYS('2024-02-01')),
    PARTITION p_future  VALUES LESS THAN MAXVALUE
);
```

**Key decisions**:
- `short_code` is the lookup key — UNIQUE index for O(log n) lookup
- `clicks` counter on the URL table for fast read (denormalized)
- `url_clicks` partitioned by date for easy archiving and pruning
- Separate click tracking table to avoid hot row contention on `short_urls`

---

## Scenario 2: Rate Limiting with MySQL

**Question**: Implement API rate limiting (100 requests/minute per user) using MySQL.

**Answer**:

```sql
CREATE TABLE rate_limits (
    user_id     BIGINT UNSIGNED NOT NULL,
    window_start DATETIME NOT NULL,
    request_count INT UNSIGNED NOT NULL DEFAULT 1,
    PRIMARY KEY (user_id, window_start),
    INDEX idx_window (window_start)
);

-- Check and increment (atomic upsert)
INSERT INTO rate_limits (user_id, window_start, request_count)
VALUES (?, DATE_FORMAT(NOW(), '%Y-%m-%d %H:%i:00'), 1)
ON DUPLICATE KEY UPDATE request_count = request_count + 1;

-- Check if over limit
SELECT request_count FROM rate_limits
WHERE user_id = ? AND window_start = DATE_FORMAT(NOW(), '%Y-%m-%d %H:%i:00');

-- Cleanup old windows (run periodically)
DELETE FROM rate_limits WHERE window_start < DATE_SUB(NOW(), INTERVAL 5 MINUTE);
```

**Trade-offs**: MySQL-based rate limiting adds DB load. For high-throughput APIs, use Redis (INCR + EXPIRE) instead.

---

## Scenario 3: Leaderboard Design

**Question**: Design a real-time leaderboard for a gaming platform with millions of users. Support global rank, friend rank, and weekly/monthly/all-time leaderboards.

**Answer**:

```sql
CREATE TABLE scores (
    user_id     BIGINT UNSIGNED NOT NULL,
    period      ENUM('weekly','monthly','alltime') NOT NULL,
    score       BIGINT UNSIGNED NOT NULL DEFAULT 0,
    updated_at  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (user_id, period),
    INDEX idx_period_score (period, score DESC)  -- for rank queries
);

-- Get global rank (expensive for large tables — use Redis for real-time)
SELECT user_id, score,
       RANK() OVER (PARTITION BY period ORDER BY score DESC) AS global_rank
FROM scores WHERE period = 'weekly';

-- Approximate rank (fast, uses index)
SELECT COUNT(*) + 1 AS rank
FROM scores
WHERE period = 'weekly' AND score > (SELECT score FROM scores WHERE user_id = ? AND period = 'weekly');
```

**Production note**: For millions of users, use Redis Sorted Sets (`ZADD`, `ZRANK`) for O(log n) rank queries. MySQL leaderboard works for < 100K users.

---

## Scenario 4: Audit Trail System

**Question**: Design an audit trail that tracks all changes to critical tables (who changed what, when, and what the old/new values were).

**Answer**:

```sql
CREATE TABLE audit_log (
    audit_id    BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    table_name  VARCHAR(100) NOT NULL,
    record_id   BIGINT UNSIGNED NOT NULL,
    action      ENUM('INSERT','UPDATE','DELETE') NOT NULL,
    changed_by  BIGINT UNSIGNED,
    old_values  JSON,
    new_values  JSON,
    changed_at  DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    INDEX idx_table_record (table_name, record_id),
    INDEX idx_changed_at (changed_at),
    INDEX idx_changed_by (changed_by)
) PARTITION BY RANGE (TO_DAYS(changed_at)) (
    PARTITION p_2024_q1 VALUES LESS THAN (TO_DAYS('2024-04-01')),
    PARTITION p_future  VALUES LESS THAN MAXVALUE
);

-- Trigger example for accounts table
DELIMITER $$
CREATE TRIGGER trg_accounts_audit
AFTER UPDATE ON accounts FOR EACH ROW
BEGIN
    INSERT INTO audit_log (table_name, record_id, action, old_values, new_values)
    VALUES ('accounts', OLD.account_id, 'UPDATE',
        JSON_OBJECT('balance', OLD.balance, 'status', OLD.status),
        JSON_OBJECT('balance', NEW.balance, 'status', NEW.status));
END$$
DELIMITER ;
```

---

## Scenario 5: Handling Soft Deletes at Scale

**Question**: You have a users table with 50M rows. You need to implement soft deletes without degrading query performance.

**Answer**:

```sql
-- Add deleted_at column
ALTER TABLE users ADD COLUMN deleted_at DATETIME NULL;

-- All queries must filter: WHERE deleted_at IS NULL
-- Problem: full table scan if deleted_at is not indexed

-- Solution 1: Regular index (works but includes NULLs)
ALTER TABLE users ADD INDEX idx_deleted_at (deleted_at);

-- Solution 2: Partial index workaround (MySQL doesn't support partial indexes natively)
-- Use a generated column trick:
ALTER TABLE users ADD COLUMN is_active TINYINT(1) GENERATED ALWAYS AS (deleted_at IS NULL) STORED;
ALTER TABLE users ADD INDEX idx_active (is_active);
-- Query: WHERE is_active = 1

-- Solution 3: Separate active/deleted tables (for very high delete rates)
-- Move deleted rows to users_deleted table periodically

-- Solution 4: Use a view
CREATE VIEW active_users AS SELECT * FROM users WHERE deleted_at IS NULL;
```

---

## Scenario 6: Optimizing a Slow Report Query

**Question**: This query takes 45 seconds on a 10M row orders table. How do you fix it?

```sql
SELECT customer_id, SUM(total) AS revenue
FROM orders
WHERE YEAR(created_at) = 2024 AND status = 'completed'
GROUP BY customer_id
ORDER BY revenue DESC;
```

**Answer**:

Step 1: Rewrite to use index on created_at:
```sql
WHERE created_at >= '2024-01-01' AND created_at < '2025-01-01' AND status = 'completed'
```

Step 2: Add composite index:
```sql
ALTER TABLE orders ADD INDEX idx_status_created_cust (status, created_at, customer_id, total);
```

Step 3: Verify with EXPLAIN — look for `type=range`, `Extra=Using index`.

Step 4: If still slow (many rows), consider:
- Pre-aggregating into a `daily_revenue` summary table (materialized view pattern)
- Partitioning orders by year for partition pruning
- Running the report on a read replica
