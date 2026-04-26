# 05 — Large-Scale Database Design

## Scaling Strategies

### Vertical Scaling (Scale Up)
- Add more CPU, RAM, faster storage to the same server
- Simplest approach — no application changes
- Limited by hardware ceiling and cost
- Single point of failure

### Horizontal Scaling (Scale Out)
- Add more servers
- Requires application-level changes
- Theoretically unlimited scale
- More complex to manage

---

## Read Replicas

Route read queries to replicas, writes to primary:

```
Application
    ├── Writes → Primary
    └── Reads  → Replica 1, Replica 2, Replica 3
```

**Implementation**:
- Use a connection pool/proxy (ProxySQL, MySQL Router) to route queries
- Application must tolerate **replication lag** for reads
- Use `SELECT ... FOR UPDATE` on primary for consistency-critical reads

**ProxySQL routing rules**:
```sql
-- Route SELECTs to replicas, writes to primary
INSERT INTO mysql_query_rules (rule_id, active, match_pattern, destination_hostgroup)
VALUES (1, 1, '^SELECT', 2),   -- hostgroup 2 = replicas
       (2, 1, '.*',      1);   -- hostgroup 1 = primary
```

---

## Sharding

Horizontal partitioning across multiple database servers.

### Sharding Strategies

**Range-based sharding**:
```
Shard 1: user_id 1–1,000,000
Shard 2: user_id 1,000,001–2,000,000
```
- Simple, supports range queries
- Risk: hot shards (uneven distribution)

**Hash-based sharding**:
```
shard = hash(user_id) % num_shards
```
- Even distribution
- Range queries require scatter-gather across all shards

**Directory-based sharding**:
- Lookup table maps entity → shard
- Flexible, supports resharding
- Lookup table is a bottleneck/SPOF

### Cross-Shard Challenges
- **JOINs**: must be done in application layer
- **Transactions**: no cross-shard ACID (use saga pattern or 2PC)
- **Aggregations**: scatter-gather, then merge in application
- **Resharding**: complex, requires data migration

---

## Caching Strategies

### Query Result Cache (Application-Level)
```
Application → Redis/Memcached → MySQL (on cache miss)
```

Cache invalidation strategies:
- **TTL-based**: expire after N seconds (simple, may serve stale data)
- **Write-through**: update cache on every write (consistent, write overhead)
- **Cache-aside**: application manages cache explicitly

### Read-Through Cache
```sql
-- Application pseudocode:
result = cache.get(key)
if result is None:
    result = db.query(sql)
    cache.set(key, result, ttl=300)
return result
```

---

## Connection Pooling

Each MySQL connection uses ~1MB RAM and a thread. At 1000 connections = 1GB RAM just for connections.

**PgBouncer equivalent for MySQL**: ProxySQL, MySQL Router, Vitess

```
Application Servers (100 instances × 10 connections = 1000)
    ↓
ProxySQL (connection pool: 50 connections to MySQL)
    ↓
MySQL Primary (50 connections)
```

---

## Schema Design for Scale

### Avoid Wide Rows
- Fewer columns per table = smaller rows = more rows per page = better cache efficiency
- Split rarely-used columns into a separate table (vertical partitioning)

### Use Surrogate Keys
- INT AUTO_INCREMENT or BIGINT for PKs
- Avoid natural keys (email, phone) as PKs — they change and are wide

### Soft Deletes
```sql
-- Instead of DELETE:
ALTER TABLE users ADD COLUMN deleted_at DATETIME NULL;
UPDATE users SET deleted_at = NOW() WHERE user_id = 123;
-- Query: WHERE deleted_at IS NULL
-- Add partial index: INDEX idx_active (deleted_at) WHERE deleted_at IS NULL
```

### Audit Columns
```sql
-- Every table should have:
created_at  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
updated_at  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
created_by  INT,
updated_by  INT
```

---

## MySQL at Scale: Key Settings

```ini
[mysqld]
# Memory
innodb_buffer_pool_size = 48G          # 75% of 64GB RAM
innodb_buffer_pool_instances = 16      # 1 per 3GB
innodb_log_file_size = 2G              # large redo log
innodb_log_buffer_size = 64M

# I/O
innodb_flush_method = O_DIRECT         # avoid OS double buffering
innodb_io_capacity = 4000              # SSD IOPS
innodb_io_capacity_max = 8000
innodb_read_io_threads = 8
innodb_write_io_threads = 8

# Connections
max_connections = 500
thread_cache_size = 50

# Replication
binlog_format = ROW
sync_binlog = 1                        # fsync binlog on every commit
innodb_flush_log_at_trx_commit = 1    # fully durable

# Query
slow_query_log = ON
long_query_time = 0.1
log_queries_not_using_indexes = ON
```

---

## Interview Q&A

**Q: How would you scale a MySQL database that's hitting its write limits?**
A: Options in order of complexity: (1) Optimize queries and indexes — often the first bottleneck. (2) Upgrade hardware (faster NVMe, more RAM for buffer pool). (3) Shard the database — partition data across multiple servers by a shard key. (4) Use a distributed SQL database (Vitess, TiDB) that handles sharding transparently.

**Q: What are the trade-offs of sharding?**
A: Benefits: horizontal write scalability, data isolation. Costs: no cross-shard JOINs (must be done in application), no cross-shard transactions (need saga/2PC), complex resharding when adding shards, scatter-gather for aggregations, increased operational complexity.

**Q: How do you handle cache invalidation in a read-heavy system?**
A: Common strategies: TTL-based (simple, tolerates some staleness), write-through (update cache on every write — consistent but adds write latency), event-driven invalidation (publish change events, consumers invalidate cache). The right choice depends on acceptable staleness and write frequency.

**Q: What is connection pooling and why is it important?**
A: Each MySQL connection consumes ~1MB RAM and a thread. Without pooling, 1000 app server connections = 1000 MySQL threads = 1GB RAM just for connections. A connection pool (ProxySQL, MySQL Router) maintains a smaller pool of persistent connections to MySQL and multiplexes many application connections through them.

**Q: How do you design a schema for a multi-tenant SaaS application?**
A: Three approaches: (1) Shared schema — all tenants in same tables with tenant_id column (simplest, cheapest, but noisy neighbor risk). (2) Separate schema per tenant — each tenant has their own database (better isolation, harder to query across tenants). (3) Separate server per tenant (maximum isolation, most expensive). Most SaaS apps start with shared schema + tenant_id and migrate to separate schemas for large/enterprise customers.
