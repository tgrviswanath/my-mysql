# 03 — Indexing Deep Dive

## Composite Indexes

A composite (multi-column) index covers multiple columns in a defined order.

```sql
ALTER TABLE orders ADD INDEX idx_customer_status_date (customer_id, status, created_at);
```

### Leftmost Prefix Rule
The optimizer can use a composite index for queries that match a **prefix** of the index columns:

| Query | Uses Index? |
|-------|-------------|
| `WHERE customer_id = 1` | ✅ (prefix: customer_id) |
| `WHERE customer_id = 1 AND status = 'paid'` | ✅ (prefix: customer_id, status) |
| `WHERE customer_id = 1 AND status = 'paid' AND created_at > '2024-01-01'` | ✅ (full index) |
| `WHERE status = 'paid'` | ❌ (not leftmost) |
| `WHERE customer_id = 1 AND created_at > '2024-01-01'` | ⚠️ (partial: only customer_id used for index, created_at filtered in memory) |

### Column Order Strategy
1. **Equality columns first** (=), then **range columns** (>, <, BETWEEN)
2. **High cardinality columns first** for better filtering
3. **ORDER BY columns** at the end to avoid filesort

---

## Covering Indexes

A covering index includes all columns referenced in a query:
- SELECT columns
- WHERE columns
- ORDER BY columns
- GROUP BY columns

```sql
-- Query:
SELECT user_id, email FROM users WHERE status = 'active' AND country = 'US' ORDER BY created_at;

-- Covering index:
ALTER TABLE users ADD INDEX idx_cover (status, country, created_at, user_id, email);
-- EXPLAIN Extra: "Using index" — no table access needed
```

---

## Index Merge

MySQL can use multiple indexes on the same table and merge results:

```sql
-- Two separate indexes: idx_status, idx_country
SELECT * FROM users WHERE status = 'active' OR country = 'US';
-- EXPLAIN type=index_merge, Extra=Using union(idx_status, idx_country)
```

Index merge is often less efficient than a single composite index — prefer composite.

---

## Prefix Indexes

For long string columns, index only the first N characters:

```sql
ALTER TABLE users ADD INDEX idx_email_prefix (email(20));
```

- Saves index space
- Loses full selectivity (can't be a covering index)
- Can't be used for ORDER BY

Calculate optimal prefix length:
```sql
SELECT
    COUNT(DISTINCT LEFT(email, 10)) / COUNT(*) AS sel_10,
    COUNT(DISTINCT LEFT(email, 20)) / COUNT(*) AS sel_20,
    COUNT(DISTINCT email)           / COUNT(*) AS sel_full
FROM users;
-- Choose prefix where selectivity approaches full selectivity
```

---

## Invisible Indexes (MySQL 8.0+)

Test removing an index without actually dropping it:

```sql
ALTER TABLE users ALTER INDEX idx_status INVISIBLE;
-- Optimizer ignores it, but it's still maintained
-- Test query performance, then:
ALTER TABLE users ALTER INDEX idx_status VISIBLE;  -- restore
-- Or:
DROP INDEX idx_status ON users;  -- if confirmed unused
```

---

## Functional Indexes (MySQL 8.0.13+)

Index on an expression:

```sql
ALTER TABLE users ADD INDEX idx_email_lower ((LOWER(email)));
-- Now this query uses the index:
SELECT * FROM users WHERE LOWER(email) = 'alice@example.com';
```

---

## Index Condition Pushdown (ICP)

MySQL 5.6+ optimization: evaluate WHERE conditions using index columns **before** accessing the table row.

```sql
-- Without ICP: fetch row, then apply WHERE
-- With ICP: apply WHERE on index, only fetch matching rows
EXPLAIN SELECT * FROM users WHERE status = 'active' AND username LIKE 'user1%';
-- Extra: "Using index condition" → ICP active
```

---

## Index Statistics & Maintenance

```sql
-- Update statistics (important after bulk loads)
ANALYZE TABLE users;

-- Check fragmentation
SELECT TABLE_NAME, DATA_FREE, DATA_LENGTH
FROM information_schema.TABLES
WHERE TABLE_SCHEMA = 'practice_db';

-- Rebuild index (defragment)
ALTER TABLE users ENGINE=InnoDB;  -- rebuilds all indexes
-- Or:
OPTIMIZE TABLE users;
```

---

## Interview Q&A

**Q: What is the leftmost prefix rule for composite indexes?**
A: MySQL can use a composite index only if the query's WHERE clause includes the leftmost column(s) of the index. For index (a, b, c): queries on (a), (a,b), or (a,b,c) can use the index. Queries on (b), (c), or (b,c) cannot use the index.

**Q: How do you design a composite index for a query with both equality and range conditions?**
A: Put equality columns first, range columns last. For `WHERE status = 'active' AND created_at > '2024-01-01'`, use index (status, created_at). The optimizer uses status for equality lookup, then created_at for range scan within the matching status rows.

**Q: What is a covering index and how do you identify one in EXPLAIN?**
A: A covering index includes all columns needed by the query. EXPLAIN shows `Extra: Using index` — meaning MySQL reads only the index B-Tree without accessing the table. This eliminates the secondary index "double lookup" and reduces I/O.

**Q: What is Index Condition Pushdown (ICP)?**
A: ICP allows MySQL to evaluate WHERE conditions that use index columns before fetching the full row from the table. Without ICP, MySQL fetches the row first, then applies the WHERE. With ICP, non-matching rows are filtered at the index level, reducing table I/O.

**Q: When would you use a prefix index and what are its limitations?**
A: Use prefix indexes for long string columns (URLs, emails) to reduce index size. Limitations: can't be used as a covering index (doesn't store full value), can't be used for ORDER BY, and has lower selectivity than a full-column index.
