# 01 — RDBMS & MySQL Architecture

## What is an RDBMS?

A Relational Database Management System stores data in **tables** (relations) with rows and columns. Relationships between tables are enforced via **foreign keys**. The relational model is based on Codd's 12 rules (1970).

Key properties:
- Data stored in normalized tables
- Relationships via primary/foreign keys
- SQL as the query language
- ACID guarantees for transactions

---

## MySQL Architecture (Layered)

```
┌─────────────────────────────────────────┐
│           Client Layer                  │  ← mysql CLI, JDBC, connectors
├─────────────────────────────────────────┤
│        Connection Pool / Thread Cache   │  ← one thread per connection
├─────────────────────────────────────────┤
│           SQL Layer                     │
│  ┌──────────┐  ┌──────────┐  ┌───────┐ │
│  │  Parser  │→ │Optimizer │→ │Executor│ │
│  └──────────┘  └──────────┘  └───────┘ │
├─────────────────────────────────────────┤
│        Storage Engine API               │  ← pluggable interface
├──────────────┬──────────────────────────┤
│   InnoDB     │  MyISAM  │  Memory  │... │  ← storage engines
└──────────────┴──────────────────────────┘
```

### Layer Breakdown

**1. Connection Layer**
- Each client gets a dedicated thread (or uses thread pool in enterprise)
- Handles authentication, SSL, connection limits (`max_connections`)
- Thread cache (`thread_cache_size`) reuses threads to avoid creation overhead

**2. SQL Layer**
- **Parser**: Tokenizes SQL, builds parse tree, checks syntax
- **Preprocessor**: Resolves table/column names, checks privileges
- **Query Cache** (removed in MySQL 8.0): Was a hash map of query → result
- **Optimizer**: Chooses the lowest-cost execution plan (cost-based)
- **Executor**: Calls storage engine API to fetch/write data

**3. Storage Engine Layer**
- Pluggable via `CREATE TABLE ... ENGINE=InnoDB`
- Each engine implements: read, write, index, transaction APIs
- InnoDB is the default and recommended engine

---

## InnoDB vs MyISAM

| Feature | InnoDB | MyISAM |
|---------|--------|--------|
| Transactions | ✅ ACID | ❌ |
| Foreign Keys | ✅ | ❌ |
| Row-level Locking | ✅ | ❌ (table-level) |
| Crash Recovery | ✅ redo logs | ❌ |
| Full-text Index | ✅ (5.6+) | ✅ |
| Use case | OLTP | Read-heavy legacy |

---

## Query Execution Flow

```
SQL String
   ↓
Parser → Parse Tree
   ↓
Preprocessor → Validated Tree
   ↓
Optimizer → Execution Plan (cheapest cost)
   ↓
Executor → calls Storage Engine API
   ↓
Storage Engine → reads pages from Buffer Pool / disk
   ↓
Result Set → sent to client
```

### Cost-Based Optimizer
- Uses **statistics** (index cardinality, row counts, data distribution)
- Evaluates multiple plans, picks lowest estimated cost
- Statistics updated via `ANALYZE TABLE`
- Can be hinted: `USE INDEX`, `FORCE INDEX`, `STRAIGHT_JOIN`

---

## MySQL System Databases

| Database | Purpose |
|----------|---------|
| `information_schema` | Metadata about all DBs, tables, columns |
| `performance_schema` | Runtime performance metrics |
| `sys` | Human-readable views over performance_schema |
| `mysql` | User accounts, privileges, system config |

---

## Performance Considerations

- `max_connections`: default 151 — increase for high-concurrency apps
- `innodb_buffer_pool_size`: most critical setting — set to 70–80% of RAM
- `thread_cache_size`: reduces thread creation overhead
- `query_cache_type=0`: disable query cache in MySQL 5.7 (removed in 8.0)

---

## Common Mistakes

- Using MyISAM for write-heavy workloads (no row locking)
- Not sizing `innodb_buffer_pool_size` properly
- Ignoring `max_connections` until production crashes
- Running MySQL as root user in production

---

## Interview Q&A

**Q: What is the difference between the SQL layer and storage engine layer?**
A: The SQL layer handles parsing, optimization, and execution planning. The storage engine layer handles actual data storage, retrieval, and indexing. They communicate via a pluggable API, allowing different engines (InnoDB, MyISAM) to be swapped.

**Q: Why was the query cache removed in MySQL 8.0?**
A: The query cache was a global mutex-protected hash map. Under high concurrency, it became a bottleneck — every write invalidated cache entries, and the mutex caused contention. Application-level caching (Redis, Memcached) is more effective.

**Q: How does MySQL handle concurrent connections?**
A: Each connection gets a dedicated OS thread (or a thread from the thread pool). The thread handles parsing, optimization, and execution for that connection. `thread_cache_size` controls how many idle threads are kept alive for reuse.

**Q: What is the role of the optimizer?**
A: The cost-based optimizer evaluates multiple execution plans using table statistics (row counts, index cardinality, data distribution) and selects the plan with the lowest estimated I/O and CPU cost.

**Q: What is `information_schema`?**
A: A virtual database containing metadata about all databases, tables, columns, indexes, and constraints. It's read-only and populated dynamically by MySQL. Used for schema introspection and tooling.
