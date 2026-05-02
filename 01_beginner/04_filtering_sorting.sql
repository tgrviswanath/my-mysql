-- ============================================================
-- 04_filtering_sorting.sql
-- WHERE, ORDER BY, DISTINCT, CASE, string/date functions
-- ============================================================
USE practice_db;

-- ── DISTINCT ─────────────────────────────────────────────────
SELECT DISTINCT category FROM products ORDER BY category;

-- ── CASE expressions ─────────────────────────────────────────
SELECT name, price,
    CASE
        WHEN price < 50   THEN 'Budget'
        WHEN price < 200  THEN 'Mid-range'
        WHEN price < 600  THEN 'Premium'
        ELSE 'Luxury'
    END AS price_tier
FROM products
ORDER BY price;

-- Aggregate with CASE (pivot-style)
SELECT
    SUM(CASE WHEN category = 'Electronics' THEN 1 ELSE 0 END) AS electronics_count,
    SUM(CASE WHEN category = 'Furniture'   THEN 1 ELSE 0 END) AS furniture_count,
    SUM(CASE WHEN category = 'Stationery'  THEN 1 ELSE 0 END) AS stationery_count
FROM products;

-- ── String functions ─────────────────────────────────────────
SELECT
    UPPER(name)                    AS upper_name,
    LOWER(category)                AS lower_cat,
    LENGTH(name)                   AS name_len,
    CHAR_LENGTH(name)              AS char_len,   -- differs for multibyte chars
    SUBSTRING(name, 1, 5)          AS first5,
    CONCAT(name, ' [', category, ']') AS label,
    TRIM('  hello  ')              AS trimmed,
    REPLACE(name, ' ', '_')        AS slug,
    LOCATE('Pro', name)            AS pro_position
FROM products
WHERE name LIKE '%Pro%' OR name LIKE '%HD%';

-- ── Date functions ────────────────────────────────────────────
SELECT
    NOW()                          AS current_datetime,
    CURDATE()                      AS today,
    YEAR(created_at)               AS yr,
    MONTH(created_at)              AS mo,
    DAY(created_at)                AS dy,
    DAYNAME(created_at)            AS day_name,
    DATE_FORMAT(created_at, '%Y-%m')  AS year_month,
    DATEDIFF(NOW(), created_at)    AS days_since_created,
    DATE_ADD(created_at, INTERVAL 30 DAY) AS expires_at
FROM products
LIMIT 5;

-- Products created in the last 7 days
SELECT name FROM products
WHERE created_at >= DATE_SUB(NOW(), INTERVAL 7 DAY);

-- ── Numeric functions ─────────────────────────────────────────
SELECT
    ROUND(price, 0)    AS rounded,
    CEIL(price)        AS ceiling,
    FLOOR(price)       AS floor_val,
    ABS(-price)        AS absolute,
    MOD(stock, 10)     AS stock_mod_10,
    POWER(2, 10)       AS two_to_ten
FROM products LIMIT 5;

-- ── NULL functions ────────────────────────────────────────────
SELECT
    IFNULL(NULL, 'default')        AS ifnull_demo,
    COALESCE(NULL, NULL, 'found')  AS coalesce_demo,
    NULLIF(5, 5)                   AS nullif_same,   -- returns NULL
    NULLIF(5, 3)                   AS nullif_diff;   -- returns 5

-- ── ORDER BY multi-column ─────────────────────────────────────
SELECT name, category, price
FROM products
ORDER BY category ASC, price DESC;

-- ORDER BY expression
SELECT name, price, stock, price * stock AS inventory_value
FROM products
ORDER BY price * stock DESC
LIMIT 5;

-- ── Filtering with subquery ───────────────────────────────────
-- Products priced above average
SELECT name, price FROM products
WHERE price > (SELECT AVG(price) FROM products)
ORDER BY price DESC;
