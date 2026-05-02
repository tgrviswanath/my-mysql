-- ============================================================
-- 05_normalization.sql
-- Normalization examples: 1NF → 3NF with schema evolution
-- ============================================================
USE practice_db;

-- ── BEFORE normalization (violates 1NF, 2NF, 3NF) ────────────
CREATE TABLE IF NOT EXISTS orders_unnormalized (
    order_id     INT,
    customer_name VARCHAR(100),
    customer_email VARCHAR(100),
    customer_city  VARCHAR(50),
    products      VARCHAR(500),   -- comma-separated: violates 1NF
    order_total   DECIMAL(10,2)
);

-- ── Step 1: Apply 1NF — atomic values ────────────────────────
CREATE TABLE IF NOT EXISTS orders_1nf (
    order_id     INT,
    customer_name VARCHAR(100),
    customer_email VARCHAR(100),
    customer_city  VARCHAR(50),
    product_name  VARCHAR(100),   -- one product per row
    quantity      INT,
    unit_price    DECIMAL(10,2),
    PRIMARY KEY (order_id, product_name)
);

-- ── Step 2: Apply 2NF — remove partial dependencies ──────────
-- product_name depends only on product_name (not full PK)
CREATE TABLE IF NOT EXISTS customers_2nf (
    customer_id  INT AUTO_INCREMENT PRIMARY KEY,
    name         VARCHAR(100) NOT NULL,
    email        VARCHAR(100) NOT NULL UNIQUE,
    city         VARCHAR(50)
);

CREATE TABLE IF NOT EXISTS products_2nf (
    product_id   INT AUTO_INCREMENT PRIMARY KEY,
    name         VARCHAR(100) NOT NULL,
    unit_price   DECIMAL(10,2) NOT NULL
);

CREATE TABLE IF NOT EXISTS orders_2nf (
    order_id     INT AUTO_INCREMENT PRIMARY KEY,
    customer_id  INT NOT NULL,
    FOREIGN KEY (customer_id) REFERENCES customers_2nf(customer_id)
);

CREATE TABLE IF NOT EXISTS order_items_2nf (
    order_id    INT NOT NULL,
    product_id  INT NOT NULL,
    quantity    INT NOT NULL,
    PRIMARY KEY (order_id, product_id),
    FOREIGN KEY (order_id)   REFERENCES orders_2nf(order_id),
    FOREIGN KEY (product_id) REFERENCES products_2nf(product_id)
);

-- ── Step 3: Apply 3NF — remove transitive dependencies ───────
-- city depends on zip_code, not customer_id (if we had zip)
-- Here: separate city into a lookup if needed
CREATE TABLE IF NOT EXISTS cities_3nf (
    city_id   INT AUTO_INCREMENT PRIMARY KEY,
    city_name VARCHAR(50) NOT NULL,
    country   VARCHAR(50) NOT NULL DEFAULT 'US'
);

CREATE TABLE IF NOT EXISTS customers_3nf (
    customer_id INT AUTO_INCREMENT PRIMARY KEY,
    name        VARCHAR(100) NOT NULL,
    email       VARCHAR(100) NOT NULL UNIQUE,
    city_id     INT,
    FOREIGN KEY (city_id) REFERENCES cities_3nf(city_id)
);

-- ── Seed normalized data ──────────────────────────────────────
INSERT INTO cities_3nf (city_name, country) VALUES
    ('New York', 'US'), ('San Francisco', 'US'), ('London', 'UK');

INSERT INTO customers_3nf (name, email, city_id) VALUES
    ('Alice Smith',  'alice@example.com', 1),
    ('Bob Jones',    'bob@example.com',   2),
    ('Carol White',  'carol@example.com', 3);

INSERT INTO products_2nf (name, unit_price) VALUES
    ('Laptop Pro',     1299.99),
    ('Wireless Mouse',   29.99),
    ('USB-C Hub',        49.99);

INSERT INTO orders_2nf (customer_id) VALUES (1), (2), (1);

INSERT INTO order_items_2nf (order_id, product_id, quantity) VALUES
    (1, 1, 1), (1, 2, 2),
    (2, 3, 1), (2, 2, 1),
    (3, 1, 2);

-- ── Query normalized schema (requires JOINs) ─────────────────
SELECT
    o.order_id,
    c.name          AS customer,
    ci.city_name    AS city,
    p.name          AS product,
    oi.quantity,
    p.unit_price,
    oi.quantity * p.unit_price AS line_total
FROM orders_2nf o
JOIN customers_3nf c  ON o.customer_id = c.customer_id
JOIN cities_3nf ci    ON c.city_id = ci.city_id
JOIN order_items_2nf oi ON o.order_id = oi.order_id
JOIN products_2nf p   ON oi.product_id = p.product_id
ORDER BY o.order_id, p.name;

-- ── Order totals (derived, not stored — normalized) ───────────
SELECT
    o.order_id,
    c.name AS customer,
    SUM(oi.quantity * p.unit_price) AS order_total
FROM orders_2nf o
JOIN customers_3nf c  ON o.customer_id = c.customer_id
JOIN order_items_2nf oi ON o.order_id = oi.order_id
JOIN products_2nf p   ON oi.product_id = p.product_id
GROUP BY o.order_id, c.name
ORDER BY order_total DESC;
