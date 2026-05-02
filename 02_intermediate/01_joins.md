# 01 — JOINs Deep Dive

## How JOINs Work Internally

MySQL uses three join algorithms:

### 1. Nested Loop Join (NLJ)
The default algorithm. For each row in the outer table, scan the inner table.
```
for each row r1 in outer_table:
    for each row r2 in inner_table where r2.key = r1.key:
        emit (r1, r2)
```
- O(n × m) worst case without indexes
- With index on inner table: O(n × log m)
- Best for small outer tables with indexed inner tables

### 2. Block Nested Loop Join (BNL)
Loads a block of outer rows into a **join buffer**, then scans inner table once per buffer.
- Reduces inner table scans from n to n/buffer_size
- Used when inner table has no usable index
- `join_buffer_size` controls buffer size (default 256KB)

### 3. Hash Join (MySQL 8.0.18+)
Builds a hash table from the smaller table, probes with the larger table.
- O(n + m) — much faster than NLJ for large unindexed joins
- Used automatically when no index is available
- Memory-bound: spills to disk if hash table exceeds `join_buffer_size`

---

## JOIN Types

### INNER JOIN
Returns rows where the join condition matches in **both** tables.
```sql
SELECT e.name, d.dept_name
FROM employees e
INNER JOIN departments d ON e.dept_id = d.dept_id;
```

### LEFT JOIN (LEFT OUTER JOIN)
Returns **all rows from the left table** + matching rows from right. NULL for non-matches.
```sql
SELECT e.name, d.dept_name
FROM employees e
LEFT JOIN departments d ON e.dept_id = d.dept_id;
-- Employees without a department get NULL for dept_name
```

### RIGHT JOIN
Returns all rows from the right table + matching rows from left. Rarely used — rewrite as LEFT JOIN.

### FULL OUTER JOIN
MySQL doesn't support FULL OUTER JOIN natively. Simulate with UNION:
```sql
SELECT e.name, d.dept_name FROM employees e LEFT JOIN departments d ON e.dept_id = d.dept_id
UNION
SELECT e.name, d.dept_name FROM employees e RIGHT JOIN departments d ON e.dept_id = d.dept_id;
```

### SELF JOIN
Join a table to itself. Used for hierarchical data.
```sql
SELECT e.name AS employee, m.name AS manager
FROM employees e
LEFT JOIN employees m ON e.manager_id = m.emp_id;
```

### CROSS JOIN
Cartesian product — every row from left × every row from right.
```sql
SELECT a.color, b.size FROM colors a CROSS JOIN sizes b;
-- 3 colors × 4 sizes = 12 rows
```

---

## Join Execution Order & Optimizer

The optimizer chooses the join order based on:
1. Table statistics (row counts, index cardinality)
2. Available indexes
3. Estimated cost of each plan

Force join order with `STRAIGHT_JOIN`:
```sql
SELECT STRAIGHT_JOIN e.name, d.dept_name
FROM employees e JOIN departments d ON e.dept_id = d.dept_id;
```

---

## NULL Behavior in JOINs

- INNER JOIN excludes rows where the join key is NULL
- LEFT JOIN preserves left rows even when right key is NULL
- Filtering on right-table columns in WHERE converts LEFT JOIN to INNER JOIN:

```sql
-- This is effectively an INNER JOIN (WHERE filters out NULLs):
SELECT e.name FROM employees e
LEFT JOIN departments d ON e.dept_id = d.dept_id
WHERE d.dept_name = 'Engineering';  -- ← kills the LEFT JOIN effect

-- Correct way to keep it a LEFT JOIN:
SELECT e.name FROM employees e
LEFT JOIN departments d ON e.dept_id = d.dept_id AND d.dept_name = 'Engineering';
```

---

## Performance Considerations

- Always index the JOIN columns (especially the inner/right table)
- Smaller result set as the outer (driving) table
- Avoid joining on functions: `ON YEAR(e.hire_date) = YEAR(d.created_at)` — can't use index
- Use `EXPLAIN` to verify join type: `ref` (index lookup) vs `ALL` (full scan)
- `join_buffer_size`: increase for BNL joins (no index available)

---

## Interview Q&A

**Q: What is the difference between INNER JOIN and LEFT JOIN?**
A: INNER JOIN returns only rows with matching values in both tables. LEFT JOIN returns all rows from the left table, with NULLs for columns from the right table when no match exists.

**Q: How does MySQL execute a JOIN internally?**
A: MySQL primarily uses Nested Loop Join (NLJ). For each row in the outer table, it looks up matching rows in the inner table using an index. Without an index, it uses Block Nested Loop (BNL) with a join buffer. MySQL 8.0.18+ also supports Hash Join for large unindexed joins.

**Q: How do you simulate FULL OUTER JOIN in MySQL?**
A: Use UNION of LEFT JOIN and RIGHT JOIN (or LEFT JOIN with tables swapped).

**Q: Why does adding a WHERE clause on the right table convert a LEFT JOIN to an INNER JOIN?**
A: Because WHERE filters are applied after the JOIN. Rows where the right table has no match get NULL values. A WHERE condition like `WHERE right_table.col = 'value'` filters out NULLs, effectively making it an INNER JOIN. Move the condition to the ON clause to preserve LEFT JOIN semantics.

**Q: What is a SELF JOIN and when would you use it?**
A: A SELF JOIN joins a table to itself using an alias. Used for hierarchical/recursive data like employee-manager relationships, category trees, or finding pairs within the same table.
