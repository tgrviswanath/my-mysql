-- ============================================================
-- 04_multitenant/schema.sql
-- Multi-tenant SaaS: shared schema with tenant isolation
-- ============================================================

CREATE DATABASE IF NOT EXISTS saas_platform;
USE saas_platform;

-- ── Tenants (organizations) ───────────────────────────────────
CREATE TABLE tenants (
    tenant_id   INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    name        VARCHAR(100) NOT NULL,
    slug        VARCHAR(50)  NOT NULL,
    plan        ENUM('free','starter','pro','enterprise') NOT NULL DEFAULT 'free',
    status      ENUM('active','suspended','cancelled') NOT NULL DEFAULT 'active',
    created_at  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE INDEX idx_slug (slug)
);

-- ── Users (belong to a tenant) ────────────────────────────────
CREATE TABLE users (
    user_id     BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    tenant_id   INT UNSIGNED NOT NULL,
    email       VARCHAR(100) NOT NULL,
    role        ENUM('owner','admin','member','viewer') NOT NULL DEFAULT 'member',
    status      ENUM('active','inactive') NOT NULL DEFAULT 'active',
    created_at  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE INDEX idx_tenant_email (tenant_id, email),  -- email unique per tenant
    INDEX idx_tenant (tenant_id),
    FOREIGN KEY (tenant_id) REFERENCES tenants(tenant_id)
);

-- ── Projects (tenant-scoped) ──────────────────────────────────
CREATE TABLE projects (
    project_id  BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    tenant_id   INT UNSIGNED NOT NULL,
    name        VARCHAR(200) NOT NULL,
    status      ENUM('active','archived') NOT NULL DEFAULT 'active',
    created_by  BIGINT UNSIGNED NOT NULL,
    created_at  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_tenant_status (tenant_id, status),
    FOREIGN KEY (tenant_id)  REFERENCES tenants(tenant_id),
    FOREIGN KEY (created_by) REFERENCES users(user_id)
);

-- ── Row-Level Security via Application Layer ──────────────────
-- Every query MUST include tenant_id in WHERE clause
-- Enforced by application middleware, not MySQL

-- Example: get projects for a tenant (always filter by tenant_id)
-- SELECT * FROM projects WHERE tenant_id = ? AND status = 'active';

-- ── Tenant usage metrics ──────────────────────────────────────
CREATE TABLE tenant_usage (
    tenant_id   INT UNSIGNED NOT NULL,
    metric_date DATE NOT NULL,
    api_calls   INT NOT NULL DEFAULT 0,
    storage_mb  DECIMAL(10,2) NOT NULL DEFAULT 0,
    active_users INT NOT NULL DEFAULT 0,
    PRIMARY KEY (tenant_id, metric_date),
    FOREIGN KEY (tenant_id) REFERENCES tenants(tenant_id)
);

-- ── Tenant isolation queries ──────────────────────────────────

-- Get all data for a tenant (always scoped)
SELECT p.project_id, p.name, u.email AS created_by, p.created_at
FROM projects p
JOIN users u ON p.created_by = u.user_id
WHERE p.tenant_id = 1  -- ALWAYS include tenant_id
  AND p.status = 'active'
ORDER BY p.created_at DESC;

-- Cross-tenant analytics (admin only — no tenant filter)
SELECT
    t.name AS tenant,
    t.plan,
    COUNT(DISTINCT u.user_id) AS user_count,
    COUNT(DISTINCT p.project_id) AS project_count
FROM tenants t
LEFT JOIN users u    ON t.tenant_id = u.tenant_id AND u.status = 'active'
LEFT JOIN projects p ON t.tenant_id = p.tenant_id AND p.status = 'active'
WHERE t.status = 'active'
GROUP BY t.tenant_id, t.name, t.plan
ORDER BY user_count DESC;

-- Tenant usage report
SELECT
    t.name,
    t.plan,
    SUM(tu.api_calls) AS total_api_calls,
    MAX(tu.storage_mb) AS current_storage_mb,
    AVG(tu.active_users) AS avg_daily_active_users
FROM tenants t
JOIN tenant_usage tu ON t.tenant_id = tu.tenant_id
WHERE tu.metric_date >= DATE_SUB(CURDATE(), INTERVAL 30 DAY)
GROUP BY t.tenant_id, t.name, t.plan
ORDER BY total_api_calls DESC;

-- ── Plan limits enforcement ───────────────────────────────────
DELIMITER $$
CREATE FUNCTION IF NOT EXISTS get_plan_limit(p_plan VARCHAR(20), p_resource VARCHAR(50))
RETURNS INT DETERMINISTIC
BEGIN
    RETURN CASE p_resource
        WHEN 'max_users' THEN CASE p_plan
            WHEN 'free'       THEN 5
            WHEN 'starter'    THEN 25
            WHEN 'pro'        THEN 100
            WHEN 'enterprise' THEN 999999
        END
        WHEN 'max_projects' THEN CASE p_plan
            WHEN 'free'       THEN 3
            WHEN 'starter'    THEN 20
            WHEN 'pro'        THEN 100
            WHEN 'enterprise' THEN 999999
        END
        ELSE 0
    END;
END$$
DELIMITER ;

-- Check if tenant can add more users
SELECT
    t.tenant_id,
    t.plan,
    COUNT(u.user_id) AS current_users,
    get_plan_limit(t.plan, 'max_users') AS max_users,
    COUNT(u.user_id) >= get_plan_limit(t.plan, 'max_users') AS at_limit
FROM tenants t
LEFT JOIN users u ON t.tenant_id = u.tenant_id AND u.status = 'active'
GROUP BY t.tenant_id, t.plan;
