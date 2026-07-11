-- =============================================================================
-- FILE: 02_funnel_analysis.sql
-- PROJECT: E-Commerce Ad Campaign Analytics
-- DESCRIPTION: Full funnel from impressions → clicks → conversions → revenue.
--              Answers: Where are users dropping off? Which channels convert best?
-- =============================================================================


-- =============================================================================
-- QUERY 1: Overall Funnel Summary
-- Business Question: What does the end-to-end funnel look like across all campaigns?
-- =============================================================================

SELECT
    'All Campaigns'                                         AS segment,
    SUM(impressions)                                        AS impressions,
    SUM(clicks)                                             AS clicks,
    SUM(attributed_orders)                                        AS attributed_orders,
    SUM(ad_spend)                                           AS total_spend,
    SUM(attributed_revenue)                                            AS total_attributed_revenue,

    -- Stage drop-offs
    ROUND(SUM(clicks)::NUMERIC       / NULLIF(SUM(impressions),0)  * 100, 2) AS imp_to_click_pct,
    ROUND(SUM(attributed_orders)::NUMERIC  / NULLIF(SUM(clicks),0)       * 100, 2) AS click_to_conv_pct,
    ROUND(SUM(attributed_orders)::NUMERIC  / NULLIF(SUM(impressions),0)  * 100, 4) AS overall_conv_rate_pct,

    -- Revenue metrics
    ROUND(SUM(attributed_revenue) / NULLIF(SUM(ad_spend), 0), 2)              AS roas,
    ROUND(SUM(ad_spend) / NULLIF(SUM(attributed_orders), 0), 2)          AS cpa

FROM fct_ad_campaigns;


-- =============================================================================
-- QUERY 2: Funnel by Channel
-- Business Question: Which channel has the best/worst drop-off at each stage?
-- =============================================================================

SELECT
    channel,
    SUM(impressions)                                                        AS impressions,
    SUM(clicks)                                                             AS clicks,
    SUM(attributed_orders)                                                        AS attributed_orders,
    SUM(ad_spend)                                                           AS total_spend,
    SUM(attributed_revenue)                                                            AS total_attributed_revenue,

    -- Stage metrics
    ROUND(SUM(clicks)::NUMERIC      / NULLIF(SUM(impressions),0)  * 100, 2) AS ctr_pct,
    ROUND(SUM(attributed_orders)::NUMERIC / NULLIF(SUM(clicks),0)       * 100, 2) AS cvr_pct,
    ROUND(SUM(attributed_revenue) / NULLIF(SUM(ad_spend), 0), 2)                       AS roas,
    ROUND(SUM(ad_spend) / NULLIF(SUM(attributed_orders), 0), 2)                   AS cpa,

    -- Rank by ROAS
    RANK() OVER (ORDER BY SUM(attributed_revenue) / NULLIF(SUM(ad_spend), 0) DESC)    AS roas_rank

FROM fct_ad_campaigns
GROUP BY channel
ORDER BY roas_rank;

-- EXPECTED INSIGHT:
-- Retargeting typically shows low CTR but HIGH CVR (users already know the brand)
-- Display typically shows high impressions but low CTR and low CVR
-- Identify channels with HIGH CTR but LOW CVR → landing page or offer problem


-- =============================================================================
-- QUERY 3: Funnel by Product Category
-- Business Question: Which product categories convert best from ads?
-- =============================================================================

SELECT
    product_category,
    SUM(impressions)                                                         AS impressions,
    SUM(clicks)                                                              AS clicks,
    SUM(attributed_orders)                                                         AS attributed_orders,
    SUM(ad_spend)                                                            AS total_spend,
    SUM(attributed_revenue)                                                             AS total_attributed_revenue,
    ROUND(SUM(clicks)::NUMERIC      / NULLIF(SUM(impressions),0)  * 100, 2) AS ctr_pct,
    ROUND(SUM(attributed_orders)::NUMERIC / NULLIF(SUM(clicks),0)       * 100, 2) AS cvr_pct,
    ROUND(SUM(attributed_revenue) / NULLIF(SUM(ad_spend), 0), 2)                       AS roas,

    -- Flag underperforming categories
    CASE
        WHEN SUM(attributed_revenue) / NULLIF(SUM(ad_spend), 0) < 1.5  THEN 'Underperforming'
        WHEN SUM(attributed_revenue) / NULLIF(SUM(ad_spend), 0) < 2.5  THEN 'Average'
        ELSE 'Strong'
    END AS performance_tier

FROM fct_ad_campaigns
GROUP BY product_category
ORDER BY roas DESC;


-- =============================================================================
-- QUERY 4: Funnel by Channel × Category (Cross-dimension)
-- Business Question: Which channel-category combinations are most/least efficient?
-- =============================================================================

SELECT
    channel,
    product_category,
    SUM(impressions)                                                         AS impressions,
    SUM(clicks)                                                              AS clicks,
    SUM(attributed_orders)                                                         AS attributed_orders,
    ROUND(SUM(clicks)::NUMERIC      / NULLIF(SUM(impressions),0)  * 100, 2) AS ctr_pct,
    ROUND(SUM(attributed_orders)::NUMERIC / NULLIF(SUM(clicks),0)       * 100, 2) AS cvr_pct,
    ROUND(SUM(attributed_revenue) / NULLIF(SUM(ad_spend), 0), 2)                       AS roas,
    SUM(ad_spend)                                                            AS total_spend,
    SUM(attributed_revenue)                                                             AS total_revenue
FROM fct_ad_campaigns
GROUP BY channel, product_category
ORDER BY roas DESC
LIMIT 30;


-- =============================================================================
-- QUERY 5: Weekly Funnel Trend
-- Business Question: Is the funnel improving or deteriorating week over week?
-- =============================================================================

SELECT
    campaign_week,
    SUM(impressions)                                                         AS impressions,
    SUM(clicks)                                                              AS clicks,
    SUM(attributed_orders)                                                         AS attributed_orders,
    SUM(ad_spend)                                                            AS total_spend,
    SUM(attributed_revenue)                                                             AS total_attributed_revenue,
    ROUND(SUM(clicks)::NUMERIC      / NULLIF(SUM(impressions),0)  * 100, 2) AS ctr_pct,
    ROUND(SUM(attributed_orders)::NUMERIC / NULLIF(SUM(clicks),0)       * 100, 2) AS cvr_pct,
    ROUND(SUM(attributed_revenue) / NULLIF(SUM(ad_spend), 0), 2)                       AS roas,

    -- Week-over-week ROAS change
    ROUND(
        (SUM(attributed_revenue) / NULLIF(SUM(ad_spend), 0))
        - LAG(SUM(attributed_revenue) / NULLIF(SUM(ad_spend), 0))
            OVER (ORDER BY campaign_week),
        3
    ) AS roas_wow_change,

    -- Week-over-week CVR change
    ROUND(
        (SUM(attributed_orders)::NUMERIC / NULLIF(SUM(clicks), 0) * 100)
        - LAG(SUM(attributed_orders)::NUMERIC / NULLIF(SUM(clicks), 0) * 100)
            OVER (ORDER BY campaign_week),
        2
    ) AS cvr_wow_change_pct

FROM fct_ad_campaigns
GROUP BY campaign_week
ORDER BY campaign_week;


-- =============================================================================
-- QUERY 6: Drop-off Rate Between Funnel Stages (Waterfall View)
-- Business Question: At which exact stage are we losing the most potential customers?
-- =============================================================================

WITH funnel_totals AS (
    SELECT
        SUM(impressions)   AS total_impressions,
        SUM(clicks)        AS total_clicks,
        SUM(attributed_orders)   AS total_conversions
    FROM fct_ad_campaigns
)
SELECT
    stage,
    users,
    ROUND(users::NUMERIC / MAX(users) OVER () * 100, 1)                    AS pct_of_top,
    ROUND((1 - users::NUMERIC / LAG(users) OVER (ORDER BY stage_order)) * 100, 1) AS drop_off_pct
FROM (
    SELECT 1 AS stage_order, 'Impressions'  AS stage, total_impressions  AS users FROM funnel_totals
    UNION ALL
    SELECT 2,                'Clicks',                 total_clicks               FROM funnel_totals
    UNION ALL
    SELECT 3,                'Conversions',            total_conversions           FROM funnel_totals
) funnel_stages
ORDER BY stage_order;


-- =============================================================================
-- QUERY 7: Top 10 Campaigns by Conversion Volume
-- Business Question: Which campaigns are driving the most actual sales?
-- =============================================================================

SELECT
    campaign_name,
    channel,
    product_category,
    SUM(attributed_orders)                                                         AS total_attributed_orders,
    SUM(ad_spend)                                                            AS total_spend,
    SUM(attributed_revenue)                                                             AS total_attributed_revenue,
    ROUND(SUM(attributed_revenue) / NULLIF(SUM(ad_spend), 0), 2)                       AS roas,
    ROUND(SUM(ad_spend) / NULLIF(SUM(attributed_orders), 0), 2)                   AS cpa,
    ROUND(SUM(attributed_orders)::NUMERIC / NULLIF(SUM(clicks), 0) * 100, 2)      AS cvr_pct,
    ROUND(SUM(attributed_orders)::NUMERIC / NULLIF(SUM(clicks), 0) , 2)      AS total_conversions
FROM fct_ad_campaigns
GROUP BY campaign_name, channel, product_category
ORDER BY total_conversions DESC
LIMIT 10;


-- =============================================================================
-- QUERY 8: Bottom 10 Campaigns by ROAS (Candidates for Budget Reallocation)
-- Business Question: Where is budget being wasted?
-- =============================================================================

SELECT
    campaign_name,
    channel,
    product_category,
    SUM(ad_spend)                                                            AS total_spend,
    SUM(attributed_revenue)                                                             AS total_attributed_revenue,
    ROUND(SUM(attributed_revenue) / NULLIF(SUM(ad_spend), 0), 2)                       AS roas,
    ROUND(SUM(clicks)::NUMERIC / NULLIF(SUM(impressions), 0) * 100, 2)      AS ctr_pct,
    ROUND(SUM(attributed_orders)::NUMERIC / NULLIF(SUM(clicks), 0) * 100, 2)      AS cvr_pct,
    -- Diagnosis: Is it a click problem or a conversion problem?
    CASE
        WHEN SUM(clicks)::NUMERIC / NULLIF(SUM(impressions),0) < 0.02
        THEN 'Creative/Targeting Issue (Low CTR)'
        WHEN SUM(attributed_orders)::NUMERIC / NULLIF(SUM(clicks),0) < 0.02
        THEN 'Landing Page/Offer Issue (Low CVR)'
        ELSE 'High CPC / Low Revenue per Order'
    END AS likely_issue
FROM fct_ad_campaigns
GROUP BY campaign_name, channel, product_category
HAVING SUM(ad_spend) > 100           -- only campaigns with meaningful spend
ORDER BY roas ASC
LIMIT 10;
