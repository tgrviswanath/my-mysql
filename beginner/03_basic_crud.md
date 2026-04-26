# 03 — Basic CRUD Operations

## DDL vs DML vs DCL vs TCL

| Category | Commands | Description |
|----------|----------|-------------|
| DDL | CREATE, ALTER, DROP, TRUNCATE | Define schema structure |
| DML | SELECT, INSERT, UPDATE, DELETE | Manipulate data |
| DCL | GRANT, REVOKE | Control access |
| TCL | COMMIT, ROLLBACK, SAVEPOINT | Manage transactions |

---

## SELECT — Query Execution Order

SQL is **declarative** — you describe *what* you want, not *how* to get it. The logical execution order differs from the written order:

```
Written order:        Execution order:
SELECT                1. FROM
FROM                  2. JOIN
WHERE                 3. WHERE
GROUP BY              4. GROUP BY
HAVING                5. HAVING
ORDER BY              6. SELECT
LIMIT                 7. DISTINCT
                      8. ORDER BY
                      9. LIMIT
```

This matters because:
- You **cannot** use a SELECT alias in WHERE (WHERE runs before SELECT)
- You **can** use a SELECT alias in ORDER BY (ORDER BY runs after SELECT)
- HAVING filters on aggregated results; WHERE filters on raw rows

---

## INSERT Patterns

```sql
-- Single row
INSERT INTO table (col1, col2) VALUES (v1, v2);

-- Multi-row (more efficient than multiple single inserts)
INSERT INTO table (col1, col2) VALUES (v1, v2), (v3, v4), (v5, v6);

-- Insert from SELECT
INSERT INTO archive_orders SELECT * FROM orders WHERE created_at < '2023-01-01';

-- Upsert: insert or update on duplicate key
INSERT INTO table (id, col) VALUES (1, 'new')
ON DUPLICATE KEY UPDATE col = VALUES(col);

-- Insert ignore: skip on duplicate key error
INSERT IGNORE INTO table (id, col) VALUES (1, 'val');
```

---

## UPDATE Patterns

```sql
-- Basic update
UPDATE employees SET salary = salary * 1.10 WHERE dept_id = 1;

-- Multi-table update (JOIN)
UPDATE employees e
JOIN departments d ON e.dept_id = d.dept_id
SET e.salary = e.salary * 1.05
WHERE d.dept_name = 'Engineering';

-- Update with subquery
UPDATE products
SET price = price * 0.9
WHERE product_id IN (
    SELECT product_id FROM order_items
    GROUP BY product_id
    HAVING COUNT(*) > 100
);
```

> ⚠️ Always include WHERE in UPDATE/DELETE — a missing WHERE updates/deletes ALL rows

---

## DELETE vs TRUNCATE vs DROP

| Operation | Logs | WHERE | Rollback | Resets AUTO_INCREMENT | Speed |
|-----------|------|-------|----------|-----------------------|-------|
| DELETE | Row-by-row | ✅ | ✅ | ❌ | Slow |
| TRUNCATE | Minimal | ❌ | ❌ (DDL) | ✅ | Fast |
| DROP | Minimal | ❌ | ❌ (DDL) | N/A | Fast |

---

## GROUP BY & Aggregates

```sql
SELECT dept_id, COUNT(*) AS headcount, AVG(salary) AS avg_salary
FROM employees
GROUP BY dept_id
HAVING AVG(salary) > 80000
ORDER BY avg_salary DESC;
```

Aggregate functions: `COUNT`, `SUM`, `AVG`, `MIN`, `MAX`, `GROUP_CONCAT`

**ONLY_FULL_GROUP_BY mode** (default in MySQL 5.7+):
- Every non-aggregated column in SELECT must appear in GROUP BY
- Prevents non-deterministic results

---

## Performance Considerations

- `SELECT *` fetches all columns — use explicit column lists to reduce I/O
- `LIMIT` without `ORDER BY` returns non-deterministic rows
- `ORDER BY` on non-indexed columns causes filesort (expensive)
- Multi-row INSERT is significantly faster than individual INSERTs
- `TRUNCATE` is faster than `DELETE FROM table` for clearing all rows

---

## Common Mistakes

- `UPDATE` / `DELETE` without `WHERE` — affects all rows
- Using `SELECT *` in production queries
- Forgetting `COMMIT` after DML in non-autocommit mode
- Using `HAVING` instead of `WHERE` for non-aggregate filters (HAVING is slower)
- `GROUP BY` without understanding ONLY_FULL_GROUP_BY mode

---

## Interview Q&A

**Q: What is the logical execution order of a SELECT statement?**
A: FROM → JOIN → WHERE → GROUP BY → HAVING → SELECT → DISTINCT → ORDER BY → LIMIT. This is why you can't reference a SELECT alias in WHERE, but you can in ORDER BY.

**Q: What is the difference between DELETE and TRUNCATE?**
A: DELETE is DML — it removes rows one by one, logs each deletion, supports WHERE, and can be rolled back. TRUNCATE is DDL — it drops and recreates the table structure, is minimally logged, cannot be rolled back, and resets AUTO_INCREMENT.

**Q: What is the difference between WHERE and HAVING?**
A: WHERE filters individual rows before grouping. HAVING filters groups after GROUP BY. Using HAVING for non-aggregate conditions is valid but less efficient than WHERE because it processes more rows.

**Q: What does ON DUPLICATE KEY UPDATE do?**
A: It performs an upsert — if the INSERT would cause a duplicate key violation (PK or UNIQUE), it executes the UPDATE clause instead. Useful for idempotent writes.

**Q: Why is multi-row INSERT faster than multiple single INSERTs?**
A: Each INSERT statement has overhead: parsing, network round-trip, transaction commit (in autocommit mode), and index updates. Multi-row INSERT batches all rows into one statement, one transaction, and one index update pass.
