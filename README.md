# Ecommerce Dimensional Model

A data engineering portfolio project: building a star schema data
warehouse from a real, messy public e-commerce dataset — practicing SQL
joins, subqueries, window functions, and CTEs through dimensional
modeling and hands-on data quality investigation.

## Project Goal

Built to close a specific skill gap: hands-on fluency with SQL joins,
subqueries, window functions, and CTEs — identified as weak after an
earlier checkpoint project. Dimensional modeling itself is also a core,
job-relevant skill for the data engineer role this project supports, so
the two goals are combined deliberately rather than treated as separate
exercises.

## Skills Demonstrated

- **SQL:** joins, subqueries, window functions, CTEs, dimensional
  modeling (star schema design)
- **Python / pandas:** data exploration, profiling, and validation at
  scale (from a few hundred rows to over 1 million)
- **Data quality investigation:** systematic anomaly detection using
  aggregation, regex pattern matching, string similarity, and
  cross-column/cross-file consistency checks
- **Pipeline design:** ELT architecture (Python extract/load, SQL
  transform) — the same pattern dbt is built around
- **Tooling:** PostgreSQL, DBeaver, git/GitHub, VSCode

## Project Overview

The pipeline: explore all 9 raw CSVs to understand their real structure
and quality, load them as-is into Postgres staging tables, then
transform them into a star schema entirely in SQL — deduping, cleaning,
and joining along the way. The project closes with a set of checkpoint
SQL queries demonstrating the specific skills it was built to practice.

## Dataset

**Brazilian E-Commerce Public Dataset by Olist**
https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce

Real, anonymized data covering ~100,000 orders placed on the Olist
marketplace (2016-2018), split across 9 CSVs joined by shared keys
(`order_id`, `customer_id`, `product_id`, `seller_id`):

| File | Contents |
|---|---|
| `olist_orders_dataset.csv` | One row per order: status, purchase/delivery timestamps |
| `olist_order_items_dataset.csv` | Line items per order: product, seller, price, freight value |
| `olist_order_payments_dataset.csv` | Payment method, installments, payment value per order |
| `olist_order_reviews_dataset.csv` | Customer review score, comment, review timestamps |
| `olist_customers_dataset.csv` | Customer ID, city, state, zip prefix |
| `olist_sellers_dataset.csv` | Seller ID, city, state, zip prefix |
| `olist_products_dataset.csv` | Product category, dimensions, weight |
| `olist_geolocation_dataset.csv` | Zip code prefix to lat/long mapping (~1M rows) |
| `product_category_name_translation.csv` | Portuguese to English category name mapping |

CSVs are not committed to this repo (see `.gitignore`) — download them
from the Kaggle link above into `raw_csv/` to reproduce.

## Pipeline Pattern: ELT, not ETL

- **Extract:** Python reads the 9 raw CSVs.
- **Load:** Python loads them into Postgres staging tables (`stg_*`)
  largely as-is — only load-hygiene fixes (dtypes, encoding), no
  business logic.
- **Transform:** SQL against the staging tables builds the star schema
  — deduping, null handling, standardization, and joins all happen
  here.

Chosen deliberately over ETL to force SQL joins/CTEs/window functions,
and because it mirrors the dbt-style pattern used in real-world DE
pipelines.

## Notable Data Quality Findings

Full investigation documented in `notes/data_exploration.md`. A few
highlights:

- **Root-caused a timezone artifact to the exact source:** 85 anomalous
  timestamps in the reviews data all traced to two specific historical
  Brazilian daylight-saving-time transition dates (2016-10-16 and
  2017-10-15), not random bad data.
- **Uncovered systemic data entry issues in seller location data:**
  across 34 zip codes, found city fields containing email addresses,
  full state names, raw zip-code numbers, and a wide range of
  misspellings/concatenation errors — catalogued and exported for
  future cleaning.
- **Quantified hidden duplication in a 1M-row geolocation table:**
  confirmed ~25% of apparent city-name variety was accent-mark and
  casing noise (e.g. "sao paulo" vs "são paulo"), not real distinct
  values, using Unicode normalization.
- **Caught and corrected my own faulty hypothesis before it became a
  schema decision:** initially assumed two near-duplicate product
  categories were the reason a translation table had fewer entries
  than the products table — verified with a direct set comparison and
  found the real cause was two entirely different, unrelated missing
  categories.
- **Distinguished two different causes of "multiple rows per order"**
  in payment data (mixed payment methods vs. multiple entries of the
  same method) by pulling and comparing real examples rather than
  assuming from aggregate counts alone.

## Target Schema

- `fact_orders` — grain: order line item level
- `dim_customers`
- `dim_products`
- `dim_sellers`
- `dim_geolocation`
- `dim_date`

## Tech Stack

Python 3.12 (pandas, SQLAlchemy, psycopg2), PostgreSQL, DBeaver, VSCode.

## How to Reproduce

```bash
git clone https://github.com/Hanyyoussef4/ecommerce-dimensional-model.git
cd ecommerce-dimensional-model
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
```

Download the dataset from the Kaggle link above into `raw_csv/`, then
follow the pipeline steps below as they're completed.

## Milestones

- **2026-07-24** — Project scaffolded (git, venv, folder structure,
  GitHub repo).
- **2026-08-19** — Data exploration phase complete: all 9 raw CSVs
  fully profiled and documented, including systematic data quality
  investigation (see `notes/data_exploration.md`).
- **2026-08-20** — `ecommerce_dw` Postgres database created via
  `scripts/create_database.py` (psycopg2, autocommit mode, existence
  check to keep the script idempotent).
- **2026-08-20** — All 9 raw CSVs loaded into Postgres staging tables
  via `scripts/load_raw_to_postgres.py` (SQLAlchemy, `pandas.to_sql()`),
  with every table verified against its source CSV via a per-table
  row-count check (CSV count vs `SELECT COUNT(*)`) — all 9 matched
  exactly.
- **2026-08-29/30** — Star schema design in progress: `fact_orders`,
  `dim_customers`, and `dim_products` fully designed (grain, keys,
  columns) and documented via ADRs in `notes/decisions/` and
  `notes/schema_design.md`. `dim_sellers`, `dim_geolocation`, and
  `dim_date` still to be designed.
- **2026-08-31** — Found and fixed a real data quality bug: zip code
  leading zeros were being silently dropped by the loader (pandas
  numeric type inference), affecting ~24-33% of rows across 3 staging
  tables. Fixed at the load-hygiene layer per the project's ELT
  principle, reloaded, and documented (ADR 0006). `dim_sellers` and
  `dim_geolocation` fully designed — including a documented
  referential-integrity gap between `stg_geolocation` and
  `stg_customers`/`stg_sellers` zip coverage.
- **2026-09-01** — `dim_date` designed, completing the star schema:
  surrogate `YYYYMMDD` key (not native `DATE`) to support dedicated
  placeholder rows for missing and known-invalid dates, after finding
  and diagnosing 4 corrupted `shipping_limit_date` values as genuine
  data entry errors (ADR 0007). **Star schema design phase complete**
  — all 6 tables (`fact_orders` + 5 dimensions) designed and
  documented across 7 ADRs.
- *(upcoming)* Dimension and fact tables built in SQL.
- *(upcoming)* Checkpoint queries written; project finalized.

## Status

- [x] Project scaffolded (venv, git, requirements.txt)
- [x] Raw CSVs explored, data quality findings documented
      (`notes/data_exploration.md`)
- [x] `ecommerce_dw` database created
- [x] Raw CSVs loaded to Postgres staging tables
- [x] Star schema designed
- [ ] Dimension tables built (SQL)
- [ ] Fact table built (SQL)
- [ ] Checkpoint queries written (top sellers by revenue — window
      function; month-over-month order trends — CTE; above-average
      order value customers — subquery)

## Good to Know

- This is real, messy public data, not a cleaned-up teaching dataset —
  every data quality issue documented in `notes/data_exploration.md`
  was genuinely discovered during exploration, not injected for
  practice.
- Olist anonymized seller/store-identifying text using Game of Thrones
  house names (per the Kaggle dataset card) — unusual values in text
  fields may reflect this rather than being errors.
- `notes/data_exploration.md` documents the full investigative process
  for each file, not just conclusions — useful context if you want to
  see the reasoning behind specific data quality findings, not just the
  final decisions.