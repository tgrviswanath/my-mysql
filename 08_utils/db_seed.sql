-- ============================================================
-- utils/db_seed.sql
-- Master seed script — runs all dataset seeds in order
-- ============================================================

-- Run this after db_setup.sql to populate all practice data:
-- mysql -u root -p < utils/db_setup.sql
-- mysql -u root -p < utils/db_seed.sql

USE practice_db;

-- 1. Seed users (10,000 rows)
SOURCE datasets/seed_users.sql;

-- 2. Seed orders (50,000 rows)
SOURCE datasets/seed_orders.sql;

-- 3. Seed transactions and logs (100,000 + 500,000 rows)
SOURCE datasets/seed_transactions.sql;

-- ── Verification ──────────────────────────────────────────────
SELECT 'users'                AS tbl, COUNT(*) AS rows FROM users
UNION ALL
SELECT 'orders',                       COUNT(*) FROM orders
UNION ALL
SELECT 'financial_transactions',       COUNT(*) FROM financial_transactions
UNION ALL
SELECT 'app_logs',                     COUNT(*) FROM app_logs;
