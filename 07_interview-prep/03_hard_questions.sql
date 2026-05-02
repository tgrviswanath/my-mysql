-- ============================================================
-- 03_hard_questions.sql
-- Hard interview SQL problems with solutions
-- ============================================================
USE practice_db;

-- ── Q1: Trips and users (cancellation rate) ───────────────────
CREATE TABLE IF NOT EXISTS trips (
    id INT PRIMARY KEY, client_id INT, driver_id INT,
    city_id INT, status VARCHAR(20), request_at DATE
);
CREATE TABLE IF NOT EXISTS trip_users (
    users_id INT PRIMARY KEY, banned VARCHAR(5), role VARCHAR(10)
);
INSERT IGNORE INTO trips VALUES
    (1,1,10,1,'completed','2013-10-01'),
    (2,2,11,1,'cancelled_by_driver','2013-10-01'),
    (3,3,12,6,'completed','2013-10-01'),
    (4,4,13,6,'cancelled_by_client','2013-10-01'),
    (5,1,10,1,'completed','2013-10-02'),
    (6,2,11,6,'completed','2013-10-02'),
    (7,3,12,6,'completed','2013-10-02');
INSERT IGNORE INTO trip_users VALUES
    (1,'No','client'),(2,'Yes','client'),(3,'No','client'),
    (4,'No','client'),(10,'No','driver'),(11,'No','driver'),
    (12,'No','driver'),(13,'No','driver');

SELECT
    t.request_at AS Day,
    ROUND(SUM(t.status != 'completed') / COUNT(*), 2) AS `Cancellation Rate`
FROM trips t
JOIN trip_users c ON t.client_id = c.users_id AND c.banned = 'No'
JOIN trip_users d ON t.driver_id = d.users_id AND d.banned = 'No'
WHERE t.request_at BETWEEN '2013-10-01' AND '2013-10-03'
GROUP BY t.request_at;

-- ── Q2: Human traffic of stadium (3+ consecutive rows ≥ 100) ──
CREATE TABLE IF NOT EXISTS stadium (
    id INT PRIMARY KEY, visit_date DATE, people INT
);
INSERT IGNORE INTO stadium VALUES
    (1,'2017-01-01',10),(2,'2017-01-02',109),(3,'2017-01-03',150),
    (4,'2017-01-04',99),(5,'2017-01-05',145),(6,'2017-01-06',1455),
    (7,'2017-01-07',199),(8,'2017-01-08',188);

WITH high_traffic AS (
    SELECT id, visit_date, people,
           id - ROW_NUMBER() OVER (ORDER BY id) AS grp
    FROM stadium WHERE people >= 100
),
groups AS (
    SELECT grp, COUNT(*) AS cnt FROM high_traffic GROUP BY grp HAVING cnt >= 3
)
SELECT h.id, h.visit_date, h.people
FROM high_traffic h JOIN groups g ON h.grp = g.grp
ORDER BY h.visit_date;

-- ── Q3: Department highest salary (handle ties) ───────────────
CREATE TABLE IF NOT EXISTS dept_iv (id INT PRIMARY KEY, name VARCHAR(50));
CREATE TABLE IF NOT EXISTS emp_iv2 (id INT PRIMARY KEY, name VARCHAR(50), salary INT, dept_id INT);
INSERT IGNORE INTO dept_iv VALUES (1,'IT'),(2,'Sales');
INSERT IGNORE INTO emp_iv2 VALUES (1,'Joe',85000,1),(2,'Henry',80000,2),(3,'Sam',60000,2),(4,'Max',90000,1),(5,'Janet',69000,1),(6,'Randy',85000,1);

SELECT d.name AS Department, e.name AS Employee, e.salary AS Salary
FROM emp_iv2 e
JOIN dept_iv d ON e.dept_id = d.id
WHERE (e.dept_id, e.salary) IN (
    SELECT dept_id, MAX(salary) FROM emp_iv2 GROUP BY dept_id
);

-- ── Q4: Find median in SQL (without PERCENTILE_CONT) ─────────
WITH ordered AS (
    SELECT salary,
           ROW_NUMBER() OVER (ORDER BY salary) AS rn,
           COUNT(*) OVER () AS total
    FROM employees_iv
)
SELECT AVG(salary) AS median
FROM ordered
WHERE rn IN (FLOOR((total + 1) / 2.0), CEIL((total + 1) / 2.0));

-- ── Q5: Longest consecutive sequence ─────────────────────────
CREATE TABLE IF NOT EXISTS num_seq (num INT);
INSERT IGNORE INTO num_seq VALUES (100),(4),(200),(1),(3),(2);

WITH grouped AS (
    SELECT num, num - ROW_NUMBER() OVER (ORDER BY num) AS grp
    FROM (SELECT DISTINCT num FROM num_seq) AS d
)
SELECT MAX(COUNT(*)) OVER () AS longest_consecutive
FROM grouped GROUP BY grp
ORDER BY COUNT(*) DESC LIMIT 1;

-- ── Q6: Recursive bill of materials ──────────────────────────
CREATE TABLE IF NOT EXISTS bom (
    component_id INT, parent_id INT, name VARCHAR(50), quantity INT
);
INSERT IGNORE INTO bom VALUES
    (1,NULL,'Product A',1),(2,1,'Assembly B',2),(3,1,'Part C',3),
    (4,2,'Part D',1),(5,2,'Part E',2),(6,4,'Raw F',5);

WITH RECURSIVE bom_tree AS (
    SELECT component_id, parent_id, name, quantity, 1 AS level,
           CAST(name AS CHAR(500)) AS path
    FROM bom WHERE parent_id IS NULL
    UNION ALL
    SELECT b.component_id, b.parent_id, b.name,
           b.quantity * bt.quantity AS total_qty,
           bt.level + 1,
           CONCAT(bt.path, ' > ', b.name)
    FROM bom b JOIN bom_tree bt ON b.parent_id = bt.component_id
)
SELECT level, name, quantity AS total_needed, path FROM bom_tree ORDER BY path;

-- ── Q7: Session window (group events within 30 min) ──────────
CREATE TABLE IF NOT EXISTS user_events (
    user_id INT, event_time DATETIME
);
INSERT IGNORE INTO user_events VALUES
    (1,'2024-01-01 10:00:00'),(1,'2024-01-01 10:15:00'),
    (1,'2024-01-01 10:50:00'),(1,'2024-01-01 11:30:00'),
    (2,'2024-01-01 09:00:00'),(2,'2024-01-01 09:20:00');

WITH gaps AS (
    SELECT user_id, event_time,
           TIMESTAMPDIFF(MINUTE,
               LAG(event_time) OVER (PARTITION BY user_id ORDER BY event_time),
               event_time) AS gap_min
    FROM user_events
),
sessions AS (
    SELECT user_id, event_time,
           SUM(CASE WHEN gap_min IS NULL OR gap_min > 30 THEN 1 ELSE 0 END)
               OVER (PARTITION BY user_id ORDER BY event_time) AS session_id
    FROM gaps
)
SELECT user_id, session_id,
       MIN(event_time) AS session_start,
       MAX(event_time) AS session_end,
       COUNT(*) AS events_in_session
FROM sessions
GROUP BY user_id, session_id
ORDER BY user_id, session_start;

-- ── Q8: Find all ancestors in a hierarchy ────────────────────
WITH RECURSIVE ancestors AS (
    SELECT emp_id, name, manager_id, 0 AS depth
    FROM employees_iv WHERE emp_id = 8  -- start from Heidi
    UNION ALL
    SELECT e.emp_id, e.name, e.manager_id, a.depth + 1
    FROM employees_iv e JOIN ancestors a ON e.emp_id = a.manager_id
)
SELECT emp_id, name, depth FROM ancestors ORDER BY depth;
