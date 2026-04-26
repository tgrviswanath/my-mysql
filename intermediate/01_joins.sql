-- ============================================================
-- 01_joins.sql
-- INNER, LEFT, RIGHT, SELF, CROSS JOIN with real scenarios
-- ============================================================
USE practice_db;

-- ── Setup: org chart schema ───────────────────────────────────
CREATE TABLE IF NOT EXISTS dept (
    dept_id   INT AUTO_INCREMENT PRIMARY KEY,
    name      VARCHAR(50) NOT NULL,
    location  VARCHAR(50)
);

CREATE TABLE IF NOT EXISTS emp (
    emp_id     INT AUTO_INCREMENT PRIMARY KEY,
    name       VARCHAR(100) NOT NULL,
    dept_id    INT,
    manager_id INT,
    salary     DECIMAL(10,2),
    FOREIGN KEY (dept_id)    REFERENCES dept(dept_id),
    FOREIGN KEY (manager_id) REFERENCES emp(emp_id)
);

CREATE TABLE IF NOT EXISTS projects (
    project_id INT AUTO_INCREMENT PRIMARY KEY,
    name       VARCHAR(100) NOT NULL,
    dept_id    INT,
    FOREIGN KEY (dept_id) REFERENCES dept(dept_id)
);

INSERT INTO dept (name, location) VALUES
    ('Engineering', 'NYC'), ('Marketing', 'LA'),
    ('HR', 'Chicago'), ('Finance', 'NYC');

INSERT INTO emp (name, dept_id, manager_id, salary) VALUES
    ('Alice',   1, NULL,  120000),  -- CEO/CTO
    ('Bob',     1, 1,      95000),
    ('Carol',   1, 1,      90000),
    ('Dave',    2, NULL,   85000),
    ('Eve',     2, 4,      75000),
    ('Frank',   3, NULL,   70000),
    ('Grace',   NULL, 1,   65000);  -- no dept assigned

INSERT INTO projects (name, dept_id) VALUES
    ('Platform Rewrite', 1),
    ('Brand Campaign',   2),
    ('Compliance Audit', NULL);  -- no dept assigned

-- ── INNER JOIN ────────────────────────────────────────────────
-- Only employees WITH a department
SELECT e.name, d.name AS dept, d.location
FROM emp e
INNER JOIN dept d ON e.dept_id = d.dept_id
ORDER BY d.name, e.name;

-- ── LEFT JOIN ─────────────────────────────────────────────────
-- All employees, including those without a department
SELECT e.name, COALESCE(d.name, 'Unassigned') AS dept
FROM emp e
LEFT JOIN dept d ON e.dept_id = d.dept_id;

-- Find employees WITHOUT a department (anti-join pattern)
SELECT e.name FROM emp e
LEFT JOIN dept d ON e.dept_id = d.dept_id
WHERE d.dept_id IS NULL;

-- ── RIGHT JOIN (rewritten as LEFT JOIN) ───────────────────────
-- All departments, including those with no employees
SELECT d.name AS dept, COUNT(e.emp_id) AS headcount
FROM emp e
RIGHT JOIN dept d ON e.dept_id = d.dept_id
GROUP BY d.dept_id, d.name
ORDER BY headcount DESC;

-- ── SELF JOIN — employee-manager hierarchy ────────────────────
SELECT
    e.name  AS employee,
    m.name  AS manager,
    e.salary
FROM emp e
LEFT JOIN emp m ON e.manager_id = m.emp_id
ORDER BY m.name NULLS LAST, e.name;

-- ── SELF JOIN — find employees earning more than their manager ─
SELECT e.name AS employee, e.salary AS emp_salary,
       m.name AS manager,  m.salary AS mgr_salary
FROM emp e
JOIN emp m ON e.manager_id = m.emp_id
WHERE e.salary > m.salary;

-- ── CROSS JOIN — generate combinations ───────────────────────
CREATE TABLE IF NOT EXISTS sizes  (size  VARCHAR(5));
CREATE TABLE IF NOT EXISTS colors (color VARCHAR(10));
INSERT IGNORE INTO sizes  VALUES ('S'),('M'),('L'),('XL');
INSERT IGNORE INTO colors VALUES ('Red'),('Blue'),('Green');

SELECT color, size FROM colors CROSS JOIN sizes ORDER BY color, size;

-- ── FULL OUTER JOIN simulation ────────────────────────────────
-- All employees + all departments (even unmatched on both sides)
SELECT e.name AS employee, d.name AS dept
FROM emp e LEFT JOIN dept d ON e.dept_id = d.dept_id
UNION
SELECT e.name AS employee, d.name AS dept
FROM emp e RIGHT JOIN dept d ON e.dept_id = d.dept_id;

-- ── Multi-table JOIN ──────────────────────────────────────────
SELECT e.name AS employee, d.name AS dept, p.name AS project
FROM emp e
JOIN dept d ON e.dept_id = d.dept_id
JOIN projects p ON p.dept_id = d.dept_id
ORDER BY d.name, e.name;

-- ── WHERE vs ON for LEFT JOIN (critical difference) ──────────
-- Correct: filter in ON clause preserves LEFT JOIN
SELECT e.name, d.name AS dept
FROM emp e
LEFT JOIN dept d ON e.dept_id = d.dept_id AND d.location = 'NYC';

-- Wrong: filter in WHERE converts to INNER JOIN
SELECT e.name, d.name AS dept
FROM emp e
LEFT JOIN dept d ON e.dept_id = d.dept_id
WHERE d.location = 'NYC';  -- Grace (no dept) disappears

-- ── EXPLAIN to verify join algorithm ─────────────────────────
EXPLAIN SELECT e.name, d.name
FROM emp e JOIN dept d ON e.dept_id = d.dept_id;
-- Look for: type=ref (index lookup) vs type=ALL (full scan)
