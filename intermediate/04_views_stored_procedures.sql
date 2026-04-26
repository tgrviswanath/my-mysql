-- ============================================================
-- 04_views_stored_procedures.sql
-- Views, Stored Procedures, Functions, Triggers
-- ============================================================
USE practice_db;

-- ════════════════════════════════════════════════════════════
-- VIEWS
-- ════════════════════════════════════════════════════════════

-- Simple view: active users summary
CREATE OR REPLACE VIEW v_active_users AS
SELECT user_id, email, username, country, created_at
FROM users
WHERE status = 'active';

-- Query the view like a table
SELECT country, COUNT(*) AS active_count
FROM v_active_users
GROUP BY country
ORDER BY active_count DESC;

-- Updatable view (simple views on single table are updatable)
UPDATE v_active_users SET country = 'CA' WHERE user_id = 1;

-- View with JOIN (not updatable)
CREATE OR REPLACE VIEW v_order_summary AS
SELECT
    o.order_id,
    c.name    AS customer,
    ci.city_name AS city,
    SUM(oi.quantity * p.unit_price) AS total,
    COUNT(oi.product_id) AS item_count
FROM orders_2nf o
JOIN customers_3nf c  ON o.customer_id = c.customer_id
JOIN cities_3nf ci    ON c.city_id = ci.city_id
JOIN order_items_2nf oi ON o.order_id = oi.order_id
JOIN products_2nf p   ON oi.product_id = p.product_id
GROUP BY o.order_id, c.name, ci.city_name;

SELECT * FROM v_order_summary ORDER BY total DESC;

-- ════════════════════════════════════════════════════════════
-- STORED PROCEDURES
-- ════════════════════════════════════════════════════════════
DELIMITER $$

-- Procedure: get employees by department
CREATE PROCEDURE IF NOT EXISTS GetEmpByDept(IN p_dept_id INT)
BEGIN
    SELECT emp_id, name, salary
    FROM emp
    WHERE dept_id = p_dept_id
    ORDER BY salary DESC;
END$$

-- Procedure with OUT parameter
CREATE PROCEDURE IF NOT EXISTS GetDeptStats(
    IN  p_dept_id  INT,
    OUT p_count    INT,
    OUT p_avg_sal  DECIMAL(10,2)
)
BEGIN
    SELECT COUNT(*), AVG(salary)
    INTO p_count, p_avg_sal
    FROM emp
    WHERE dept_id = p_dept_id;
END$$

-- Procedure with error handling and transaction
CREATE PROCEDURE IF NOT EXISTS TransferEmployee(
    IN p_emp_id     INT,
    IN p_new_dept   INT
)
BEGIN
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    START TRANSACTION;
        UPDATE emp SET dept_id = p_new_dept WHERE emp_id = p_emp_id;
        -- Log the transfer
        INSERT INTO emp_audit (emp_id, action, changed_at)
        VALUES (p_emp_id, CONCAT('Transferred to dept ', p_new_dept), NOW());
    COMMIT;
END$$

DELIMITER ;

-- Call procedures
CALL GetEmpByDept(1);

CALL GetDeptStats(1, @cnt, @avg);
SELECT @cnt AS headcount, @avg AS avg_salary;

-- ════════════════════════════════════════════════════════════
-- STORED FUNCTIONS
-- ════════════════════════════════════════════════════════════
DELIMITER $$

CREATE FUNCTION IF NOT EXISTS salary_grade(p_salary DECIMAL(10,2))
RETURNS VARCHAR(10)
DETERMINISTIC
BEGIN
    RETURN CASE
        WHEN p_salary >= 100000 THEN 'Senior'
        WHEN p_salary >= 75000  THEN 'Mid'
        WHEN p_salary >= 50000  THEN 'Junior'
        ELSE 'Entry'
    END;
END$$

CREATE FUNCTION IF NOT EXISTS days_employed(p_hire_date DATE)
RETURNS INT
DETERMINISTIC
BEGIN
    RETURN DATEDIFF(CURDATE(), p_hire_date);
END$$

DELIMITER ;

-- Use functions in queries
SELECT name, salary, salary_grade(salary) AS grade FROM emp;

-- ════════════════════════════════════════════════════════════
-- TRIGGERS
-- ════════════════════════════════════════════════════════════

-- Audit table
CREATE TABLE IF NOT EXISTS emp_audit (
    audit_id   INT AUTO_INCREMENT PRIMARY KEY,
    emp_id     INT,
    action     VARCHAR(200),
    old_salary DECIMAL(10,2),
    new_salary DECIMAL(10,2),
    changed_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    changed_by VARCHAR(50) DEFAULT USER()
);

DELIMITER $$

-- BEFORE UPDATE trigger: validate salary change
CREATE TRIGGER IF NOT EXISTS trg_emp_salary_check
BEFORE UPDATE ON emp
FOR EACH ROW
BEGIN
    IF NEW.salary < 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Salary cannot be negative';
    END IF;
    IF NEW.salary > OLD.salary * 2 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Salary increase cannot exceed 100%';
    END IF;
END$$

-- AFTER UPDATE trigger: audit salary changes
CREATE TRIGGER IF NOT EXISTS trg_emp_salary_audit
AFTER UPDATE ON emp
FOR EACH ROW
BEGIN
    IF OLD.salary != NEW.salary THEN
        INSERT INTO emp_audit (emp_id, action, old_salary, new_salary)
        VALUES (NEW.emp_id, 'SALARY_CHANGE', OLD.salary, NEW.salary);
    END IF;
END$$

DELIMITER ;

-- Test trigger
UPDATE emp SET salary = 100000 WHERE emp_id = 2;
SELECT * FROM emp_audit;

-- Test validation trigger
-- UPDATE emp SET salary = -1000 WHERE emp_id = 2;  -- Should fail

-- ── View all stored objects ───────────────────────────────────
SHOW PROCEDURE STATUS WHERE Db = 'practice_db';
SHOW FUNCTION STATUS WHERE Db = 'practice_db';
SHOW TRIGGERS FROM practice_db;
