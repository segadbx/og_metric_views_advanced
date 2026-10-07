-- Databricks notebook source
USE CATALOG IDENTIFIER(:catalog);
USE SCHEMA gl_reporting;

-- COMMAND ----------

-- ============================================================
-- DIMENSION: Chart of Accounts (dim_accounts)
-- ============================================================
-- ============================================================
-- DIMENSION: Chart of Accounts (Account Group > Category > Account)
-- ============================================================
CREATE OR REPLACE TABLE dim_accounts (
  account_id        STRING    NOT NULL COMMENT 'GL Account code',
  account_name      STRING    NOT NULL COMMENT 'Account descriptive name',
  account_category  STRING    NOT NULL COMMENT 'Mid-level grouping (e.g. Well Services, Lease Operating)',
  account_group     STRING    NOT NULL COMMENT 'Top-level grouping (e.g. Production Costs, Revenue)'
) COMMENT 'Chart of Accounts hierarchy for GL';

INSERT INTO dim_accounts VALUES
  -- Revenue
  ('4100', 'Crude Oil Sales',           'Oil Revenue',         'Revenue'),
  ('4200', 'Natural Gas Sales',         'Gas Revenue',         'Revenue'),
  ('4300', 'NGL Sales',                 'NGL Revenue',         'Revenue'),
  ('4400', 'Midstream Tariff Revenue',  'Midstream Revenue',   'Revenue'),
  -- Production Costs
  ('5100', 'Well Maintenance',          'Well Services',       'Production Costs'),
  ('5110', 'Workover Expenses',         'Well Services',       'Production Costs'),
  ('5200', 'Lease Operating Expense',   'Lease Operating',     'Production Costs'),
  ('5210', 'Saltwater Disposal',        'Lease Operating',     'Production Costs'),
  ('5300', 'Gathering & Processing',    'Midstream Costs',     'Production Costs'),
  -- Exploration Costs
  ('6100', 'Seismic Acquisition',       'Geoscience',          'Exploration Costs'),
  ('6200', 'Dry Hole Expense',          'Drilling',            'Exploration Costs'),
  ('6300', 'Geological Studies',        'Geoscience',          'Exploration Costs'),
  -- G&A
  ('7100', 'Salaries & Benefits',       'Compensation',        'General & Admin'),
  ('7200', 'Office Rent',              'Facilities',          'General & Admin'),
  ('7300', 'Insurance',                 'Risk Management',     'General & Admin'),
  ('7400', 'Legal & Professional',      'Professional Fees',   'General & Admin'),
  -- DD&A
  ('8100', 'Depletion',                 'DD&A - Assets',       'DD&A'),
  ('8200', 'Depreciation',              'DD&A - Assets',       'DD&A'),
  ('8300', 'Amortization of Leases',    'DD&A - Leases',       'DD&A'),
  -- Capital
  ('9100', 'Drilling CAPEX',            'Well Capital',        'Capital Expenditures'),
  ('9200', 'Completion CAPEX',          'Well Capital',        'Capital Expenditures'),
  ('9300', 'Facilities CAPEX',          'Infrastructure',      'Capital Expenditures'),
  ('9400', 'Land & Lease Acquisition',  'Land Capital',        'Capital Expenditures');

-- COMMAND ----------

-- ============================================================
-- DIMENSION: Cost Centers (dim_cost_centers)
-- ============================================================
-- ============================================================
-- DIMENSION: Cost Centers (Business Unit > Region > Cost Center)
-- ============================================================
CREATE OR REPLACE TABLE dim_cost_centers (
  cost_center_id    STRING    NOT NULL COMMENT 'Cost center code',
  cost_center_name  STRING    NOT NULL COMMENT 'Cost center descriptive name',
  region            STRING    NOT NULL COMMENT 'Operating region',
  business_unit     STRING    NOT NULL COMMENT 'Top-level business unit'
) COMMENT 'Cost Center hierarchy for operations';

INSERT INTO dim_cost_centers VALUES
  -- Upstream
  ('CC-100', 'PB Drilling Operations',    'Permian Basin',     'Upstream'),
  ('CC-101', 'PB Production Operations',  'Permian Basin',     'Upstream'),
  ('CC-102', 'PB Completions',            'Permian Basin',     'Upstream'),
  ('CC-200', 'EF Drilling Operations',    'Eagle Ford',        'Upstream'),
  ('CC-201', 'EF Production Operations',  'Eagle Ford',        'Upstream'),
  ('CC-300', 'DJ Drilling Operations',    'DJ Basin',          'Upstream'),
  ('CC-301', 'DJ Production Operations',  'DJ Basin',          'Upstream'),
  -- Midstream
  ('CC-400', 'PB Gathering System',       'Permian Basin',     'Midstream'),
  ('CC-401', 'EF Gathering System',       'Eagle Ford',        'Midstream'),
  ('CC-500', 'Gas Processing Plant',      'Permian Basin',     'Midstream'),
  -- Corporate
  ('CC-600', 'Corporate HQ',             'Houston',           'Corporate'),
  ('CC-601', 'Field Office - Midland',    'Permian Basin',     'Corporate'),
  ('CC-602', 'Field Office - San Antonio','Eagle Ford',        'Corporate');

-- COMMAND ----------

-- ============================================================
-- DIMENSION: Projects (dim_projects)
-- ============================================================
-- ============================================================
-- DIMENSION: Projects (Project Type > Phase > Project)
-- ============================================================
CREATE OR REPLACE TABLE dim_projects (
  project_id       STRING    NOT NULL COMMENT 'Project identifier',
  project_name     STRING    NOT NULL COMMENT 'Project descriptive name',
  project_phase    STRING    NOT NULL COMMENT 'Current phase of the project',
  project_type     STRING    NOT NULL COMMENT 'Top-level project classification'
) COMMENT 'Project hierarchy for capital and operational projects';

INSERT INTO dim_projects VALUES
  -- Exploration
  ('PRJ-001', 'Permian Deep Exploration',     'Active Drilling',   'Exploration'),
  ('PRJ-002', 'Eagle Ford Phase 2',           'Active Drilling',   'Exploration'),
  ('PRJ-003', 'DJ Basin Seismic Survey',      'Pre-Drill Studies',  'Exploration'),
  ('PRJ-004', 'Midland Basin Wildcat',        'Pre-Drill Studies',  'Exploration'),
  -- Development
  ('PRJ-010', 'PB Infill Drilling Program',   'Execution',         'Development'),
  ('PRJ-011', 'EF Recompletion Campaign',     'Execution',         'Development'),
  ('PRJ-012', 'DJ Pad Development',           'Planning',          'Development'),
  -- Infrastructure
  ('PRJ-020', 'PB Water Recycling Facility',  'Execution',         'Infrastructure'),
  ('PRJ-021', 'EF Gas Gathering Expansion',   'Execution',         'Infrastructure'),
  ('PRJ-022', 'Central Tank Battery Upgrade', 'Planning',          'Infrastructure'),
  -- Corporate
  ('PRJ-030', 'ERP System Upgrade',           'Execution',         'Corporate'),
  ('PRJ-031', 'HSE Compliance Program',       'Ongoing',           'Corporate');

-- COMMAND ----------

-- ============================================================
-- DIMENSION: Vendors (dim_vendors)
-- ============================================================
-- ============================================================
-- DIMENSION: Vendors (Vendor Category > Vendor)
-- ============================================================
CREATE OR REPLACE TABLE dim_vendors (
  vendor_id         STRING    NOT NULL COMMENT 'Vendor code',
  vendor_name       STRING    NOT NULL COMMENT 'Vendor legal name',
  vendor_category   STRING    NOT NULL COMMENT 'Top-level vendor classification'
) COMMENT 'Vendor master for Accounts Payable';

INSERT INTO dim_vendors VALUES
  ('V-001', 'Halliburton',               'Oilfield Services'),
  ('V-002', 'Schlumberger',              'Oilfield Services'),
  ('V-003', 'Baker Hughes',              'Oilfield Services'),
  ('V-004', 'Patterson-UTI',             'Drilling Contractors'),
  ('V-005', 'Helmerich & Payne',         'Drilling Contractors'),
  ('V-006', 'Targa Resources',           'Midstream Partners'),
  ('V-007', 'DCP Midstream',             'Midstream Partners'),
  ('V-008', 'Basic Energy Services',     'Production Services'),
  ('V-009', 'C&J Well Services',         'Production Services'),
  ('V-010', 'Cactus Water Services',     'Water Management'),
  ('V-011', 'Solaris Oilfield',          'Water Management'),
  ('V-012', 'Ernst & Young',             'Professional Services'),
  ('V-013', 'Vinson & Elkins',           'Professional Services'),
  ('V-014', 'Marsh McLennan',            'Insurance'),
  ('V-015', 'HESS Office Solutions',     'Corporate Services');

-- COMMAND ----------

-- ============================================================
-- DIMENSION: Line Formats (dim_line_formats)
-- ============================================================
-- ============================================================
-- DIMENSION: Line Formats (Report Section > Line Format)
-- Defines how GL lines appear on financial statements
-- ============================================================
CREATE OR REPLACE TABLE dim_line_formats (
  line_format_id    STRING    NOT NULL COMMENT 'Line format code',
  line_format_name  STRING    NOT NULL COMMENT 'Detailed line format label',
  report_section    STRING    NOT NULL COMMENT 'Top-level section on financial report',
  sort_order        INT       NOT NULL COMMENT 'Display order on the report'
) COMMENT 'Financial report line format hierarchy';

INSERT INTO dim_line_formats VALUES
  ('LF-REV',   'Revenue',                   'Operating Income',           10),
  ('LF-OPEX-D','OPEX - Direct',             'Operating Expenses',         20),
  ('LF-OPEX-I','OPEX - Indirect',           'Operating Expenses',         30),
  ('LF-DDA',   'DD&A',                      'Operating Expenses',         40),
  ('LF-GA',    'General & Administrative',   'Operating Expenses',         50),
  ('LF-CAPEX', 'Capital Expenditures',       'Capital & Investment',       60),
  ('LF-EXPL',  'Exploration Expense',        'Capital & Investment',       70);