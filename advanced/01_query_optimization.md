# 01 — Query Optimization

## The Cost-Based Optimizer (CBO)

MySQL's optimizer evaluates multiple execution plans and selects the one with the **lowest estimated cost**.

Cost components:
- **I/O cost**: reading data pages from disk (most expensive)
- **CPU cost**: evaluating conditions, sorting, hashing
- **Memory cost**: join buffers, sort buffers

The optimizer uses **table statistics** to estimate costs:
- Row count (`TABLE_ROWS` in information_schema)
- Index cardinality (`CARDINALITY` in STATISTICS)
- Data distribution (histograms in MySQL 8.0+)

---

## EXPLAIN Output Fields

```sql
EXPLAIN SELECT e.name, d.name FROM emp e JOIN dept d ON e.dept_id = d.dept_id WHERE e.salary > 80000;
```

| Field | Meaning |
|-------|---------|
| id | Query block number (higher = executed first in subqueries) |
| select_type | SIMPLE, PRIMARY, SUBQUERY, DERIVED, UNION |
| table | Table being accessed |
| partitions | Partitions accessed |
| **type** | Join/access type (most important) |
| possible_keys | Indexes the optimizer considered |
| **key** | Index actually chosen |
| key_len | Bytes of index used (longer = more columns used) |
| ref | Column/constant compared to the index |
| **rows** | Estimated rows examined |
| filtered | % of rows passing WHERE after index |
| **Extra** | Additional info (Using index, Using filesort, etc.) |

### Access Types (type) — Best to Worst

| Type | Description |
|------|-------------|
| `system` | Single row table |
| `const` | PK or unique index with constant — single row |
| `eq_ref` | PK/unique index join — one row per outer row |
| `ref` | Non-unique index lookup |
| `range` | Index range scan (BETWEEN, >, <, IN) |
| `index` | Full index scan (better than ALL, still slow) |
| `ALL` | Full table scan — usually bad |

### Extra Values

| Extra | Meaning |
|-------|---------|
| `Using index` | Covering index — no table access ✅ |
| `Using where` | WHERE filter applied after index |
| `Using filesort` | Sort not satisfied by index ⚠️ |
| `Using temporary` | Temp table for GROUP BY/DISTINCT ⚠️ |
| `Using join buffer` | BNL join — no index on join column ⚠️ |
| `Impossible WHERE` | WHERE is always false |

---

## EXPLAIN ANALYZE (MySQL 8.0.18+)

Actually executes the query and shows real vs estimated metrics:

```sql
EXPLAIN ANALYZE SELECT * FROM emp WHERE salary > 80000;
```

Output includes:
- `actual time=X..Y` — actual start/end time
- `rows=N` — actual rows returned
- `loops=N` — how many times this node executed

---

## Optimization Techniques

### 1. Index Optimization
```sql
-- Bad: function prevents index use
WHERE DATE(created_at) = '2024-01-15'

-- Good: range scan uses index
WHERE created_at >= '2024-01-15' AND created_at < '2024-01-16'
```

### 2. Covering Index
```sql
-- Query only needs user_id, email, status
-- Create covering index:
ALTER TABLE users ADD INDEX idx_cover (status, user_id, email);
-- EXPLAIN shows: Extra = "Using index"
```

### 3. Query Rewriting
```sql
-- Bad: correlated subquery (N executions)
SELECT * FROM orders o
WHERE amount > (SELECT AVG(amount) FROM orders WHERE customer_id = o.customer_id);

-- Good: JOIN with derived table (1 execution)
SELECT o.* FROM orders o
JOIN (SELECT customer_id, AVG(amount) AS avg_amt FROM orders GROUP BY customer_id) AS ca
ON o.customer_id = ca.customer_id AND o.amount > ca.avg_amt;
```

### 4. Pagination Optimization
```sql
-- Bad: OFFSET 10000 scans and discards 10000 rows
SELECT * FROM orders ORDER BY order_id LIMIT 10 OFFSET 10000;

-- Good: keyset pagination (cursor-based)
SELECT * FROM orders WHERE order_id > 10000 ORDER BY order_id LIMIT 10;
```

### 5. COUNT Optimization
```sql
COUNT(*)     -- counts all rows (optimized by InnoDB for MyISAM)
COUNT(col)   -- counts non-NULL values (different result!)
COUNT(1)     -- same as COUNT(*) — no difference in MySQL
```

---

## Optimizer Hints (MySQL 8.0+)

```sql
-- Force index
SELECT /*+ INDEX(e idx_salary) */ * FROM emp e WHERE salary > 80000;

-- Disable hash join
SELECT /*+ NO_HASH_JOIN(e, d) */ e.name, d.name FROM emp e JOIN dept d ON e.dept_id = d.dept_id;

-- Set join order
SELECT /*+ JOIN_ORDER(d, e) */ e.name FROM emp e JOIN dept d ON e.dept_id = d.dept_id;
```

---

## Histograms (MySQL 8.0+)

Histograms provide data distribution statistics for non-indexed columns:

```sql
ANALYZE TABLE emp UPDATE HISTOGRAM ON salary, dept_id WITH 100 BUCKETS;
SELECT * FROM information_schema.COLUMN_STATISTICS WHERE TABLE_NAME = 'emp';
```

---

## Interview Q&A

**Q: What does "Using filesort" mean in EXPLAIN and how do you fix it?**
A: Filesort means MySQL couldn't use an index to satisfy the ORDER BY — it sorts the result set in memory (or on disk if too large). Fix by adding an index that matches the ORDER BY columns, or by ensuring the WHERE + ORDER BY columns are covered by a composite index.

**Q: What is the difference between `rows` and `filtered` in EXPLAIN?**
A: `rows` is the estimated number of rows MySQL will examine. `filtered` is the estimated percentage of those rows that will pass the WHERE condition. Actual rows returned ≈ rows × (filtered/100). Low filtered% means many rows are examined but few returned — a sign of poor index selectivity.

**Q: How does keyset pagination outperform OFFSET pagination?**
A: OFFSET N scans and discards N rows before returning results — O(N) work. Keyset pagination uses a WHERE clause on an indexed column (e.g., `WHERE id > last_seen_id`) — O(log N) index lookup. For page 1000 with 10 rows/page, OFFSET scans 10,000 rows; keyset scans 10.

**Q: When would you use EXPLAIN ANALYZE over EXPLAIN?**
A: EXPLAIN shows estimated metrics based on statistics. EXPLAIN ANALYZE actually executes the query and shows real metrics. Use EXPLAIN ANALYZE when estimates are wildly off (stale statistics, skewed data distribution) to see actual vs estimated row counts and timing.

**Q: What is a covering index and why is it beneficial?**
A: A covering index includes all columns needed by a query (SELECT list + WHERE + ORDER BY). MySQL can satisfy the query entirely from the index B-Tree without accessing the table data pages. This eliminates the "double lookup" for secondary indexes and reduces I/O significantly.
