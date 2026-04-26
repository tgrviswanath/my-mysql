# 03 — Indexes Basics

## What is an Index?

An index is a **separate data structure** that MySQL maintains alongside a table to speed up data retrieval. It trades **write overhead and storage** for **faster reads**.

Without an index: MySQL scans every row (full table scan) — O(n).
With an index: MySQL navigates a B-Tree — O(log n).

---

## B-Tree Index (Default)

InnoDB uses a **B+ Tree** (not B-Tree) for all standard indexes:
- All data stored in **leaf nodes**
- Leaf nodes are **doubly linked** → efficient range scans
- Internal nodes store only keys (routing)
- Tree height is typically 3–4 levels for millions of rows

```
                    [50]
                   /    \
            [20, 35]    [65, 80]
           /   |   \    /   |   \
         [10] [25] [40][55][70] [90]
          ↔    ↔    ↔   ↔   ↔    ↔   (linked leaf nodes)
```

**Supported operations**: =, <, >, <=, >=, BETWEEN, LIKE 'prefix%', IN

**Not supported**: LIKE '%suffix', functions on indexed column

---

## Index Types in MySQL

| Type | Use Case | Notes |
|------|----------|-------|
| PRIMARY KEY | Clustered index, row locator | One per table, InnoDB |
| UNIQUE | Enforce uniqueness | Allows NULL |
| INDEX (KEY) | Speed up queries | Non-unique |
| FULLTEXT | Text search | MATCH...AGAINST |
| SPATIAL | Geospatial data | GEOMETRY types |
| HASH | Exact lookups only | Memory engine only |

---

## Clustered vs Secondary Index

**Clustered Index (Primary Key)**:
- Table data is physically ordered by PK
- Leaf nodes contain the actual row data
- Only one per table

**Secondary Index**:
- Separate B-Tree structure
- Leaf nodes contain the **indexed column value + PK value**
- To fetch non-indexed columns: look up PK in clustered index ("double lookup")

```
Secondary Index Lookup:
  1. Search secondary B-Tree → find PK value
  2. Search clustered B-Tree → find full row
```

---

## Index Selectivity

Selectivity = number of distinct values / total rows.

- High selectivity (close to 1.0): good candidate for index (e.g., email, user_id)
- Low selectivity (close to 0): poor candidate (e.g., gender, boolean flags)

The optimizer uses **cardinality** (distinct values) from index statistics to estimate selectivity.

```sql
-- Check cardinality
SHOW INDEX FROM employees;
-- Or:
SELECT INDEX_NAME, CARDINALITY FROM information_schema.STATISTICS
WHERE TABLE_NAME = 'employees';
```

---

## When MySQL Does NOT Use an Index

1. **Function on indexed column**: `WHERE YEAR(created_at) = 2023` → use range instead
2. **Leading wildcard**: `WHERE name LIKE '%smith'`
3. **Type mismatch**: `WHERE varchar_col = 123` (implicit cast)
4. **Low selectivity**: optimizer prefers full scan for < ~20% of rows
5. **OR without index on all branches**: `WHERE a = 1 OR b = 2` (unless both indexed)
6. **NOT, !=, <>**: generally can't use index efficiently

---

## Performance Considerations

- Index every foreign key column (MySQL doesn't do this automatically)
- Don't over-index: each index adds write overhead (INSERT/UPDATE/DELETE)
- Monitor unused indexes: `performance_schema.table_io_waits_summary_by_index_usage`
- `ANALYZE TABLE` updates index statistics for the optimizer
- Prefix indexes for long strings: `INDEX (email(20))` — saves space but loses full selectivity

---

## Interview Q&A

**Q: What is the difference between a clustered and non-clustered index?**
A: A clustered index determines the physical order of data in the table — the leaf nodes contain the actual row data. InnoDB's PRIMARY KEY is the clustered index. A non-clustered (secondary) index is a separate B-Tree where leaf nodes contain the indexed column value plus the primary key, requiring a second lookup to fetch the full row.

**Q: Why is a low-cardinality column a poor index candidate?**
A: The optimizer estimates that a low-cardinality index (e.g., gender with 2 values) would still require reading ~50% of the table. A full table scan is often cheaper because it avoids the overhead of index traversal + random I/O for each row lookup.

**Q: What happens when you use a function on an indexed column in WHERE?**
A: MySQL cannot use the index because the index stores the raw column values, not the function results. For example, `WHERE YEAR(created_at) = 2023` forces a full scan. Rewrite as `WHERE created_at >= '2023-01-01' AND created_at < '2024-01-01'` to use the index.

**Q: What is a covering index?**
A: A covering index includes all columns needed by a query (SELECT + WHERE + ORDER BY). MySQL can satisfy the query entirely from the index without accessing the table. Identified by "Using index" in EXPLAIN.

**Q: How does InnoDB handle secondary index lookups?**
A: Secondary index leaf nodes store the indexed column value + the primary key value. To fetch non-indexed columns, InnoDB performs a second lookup in the clustered index using the PK. This "double lookup" is avoided if the query is covered by the index.
