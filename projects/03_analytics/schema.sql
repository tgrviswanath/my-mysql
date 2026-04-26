-- ============================================================
-- 03_analytics/schema.sql
-- Logging & analytics pipeline: events, aggregations, reporting
-- ============================================================

CREATE DATABASE IF NOT EXISTS analytics;
USE analytics;

-- ── Raw events (high-volume, partitioned) ────────────────────
CREATE TABLE events (
    event_id    BIGINT UNSIGNED AUTO_INCREMENT,
    session_id  VARCHAR(36) NOT NULL,
    user_id     BIGINT UNSIGNED,
    event_type  VARCHAR(50) NOT NULL,
    page        VARCHAR(200),
    properties  JSON,
    ip_address  VARCHAR(45),
    user_agent  VARCHAR(500),
    created_at  DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    PRIMARY KEY (event_id, created_at)
) PARTITION BY RANGE (TO_DAYS(created_at)) (
    PARTITION p_2024_q1 VALUES LESS THAN (TO_DAYS('2024-04-01')),
    PARTITION p_2024_q2 VALUES LESS THAN (TO_DAYS('2024-07-01')),
    PARTITION p_2024_q3 VALUES LESS THAN (TO_DAYS('2024-10-01')),
    PARTITION p_2024_q4 VALUES LESS THAN (TO_DAYS('2025-01-01')),
    PARTITION p_future  VALUES LESS THAN MAXVALUE
);

-- ── Pre-aggregated daily metrics (materialized) ───────────────
CREATE TABLE daily_metrics (
    metric_date     DATE NOT NULL,
    metric_name     VARCHAR(100) NOT NULL,
    dimension       VARCHAR(100) NOT NULL DEFAULT 'all',
    value           DECIMAL(20,4) NOT NULL,
    updated_at      DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (metric_date, metric_name, dimension)
);

-- ── Funnel steps ──────────────────────────────────────────────
CREATE TABLE funnel_steps (
    step_id     INT AUTO_INCREMENT PRIMARY KEY,
    funnel_name VARCHAR(100) NOT NULL,
    step_order  INT NOT NULL,
    step_name   VARCHAR(100) NOT NULL,
    event_type  VARCHAR(50) NOT NULL,
    UNIQUE INDEX idx_funnel_step (funnel_name, step_order)
);

-- ── Analytics queries ─────────────────────────────────────────

-- Daily active users (DAU)
SELECT
    DATE(created_at) AS day,
    COUNT(DISTINCT user_id) AS dau
FROM events
WHERE user_id IS NOT NULL
  AND created_at >= DATE_SUB(NOW(), INTERVAL 30 DAY)
GROUP BY DATE(created_at)
ORDER BY day;

-- Event funnel analysis (checkout funnel)
WITH funnel_events AS (
    SELECT
        session_id,
        MAX(CASE WHEN event_type = 'page_view'       THEN 1 ELSE 0 END) AS step1,
        MAX(CASE WHEN event_type = 'add_to_cart'     THEN 1 ELSE 0 END) AS step2,
        MAX(CASE WHEN event_type = 'checkout_start'  THEN 1 ELSE 0 END) AS step3,
        MAX(CASE WHEN event_type = 'payment_submit'  THEN 1 ELSE 0 END) AS step4,
        MAX(CASE WHEN event_type = 'order_complete'  THEN 1 ELSE 0 END) AS step5
    FROM events
    WHERE created_at >= DATE_SUB(NOW(), INTERVAL 7 DAY)
    GROUP BY session_id
)
SELECT
    SUM(step1) AS page_views,
    SUM(step2) AS add_to_cart,
    SUM(step3) AS checkout_start,
    SUM(step4) AS payment_submit,
    SUM(step5) AS order_complete,
    ROUND(SUM(step2) / NULLIF(SUM(step1), 0) * 100, 2) AS view_to_cart_pct,
    ROUND(SUM(step5) / NULLIF(SUM(step1), 0) * 100, 2) AS overall_conversion_pct
FROM funnel_events;

-- Rolling 7-day average (window function)
WITH daily AS (
    SELECT DATE(created_at) AS day, COUNT(DISTINCT user_id) AS dau
    FROM events WHERE user_id IS NOT NULL
    GROUP BY DATE(created_at)
)
SELECT
    day,
    dau,
    ROUND(AVG(dau) OVER (ORDER BY day ROWS BETWEEN 6 PRECEDING AND CURRENT ROW), 1) AS rolling_7d_avg
FROM daily
ORDER BY day;

-- Top pages by unique visitors
SELECT
    page,
    COUNT(*) AS page_views,
    COUNT(DISTINCT session_id) AS unique_sessions,
    COUNT(DISTINCT user_id) AS unique_users,
    ROUND(COUNT(DISTINCT user_id) / COUNT(DISTINCT session_id) * 100, 2) AS login_rate_pct
FROM events
WHERE event_type = 'page_view'
  AND created_at >= DATE_SUB(NOW(), INTERVAL 7 DAY)
GROUP BY page
ORDER BY page_views DESC
LIMIT 20;

-- Aggregate daily metrics (run as scheduled job)
INSERT INTO daily_metrics (metric_date, metric_name, dimension, value)
SELECT
    DATE(NOW() - INTERVAL 1 DAY),
    'dau',
    'all',
    COUNT(DISTINCT user_id)
FROM events
WHERE DATE(created_at) = DATE(NOW() - INTERVAL 1 DAY)
  AND user_id IS NOT NULL
ON DUPLICATE KEY UPDATE value = VALUES(value), updated_at = NOW();
