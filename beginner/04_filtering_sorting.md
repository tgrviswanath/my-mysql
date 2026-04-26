# 04 — Filtering, Sorting & SQL Functions

## WHERE Clause Operators

| Operator | Example | Notes |
|----------|---------|-------|
| `=` | `WHERE status = 'active'` | Exact match |
| `!=` / `<>` | `WHERE status != 'banned'` | Not equal |
| `>`, `<`, `>=`, `<=` | `WHERE price > 100` | Comparison |
| `BETWEEN` | `WHERE price BETWEEN 10 AND 100` | Inclusive on both ends |
| `IN` | `WHERE country IN ('US','UK')` | Set membership |
| `NOT IN` | `WHERE status NOT IN ('banned')` | Exclusion — beware NULLs |
| `LIKE` | `WHERE name LIKE 'A%'` | Pattern match |
| `IS NULL` | `WHERE deleted_at IS NULL` | NULL check |
| `IS NOT NULL` | `WHERE email IS NOT NULL` | Non-NULL check |

### LIKE Patterns
- `%` — matches any sequence of characters (including empty)
- `_` — matches exactly one character
- `LIKE 'A%'` — starts with A (can use index)
- `LIKE '%A'` — ends with A (cannot use index)
- `LIKE '%A%'` — contains A (cannot use index)

---

## CASE Expression

Two forms:

**Simple CASE** (equality check):
```sql
CASE status
    WHEN 'active'   THEN 'Active User'
    WHEN 'inactive' THEN 'Inactive User'
    ELSE 'Other'
END
```

**Searched CASE** (arbitrary conditions):
```sql
CASE
    WHEN salary >= 100000 THEN 'Senior'
    WHEN salary >= 70000  THEN 'Mid'
    ELSE 'Junior'
END
```

---

## String Functions

| Function | Example | Result |
|----------|---------|--------|
| `UPPER(s)` | `UPPER('hello')` | `'HELLO'` |
| `LOWER(s)` | `LOWER('HELLO')` | `'hello'` |
| `LENGTH(s)` | `LENGTH('hello')` | `5` (bytes) |
| `CHAR_LENGTH(s)` | `CHAR_LENGTH('hello')` | `5` (chars) |
| `SUBSTRING(s,pos,len)` | `SUBSTRING('hello',2,3)` | `'ell'` |
| `CONCAT(s1,s2)` | `CONCAT('a','b')` | `'ab'` |
| `TRIM(s)` | `TRIM(' hi ')` | `'hi'` |
| `REPLACE(s,from,to)` | `REPLACE('a-b','-','_')` | `'a_b'` |
| `LOCATE(sub,s)` | `LOCATE('ll','hello')` | `3` |
| `LPAD(s,len,pad)` | `LPAD('5',3,'0')` | `'005'` |

---

## Date Functions

| Function | Description |
|----------|-------------|
| `NOW()` | Current datetime |
| `CURDATE()` | Current date |
| `YEAR(d)`, `MONTH(d)`, `DAY(d)` | Extract parts |
| `DATE_FORMAT(d, fmt)` | Format date string |
| `DATEDIFF(d1, d2)` | Days between dates |
| `DATE_ADD(d, INTERVAL n unit)` | Add interval |
| `DATE_SUB(d, INTERVAL n unit)` | Subtract interval |
| `TIMESTAMPDIFF(unit, d1, d2)` | Difference in units |

---

## NULL Handling Functions

| Function | Behavior |
|----------|---------|
| `IFNULL(a, b)` | Returns b if a is NULL |
| `COALESCE(a,b,c,...)` | Returns first non-NULL |
| `NULLIF(a, b)` | Returns NULL if a=b, else a |
| `IF(cond, a, b)` | Ternary: a if true, b if false |

---

## Performance Considerations

- `LIKE 'prefix%'` can use a B-Tree index; `LIKE '%suffix'` cannot
- `BETWEEN` is inclusive and uses index range scan
- `IN` with a small list is efficient; large IN lists may be slower than a JOIN
- Functions on columns in WHERE prevent index use: `WHERE YEAR(col) = 2024` → bad
- `ORDER BY` on non-indexed columns causes filesort — add index if frequent

---

## Interview Q&A

**Q: What is the difference between LENGTH() and CHAR_LENGTH()?**
A: LENGTH() returns the byte length of a string. CHAR_LENGTH() returns the character count. They differ for multibyte character sets (e.g., utf8mb4 where some characters use 3–4 bytes). For ASCII text they're identical.

**Q: How does COALESCE differ from IFNULL?**
A: IFNULL takes exactly 2 arguments and returns the second if the first is NULL. COALESCE takes any number of arguments and returns the first non-NULL value. COALESCE is the SQL standard function; IFNULL is MySQL-specific.

**Q: Why is LIKE '%pattern' slow?**
A: A leading wildcard means MySQL can't use a B-Tree index because the index is sorted by the beginning of the string. MySQL must scan every row and apply the pattern. For suffix searches, consider FULLTEXT indexes or reversing the string and using a prefix match.
