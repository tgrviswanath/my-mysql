-- ============================================================
-- 02_medium_questions.sql
-- Medium interview SQL problems with solutions
-- ============================================================
USE practice_db;

-- ── Q1: Rank scores (no gaps in ranking) ─────────────────────
CREATE TABLE IF NOT EXISTS scores (id INT, score DECIMAL(3,2));
INSERT IGNORE INTO scores VALUES (1,3.50),(2,3.65),(3,4.00),(4,3.85),(5,4.00),(6,3.65);

SELECT score,
       DENSE_RANK() OVER (ORDER BY score DESC) AS `rank`
FROM scores ORDER BY score DESC;

-- ── Q2: Department top 3 earners ─────────────────────────────
WITH ranked AS (
    SELECT name, dept, salary,
           DENSE_RANK() OVER (PARTITION BY dept ORDER BY salary DESC) AS rnk
    FROM employees_iv
)
SELECT dept, name, salary FROM ranked WHERE rnk <= 3 ORDER BY dept, salary DESC;

-- ── Q3: Running total of orders ───────────────────────────────
SELECT
    order_id,
    customer_id,
    amount,
    SUM(amount) OVER (PARTITION BY customer_id ORDER BY order_id) AS running_total
FROM orders
ORDER BY customer_id, order_id;

-- ── Q4: Median salary per department ─────────────────────────
WITH ranked AS (
    SELECT dept, salary,
           ROW_NUMBER() OVER (PARTITION BY dept ORDER BY salary) AS rn,
           COUNT(*) OVER (PARTITION BY dept) AS cnt
    FROM employees_iv
)
SELECT dept, AVG(salary) AS median_salary
FROM ranked
WHERE rn IN (FLOOR((cnt+1)/2), CEIL((cnt+1)/2))
GROUP BY dept;

-- ── Q5: Find gaps in sequential IDs ──────────────────────────
CREATE TABLE IF NOT EXISTS seq_table (id INT PRIMARY KEY);
INSERT IGNORE INTO seq_table VALUES (1),(2),(4),(5),(8),(9),(10);

SELECT t1.id + 1 AS gap_start,
       MIN(t2.id) - 1 AS gap_end
FROM seq_table t1
JOIN seq_table t2 ON t2.id > t1.id
WHERE NOT EXISTS (SELECT 1 FROM seq_table WHERE id = t1.id + 1)
GROUP BY t1.id;

-- ── Q6: Pivot — sales by quarter ─────────────────────────────
CREATE TABLE IF NOT EXISTS sales_data (
    product VARCHAR(20), quarter VARCHAR(5), amount INT
);
INSERT IGNORE INTO sales_data VALUES
    ('A','Q1',100),('A','Q2',200),('A','Q3',150),('A','Q4',300),
    ('B','Q1',80), ('B','Q2',120),('B','Q3',90), ('B','Q4',200);

SELECT product,
    SUM(CASE WHEN quarter='Q1' THEN amount ELSE 0 END) AS Q1,
    SUM(CASE WHEN quarter='Q2' THEN amount ELSE 0 END) AS Q2,
    SUM(CASE WHEN quarter='Q3' THEN amount ELSE 0 END) AS Q3,
    SUM(CASE WHEN quarter='Q4' THEN amount ELSE 0 END) AS Q4,
    SUM(amount) AS total
FROM sales_data GROUP BY product;

-- ── Q7: First and last order per customer ────────────────────
SELECT
    customer_id,
    MIN(created_at) AS first_order,
    MAX(created_at) AS last_order,
    COUNT(*) AS total_orders,
    DATEDIFF(MAX(created_at), MIN(created_at)) AS days_as_customer
FROM orders
GROUP BY customer_id;

-- ── Q8: Consecutive login days ───────────────────────────────
CREATE TABLE IF NOT EXISTS logins (user_id INT, login_date DATE);
INSERT IGNORE INTO logins VALUES
    (1,'2024-01-01'),(1,'2024-01-02'),(1,'2024-01-03'),
    (1,'2024-01-05'),(2,'2024-01-01'),(2,'2024-01-02');

WITH grouped AS (
    SELECT user_id, login_date,
           DATE_SUB(login_date, INTERVAL ROW_NUMBER() OVER (PARTITION BY user_id ORDER BY login_date) DAY) AS grp
    FROM logins
)
SELECT user_id, MIN(login_date) AS streak_start, MAX(login_date) AS streak_end,
       COUNT(*) AS streak_length
FROM grouped
GROUP BY user_id, grp
ORDER BY streak_length DESC;

-- ── Q9: Products bought by all customers ─────────────────────
SELECT product_id FROM order_items_2nf
GROUP BY product_id
HAVING COUNT(DISTINCT (SELECT customer_id FROM orders_2nf WHERE order_id = order_items_2nf.order_id)) =
       (SELECT COUNT(*) FROM customers_3nf);

-- Cleaner version:
SELECT oi.product_id
FROM order_items_2nf oi
JOIN orders_2nf o ON oi.order_id = o.order_id
GROUP BY oi.product_id
HAVING COUNT(DISTINCT o.customer_id) = (SELECT COUNT(*) FROM customers_3nf);

-- ── Q10: Moving average (3-day) ───────────────────────────────
WITH daily_sales AS (
    SELECT DATE(created_at) AS sale_date, SUM(amount) AS daily_total
    FROM orders GROUP BY DATE(created_at)
)
SELECT sale_date, daily_total,
       ROUND(AVG(daily_total) OVER (ORDER BY sale_date ROWS BETWEEN 2 PRECEDING AND CURRENT ROW), 2) AS moving_avg_3d
FROM daily_sales ORDER BY sale_date;
