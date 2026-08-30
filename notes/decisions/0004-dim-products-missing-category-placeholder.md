# 0004 — dim_products Missing Category Placeholder

**Status:** Accepted

## Context

610 rows in `stg_products` are missing `product_category_name`
(alongside `product_name_lenght`, `product_description_lenght`, and
`product_photos_qty` — all missing together, confirmed during
exploration to be incomplete listings, not independent random gaps).

Verified before deciding how to handle this (two independent checks):
a `COUNT(DISTINCT oi.product_id)` join against `stg_order_items`
returned exactly 610 (matching the full null-category count), and a
cleaner anti-join (`LEFT JOIN ... WHERE oi.product_id IS NULL`)
confirmed zero of the 610 were never ordered. **All 610 products with
missing category data have real purchases in `stg_order_items`.**
This means `dim_products` cannot exclude these rows — `fact_orders`
will genuinely reference them via `product_key`.

## Options Considered

**Option 1 — leave as `NULL`.** No transformation needed. Trade-off:
`NULL` behaves inconsistently across reporting/BI tools and SQL
operations — grouping by a `NULL` category can render as a blank or
ambiguous row depending on the tool, comparisons need `IS NULL` rather
than `=`, and it's easy for a downstream query to silently drop or
mishandle these rows without realizing it.

**Option 2 — replace with an explicit placeholder value
(`'not specified'`).** Applied to both `product_category_name` and
`product_category_name_english` during the SQL transform. Trade-off:
introduces a value into `dim_products` that isn't a real category —
anyone querying the table needs to know it's a placeholder, not an
actual product type.

## Decision

**Option 2** — missing categories are replaced with the literal string
`'not specified'` in both `product_category_name` and
`product_category_name_english`.

Reasons:
- Makes the data quality gap visible and explicit to anyone querying
  `dim_products`, rather than requiring every downstream query to
  separately handle `NULL` category values.
- Produces predictable, consistent behavior in `GROUP BY` — e.g. the
  planned "top sellers by revenue" checkpoint query will show a clear
  `'not specified'` row for these 610 products' revenue, rather than a
  blank or tool-dependent rendering of `NULL`.
- Since all 610 products have confirmed real purchases, this data will
  actually surface in reports — an explicit label is more honest and
  usable than silently letting it appear as `NULL`.

## Consequences

- `'not specified'` will appear as a legitimate-looking value in
  `product_category_name`/`product_category_name_english` alongside
  73 real categories — anyone consuming `dim_products` needs to know
  this is a placeholder for missing source data, not a genuine
  73rd/74th category. Worth noting in any README/documentation that
  describes the dimension's category values.
- This only resolves the *display* of missing categories — it does
  not address the separate, still-open cleanup items also found in
  `stg_products` during exploration (the `casa_conforto`/
  `casa_conforto_2` and `eletrodomesticos`/`eletrodomesticos_2`
  near-duplicate category pairs), which remain tracked as known
  cleanup for the SQL transform step.
