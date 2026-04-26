-- ============================================================
-- 01_ecommerce/schema.sql
-- Production-grade e-commerce database schema
-- ============================================================

CREATE DATABASE IF NOT EXISTS ecommerce;
USE ecommerce;

-- ── Users & Auth ──────────────────────────────────────────────
CREATE TABLE users (
    user_id     BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    email       VARCHAR(100) NOT NULL,
    username    VARCHAR(50)  NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    status      ENUM('active','inactive','banned') NOT NULL DEFAULT 'active',
    created_at  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    deleted_at  DATETIME NULL,
    UNIQUE INDEX idx_email (email),
    UNIQUE INDEX idx_username (username),
    INDEX idx_status_created (status, created_at)
);

-- ── Addresses ─────────────────────────────────────────────────
CREATE TABLE addresses (
    address_id  BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    user_id     BIGINT UNSIGNED NOT NULL,
    type        ENUM('billing','shipping') NOT NULL DEFAULT 'shipping',
    line1       VARCHAR(200) NOT NULL,
    line2       VARCHAR(200),
    city        VARCHAR(100) NOT NULL,
    state       VARCHAR(100),
    postal_code VARCHAR(20)  NOT NULL,
    country     CHAR(2)      NOT NULL DEFAULT 'US',
    is_default  TINYINT(1)   NOT NULL DEFAULT 0,
    FOREIGN KEY (user_id) REFERENCES users(user_id) ON DELETE CASCADE,
    INDEX idx_user_type (user_id, type)
);

-- ── Categories ────────────────────────────────────────────────
CREATE TABLE categories (
    category_id   INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    parent_id     INT UNSIGNED NULL,
    name          VARCHAR(100) NOT NULL,
    slug          VARCHAR(100) NOT NULL,
    description   TEXT,
    UNIQUE INDEX idx_slug (slug),
    FOREIGN KEY (parent_id) REFERENCES categories(category_id)
);

-- ── Products ──────────────────────────────────────────────────
CREATE TABLE products (
    product_id    BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    category_id   INT UNSIGNED NOT NULL,
    sku           VARCHAR(50)  NOT NULL,
    name          VARCHAR(200) NOT NULL,
    description   TEXT,
    price         DECIMAL(10,2) NOT NULL,
    cost          DECIMAL(10,2) NOT NULL,
    status        ENUM('active','inactive','discontinued') NOT NULL DEFAULT 'active',
    created_at    DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at    DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    UNIQUE INDEX idx_sku (sku),
    INDEX idx_category_status (category_id, status),
    INDEX idx_price (price),
    FOREIGN KEY (category_id) REFERENCES categories(category_id)
);

-- ── Inventory ─────────────────────────────────────────────────
CREATE TABLE inventory (
    product_id    BIGINT UNSIGNED PRIMARY KEY,
    stock         INT NOT NULL DEFAULT 0,
    reserved      INT NOT NULL DEFAULT 0,
    reorder_point INT NOT NULL DEFAULT 10,
    updated_at    DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    CHECK (stock >= 0),
    CHECK (reserved >= 0),
    FOREIGN KEY (product_id) REFERENCES products(product_id)
);

-- ── Orders ────────────────────────────────────────────────────
CREATE TABLE orders (
    order_id        BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    user_id         BIGINT UNSIGNED NOT NULL,
    shipping_addr   BIGINT UNSIGNED NOT NULL,
    status          ENUM('pending','confirmed','processing','shipped','delivered','cancelled','refunded')
                    NOT NULL DEFAULT 'pending',
    subtotal        DECIMAL(10,2) NOT NULL,
    tax             DECIMAL(10,2) NOT NULL DEFAULT 0.00,
    shipping_cost   DECIMAL(10,2) NOT NULL DEFAULT 0.00,
    total           DECIMAL(10,2) NOT NULL,
    notes           TEXT,
    created_at      DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at      DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id)       REFERENCES users(user_id),
    FOREIGN KEY (shipping_addr) REFERENCES addresses(address_id),
    INDEX idx_user_status (user_id, status),
    INDEX idx_status_created (status, created_at),
    INDEX idx_created_at (created_at)
);

-- ── Order Items ───────────────────────────────────────────────
CREATE TABLE order_items (
    item_id     BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    order_id    BIGINT UNSIGNED NOT NULL,
    product_id  BIGINT UNSIGNED NOT NULL,
    quantity    INT NOT NULL,
    unit_price  DECIMAL(10,2) NOT NULL,  -- snapshot at time of order
    discount    DECIMAL(10,2) NOT NULL DEFAULT 0.00,
    FOREIGN KEY (order_id)   REFERENCES orders(order_id) ON DELETE CASCADE,
    FOREIGN KEY (product_id) REFERENCES products(product_id),
    INDEX idx_order (order_id),
    INDEX idx_product (product_id)
);

-- ── Payments ──────────────────────────────────────────────────
CREATE TABLE payments (
    payment_id      BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    order_id        BIGINT UNSIGNED NOT NULL,
    method          ENUM('card','paypal','bank_transfer','crypto') NOT NULL,
    status          ENUM('pending','completed','failed','refunded') NOT NULL DEFAULT 'pending',
    amount          DECIMAL(10,2) NOT NULL,
    gateway_txn_id  VARCHAR(100),
    processed_at    DATETIME,
    created_at      DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (order_id) REFERENCES orders(order_id),
    INDEX idx_order (order_id),
    INDEX idx_status_created (status, created_at)
);

-- ── Reviews ───────────────────────────────────────────────────
CREATE TABLE reviews (
    review_id   BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    product_id  BIGINT UNSIGNED NOT NULL,
    user_id     BIGINT UNSIGNED NOT NULL,
    rating      TINYINT NOT NULL CHECK (rating BETWEEN 1 AND 5),
    title       VARCHAR(200),
    body        TEXT,
    verified    TINYINT(1) NOT NULL DEFAULT 0,
    created_at  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE INDEX idx_user_product (user_id, product_id),
    INDEX idx_product_rating (product_id, rating),
    FOREIGN KEY (product_id) REFERENCES products(product_id),
    FOREIGN KEY (user_id)    REFERENCES users(user_id)
);

-- ── Coupons ───────────────────────────────────────────────────
CREATE TABLE coupons (
    coupon_id   INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    code        VARCHAR(50) NOT NULL,
    type        ENUM('percent','fixed') NOT NULL,
    value       DECIMAL(10,2) NOT NULL,
    min_order   DECIMAL(10,2) NOT NULL DEFAULT 0.00,
    max_uses    INT,
    used_count  INT NOT NULL DEFAULT 0,
    expires_at  DATETIME,
    UNIQUE INDEX idx_code (code)
);
