-- ============================================================
-- utils/db_setup.sql
-- Database initialization and configuration
-- ============================================================

-- Create practice database
CREATE DATABASE IF NOT EXISTS practice_db
    CHARACTER SET utf8mb4
    COLLATE utf8mb4_unicode_ci;

-- Create application user (don't use root in production)
CREATE USER IF NOT EXISTS 'app_user'@'localhost' IDENTIFIED BY 'change_this_password';
GRANT SELECT, INSERT, UPDATE, DELETE, CREATE, DROP, INDEX, ALTER
    ON practice_db.* TO 'app_user'@'localhost';

-- Read-only user for reporting/replicas
CREATE USER IF NOT EXISTS 'readonly_user'@'%' IDENTIFIED BY 'change_this_password';
GRANT SELECT ON practice_db.* TO 'readonly_user'@'%';

FLUSH PRIVILEGES;

-- Verify character set
SHOW VARIABLES LIKE 'character_set%';
SHOW VARIABLES LIKE 'collation%';

-- Set session timezone to UTC (recommended for applications)
SET time_zone = '+00:00';
SHOW VARIABLES LIKE 'time_zone';
