-- =============================================================================
-- FILE: 03_kpi_queries.sql
-- PROJECT: E-Commerce Ad Campaign Analytics
-- DESCRIPTION: KPI tracking queries — CTR, ROAS, CPA, CVR, Revenue, Spend.
--              These power the Tableau dashboard KPI tiles and trend charts.
-- =============================================================================


-- =============================================================================
-- QUERY 1: Master KPI Summary (Dashboard Header Tiles)
-- Business Question: What are our overall campaign numbers this period?
-- =============================================================================

SELECT
    COUNT(DISTINCT campaign_id)                                              AS total_campaigns,
    SUM(impressions)                                                         AS total_impressions,
    SUM(clicks)                                                              AS total_clicks,
    SUM(attributed_orders)                                                         AS total_attributed_orders,
    ROUND(SUM(ad_spend), 2)                                                  AS total_spend,
    ROUND(SUM(attributed_revenue), 2)                                                   AS total_attributed_revenue,
    ROUND(SUM(attributed_revenue) - SUM(ad_spend), 2)                                   AS net_profit,

    -- Core KPIs
    ROUND(SUM(clicks)::NUMERIC      / NULLIF(SUM(impressions),0)  * 100, 2) AS ctr_pct,
    ROUND(SUM(attributed_orders)::NUMERIC / NULLIF(SUM(clicks),0)       * 100, 2) AS cvr_pct,
    ROUND(SUM(attributed_revenue) / NULLIF(SUM(ad_spend), 0), 2)                       AS roas,
    ROUND(SUM(ad_spend) / NULLIF(SUM(clicks), 0), 2)                        AS avg_cpc,
    ROUND(SUM(ad_spend) / NULLIF(SUM(attributed_orders), 0), 2)                   AS avg_cpa,
    ROUND(SUM(attributed_revenue)  / NULLIF(SUM(attributed_orders), 0), 2)                   AS avg_order_value

FROM fct_ad_campaigns;


-- =============================================================================
-- QUERY 2: Weekly KPI Trend (Line Chart in Tableau)
-- Business Question: How are our core KPIs trending week over week?
-- =============================================================================

SELECT
    campaign_week,
    TO_CHAR(campaign_week, 'YYYY-"W"IW')                                    AS week_label,
    COUNT(DISTINCT campaign_id)                                              AS active_campaigns,
    SUM(impressions)                                                         AS impressions,
    SUM(clicks)                                                              AS clicks,
    SUM(attributed_orders)                                                         AS attributed_orders,
    ROUND(SUM(ad_spend), 2)                                                  AS spend,
    ROUND(SUM(attributed_revenue), 2)                                                   AS attributed_revenue,

    -- KPIs
    ROUND(SUM(clicks)::NUMERIC      / NULLIF(SUM(impressions),0)  * 100, 2) AS ctr_pct,
    ROUND(SUM(attributed_orders)::NUMERIC / NULLIF(SUM(clicks),0)       * 100, 2) AS cvr_pct,
    ROUND(SUM(attributed_revenue) / NULLIF(SUM(ad_spend), 0), 2)                       AS roas,
    ROUND(SUM(ad_spend) / NULLIF(SUM(attributed_orders), 0), 2)                   AS cpa,

    -- WoW % change in ROAS
    ROUND(
        (
            (SUM(attributed_revenue) / NULLIF(SUM(ad_spend), 0))
            - LAG(SUM(attributed_revenue) / NULLIF(SUM(ad_spend), 0)) OVER (ORDER BY campaign_week)
        )
        / NULLIF(LAG(SUM(attributed_revenue) / NULLIF(SUM(ad_spend), 0)) OVER (ORDER BY campaign_week), 0)
        * 100,
        1
    ) AS roas_wow_chg_pct,

    -- WoW % change in spend
    ROUND(
        (SUM(ad_spend) - LAG(SUM(ad_spend)) OVER (ORDER BY campaign_week))
        / NULLIF(LAG(SUM(ad_spend)) OVER (ORDER BY campaign_week), 0) * 100,
        1
    ) AS spend_wow_chg_pct

FROM fct_ad_campaigns
GROUP BY campaign_week
ORDER BY campaign_week;


-- =============================================================================
-- QUERY 3: KPI by Channel (Bar Chart — ROAS Comparison)
-- Business Question: How does each channel perform on every KPI?
-- =============================================================================

SELECT
    channel,
    SUM(impressions)                                                         AS impressions,
    SUM(clicks)                                                              AS clicks,
    SUM(attributed_orders)                                                         AS attributed_orders,
    ROUND(SUM(ad_spend), 2)                                                  AS total_spend,
    ROUND(SUM(attributed_revenue), 2)                                                   AS total_attributed_revenue,
    ROUND(SUM(clicks)::NUMERIC      / NULLIF(SUM(impressions),0)  * 100, 2) AS ctr_pct,
    ROUND(SUM(attributed_orders)::NUMERIC / NULLIF(SUM(clicks),0)       * 100, 2) AS cvr_pct,
    ROUND(SUM(attributed_revenue) / NULLIF(SUM(ad_spend), 0), 2)                       AS roas,
    ROUND(SUM(ad_spend) / NULLIF(SUM(clicks), 0), 2)                        AS cpc,
    ROUND(SUM(ad_spend) / NULLIF(SUM(attributed_orders), 0), 2)                   AS cpa,
    ROUND(SUM(attributed_revenue)  / NULLIF(SUM(attributed_orders), 0), 2)                   AS avg_order_value,

    -- Share of total spend
    ROUND(SUM(ad_spend) / SUM(SUM(ad_spend)) OVER () * 100, 1)             AS spend_share_pct,
    -- Share of total revenue
    ROUND(SUM(attributed_revenue) / SUM(SUM(attributed_revenue)) OVER () * 100, 1)               AS revenue_share_pct

FROM fct_ad_campaigns
GROUP BY channel
ORDER BY roas DESC;


-- =============================================================================
-- QUERY 4: Daily KPI (for day-of-week analysis)
-- Business Question: Which days of the week perform best? Should we shift budget?
-- =============================================================================

SELECT
    TO_CHAR(campaign_date, 'Day')                                            AS day_name,
    EXTRACT(DOW FROM campaign_date)                                          AS day_num,  -- 0=Sun
    COUNT(*)                                                                 AS data_points,
    ROUND(AVG(ctr_pct), 2)                                                   AS avg_ctr_pct,
    ROUND(AVG(cvr_pct), 2)                                                   AS avg_cvr_pct,
    ROUND(AVG(roas), 2)                                                      AS avg_roas,
    ROUND(SUM(ad_spend) / COUNT(DISTINCT campaign_date), 2)                  AS avg_daily_spend,
    ROUND(SUM(attributed_revenue)  / COUNT(DISTINCT campaign_date), 2)                  AS avg_daily_revenue
FROM fct_ad_campaigns
GROUP BY day_name, day_num
ORDER BY day_num;


-- =============================================================================
-- QUERY 5: Budget Efficiency — Spend vs Revenue Scatter Data
-- Business Question: Are high-spend campaigns generating proportional revenue?
-- =============================================================================

WITH campaign_totals AS (
  SELECT
    campaign_name,
    SUM(ad_spend)            AS campaign_total_spend
  FROM fct_ad_campaigns
  GROUP BY campaign_name
),
median_spend AS (
  SELECT
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY campaign_total_spend) AS median_ad_spend
  FROM campaign_totals
)
SELECT
  campaign_name,
  channel,
  product_category,
  SUM(ad_spend)                                     AS total_spend,
  SUM(attributed_revenue)                          AS total_attributed_revenue,
  SUM(attributed_orders)                           AS total_conversions,
  ROUND(SUM(attributed_revenue) / NULLIF(SUM(ad_spend), 0), 2) AS roas,

  CASE
    WHEN SUM(ad_spend) > (SELECT median_ad_spend FROM median_spend)
         AND SUM(attributed_revenue) / NULLIF(SUM(ad_spend), 0) > 2.0
      THEN 'Scale Up (High Spend, High ROAS)'

    WHEN SUM(ad_spend) > (SELECT median_ad_spend FROM median_spend)
         AND SUM(attributed_revenue) / NULLIF(SUM(ad_spend), 0) <= 2.0
      THEN 'Optimise (High Spend, Low ROAS)'

    WHEN SUM(ad_spend) <= (SELECT median_ad_spend FROM median_spend)
         AND SUM(attributed_revenue) / NULLIF(SUM(ad_spend), 0) > 2.0
      THEN 'Invest More (Low Spend, High ROAS)'

    ELSE 'Review or Pause (Low Spend, Low ROAS)'
  END AS budget_action

FROM fct_ad_campaigns
GROUP BY campaign_name, channel, product_category
ORDER BY total_spend DESC;


-- =============================================================================
-- QUERY 6: Category Revenue vs Ad Spend (Treemap Data)
-- Business Question: Which categories generate the most revenue from ad investment?
-- =============================================================================

SELECT
    product_category,
    ROUND(SUM(ad_spend), 2)                                                  AS total_spend,
    ROUND(SUM(attributed_revenue), 2)                                                   AS total_attributed_revenue,
    SUM(attributed_orders)                                                         AS total_attributed_orders,
    ROUND(SUM(attributed_revenue) / NULLIF(SUM(ad_spend), 0), 2)                       AS roas,
    ROUND(SUM(attributed_revenue) / SUM(SUM(attributed_revenue)) OVER () * 100, 1)                AS pct_of_total_revenue
FROM fct_ad_campaigns
GROUP BY product_category
ORDER BY total_attributed_revenue DESC;


-- =============================================================================
-- QUERY 7: Month-over-Month KPI Summary
-- Business Question: Are we growing? What's the MoM trajectory?
-- =============================================================================

SELECT
    campaign_month,
    TO_CHAR(campaign_month, 'Mon YYYY')                                      AS month_label,
    ROUND(SUM(ad_spend), 2)                                                  AS spend,
    ROUND(SUM(attributed_revenue), 2)                                                   AS attributed_revenue,
    SUM(attributed_orders)                                                         AS attributed_orders,
    ROUND(SUM(attributed_revenue) / NULLIF(SUM(ad_spend), 0), 2)                       AS roas,
    ROUND(SUM(attributed_orders)::NUMERIC / NULLIF(SUM(clicks), 0) * 100, 2)      AS cvr_pct,

    -- MoM Revenue Growth %
    ROUND(
        (SUM(attributed_revenue) - LAG(SUM(attributed_revenue)) OVER (ORDER BY campaign_month))
        / NULLIF(LAG(SUM(attributed_revenue)) OVER (ORDER BY campaign_month), 0) * 100,
        1
    ) AS revenue_mom_chg_pct,

    -- MoM Spend Growth %
    ROUND(
        (SUM(ad_spend) - LAG(SUM(ad_spend)) OVER (ORDER BY campaign_month))
        / NULLIF(LAG(SUM(ad_spend)) OVER (ORDER BY campaign_month), 0) * 100,
        1
    ) AS spend_mom_chg_pct

FROM fct_ad_campaigns
GROUP BY campaign_month
ORDER BY campaign_month;
