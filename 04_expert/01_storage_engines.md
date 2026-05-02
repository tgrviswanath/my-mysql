# 01 — InnoDB Storage Engine Internals

## InnoDB Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    InnoDB Memory                         │
│  ┌──────────────────────────────────────────────────┐   │
│  │              Buffer Pool                          │   │
│  │  ┌──────────┐ ┌──────────┐ ┌──────────────────┐  │   │
│  │  │Data Pages│ │Index Pages│ │Insert Buffer     │  │   │
│  │  └──────────┘ └──────────┘ └──────────────────┘  │   │
│  └──────────────────────────────────────────────────┘   │
│  ┌────────────┐  ┌──────────────┐  ┌────────────────┐   │
│  │ Log Buffer │  │Adaptive Hash │  │ Change Buffer  │   │
│  └────────────┘  └──────────────┘  └────────────────┘   │
├─────────────────────────────────────────────────────────┤
│                    InnoDB Disk                           │
│  ┌──────────────┐  ┌──────────┐  ┌──────────────────┐   │
│  │  Tablespace  │  │Redo Logs │  │   Undo Logs      │   │
│  │  (.ibd files)│  │(ib_logfile)│ │(undo tablespace) │   │
│  └──────────────┘  └──────────┘  └──────────────────┘   │
└─────────────────────────────────────────────────────────┘
```

---

## Buffer Pool

The most critical InnoDB component. Caches data pages and index pages in memory.

- Default size: 128MB — **set to 70–80% of available RAM**
- Organized as a **LRU list** with a "midpoint insertion" strategy
- New pages inserted at the midpoint (3/8 from tail) to protect hot pages from full scans
- **Dirty pages**: modified pages not yet flushed to disk
- Background threads flush dirty pages to disk (checkpoint)

```sql
-- Key settings
SHOW VARIABLES LIKE 'innodb_buffer_pool_size';
SHOW VARIABLES LIKE 'innodb_buffer_pool_instances';  -- parallel pools (default: 8 if > 1GB)

-- Buffer pool hit ratio (target > 99%)
SELECT
    (1 - Innodb_buffer_pool_reads / Innodb_buffer_pool_read_requests) * 100 AS hit_ratio_pct
FROM (
    SELECT
        VARIABLE_VALUE AS Innodb_buffer_pool_reads
    FROM performance_schema.global_status WHERE VARIABLE_NAME = 'Innodb_buffer_pool_reads'
) r,
(
    SELECT VARIABLE_VALUE AS Innodb_buffer_pool_read_requests
    FROM performance_schema.global_status WHERE VARIABLE_NAME = 'Innodb_buffer_pool_read_requests'
) rr;
```

---

## Redo Log (Write-Ahead Log)

Ensures **durability** (the D in ACID).

- All changes are written to the redo log **before** being applied to data pages
- On crash: MySQL replays the redo log to recover committed transactions
- Circular log files: `ib_logfile0`, `ib_logfile1` (MySQL 8.0.30+: `#ib_redo*`)

```sql
SHOW VARIABLES LIKE 'innodb_log_file_size';       -- size of each log file
SHOW VARIABLES LIKE 'innodb_log_files_in_group';  -- number of log files
-- Total redo log capacity = log_file_size × log_files_in_group
-- Larger redo log = fewer checkpoints = better write throughput
```

**`innodb_flush_log_at_trx_commit`**:
- `1` (default): fsync on every commit — fully durable, slowest
- `2`: write to OS buffer on commit, fsync every second — risk: 1s data loss on OS crash
- `0`: write to log buffer, fsync every second — risk: 1s data loss on MySQL crash

---

## Undo Log

Enables **atomicity** (rollback) and **MVCC** (consistent reads).

- Stores the **before-image** of modified rows
- On rollback: undo log reverses changes
- For MVCC: older transactions read historical versions via undo log chain
- Purge thread cleans up undo logs when no transaction needs them

---

## MVCC (Multi-Version Concurrency Control)

Each InnoDB row has hidden system columns:
- `DB_TRX_ID` (6 bytes): ID of the last transaction that modified the row
- `DB_ROLL_PTR` (7 bytes): pointer to undo log record for previous version
- `DB_ROW_ID` (6 bytes): auto-generated row ID if no PK

**Read View**: snapshot of active transactions at the time a consistent read starts.
- A row version is visible if `DB_TRX_ID < min_active_trx_id` OR `DB_TRX_ID` is the current transaction
- If not visible: follow `DB_ROLL_PTR` to find an older visible version

---

## Change Buffer

Caches changes to **secondary index pages** that are not in the buffer pool.

- Avoids random I/O for secondary index updates
- Merged into the buffer pool when the page is later read
- Only for non-unique secondary indexes (unique indexes require immediate consistency check)

```sql
SHOW VARIABLES LIKE 'innodb_change_buffer_max_size';  -- % of buffer pool (default 25%)
```

---

## Adaptive Hash Index (AHI)

InnoDB automatically builds a hash index on frequently accessed B-Tree index pages.

- Provides O(1) lookup for hot pages (vs O(log n) for B-Tree)
- Built and managed automatically — no user control over which pages
- Can be disabled: `innodb_adaptive_hash_index=OFF` (if causing contention)

---

## Page Structure

InnoDB stores data in **16KB pages** (default):
- Page header (38 bytes)
- Infimum/Supremum records (virtual boundary records)
- User records (actual row data)
- Free space
- Page directory (slot array for binary search)
- Page trailer (checksum)

```sql
SHOW VARIABLES LIKE 'innodb_page_size';  -- default 16384 (16KB)
```

---

## Interview Q&A

**Q: What is the InnoDB buffer pool and why is it the most important setting?**
A: The buffer pool is InnoDB's main memory cache for data and index pages. All reads and writes go through it. A larger buffer pool means more data fits in memory, reducing disk I/O. It should be set to 70–80% of available RAM. The buffer pool hit ratio (target >99%) measures how often reads are served from memory vs disk.

**Q: How does InnoDB ensure durability on crash?**
A: InnoDB uses Write-Ahead Logging (WAL). All changes are written to the redo log before being applied to data pages. On crash recovery, MySQL replays the redo log to restore all committed transactions. `innodb_flush_log_at_trx_commit=1` ensures the redo log is fsynced to disk on every commit.

**Q: What is the difference between redo log and undo log?**
A: Redo log records the after-image of changes for crash recovery (durability). Undo log records the before-image of changes for rollback (atomicity) and MVCC (consistent reads). Redo log is append-only and circular; undo log is maintained per transaction and purged when no longer needed.

**Q: How does MVCC work in InnoDB?**
A: Each row has hidden columns: DB_TRX_ID (last modifying transaction) and DB_ROLL_PTR (pointer to undo log). When a transaction reads a row, it checks if the row's DB_TRX_ID is visible in its read view. If not (modified by a newer transaction), it follows DB_ROLL_PTR to find an older visible version in the undo log. This allows non-locking reads.

**Q: What is the Change Buffer and when is it beneficial?**
A: The Change Buffer caches modifications to secondary index pages that aren't currently in the buffer pool, avoiding random I/O. It's beneficial for write-heavy workloads with many secondary indexes. It's only used for non-unique indexes (unique indexes require immediate consistency checks). Changes are merged when the page is later read into the buffer pool.
