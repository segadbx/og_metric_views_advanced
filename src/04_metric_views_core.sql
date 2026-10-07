-- Databricks notebook source
USE CATALOG IDENTIFIER(:catalog);
USE SCHEMA gl_reporting;

-- COMMAND ----------

-- ============================================================
-- MV1: Base Financial Rollup (mv_financial_rollup)
-- ============================================================
CREATE OR REPLACE VIEW gl_reporting.mv_financial_rollup
WITH METRICS LANGUAGE YAML AS
$$
version: 1.1
comment: >
  Base financial rollup.
  Supports drill-down across Line Format, Account, Cost Center, Project, and Vendor hierarchies.
  All measures computed on posted GL journal entries only.

source: gl_reporting.gl_journal_entries

# ── Global filter: only posted entries ──
filter: source.status = 'Posted'

# ── Star-schema joins to all 5 dimension tables ──
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

  - name: project
    source: gl_reporting.dim_projects
    'on': source.project_id = project.project_id
    rely:
      at_most_one_match: true

  - name: vendor
    source: gl_reporting.dim_vendors
    'on': source.vendor_id = vendor.vendor_id
    rely:
      at_most_one_match: true

  - name: line_format
    source: gl_reporting.dim_line_formats
    'on': source.line_format_id = line_format.line_format_id
    rely:
      at_most_one_match: true

# ══════════════════════════════════════════════════════════
#  FIELDS (Dimensions) — organized by hierarchy
# ══════════════════════════════════════════════════════════
fields:
  # ── Time Dimensions ──
  - name: Fiscal Year
    expr: source.fiscal_year
    comment: Fiscal year of the GL posting
    display_name: Fiscal Year
    synonyms:
      - year
      - FY

  - name: Fiscal Quarter
    expr: source.fiscal_quarter
    comment: Fiscal quarter (Q1-Q4)
    display_name: Fiscal Quarter
    synonyms:
      - quarter

  - name: Fiscal Period
    expr: source.fiscal_period
    comment: Fiscal period (month number 1-12)
    display_name: Fiscal Period
    synonyms:
      - month
      - period

  - name: Posting Month
    expr: DATE_TRUNC('MONTH', source.posting_date)
    comment: Month of GL posting (truncated date)
    display_name: Posting Month
    format:
      type: date
      date_format: locale_short_month

  # ── Line Format Hierarchy (2 levels) ──
  - name: Report Section
    expr: line_format.report_section
    comment: "Top-level financial report section (Operating Income, Operating Expenses, Capital & Investment)"
    display_name: Report Section
    synonyms:
      - report group
      - statement section

  - name: Line Format
    expr: line_format.line_format_name
    comment: "Financial line format (Revenue, OPEX-Direct, OPEX-Indirect, DD&A, G&A, CAPEX, Exploration)"
    display_name: Line Format
    synonyms:
      - line type
      - report line

  # ── Account Hierarchy (3 levels) ──
  - name: Account Group
    expr: account.account_group
    comment: "Top-level account classification (Revenue, Production Costs, Exploration, G&A, DD&A, CAPEX)"
    display_name: Account Group
    synonyms:
      - account type
      - GL group

  - name: Account Category
    expr: account.account_category
    comment: Mid-level account grouping (Well Services, Lease Operating, Geoscience, etc.)
    display_name: Account Category
    synonyms:
      - sub-group
      - account sub-type

  - name: Account Name
    expr: account.account_name
    comment: Leaf-level GL account name
    display_name: Account
    synonyms:
      - GL account
      - account

  - name: Account Code
    expr: source.account_id
    comment: GL account numeric code
    display_name: Account Code

  # ── Cost Center Hierarchy (3 levels) ──
  - name: Business Unit
    expr: cost_center.business_unit
    comment: "Top-level organizational unit (Upstream, Midstream, Corporate)"
    display_name: Business Unit
    synonyms:
      - BU
      - segment

  - name: Operating Region
    expr: cost_center.region
    comment: "Geographic operating region (Permian Basin, Eagle Ford, DJ Basin, Houston)"
    display_name: Operating Region
    synonyms:
      - region
      - basin
      - field

  - name: Cost Center
    expr: cost_center.cost_center_name
    comment: Leaf-level cost center
    display_name: Cost Center
    synonyms:
      - CC
      - department

  # ── Project Hierarchy (3 levels) ──
  - name: Project Type
    expr: COALESCE(project.project_type, 'Non-Project')
    comment: "Top-level project classification (Exploration, Development, Infrastructure, Corporate)"
    display_name: Project Type
    synonyms:
      - project category

  - name: Project Phase
    expr: COALESCE(project.project_phase, 'N/A')
    comment: Current project lifecycle phase
    display_name: Project Phase
    synonyms:
      - phase
      - project stage

  - name: Project Name
    expr: COALESCE(project.project_name, 'Non-Project Spend')
    comment: Specific project name
    display_name: Project
    synonyms:
      - project

  # ── Vendor Hierarchy (2 levels) ──
  - name: Vendor Category
    expr: COALESCE(vendor.vendor_category, 'Internal / No Vendor')
    comment: "Vendor classification (Oilfield Services, Drilling Contractors, etc.)"
    display_name: Vendor Category
    synonyms:
      - vendor type
      - supplier category

  - name: Vendor Name
    expr: COALESCE(vendor.vendor_name, 'Internal')
    comment: Vendor or supplier name
    display_name: Vendor
    synonyms:
      - supplier
      - vendor

  # ── Transaction Attributes ──
  - name: Journal Type
    expr: source.journal_type
    comment: "Journal entry type (AP, GL, FA, AR)"
    display_name: Journal Type
    synonyms:
      - entry type

  - name: Currency
    expr: source.currency
    comment: Transaction currency
    display_name: Currency

# ══════════════════════════════════════════════════════════
#  MEASURES — core financial aggregations
# ══════════════════════════════════════════════════════════
measures:
  - name: Actual Amount
    expr: SUM(source.amount)
    comment: Total actual spend or revenue
    display_name: Actual Amount
    format:
      type: currency
      currency_code: USD
      decimal_places:
        type: exact
        places: 0
      abbreviation: compact
    synonyms:
      - actual
      - spend
      - total amount

  - name: Budget Amount
    expr: SUM(source.budget_amount)
    comment: Total budgeted amount
    display_name: Budget Amount
    format:
      type: currency
      currency_code: USD
      decimal_places:
        type: exact
        places: 0
      abbreviation: compact
    synonyms:
      - budget
      - planned amount

  - name: Variance
    expr: SUM(source.budget_amount) - SUM(source.amount)
    comment: "Budget minus Actual (positive = under budget, negative = over budget)"
    display_name: Budget Variance
    format:
      type: currency
      currency_code: USD
      decimal_places:
        type: exact
        places: 0
      abbreviation: compact
    synonyms:
      - variance
      - budget variance

  - name: Variance Pct
    expr: (SUM(source.budget_amount) - SUM(source.amount)) / NULLIF(SUM(source.budget_amount), 0)
    comment: "Variance as a percentage of budget"
    display_name: Variance %
    format:
      type: percentage
      decimal_places:
        type: exact
        places: 1
    synonyms:
      - variance percent
      - budget deviation

  - name: Transaction Count
    expr: COUNT(1)
    comment: Number of GL journal entries
    display_name: Transaction Count
    format:
      type: number
      decimal_places:
        type: exact
        places: 0
    synonyms:
      - count
      - number of entries

  - name: Avg Transaction Size
    expr: SUM(source.amount) / NULLIF(COUNT(1), 0)
    comment: Average amount per journal entry
    display_name: Avg Transaction Size
    format:
      type: currency
      currency_code: USD
      decimal_places:
        type: exact
        places: 0
    synonyms:
      - average transaction
      - mean entry size
$$;

-- COMMAND ----------

-- ============================================================
-- MV2: Budget vs Actual Variance (mv_budget_variance)
-- ============================================================
CREATE OR REPLACE VIEW gl_reporting.mv_budget_variance
WITH METRICS LANGUAGE YAML AS
$$
version: 1.1
comment: >
  Budget vs Actual variance analysis with composable measures.
  Sources from the base financial rollup to inherit dimensions.
  Adds filtered and composed metrics for deep variance drill-down.

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
  - name: Fiscal Year
    expr: source.fiscal_year
    display_name: Fiscal Year

  - name: Fiscal Quarter
    expr: source.fiscal_quarter
    display_name: Fiscal Quarter

  - name: Posting Month
    expr: DATE_TRUNC('MONTH', source.posting_date)
    display_name: Posting Month
    format:
      type: date
      date_format: locale_short_month

  - name: Account Group
    expr: account.account_group
    display_name: Account Group

  - name: Account Category
    expr: account.account_category
    display_name: Account Category

  - name: Business Unit
    expr: cost_center.business_unit
    display_name: Business Unit

  - name: Operating Region
    expr: cost_center.region
    display_name: Operating Region

  - name: Report Section
    expr: line_format.report_section
    display_name: Report Section

  - name: Line Format
    expr: line_format.line_format_name
    display_name: Line Format

measures:
  # --- Core measures ---
  - name: Actual Amount
    expr: SUM(source.amount)
    display_name: Actual
    format:
      type: currency
      currency_code: USD
      decimal_places:
        type: exact
        places: 0
      abbreviation: compact

  - name: Budget Amount
    expr: SUM(source.budget_amount)
    display_name: Budget
    format:
      type: currency
      currency_code: USD
      decimal_places:
        type: exact
        places: 0
      abbreviation: compact

  # --- Composed variance measures ---
  - name: Variance
    expr: MEASURE(`Budget Amount`) - MEASURE(`Actual Amount`)
    comment: "Positive = under budget (favorable)"
    display_name: Variance ($)
    format:
      type: currency
      currency_code: USD
      decimal_places:
        type: exact
        places: 0

  - name: Variance Pct
    expr: MEASURE(Variance) / NULLIF(MEASURE(`Budget Amount`), 0)
    comment: Variance as percentage of budget
    display_name: Variance %
    format:
      type: percentage
      decimal_places:
        type: exact
        places: 1

  - name: Budget Utilization
    expr: MEASURE(`Actual Amount`) / NULLIF(MEASURE(`Budget Amount`), 0)
    comment: "How much of the budget has been consumed (>100% = over budget)"
    display_name: Budget Utilization %
    format:
      type: percentage
      decimal_places:
        type: exact
        places: 1
    synonyms:
      - burn rate
      - budget consumption

  # --- Filtered (conditional) measures — CAPEX vs OPEX breakdown ---
  - name: CAPEX Actual
    expr: SUM(source.amount) FILTER (WHERE source.line_format_id = 'LF-CAPEX')
    comment: Capital expenditure actuals only
    display_name: CAPEX Spend
    format:
      type: currency
      currency_code: USD
      decimal_places:
        type: exact
        places: 0
      abbreviation: compact
    synonyms:
      - capital expenditure
      - capex

  - name: OPEX Actual
    expr: SUM(source.amount) FILTER (WHERE source.line_format_id IN ('LF-OPEX-D', 'LF-OPEX-I'))
    comment: Operating expenditure actuals only (Direct + Indirect)
    display_name: OPEX Spend
    format:
      type: currency
      currency_code: USD
      decimal_places:
        type: exact
        places: 0
      abbreviation: compact
    synonyms:
      - operating expense
      - opex

  - name: CAPEX Budget
    expr: SUM(source.budget_amount) FILTER (WHERE source.line_format_id = 'LF-CAPEX')
    display_name: CAPEX Budget
    format:
      type: currency
      currency_code: USD
      decimal_places:
        type: exact
        places: 0
      abbreviation: compact

  - name: OPEX Budget
    expr: SUM(source.budget_amount) FILTER (WHERE source.line_format_id IN ('LF-OPEX-D', 'LF-OPEX-I'))
    display_name: OPEX Budget
    format:
      type: currency
      currency_code: USD
      decimal_places:
        type: exact
        places: 0
      abbreviation: compact

  - name: CAPEX Variance Pct
    expr: (MEASURE(`CAPEX Budget`) - MEASURE(`CAPEX Actual`)) / NULLIF(MEASURE(`CAPEX Budget`), 0)
    comment: CAPEX-specific variance percentage
    display_name: CAPEX Variance %
    format:
      type: percentage
      decimal_places:
        type: exact
        places: 1

  - name: OPEX Variance Pct
    expr: (MEASURE(`OPEX Budget`) - MEASURE(`OPEX Actual`)) / NULLIF(MEASURE(`OPEX Budget`), 0)
    comment: OPEX-specific variance percentage
    display_name: OPEX Variance %
    format:
      type: percentage
      decimal_places:
        type: exact
        places: 1
$$;

-- COMMAND ----------

-- ============================================================
-- MV3: Period-over-Period Trends (mv_spending_trends)
-- ============================================================
CREATE OR REPLACE VIEW gl_reporting.mv_spending_trends
WITH METRICS LANGUAGE YAML AS
$$
version: 1.1
comment: >
  Time-series spending analysis with window measures.
  Supports cumulative YTD, MoM comparison, and rolling averages
  across all financial dimension hierarchies.

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

  - name: Account Group
    expr: account.account_group
    display_name: Account Group

  - name: Business Unit
    expr: cost_center.business_unit
    display_name: Business Unit

  - name: Operating Region
    expr: cost_center.region
    display_name: Operating Region

  - name: Report Section
    expr: line_format.report_section
    display_name: Report Section

  - name: Line Format
    expr: line_format.line_format_name
    display_name: Line Format

measures:
  # --- Base measure ---
  - name: Monthly Spend
    expr: SUM(source.amount)
    comment: Total actual spend in a given month
    display_name: Monthly Spend
    format:
      type: currency
      currency_code: USD
      decimal_places:
        type: exact
        places: 0
      abbreviation: compact

  # --- Window: Cumulative year-to-date ---
  - name: Cumulative YTD Spend
    expr: SUM(source.amount)
    comment: Running total of spend from the beginning of the dataset through each month
    display_name: Cumulative YTD Spend
    format:
      type: currency
      currency_code: USD
      decimal_places:
        type: exact
        places: 0
      abbreviation: compact
    synonyms:
      - YTD spend
      - running total
    window:
      - order: Posting Month
        range: cumulative
        semiadditive: last

  # --- Window: Prior month spend (for MoM comparison) ---
  - name: Prior Month Spend
    expr: SUM(source.amount)
    comment: Spend from the immediately preceding month
    display_name: Prior Month Spend
    format:
      type: currency
      currency_code: USD
      decimal_places:
        type: exact
        places: 0
      abbreviation: compact
    window:
      - order: Posting Month
        range: trailing 1 month
        semiadditive: last

  # --- Composed: Month-over-Month growth % ---
  - name: MoM Growth Pct
    expr: >
      (MEASURE(`Monthly Spend`) - MEASURE(`Prior Month Spend`))
      / NULLIF(MEASURE(`Prior Month Spend`), 0)
    comment: Month-over-month change as a percentage
    display_name: MoM Growth %
    format:
      type: percentage
      decimal_places:
        type: exact
        places: 1
    synonyms:
      - month over month
      - MoM change

  # --- Window: Rolling 3-month average ---
  - name: Rolling 3M Avg Spend
    expr: AVG(source.amount)
    comment: 3-month trailing moving average of spend
    display_name: Rolling 3-Month Average
    format:
      type: currency
      currency_code: USD
      decimal_places:
        type: exact
        places: 0
      abbreviation: compact
    synonyms:
      - moving average
      - 3 month average
    window:
      - order: Posting Month
        range: trailing 3 month
        semiadditive: last
$$;

-- COMMAND ----------

-- ============================================================
-- MV4: Filtered Conditional Metrics (mv_conditional_metrics)
-- ============================================================
CREATE OR REPLACE VIEW gl_reporting.mv_conditional_metrics
WITH METRICS LANGUAGE YAML AS
$$
version: 1.1
comment: >
  Conditional financial metrics using FILTER clauses.
  Revenue/expense splits, journal-type filters, and income statement composability.

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
  - name: Fiscal Year
    expr: source.fiscal_year
    display_name: Fiscal Year

  - name: Fiscal Quarter
    expr: source.fiscal_quarter
    display_name: Fiscal Quarter

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

  - name: Line Format
    expr: line_format.line_format_name
    display_name: Line Format

measures:
  # --- Revenue measures ---
  - name: Total Revenue
    expr: SUM(source.amount) FILTER (WHERE source.account_id LIKE '4%')
    comment: All revenue accounts (4xxx)
    display_name: Total Revenue
    format:
      type: currency
      currency_code: USD
      decimal_places:
        type: exact
        places: 0
      abbreviation: compact
    synonyms:
      - revenue
      - top line

  - name: Oil Revenue
    expr: SUM(source.amount) FILTER (WHERE source.account_id = '4100')
    comment: Crude oil sales only
    display_name: Oil Revenue
    format:
      type: currency
      currency_code: USD
      decimal_places:
        type: exact
        places: 0
      abbreviation: compact

  - name: Gas Revenue
    expr: SUM(source.amount) FILTER (WHERE source.account_id = '4200')
    comment: Natural gas sales only
    display_name: Gas Revenue
    format:
      type: currency
      currency_code: USD
      decimal_places:
        type: exact
        places: 0
      abbreviation: compact

  # --- Expense measures ---
  - name: Total Operating Expense
    expr: SUM(source.amount) FILTER (WHERE source.account_id LIKE '5%')
    comment: Production costs (5xxx accounts)
    display_name: Total OPEX
    format:
      type: currency
      currency_code: USD
      decimal_places:
        type: exact
        places: 0
      abbreviation: compact

  - name: Total G&A
    expr: SUM(source.amount) FILTER (WHERE source.account_id LIKE '7%')
    comment: General & Administrative (7xxx accounts)
    display_name: Total G&A
    format:
      type: currency
      currency_code: USD
      decimal_places:
        type: exact
        places: 0
      abbreviation: compact

  - name: Total DD&A
    expr: SUM(source.amount) FILTER (WHERE source.account_id LIKE '8%')
    comment: "Depreciation, Depletion & Amortization (8xxx accounts)"
    display_name: Total DD&A
    format:
      type: currency
      currency_code: USD
      decimal_places:
        type: exact
        places: 0
      abbreviation: compact

  - name: Exploration Expense
    expr: SUM(source.amount) FILTER (WHERE source.account_id LIKE '6%')
    comment: Exploration costs (6xxx accounts)
    display_name: Exploration Expense
    format:
      type: currency
      currency_code: USD
      decimal_places:
        type: exact
        places: 0
      abbreviation: compact

  # --- Journal-type filters ---
  - name: AP Spend
    expr: SUM(source.amount) FILTER (WHERE source.journal_type = 'AP')
    comment: Accounts Payable journal entries only
    display_name: AP Spend
    format:
      type: currency
      currency_code: USD
      decimal_places:
        type: exact
        places: 0
      abbreviation: compact
    synonyms:
      - accounts payable
      - vendor payments

  # --- Threshold filter ---
  - name: High Value Transaction Total
    expr: SUM(source.amount) FILTER (WHERE source.amount >= 500000)
    comment: Sum of all journal entries >= $500K
    display_name: High-Value Txn Total
    format:
      type: currency
      currency_code: USD
      decimal_places:
        type: exact
        places: 0
      abbreviation: compact

  - name: High Value Transaction Count
    expr: COUNT(1) FILTER (WHERE source.amount >= 500000)
    comment: Count of journal entries >= $500K
    display_name: High-Value Txn Count
    format:
      type: number
      decimal_places:
        type: exact
        places: 0

  # --- Composed income statement measures ---
  - name: Net Operating Income
    expr: MEASURE(`Total Revenue`) - MEASURE(`Total Operating Expense`) - MEASURE(`Total G&A`)
    comment: Revenue minus operating expenses and G&A
    display_name: Net Operating Income
    format:
      type: currency
      currency_code: USD
      decimal_places:
        type: exact
        places: 0
      abbreviation: compact
    synonyms:
      - NOI
      - operating income

  - name: EBITDA Proxy
    expr: MEASURE(`Total Revenue`) - MEASURE(`Total Operating Expense`) - MEASURE(`Total G&A`)
    comment: "EBITDA approximation (Revenue - OPEX - G&A, excludes DD&A)"
    display_name: EBITDA (Proxy)
    format:
      type: currency
      currency_code: USD
      decimal_places:
        type: exact
        places: 0
      abbreviation: compact
    synonyms:
      - EBITDA
      - earnings before interest taxes depreciation amortization
$$;

-- COMMAND ----------

-- ============================================================
-- MV5: Parameterized Fiscal Period (mv_fiscal_period_analysis)
-- ============================================================
CREATE OR REPLACE VIEW gl_reporting.mv_fiscal_period_analysis
WITH METRICS LANGUAGE YAML AS
$$
version: 1.1
comment: >
  Parameterized fiscal period analysis.
  Call as a table-valued function: mv_fiscal_period_analysis(fiscal_year_param => 2025).
  Supports drill-down across all dimension hierarchies within the selected fiscal period.

source: gl_reporting.gl_journal_entries

parameters:
  - name: fiscal_year_param
    data_type: INT
    comment: "The fiscal year to analyze (e.g. 2025 or 2026)"
  - name: quarter_param
    data_type: STRING
    default: "'ALL'"
    comment: "Fiscal quarter filter (Q1, Q2, Q3, Q4, or ALL for full year)"

filter: >
  source.status = 'Posted'
  AND source.fiscal_year = fiscal_year_param
  AND (quarter_param = 'ALL' OR source.fiscal_quarter = quarter_param)

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
  - name: project
    source: gl_reporting.dim_projects
    'on': source.project_id = project.project_id
    rely:
      at_most_one_match: true
  - name: vendor
    source: gl_reporting.dim_vendors
    'on': source.vendor_id = vendor.vendor_id
    rely:
      at_most_one_match: true
  - name: line_format
    source: gl_reporting.dim_line_formats
    'on': source.line_format_id = line_format.line_format_id
    rely:
      at_most_one_match: true

fields:
  - name: Fiscal Quarter
    expr: source.fiscal_quarter
    display_name: Fiscal Quarter

  - name: Fiscal Period
    expr: source.fiscal_period
    display_name: Period (Month)

  - name: Report Section
    expr: line_format.report_section
    display_name: Report Section

  - name: Line Format
    expr: line_format.line_format_name
    display_name: Line Format

  - name: Account Group
    expr: account.account_group
    display_name: Account Group

  - name: Account Category
    expr: account.account_category
    display_name: Account Category

  - name: Account Name
    expr: account.account_name
    display_name: Account

  - name: Business Unit
    expr: cost_center.business_unit
    display_name: Business Unit

  - name: Operating Region
    expr: cost_center.region
    display_name: Operating Region

  - name: Cost Center
    expr: cost_center.cost_center_name
    display_name: Cost Center

  - name: Project Type
    expr: COALESCE(project.project_type, 'Non-Project')
    display_name: Project Type

  - name: Project Name
    expr: COALESCE(project.project_name, 'Non-Project Spend')
    display_name: Project

  - name: Vendor Category
    expr: COALESCE(vendor.vendor_category, 'Internal / No Vendor')
    display_name: Vendor Category

  - name: Vendor Name
    expr: COALESCE(vendor.vendor_name, 'Internal')
    display_name: Vendor

measures:
  - name: Actual Amount
    expr: SUM(source.amount)
    display_name: Actual
    format:
      type: currency
      currency_code: USD
      decimal_places:
        type: exact
        places: 0
      abbreviation: compact

  - name: Budget Amount
    expr: SUM(source.budget_amount)
    display_name: Budget
    format:
      type: currency
      currency_code: USD
      decimal_places:
        type: exact
        places: 0
      abbreviation: compact

  - name: Variance
    expr: MEASURE(`Budget Amount`) - MEASURE(`Actual Amount`)
    display_name: Variance
    format:
      type: currency
      currency_code: USD
      decimal_places:
        type: exact
        places: 0

  - name: Variance Pct
    expr: MEASURE(Variance) / NULLIF(MEASURE(`Budget Amount`), 0)
    display_name: Variance %
    format:
      type: percentage
      decimal_places:
        type: exact
        places: 1

  - name: Transaction Count
    expr: COUNT(1)
    display_name: Entries
    format:
      type: number
      decimal_places:
        type: exact
        places: 0
$$;

-- COMMAND ----------

-- ============================================================
-- MV6: Materialized Rollup (mv_materialized_rollup)
-- ============================================================
-- NOTE: Materialization requires specific permissions and compute.
-- Materialization is declared via the `materialization:` block in the YAML.
-- If you lack permissions, the base CREATE VIEW (without materialization) still works.

CREATE OR REPLACE VIEW gl_reporting.mv_materialized_rollup
WITH METRICS LANGUAGE YAML AS
$$
version: 1.1
comment: >
  Materialized financial rollup for dashboard performance.
  Pre-aggregates monthly actuals/budget by key dimensions.
  Auto-refreshes every 6 hours.

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

  - name: Account Group
    expr: account.account_group
    display_name: Account Group

  - name: Business Unit
    expr: cost_center.business_unit
    display_name: Business Unit

  - name: Operating Region
    expr: cost_center.region
    display_name: Operating Region

  - name: Report Section
    expr: line_format.report_section
    display_name: Report Section

  - name: Line Format
    expr: line_format.line_format_name
    display_name: Line Format

measures:
  - name: Actual Amount
    expr: SUM(source.amount)
    display_name: Actual
    format:
      type: currency
      currency_code: USD
      decimal_places:
        type: exact
        places: 0
      abbreviation: compact

  - name: Budget Amount
    expr: SUM(source.budget_amount)
    display_name: Budget
    format:
      type: currency
      currency_code: USD
      decimal_places:
        type: exact
        places: 0
      abbreviation: compact

  - name: Transaction Count
    expr: COUNT(1)
    display_name: Transaction Count
    format:
      type: number
      decimal_places:
        type: exact
        places: 0

materialization:
  schedule: every 6 hours
  mode: relaxed
  materialized_views:
    - name: baseline_fact
      type: unaggregated

    - name: monthly_rollup
      type: aggregated
      dimensions:
        - Posting Month
        - Fiscal Year
        - Account Group
        - Business Unit
        - Report Section
        - Line Format
      measures:
        - Actual Amount
        - Budget Amount
        - Transaction Count
      cluster_by:
        cols:
          - Posting Month
          - Account Group
$$;