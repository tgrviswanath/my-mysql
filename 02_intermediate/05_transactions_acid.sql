-- ============================================================
-- 05_transactions_acid.sql
-- Transactions, isolation levels, MVCC, savepoints
-- ============================================================
USE practice_db;

-- ── Setup: bank accounts ──────────────────────────────────────
CREATE TABLE IF NOT EXISTS accounts (
    account_id  INT AUTO_INCREMENT PRIMARY KEY,
    owner       VARCHAR(100) NOT NULL,
    balance     DECIMAL(15,2) NOT NULL DEFAULT 0.00,
    CHECK (balance >= 0)
);

CREATE TABLE IF NOT EXISTS txn_log (
    log_id      INT AUTO_INCREMENT PRIMARY KEY,
    from_acct   INT,
    to_acct     INT,
    amount      DECIMAL(15,2),
    status      ENUM('success','failed') NOT NULL,
    logged_at   DATETIME DEFAULT CURRENT_TIMESTAMP
);

INSERT INTO accounts (owner, balance) VALUES
    ('Alice', 10000.00),
    ('Bob',    5000.00),
    ('Carol',  8000.00);

-- ── Basic transaction: money transfer ────────────────────────
DELIMITER $$
CREATE PROCEDURE IF NOT EXISTS transfer_funds(
    IN p_from INT, IN p_to INT, IN p_amount DECIMAL(15,2)
)
BEGIN
    DECLARE v_balance DECIMAL(15,2);
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        INSERT INTO txn_log (from_acct, to_acct, amount, status)
        VALUES (p_from, p_to, p_amount, 'failed');
    END;

    START TRANSACTION;
        -- Lock the rows for update (prevents lost update)
        SELECT balance INTO v_balance FROM accounts
        WHERE account_id = p_from FOR UPDATE;

        IF v_balance < p_amount THEN
            SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Insufficient funds';
        END IF;

        UPDATE accounts SET balance = balance - p_amount WHERE account_id = p_from;
        UPDATE accounts SET balance = balance + p_amount WHERE account_id = p_to;

        INSERT INTO txn_log (from_acct, to_acct, amount, status)
        VALUES (p_from, p_to, p_amount, 'success');
    COMMIT;
END$$
DELIMITER ;

CALL transfer_funds(1, 2, 1500.00);
SELECT * FROM accounts;
SELECT * FROM txn_log;

-- ── Savepoints ────────────────────────────────────────────────
START TRANSACTION;
    UPDATE accounts SET balance = balance - 100 WHERE account_id = 1;
    SAVEPOINT sp1;

    UPDATE accounts SET balance = balance - 200 WHERE account_id = 1;
    SAVEPOINT sp2;

    -- Oops, rollback only the second update
    ROLLBACK TO SAVEPOINT sp1;

    -- First update (-100) is still pending
    SELECT balance FROM accounts WHERE account_id = 1;
COMMIT;

-- ── Isolation level demo ──────────────────────────────────────
-- Check current isolation level
SELECT @@transaction_isolation;

-- Set for this session
SET SESSION TRANSACTION ISOLATION LEVEL READ COMMITTED;
SET SESSION TRANSACTION ISOLATION LEVEL REPEATABLE READ;  -- restore default

-- ── Demonstrate dirty read prevention ────────────────────────
-- Session 1 (run in one connection):
-- START TRANSACTION;
-- UPDATE accounts SET balance = 99999 WHERE account_id = 1;
-- (don't commit yet)

-- Session 2 (run in another connection):
-- SET SESSION TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
-- SELECT balance FROM accounts WHERE account_id = 1;  -- sees 99999 (dirty read!)

-- Session 2 with READ COMMITTED:
-- SET SESSION TRANSACTION ISOLATION LEVEL READ COMMITTED;
-- SELECT balance FROM accounts WHERE account_id = 1;  -- sees original value

-- ── SELECT FOR UPDATE (locking read) ─────────────────────────
START TRANSACTION;
    -- Lock row to prevent concurrent modification
    SELECT balance FROM accounts WHERE account_id = 1 FOR UPDATE;
    -- Other transactions trying to UPDATE or SELECT FOR UPDATE this row will wait
    UPDATE accounts SET balance = balance + 500 WHERE account_id = 1;
COMMIT;

-- SELECT FOR SHARE (shared lock — allows other reads, blocks writes)
START TRANSACTION;
    SELECT balance FROM accounts WHERE account_id = 1 FOR SHARE;
    -- Other transactions can read but not write
COMMIT;

-- ── Check InnoDB transaction status ──────────────────────────
SELECT * FROM information_schema.INNODB_TRX\G

-- ── Check for deadlocks ───────────────────────────────────────
SHOW ENGINE INNODB STATUS\G
-- Look for "LATEST DETECTED DEADLOCK" section

-- ── autocommit behavior ───────────────────────────────────────
SHOW VARIABLES LIKE 'autocommit';

-- With autocommit=1 (default): each statement auto-commits
-- With autocommit=0: must explicitly COMMIT or ROLLBACK
SET autocommit = 0;
UPDATE accounts SET balance = balance + 100 WHERE account_id = 3;
-- Not committed yet — visible only in this session
COMMIT;
SET autocommit = 1;  -- restore

-- ── Verify total balance (consistency check) ─────────────────
SELECT SUM(balance) AS total_balance FROM accounts;
-- Should always equal 10000 + 5000 + 8000 = 23000 (minus transfers)
