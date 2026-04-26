-- ============================================================
-- 02_subqueries.sql
-- Subqueries, EXISTS/IN, CTEs, recursive CTEs
-- ============================================================
USE practice_db;

-- ── Scalar subquery ───────────────────────────────────────────
-- Each employee's salary vs company average
SELECT name, salary,
       ROUND((SELECT AVG(salary) FROM emp), 2) AS company_avg,
       ROUND(salary - (SELECT AVG(salary) FROM emp), 2) AS diff_from_avg
FROM emp
ORDER BY salary DESC;

-- ── Correlated subquery ───────────────────────────────────────
-- Employees earning above their department average
SELECT e.name, e.salary, e.dept_id
FROM emp e
WHERE e.salary > (
    SELECT AVG(e2.salary) FROM emp e2 WHERE e2.dept_id = e.dept_id
)
ORDER BY e.dept_id, e.salary DESC;

-- Rewrite as JOIN (more efficient):
SELECT e.name, e.salary, ds.avg_sal
FROM emp e
JOIN (
    SELECT dept_id, AVG(salary) AS avg_sal FROM emp GROUP BY dept_id
) AS ds ON e.dept_id = ds.dept_id
WHERE e.salary > ds.avg_sal;

-- ── IN vs EXISTS ──────────────────────────────────────────────
-- Employees in departments located in NYC (using IN)
SELECT name FROM emp
WHERE dept_id IN (SELECT dept_id FROM dept WHERE location = 'NYC');

-- Same query using EXISTS (preferred for large subqueries)
SELECT e.name FROM emp e
WHERE EXISTS (
    SELECT 1 FROM dept d WHERE d.dept_id = e.dept_id AND d.location = 'NYC'
);

-- ── NOT IN vs NOT EXISTS (NULL trap) ─────────────────────────
-- Safe: NOT EXISTS
SELECT e.name FROM emp e
WHERE NOT EXISTS (
    SELECT 1 FROM projects p WHERE p.dept_id = e.dept_id
);

-- Dangerous if dept_id can be NULL: NOT IN
-- SELECT name FROM emp WHERE dept_id NOT IN (SELECT dept_id FROM projects);
-- If any project has dept_id = NULL → returns 0 rows

-- ── Derived table (inline view) ───────────────────────────────
SELECT dept_id, avg_sal, headcount
FROM (
    SELECT dept_id, ROUND(AVG(salary), 2) AS avg_sal, COUNT(*) AS headcount
    FROM emp
    WHERE dept_id IS NOT NULL
    GROUP BY dept_id
) AS dept_stats
WHERE avg_sal > 80000;

-- ── CTE (MySQL 8.0+) ──────────────────────────────────────────
WITH dept_stats AS (
    SELECT dept_id, AVG(salary) AS avg_sal
    FROM emp
    WHERE dept_id IS NOT NULL
    GROUP BY dept_id
),
top_depts AS (
    SELECT dept_id FROM dept_stats WHERE avg_sal > 85000
)
SELECT e.name, e.salary, d.name AS dept
FROM emp e
JOIN dept d ON e.dept_id = d.dept_id
WHERE e.dept_id IN (SELECT dept_id FROM top_depts)
ORDER BY e.salary DESC;

-- ── Recursive CTE — org chart ─────────────────────────────────
WITH RECURSIVE org AS (
    -- Anchor: employees with no manager
    SELECT emp_id, name, manager_id, 0 AS depth,
           CAST(name AS CHAR(500)) AS path
    FROM emp WHERE manager_id IS NULL

    UNION ALL

    -- Recursive: direct reports
    SELECT e.emp_id, e.name, e.manager_id, o.depth + 1,
           CONCAT(o.path, ' → ', e.name)
    FROM emp e
    JOIN org o ON e.manager_id = o.emp_id
)
SELECT depth, REPEAT('  ', depth) AS indent, name, path
FROM org
ORDER BY path;

-- ── Recursive CTE — running total ────────────────────────────
WITH RECURSIVE numbers AS (
    SELECT 1 AS n
    UNION ALL
    SELECT n + 1 FROM numbers WHERE n < 10
)
SELECT n, SUM(n) OVER (ORDER BY n) AS running_total FROM numbers;

-- ── Subquery in SELECT (scalar) ───────────────────────────────
SELECT
    d.name AS dept,
    (SELECT COUNT(*) FROM emp e WHERE e.dept_id = d.dept_id) AS headcount,
    (SELECT MAX(salary) FROM emp e WHERE e.dept_id = d.dept_id) AS top_salary
FROM dept d
ORDER BY headcount DESC;

-- ── Row subquery ──────────────────────────────────────────────
-- Find the employee with the highest salary in dept 1
SELECT name, salary FROM emp
WHERE (dept_id, salary) = (
    SELECT dept_id, MAX(salary) FROM emp WHERE dept_id = 1
);
