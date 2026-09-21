# Build Log

Full day-by-day build history for this project — every bug found,
decision made, and verification step, in chronological order. The
README keeps only a condensed, high-level version of this under
[Milestones](../README.md#milestones); this file is the detailed
record for anyone who wants the full story.

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
- **2026-09-05/07** — SQL build phase started: `dim_products` and
  `dim_customers` built (`CREATE TABLE` + `INSERT INTO ... SELECT`,
  surrogate keys via `GENERATED ALWAYS AS IDENTITY` per
  [ADR 0008](decisions/0008-surrogate-key-generation-strategy.md)),
  verified row-for-row against known distinct counts (32,951 products,
  96,096 customers), and committed as `sql/build_dim_products.sql` /
  `sql/build_dim_customers.sql`. `dim_sellers`, `dim_geolocation`, and
  `dim_date` still to be built.
- **2026-09-10/11** — `seed_seller_city_corrections` seed table built:
  the 27 known bad `seller_city` values catalogued during exploration
  (`notes/seller_city_anomalies.csv`) converted to a `raw_value` →
  `corrected_value` mapping (`notes/seller_city_corrections.csv`),
  loaded via `scripts/load_seller_city_corrections.py`, and verified
  (27 rows). `dim_sellers` built (`CREATE TABLE` + `INSERT INTO ...
  SELECT`, surrogate `seller_key`, `seller_city` corrected via
  `LEFT JOIN` + `COALESCE` against the seed table per
  [ADR 0005](decisions/0005-dim-sellers-city-cleanup.md)),
  verified against the confirmed distinct count (3,095 sellers), and
  committed as `sql/build_dim_sellers.sql`. ADR 0005 updated to
  document that corrections match on city text alone, not scoped by
  zip — confirmed safe for this dataset's 27 values. `dim_geolocation`
  and `dim_date` still to be built.
- **2026-09-12/16** — `dim_geolocation` designed and built: normalization
  approach documented in
  [ADR 0009](decisions/0009-dim-geolocation-city-normalization.md)
  after investigating `unaccent`/`LOWER()` collapsed 8,011 raw distinct
  city values to 5,969 (~25.5% reduction, matching the ~25% found
  during Python exploration), then root-caused the remaining 23
  leftover values down to 11 genuine corruption cases (HTML entities,
  double URL/HTML encoding, charset mis-decodes) plus 2
  full-address-as-city values, distinguishing those from 10 legitimate
  Brazilian sub-district names that only looked anomalous.
  `seed_geolocation_city_corrections` (13 rows) built and loaded via
  `scripts/seed_geolocation_city_corrections.py`. `dim_geolocation`
  built (`CREATE TABLE` + two chained CTEs + `INSERT INTO ... SELECT`
  with `AVG()`/`MODE() WITHIN GROUP` to collapse ~1M raw rows down to
  one row per zip), verified against the confirmed distinct zip count
  (19,015), and committed as `sql/build_dim_geolocation.sql`. `dim_date`
  is the last remaining dimension before `fact_orders`.
- **2026-09-18** — `dim_date` built via `generate_series()` — the one
  dimension with no direct source table, generated rather than
  transformed. `date_key` computed as a surrogate `YYYYMMDD` integer
  (not `GENERATED ALWAYS AS IDENTITY` like the other dimensions, and
  not a native `DATE`, per [ADR 0007](decisions/0007-dim-date-key-strategy-and-placeholders.md)),
  spanning the confirmed `2016-09-04` to `2018-11-12` date range plus
  2 `UNION ALL`-appended placeholder rows for not-applicable and
  known-invalid dates. Verified: 802 rows (800 calendar days + 2
  placeholders), committed as `sql/build_dim_date.sql`. **All 5
  dimension tables are now built and verified** — `fact_orders` and
  the checkpoint queries are all that remain.
- **2026-09-19** — `fact_orders` built: one row per order line item
  (112,650 rows, matching `stg_order_items` exactly), resolving all 10
  foreign keys (`product_key`/`seller_key` direct lookups,
  `customer_key` via a two-hop join through `stg_customers` per ADR
  0002, and 8 separate `dim_date` role-playing lookups via `LEFT JOIN`
  + `COALESCE`/`CASE`) plus two pre-aggregation CTEs collapsing
  `stg_order_payments`/`stg_order_reviews` to one row per order before
  joining in. While building this, found and fixed a real load-hygiene
  bug — all 8 date/timestamp source columns were stored as `TEXT` in
  staging, not a real date type, because the original loader had no
  `parse_dates` argument. Fixed in `scripts/load_raw_to_postgres.py`,
  reloaded the 3 affected staging tables, and documented as
  [ADR 0010](decisions/0010-date-column-type-fix.md), following
  the same load-layer-fix precedent as ADR 0006. Verified zero `NULL`
  date-keys and exactly 4 rows with `shipping_limit_date_key = -2`
  (matching ADR 0007's documented corrupted-row count). Committed as
  `sql/build_fact_orders.sql`. **The star schema is now fully built**
  — checkpoint queries are the only remaining step.
- **2026-09-19** — 11 foreign key constraints added to `fact_orders`
  (`sql/add_foreign_keys.sql`), referencing `dim_products`,
  `dim_sellers`, `dim_customers`, and `dim_date` 8 times over for its
  8 role-playing date columns. Verified via DBeaver's ER diagram,
  which now renders all relationship lines correctly (see
  [Target Schema](../README.md#target-schema) in the README) — only
  possible because every date-key column is guaranteed to resolve to
  a real `dim_date` row, including the `-1`/`-2` placeholder rows from
  ADR 0007.
- **2026-09-20** — All 3 checkpoint SQL queries written, verified, and
  committed, closing out the project's original skill-gap goal:
  top sellers by revenue (`sql/checkpoint1_top_sellers_by_revenue.sql`,
  `DENSE_RANK()`), month-over-month order trends
  (`sql/checkpoint2_month_over_month_trends.sql`, two chained CTEs plus
  `LAG()`), and above-average order value customers
  (`sql/checkpoint3_above_average_customers_subquery.sql`, a scalar
  subquery in the `WHERE` clause). Checkpoint 3 also has a second,
  window-function-based version
  (`sql/checkpoint3_above_average_customers_window_function.sql`) kept
  alongside the subquery version deliberately, to show the same result
  reached two different ways. Along the way, caught and fixed a real
  integer-division bug in checkpoint 2 (Postgres truncates `bigint /
  bigint` before it can be scaled or rounded — a `::numeric` cast was
  required to get correct percentages) and a `PARTITION BY` misuse in
  checkpoint 1 (partitioning by the same columns already used to
  produce one row per group leaves window functions like `LAG()`
  nothing to look back at). **Project complete** — all schema and
  analysis goals from the original README are done.
