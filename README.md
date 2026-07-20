# Ecommerce Dimensional Model

Star schema built from the Olist Brazilian E-Commerce dataset (Kaggle) as a
data engineering portfolio project — practicing SQL joins, subqueries,
window functions, and CTEs via dimensional modeling.

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
| `olist_geolocation_dataset.csv` | Zip code prefix to lat/long mapping |
| `product_category_name_translation.csv` | Portuguese to English category name mapping |

CSVs are not committed to this repo (see `.gitignore`) — download them from
the Kaggle link above into `raw_csv/` to reproduce.

## Pipeline pattern: ELT, not ETL

- **Extract:** Python reads the 9 raw CSVs.
- **Load:** Python loads them into Postgres staging tables (`stg_*`)
  largely as-is — only load-hygiene fixes (dtypes, encoding), no business
  logic.
- **Transform:** SQL against the staging tables builds the star schema —
  deduping, null handling, standardization, and joins all happen here.

Chosen deliberately over ETL to force SQL joins/CTEs/window functions, and
because it mirrors the dbt-style pattern used in real-world DE pipelines.

## Target schema

- `fact_orders` — grain TBD (order line item level, most likely)
- `dim_customers`
- `dim_products`
- `dim_sellers`
- `dim_date`

## Tech stack

Python 3.12 (pandas, SQLAlchemy, psycopg2), PostgreSQL, DBeaver, VSCode.

## Status

- [x] Project scaffolded (venv, git, requirements.txt)
- [ ] `ecommerce_dw` database created
- [ ] Raw CSVs loaded to Postgres staging tables
- [ ] Star schema designed
- [ ] Dimension tables built (SQL)
- [ ] Fact table built (SQL)
- [ ] Checkpoint queries written (top sellers by revenue — window function;
      month-over-month order trends — CTE; above-average order value
      customers — subquery)