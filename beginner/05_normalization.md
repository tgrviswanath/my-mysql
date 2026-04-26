# 05 — Normalization

## What is Normalization?

Normalization is the process of organizing a relational database to **reduce data redundancy** and **improve data integrity** by decomposing tables into smaller, well-structured ones.

Goals:
- Eliminate redundant data (same data stored in multiple places)
- Ensure data dependencies make sense (only storing related data in a table)
- Prevent update/insert/delete anomalies

---

## Normal Forms

### 1NF — First Normal Form
**Rule**: Each column must contain **atomic** (indivisible) values. No repeating groups.

❌ Violates 1NF:
```
| order_id | products              |
|----------|-----------------------|
| 1        | Laptop, Mouse, Webcam |
```

✅ 1NF:
```
| order_id | product    |
|----------|------------|
| 1        | Laptop     |
| 1        | Mouse      |
| 1        | Webcam     |
```

---

### 2NF — Second Normal Form
**Rule**: Must be in 1NF + every non-key attribute must depend on the **entire** primary key (no partial dependency).

Only relevant when the PK is **composite**.

❌ Violates 2NF (composite PK: order_id + product_id):
```
| order_id | product_id | product_name | quantity |
|----------|------------|--------------|----------|
| 1        | 101        | Laptop       | 2        |
```
`product_name` depends only on `product_id`, not the full composite key.

✅ 2NF — split into:
- `order_items(order_id, product_id, quantity)`
- `products(product_id, product_name)`

---

### 3NF — Third Normal Form
**Rule**: Must be in 2NF + no **transitive dependencies** (non-key column depends on another non-key column).

❌ Violates 3NF:
```
| emp_id | dept_id | dept_name |
|--------|---------|-----------|
| 1      | 10      | Engineering |
```
`dept_name` depends on `dept_id`, not `emp_id`.

✅ 3NF — split into:
- `employees(emp_id, dept_id)`
- `departments(dept_id, dept_name)`

---

### BCNF — Boyce-Codd Normal Form
**Rule**: Must be in 3NF + for every functional dependency X → Y, X must be a **superkey**.

Stricter than 3NF. Handles edge cases with multiple overlapping candidate keys.

---

### 4NF — Fourth Normal Form
**Rule**: No multi-valued dependencies.

Rarely needed in practice. Relevant when a table has two independent multi-valued facts about an entity.

---

## Denormalization

Intentionally introducing redundancy for **performance**:
- Avoid expensive JOINs on hot query paths
- Pre-aggregate data for reporting
- Store derived values (e.g., `order_total` on the orders table)

Trade-off: faster reads, slower writes, risk of inconsistency.

**When to denormalize**:
- Read-heavy workloads (OLAP, reporting)
- JOIN cost is measurably impacting performance
- Data is rarely updated

---

## Functional Dependencies

A functional dependency X → Y means: knowing X uniquely determines Y.

Example: `emp_id → {name, salary, dept_id}` — knowing emp_id determines all other attributes.

**Candidate key**: minimal set of attributes that uniquely identifies a row.
**Primary key**: chosen candidate key.
**Superkey**: any superset of a candidate key.

---

## Performance Considerations

- Normalized schemas reduce write amplification (update one place)
- Normalized schemas require more JOINs for reads
- For OLTP: normalize to 3NF (write-heavy, transactional)
- For OLAP/DWH: denormalize into star/snowflake schema (read-heavy)
- Covering indexes can compensate for JOIN overhead in normalized schemas

---

## Interview Q&A

**Q: What is the difference between 2NF and 3NF?**
A: 2NF eliminates partial dependencies (non-key column depends on part of a composite PK). 3NF eliminates transitive dependencies (non-key column depends on another non-key column). Both require 1NF as a prerequisite.

**Q: When would you intentionally denormalize a database?**
A: When JOIN performance is a bottleneck on read-heavy workloads. For example, storing a pre-computed `order_total` on the orders table avoids summing order_items on every read. Also common in data warehouses (star schema) where query speed is prioritized over write efficiency.

**Q: What is a transitive dependency?**
A: When a non-key column A depends on another non-key column B, which depends on the primary key. Example: emp_id → dept_id → dept_name. dept_name transitively depends on emp_id through dept_id. 3NF requires moving dept_name to a departments table.

**Q: What is BCNF and how does it differ from 3NF?**
A: BCNF requires that for every functional dependency X → Y, X must be a superkey. 3NF allows exceptions when Y is part of a candidate key. BCNF is stricter and eliminates more anomalies but may not always be achievable without losing functional dependencies.

**Q: What anomalies does normalization prevent?**
A: Insert anomaly (can't insert data without unrelated data), update anomaly (updating redundant data in multiple places), and delete anomaly (deleting a row unintentionally removes other information).
