-- Databricks notebook source
USE CATALOG IDENTIFIER(:catalog);
USE SCHEMA gl_reporting;

-- COMMAND ----------

-- ============================================================
-- MV7: Year-over-Year Analysis (mv_yoy_analysis)
-- ============================================================
CREATE OR REPLACE VIEW gl_reporting.mv_yoy_analysis
WITH METRICS LANGUAGE YAML AS
$$
version: 1.1
comment: >
  Year-over-Year financial analysis using window offset.
  Compares each month to the same month in the prior year.
  Demonstrates: offset, same-position-prior-cycle (two window specs),
  range: current, and composed YoY growth measures.

source: gl_reporting.gl_journal_entries

filter: source.status = 'Posted'

joins:
  - name: account
    source: gl_reporting.dim_accounts
    'on': source.account_id = account.account_id
    rely:
      at_most_one_match: true
  - name: cost_center
    source: gl_reporting.dim_cost_centers
    'on': source.cost_center_id = cost_center.cost_center_id
    rely:
      at_most_one_match: true
  - name: line_format
    source: gl_reporting.dim_line_formats
    'on': source.line_format_id = line_format.line_format_id
    rely:
      at_most_one_match: true

fields:
  - name: Posting Month
    expr: DATE_TRUNC('MONTH', source.posting_date)
    display_name: Posting Month
    format:
      type: date
      date_format: locale_short_month

  - name: Fiscal Year
    expr: source.fiscal_year
    display_name: Fiscal Year

  - name: Fiscal Period
    expr: source.fiscal_period
    display_name: Fiscal Period
    comment: "Month number 1-12, used for same-position-prior-cycle alignment"

  - name: Account Group
    expr: account.account_group
    display_name: Account Group

  - name: Business Unit
    expr: cost_center.business_unit
    display_name: Business Unit

  - name: Report Section
    expr: line_format.report_section
    display_name: Report Section

  - name: Line Format
    expr: line_format.line_format_name
    display_name: Line Format

measures:
  # --- Current month spend (explicit range: current) ---
  - name: Current Month Spend
    expr: SUM(source.amount)
    comment: "Spend for the current month (range: current = single-point window)"
    display_name: Current Month Spend
    format:
      type: currency
      currency_code: USD
      decimal_places:
        type: exact
        places: 0
      abbreviation: compact
    window:
      - order: Posting Month
        range: current
        semiadditive: last

  # --- TECHNIQUE: offset: -12 month (date-based YoY) ---
  - name: Prior Year Month Spend
    expr: SUM(source.amount)
    comment: "Same month 12 months ago via offset: -12 month. For Jan 2026, returns Jan 2025 spend."
    display_name: Prior Year Month Spend
    format:
      type: currency
      currency_code: USD
      decimal_places:
        type: exact
        places: 0
      abbreviation: compact
    synonyms:
      - last year
      - prior year
    window:
      - order: Posting Month
        range: current
        offset: -12 month
        semiadditive: last

  # --- Composed: YoY Delta (absolute change) ---
  - name: YoY Delta
    expr: MEASURE(`Current Month Spend`) - MEASURE(`Prior Year Month Spend`)
    comment: "Absolute change vs same month prior year (positive = increase)"
    display_name: YoY Change ($)
    format:
      type: currency
      currency_code: USD
      decimal_places:
        type: exact
        places: 0
    synonyms:
      - year over year change
      - YoY difference

  # --- Composed: YoY Growth % ---
  - name: YoY Growth Pct
    expr: >
      (MEASURE(`Current Month Spend`) - MEASURE(`Prior Year Month Spend`))
      / NULLIF(MEASURE(`Prior Year Month Spend`), 0)
    comment: "Percentage change vs same month prior year"
    display_name: YoY Growth %
    format:
      type: percentage
      decimal_places:
        type: exact
        places: 1
    synonyms:
      - year over year growth
      - YoY percent change

  # --- TECHNIQUE: Same-position-prior-cycle (two window specs) ---
  # This pattern uses Fiscal Year + Fiscal Period instead of a date offset,
  # aligning by position (same period number) across fiscal years.
  - name: Same Period Prior FY Spend
    expr: SUM(source.amount)
    comment: >
      Same fiscal period in the prior fiscal year using two window specs:
      offset: -1 on Fiscal Year shifts to the prior year,
      range: current on Fiscal Period holds the month position fixed.
    display_name: Same Period Prior FY
    format:
      type: currency
      currency_code: USD
      decimal_places:
        type: exact
        places: 0
      abbreviation: compact
    window:
      - order: Fiscal Year
        range: current
        offset: -1
        semiadditive: last
      - order: Fiscal Period
        range: current
        semiadditive: last

  # --- Revenue-specific YoY (filtered + offset combined) ---
  - name: Revenue Current
    expr: SUM(source.amount) FILTER (WHERE source.account_id LIKE '4%')
    comment: Current month revenue only
    display_name: Revenue (Current)
    format:
      type: currency
      currency_code: USD
      decimal_places:
        type: exact
        places: 0
      abbreviation: compact
    window:
      - order: Posting Month
        range: current
        semiadditive: last

  - name: Revenue Prior Year
    expr: SUM(source.amount) FILTER (WHERE source.account_id LIKE '4%')
    comment: Same month prior year revenue
    display_name: Revenue (Prior Year)
    format:
      type: currency
      currency_code: USD
      decimal_places:
        type: exact
        places: 0
      abbreviation: compact
    window:
      - order: Posting Month
        range: current
        offset: -12 month
        semiadditive: last

  - name: Revenue YoY Growth Pct
    expr: >
      (MEASURE(`Revenue Current`) - MEASURE(`Revenue Prior Year`))
      / NULLIF(MEASURE(`Revenue Prior Year`), 0)
    comment: Revenue-specific YoY growth percentage
    display_name: Revenue YoY Growth %
    format:
      type: percentage
      decimal_places:
        type: exact
        places: 1
$$;

-- COMMAND ----------

-- ============================================================
-- MV8: Cross-Metric-View Composability (mv_executive_kpis)
-- ============================================================
CREATE OR REPLACE VIEW gl_reporting.mv_executive_kpis
WITH METRICS LANGUAGE YAML AS
$$
version: 1.1
comment: >
  Executive KPI layer sourced from the base financial rollup metric view.
  Demonstrates cross-metric-view composability using wildcard projections (source.*)
  to inherit all dimensions and measures from the upstream metric view, then adding
  new derived KPIs on top. This is the recommended pattern for layering metric views.

# ── TECHNIQUE: metric view as source (cross-MV composability) ──
source: gl_reporting.mv_financial_rollup

fields:
  # ── TECHNIQUE: wildcard projection from upstream metric view ──
  # Inherits ALL 13 dimensions from mv_financial_rollup automatically.
  # When the source is a metric view, prefer source.* to inherit definitions + metadata.
  - expr: source.*

  # --- New derived field combining inherited dimensions ---
  - name: BU Region
    expr: "CONCAT(`Business Unit`, ' - ', `Operating Region`)"
    comment: "Concatenated business unit and region label for compact reporting"
    display_name: BU / Region

measures:
  # ── TECHNIQUE: wildcard measure projection from upstream metric view ──
  # Inherits ALL 6 measures (Actual Amount, Budget Amount, Variance, Variance %,
  # Transaction Count, Avg Transaction Size) with their formatting metadata.
  - expr: source.*

  # --- New composed measures built on inherited measures ---
  - name: Revenue Share
    expr: >
      MEASURE(`Actual Amount`) FILTER (WHERE `Report Section` = 'Operating Income')
      / NULLIF(MEASURE(`Actual Amount`), 0)
    comment: "Revenue as a share of total financial activity"
    display_name: Revenue Share %
    format:
      type: percentage
      decimal_places:
        type: exact
        places: 1
    synonyms:
      - revenue percentage
      - top line share

  - name: OPEX to Revenue Ratio
    expr: >
      MEASURE(`Actual Amount`) FILTER (WHERE `Report Section` = 'Operating Expenses')
      / NULLIF(MEASURE(`Actual Amount`) FILTER (WHERE `Report Section` = 'Operating Income'), 0)
    comment: "Operating expenses as a ratio of revenue (lower is more efficient)"
    display_name: OPEX/Revenue Ratio
    format:
      type: percentage
      decimal_places:
        type: exact
        places: 1
    synonyms:
      - cost ratio
      - operating cost efficiency

  - name: CAPEX Intensity
    expr: >
      MEASURE(`Actual Amount`) FILTER (WHERE `Account Group` = 'Capital Expenditures')
      / NULLIF(MEASURE(`Actual Amount`) FILTER (WHERE `Report Section` = 'Operating Income'), 0)
    comment: "Capital spending as a percentage of revenue (key E&P metric)"
    display_name: CAPEX Intensity %
    format:
      type: percentage
      decimal_places:
        type: exact
        places: 1
    synonyms:
      - capital intensity
      - capex to revenue

  - name: Operating Margin
    expr: >
      (MEASURE(`Actual Amount`) FILTER (WHERE `Report Section` = 'Operating Income')
       - MEASURE(`Actual Amount`) FILTER (WHERE `Report Section` = 'Operating Expenses'))
      / NULLIF(MEASURE(`Actual Amount`) FILTER (WHERE `Report Section` = 'Operating Income'), 0)
    comment: "Operating margin = (Revenue - OPEX) / Revenue"
    display_name: Operating Margin %
    format:
      type: percentage
      decimal_places:
        type: exact
        places: 1
    synonyms:
      - margin
      - profitability
$$;

-- COMMAND ----------

-- ============================================================
-- MV9: Index-Based Period Comparison (mv_index_based_trends)
-- ============================================================
CREATE OR REPLACE VIEW gl_reporting.mv_index_based_trends
WITH METRICS LANGUAGE YAML AS
$$
version: 1.1
comment: >
  Index-based period comparison using a consecutive monotonic integer index.
  Demonstrates: numeric offset, unitless range, range:all for breakdown columns,
  and composed MoM measures from index-shifted windows.

source: gl_reporting.gl_journal_entries

filter: source.status = 'Posted'

joins:
  - name: account
    source: gl_reporting.dim_accounts
    'on': source.account_id = account.account_id
    rely:
      at_most_one_match: true
  - name: cost_center
    source: gl_reporting.dim_cost_centers
    'on': source.cost_center_id = cost_center.cost_center_id
    rely:
      at_most_one_match: true

fields:
  # --- Breakdown columns (need range: all on their window specs) ---
  - name: Fiscal Year
    expr: source.fiscal_year
    display_name: Fiscal Year
    comment: INT breakdown column

  - name: Fiscal Period
    expr: source.fiscal_period
    display_name: Fiscal Period
    comment: INT breakdown column (month 1-12)

  # --- TECHNIQUE: Consecutive monotonic index ---
  - name: Month Index
    expr: source.fiscal_year * 12 + source.fiscal_period
    display_name: Month Index
    comment: >
      Consecutive monotonic INT index: increases by exactly 1 each month,
      crosses year boundary correctly (Dec 2025 = 24312, Jan 2026 = 24313).
      Required properties: integral, monotonic, consecutive (dense).

  - name: Account Group
    expr: account.account_group
    display_name: Account Group

  - name: Business Unit
    expr: cost_center.business_unit
    display_name: Business Unit

  - name: Operating Region
    expr: cost_center.region
    display_name: Operating Region

measures:
  # --- Current month spend using the index ---
  # range: all on breakdown columns keeps GROUP BY working
  - name: Monthly Spend
    expr: SUM(source.amount)
    comment: >
      Current month spend. The index orders on Month Index with range: current.
      Fiscal Year and Fiscal Period get range: all so grouping by them works.
    display_name: Monthly Spend
    format:
      type: currency
      currency_code: USD
      decimal_places:
        type: exact
        places: 0
      abbreviation: compact
    window:
      - order: Fiscal Year
        range: all
        semiadditive: last
      - order: Fiscal Period
        range: all
        semiadditive: last
      - order: Month Index
        range: current
        semiadditive: last

  # --- TECHNIQUE: unitless numeric offset: -1 (previous month via index) ---
  - name: Prior Month Spend
    expr: SUM(source.amount)
    comment: >
      Previous month spend via offset: -1 on the index.
      Crosses year boundary correctly because index is consecutive.
    display_name: Prior Month Spend
    format:
      type: currency
      currency_code: USD
      decimal_places:
        type: exact
        places: 0
      abbreviation: compact
    window:
      - order: Fiscal Year
        range: all
        semiadditive: last
      - order: Fiscal Period
        range: all
        semiadditive: last
      - order: Month Index
        range: current
        offset: -1
        semiadditive: last

  # --- TECHNIQUE: unitless trailing 3 (rolling 3 months via index) ---
  - name: Trailing 3M Spend
    expr: SUM(source.amount)
    comment: >
      Sum of the 3 index positions before the current month (exclusive).
      Because the index is consecutive, 3 positions = 3 calendar months.
      Add 'inclusive' to include the current month instead.
    display_name: Trailing 3-Month Spend
    format:
      type: currency
      currency_code: USD
      decimal_places:
        type: exact
        places: 0
      abbreviation: compact
    window:
      - order: Fiscal Year
        range: all
        semiadditive: last
      - order: Fiscal Period
        range: all
        semiadditive: last
      - order: Month Index
        range: trailing 3
        semiadditive: last

  # --- Composed: MoM % change from index-based measures ---
  - name: MoM Pct Change
    expr: >
      (MEASURE(`Monthly Spend`) - MEASURE(`Prior Month Spend`))
      / NULLIF(MEASURE(`Prior Month Spend`), 0) * 100
    comment: "Month-over-month percentage change using index-based window measures"
    display_name: MoM % Change
    format:
      type: number
      decimal_places:
        type: exact
        places: 1
    synonyms:
      - month over month change
      - MoM growth

  # --- Composed: Trailing 3M average from index-based trailing sum ---
  - name: Trailing 3M Avg Spend
    expr: MEASURE(`Trailing 3M Spend`) / 3
    comment: "Simple average of trailing 3-month spend"
    display_name: Trailing 3M Average
    format:
      type: currency
      currency_code: USD
      decimal_places:
        type: exact
        places: 0
      abbreviation: compact
$$;

-- COMMAND ----------

-- ============================================================
-- MV10: Parameterized Rolling Window (mv_dynamic_rolling)
-- ============================================================
CREATE OR REPLACE VIEW gl_reporting.mv_dynamic_rolling
WITH METRICS LANGUAGE YAML AS
$$
version: 1.1
comment: >
  Parameterized rolling window analysis.
  Caller passes the window size at query time.
  Demonstrates: range with parameter reference, dynamic rolling aggregation.

source: gl_reporting.gl_journal_entries

filter: source.status = 'Posted'

# --- TECHNIQUE: parameter as window size ---
parameters:
  - name: window_days
    data_type: INT
    default: 30
    comment: "Number of trailing days for the rolling window (e.g. 7, 30, 90)"

joins:
  - name: account
    source: gl_reporting.dim_accounts
    'on': source.account_id = account.account_id
    rely:
      at_most_one_match: true
  - name: cost_center
    source: gl_reporting.dim_cost_centers
    'on': source.cost_center_id = cost_center.cost_center_id
    rely:
      at_most_one_match: true

fields:
  - name: Posting Date
    expr: source.posting_date
    display_name: Posting Date
    format:
      type: date
      date_format: year_month_day

  - name: Posting Month
    expr: DATE_TRUNC('MONTH', source.posting_date)
    display_name: Posting Month
    format:
      type: date
      date_format: locale_short_month

  - name: Account Group
    expr: account.account_group
    display_name: Account Group

  - name: Business Unit
    expr: cost_center.business_unit
    display_name: Business Unit

  - name: Operating Region
    expr: cost_center.region
    display_name: Operating Region

measures:
  # --- Daily spend (base) ---
  - name: Daily Spend
    expr: SUM(source.amount)
    comment: Total spend on a given day
    display_name: Daily Spend
    format:
      type: currency
      currency_code: USD
      decimal_places:
        type: exact
        places: 0

  # --- TECHNIQUE: trailing range with parameterized magnitude ---
  - name: Rolling Spend
    expr: SUM(source.amount)
    comment: >
      Rolling sum of spend over the trailing N days.
      The window size comes from the window_days parameter.
      Call with window_days => 7 for weekly, 30 for monthly, 90 for quarterly.
    display_name: Rolling Spend
    format:
      type: currency
      currency_code: USD
      decimal_places:
        type: exact
        places: 0
      abbreviation: compact
    synonyms:
      - rolling total
      - trailing spend
    window:
      - order: Posting Date
        range: trailing window_days day
        semiadditive: last

  # --- Rolling distinct vendor count (parameterized) ---
  - name: Rolling Active Vendors
    expr: COUNT(DISTINCT source.vendor_id)
    comment: >
      Count of distinct vendors with GL entries in the trailing N days.
      Useful for monitoring vendor concentration.
    display_name: Rolling Active Vendors
    format:
      type: number
      decimal_places:
        type: exact
        places: 0
    synonyms:
      - active suppliers
      - vendor count
    window:
      - order: Posting Date
        range: trailing window_days day
        semiadditive: last

  # --- Rolling transaction count (parameterized) ---
  - name: Rolling Transaction Count
    expr: COUNT(1)
    comment: "Number of GL entries in the trailing N-day window"
    display_name: Rolling Txn Count
    format:
      type: number
      decimal_places:
        type: exact
        places: 0
    window:
      - order: Posting Date
        range: trailing window_days day
        semiadditive: last

  # --- Composed: Rolling average transaction size ---
  - name: Rolling Avg Txn Size
    expr: MEASURE(`Rolling Spend`) / NULLIF(MEASURE(`Rolling Transaction Count`), 0)
    comment: "Average transaction size over the rolling window"
    display_name: Rolling Avg Txn Size
    format:
      type: currency
      currency_code: USD
      decimal_places:
        type: exact
        places: 0
$$;