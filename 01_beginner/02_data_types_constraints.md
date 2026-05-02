# 02 — Data Types & Constraints

## Numeric Types

| Type | Storage | Range (Signed) | Use Case |
|------|---------|----------------|----------|
| TINYINT | 1 byte | -128 to 127 | flags, status codes |
| SMALLINT | 2 bytes | -32,768 to 32,767 | small counters |
| MEDIUMINT | 3 bytes | -8M to 8M | medium IDs |
| INT | 4 bytes | -2.1B to 2.1B | standard IDs |
| BIGINT | 8 bytes | ±9.2 × 10^18 | large IDs, timestamps |
| DECIMAL(p,s) | variable | exact | money, financial |
| FLOAT | 4 bytes | approximate | scientific |
| DOUBLE | 8 bytes | approximate | scientific |

> ⚠️ Never use FLOAT/DOUBLE for money — use DECIMAL(15,2)

---

## String Types

| Type | Max Size | Notes |
|------|----------|-------|
| CHAR(n) | 255 chars | Fixed-length, padded with spaces |
| VARCHAR(n) | 65,535 bytes | Variable-length, 1–2 byte length prefix |
| TEXT | 65,535 bytes | Stored off-page for large values |
| MEDIUMTEXT | 16 MB | |
| LONGTEXT | 4 GB | |
| ENUM | 1–2 bytes | Stored as integer internally |
| SET | 1–8 bytes | Bitmask of values |

### CHAR vs VARCHAR
- `CHAR(10)`: always 10 bytes — fast for fixed-length data (e.g., country codes)
- `VARCHAR(255)`: 1–255 bytes + 1 byte overhead — efficient for variable data
- InnoDB stores VARCHAR inline if ≤ 767 bytes (utf8mb4: 191 chars per index prefix)

---

## Date/Time Types

| Type | Storage | Format | Range |
|------|---------|--------|-------|
| DATE | 3 bytes | YYYY-MM-DD | 1000-01-01 to 9999-12-31 |
| TIME | 3 bytes | HH:MM:SS | -838:59:59 to 838:59:59 |
| DATETIME | 8 bytes | YYYY-MM-DD HH:MM:SS | 1000 to 9999 |
| TIMESTAMP | 4 bytes | YYYY-MM-DD HH:MM:SS | 1970 to 2038 |
| YEAR | 1 byte | YYYY | 1901 to 2155 |

> ⚠️ TIMESTAMP has the **Year 2038 problem** — use DATETIME for future-proof apps
> TIMESTAMP is timezone-aware (stored as UTC, displayed in session timezone)
> DATETIME is timezone-naive (stored as-is)

---

## Constraints

### PRIMARY KEY
- Uniquely identifies each row
- Implicitly creates a clustered index in InnoDB
- Cannot be NULL
- Only one per table

### UNIQUE
- Enforces uniqueness across one or more columns
- Allows NULL (multiple NULLs allowed — NULL ≠ NULL)
- Creates a secondary index

### NOT NULL
- Prevents NULL values in a column
- Forces explicit data entry

### FOREIGN KEY
- Enforces referential integrity between tables
- Requires matching index on referenced column
- Actions: `ON DELETE CASCADE | SET NULL | RESTRICT | NO ACTION`

### CHECK (MySQL 8.0.16+)
- Validates column values against an expression
- Older MySQL versions parsed but ignored CHECK constraints

### DEFAULT
- Provides a default value when none is specified
- Can use functions: `DEFAULT CURRENT_TIMESTAMP`

---

## InnoDB Clustered Index Behavior

In InnoDB, the PRIMARY KEY **is** the clustered index — the table data is physically ordered by PK.

- If no PK defined: InnoDB uses first UNIQUE NOT NULL column
- If none exists: InnoDB creates a hidden 6-byte `rowid`
- Secondary indexes store the PK value as a pointer → "double lookup" for non-covering queries

**Implication**: Choose a monotonically increasing PK (INT AUTO_INCREMENT) to avoid page splits and fragmentation.

---

## Performance Considerations

- Use the **smallest data type** that fits your data — saves storage and improves cache efficiency
- `TINYINT(1)` for boolean flags (MySQL uses this for BIT internally)
- Avoid `TEXT`/`BLOB` in frequently-joined columns — stored off-page
- `ENUM` is compact but rigid — adding values requires `ALTER TABLE`
- Index prefix length for `VARCHAR`: `INDEX (col(191))` for utf8mb4

---

## Common Mistakes

- Using `VARCHAR(255)` everywhere — wastes memory in temp tables
- Using `FLOAT` for currency — causes rounding errors
- Forgetting `NOT NULL` — NULLs complicate queries and indexes
- Using `DATETIME` when timezone handling is needed (use TIMESTAMP + UTC)
- Defining FK without an index on the child column — causes full table scans on FK checks

---

## Interview Q&A

**Q: What is the difference between CHAR and VARCHAR?**
A: CHAR is fixed-length — always allocates n bytes, padded with spaces. VARCHAR is variable-length — stores only the actual data plus 1–2 bytes for length. CHAR is faster for fixed-size data (e.g., ISO country codes), VARCHAR is more space-efficient for variable data.

**Q: Why should you never use FLOAT for monetary values?**
A: FLOAT uses binary floating-point representation, which cannot exactly represent most decimal fractions. For example, 0.1 + 0.2 ≠ 0.3 in binary. Use DECIMAL(15,2) for exact decimal arithmetic.

**Q: What happens if you define no PRIMARY KEY in InnoDB?**
A: InnoDB looks for the first UNIQUE NOT NULL column to use as the clustered index. If none exists, it creates a hidden 6-byte integer rowid. This is problematic because secondary indexes can't reference a meaningful key, and replication/tools may behave unexpectedly.

**Q: What is the Year 2038 problem with TIMESTAMP?**
A: TIMESTAMP stores values as a 32-bit signed integer (seconds since Unix epoch). The maximum value is 2^31 - 1 = 2147483647, which corresponds to 2038-01-19 03:14:07 UTC. After that, it overflows. Use DATETIME for dates beyond 2038.

**Q: Can a UNIQUE constraint have NULL values?**
A: Yes. In MySQL, NULL is not equal to NULL (NULL ≠ NULL), so multiple NULL values are allowed in a UNIQUE column. This is standard SQL behavior.
