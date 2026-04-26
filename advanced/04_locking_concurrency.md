# 04 — Locking & Concurrency

## Lock Types in InnoDB

### Shared Lock (S)
- Multiple transactions can hold shared locks simultaneously
- Acquired by: `SELECT ... FOR SHARE` (or `LOCK IN SHARE MODE`)
- Blocks: exclusive locks (writes)

### Exclusive Lock (X)
- Only one transaction can hold an exclusive lock
- Acquired by: `SELECT ... FOR UPDATE`, `UPDATE`, `DELETE`, `INSERT`
- Blocks: all other locks (shared and exclusive)

### Intention Locks
Table-level locks that signal intent to acquire row-level locks:
- **IS** (Intention Shared): intent to acquire S locks on rows
- **IX** (Intention Exclusive): intent to acquire X locks on rows
- Allow table-level operations (e.g., `LOCK TABLES`) to detect conflicts without scanning all rows

---

## Row-Level Lock Types

### Record Lock
Locks a single index record.
```sql
SELECT * FROM accounts WHERE account_id = 1 FOR UPDATE;
-- Locks the index record for account_id=1
```

### Gap Lock
Locks the **gap** between index records (prevents phantom inserts).
```sql
SELECT * FROM orders WHERE order_id BETWEEN 10 AND 20 FOR UPDATE;
-- Locks the gap: no new rows with order_id 10-20 can be inserted
```

Gap locks only exist in REPEATABLE READ isolation level.

### Next-Key Lock
Combination of record lock + gap lock on the preceding gap.
- Default locking in InnoDB REPEATABLE READ
- Prevents phantom reads

### Insert Intention Lock
Special gap lock acquired before INSERT. Multiple inserts into the same gap don't block each other (unless they insert at the same position).

---

## Table-Level Locks

```sql
LOCK TABLES orders READ;   -- shared table lock
LOCK TABLES orders WRITE;  -- exclusive table lock
UNLOCK TABLES;
```

InnoDB rarely needs table locks — row-level locking is preferred. Table locks are used by:
- `ALTER TABLE` (DDL)
- `LOCK TABLES` statement
- MyISAM engine (always table-level)

---

## Deadlocks

A deadlock occurs when two transactions each hold a lock the other needs:

```
Transaction 1: LOCK row A → wait for row B
Transaction 2: LOCK row B → wait for row A
```

InnoDB detects deadlocks automatically and **rolls back the smaller transaction** (by undo log size).

### Deadlock Prevention
1. Always acquire locks in the **same order** across transactions
2. Keep transactions **short**
3. Use `SELECT ... FOR UPDATE` to acquire all needed locks upfront
4. Use lower isolation levels where possible

```sql
-- Check last deadlock
SHOW ENGINE INNODB STATUS\G
-- Look for: LATEST DETECTED DEADLOCK
```

---

## Lock Monitoring

```sql
-- Active transactions
SELECT * FROM information_schema.INNODB_TRX\G

-- Current locks
SELECT * FROM performance_schema.data_locks;

-- Lock waits
SELECT * FROM performance_schema.data_lock_waits;

-- Who is blocking whom
SELECT
    r.trx_id AS waiting_trx,
    r.trx_mysql_thread_id AS waiting_thread,
    b.trx_id AS blocking_trx,
    b.trx_mysql_thread_id AS blocking_thread,
    b.trx_query AS blocking_query
FROM information_schema.INNODB_LOCK_WAITS w
JOIN information_schema.INNODB_TRX b ON b.trx_id = w.blocking_trx_id
JOIN information_schema.INNODB_TRX r ON r.trx_id = w.requesting_trx_id;
```

---

## Optimistic vs Pessimistic Locking

### Pessimistic Locking
Lock the row before reading to prevent concurrent modification:
```sql
START TRANSACTION;
SELECT * FROM inventory WHERE product_id = 1 FOR UPDATE;  -- lock
-- ... process ...
UPDATE inventory SET stock = stock - 1 WHERE product_id = 1;
COMMIT;
```

### Optimistic Locking
Read without locking, check for conflicts at write time using a version column:
```sql
-- Read
SELECT stock, version FROM inventory WHERE product_id = 1;
-- ... process ...
-- Write: only succeeds if version hasn't changed
UPDATE inventory SET stock = stock - 1, version = version + 1
WHERE product_id = 1 AND version = <read_version>;
-- If 0 rows affected → conflict, retry
```

Optimistic locking is better for low-contention scenarios (fewer lock waits).

---

## Interview Q&A

**Q: What is the difference between a gap lock and a record lock?**
A: A record lock locks a specific index record. A gap lock locks the gap between index records, preventing new rows from being inserted in that range. Gap locks exist only in REPEATABLE READ to prevent phantom reads.

**Q: How does InnoDB resolve deadlocks?**
A: InnoDB's deadlock detector runs automatically. When a deadlock is detected, InnoDB rolls back the transaction with the smallest undo log (least work done), allowing the other transaction to proceed. The rolled-back transaction receives error 1213 (ER_LOCK_DEADLOCK) and should be retried.

**Q: What is the difference between optimistic and pessimistic locking?**
A: Pessimistic locking acquires locks before reading data, preventing concurrent modifications. It's safe but reduces concurrency. Optimistic locking reads without locks and checks for conflicts at write time using a version/timestamp column. It's better for low-contention scenarios but requires retry logic.

**Q: Why do gap locks exist and when are they released?**
A: Gap locks prevent phantom reads in REPEATABLE READ by blocking inserts into ranges that a transaction has read. They're released when the transaction commits or rolls back. Gap locks don't exist in READ COMMITTED — each statement gets a fresh snapshot.

**Q: What is a next-key lock?**
A: A next-key lock is a combination of a record lock on an index record and a gap lock on the gap before that record. InnoDB uses next-key locks by default in REPEATABLE READ to prevent both non-repeatable reads and phantom reads.
