# 0005 — dim_sellers seller_city Cleanup Approach

**Status:** Accepted

## Context

`seller_city` has known data quality issues across 34 zip prefixes,
found during exploration: misspellings, missing spaces, apostrophe
variants, full state names used as a city, an email address used as a
city, a zip-code-number used as a city, malformed concatenations, and
one seller_STATE mismatch. 112 total anomalous rows out of 3,095
sellers (~3.6%), fully catalogued in `notes/seller_city_anomalies.csv`
during exploration — each anomaly was manually reviewed and the
correct value is already known.

Referential integrity between `stg_order_items.seller_id` and
`stg_sellers.seller_id` is confirmed clean in both directions (verified
via `LEFT JOIN`/`RIGHT JOIN` + `WHERE ... IS NULL` checks) — so this
decision is purely about the *content* of `seller_city`, not whether
`dim_sellers` needs to include these sellers (it does; they're real,
referenced sellers).

## Options Considered

**Option 1 — automated pattern-matching/regex cleanup.** Write SQL
(or Python) logic to detect and fix patterns algorithmically (e.g.
strip email-like strings, standardize whitespace). Trade-off: fragile
and hard to fully verify — a rule general enough to catch all 34
distinct anomaly types risks incorrectly modifying legitimate city
names elsewhere in the other ~96% of the data, and doesn't leverage
the manual review already done during exploration.

**Option 2 — manual correction table (seed data), sourced from the
already-catalogued anomalies.** Convert
`notes/seller_city_anomalies.csv` into a two-column mapping
(`raw_value` → `corrected_value`), load it into Postgres as a small
reference table, and apply it during the SQL transform via
`LEFT JOIN` + `COALESCE(corrected_value, seller_city)` — using the
correction where one exists, otherwise keeping the original value
unchanged. Trade-off: doesn't scale automatically to *new* anomalies
that weren't part of the original 112 found during exploration.

## Decision

**Option 2** — manual correction table, loaded as seed data,
applied via `LEFT JOIN` + `COALESCE` during the SQL transform.

Reasons:
- The correction values are already known with certainty from manual
  review during exploration — deterministic, auditable, and doesn't
  risk collateral damage to legitimate city names the way a
  general-purpose pattern-matching rule could.
- Matches standard real-world practice for small, static reference
  data ("seed data") — checked into the repo as a reviewable CSV,
  loaded into the warehouse as an actual table so it can be joined in
  SQL.
- Scope is bounded and known (112 of 3,095 sellers, ~3.6%) — doesn't
  justify building general-purpose fuzzy-matching infrastructure for
  this project's scale.

## Consequences

- This is a one-time fix for *already-existing* bad data — it does
  not prevent new messy values from being entered into `stg_sellers`
  in a future data load. Genuine prevention would need validation at
  the point of data entry (the source application), which is outside
  this pipeline's control. Detecting *new* anomalies quickly (rather
  than preventing them) would require recurring automated data
  quality checks re-run on every new load — reasonable to mention as
  future/production-scale practice, not needed for this one-time
  historical portfolio load.
- The correction table needs to be created (from
  `notes/seller_city_anomalies.csv`, reformatted into
  `raw_value`/`corrected_value` columns) and loaded into Postgres
  before the `dim_sellers` transform query can reference it — tracked
  as a build-step task, not yet done.
- If new anomaly patterns are found later (e.g. during the SQL build
  step), the correction table can simply be extended with more rows —
  it's a living reference table, not a one-time fixed list.
