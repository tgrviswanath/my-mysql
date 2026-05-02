# 04 — Views, Stored Procedures, Functions & Triggers

## Views

A view is a **named query** stored in the database. It behaves like a virtual table.

### Types of Views
- **Simple view**: single table, no aggregation — **updatable**
- **Complex view**: JOINs, GROUP BY, DISTINCT, subqueries — **read-only**

### When to Use Views
- Simplify complex queries for application developers
- Enforce column-level security (expose only certain columns)
- Provide a stable API over changing underlying schema

### View Algorithms
- `MERGE`: view query is merged with the outer query (like a macro) — efficient
- `TEMPTABLE`: view is materialized into a temp table first — less efficient
- `UNDEFINED` (default): MySQL chooses

```sql
CREATE ALGORITHM=MERGE VIEW v_active AS SELECT * FROM users WHERE status='active';
```

---

## Stored Procedures

Precompiled SQL code stored in the database. Executed with `CALL`.

### Advantages
- Reduce network round-trips (logic runs on DB server)
- Reusable across applications
- Can encapsulate complex transactions

### Disadvantages
- Hard to version control and test
- Business logic in DB makes it harder to scale horizontally
- Debugging is limited compared to application code

### Parameter Modes
- `IN`: input only (default)
- `OUT`: output only (caller reads after CALL)
- `INOUT`: both input and output

### Error Handling
```sql
DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN ROLLBACK; RESIGNAL; END;
DECLARE CONTINUE HANDLER FOR SQLSTATE '23000' SET @dup = 1;
```

---

## Stored Functions

Return a single value. Can be used in SQL expressions (SELECT, WHERE, etc.).

Must be declared as:
- `DETERMINISTIC`: same inputs always produce same output (safe for replication)
- `NOT DETERMINISTIC`: may return different results (e.g., uses NOW())
- `READS SQL DATA` / `MODIFIES SQL DATA` / `NO SQL`

---

## Triggers

Automatically execute SQL in response to INSERT, UPDATE, or DELETE on a table.

### Trigger Timing
- `BEFORE`: runs before the operation — can modify NEW values or abort with SIGNAL
- `AFTER`: runs after the operation — can't modify the row, used for auditing

### Trigger Limitations
- Cannot call stored procedures that use transactions
- Cannot use CALL to invoke procedures that return result sets
- Triggers fire per-row, not per-statement — can be slow on bulk operations
- Cascading triggers (trigger fires another trigger) limited to depth 1 in MySQL

### NEW and OLD
- `NEW.col`: new value (available in INSERT and UPDATE triggers)
- `OLD.col`: old value (available in UPDATE and DELETE triggers)

---

## Performance Considerations

- Views with `TEMPTABLE` algorithm create temp tables — avoid for large datasets
- Stored procedures reduce network overhead but add DB CPU load
- Triggers add overhead to every INSERT/UPDATE/DELETE — keep them lightweight
- Avoid triggers for bulk operations — use application-level batch processing instead
- Functions called in WHERE clause prevent index use if applied to indexed columns

---

## Interview Q&A

**Q: What is the difference between a stored procedure and a stored function?**
A: A stored procedure is called with CALL and can return multiple result sets and OUT parameters. A stored function returns a single scalar value and can be used in SQL expressions (SELECT, WHERE). Functions must be deterministic for safe use in replication.

**Q: When would you use a trigger vs application-level logic?**
A: Triggers are useful for database-level enforcement that must apply regardless of which application or tool modifies the data (e.g., audit logging, constraint enforcement). Application logic is better for complex business rules, external API calls, and anything that needs to be tested, versioned, or scaled independently.

**Q: What is the difference between BEFORE and AFTER triggers?**
A: BEFORE triggers run before the DML operation and can modify NEW values or abort the operation with SIGNAL. AFTER triggers run after the operation succeeds and are used for side effects like audit logging. AFTER triggers cannot modify the row that triggered them.

**Q: Can a view be updated?**
A: Simple views on a single table without aggregation, DISTINCT, GROUP BY, or subqueries are updatable — INSERT/UPDATE/DELETE on the view modifies the underlying table. Complex views (JOINs, aggregations) are read-only.
