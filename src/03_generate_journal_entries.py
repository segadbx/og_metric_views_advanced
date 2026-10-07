# Databricks notebook source
# 03_generate_journal_entries.py
# Synthetic GL journal entry data generator (1,912 rows, 24 months)

# ============================================================
# FACT TABLE: GL Journal Entries
# Generates 24 months of realistic Oil & Gas GL data
# with proper FK relationships to all 5 dimension tables
# ============================================================
import random
from datetime import date, timedelta
from pyspark.sql import Row
from pyspark.sql.types import *

dbutils.widgets.text("catalog", "")
catalog_name = dbutils.widgets.get("catalog")

random.seed(42)

# --- Mapping: account_id -> line_format_id ---
account_to_line_format = {
    '4100': 'LF-REV', '4200': 'LF-REV', '4300': 'LF-REV', '4400': 'LF-REV',
    '5100': 'LF-OPEX-D', '5110': 'LF-OPEX-D', '5200': 'LF-OPEX-D',
    '5210': 'LF-OPEX-D', '5300': 'LF-OPEX-D',
    '6100': 'LF-EXPL', '6200': 'LF-EXPL', '6300': 'LF-EXPL',
    '7100': 'LF-GA', '7200': 'LF-GA', '7300': 'LF-GA', '7400': 'LF-GA',
    '8100': 'LF-DDA', '8200': 'LF-DDA', '8300': 'LF-DDA',
    '9100': 'LF-CAPEX', '9200': 'LF-CAPEX', '9300': 'LF-CAPEX', '9400': 'LF-CAPEX'
}

# --- Mapping: account_id -> realistic vendor pool ---
account_to_vendors = {
    '4100': [None], '4200': [None], '4300': [None], '4400': [None],  # Revenue: no vendor
    '5100': ['V-001','V-002','V-008','V-009'], '5110': ['V-001','V-003','V-009'],
    '5200': ['V-008','V-009'], '5210': ['V-010','V-011'],
    '5300': ['V-006','V-007'],
    '6100': ['V-002','V-003'], '6200': ['V-004','V-005'], '6300': ['V-002'],
    '7100': [None], '7200': [None], '7300': ['V-014'], '7400': ['V-012','V-013'],
    '8100': [None], '8200': [None], '8300': [None],
    '9100': ['V-004','V-005'], '9200': ['V-001','V-003'],
    '9300': ['V-006','V-007'], '9400': [None]
}

# --- Mapping: account_id -> cost center pool ---
account_to_cc = {
    '4100': ['CC-100','CC-101','CC-200','CC-201','CC-300','CC-301'],
    '4200': ['CC-100','CC-101','CC-200','CC-201','CC-300','CC-301'],
    '4300': ['CC-101','CC-201','CC-301'],
    '4400': ['CC-400','CC-401','CC-500'],
    '5100': ['CC-100','CC-101','CC-200','CC-201','CC-300','CC-301'],
    '5110': ['CC-100','CC-200','CC-300'],
    '5200': ['CC-101','CC-201','CC-301'],
    '5210': ['CC-101','CC-201','CC-301'],
    '5300': ['CC-400','CC-401','CC-500'],
    '6100': ['CC-100','CC-200','CC-300'], '6200': ['CC-100','CC-200','CC-300'],
    '6300': ['CC-100','CC-200','CC-300'],
    '7100': ['CC-600','CC-601','CC-602'], '7200': ['CC-600','CC-601','CC-602'],
    '7300': ['CC-600'], '7400': ['CC-600'],
    '8100': ['CC-100','CC-101','CC-200','CC-201','CC-300','CC-301'],
    '8200': ['CC-400','CC-401','CC-500','CC-600','CC-601'],
    '8300': ['CC-101','CC-201','CC-301'],
    '9100': ['CC-100','CC-200','CC-300'], '9200': ['CC-100','CC-102','CC-200'],
    '9300': ['CC-400','CC-401','CC-500'], '9400': ['CC-100','CC-200','CC-300']
}

# --- Mapping: account_id -> project pool ---
account_to_project = {
    '4100': [None], '4200': [None], '4300': [None], '4400': [None],
    '5100': ['PRJ-010','PRJ-011',None], '5110': ['PRJ-010','PRJ-011',None],
    '5200': [None], '5210': ['PRJ-020',None],
    '5300': ['PRJ-021',None],
    '6100': ['PRJ-003','PRJ-004'], '6200': ['PRJ-001','PRJ-002'],
    '6300': ['PRJ-003','PRJ-004'],
    '7100': ['PRJ-030','PRJ-031',None], '7200': [None], '7300': [None],
    '7400': ['PRJ-031',None],
    '8100': [None], '8200': [None], '8300': [None],
    '9100': ['PRJ-001','PRJ-002','PRJ-010','PRJ-012'],
    '9200': ['PRJ-001','PRJ-002','PRJ-010','PRJ-011'],
    '9300': ['PRJ-020','PRJ-021','PRJ-022'],
    '9400': ['PRJ-001','PRJ-002','PRJ-004']
}

# --- Amount ranges by account (monthly, in thousands USD) ---
account_amounts = {
    '4100': (8000, 15000), '4200': (3000, 7000), '4300': (1000, 3000), '4400': (500, 2000),
    '5100': (200, 800), '5110': (100, 500), '5200': (300, 1200), '5210': (80, 300),
    '5300': (150, 600),
    '6100': (100, 500), '6200': (200, 1000), '6300': (50, 200),
    '7100': (400, 900), '7200': (60, 120), '7300': (30, 80), '7400': (40, 150),
    '8100': (500, 1200), '8200': (200, 500), '8300': (100, 300),
    '9100': (1000, 5000), '9200': (500, 2500), '9300': (300, 1500), '9400': (200, 1000)
}

rows = []
entry_id = 1
start_date = date(2025, 1, 1)

for month_offset in range(24):  # Jan 2025 - Dec 2026
    current_month = date(start_date.year + (start_date.month + month_offset - 1) // 12,
                         (start_date.month + month_offset - 1) % 12 + 1, 1)
    fiscal_year = current_month.year
    fiscal_quarter = f"Q{(current_month.month - 1) // 3 + 1}"
    fiscal_period = current_month.month

    for acct_id, (amt_low, amt_high) in account_amounts.items():
        # Generate 2-5 entries per account per month for granularity
        n_entries = random.randint(2, 5)
        for _ in range(n_entries):
            day = random.randint(1, 28)
            posting_date = current_month.replace(day=day)
            amount = round(random.uniform(amt_low / n_entries, amt_high / n_entries) * 1000, 2)
            # Budget = amount * variance factor (some over, some under)
            budget_amount = round(amount * random.uniform(0.85, 1.15), 2)

            vendor = random.choice(account_to_vendors[acct_id])
            cc = random.choice(account_to_cc[acct_id])
            project = random.choice(account_to_project[acct_id])
            lf = account_to_line_format[acct_id]

            rows.append(Row(
                entry_id=f"JE-{entry_id:06d}",
                posting_date=posting_date,
                fiscal_year=fiscal_year,
                fiscal_quarter=fiscal_quarter,
                fiscal_period=fiscal_period,
                account_id=acct_id,
                cost_center_id=cc,
                project_id=project,
                vendor_id=vendor,
                line_format_id=lf,
                amount=amount,
                budget_amount=budget_amount,
                currency='USD',
                journal_type=random.choice(['AP', 'GL', 'FA', 'AR']) if acct_id.startswith(('5','6','7','9')) else 'GL',
                status=random.choice(['Posted', 'Posted', 'Posted', 'Reversed']) # 75% Posted
            ))
            entry_id += 1

schema = StructType([
    StructField('entry_id', StringType()),
    StructField('posting_date', DateType()),
    StructField('fiscal_year', IntegerType()),
    StructField('fiscal_quarter', StringType()),
    StructField('fiscal_period', IntegerType()),
    StructField('account_id', StringType()),
    StructField('cost_center_id', StringType()),
    StructField('project_id', StringType()),
    StructField('vendor_id', StringType()),
    StructField('line_format_id', StringType()),
    StructField('amount', DoubleType()),
    StructField('budget_amount', DoubleType()),
    StructField('currency', StringType()),
    StructField('journal_type', StringType()),
    StructField('status', StringType())
])

df = spark.createDataFrame(rows, schema)
df.write.mode('overwrite').saveAsTable(f'{catalog_name}.gl_reporting.gl_journal_entries')
print(f"Created {df.count()} GL journal entries across {24} months")
df.groupBy('fiscal_year', 'fiscal_quarter').count().orderBy('fiscal_year', 'fiscal_quarter').show()