-- ============================================================
-- datasets/seed_users.sql
-- Realistic user dataset (10,000 rows)
-- ============================================================
USE practice_db;

-- Generate 10,000 users using recursive CTE
INSERT INTO users (email, username, status, country, created_at, last_login)
SELECT
    CONCAT('user', n, '@', ELT(1+FLOOR(RAND()*5),'gmail.com','yahoo.com','outlook.com','hotmail.com','icloud.com')) AS email,
    CONCAT('user_', LPAD(n, 5, '0')) AS username,
    ELT(1+FLOOR(RAND()*3), 'active','inactive','banned') AS status,
    ELT(1+FLOOR(RAND()*8), 'US','UK','CA','AU','DE','FR','JP','IN') AS country,
    DATE_SUB(NOW(), INTERVAL FLOOR(RAND()*730) DAY) AS created_at,
    CASE WHEN RAND() > 0.3
         THEN DATE_SUB(NOW(), INTERVAL FLOOR(RAND()*30) DAY)
         ELSE NULL END AS last_login
FROM (
    WITH RECURSIVE nums AS (
        SELECT 1001 AS n
        UNION ALL SELECT n + 1 FROM nums WHERE n < 11000
    )
    SELECT n FROM nums
) AS seq
ON DUPLICATE KEY UPDATE username = VALUES(username);

SELECT COUNT(*) AS total_users FROM users;
SELECT status, COUNT(*) AS cnt FROM users GROUP BY status;
SELECT country, COUNT(*) AS cnt FROM users GROUP BY country ORDER BY cnt DESC;
