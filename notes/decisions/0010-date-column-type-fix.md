# 0010 — Date/Timestamp Column Type Fix

**Status:** Accepted

## Context

While building `fact_orders`, a `TO_CHAR()` call against
`stg_orders.order_purchase_timestamp` (used to convert order dates
into `dim_date`'s `YYYYMMDD` surrogate key format) failed with
`function to_char(text, unknown) does not exist`. This error only
occurs when `TO_CHAR()` is called against a `TEXT` value, since
Postgres has no matching function signature for that combination —
the column should have been a `DATE`/`TIMESTAMP` type.

Checked via `information_schema.columns` and confirmed this wasn't an
isolated issue: every date/timestamp column across the three tables
that feed `fact_orders`'s 8 date-role lookups was stored as `TEXT`,
not a real date type:

- `stg_orders`: `order_purchase_timestamp`, `order_approved_at`,
  `order_delivered_carrier_date`, `order_delivered_customer_date`,
  `order_estimated_delivery_date` (5 columns)
- `stg_order_items`: `shipping_limit_date` (1 column)
- `stg_order_reviews`: `review_creation_date`,
  `review_answer_timestamp` (2 columns)

Checked `scripts/load_raw_to_postgres.py` to confirm the root cause:
`pd.read_csv()` was called with no `parse_dates` argument and no
`dtype` override for any of these columns, so pandas defaulted them
to plain strings, and `.to_sql()` then created them as `TEXT` in
Postgres. This is the same category of bug as
[ADR 0006](0006-zip-code-leading-zero-fix.md) (a wrong/missing dtype
during load causing data loss or, here, loss of type fidelity) — a
new, previously-undiscovered instance of it, affecting a different
set of columns.

## Options Considered

**Option 1 — cast inline in the SQL transform** (e.g.
`TO_CHAR(o.order_purchase_timestamp::timestamp, 'YYYYMMDD')` at every
call site). Trade-off: treats the symptom, not the cause — the
staging tables (`stg_orders`, `stg_order_items`, `stg_order_reviews`)
would still hold the wrong type, and every future query against them
(not just `fact_orders`) would need to remember to cast.

**Option 2 — fix the loader script and reload the affected staging
tables.** Add a `date_columns` dict (mirroring the existing
`zip_columns` pattern) mapping each affected file to its list of date
columns, pass it into `pd.read_csv()`'s `parse_dates` argument, and
re-run the loader to reload all 9 staging tables
(`if_exists="replace"` makes this a clean overwrite, same as ADR
0006).

## Decision

**Option 2** — fixed `load_raw_to_postgres.py` to parse the 8 affected
columns as real dates via `parse_dates`, then reloaded all 9 staging
tables. Verified via the same `information_schema.columns` check —
all 8 columns now show `timestamp without time zone` instead of
`text`. Row counts for all 9 tables re-verified against their source
CSVs (unchanged, exact match), confirming no data was lost or altered
by the reload — only the column type changed, not the underlying
values.

Reasons:
- Same reasoning as ADR 0006: this is a load-hygiene bug, and the
  project's own documented ELT plan scopes dtype fixes to the Python
  load step, not the SQL transform step. Fixing it at the load step
  keeps the staging layer trustworthy for any future consumer, not
  just this one build.
- Inline casting in `fact_orders` would have hidden the bug rather
  than fixed it — the staging tables would remain silently wrong.
- Low-risk, cheap fix at this stage: nothing besides the in-progress
  `fact_orders` build depends on these three staging tables' date
  columns yet, so reloading now costs almost nothing.

## Consequences

- `stg_orders`, `stg_order_items`, and `stg_order_reviews` were
  reloaded and now contain correctly-typed
  `timestamp without time zone` columns for all 8 affected fields.
- Reloading via `if_exists="replace"` only touches these `stg_*`
  tables — it does not affect `dim_customers`, `dim_products`,
  `dim_sellers`, `dim_geolocation`, or `dim_date`, since those are
  separate tables built via `INSERT ... SELECT`, not live references
  to staging. No downstream dimension rebuild was needed.
- This fix was caught while building `fact_orders`, not during the
  original exploration or design phases — another example (alongside
  ADR 0006) of a load-hygiene bug only surfacing once real
  date-manipulation logic was written against the data, reinforcing
  the value of re-verifying assumptions at each project phase.
