-- ============================================================
-- 01_ecommerce/queries.sql
-- Complex queries, analytics, optimization
-- ============================================================
USE ecommerce;

-- ── 1. Revenue by category (last 30 days) ────────────────────
SELECT
    c.name AS category,
    COUNT(DISTINCT o.order_id)  AS order_count,
    SUM(oi.quantity)            AS units_sold,
    SUM(oi.quantity * oi.unit_price - oi.discount) AS revenue
FROM orders o
JOIN order_items oi ON o.order_id = oi.order_id
JOIN products p     ON oi.product_id = p.product_id
JOIN categories c   ON p.category_id = c.category_id
WHERE o.status IN ('confirmed','processing','shipped','delivered')
  AND o.created_at >= DATE_SUB(NOW(), INTERVAL 30 DAY)
GROUP BY c.category_id, c.name
ORDER BY revenue DESC;

-- ── 2. Customer lifetime value (CLV) ─────────────────────────
SELECT
    u.user_id,
    u.email,
    COUNT(o.order_id)       AS total_orders,
    SUM(o.total)            AS lifetime_value,
    AVG(o.total)            AS avg_order_value,
    MIN(o.created_at)       AS first_order,
    MAX(o.created_at)       AS last_order,
    DATEDIFF(MAX(o.created_at), MIN(o.created_at)) AS customer_age_days
FROM users u
JOIN orders o ON u.user_id = o.user_id
WHERE o.status NOT IN ('cancelled','refunded')
GROUP BY u.user_id, u.email
ORDER BY lifetime_value DESC
LIMIT 100;

-- ── 3. Products low on stock ──────────────────────────────────
SELECT
    p.product_id, p.sku, p.name,
    i.stock, i.reserved,
    i.stock - i.reserved AS available,
    i.reorder_point
FROM products p
JOIN inventory i ON p.product_id = i.product_id
WHERE p.status = 'active'
  AND (i.stock - i.reserved) <= i.reorder_point
ORDER BY available ASC;

-- ── 4. Monthly revenue trend (window function) ───────────────
WITH monthly AS (
    SELECT
        DATE_FORMAT(created_at, '%Y-%m') AS month,
        SUM(total) AS revenue
    FROM orders
    WHERE status NOT IN ('cancelled','refunded')
    GROUP BY DATE_FORMAT(created_at, '%Y-%m')
)
SELECT
    month,
    revenue,
    LAG(revenue) OVER (ORDER BY month)  AS prev_month,
    ROUND(
        (revenue - LAG(revenue) OVER (ORDER BY month)) /
        LAG(revenue) OVER (ORDER BY month) * 100, 2
    ) AS growth_pct,
    SUM(revenue) OVER (ORDER BY month ROWS UNBOUNDED PRECEDING) AS cumulative_revenue
FROM monthly
ORDER BY month;

-- ── 5. Top products by revenue with rank ─────────────────────
SELECT
    p.product_id, p.name, p.sku,
    SUM(oi.quantity * oi.unit_price) AS revenue,
    RANK()       OVER (ORDER BY SUM(oi.quantity * oi.unit_price) DESC) AS revenue_rank,
    DENSE_RANK() OVER (ORDER BY SUM(oi.quantity * oi.unit_price) DESC) AS dense_rank,
    NTILE(4)     OVER (ORDER BY SUM(oi.quantity * oi.unit_price) DESC) AS quartile
FROM order_items oi
JOIN products p ON oi.product_id = p.product_id
JOIN orders o   ON oi.order_id = o.order_id
WHERE o.status NOT IN ('cancelled','refunded')
GROUP BY p.product_id, p.name, p.sku
ORDER BY revenue DESC
LIMIT 20;

-- ── 6. Cohort retention analysis ─────────────────────────────
WITH cohorts AS (
    SELECT
        user_id,
        DATE_FORMAT(MIN(created_at), '%Y-%m') AS cohort_month
    FROM orders
    GROUP BY user_id
),
order_months AS (
    SELECT
        o.user_id,
        c.cohort_month,
        DATE_FORMAT(o.created_at, '%Y-%m') AS order_month,
        PERIOD_DIFF(
            DATE_FORMAT(o.created_at, '%Y%m'),
            DATE_FORMAT(c.cohort_month, '%Y%m') + 0
        ) AS months_since_first
    FROM orders o
    JOIN cohorts c ON o.user_id = c.user_id
)
SELECT
    cohort_month,
    months_since_first,
    COUNT(DISTINCT user_id) AS users
FROM order_months
GROUP BY cohort_month, months_since_first
ORDER BY cohort_month, months_since_first;

-- ── 7. Abandoned cart simulation (orders stuck in pending) ────
SELECT
    u.email,
    o.order_id,
    o.total,
    o.created_at,
    TIMESTAMPDIFF(HOUR, o.created_at, NOW()) AS hours_pending
FROM orders o
JOIN users u ON o.user_id = u.user_id
WHERE o.status = 'pending'
  AND o.created_at < DATE_SUB(NOW(), INTERVAL 24 HOUR)
ORDER BY hours_pending DESC;

-- ── 8. Product recommendation (frequently bought together) ────
SELECT
    a.product_id AS product_a,
    b.product_id AS product_b,
    COUNT(*) AS co_purchase_count
FROM order_items a
JOIN order_items b ON a.order_id = b.order_id AND a.product_id < b.product_id
GROUP BY a.product_id, b.product_id
HAVING co_purchase_count >= 5
ORDER BY co_purchase_count DESC
LIMIT 20;

-- ── 9. Inventory turnover rate ────────────────────────────────
SELECT
    p.product_id, p.name,
    SUM(oi.quantity) AS units_sold_30d,
    i.stock AS current_stock,
    ROUND(i.stock / NULLIF(SUM(oi.quantity) / 30, 0), 1) AS days_of_stock_remaining
FROM products p
JOIN inventory i    ON p.product_id = i.product_id
LEFT JOIN order_items oi ON p.product_id = oi.product_id
LEFT JOIN orders o  ON oi.order_id = o.order_id
    AND o.created_at >= DATE_SUB(NOW(), INTERVAL 30 DAY)
    AND o.status NOT IN ('cancelled','refunded')
WHERE p.status = 'active'
GROUP BY p.product_id, p.name, i.stock
ORDER BY days_of_stock_remaining ASC;

-- ── 10. Place order with inventory reservation (procedure) ────
DELIMITER $$
CREATE PROCEDURE IF NOT EXISTS place_order(
    IN p_user_id    BIGINT,
    IN p_addr_id    BIGINT,
    IN p_product_id BIGINT,
    IN p_quantity   INT
)
BEGIN
    DECLARE v_price   DECIMAL(10,2);
    DECLARE v_stock   INT;
    DECLARE v_order_id BIGINT;
    DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN ROLLBACK; RESIGNAL; END;

    START TRANSACTION;
        -- Lock inventory row
        SELECT i.stock, p.price INTO v_stock, v_price
        FROM inventory i JOIN products p ON i.product_id = p.product_id
        WHERE i.product_id = p_product_id FOR UPDATE;

        IF v_stock < p_quantity THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Insufficient stock';
        END IF;

        -- Create order
        INSERT INTO orders (user_id, shipping_addr, status, subtotal, total)
        VALUES (p_user_id, p_addr_id, 'confirmed', v_price * p_quantity, v_price * p_quantity);
        SET v_order_id = LAST_INSERT_ID();

        -- Add order item
        INSERT INTO order_items (order_id, product_id, quantity, unit_price)
        VALUES (v_order_id, p_product_id, p_quantity, v_price);

        -- Deduct inventory
        UPDATE inventory SET stock = stock - p_quantity WHERE product_id = p_product_id;
    COMMIT;

    SELECT v_order_id AS order_id;
END$$
DELIMITER ;
