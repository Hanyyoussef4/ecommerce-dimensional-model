# 0008 — Surrogate Key Generation Strategy (Project-Wide)

**Status:** Accepted

## Context

While building `dim_products`, the surrogate key `product_key` was
first generated inline in the transform query using
`ROW_NUMBER() OVER (ORDER BY product_id)`, as part of a single
`CREATE TABLE dim_products AS SELECT ...` statement.

Working through this raised a real question: `ROW_NUMBER()` is
recalculated from scratch every time the query runs, numbering
whatever rows exist *at that moment*, in the specified order. It has
no memory of any previous run. If a row were ever deleted from the
underlying source data and the table rebuilt, every row ordered after
the deleted one would shift up one position and receive a *different*
key than it had before — even though that real-world product never
changed. In a live system, if `fact_orders` already had rows
referencing the old key, those references would now silently point to
the wrong product (or a key that no longer means what it used to).

This project's own data is a one-time static historical load (see
[ADR 0007](0007-dim-date-key-strategy-and-placeholders.md)'s reasoning
about `dim_date`'s range) and will never actually be rebuilt against
changed source data — so this specific risk has no practical
consequence *here*. However, this project's explicit goal is to
demonstrate real, transferable data engineering skills (dynamic
ETL/ELT pipeline design), not just produce correct output for one
frozen dataset. A dimension table's surrogate key is exactly the kind
of "obvious" detail — referenced by other tables, expected to be
stable — that a reviewer or interviewer would examine closely.

This decision applies project-wide to every dimension table that
needs a *generated* surrogate key: `dim_products`, `dim_customers`,
and `dim_sellers`. It does not apply to `dim_date` (uses a
deliberately-designed `YYYYMMDD` key, see ADR 0007) or
`dim_geolocation` (uses its natural key, `zip_code_prefix`, no
surrogate at all).

## Options Considered

**Option 1 — `ROW_NUMBER() OVER (ORDER BY ...)` inline in a single
`CREATE TABLE ... AS SELECT` statement.** Simple, one-step build.
Trade-off: keys are recalculated from scratch on every run with no
memory of prior assignments — not stable if the table is ever rebuilt
against changed source data. Doesn't reflect how a real, ongoing
pipeline would need to behave, since dimension tables in production
are normally loaded incrementally, not fully regenerated each time.

**Option 2 — a true auto-incrementing identity column
(`GENERATED ALWAYS AS IDENTITY`), defined directly on the table and
populated via a two-step `CREATE TABLE` + `INSERT INTO ... SELECT`.**
Trade-off: one more step than a single `CREATE TABLE AS SELECT`, and
requires explicitly listing the table's column definitions rather than
letting Postgres infer them from the query.

## Decision

**Option 2** — every dimension table needing a generated surrogate key
(`dim_products.product_key`, `dim_customers.customer_key`,
`dim_sellers.seller_key`) is built as `CREATE TABLE` (with the key
column defined as `integer generated always as identity primary key`)
followed by `INSERT INTO ... SELECT` from the finished transform
query, with `ROW_NUMBER()` removed from that query entirely.

Reasons:
- An identity column assigns its value once, at the moment a row is
  physically inserted, and that value is permanently attached to that
  row afterward — deleting or reordering other rows never renumbers
  it. This matches how surrogate keys need to behave in any pipeline
  where a dimension table might receive new rows over time without a
  full rebuild.
- This project is explicitly meant to demonstrate skills transferable
  to real, dynamic ETL/ELT pipelines, not just produce correct output
  for a single static dataset. Using the same key-generation pattern
  a production system would need is a more honest demonstration of
  that understanding than relying on a pattern (`ROW_NUMBER()`) that
  only happens to be safe here because the data will never change.
- Surrogate keys are referenced by other tables (`fact_orders`) — key
  stability is exactly the kind of foundational, easy-to-overlook
  detail a reviewer would check closely.

## Consequences

- `dim_products`, `dim_customers`, and `dim_sellers` are each built in
  two steps (`CREATE TABLE` with an explicit column list, then
  `INSERT INTO ... SELECT`) instead of a single
  `CREATE TABLE ... AS SELECT`. Slightly more setup per table, but
  necessary for key stability.
- Any transform query already written using `ROW_NUMBER()` for a
  surrogate key (e.g. the `dim_products` work in progress) needs that
  `ROW_NUMBER()` column removed before it becomes the `SELECT` used in
  the `INSERT INTO` step — the identity column on the table handles
  key assignment instead.
- `dim_date` (ADR 0007) and `dim_geolocation` (natural key) are
  unaffected by this decision — they use different, already-justified
  key strategies.
