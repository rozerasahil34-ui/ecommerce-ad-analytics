-- =============================================================================
-- FILE: 04_rca_queries.sql
-- PROJECT: E-Commerce Ad Campaign Analytics
-- DESCRIPTION: Root Cause Analysis queries. When a KPI drops, these queries
--              help diagnose WHY.
-- USAGE: Run these when you notice a drop in ROAS/CTR/CVR in your weekly trend.
-- =============================================================================


-- =============================================================================
-- STEP 1: DETECT THE PROBLEM
-- Identify which week/channel/category had the biggest ROAS decline
-- =============================================================================

-- 1a. Flag weeks where ROAS dropped more than 10% WoW
WITH weekly_roas AS (
    SELECT
        campaign_week,
        channel,
        ROUND(SUM(attributed_revenue) / NULLIF(SUM(ad_spend), 0), 3)  AS roas,
        SUM(ad_spend)                                        AS spend
    FROM fct_ad_campaigns
    GROUP BY campaign_week, channel
),
roas_with_lag AS (
    SELECT
        *,
        LAG(roas)  OVER (PARTITION BY channel ORDER BY campaign_week) AS prev_roas,
        LAG(spend) OVER (PARTITION BY channel ORDER BY campaign_week) AS prev_spend
    FROM weekly_roas
)
SELECT
    campaign_week,
    channel,
    roas,
    prev_roas,
    ROUND((roas - prev_roas) / NULLIF(prev_roas, 0) * 100, 1) AS roas_chg_pct,
    spend,
    -- Severity flag
    CASE
        WHEN (roas - prev_roas) / NULLIF(prev_roas, 0) < -0.10 THEN 'Significant Drop (>10%)'
        WHEN (roas - prev_roas) / NULLIF(prev_roas, 0) < -0.05 THEN 'Moderate Drop (5-10%)'
        ELSE 'Stable'
    END AS alert_level
FROM roas_with_lag
WHERE prev_roas IS NOT NULL and (roas - prev_roas) / NULLIF(prev_roas, 0) < -0.10
ORDER BY roas_chg_pct ASC;


-- =============================================================================
-- STEP 2: DECOMPOSE THE DROP
-- When ROAS drops, it's caused by: (a) CTR drop, (b) CVR drop, (c) CPC increase,
-- or (d) AOV decrease. This query decomposes which driver is responsible.
-- =============================================================================

-- 2a. Decompose KPI drivers for a specific channel (edit channel name as needed)
WITH channel_weekly AS (
    SELECT
        campaign_week,
        channel,
        SUM(impressions)   AS impressions,
        SUM(clicks)        AS clicks,
        SUM(attributed_orders)   AS attributed_orders,
        SUM(ad_spend)      AS spend,
        SUM(attributed_revenue)       AS revenue
    FROM fct_ad_campaigns
    -- WHERE channel = 'Meta Ads'    -- ← uncomment and change to focus on one channel
    GROUP BY campaign_week, channel
)
SELECT
    campaign_week,
    channel,
    ROUND(clicks::NUMERIC      / NULLIF(impressions, 0) * 100, 2)  AS ctr_pct,
    ROUND(attributed_orders::NUMERIC / NULLIF(clicks, 0)      * 100, 2)  AS cvr_pct,
    ROUND(spend / NULLIF(clicks, 0), 2)                             AS cpc,
    ROUND(attributed_revenue / NULLIF(attributed_orders, 0), 2)                      AS aov,
    ROUND(revenue / NULLIF(spend, 0), 2)                            AS roas,

    -- WoW changes for each driver
    ROUND(clicks::NUMERIC/NULLIF(impressions,0)*100
          - LAG(clicks::NUMERIC/NULLIF(impressions,0)*100) OVER (PARTITION BY channel ORDER BY campaign_week), 2)
    AS ctr_wow_chg,

    ROUND(attributed_orders::NUMERIC/NULLIF(clicks,0)*100
          - LAG(attributed_orders::NUMERIC/NULLIF(clicks,0)*100) OVER (PARTITION BY channel ORDER BY campaign_week), 2)
    AS cvr_wow_chg,

    ROUND(spend/NULLIF(clicks,0)
          - LAG(spend/NULLIF(clicks,0)) OVER (PARTITION BY channel ORDER BY campaign_week), 2)
    AS cpc_wow_chg,

    ROUND(attributed_revenue/NULLIF(attributed_orders,0)
          - LAG(attributed_revenue/NULLIF(attributed_orders,0)) OVER (PARTITION BY channel ORDER BY campaign_week), 2)
    AS aov_wow_chg,

    -- Diagnosis: Which driver is the biggest contributor to ROAS change?
    CASE
        WHEN ABS(clicks::NUMERIC/NULLIF(impressions,0)
                 - LAG(clicks::NUMERIC/NULLIF(impressions,0)) OVER (PARTITION BY channel ORDER BY campaign_week))
             > 0.01
        THEN 'CTR Shift'

        WHEN ABS(attributed_orders::NUMERIC/NULLIF(clicks,0)
                 - LAG(attributed_orders::NUMERIC/NULLIF(clicks,0)) OVER (PARTITION BY channel ORDER BY campaign_week))
             > 0.01
        THEN 'CVR Shift'

        WHEN ABS(spend/NULLIF(clicks,0)
                 - LAG(spend/NULLIF(clicks,0)) OVER (PARTITION BY channel ORDER BY campaign_week))
             > 0.20
        THEN 'CPC Shift (Auction Competition)'

        ELSE 'AOV / Revenue Mix Shift'
    END AS likely_root_cause

FROM channel_weekly
ORDER BY channel, campaign_week;


-- =============================================================================
-- STEP 3: DRILL DOWN — Find the specific campaigns causing the drop
-- =============================================================================

-- 3a. Which campaigns declined most in a specific week vs the week before?
--     Edit the week dates below to match your analysis period.
-- =============================================================================
-- DRILL DOWN — 2018-08-27 vs 2018-08-20 (the week every channel tanked)

The standout week: 2018-08-27. Every single channel dropped >55% simultaneously that week — Retargeting -75.7%, Display -62.6%, Google -62.5%, Meta -59.9%. That's not channel-specific noise; something happened account-wide or platform-wide (holiday, tracking outage, budget pause, algorithm issue, whatever). This is your primary lead — it's the only week where all four channels tank together.
-- =============================================================================
WITH week_current AS (
    SELECT
        campaign_name, channel, product_category,
        SUM(ad_spend)          AS spend,
        SUM(attributed_revenue) AS revenue,
        SUM(clicks)             AS clicks,
        SUM(attributed_orders)  AS conversions,
        SUM(impressions)        AS impressions
    FROM fct_ad_campaigns
    WHERE campaign_week = DATE_TRUNC('week', DATE '2018-08-27')
    GROUP BY campaign_name, channel, product_category
),
week_prior AS (
    SELECT
        campaign_name, channel, product_category,
        SUM(ad_spend)          AS spend,
        SUM(attributed_revenue) AS revenue,
        SUM(clicks)             AS clicks,
        SUM(attributed_orders)  AS conversions,
        SUM(impressions)        AS impressions
    FROM fct_ad_campaigns
    WHERE campaign_week = DATE_TRUNC('week', DATE '2018-08-20')
    GROUP BY campaign_name, channel, product_category
)
SELECT
    c.campaign_name,
    c.channel,
    c.product_category,

    -- Volume metrics, so you can see WHERE the drop originates
    c.impressions   AS impressions_current,
    p.impressions   AS impressions_prior,
    ROUND((c.impressions - p.impressions)::NUMERIC / NULLIF(p.impressions,0) * 100, 1) AS impressions_chg_pct,

    c.clicks        AS clicks_current,
    p.clicks        AS clicks_prior,
    ROUND((c.clicks - p.clicks)::NUMERIC / NULLIF(p.clicks,0) * 100, 1)                AS clicks_chg_pct,

    c.conversions   AS conversions_current,
    p.conversions   AS conversions_prior,
    ROUND((c.conversions - p.conversions)::NUMERIC / NULLIF(p.conversions,0) * 100, 1) AS conversions_chg_pct,

    c.spend         AS spend_current,
    p.spend         AS spend_prior,
    ROUND((c.spend - p.spend)::NUMERIC / NULLIF(p.spend,0) * 100, 1)                   AS spend_chg_pct,

    -- Efficiency metrics
    ROUND(c.clicks::NUMERIC / NULLIF(c.impressions,0) * 100, 2)      AS ctr_current,
    ROUND(p.clicks::NUMERIC / NULLIF(p.impressions,0) * 100, 2)      AS ctr_prior,

    ROUND(c.conversions::NUMERIC / NULLIF(c.clicks,0) * 100, 2)      AS cvr_current,
    ROUND(p.conversions::NUMERIC / NULLIF(p.clicks,0) * 100, 2)      AS cvr_prior,

    ROUND(c.revenue / NULLIF(c.spend, 0), 2) AS roas_current,
    ROUND(p.revenue / NULLIF(p.spend, 0), 2) AS roas_prior,
    ROUND(
        (c.revenue/NULLIF(c.spend,0) - p.revenue/NULLIF(p.spend,0))
        / NULLIF(p.revenue/NULLIF(p.spend,0), 0) * 100,
        1
    ) AS roas_chg_pct

FROM week_current c
FULL OUTER JOIN week_prior p
    USING (campaign_name, channel, product_category)
ORDER BY roas_chg_pct ASC NULLS LAST
LIMIT 50;


-- =============================================================================
-- STEP 4: HYPOTHESIS VALIDATION
-- Test whether the issue is isolated to a specific segment
-- =============================================================================

-- 4a. Is the CTR drop concentrated in one product category?
SELECT
    product_category,
    campaign_week,
    ROUND(SUM(clicks)::NUMERIC / NULLIF(SUM(impressions),0) * 100, 2) AS ctr_pct,
    SUM(impressions)                                                    AS impressions,
    SUM(ad_spend)                                                       AS spend
FROM fct_ad_campaigns
GROUP BY product_category, campaign_week
ORDER BY product_category, campaign_week;


-- 4b. Is the CVR drop driven by a specific channel?
SELECT
    channel,
    campaign_week,
    ROUND(SUM(attributed_orders)::NUMERIC / NULLIF(SUM(clicks),0) * 100, 2) AS cvr_pct,
    SUM(clicks)                                                         AS clicks,
    SUM(attributed_orders)                                                    AS conversions
FROM fct_ad_campaigns
GROUP BY channel, campaign_week
ORDER BY channel, campaign_week;


-- =============================================================================
-- STEP 5: RECOMMENDATION QUERY
-- Summarise findings and surface actionable budget reallocation
-- =============================================================================

-- 5a. Budget reallocation recommendation based on ROAS efficiency
WITH channel_perf AS (
    SELECT
        channel,
        SUM(ad_spend)  AS spend,
        SUM(attributed_revenue)   AS attributed_revenue,
        ROUND(SUM(attributed_revenue) / NULLIF(SUM(ad_spend),0), 2) AS roas
    FROM fct_ad_campaigns
    GROUP BY channel
),
total AS (SELECT SUM(spend) AS total_spend FROM channel_perf)
SELECT
    cp.channel,
    cp.spend,
    cp.attributed_revenue,
    cp.roas,
    ROUND(cp.spend / t.total_spend * 100, 1)            AS current_spend_share_pct,

    -- Recommended action
    CASE
        WHEN cp.roas >= 3.0 THEN 'INCREASE budget by 20–30%'
        WHEN cp.roas >= 2.0 THEN 'MAINTAIN — monitor weekly'
        WHEN cp.roas >= 1.0 THEN 'OPTIMISE — review targeting & creatives'
        ELSE                     'PAUSE or REDUCE — ROAS below breakeven'
    END AS recommended_action,

    -- Estimated revenue gain if we shift 10% of low-ROAS spend to top performer
    ROUND(
        (cp.spend * 0.10)
        * (SELECT MAX(roas) FROM channel_perf)
        , 2
    ) AS est_revenue_gain_if_reallocated

FROM channel_perf cp, total t
ORDER BY cp.roas DESC;
