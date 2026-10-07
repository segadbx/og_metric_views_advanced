# Finance GL Metric Views — Declarative Automation Bundle

## Overview

This DAB deploys a complete **Oil & Gas General Ledger semantic layer** built on
Unity Catalog Metric Views. It demonstrates the full spectrum of metric view
capabilities for financial reporting and analysis.

## Questions the Metric Views Cover
1. Actual spend by Business Unit (MV1, basic grouping)
2. Multi-dimension drill-down: BU → Region → Cost Center (MV1)
3. Over-budget areas where Budget Utilization > 100% (MV2)
4. Net Operating Income and EBITDA by quarter (MV4)
5. Month-over-month spending trend (MV3)
6. Cumulative YTD spend + rolling 3-month average (MV3)
7. Parameterized fiscal year analysis via TVF (MV5)
8. Year-over-year spend comparison by month (MV7)
9. Operating margin and CAPEX intensity by BU (MV8)
10. 90-day rolling spend with parameterized window (MV10)
11. Index-based MoM change crossing the year boundary (MV9)


## Included Assets

| Asset Type | Count | Details |
|---|---|---|
| Dimension Tables | 5 | dim_accounts, dim_cost_centers, dim_projects, dim_vendors, dim_line_formats |
| Fact Table | 1 | gl_journal_entries (1,912 rows, 24 months Jan 2025–Dec 2026) |
| Metric Views (Core) | 6 | mv_financial_rollup, mv_budget_variance, mv_spending_trends, mv_conditional_metrics, mv_fiscal_period_analysis, mv_materialized_rollup |
| Metric Views (Advanced) | 4 | mv_yoy_analysis, mv_executive_kpis, mv_index_based_trends, mv_dynamic_rolling |
| Dashboard | 1 | Finance Drill-Down Explorer (5 pages) |

## Project Structure

```
og_metric_views_advanced/
├── databricks.yml              # Bundle configuration
├── README.md                   # This file
└── src/
    ├── 01_setup.sql            # Catalog & schema setup
    ├── 02_dimensions.sql       # 5 dimension tables
    ├── 03_generate_journal_entries.py  # Synthetic data generator
    ├── 04_metric_views_core.sql       # MV1–MV6
    ├── 05_metric_views_advanced.sql   # MV7–MV10
    └── dashboard.lvdash.json   # Lakeview dashboard definition
```

**Catalog:** Configurable via `catalog` variable | **Schema:** `gl_reporting` (auto-created)

## Deployment

### Prerequisites

- Databricks CLI v1.0.0 or higher
- Access to an existing Unity Catalog
- A SQL Warehouse for dashboard queries
- Proper authentication configured (`databricks auth login`)

### Required Variables

| Variable | Required | Description | Example |
|----------|----------|-------------|---------|
| `catalog` | ✅ Yes | Catalog name where schema will be created | `my_catalog` |
| `warehouse_id` | ✅ Yes | SQL Warehouse ID for dashboard | `abc123xyz` |

### Deploy Steps

```bash
# Validate the bundle
databricks bundle validate -t dev \
  --var catalog=<your_catalog> \
  --var warehouse_id=<your_warehouse_id>

# Deploy to development
databricks bundle deploy -t dev \
  --var catalog=<your_catalog> \
  --var warehouse_id=<your_warehouse_id>

# Run the full deployment job
databricks bundle run -t dev deploy_all \
  --var catalog=<your_catalog> \
  --var warehouse_id=<your_warehouse_id>
```

### Assets Created

- **Schema:** `gl_reporting` (created in specified catalog)
- **Dimension Tables:** 5 (accounts, cost_centers, projects, vendors, line_formats)
- **Fact Table:** 1 (gl_journal_entries with 1,912 rows, 24 months of data)
- **Metric Views:** 10 total (6 core + 4 advanced)
- **Dashboard:** Finance GL Drill-Down Explorer (5 pages)

### Serverless Compute

- All job tasks are notebook tasks with no cluster spec, so they run on serverless jobs compute.
- The `catalog` variable is passed to every task as the `catalog` job parameter. SQL notebooks read it with `USE CATALOG IDENTIFIER(:catalog)`, and the Python notebook reads it with `dbutils.widgets.get("catalog")`.
- The dashboard runs on the SQL warehouse given by `warehouse_id` and resolves `gl_reporting.*` against `dataset_catalog: ${var.catalog}`.

## Useful Links

- [Advanced techniques for metric views](https://docs.databricks.com/aws/en/uc-semantics/metric-views/advanced-techniques)