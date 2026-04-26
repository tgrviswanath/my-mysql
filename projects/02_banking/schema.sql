-- ============================================================
-- 02_banking/schema.sql + queries.sql
-- Banking system: accounts, transactions, fraud detection
-- ============================================================

CREATE DATABASE IF NOT EXISTS banking;
USE banking;

-- ── Customers ─────────────────────────────────────────────────
CREATE TABLE customers (
    customer_id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    first_name  VARCHAR(50)  NOT NULL,
    last_name   VARCHAR(50)  NOT NULL,
    email       VARCHAR(100) NOT NULL,
    phone       VARCHAR(20),
    kyc_status  ENUM('pending','verified','rejected') NOT NULL DEFAULT 'pending',
    created_at  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE INDEX idx_email (email)
);

-- ── Accounts ──────────────────────────────────────────────────
CREATE TABLE accounts (
    account_id   BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    customer_id  BIGINT UNSIGNED NOT NULL,
    account_no   VARCHAR(20) NOT NULL,
    type         ENUM('checking','savings','credit') NOT NULL,
    balance      DECIMAL(15,2) NOT NULL DEFAULT 0.00,
    credit_limit DECIMAL(15,2) NOT NULL DEFAULT 0.00,
    status       ENUM('active','frozen','closed') NOT NULL DEFAULT 'active',
    opened_at    DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE INDEX idx_account_no (account_no),
    INDEX idx_customer (customer_id),
    FOREIGN KEY (customer_id) REFERENCES customers(customer_id),
    CHECK (balance >= -credit_limit)  -- allows negative balance up to credit limit
);

-- ── Transactions ──────────────────────────────────────────────
CREATE TABLE transactions (
    txn_id          BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    account_id      BIGINT UNSIGNED NOT NULL,
    type            ENUM('debit','credit') NOT NULL,
    amount          DECIMAL(15,2) NOT NULL,
    balance_after   DECIMAL(15,2) NOT NULL,
    description     VARCHAR(200),
    reference_id    VARCHAR(100),
    channel         ENUM('atm','online','branch','api') NOT NULL DEFAULT 'api',
    status          ENUM('pending','completed','failed','reversed') NOT NULL DEFAULT 'completed',
    created_at      DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (account_id) REFERENCES accounts(account_id),
    INDEX idx_account_created (account_id, created_at),
    INDEX idx_created_at (created_at),
    INDEX idx_reference (reference_id)
) PARTITION BY RANGE (YEAR(created_at)) (
    PARTITION p2022 VALUES LESS THAN (2023),
    PARTITION p2023 VALUES LESS THAN (2024),
    PARTITION p2024 VALUES LESS THAN (2025),
    PARTITION p_future VALUES LESS THAN MAXVALUE
);

-- ── Fraud flags ───────────────────────────────────────────────
CREATE TABLE fraud_alerts (
    alert_id    BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    account_id  BIGINT UNSIGNED NOT NULL,
    txn_id      BIGINT UNSIGNED,
    rule_name   VARCHAR(100) NOT NULL,
    severity    ENUM('low','medium','high','critical') NOT NULL,
    details     JSON,
    resolved    TINYINT(1) NOT NULL DEFAULT 0,
    created_at  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (account_id) REFERENCES accounts(account_id),
    INDEX idx_account_resolved (account_id, resolved),
    INDEX idx_severity_created (severity, created_at)
);

-- ── Transfer procedure (atomic) ───────────────────────────────
DELIMITER $$
CREATE PROCEDURE IF NOT EXISTS transfer(
    IN p_from_acct  BIGINT,
    IN p_to_acct    BIGINT,
    IN p_amount     DECIMAL(15,2),
    IN p_desc       VARCHAR(200)
)
BEGIN
    DECLARE v_from_balance DECIMAL(15,2);
    DECLARE v_from_limit   DECIMAL(15,2);
    DECLARE v_ref          VARCHAR(100);
    DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN ROLLBACK; RESIGNAL; END;

    SET v_ref = CONCAT('TXN-', UNIX_TIMESTAMP(), '-', FLOOR(RAND()*10000));

    START TRANSACTION;
        -- Lock both accounts in consistent order (lower ID first)
        IF p_from_acct < p_to_acct THEN
            SELECT balance, credit_limit INTO v_from_balance, v_from_limit
            FROM accounts WHERE account_id = p_from_acct AND status = 'active' FOR UPDATE;
            SELECT 1 FROM accounts WHERE account_id = p_to_acct AND status = 'active' FOR UPDATE;
        ELSE
            SELECT 1 FROM accounts WHERE account_id = p_to_acct AND status = 'active' FOR UPDATE;
            SELECT balance, credit_limit INTO v_from_balance, v_from_limit
            FROM accounts WHERE account_id = p_from_acct AND status = 'active' FOR UPDATE;
        END IF;

        IF v_from_balance IS NULL THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Account not found or frozen';
        END IF;

        IF v_from_balance - p_amount < -v_from_limit THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Insufficient funds';
        END IF;

        -- Debit source
        UPDATE accounts SET balance = balance - p_amount WHERE account_id = p_from_acct;
        INSERT INTO transactions (account_id, type, amount, balance_after, description, reference_id)
        SELECT p_from_acct, 'debit', p_amount, balance, p_desc, v_ref FROM accounts WHERE account_id = p_from_acct;

        -- Credit destination
        UPDATE accounts SET balance = balance + p_amount WHERE account_id = p_to_acct;
        INSERT INTO transactions (account_id, type, amount, balance_after, description, reference_id)
        SELECT p_to_acct, 'credit', p_amount, balance, p_desc, v_ref FROM accounts WHERE account_id = p_to_acct;
    COMMIT;

    SELECT v_ref AS reference_id;
END$$
DELIMITER ;

-- ── Fraud detection queries ───────────────────────────────────

-- Rule 1: Large transactions (> $10,000)
SELECT t.txn_id, t.account_id, t.amount, t.created_at
FROM transactions t
WHERE t.amount > 10000 AND t.status = 'completed'
  AND t.created_at >= DATE_SUB(NOW(), INTERVAL 1 DAY);

-- Rule 2: Velocity check — more than 10 transactions in 1 hour
SELECT account_id, COUNT(*) AS txn_count, SUM(amount) AS total_amount
FROM transactions
WHERE created_at >= DATE_SUB(NOW(), INTERVAL 1 HOUR)
  AND status = 'completed'
GROUP BY account_id
HAVING txn_count > 10;

-- Rule 3: Round-number transactions (common in fraud)
SELECT account_id, COUNT(*) AS round_txn_count
FROM transactions
WHERE amount = FLOOR(amount)  -- no cents
  AND amount >= 1000
  AND created_at >= DATE_SUB(NOW(), INTERVAL 7 DAY)
GROUP BY account_id
HAVING round_txn_count >= 5;

-- ── Account statement ─────────────────────────────────────────
SELECT
    t.txn_id,
    t.type,
    t.amount,
    t.balance_after,
    t.description,
    t.channel,
    t.created_at,
    SUM(CASE WHEN t.type = 'credit' THEN t.amount ELSE -t.amount END)
        OVER (PARTITION BY t.account_id ORDER BY t.created_at, t.txn_id) AS running_balance
FROM transactions t
WHERE t.account_id = 1
  AND t.created_at >= DATE_SUB(NOW(), INTERVAL 30 DAY)
ORDER BY t.created_at DESC;
