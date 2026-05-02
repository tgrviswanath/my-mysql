# Database System Design with MySQL

## Designing for Scale

### When MySQL Starts to Struggle

```
Single MySQL Instance Limits:
  Reads:   ~10,000 queries/sec (with good indexes)
  Writes:  ~5,000 inserts/sec
  Storage: Practical limit ~5TB per instance
  Connections: ~1,000 concurrent (with connection pooling)

Signs you need to scale:
  - Query latency > 100ms consistently
  - CPU > 70% sustained
  - Replication lag growing
  - Storage > 80% full
  - Connection pool exhausted
```

---

## Replication Architecture

### Primary-Replica (Read Scaling)

```
                    ┌─────────────────┐
  Writes ──────────►│  Primary (RW)   │
                    └────────┬────────┘
                             │ Binary Log (async replication)
              ┌──────────────┼──────────────┐
              ▼              ▼              ▼
        ┌──────────┐  ┌──────────┐  ┌──────────┐
        │ Replica 1│  │ Replica 2│  │ Replica 3│
        │ (RO)     │  │ (RO)     │  │ (RO)     │
        └──────────┘  └──────────┘  └──────────┘
  Reads ──────────────────────────────────────►

Application routing:
  - All writes → Primary
  - All reads  → Replica (round-robin or least-connections)
  - Caution: replication lag means replicas may be slightly behind
```

```sql
-- MySQL replication setup
-- On Primary:
CREATE USER 'repl'@'%' IDENTIFIED BY 'password';
GRANT REPLICATION SLAVE ON *.* TO 'repl'@'%';
SHOW MASTER STATUS;  -- Note File and Position

-- On Replica:
CHANGE MASTER TO
  MASTER_HOST='primary_host',
  MASTER_USER='repl',
  MASTER_PASSWORD='password',
  MASTER_LOG_FILE='mysql-bin.000001',
  MASTER_LOG_POS=154;
START SLAVE;
SHOW SLAVE STATUS\G  -- Check Seconds_Behind_Master
```

### Primary-Primary (Write Scaling + HA)

```
  ┌─────────────────┐         ┌─────────────────┐
  │   Primary 1     │◄───────►│   Primary 2     │
  │   (Active)      │  Sync   │   (Active)      │
  └─────────────────┘         └─────────────────┘
         ▲                           ▲
         │ Writes                    │ Writes
    Region A                    Region B

Risk: Write conflicts — use auto_increment_increment=2 to avoid
Primary 1: IDs 1, 3, 5, 7...
Primary 2: IDs 2, 4, 6, 8...
```

---

## Sharding Strategies

### Horizontal Sharding (Partitioning Across Servers)

```
Problem: Single server can't hold all data

Solution: Split data across multiple MySQL instances

Shard 1 (users 1–1M):     Shard 2 (users 1M–2M):
  ┌──────────────┐           ┌──────────────┐
  │ MySQL DB 1   │           │ MySQL DB 2   │
  │ users 1-1M   │           │ users 1M-2M  │
  └──────────────┘           └──────────────┘

Shard key selection (critical!):
  Good:  user_id (even distribution, most queries filter by user)
  Bad:   created_at (hot shard for recent data)
  Bad:   country (uneven — US has 40% of users)
```

```python
# Shard routing logic
class ShardRouter:
    def __init__(self, shard_connections: list):
        self.shards = shard_connections
        self.num_shards = len(shard_connections)

    def get_shard(self, user_id: int):
        """Route to correct shard based on user_id."""
        shard_index = user_id % self.num_shards
        return self.shards[shard_index]

    def get_user(self, user_id: int) -> dict:
        shard = self.get_shard(user_id)
        return shard.execute(
            "SELECT * FROM users WHERE id = %s", (user_id,)
        ).fetchone()

    def create_user(self, user: dict) -> dict:
        # Must know shard before insert
        shard = self.get_shard(user["id"])
        return shard.execute(
            "INSERT INTO users (id, name, email) VALUES (%s, %s, %s)",
            (user["id"], user["name"], user["email"])
        )

# Cross-shard queries are expensive — avoid or use scatter-gather
def get_all_users_by_email(email: str) -> list:
    results = []
    for shard in router.shards:
        result = shard.execute(
            "SELECT * FROM users WHERE email = %s", (email,)
        ).fetchall()
        results.extend(result)
    return results  # Scatter-gather: query all shards
```

---

## Connection Pooling

```python
# SQLAlchemy connection pool for MySQL
from sqlalchemy import create_engine
from sqlalchemy.pool import QueuePool

engine = create_engine(
    "mysql+pymysql://user:pass@host/db",
    poolclass=QueuePool,
    pool_size=20,          # Persistent connections
    max_overflow=10,       # Extra connections under load
    pool_timeout=30,       # Wait time for connection
    pool_recycle=3600,     # Recycle connections every hour
    pool_pre_ping=True,    # Verify connection before use
)

# For async (aiomysql)
import aiomysql

async def create_pool():
    return await aiomysql.create_pool(
        host='localhost', port=3306,
        user='root', password='password',
        db='mydb', minsize=5, maxsize=20
    )
```

---

## Designing an E-Commerce Database

```sql
-- Optimized schema for high-traffic e-commerce

-- Users table (sharded by user_id)
CREATE TABLE users (
    id          BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    email       VARCHAR(255) NOT NULL,
    name        VARCHAR(100) NOT NULL,
    created_at  DATETIME(3) DEFAULT CURRENT_TIMESTAMP(3),
    UNIQUE KEY uk_email (email)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Products (read-heavy, cache aggressively)
CREATE TABLE products (
    id          BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    name        VARCHAR(200) NOT NULL,
    price       DECIMAL(10,2) NOT NULL,
    stock       INT UNSIGNED NOT NULL DEFAULT 0,
    category_id INT UNSIGNED NOT NULL,
    created_at  DATETIME(3) DEFAULT CURRENT_TIMESTAMP(3),
    INDEX idx_category (category_id),
    INDEX idx_price (price)
) ENGINE=InnoDB;

-- Orders (partitioned by created_at for performance)
CREATE TABLE orders (
    id          BIGINT UNSIGNED AUTO_INCREMENT,
    user_id     BIGINT UNSIGNED NOT NULL,
    total       DECIMAL(12,2) NOT NULL,
    status      ENUM('pending','paid','shipped','delivered','cancelled'),
    created_at  DATETIME(3) DEFAULT CURRENT_TIMESTAMP(3),
    PRIMARY KEY (id, created_at),  -- Include partition key in PK
    INDEX idx_user_id (user_id),
    INDEX idx_status_date (status, created_at)
) ENGINE=InnoDB
PARTITION BY RANGE (YEAR(created_at)) (
    PARTITION p2023 VALUES LESS THAN (2024),
    PARTITION p2024 VALUES LESS THAN (2025),
    PARTITION p2025 VALUES LESS THAN (2026),
    PARTITION pmax  VALUES LESS THAN MAXVALUE
);

-- Inventory with optimistic locking
CREATE TABLE inventory (
    product_id  BIGINT UNSIGNED PRIMARY KEY,
    quantity    INT UNSIGNED NOT NULL DEFAULT 0,
    version     INT UNSIGNED NOT NULL DEFAULT 0,  -- Optimistic lock
    updated_at  DATETIME(3) ON UPDATE CURRENT_TIMESTAMP(3)
) ENGINE=InnoDB;

-- Atomic inventory decrement (prevents overselling)
UPDATE inventory
SET quantity = quantity - 1, version = version + 1
WHERE product_id = 123
  AND quantity >= 1
  AND version = 5;  -- Must match expected version
-- If 0 rows affected → concurrent update, retry
```

---

## High Availability Patterns

```sql
-- ProxySQL for automatic failover and load balancing
-- Routes reads to replicas, writes to primary
-- Handles failover transparently

-- Health check query (ProxySQL uses this)
SELECT 1;

-- Monitor replication lag
SELECT
    MEMBER_HOST,
    MEMBER_STATE,
    MEMBER_ROLE
FROM performance_schema.replication_group_members;

-- Check for long-running queries (blocking others)
SELECT
    id, user, host, db,
    time, state, info
FROM information_schema.processlist
WHERE command != 'Sleep'
  AND time > 30
ORDER BY time DESC;

-- Kill blocking query
KILL QUERY 12345;
```

---

## Interview Q&A

### Q1: How do you handle database migrations with zero downtime?
1. **Backward-compatible changes first**: Add new column as nullable, deploy code that works with both old and new schema
2. **Backfill data**: Populate new column in background (small batches to avoid locking)
3. **Deploy new code**: Switch to using new column
4. **Cleanup**: Add NOT NULL constraint, drop old column
Tools: Flyway, Liquibase, gh-ost (for large table alterations without locking)

### Q2: What is the difference between optimistic and pessimistic locking?
**Pessimistic**: Lock the row before reading (`SELECT ... FOR UPDATE`). Prevents concurrent modifications. Use for: high contention, financial transactions. Downside: reduces throughput.
**Optimistic**: No lock on read. Check version on update. If version changed, retry. Use for: low contention, read-heavy workloads. Downside: retry logic needed.

### Q3: When would you choose MySQL over PostgreSQL?
**MySQL**: Better for read-heavy workloads, simpler replication setup, slightly faster for simple queries, better ecosystem for web apps (LAMP stack), InnoDB is excellent for OLTP.
**PostgreSQL**: Better for complex queries, JSON support, full-text search, advanced indexing (GIN, GiST), ACID compliance is stricter, better for analytics.
For most web apps: either works. MySQL has a slight edge for pure OLTP; PostgreSQL for complex data needs.
