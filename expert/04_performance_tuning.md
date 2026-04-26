# 04 — Performance Tuning

## Tuning Methodology

1. **Identify**: Find slow queries (slow query log, performance_schema)
2. **Analyze**: EXPLAIN / EXPLAIN ANALYZE the query
3. **Fix**: Add indexes, rewrite query, tune configuration
4. **Verify**: Confirm improvement with EXPLAIN ANALYZE and metrics
5. **Monitor**: Watch for regressions

---

## Slow Query Log

```ini
[mysqld]
slow_query_log = ON
long_query_time = 0.1          # log queries > 100ms
log_queries_not_using_indexes = ON
slow_query_log_file = /var/log/mysql/slow.log
```

Analyze with `mysqldumpslow`:
```bash
mysqldumpslow -s t -t 10 /var/log/mysql/slow.log  # top 10 by total time
mysqldumpslow -s c -t 10 /var/log/mysql/slow.log  # top 10 by count
```

Or use `pt-query-digest` (Percona Toolkit) for detailed analysis.

---

## Key InnoDB Variables

| Variable | Recommended | Notes |
|----------|-------------|-------|
| `innodb_buffer_pool_size` | 70–80% of RAM | Most impactful setting |
| `innodb_buffer_pool_instances` | 1 per GB (max 64) | Reduces contention |
| `innodb_log_file_size` | 1–4 GB | Larger = fewer checkpoints |
| `innodb_flush_method` | `O_DIRECT` | Avoids OS double buffering |
| `innodb_io_capacity` | SSD: 2000–10000 | Match your storage IOPS |
| `innodb_flush_log_at_trx_commit` | `1` (safe) or `2` (fast) | Durability vs performance |
| `sync_binlog` | `1` (safe) or `0` (fast) | Binlog durability |

---

## Connection Tuning

```ini
max_connections = 500           # based on RAM and workload
thread_cache_size = 50          # reuse threads
wait_timeout = 600              # close idle connections after 10 min
interactive_timeout = 600
```

Monitor:
```sql
SHOW STATUS LIKE 'Threads_connected';
SHOW STATUS LIKE 'Threads_running';
SHOW STATUS LIKE 'Connection_errors_max_connections';  -- > 0 = too low
```

---

## Query Cache (Removed in MySQL 8.0)

The query cache was a global mutex-protected hash map. Under concurrency it became a bottleneck. It was deprecated in MySQL 5.7 and removed in 8.0.

**Alternative**: Application-level caching with Redis or Memcached.

---

## Performance Schema

Key tables:
- `events_statements_summary_by_digest`: query performance aggregated by fingerprint
- `table_io_waits_summary_by_table`: I/O per table
- `table_io_waits_summary_by_index_usage`: index usage statistics
- `memory_summary_global_by_event_name`: memory usage

---

## sys Schema

Human-readable views over performance_schema:
- `sys.statement_analysis`: top queries by latency
- `sys.schema_tables_with_full_table_scans`: tables with full scans
- `sys.schema_redundant_indexes`: duplicate/redundant indexes
- `sys.schema_unused_indexes`: indexes never used
- `sys.memory_global_by_current_bytes`: memory usage

---

## Interview Q&A

**Q: What is the most important MySQL configuration setting and why?**
A: `innodb_buffer_pool_size`. The buffer pool caches all data and index pages. If it's too small, MySQL constantly reads from disk (slow). Setting it to 70–80% of available RAM maximizes cache hits. The buffer pool hit ratio (target >99%) measures effectiveness.

**Q: How do you find the slowest queries in production?**
A: Enable the slow query log (`slow_query_log=ON`, `long_query_time=0.1`). Analyze with `mysqldumpslow` or `pt-query-digest`. Alternatively, query `performance_schema.events_statements_summary_by_digest` ordered by `SUM_TIMER_WAIT` for real-time analysis without log files.

**Q: What is `innodb_flush_log_at_trx_commit` and what are the trade-offs?**
A: Controls when the redo log is fsynced to disk. Value 1 (default): fsync on every commit — fully durable, slowest. Value 2: write to OS buffer on commit, fsync every second — risk of 1 second of data loss on OS crash, much faster. Value 0: write to log buffer, fsync every second — risk of 1 second loss on MySQL crash.

**Q: What is the history list length and why does it matter?**
A: The history list length is the number of undo log records waiting to be purged. It grows when long-running transactions prevent the purge thread from cleaning up old row versions. A high value (>1000) indicates MVCC bloat — old row versions accumulate, increasing table size and slowing reads. Fix: identify and terminate long-running transactions.

**Q: How do you identify unused indexes?**
A: Query `performance_schema.table_io_waits_summary_by_index_usage` where `count_star = 0` and `index_name != 'PRIMARY'`. Or use `sys.schema_unused_indexes`. Unused indexes waste storage and slow down writes without benefiting reads. Use invisible indexes to test removal before dropping.
