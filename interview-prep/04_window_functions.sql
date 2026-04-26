-- ============================================================
-- 04_window_functions.sql
-- Complete window functions reference and practice
-- ============================================================
USE practice_db;

-- ── Window function syntax ────────────────────────────────────
-- function() OVER (
--     [PARTITION BY col1, col2]
--     [ORDER BY col3 ASC/DESC]
--     [ROWS/RANGE BETWEEN frame_start AND frame_end]
-- )

-- ── Ranking functions ─────────────────────────────────────────
SELECT name, dept, salary,
    ROW_NUMBER()  OVER (PARTITION BY dept ORDER BY salary DESC) AS row_num,
    RANK()        OVER (PARTITION BY dept ORDER BY salary DESC) AS rank_val,
    DENSE_RANK()  OVER (PARTITION BY dept ORDER BY salary DESC) AS dense_rank_val,
    PERCENT_RANK() OVER (PARTITION BY dept ORDER BY salary DESC) AS pct_rank,
    CUME_DIST()   OVER (PARTITION BY dept ORDER BY salary DESC) AS cume_dist_val,
    NTILE(4)      OVER (ORDER BY salary DESC) AS quartile
FROM employees_iv
ORDER BY dept, salary DESC;

-- ROW_NUMBER vs RANK vs DENSE_RANK:
-- Salary: 100, 100, 90, 80
-- ROW_NUMBER:  1, 2, 3, 4  (always unique)
-- RANK:        1, 1, 3, 4  (gaps after ties)
-- DENSE_RANK:  1, 1, 2, 3  (no gaps)

-- ── Value functions ───────────────────────────────────────────
SELECT name, dept, salary,
    LAG(salary)  OVER (PARTITION BY dept ORDER BY salary)  AS prev_salary,
    LEAD(salary) OVER (PARTITION BY dept ORDER BY salary)  AS next_salary,
    FIRST_VALUE(name) OVER (PARTITION BY dept ORDER BY salary DESC) AS top_earner,
    LAST_VALUE(name)  OVER (
        PARTITION BY dept ORDER BY salary DESC
        ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
    ) AS lowest_earner,
    NTH_VALUE(salary, 2) OVER (PARTITION BY dept ORDER BY salary DESC) AS second_highest
FROM employees_iv;

-- ── Aggregate window functions ────────────────────────────────
SELECT name, dept, salary,
    SUM(salary)   OVER (PARTITION BY dept) AS dept_total,
    AVG(salary)   OVER (PARTITION BY dept) AS dept_avg,
    COUNT(*)      OVER (PARTITION BY dept) AS dept_headcount,
    salary - AVG(salary) OVER (PARTITION BY dept) AS diff_from_avg,
    ROUND(salary / SUM(salary) OVER (PARTITION BY dept) * 100, 2) AS pct_of_dept
FROM employees_iv;

-- ── Running totals & moving averages ─────────────────────────
WITH daily_orders AS (
    SELECT DATE(created_at) AS day, COUNT(*) AS cnt, SUM(amount) AS revenue
    FROM orders GROUP BY DATE(created_at)
)
SELECT day, cnt, revenue,
    SUM(revenue) OVER (ORDER BY day ROWS UNBOUNDED PRECEDING) AS cumulative_revenue,
    AVG(revenue) OVER (ORDER BY day ROWS BETWEEN 6 PRECEDING AND CURRENT ROW) AS rolling_7d_avg,
    AVG(revenue) OVER (ORDER BY day ROWS BETWEEN 2 PRECEDING AND 2 FOLLOWING) AS centered_5d_avg
FROM daily_orders ORDER BY day;

-- ── Frame specifications ──────────────────────────────────────
-- ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW  → running total
-- ROWS BETWEEN 2 PRECEDING AND CURRENT ROW          → 3-row moving avg
-- ROWS BETWEEN CURRENT ROW AND UNBOUNDED FOLLOWING  → reverse running total
-- ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING → whole partition
-- RANGE BETWEEN INTERVAL 7 DAY PRECEDING AND CURRENT ROW  → 7-day window by date

-- ── Practical: top N per group ────────────────────────────────
-- Top 2 earners per department
SELECT dept, name, salary FROM (
    SELECT dept, name, salary,
           ROW_NUMBER() OVER (PARTITION BY dept ORDER BY salary DESC) AS rn
    FROM employees_iv
) AS ranked WHERE rn <= 2;

-- ── Practical: year-over-year comparison ─────────────────────
WITH yearly AS (
    SELECT YEAR(created_at) AS yr, SUM(amount) AS revenue
    FROM orders GROUP BY YEAR(created_at)
)
SELECT yr, revenue,
    LAG(revenue) OVER (ORDER BY yr) AS prev_year,
    ROUND((revenue - LAG(revenue) OVER (ORDER BY yr)) /
          LAG(revenue) OVER (ORDER BY yr) * 100, 2) AS yoy_growth_pct
FROM yearly ORDER BY yr;

-- ── Practical: percentile buckets ────────────────────────────
SELECT name, salary,
    CASE NTILE(4) OVER (ORDER BY salary)
        WHEN 1 THEN 'Bottom 25%'
        WHEN 2 THEN '25-50%'
        WHEN 3 THEN '50-75%'
        WHEN 4 THEN 'Top 25%'
    END AS salary_bucket
FROM employees_iv ORDER BY salary;

-- ── Practical: detect anomalies (salary spike) ───────────────
WITH monthly_sal AS (
    SELECT DATE_FORMAT(created_at, '%Y-%m') AS month, SUM(amount) AS revenue
    FROM orders GROUP BY DATE_FORMAT(created_at, '%Y-%m')
)
SELECT month, revenue,
    AVG(revenue) OVER (ORDER BY month ROWS BETWEEN 2 PRECEDING AND 2 FOLLOWING) AS local_avg,
    revenue / AVG(revenue) OVER (ORDER BY month ROWS BETWEEN 2 PRECEDING AND 2 FOLLOWING) AS ratio
FROM monthly_sal
HAVING ratio > 1.5 OR ratio < 0.5;  -- anomaly: 50% above/below local average
