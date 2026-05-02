# 05 — Transactions & ACID

## ACID Properties

### Atomicity
A transaction is **all-or-nothing**. Either all operations succeed and are committed, or all are rolled back.

InnoDB implements atomicity via **undo logs** — if a transaction fails, undo logs reverse all changes.

### Consistency
A transaction brings the database from one **valid state** to another. All constraints (FK, UNIQUE, CHECK) must hold after the transaction.

### Isolation
Concurrent transactions are **isolated** from each other. The degree of isolation is configurable via isolation levels.

InnoDB implements isolation via **MVCC** (Multi-Version Concurrency Control) and **locking**.

### Durability
Once committed, a transaction **persists** even if the system crashes.

InnoDB implements durability via **redo logs** (WAL — Write-Ahead Logging). Changes are written to the redo log before being applied to data pages.

---

## Transaction Syntax

```sql
START TRANSACTION;  -- or BEGIN
    UPDATE accounts SET balance = balance - 500 WHERE account_id = 1;
    UPDATE accounts SET balance = balance + 500 WHERE account_id = 2;
COMMIT;

-- On error:
ROLLBACK;

-- Savepoints (partial rollback)
START TRANSACTION;
    INSERT INTO orders ...;
    SAVEPOINT after_order;
    INSERT INTO order_items ...;
    -- Something fails:
    ROLLBACK TO SAVEPOINT after_order;
    -- Order is preserved, items are rolled back
COMMIT;
```

---

## Isolation Levels

MySQL supports 4 isolation levels (set per session or globally):

```sql
SET SESSION TRANSACTION ISOLATION LEVEL READ COMMITTED;
```

### READ UNCOMMITTED
- Can read **dirty reads** (uncommitted changes from other transactions)
- Fastest, least safe
- Almost never used in production

### READ COMMITTED
- Only reads **committed** data
- Prevents dirty reads
- Allows **non-repeatable reads** (same row read twice may return different values)
- Default in PostgreSQL, Oracle

### REPEATABLE READ (MySQL Default)
- Same row read twice returns the same value within a transaction
- Prevents dirty reads + non-repeatable reads
- Allows **phantom reads** in standard SQL, but InnoDB prevents them via **gap locks**
- InnoDB's default

### SERIALIZABLE
- Transactions execute as if serial (one at a time)
- Prevents all anomalies
- Highest isolation, lowest concurrency
- Converts all reads to locking reads

---

## Isolation Anomalies

| Anomaly | Description | Prevented by |
|---------|-------------|--------------|
| Dirty Read | Read uncommitted data | READ COMMITTED+ |
| Non-Repeatable Read | Same row returns different values | REPEATABLE READ+ |
| Phantom Read | New rows appear in repeated range query | SERIALIZABLE (standard), REPEATABLE READ (InnoDB via gap locks) |
| Lost Update | Two transactions overwrite each other | Locking reads (SELECT FOR UPDATE) |

---

## MVCC (Multi-Version Concurrency Control)

InnoDB maintains **multiple versions** of each row using:
- **DB_TRX_ID**: transaction ID that last modified the row
- **DB_ROLL_PTR**: pointer to undo log for previous version
- **DB_ROW_ID**: hidden row ID (if no PK)

When a transaction reads a row:
1. Check if the row's `DB_TRX_ID` is visible to the current transaction's **read view**
2. If not visible (modified by a newer transaction), follow `DB_ROLL_PTR` to find the older version in the undo log

This allows **non-locking reads** — readers don't block writers, writers don't block readers.

---

## autocommit

MySQL defaults to `autocommit=1` — each statement is its own transaction.

```sql
SET autocommit = 0;  -- Manual transaction control
-- or use explicit START TRANSACTION (temporarily disables autocommit)
```

---

## Performance Considerations

- Keep transactions **short** — long transactions hold locks and undo log space
- Avoid user interaction inside a transaction
- `innodb_flush_log_at_trx_commit=1`: safest (fsync on every commit), slowest
- `innodb_flush_log_at_trx_commit=2`: fsync every second (risk: 1 second of data loss on crash)
- Batch large operations into chunks to avoid long-running transactions

---

## Interview Q&A

**Q: Explain ACID properties with a banking example.**
A: Transfer $500 from account A to B: Atomicity — both debit and credit happen or neither does. Consistency — total money in the system remains the same. Isolation — another transaction reading balances mid-transfer sees either the old or new state, not an intermediate state. Durability — once committed, the transfer survives a server crash.

**Q: What is MVCC and how does it help concurrency?**
A: MVCC maintains multiple versions of each row. Readers see a consistent snapshot of the database as of their transaction start time, without acquiring locks. Writers create new versions. This allows reads and writes to proceed concurrently without blocking each other.

**Q: What is the difference between REPEATABLE READ and SERIALIZABLE?**
A: REPEATABLE READ ensures the same row returns the same value within a transaction and prevents phantom reads in InnoDB (via gap locks). SERIALIZABLE additionally converts all plain reads to locking reads, preventing all concurrency anomalies but significantly reducing throughput.

**Q: What is a phantom read?**
A: A phantom read occurs when a transaction re-executes a range query and finds new rows that weren't there before (inserted by another committed transaction). InnoDB prevents this in REPEATABLE READ using gap locks, which lock the gaps between index values.

**Q: What is the risk of long-running transactions?**
A: Long transactions hold row locks (blocking other writers), accumulate undo log entries (increasing undo tablespace), delay purge of old row versions (increasing table size), and can cause deadlocks. They also delay replication on replicas.
