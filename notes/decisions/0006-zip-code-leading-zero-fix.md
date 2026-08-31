# 0006 — Zip Code Leading Zero Fix

**Status:** Accepted

## Context

While designing `dim_geolocation`, noticed `geolocation_zip_code_prefix`
was stored as a numeric type in `stg_geolocation`. Since Brazilian zip
codes (CEP) can legitimately start with `0`, storing them as numbers
risks silently dropping that leading digit — a real value like
`"01310"` becomes the number `1310`, permanently losing information
about what the code actually was.

Verified this was a real, active problem, not a hypothetical risk —
checked `LENGTH(CAST(zip_code_prefix AS TEXT))` across all three
tables with a zip column:

- `stg_geolocation`: 245,733 of 1,000,163 rows (~24.6%) had a 4-digit
  zip instead of 5.
- `stg_customers`: 23,995 of 99,441 rows (~24.1%).
- `stg_sellers`: 1,027 of 3,095 rows (~33.2%).

All three tables lost the leading zero the same way (always exactly
one digit, never more), so joins between them via `zip_code_prefix`
would still technically match today — but the actual zip values
themselves were wrong in all three places.

Checked the raw source CSVs directly to confirm this wasn't a source
data issue: `olist_geolocation_dataset.csv` and
`olist_customers_dataset.csv` both have zip codes quoted as text with
leading zeros intact (e.g. `"01037"`, `"14409"`, `"09790"`). The
Kaggle source data is correct — the leading zero loss happened during
this project's own `scripts/load_raw_to_postgres.py`, where
`pd.read_csv()` was called with no explicit `dtype` for these columns,
letting pandas auto-infer them as numeric and silently strip the
leading zero.

## Options Considered

**Option 1 — patch the corrupted values in the SQL transform step**
(e.g. `LPAD()` to re-add a zero to any 4-digit zip). Trade-off: treats
the symptom, not the cause — the staging tables (`stg_customers`,
`stg_sellers`, `stg_geolocation`) would still hold the wrong values,
and a `LPAD` fix only works because the corruption pattern happens to
be "always exactly one missing digit," which is fragile to rely on.

**Option 2 — fix the loader script and reload the affected staging
tables.** Add a `dtype` override so `pd.read_csv()` reads the three
zip columns (`customer_zip_code_prefix`, `seller_zip_code_prefix`,
`geolocation_zip_code_prefix`) as text instead of letting pandas
infer their type, then re-run the loader to reload `stg_customers`,
`stg_sellers`, and `stg_geolocation` with corrected values.

## Decision

**Option 2** — fixed `load_raw_to_postgres.py` to force the three zip
columns to `str` via an explicit `dtype` argument, then reloaded all
9 staging tables (`if_exists="replace"` made this a clean overwrite).
Verified via the same `LENGTH(CAST(...))` check — 100% of rows in all
three tables now show 5-digit zips, zero remaining 4-digit rows.

Reasons:
- This is a load-hygiene bug (a wrong dtype causing real data loss),
  not messy source data — and the project's own documented ELT plan
  (see README) explicitly scopes "load-hygiene fixes (dtypes,
  encoding)" to the Python load step, not the SQL transform step.
  Fixing it at the load step matches the project's own stated design,
  rather than working around it downstream.
- Fixing the root cause means the staging tables now hold values that
  faithfully match the actual source data — the correct target for a
  staging layer in an ELT pipeline — rather than staging tables that
  are known to be wrong and require every downstream consumer to
  remember to correct for it.

## Consequences

- `stg_customers`, `stg_sellers`, and `stg_geolocation` were reloaded
  and now contain correct 5-digit zip codes. Any work done against
  these tables before this fix (none yet, beyond exploration/design)
  would have been based on corrupted zip values.
- The three affected columns are now `TEXT`/`VARCHAR` in Postgres
  rather than numeric — downstream SQL (including `dim_geolocation`'s
  build) should treat `zip_code_prefix` as a string identifier, not a
  number, consistent with the reasoning that codes aren't quantities.
- This fix was caught during schema design (checking real data before
  finalizing `dim_geolocation`'s columns), not during the original
  exploration phase — worth noting as an example of why re-verifying
  assumptions at each project phase (not just once, upfront) catches
  real issues.
