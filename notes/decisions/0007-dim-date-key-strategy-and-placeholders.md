# 0007 — dim_date Key Strategy and Placeholder Rows

**Status:** Accepted

## Context

While designing `dim_date`, two related questions came up about how its
primary key should work, given `fact_orders` references it 8 times as
a role-playing dimension (purchase, approved, delivered_carrier,
delivered_customer, estimated_delivery, shipping_limit,
first_review, most_recent_review dates).

**Question 1 — key type.** Following the same reasoning applied to
`dim_geolocation` (a short, cheap natural key doesn't need a
surrogate), should `dim_date` use the native `DATE` type directly as
its primary key, or a surrogate integer key?

**Question 2 — NULLs and bad values.** Several of `fact_orders`' date
columns are legitimately empty for real business reasons (e.g.
`delivered_customer_date`/`delivered_carrier_date` for orders not yet
delivered, `first_review_date`/`most_recent_review_date` for orders
with no review yet — consistent with lifecycle nulls already found
during exploration). Separately, while checking the full date range
needed for `dim_date` (via a `UNION ALL` of `MIN`/`MAX` across all 7
underlying source date columns), found a **genuine data quality
anomaly**: 4 of 112,650 `stg_order_items` rows have a
`shipping_limit_date` around 2020-02 to 2020-04, while every other
date column in the dataset caps out around 2018-09/11. Joined these 4
rows to `stg_orders` to check context — one of them (order
`c2bb89b5...`) was purchased 2017-05-23 and actually delivered to the
customer 2017-06-09, yet its `shipping_limit_date` is 2020-04-09: a
"ship by" deadline landing almost 3 years *after* the order was
already delivered, which is logically impossible for a real value.
Confirmed these are data entry errors, not real dates — and with no
way to confidently reconstruct the intended correct date (unlike the
zip leading-zero bug in [ADR 0006](0006-zip-code-leading-zero-fix.md),
where the corruption pattern made the true value recoverable).

## Options Considered

**Key type — Option A: native `DATE` as primary key.** Matches the
`zip_code_prefix` precedent (cheap natural key, no surrogate needed).
Trade-off: a `NULL` foreign key in `fact_orders` for lifecycle-empty
dates. `NULL = NULL` evaluates to unknown in SQL, so `INNER JOIN`
silently drops those fact rows entirely rather than showing them with
an empty date — a real risk for undercount bugs in any query that
happens to join through a date column with legitimate nulls.

**Key type — Option B: surrogate integer key (`YYYYMMDD` format).**
Standard Kimball convention for date dimensions specifically. Enables
a dedicated placeholder row (e.g. key `-1`) for "date not applicable"
instead of `NULL`, so lifecycle-empty dates stay visible in
`INNER JOIN` results as a real, filterable row rather than silently
vanishing.

**Bad-value handling — Option 1: extend `dim_date`'s range to cover
2020.** Would generate roughly 1.5 extra years of otherwise-empty
calendar rows just to accommodate 4 known-corrupted values out of
112,650. Trade-off: bloats the table for no real analytical benefit,
and still doesn't fix the fact that the underlying values are wrong.

**Bad-value handling — Option 2: route corrupted values to the same
placeholder row as "not applicable" (`-1`).** Simple, no new row
needed. Trade-off: conflates two different situations — "this
hasn't happened yet" (a normal, expected business state) and "this
value is present but known to be wrong" (a data quality incident) —
under one label. A future query filtering `WHERE date_key = -1` to
find undelivered orders would silently also catch these 4 unrelated
data-quality rows.

**Bad-value handling — Option 3: a second, distinct placeholder row
(e.g. key `-2`) specifically for "known corrupted/invalid value."**
Keeps the two situations distinguishable and separately queryable.
Trade-off: one more placeholder row to define and route to during the
SQL transform, for the sake of only 4 affected rows.

## Decision

**Key type: Option B** — `dim_date` uses a surrogate integer key in
`YYYYMMDD` format (e.g. `20170315`), not the native `DATE` type.

**Bad-value handling: Option 3** — a second, dedicated placeholder row
(`date_key = -2`, `full_date = NULL`, descriptive columns set to a
literal like `'invalid/data quality issue'`) is added alongside the
"not applicable" placeholder (`date_key = -1`). During the SQL
transform, `fact_orders.shipping_limit_date_key` is set to `-2` for
the 4 rows with a `shipping_limit_date` later than the order's own
delivery date (the same logical check used to find them), instead of
extending `dim_date`'s real calendar range or collapsing them into the
`-1` "not applicable" bucket.

Reasons:
- Real-world practice, absent a business/source-system owner to
  escalate a genuine data quality anomaly to (this is a static,
  anonymized public dataset — there is no team to ask "what should
  this date actually be"), is to flag and quarantine rather than
  fabricate a corrected value. A dedicated placeholder makes that
  quarantine explicit and visible in the schema, rather than silently
  dropped or guessed at.
- Keeping "not yet happened" and "known corrupted" as separate keys
  preserves real, different signals — one is a normal business
  lifecycle state (most orders eventually get delivered), the other
  is a data quality incident worth tracking distinctly. Collapsing
  them would make it impossible to later answer "how many fact rows
  have a genuine data quality issue in this column" without redoing
  this investigation.
- Avoids bloating `dim_date` with ~1.5 years of unused calendar rows
  to accommodate 4 known-bad values out of 112,650.

## Consequences

- `dim_date` needs two placeholder rows built in, not one: `-1` for
  "not applicable / hasn't happened yet" (used across all 8
  role-playing FKs wherever the source date is `NULL`) and `-2` for
  "value present but known invalid" (used only for the 4 corrupted
  `shipping_limit_date` rows identified here).
- The SQL transform for `fact_orders` needs explicit logic to detect
  these 4 rows (`shipping_limit_date` later than the order's own
  delivered_customer_date, or simply the 4 specific `order_id`s found
  during this investigation) and route them to `-2` rather than doing
  a normal `dim_date` lookup.
- This is a one-time fix for already-existing bad data in a static
  historical dataset, not a general prevention mechanism — a live
  system would need this escalated to whoever owns order fulfillment
  data entry, and/or an automated data quality check (e.g.
  `shipping_limit_date <= order_delivered_customer_date`) to catch
  new occurrences going forward.
