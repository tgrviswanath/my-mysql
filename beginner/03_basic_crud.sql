-- ============================================================
-- 03_basic_crud.sql
-- SELECT, INSERT, UPDATE, DELETE, GROUP BY, HAVING
-- ============================================================
USE practice_db;

-- ── Setup ────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS products (
    product_id   INT AUTO_INCREMENT PRIMARY KEY,
    name         VARCHAR(100) NOT NULL,
    category     VARCHAR(50)  NOT NULL,
    price        DECIMAL(10,2) NOT NULL,
    stock        INT NOT NULL DEFAULT 0,
    created_at   DATETIME DEFAULT CURRENT_TIMESTAMP
);

INSERT INTO products (name, category, price, stock) VALUES
    ('Laptop Pro',      'Electronics', 1299.99, 50),
    ('Wireless Mouse',  'Electronics',   29.99, 200),
    ('USB-C Hub',       'Electronics',   49.99, 150),
    ('Desk Chair',      'Furniture',    399.99, 30),
    ('Standing Desk',   'Furniture',    699.99, 20),
    ('Notebook',        'Stationery',     4.99, 500),
    ('Pen Set',         'Stationery',     9.99, 300),
    ('Monitor 27"',     'Electronics', 449.99, 40),
    ('Keyboard',        'Electronics',  79.99, 120),
    ('Webcam HD',       'Electronics',  89.99, 80);

-- ── SELECT patterns ──────────────────────────────────────────
-- Basic select with alias
SELECT product_id, name, price, price * 1.1 AS price_with_tax
FROM products
ORDER BY price DESC;

-- Filter with WHERE
SELECT name, price FROM products
WHERE category = 'Electronics' AND price < 100
ORDER BY price ASC;

-- BETWEEN and IN
SELECT name, price FROM products
WHERE price BETWEEN 50 AND 500;

SELECT name, category FROM products
WHERE category IN ('Electronics', 'Furniture');

-- LIKE pattern matching
SELECT name FROM products WHERE name LIKE '%Pro%';
SELECT name FROM products WHERE name LIKE 'W%';   -- starts with W
SELECT name FROM products WHERE name LIKE '%"';   -- ends with "

-- NULL handling
SELECT name, stock FROM products WHERE stock IS NOT NULL;

-- ── Aggregates & GROUP BY ─────────────────────────────────────
SELECT category,
       COUNT(*)            AS product_count,
       AVG(price)          AS avg_price,
       MIN(price)          AS min_price,
       MAX(price)          AS max_price,
       SUM(price * stock)  AS total_inventory_value
FROM products
GROUP BY category
ORDER BY total_inventory_value DESC;

-- HAVING: filter groups (not rows)
SELECT category, COUNT(*) AS cnt
FROM products
GROUP BY category
HAVING cnt >= 3;

-- GROUP_CONCAT
SELECT category, GROUP_CONCAT(name ORDER BY price DESC SEPARATOR ', ') AS product_list
FROM products
GROUP BY category;

-- ── INSERT patterns ───────────────────────────────────────────
-- Single insert
INSERT INTO products (name, category, price, stock)
VALUES ('Headphones', 'Electronics', 149.99, 60);

-- Multi-row insert (preferred)
INSERT INTO products (name, category, price, stock) VALUES
    ('Mousepad XL',  'Electronics', 19.99, 250),
    ('Cable Organizer','Stationery',  7.99, 400);

-- Upsert
INSERT INTO products (product_id, name, category, price, stock)
VALUES (1, 'Laptop Pro Max', 'Electronics', 1499.99, 45)
ON DUPLICATE KEY UPDATE price = VALUES(price), stock = VALUES(stock);

-- ── UPDATE patterns ───────────────────────────────────────────
-- Simple update
UPDATE products SET price = price * 0.9 WHERE category = 'Stationery';

-- Update with subquery (discount products with low stock)
UPDATE products
SET price = price * 0.85
WHERE product_id IN (
    SELECT product_id FROM (
        SELECT product_id FROM products WHERE stock < 25
    ) AS sub
);

-- ── DELETE patterns ───────────────────────────────────────────
-- Delete specific rows
DELETE FROM products WHERE stock = 0;

-- Safe delete with LIMIT (prevents accidental mass delete)
DELETE FROM products WHERE category = 'Stationery' ORDER BY price ASC LIMIT 1;

-- ── Execution order demo ──────────────────────────────────────
-- Alias in ORDER BY works (ORDER BY runs after SELECT)
SELECT name, price * 1.1 AS taxed_price
FROM products
ORDER BY taxed_price DESC;

-- Alias in WHERE does NOT work — use subquery or repeat expression
-- SELECT name, price * 1.1 AS taxed_price FROM products WHERE taxed_price > 100; -- ERROR
SELECT name, taxed_price FROM (
    SELECT name, price * 1.1 AS taxed_price FROM products
) AS sub
WHERE taxed_price > 100;

-- ── LIMIT & OFFSET (pagination) ───────────────────────────────
-- Page 1 (rows 1-5)
SELECT name, price FROM products ORDER BY price DESC LIMIT 5 OFFSET 0;
-- Page 2 (rows 6-10)
SELECT name, price FROM products ORDER BY price DESC LIMIT 5 OFFSET 5;
