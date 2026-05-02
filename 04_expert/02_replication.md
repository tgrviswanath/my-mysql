# 02 — MySQL Replication

## Replication Overview

MySQL replication copies data from a **source** (primary) to one or more **replicas** (secondaries).

Use cases:
- **Read scaling**: route read queries to replicas
- **High availability**: failover to replica on primary failure
- **Backup**: take backups from replica without impacting primary
- **Analytics**: run heavy queries on replica

---

## How Replication Works

```
Source                          Replica
──────                          ───────
1. Transaction commits
2. Write to binary log (binlog)
                    ──────────────────→
                                3. I/O thread reads binlog
                                4. Write to relay log
                                5. SQL thread replays relay log
                                6. Apply changes to replica
```

### Binary Log (binlog)
Records all changes to the database:
- `ROW` format: logs actual row changes (most reliable, larger)
- `STATEMENT` format: logs SQL statements (smaller, but non-deterministic functions are risky)
- `MIXED` format: uses STATEMENT by default, ROW for non-deterministic operations

```sql
SHOW VARIABLES LIKE 'binlog_format';
SHOW BINARY LOGS;
SHOW BINLOG EVENTS IN 'binlog.000001' LIMIT 20;
```

---

## Asynchronous Replication (Default)

- Source commits transaction and returns to client **without waiting** for replica acknowledgment
- Replica may lag behind source
- Risk: data loss on source failure if replica hasn't caught up

---

## Semi-Synchronous Replication

- Source waits for **at least one replica** to acknowledge receipt of binlog events before returning to client
- Reduces data loss risk (replica has the data, but may not have applied it)
- Adds latency to writes

```sql
-- Enable on source
INSTALL PLUGIN rpl_semi_sync_source SONAME 'semisync_source.so';
SET GLOBAL rpl_semi_sync_source_enabled = 1;

-- Enable on replica
INSTALL PLUGIN rpl_semi_sync_replica SONAME 'semisync_replica.so';
SET GLOBAL rpl_semi_sync_replica_enabled = 1;
```

---

## GTID-Based Replication (MySQL 5.6+)

**Global Transaction Identifier**: unique ID for every transaction across the cluster.

Format: `source_uuid:transaction_id` (e.g., `3E11FA47-71CA-11E1-9E33-C80AA9429562:1-100`)

Benefits over file/position-based replication:
- Replicas can automatically find their position in the binlog
- Easier failover — no need to find binlog file + position
- Prevents duplicate transactions

```sql
-- Enable GTID
SET GLOBAL gtid_mode = ON;
SET GLOBAL enforce_gtid_consistency = ON;

-- Check GTID status
SHOW VARIABLES LIKE 'gtid_mode';
SELECT @@global.gtid_executed;  -- all committed GTIDs
SELECT @@global.gtid_purged;    -- purged GTIDs
```

---

## Setting Up Replication

### On Source:
```sql
-- my.cnf
[mysqld]
server-id = 1
log_bin = /var/log/mysql/binlog
binlog_format = ROW
gtid_mode = ON
enforce_gtid_consistency = ON

-- Create replication user
CREATE USER 'repl'@'%' IDENTIFIED BY 'strong_password';
GRANT REPLICATION SLAVE ON *.* TO 'repl'@'%';
FLUSH PRIVILEGES;
```

### On Replica:
```sql
-- my.cnf
[mysqld]
server-id = 2
relay_log = /var/log/mysql/relay-bin
read_only = ON
gtid_mode = ON
enforce_gtid_consistency = ON

-- Configure replication
CHANGE REPLICATION SOURCE TO
    SOURCE_HOST = '192.168.1.100',
    SOURCE_USER = 'repl',
    SOURCE_PASSWORD = 'strong_password',
    SOURCE_AUTO_POSITION = 1;  -- GTID-based

START REPLICA;
SHOW REPLICA STATUS\G
```

---

## Replication Lag

Replica lag = time difference between source commit and replica apply.

Causes:
- Single-threaded SQL thread (pre-MySQL 5.7)
- Heavy write load on source
- Long-running queries on replica

Solutions:
- **Multi-threaded replication** (MySQL 5.7+): parallel SQL threads per schema or transaction
- `replica_parallel_workers = 4` (or more)
- `replica_parallel_type = LOGICAL_CLOCK` (MySQL 5.7+)

```sql
-- Check replica lag
SHOW REPLICA STATUS\G
-- Look for: Seconds_Behind_Source

-- Enable parallel replication
SET GLOBAL replica_parallel_workers = 4;
SET GLOBAL replica_parallel_type = 'LOGICAL_CLOCK';
```

---

## Group Replication (MySQL 5.7.17+)

Multi-primary or single-primary replication with:
- Automatic failover
- Conflict detection and resolution
- Distributed recovery

Basis for **MySQL InnoDB Cluster** (with MySQL Shell + MySQL Router).

---

## Interview Q&A

**Q: What is the difference between asynchronous and semi-synchronous replication?**
A: Asynchronous replication: source commits and returns to client immediately, without waiting for replica acknowledgment. Risk: data loss if source fails before replica receives the binlog. Semi-synchronous: source waits for at least one replica to acknowledge receipt before returning. Reduces data loss risk but adds write latency.

**Q: What is GTID and why is it preferred over file/position-based replication?**
A: GTID (Global Transaction Identifier) assigns a unique ID to every transaction. Replicas track which GTIDs they've applied, so they can automatically find their position in the binlog without needing the file name and position. This simplifies failover — a new primary just needs to know which GTIDs the replica has applied.

**Q: What causes replication lag and how do you fix it?**
A: Causes: single-threaded SQL thread can't keep up with source write rate, long-running queries on replica, or network latency. Fix: enable multi-threaded replication (`replica_parallel_workers > 1`), use `LOGICAL_CLOCK` parallelism, avoid long-running queries on replica, or upgrade hardware.

**Q: What is the difference between ROW and STATEMENT binlog formats?**
A: STATEMENT logs the SQL statement — compact but risky for non-deterministic functions (NOW(), RAND(), UUID()). ROW logs the actual before/after row values — larger but fully deterministic and safe. MIXED uses STATEMENT by default and switches to ROW for non-deterministic operations.

**Q: How do you handle a replica that has fallen behind by hours?**
A: Options: (1) Enable parallel replication to speed up catch-up. (2) Stop the replica, take a fresh snapshot from the source (mysqldump or xtrabackup), restore it, and restart replication. (3) Use `pt-slave-delay` to intentionally delay a replica for point-in-time recovery purposes.
