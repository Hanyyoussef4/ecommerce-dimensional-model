# 0009 — dim_geolocation City Normalization Approach

**Status:** Accepted

## Context

`stg_geolocation` (~1M rows) has 8,011 distinct raw `geolocation_city`
values. `dim_geolocation`'s design (`schema_design.md`) requires
`MODE() WITHIN GROUP` per `zip_code_prefix` to pick the most common
city name, but roughly 25% of that apparent variety is accent-mark and
casing noise (e.g. `sao paulo` vs `são paulo`), not real distinct city
names — already flagged during the Python-based exploration phase
(`notes/data_exploration.md`). A SQL-native normalization approach was
needed before `MODE()` could produce meaningful results in the
transform layer.

Applying Postgres's `unaccent` extension + `LOWER()` directly in SQL
reduced the distinct count from 8,011 to 5,969 — a ~25.5% reduction,
closely matching the ~25% figure already found during Python
exploration and confirming the two approaches agree.

Isolating the remaining 5,969 values for anything still containing
non-standard characters after normalization (a regex excluding
`[a-z0-9 ' -]`) found 23 leftover values, after correcting an initial
regex bug that had also incorrectly flagged valid apostrophe-containing
names like `santa barbara d'oeste`. Manual review of those 23 values
(catalogued in `notes/geolocation_city_anomalies.csv`) found three
distinct categories:

1. **Legitimate sub-district names** with their parent municipality
   noted in parentheses (10 values, e.g. `tamoios (cabo frio)`,
   `bacaxa (saquarema) - distrito`) — a standard Brazilian
   administrative naming convention, not an error.
2. **Full location strings** (city, state, country) crammed into the
   city field (2 values: `rio de janeiro, rio de janeiro, brasil` and
   `campo alegre de lourdes, bahia, brasil`) — the same anomaly class
   already found and fixed in `stg_sellers.seller_city` (ADR 0005).
3. **Genuine data corruption** (11 values): garbage characters
   (`...arraial do cabo`, `* cidade`), un-decoded or double-encoded
   HTML entities (`florian&oacute;polis`;
   `lambari d%26apos%3boeste` and `sao joao do pau d%26apos%3balho` —
   an apostrophe HTML-entity-encoded to `&apos;`, then that result
   URL-percent-encoded on top), charset mis-decodes (`sa£o paulo`,
   `maceia³`), a substituted quote character
   (`` santa barbara d`oeste ``), a stray leading accent character
   (`´teresopolis`), and two duplicate spellings of the same place
   (`4º centenario` / `4o. centenario`).

## Options Considered

**Option 1 — `unaccent` + `LOWER()` only, accept the remainder.**
Simple, no additional table. Trade-off: leaves the 11 genuinely
corrupted values (plus the 2 full-address values) permanently wrong
in `dim_geolocation` for their zip prefixes, even though the correct
value is already knowable from manual review — an avoidable
inaccuracy for a small, bounded set of rows.

**Option 2 — `unaccent` + `LOWER()`, plus a manual correction seed
table for the 13 known-bad values** (11 corrupted + 2 full-address,
the latter mapped to `'not specified'` per the same convention used
for unresolvable seller city values in ADR 0005) — same seed-table
pattern as `seed_seller_city_corrections`, matched against the
*normalized* (`unaccent(LOWER(...))`) text via `LEFT JOIN` +
`COALESCE`. The 10 legitimate district/parenthetical names are left
untouched.

## Decision

**Option 2.**

Reasons:
- The correct values are already known with certainty from manual
  review — same reasoning as ADR 0005.
- Reuses an established, already-verified pattern rather than
  inventing new correction machinery.
- Scope is small and bounded (13 rows) — doesn't justify
  general-purpose fuzzy-matching or additional automated cleanup.
- `unaccent` + `LOWER()` already resolves the vast majority of
  apparent duplication (2,042 of 2,055 total distinct-value noise,
  ~99.4%) automatically; the seed table only needs to cover the true
  edge cases left over.

## Consequences

- A `seed_geolocation_city_corrections` table (`raw_value` →
  `corrected_value`) and loader script are needed, following the same
  pattern as `scripts/load_seller_city_corrections.py`.
- The `dim_geolocation` build query must apply
  `unaccent(LOWER(geolocation_city))` first, then `LEFT JOIN` +
  `COALESCE` against the seed table on that *normalized* value
  (not the raw value), before the `MODE() WITHIN GROUP` aggregation
  per `zip_code_prefix`.
- The 10 legitimate district/parenthetical names are correctly left
  unmodified — worth a note in `schema_design.md` so a future reader
  doesn't mistake them for unresolved anomalies.
- Like ADR 0005, this is a one-time fix for already-existing bad data
  in this static historical dataset, not a general-purpose solution
  for future corruption patterns.
