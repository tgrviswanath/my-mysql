# 05 — Partitioning

## What is Partitioning?

Partitioning divides a large table into smaller, physically separate segments called **partitions**, while appearing as a single table to queries.

Benefits:
- **Partition pruning**: queries only scan relevant partitions
- **Faster maintenance**: drop/archive old partitions instantly (vs row-by-row DELETE)
- **Parallel I/O**: partitions can be on different disks

---

## Partition Types

### RANGE
Partitions based on column value ranges. Best for time-series data.
```sql
PARTITION BY RANGE (YEAR(created_at)) (
    PARTITION p2023 VALUES LESS THAN (2024),
    PARTITION p2024 VALUES LESS THAN (2025),
    PARTITION p_future VALUES LESS THAN MAXVALUE
)
```

### LIST
Partitions based on discrete values. Best for categorical data.
```sql
PARTITION BY LIST COLUMNS (region) (
    PARTITION p_us VALUES IN ('US', 'CA'),
    PARTITION p_eu VALUES IN ('UK', 'DE', 'FR')
)
```

### HASH
Distributes rows evenly using a hash function. Best for even distribution.
```sql
PARTITION BY HASH (user_id) PARTITIONS 8
```

### KEY
Like HASH but MySQL manages the hash function. Works with non-integer columns.
```sql
PARTITION BY KEY (email) PARTITIONS 4
```

---

## Partition Pruning

The optimizer eliminates irrelevant partitions from the query plan.

```sql
-- Only scans p2024 partition:
SELECT * FROM events WHERE created_at >= '2024-01-01' AND created_at < '2025-01-01';
-- EXPLAIN shows: partitions=p2024
```

Pruning works when:
- WHERE clause uses the partition key directly
- No function wrapping the partition key: `WHERE YEAR(col) = 2024` may not prune

---

## Partition Maintenance

```sql
-- Add new partition (reorganize MAXVALUE partition)
ALTER TABLE events REORGANIZE PARTITION p_future INTO (
    PARTITION p2025 VALUES LESS THAN (2026),
    PARTITION p_future VALUES LESS THAN MAXVALUE
);

-- Drop old partition (instant — no row-by-row delete)
ALTER TABLE events DROP PARTITION p2022;

-- Truncate a partition (faster than DELETE)
ALTER TABLE events TRUNCATE PARTITION p2022;

-- Exchange partition with a regular table (for archiving)
ALTER TABLE events EXCHANGE PARTITION p2022 WITH TABLE events_archive_2022;
```

---

## Limitations

- Partition key must be part of every UNIQUE index (including PRIMARY KEY)
- Foreign keys are not supported on partitioned tables
- Full-text indexes not supported on partitioned tables
- Maximum 8192 partitions per table (MySQL 8.0+)
- Queries not using the partition key scan all partitions

---

## Performance Considerations

- Partition pruning is the primary benefit — design partition key around your most common WHERE filters
- Too many partitions (> 100) can slow down queries that scan all partitions
- RANGE partitioning on date columns is the most common and effective use case
- For OLTP: partitioning is often unnecessary if indexes are well-designed
- For OLAP/archiving: partitioning by date enables instant data lifecycle management

---

## Interview Q&A

**Q: What is partition pruning and when does it occur?**
A: Partition pruning is the optimizer's ability to skip irrelevant partitions. It occurs when the WHERE clause includes a condition on the partition key that allows the optimizer to determine which partitions could contain matching rows. For RANGE partitioning on date, `WHERE created_at >= '2024-01-01'` prunes all partitions before 2024.

**Q: What is the main limitation of partitioned tables regarding indexes?**
A: The partition key must be included in every UNIQUE index (including the PRIMARY KEY). This means you can't have a simple `AUTO_INCREMENT` primary key on a partitioned table without including the partition key in the PK — you need a composite PK like `(id, created_at)`.

**Q: How do you archive old data efficiently with partitioning?**
A: Use RANGE partitioning by date. When data ages out, use `ALTER TABLE DROP PARTITION p_old` — this is an instant metadata operation that removes the entire partition without row-by-row deletion. Alternatively, use `EXCHANGE PARTITION` to swap the old partition with an archive table.

**Q: When would you NOT use partitioning?**
A: When queries don't filter on the partition key (all partitions are scanned — worse than no partitioning). When the table is small enough to fit in the buffer pool. When you need foreign keys. When the overhead of managing partitions outweighs the benefits.
