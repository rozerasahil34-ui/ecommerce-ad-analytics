# E-Commerce Ad Campaign Analytics

An ad-campaign analytics project built on the **Olist e-commerce dataset**, combined with a simulated ad-campaign dataset (Olist doesn't include real ad spend/impressions data). The project traces the funnel from impression → click → conversion → revenue, tracks the KPIs used for dashboarding, and runs root-cause analysis (RCA) when a KPI moves.

It's implemented **twice, independently**, using the same base dataset:

- **SQL track** - SQL track - PostgreSQL views + queries, written up as a full report and visualized in Tableau https://public.tableau.com/app/profile/sahil.rozera/viz/ecommerce-ad-analytics/PerformanceOverview
- **Python track** - Jupyter notebooks using pandas/matplotlib/plotly, which additionally include an A/B test analysis.

The two tracks are **not dependent on each other** - different code, different simulation methodology for the ad data, different tools - but they answer the same business questions on top of the same Olist source data, so they're documented together here as one project.

**Author:** Sahil

## Project Structure

```
ecommerce-ad-analytics/
├── sql/
│   ├── 01_schema.sql              # Table + view definitions
│   ├── 02_funnel_analysis.sql     # 8 funnel queries
│   ├── 03_kpi_queries.sql         # 7 KPI/dashboard queries
│   ├── 04_rca_queries.sql         # 5-step RCA workflow
│   └── ecommerce-ad-analytics_Full_Report.docx   # Full write-up: schema/ERD, glossary, every query + result + insight
├── src/
│   ├── generate_ad_data.py        # Generates the simulated ad dataset used by the SQL track
│   └── verify_ad_data.py          # Validates the generated dataset before loading
├── notebooks/
│   ├── 01_data_cleaning.ipynb         # Clean Olist CSVs, build master table
│   ├── 02_ad_data_simulation.ipynb    # Simulate ad data used by the Python track
│   ├── 03_funnel_analysis.ipynb       # Funnel analysis + visualizations
│   ├── 04_rca_analysis.ipynb          # 5-step RCA framework
│   └── 05_ab_test.ipynb               # A/B test analysis (Python-only)
└── data/
    ├── raw/                        # Olist source CSVs (shared by both tracks)
    └── processed/                  # Cleaned + simulated outputs (generated separately per track)
```

## Shared Dataset

Both tracks start from the same raw Olist CSVs — `orders`, `order_items`, `products`, `customers`, `payments`, `reviews`, `sellers`. Neither the SQL nor the Python track modifies the other's inputs or outputs; each cleans the raw data and simulates its own ad-campaign layer independently (see below), so results between the two tracks won't match exactly.

## SQL Track

Run the SQL files in order against a PostgreSQL database loaded with the raw Olist CSVs:

```bash
psql -d your_database -f sql/01_schema.sql
psql -d your_database -f sql/02_funnel_analysis.sql
psql -d your_database -f sql/03_kpi_queries.sql
psql -d your_database -f sql/04_rca_queries.sql
```

`01_schema.sql` creates the raw Olist tables, a simulated `raw_ad_campaigns` table, and a cleaned analytics layer of views:

- **`fct_orders`** - cleaned, delivered orders with purchase date parts and delivery-status flag
- **`fct_order_revenue`** - order-item-level revenue joined to product category and payment info
- **`dim_customers`** - customers mapped to Brazilian region
- **`fct_ad_campaigns`** - cleaned ad campaign data with derived metrics (CTR, CVR, ROAS, CPC, CPA, AOV, ROI) pre-calculated

Every query in `02`-`04` reads from `fct_ad_campaigns` (and occasionally `fct_orders` / `dim_customers`), so the views must exist first.

### Simulated Ad Data - `src/generate_ad_data.py`

Builds `raw_ad_campaigns` for the SQL track by working **backward from real Olist sales**:

1. Loads orders/items/products, filters to delivered/valid orders between **2017-01-01 and 2018-08-31**.
2. Aggregates real daily sales (orders + revenue) per product category - the ground truth the simulation anchors to.
3. Builds 60 campaigns: top 15 Olist categories × 4 channels (Google, Meta, Display, Retargeting).
4. For each date × campaign, simulates attributed orders from real category sales × an attribution rate, then **derives clicks and impressions backward** from attributed orders using channel CTR/CVR, with a few hand-tuned category × channel boosts (e.g. Health & Beauty performs better on Meta; Computer Accessories on Google; Watches & Gifts on Retargeting; Bed & Bath has poor Display CVR).
5. Calculates ad spend - CPM-based for Display, CPC-based for the other channels.
6. Exports to `data/processed/simulated_ad_spend.csv`, loaded into `raw_ad_campaigns`.

Verified by `src/verify_ad_data.py`: checks row count (608 days × 60 campaigns = 36,480 rows), no missing values, correct schema and date range, logical integrity (`impressions ≥ clicks ≥ attributed_orders`; spend/orders/revenue ≥ 0), and sanity checks that Display has the lowest channel ROAS and Retargeting the highest.

```bash
python src/generate_ad_data.py
python src/verify_ad_data.py
```

### Key Metrics Glossary

| Metric | Formula | What it measures |
|---|---|---|
| **CTR** | Clicks ÷ Impressions × 100 | Ad creative/targeting appeal |
| **CVR** | Attributed Orders ÷ Clicks × 100 | How well traffic converts once it lands |
| **Overall Conversion Rate** | Attributed Orders ÷ Impressions × 100 | Full end-to-end funnel efficiency |
| **ROAS** | Attributed Revenue ÷ Ad Spend | Revenue generated per ad dollar |
| **ROI %** | (Attributed Revenue − Ad Spend) ÷ Ad Spend × 100 | Net profitability of spend |
| **CPA** | Ad Spend ÷ Attributed Orders | Average cost per acquisition |
| **CPC** | Ad Spend ÷ Clicks | Average cost per click |
| **AOV** | Attributed Revenue ÷ Attributed Orders | Average revenue per order |

Full glossary (channel definitions, performance tiers, alert levels, root-cause drivers, etc.) is in the Word report.

### SQL Track - Headline Findings

- **Blended performance:** $3.09M ad spend generated $5.66M attributed revenue (ROAS 1.83), but impression-to-order conversion is only 0.0087% - lots of room to optimize the funnel.
- **Retargeting wins:** lowest spend ($154K), best ROAS (6.38) and CVR (4.52%) - warm audiences convert far more efficiently.
- **Google vs Meta:** similar ROAS (~3.5), but Google's CTR is ~3x Meta's.
- **Display underperforms:** 78% of impressions, 56% of spend, but only 0.23 ROAS and 7% of revenue - top candidate for reallocation.
- **Account-wide anomaly:** week of 2018-08-27 - every channel's ROAS drops >55% simultaneously (Retargeting -75.7%, Display -62.6%, Google -62.5%, Meta -59.9%), pointing to a platform-wide issue rather than channel-specific noise.

### SQL Track - RCA Workflow (`04_rca_queries.sql`)

1. **Detect** - flag weeks where any channel's ROAS dropped >10% WoW.
2. **Decompose** - attribute the ROAS change to CTR, CVR, CPC, or AOV shift.
3. **Drill down** - compare campaigns week-over-week to localize the drop.
4. **Validate hypotheses** - check if a CTR/CVR drop is concentrated in one category/channel.
5. **Recommend** - generate a budget-reallocation recommendation from channel ROAS efficiency.

## Python Track

```bash
pip install pandas numpy matplotlib seaborn plotly scipy
jupyter notebook
```

Run the notebooks in order (01 → 05); each reads the processed CSVs exported by the previous step from `data/processed/`. Update the hardcoded `BASE_DIR` path at the top of each notebook first.

### 01 - Data Cleaning
Loads the raw Olist CSVs, inspects shape/dtypes/nulls/duplicates, cleans and standardizes each table, joins them into a wide `master` order-level table, runs quick EDA on revenue and order volume, and exports cleaned CSVs to `data/processed/` (with an optional, commented-out PostgreSQL load step).

### 02 - Ad Data Simulation
Builds the Python track's own ad-campaign dataset - **forward-simulated** from channel-level industry benchmarks rather than backward from real sales: for each of 4 channels it defines impression/CTR/CVR/CPC ranges, generates daily campaign rows across 2017-01-01 to 2018-09-30, derives clicks from impressions × CTR, spend from clicks × CPC, attributed orders from clicks × CVR, and attributed revenue from orders × category AOV. Validated with channel summary stats and exported to `data/processed/ad_campaigns.csv`.

> This uses a different simulation approach than the SQL track's `generate_ad_data.py` and produces an independent dataset - the two tracks' numbers won't match exactly, by design.

### 03 - Funnel Analysis
Answers the same questions as the SQL funnel queries (overall funnel, by channel, by category, weekly trend, top/bottom campaigns) using matplotlib/seaborn and interactive Plotly visuals (funnel chart, grouped bars, weekly trend lines, spend-vs-revenue bubble chart).

### 04 - Root Cause Analysis
The same 5-step RCA framework as the SQL track (Detect → Decompose → Drill Down → Validate → Recommend), implemented in pandas: detects the worst weekly ROAS drop, decomposes it into CTR/CVR/CPC/AOV drivers, drills into the affected product category, validates against a 4-week rolling ROAS average, and quantifies the revenue impact of a 15% budget shift to the best-ROAS channel.

### 05 - A/B Test Analysis (Python-only)
Simulates user-level exposure/conversion data for a control and treatment ad creative, checks sample size/power for the target minimum detectable effect, runs a one-tailed two-proportion z-test, visualizes the results, estimates real-world revenue impact, and checks whether the effect holds across channels in a segmented analysis. Has no SQL counterpart.

## Notes

- Only orders with `order_status = 'delivered'` are included in revenue analysis (both tracks).
- Both simulations are seeded (`np.random.seed`) for reproducibility, but use different seeds/methods, so their outputs differ.
- Treat the SQL and Python results as two independent analyses of the same underlying business problem, not as a single pipeline - don't cross-reference numbers between them.
