-- ============================================================
-- 02_data_types_constraints.sql
-- Data types, constraints, DDL practice
-- ============================================================

CREATE DATABASE IF NOT EXISTS practice_db;
USE practice_db;

-- ── 1. Table with all major data types ──────────────────────
CREATE TABLE IF NOT EXISTS data_type_demo (
    id            INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    tiny_flag     TINYINT(1)       NOT NULL DEFAULT 0,
    small_count   SMALLINT         NOT NULL DEFAULT 0,
    big_id        BIGINT UNSIGNED  NOT NULL,
    price         DECIMAL(15, 2)   NOT NULL,
    rating        FLOAT,                          -- acceptable for non-financial
    code          CHAR(3)          NOT NULL,       -- fixed: ISO country code
    name          VARCHAR(100)     NOT NULL,
    description   TEXT,
    created_at    DATETIME         NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at    TIMESTAMP        NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    birth_date    DATE,
    status        ENUM('active','inactive','pending') NOT NULL DEFAULT 'pending'
);

-- ── 2. Constraints demo ─────────────────────────────────────
CREATE TABLE IF NOT EXISTS departments (
    dept_id   INT AUTO_INCREMENT PRIMARY KEY,
    dept_name VARCHAR(50) NOT NULL UNIQUE,
    budget    DECIMAL(15,2) CHECK (budget >= 0)
);

CREATE TABLE IF NOT EXISTS employees (
    emp_id      INT AUTO_INCREMENT PRIMARY KEY,
    dept_id     INT NOT NULL,
    email       VARCHAR(100) NOT NULL UNIQUE,
    salary      DECIMAL(10,2) NOT NULL CHECK (salary > 0),
    hire_date   DATE NOT NULL DEFAULT (CURRENT_DATE),
    CONSTRAINT fk_emp_dept FOREIGN KEY (dept_id)
        REFERENCES departments(dept_id)
        ON DELETE RESTRICT
        ON UPDATE CASCADE
);

-- ── 3. Insert valid data ─────────────────────────────────────
INSERT INTO departments (dept_name, budget) VALUES
    ('Engineering', 500000.00),
    ('Marketing',   200000.00),
    ('HR',          150000.00);

INSERT INTO employees (dept_id, email, salary, hire_date) VALUES
    (1, 'alice@example.com', 95000.00, '2022-03-15'),
    (1, 'bob@example.com',   88000.00, '2021-07-01'),
    (2, 'carol@example.com', 72000.00, '2023-01-10');

-- ── 4. Constraint violation examples (commented out) ─────────
-- INSERT INTO employees (dept_id, email, salary) VALUES (99, 'x@x.com', 50000); -- FK violation
-- INSERT INTO employees (dept_id, email, salary) VALUES (1, 'alice@example.com', 50000); -- UNIQUE violation
-- INSERT INTO employees (dept_id, email, salary) VALUES (1, 'new@x.com', -100); -- CHECK violation

-- ── 5. CHAR vs VARCHAR storage demo ─────────────────────────
CREATE TABLE IF NOT EXISTS char_vs_varchar (
    fixed_code  CHAR(10),
    var_name    VARCHAR(10)
);
INSERT INTO char_vs_varchar VALUES ('US', 'US');
-- CHAR(10) stores 'US        ' (padded), VARCHAR(10) stores 'US' (2 bytes + 1 length byte)
SELECT CHAR_LENGTH(fixed_code), CHAR_LENGTH(var_name) FROM char_vs_varchar;
SELECT LENGTH(fixed_code), LENGTH(var_name) FROM char_vs_varchar;

-- ── 6. DECIMAL precision demo ────────────────────────────────
SELECT 0.1 + 0.2;                          -- FLOAT: may show 0.30000000000000004
SELECT CAST(0.1 AS DECIMAL(5,2))
     + CAST(0.2 AS DECIMAL(5,2));          -- DECIMAL: exact 0.30

-- ── 7. TIMESTAMP vs DATETIME timezone behavior ───────────────
SET time_zone = '+00:00';
INSERT INTO data_type_demo (big_id, price, code, name)
    VALUES (1001, 29.99, 'USD', 'Test Product');
SELECT created_at, updated_at FROM data_type_demo WHERE id = LAST_INSERT_ID();

SET time_zone = '+05:30';  -- Switch to IST
SELECT created_at, updated_at FROM data_type_demo WHERE id = 1;
-- TIMESTAMP shifts with timezone; DATETIME stays the same

-- ── 8. ENUM internals ────────────────────────────────────────
SELECT status + 0 AS enum_int_value FROM data_type_demo LIMIT 5;
-- ENUM stored as 1-based integer: active=1, inactive=2, pending=3

-- ── 9. NULL behavior ─────────────────────────────────────────
SELECT NULL = NULL;       -- NULL (not TRUE)
SELECT NULL IS NULL;      -- 1 (TRUE)
SELECT NULL <=> NULL;     -- 1 (NULL-safe equality)
SELECT COALESCE(NULL, NULL, 'fallback');  -- 'fallback'

-- ── 10. Modify column type (DDL) ─────────────────────────────
-- ALTER TABLE employees MODIFY COLUMN salary DECIMAL(12,2) NOT NULL;
-- ALTER TABLE employees ADD COLUMN phone VARCHAR(20) AFTER email;
-- ALTER TABLE employees DROP COLUMN phone;
