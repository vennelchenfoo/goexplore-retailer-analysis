-- ============================================================================
-- GoExplore Retailer Performance Analytics View
-- WBS Coding School - Data Science & AI Bootcamp
-- Author: Keila
-- Created: November 2025
-- ============================================================================

-- Purpose: Create comprehensive retailer analytics view for dashboard
-- Tables Used: 
--   - Bootcamp.daily_sales_renamed
--   - Bootcamp.retailers_renamed
-- Output: Bootcamp.retailer_analytics (view)

-- ============================================================================
-- MAIN VIEW: retailer_analytics
-- ============================================================================

CREATE OR REPLACE VIEW `goexplore-476414.Bootcamp.retailer_analytics` AS

-- ============================================================================
-- STEP 1: Base Aggregation
-- Aggregate sales by retailer × year
-- ============================================================================
WITH base AS (
  SELECT
    r.retailer_code,
    r.retailer_name,
    r.retailer_type,
    r.country,
    EXTRACT(YEAR FROM ds.date) AS year,
    SUM(ds.quantity * ds.unit_sale_price) AS revenue_year,
    SUM(ds.quantity * (ds.unit_price - ds.unit_sale_price)) AS profit_year
  FROM `goexplore-476414.Bootcamp.daily_sales_renamed` ds
  JOIN `goexplore-476414.Bootcamp.retailers_renamed` r USING (retailer_code)
  GROUP BY r.retailer_code, r.retailer_name, r.retailer_type, r.country, year
),

-- ============================================================================
-- STEP 2: Previous Year Revenue (for YoY Growth)
-- Use LAG() window function to get prior year revenue
-- ============================================================================
prev AS (
  SELECT
    retailer_code,
    year,
    LAG(revenue_year) OVER (PARTITION BY retailer_code ORDER BY year) AS revenue_prev_year
  FROM base
),

-- ============================================================================
-- STEP 3: Enriched Metrics
-- Calculate profit margins and YoY growth rates
-- ============================================================================
enriched AS (
  SELECT
    b.retailer_code,
    b.retailer_name,
    b.retailer_type,
    b.country,
    b.year,
    ROUND(b.revenue_year, 2) AS total_revenue,
    ROUND(b.profit_year, 2)  AS total_profit,
    ROUND(SAFE_DIVIDE(b.profit_year, NULLIF(b.revenue_year,0)) * 100, 2) AS profit_margin_pct,
    p.revenue_prev_year,
    ROUND(
      SAFE_DIVIDE(b.revenue_year - p.revenue_prev_year, NULLIF(p.revenue_prev_year,0)) * 100, 2
    ) AS yoy_growth_pct,
    CASE
      WHEN SAFE_DIVIDE(b.revenue_year - p.revenue_prev_year, NULLIF(p.revenue_prev_year,0)) > 0
      THEN TRUE ELSE FALSE
    END AS is_growing
  FROM base b
  LEFT JOIN prev p
    ON p.retailer_code = b.retailer_code
   AND p.year = b.year
),

-- ============================================================================
-- STEP 4: Latest Year Per Retailer
-- Identify most recent year of data for each retailer
-- ============================================================================
latest_year_per_retailer AS (
  SELECT retailer_code, MAX(year) AS latest_year
  FROM enriched
  GROUP BY retailer_code
),

-- ============================================================================
-- STEP 5: Current Year Snapshot
-- One row per retailer (their latest year only)
-- ============================================================================
current_year_rows AS (
  SELECT e.*
  FROM enriched e
  JOIN latest_year_per_retailer l
    ON e.retailer_code = l.retailer_code
   AND e.year = l.latest_year
),

-- ============================================================================
-- STEP 6: Country-Level Rankings
-- Rank retailers within each country and identify top 20%
-- ============================================================================
ranked_current_year AS (
  SELECT
    c.*,
    -- Count retailers per country
    COUNT(*) OVER (PARTITION BY c.country) AS retailer_count_in_country_latest,
    -- Rank by revenue within country
    RANK()  OVER (PARTITION BY c.country ORDER BY c.total_revenue DESC) AS revenue_rank_in_country_latest
  FROM current_year_rows c
)

-- ============================================================================
-- FINAL SELECT: Combine All Metrics
-- Returns retailer × year rows with latest-year analytics
-- ============================================================================
SELECT
  -- Core retailer dimensions
  e.retailer_code,
  e.retailer_name,
  e.retailer_type,
  e.country,
  e.year,
  
  -- Financial metrics
  e.total_revenue,
  e.total_profit,
  e.profit_margin_pct,
  
  -- Growth metrics
  e.revenue_prev_year,
  e.yoy_growth_pct,
  e.is_growing,

  -- Latest-year-only fields (NULL for non-latest years)
  rcy.retailer_count_in_country_latest,
  rcy.revenue_rank_in_country_latest,
  
  -- Top 20% indicator (Pareto principle)
  CASE
    WHEN rcy.revenue_rank_in_country_latest
         <= CEIL(0.20 * rcy.retailer_count_in_country_latest)
    THEN TRUE ELSE FALSE
  END AS is_top20pct_in_country_latest,

  -- Performance tier classification (rule-based)
  CASE
    WHEN rcy.yoy_growth_pct >= 10 AND rcy.profit_margin_pct >= 15
      THEN 'Top Performer'
    WHEN rcy.yoy_growth_pct >= 0
      THEN 'Average Performer'
    ELSE 'Low Performer'
  END AS performance_tier_latest

FROM enriched e
LEFT JOIN ranked_current_year rcy
  ON rcy.retailer_code = e.retailer_code;


-- ============================================================================
-- USAGE EXAMPLES
-- ============================================================================

-- Example 1: Top 10 retailers by revenue (latest year)
/*
SELECT 
  retailer_name,
  country,
  year,
  total_revenue,
  profit_margin_pct,
  performance_tier_latest
FROM `goexplore-476414.Bootcamp.retailer_analytics`
WHERE year = (SELECT MAX(year) FROM `goexplore-476414.Bootcamp.retailer_analytics`)
ORDER BY total_revenue DESC
LIMIT 10;
*/

-- Example 2: Performance tier distribution (latest year)
/*
SELECT 
  performance_tier_latest,
  COUNT(*) as retailer_count,
  ROUND(AVG(yoy_growth_pct), 2) as avg_growth,
  ROUND(AVG(profit_margin_pct), 2) as avg_margin
FROM `goexplore-476414.Bootcamp.retailer_analytics`
WHERE year = (SELECT MAX(year) FROM `goexplore-476414.Bootcamp.retailer_analytics`)
  AND performance_tier_latest IS NOT NULL
GROUP BY performance_tier_latest
ORDER BY 
  CASE performance_tier_latest
    WHEN 'Top Performer' THEN 1
    WHEN 'Average Performer' THEN 2
    ELSE 3
  END;
*/

-- Example 3: YoY growth trend for specific retailer
/*
SELECT 
  year,
  total_revenue,
  yoy_growth_pct,
  is_growing
FROM `goexplore-476414.Bootcamp.retailer_analytics`
WHERE retailer_name = 'Grand choix'
ORDER BY year;
*/

-- Example 4: Top 20% revenue contributors per country
/*
SELECT 
  country,
  retailer_name,
  total_revenue,
  revenue_rank_in_country_latest,
  is_top20pct_in_country_latest
FROM `goexplore-476414.Bootcamp.retailer_analytics`
WHERE year = (SELECT MAX(year) FROM `goexplore-476414.Bootcamp.retailer_analytics`)
  AND is_top20pct_in_country_latest = TRUE
ORDER BY country, revenue_rank_in_country_latest;
*/


-- ============================================================================
-- KEY METRICS EXPLAINED
-- ============================================================================

/*
total_revenue:                Revenue for the retailer in given year
total_profit:                 Profit for the retailer in given year
profit_margin_pct:            Profit as % of revenue
revenue_prev_year:            Revenue from previous year (for comparison)
yoy_growth_pct:               Year-over-year growth percentage
is_growing:                   Boolean: TRUE if positive growth
retailer_count_in_country:    Total retailers in same country (latest year)
revenue_rank_in_country:      Rank within country (1 = highest revenue)
is_top20pct_in_country:       Boolean: TRUE if in top 20% by revenue
performance_tier:             Top/Average/Low based on growth + margin
*/


-- ============================================================================
-- BUSINESS RULES
-- ============================================================================

/*
PERFORMANCE TIER CLASSIFICATION:

Top Performer:
  - YoY Growth >= 10%
  - AND Profit Margin >= 15%
  - Strategic partners with strong performance

Average Performer:
  - YoY Growth >= 0%
  - Positive growth but not meeting top performer criteria
  - Development candidates

Low Performer:
  - YoY Growth < 0%
  - Declining revenue year-over-year
  - At-risk partners requiring intervention


TOP 20% IDENTIFICATION:
  - Calculated per country (not global)
  - Based on revenue ranking
  - Follows Pareto principle (80/20 rule)
  - Used for identifying key partners per market
*/


-- ============================================================================
-- NOTES
-- ============================================================================

/*
1. This view combines historical time-series data with latest-year analytics
2. Latest-year fields (e.g., revenue_rank_in_country_latest) are NULL for 
   non-current years to avoid confusion
3. Uses SAFE_DIVIDE to handle division by zero gracefully
4. Window functions (LAG, RANK) enable efficient year-over-year comparisons
5. Performance tiers update automatically as new data is loaded
*/


-- ============================================================================
-- END OF FILE
-- ============================================================================
