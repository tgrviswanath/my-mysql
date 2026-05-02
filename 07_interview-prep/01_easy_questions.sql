-- ============================================================
-- 01_easy_questions.sql
-- Easy interview SQL problems with solutions
-- ============================================================
USE practice_db;

-- ── Setup ─────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS employees_iv (
    emp_id   INT PRIMARY KEY,
    name     VARCHAR(50),
    dept     VARCHAR(50),
    salary   INT,
    manager_id INT
);

INSERT IGNORE INTO employees_iv VALUES
    (1,'Alice','Engineering',95000,NULL),
    (2,'Bob','Engineering',85000,1),
    (3,'Carol','Marketing',75000,4),
    (4,'Dave','Marketing',90000,NULL),
    (5,'Eve','Engineering',80000,1),
    (6,'Frank','HR',65000,NULL),
    (7,'Grace','HR',60000,6),
    (8,'Heidi','Engineering',70000,2);

-- ── Q1: Find the second highest salary ───────────────────────
-- Method 1: LIMIT/OFFSET
SELECT DISTINCT salary FROM employees_iv ORDER BY salary DESC LIMIT 1 OFFSET 1;

-- Method 2: Subquery (handles ties correctly)
SELECT MAX(salary) FROM employees_iv WHERE salary < (SELECT MAX(salary) FROM employees_iv);

-- Method 3: DENSE_RANK (most robust)
SELECT salary FROM (
    SELECT salary, DENSE_RANK() OVER (ORDER BY salary DESC) AS rnk
    FROM employees_iv
) AS ranked WHERE rnk = 2 LIMIT 1;

-- ── Q2: Find duplicate emails ─────────────────────────────────
CREATE TABLE IF NOT EXISTS person (id INT, email VARCHAR(50));
INSERT IGNORE INTO person VALUES (1,'a@b.com'),(2,'c@d.com'),(3,'a@b.com');

SELECT email FROM person GROUP BY email HAVING COUNT(*) > 1;

-- ── Q3: Delete duplicate rows, keep lowest id ─────────────────
DELETE p1 FROM person p1
JOIN person p2 ON p1.email = p2.email AND p1.id > p2.id;

-- ── Q4: Employees earning more than their manager ─────────────
SELECT e.name AS employee, e.salary, m.name AS manager, m.salary AS manager_salary
FROM employees_iv e
JOIN employees_iv m ON e.manager_id = m.emp_id
WHERE e.salary > m.salary;

-- ── Q5: Department with highest average salary ────────────────
SELECT dept, ROUND(AVG(salary), 2) AS avg_salary
FROM employees_iv
GROUP BY dept
ORDER BY avg_salary DESC
LIMIT 1;

-- ── Q6: Employees not in any department (NULL dept) ───────────
SELECT name FROM employees_iv WHERE dept IS NULL;
-- (none in this dataset — illustrates IS NULL usage)

-- ── Q7: Count employees per department ───────────────────────
SELECT dept, COUNT(*) AS headcount
FROM employees_iv
GROUP BY dept
ORDER BY headcount DESC;

-- ── Q8: Find employees with salary above department average ───
SELECT e.name, e.dept, e.salary
FROM employees_iv e
WHERE e.salary > (
    SELECT AVG(salary) FROM employees_iv WHERE dept = e.dept
)
ORDER BY e.dept, e.salary DESC;

-- ── Q9: Nth highest salary (generic) ─────────────────────────
-- N = 3 (third highest)
SELECT salary FROM (
    SELECT salary, DENSE_RANK() OVER (ORDER BY salary DESC) AS rnk
    FROM employees_iv
) AS r WHERE rnk = 3;

-- ── Q10: Consecutive numbers (find 3+ consecutive) ───────────
CREATE TABLE IF NOT EXISTS logs_iv (id INT, num INT);
INSERT IGNORE INTO logs_iv VALUES (1,1),(2,1),(3,1),(4,2),(5,1),(6,2),(7,2);

SELECT DISTINCT l1.num AS ConsecutiveNums
FROM logs_iv l1
JOIN logs_iv l2 ON l2.id = l1.id + 1 AND l2.num = l1.num
JOIN logs_iv l3 ON l3.id = l1.id + 2 AND l3.num = l1.num;

-- ── Q11: Rising temperature (today hotter than yesterday) ─────
CREATE TABLE IF NOT EXISTS weather (id INT, recordDate DATE, temperature INT);
INSERT IGNORE INTO weather VALUES
    (1,'2024-01-01',10),(2,'2024-01-02',25),(3,'2024-01-03',20),(4,'2024-01-04',30);

SELECT w1.id FROM weather w1
JOIN weather w2 ON w2.recordDate = DATE_SUB(w1.recordDate, INTERVAL 1 DAY)
WHERE w1.temperature > w2.temperature;

-- ── Q12: Customers who never ordered ─────────────────────────
SELECT c.name FROM customers_3nf c
LEFT JOIN orders_2nf o ON c.customer_id = o.customer_id
WHERE o.order_id IS NULL;
