# 02 — Subqueries & CTEs

## Types of Subqueries

### 1. Scalar Subquery
Returns exactly one row, one column. Used anywhere a single value is expected.
```sql
SELECT name, salary,
       (SELECT AVG(salary) FROM employees) AS company_avg
FROM employees;
```

### 2. Row Subquery
Returns one row with multiple columns.
```sql
SELECT * FROM employees
WHERE (dept_id, salary) = (SELECT dept_id, MAX(salary) FROM employees WHERE dept_id = 1);
```

### 3. Table Subquery (Derived Table)
Returns a result set used as a table in FROM.
```sql
SELECT dept_id, avg_sal FROM (
    SELECT dept_id, AVG(salary) AS avg_sal FROM employees GROUP BY dept_id
) AS dept_stats
WHERE avg_sal > 80000;
```

### 4. Correlated Subquery
References columns from the outer query. Executed **once per outer row** — can be slow.
```sql
SELECT name, salary FROM employees e
WHERE salary > (
    SELECT AVG(salary) FROM employees WHERE dept_id = e.dept_id
);
```

---

## EXISTS vs IN vs JOIN

### IN
```sql
SELECT name FROM employees
WHERE dept_id IN (SELECT dept_id FROM departments WHERE location = 'NYC');
```
- Materializes the subquery result into a list
- Efficient when subquery returns small result set
- NULL handling: `IN (1, 2, NULL)` — if value not in list AND NULL present, returns UNKNOWN (not FALSE)

### EXISTS
```sql
SELECT name FROM employees e
WHERE EXISTS (
    SELECT 1 FROM departments d WHERE d.dept_id = e.dept_id AND d.location = 'NYC'
);
```
- Short-circuits on first match — efficient for large subquery results
- Better than IN when subquery returns many rows
- NULL-safe: EXISTS returns TRUE/FALSE, never UNKNOWN

### NOT IN vs NOT EXISTS
```sql
-- NOT IN with NULLs is dangerous:
SELECT name FROM employees WHERE dept_id NOT IN (SELECT dept_id FROM departments);
-- If any dept_id in subquery is NULL → returns 0 rows (UNKNOWN propagation)

-- NOT EXISTS is NULL-safe:
SELECT name FROM employees e
WHERE NOT EXISTS (SELECT 1 FROM departments d WHERE d.dept_id = e.dept_id);
```

> ⚠️ Always prefer `NOT EXISTS` over `NOT IN` when the subquery column can contain NULLs.

---

## CTEs (Common Table Expressions)

Introduced in MySQL 8.0. Defined with `WITH` clause.

```sql
WITH dept_stats AS (
    SELECT dept_id, AVG(salary) AS avg_sal, COUNT(*) AS headcount
    FROM employees
    GROUP BY dept_id
)
SELECT e.name, e.salary, ds.avg_sal
FROM employees e
JOIN dept_stats ds ON e.dept_id = ds.dept_id
WHERE e.salary > ds.avg_sal;
```

### CTE vs Derived Table
| Feature | CTE | Derived Table |
|---------|-----|---------------|
| Readability | ✅ Named, reusable | ❌ Inline, nested |
| Multiple references | ✅ Reference by name | ❌ Must repeat |
| Recursive | ✅ | ❌ |
| Materialized | Sometimes | Sometimes |

### Recursive CTE
```sql
WITH RECURSIVE org_chart AS (
    -- Anchor: top-level employees (no manager)
    SELECT emp_id, name, manager_id, 0 AS level
    FROM employees WHERE manager_id IS NULL

    UNION ALL

    -- Recursive: employees reporting to previous level
    SELECT e.emp_id, e.name, e.manager_id, oc.level + 1
    FROM employees e
    JOIN org_chart oc ON e.manager_id = oc.emp_id
)
SELECT * FROM org_chart ORDER BY level, name;
```

---

## Performance Considerations

- Correlated subqueries execute N times (once per outer row) — often rewrite as JOIN
- `IN` with large subquery: optimizer may convert to semi-join internally
- CTEs in MySQL 8.0 may be materialized (computed once) or merged (inlined)
- Use `EXPLAIN` to see if subquery is materialized or executed per row
- Derived tables with no index: optimizer can't push predicates inside

---

## Interview Q&A

**Q: What is the difference between a correlated and non-correlated subquery?**
A: A non-correlated subquery executes once and its result is used by the outer query. A correlated subquery references columns from the outer query and executes once for each row of the outer query, making it potentially O(n) times slower.

**Q: When should you use EXISTS instead of IN?**
A: Use EXISTS when the subquery returns a large result set — it short-circuits on the first match. Use IN when the subquery returns a small, known set. Always use NOT EXISTS instead of NOT IN when the subquery column can contain NULLs.

**Q: Why does NOT IN return no rows when the subquery contains a NULL?**
A: SQL uses three-valued logic (TRUE, FALSE, UNKNOWN). `value NOT IN (1, 2, NULL)` evaluates as `value != 1 AND value != 2 AND value != NULL`. Since `value != NULL` is always UNKNOWN, the entire expression is UNKNOWN, which is treated as FALSE in WHERE clauses.

**Q: What is a recursive CTE and what is it used for?**
A: A recursive CTE references itself to process hierarchical or graph data. It has an anchor member (base case) and a recursive member (references the CTE). Used for org charts, category trees, bill of materials, and path finding.

**Q: Can you reference a CTE multiple times in the same query?**
A: Yes — that's one of the key advantages of CTEs over derived tables. The CTE is defined once and can be referenced multiple times in the main query, improving readability and potentially performance (if materialized).
