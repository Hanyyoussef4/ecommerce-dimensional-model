# Star Schema Design

Design decisions with real trade-offs are logged individually in
`notes/decisions/` (ADR format). This file documents the resulting
design itself — the actual table/column structure — not the reasoning
behind each choice. See the linked ADRs for *why*.

## fact_orders

**Grain:** one row per order line item (matches `stg_order_items` —
one product within one order). See
[ADR 0001](decisions/0001-fact-orders-grain-and-payment-handling.md).

**Natural/composite key:** `order_id` + `order_item_id`

**Foreign keys:**

| Column | References | Notes |
|---|---|---|
| `product_key` | `dim_products` | surrogate key, resolved by looking up `product_id` (from `stg_order_items`) against `dim_products` — `product_id` itself does not travel into `fact_orders`. Same fan-out reasoning as `customer_key` below. |
| `seller_key` | `dim_sellers` | surrogate key, resolved by looking up `seller_id` (from `stg_order_items`) against `dim_sellers` — `seller_id` itself does not travel into `fact_orders`. Same fan-out reasoning as `customer_key` below. |
| `customer_key` | `dim_customers` | surrogate key, resolved via join through `stg_customers` (`customer_id` → `customer_unique_id`) then looked up against `dim_customers` — not a direct pass-through of any raw column. See [ADR 0002](decisions/0002-dim-customers-grain.md). |
| `purchase_date_key` | `dim_date` | role-playing date FK |
| `approved_date_key` | `dim_date` | role-playing date FK |
| `delivered_carrier_date_key` | `dim_date` | role-playing date FK |
| `delivered_customer_date_key` | `dim_date` | role-playing date FK |
| `estimated_delivery_date_key` | `dim_date` | role-playing date FK |
| `shipping_limit_date_key` | `dim_date` | role-playing date FK, from `stg_order_items` |
| `first_review_date_key` | `dim_date` | role-playing date FK, `MIN(review_creation_date)` per order — see [ADR 0003](decisions/0003-review-data-handling.md) |
| `most_recent_review_date_key` | `dim_date` | role-playing date FK, `MAX(review_creation_date)` per order — see ADR 0003 |

**Measures:**

| Column | Source | Notes |
|---|---|---|
| `price` | `stg_order_items` | per line item |
| `freight_value` | `stg_order_items` | per line item |
| `total_payment` | `stg_order_payments`, pre-aggregated (`SUM` per order) | repeats across an order's line items — do not blindly `SUM()` across fact rows. See ADR 0001. |
| `review_count` | `stg_order_reviews`, pre-aggregated (`COUNT` per order) | repeats across an order's line items. See ADR 0003. |
| `avg_review_score` | `stg_order_reviews`, pre-aggregated (`AVG` per order) | repeats across an order's line items. See ADR 0003. |
| `min_review_score` | `stg_order_reviews`, pre-aggregated (`MIN` per order) | repeats across an order's line items. See ADR 0003. |
| `max_review_score` | `stg_order_reviews`, pre-aggregated (`MAX` per order) | repeats across an order's line items. See ADR 0003. |

**Degenerate dimension:**

| Column | Source | Notes |
|---|---|---|
| `order_status` | `stg_orders` | low cardinality (8 values), no separate descriptive attributes — kept as a plain column rather than its own dimension table |

**Explicitly excluded from this fact table** (retained in staging,
not lost — see ADR 0003): `review_comment_title`,
`review_comment_message`, and any individual review-level detail
beyond the aggregated score/date measures above.

## dim_customers

**Grain:** one row per real person (`customer_unique_id`), not one row
per order-instance. See [ADR 0002](decisions/0002-dim-customers-grain.md).

**Primary key:** `customer_key` (surrogate, auto-generated integer —
not present in source data). Used instead of `customer_unique_id`
directly as the key that `fact_orders` references, since a dimension
key gets copied into every fact row that points to it (fan-out) — a
small integer is far cheaper to store/join at that scale than a
32-character hash repeated across thousands of `fact_orders` rows.

| Column | Source | Notes |
|---|---|---|
| `customer_key` | generated | surrogate PK, referenced by `fact_orders` |
| `customer_unique_id` | `stg_customers` | natural/business key, kept as a traceable attribute |
| `customer_city` | `stg_customers` | from the person's most recent order — see ADR 0002 address collapse rule (SCD Type 1) |
| `customer_state` | `stg_customers` | from the person's most recent order — see ADR 0002 |
| `customer_zip_code_prefix` | `stg_customers` | from the person's most recent order — see ADR 0002 |

## dim_products

**Grain:** one row per product (`product_id` unique in `stg_products`,
32,951 rows = 32,951 distinct `product_id` — confirmed). 73 distinct
categories; no readable product name exists in the source data
(`product_name_lenght` is a character count of the name, not the name
itself).

**Referential integrity verified:** 0 `product_id` values in
`stg_order_items` are missing from `stg_products` (checked via
`LEFT JOIN` + `WHERE ... IS NULL`) — safe to join without risk of
silently dropped or null line items.

**Primary key:** `product_key` (surrogate, auto-generated integer).
Same fan-out reasoning as `dim_customers`' `customer_key` —
`product_id` is a long hash-format string that would otherwise be
copied into every `fact_orders` row referencing that product.

| Column | Source | Notes |
|---|---|---|
| `product_key` | generated | surrogate PK, referenced by `fact_orders` |
| `product_id` | `stg_products` | natural/business key, kept as a traceable attribute |
| `product_category_name` | `stg_products` | Portuguese category name; known data quality issues not yet cleaned here — see below |
| `product_category_name_english` | `stg_product_category_translation`, joined on category name | denormalized directly in rather than a separate dimension — translation table is small (2 columns) and has no other attributes, so a separate table would just add an unnecessary join (snowflaking) for no real benefit |
| `product_name_lenght` | `stg_products` | character count of the (unstored) product name |
| `product_description_lenght` | `stg_products` | character count of the description |
| `product_photos_qty` | `stg_products` | |
| `product_weight_g` | `stg_products` | |
| `product_length_cm` | `stg_products` | |
| `product_height_cm` | `stg_products` | |
| `product_width_cm` | `stg_products` | |

**Known cleanup needed (handled in SQL transform, not here):**
near-duplicate category pairs (`casa_conforto`/`casa_conforto_2`,
`eletrodomesticos`/`eletrodomesticos_2`); 2 categories missing English
translations (`pc_gamer`,
`portateis_cozinha_e_preparadores_de_alimentos`) — need a documented
fallback (e.g. keep Portuguese name if no translation exists, rather
than a null English column).

**Missing category placeholder (resolved):** 610 products are missing
`product_category_name` entirely — verified (two independent checks)
that all 610 have real purchases in `stg_order_items`, so they cannot
be excluded from `dim_products`. Both `product_category_name` and
`product_category_name_english` are replaced with the literal string
`'not specified'` for these rows rather than left `NULL`. See
[ADR 0004](decisions/0004-dim-products-missing-category-placeholder.md).

## dim_sellers

**Grain:** one row per seller (`seller_id` unique in `stg_sellers`,
3,095 rows = 3,095 distinct `seller_id` — confirmed). No second
identifier column exists (unlike `stg_customers`) — `seller_id` is
the only key this table has.

**Referential integrity verified (both directions):** every seller in
`stg_sellers` has sold at least one item, and every `seller_id`
referenced in `stg_order_items` exists in `stg_sellers` — zero
orphaned rows either way.

**Primary key:** `seller_key` (surrogate, auto-generated integer).
Same fan-out reasoning as `dim_customers`'/`dim_products`' surrogate
keys — `seller_id` is a long hash-format string that would otherwise
be copied into every `fact_orders` row referencing that seller.

| Column | Source | Notes |
|---|---|---|
| `seller_key` | generated | surrogate PK, referenced by `fact_orders` |
| `seller_id` | `stg_sellers` | natural/business key, kept as a traceable attribute |
| `seller_city` | `stg_sellers`, corrected via seed table | see [ADR 0005](decisions/0005-dim-sellers-city-cleanup.md) |
| `seller_state` | `stg_sellers` | |
| `seller_zip_code_prefix` | `stg_sellers` | |

**Known cleanup needed (handled in SQL transform, not here):**
`seller_city` data quality issues across 34 zip prefixes (112 of 3,095
sellers), see `notes/seller_city_anomalies.csv` and
[ADR 0005](decisions/0005-dim-sellers-city-cleanup.md) — resolved via
a manual correction seed table, not yet built.

## dim_geolocation

**Grain:** one row per `zip_code_prefix` (aggregated from `stg_geolocation`,
which has many raw rows per zip — repeated/near-duplicate lat/lng
readings, not one row per zip).

**Primary key:** `zip_code_prefix` (natural key) — no surrogate key.
Unlike `dim_customers`/`dim_products`/`dim_sellers`, `zip_code_prefix`
is already short and cheap to store/join directly, so the fan-out cost
that justifies a surrogate key elsewhere doesn't apply here. Stored as
`TEXT`, not numeric — see [ADR 0006](decisions/0006-zip-code-leading-zero-fix.md).

Connects to `dim_customers`/`dim_sellers` via `zip_code_prefix`, not
directly to `fact_orders`.

| Column | Source | Notes |
|---|---|---|
| `zip_code_prefix` | `stg_geolocation` | natural key, grain of this table |
| `latitude` | `stg_geolocation`, `AVG(geolocation_lat)` per zip | multiple raw readings per zip collapsed to one representative point |
| `longitude` | `stg_geolocation`, `AVG(geolocation_lng)` per zip | same as above |
| `city` | `stg_geolocation`, `MODE() WITHIN GROUP` per zip, after accent/casing normalization | most common city name per zip once accent/casing noise is normalized (e.g. "sao paulo" vs "são paulo") — see known cleanup below |
| `state` | `stg_geolocation`, `MODE() WITHIN GROUP` per zip | most common state per zip |

**Known cleanup needed (handled in SQL transform, not here):**
261,831 exact duplicate rows in `stg_geolocation`, and city name
accent-mark/casing normalization (~25% of apparent city-name variety
in the raw data is noise, not real distinct values — see
`notes/data_exploration.md`) needed before `MODE()` can pick a
meaningful most-common city per zip.

**Referential integrity gap (documented, not an ADR — see reasoning
below):** `stg_geolocation`'s zip coverage is incomplete relative to
`stg_customers`/`stg_sellers`. Checked both directions via
`LEFT JOIN` + `WHERE geolocation_state IS NULL`:

- `stg_customers`: 278 of 99,441 rows (157 distinct zip prefixes) have
  no matching `zip_code_prefix` in `stg_geolocation`.
- `stg_sellers`: 7 of 3,095 rows (7 distinct zip prefixes) have no
  match.

Confirmed this is a coverage gap, not a data quality bug — the
missing zips belong to real, legitimate cities (e.g. Brasília, Sinop,
Teresina, Poços de Caldas, Curitiba, Porto Alegre, São Paulo, Arujá).
`stg_geolocation` is Olist's standalone zip-to-coordinates reference
table (released to support mapping/distance calculations), not
derived from the orders data itself, so it isn't guaranteed to cover
every zip that happens to appear in this specific dataset.

Low impact either way: `dim_customers`/`dim_sellers` already carry
their own `city`/`state`/`zip_code_prefix` directly from
`stg_customers`/`stg_sellers`, so this gap only affects `latitude`/
`longitude` enrichment for the affected rows, not city/state itself.

**Decision:** any join from `dim_customers`/`dim_sellers` to
`dim_geolocation` must use `LEFT JOIN`, leaving `latitude`/`longitude`
`NULL` for unmatched rows rather than dropping those customers/sellers
from the result or fabricating approximate coordinates (e.g. a
state-level centroid). Kept as a documented note rather than a
standalone ADR — the reasoning is non-obvious from the code alone, but
the decision itself is low-blast-radius and cheap to reverse (a single
join clause), unlike grain or key-strategy decisions.

## dim_date

**Grain:** one row per calendar date, plus 2 dedicated placeholder
rows (see below). Referenced 8 times by `fact_orders` as a
role-playing dimension (purchase, approved, delivered_carrier,
delivered_customer, estimated_delivery, shipping_limit, first_review,
most_recent_review dates — see `fact_orders` table above).

**Primary key:** `date_key`, a surrogate integer in `YYYYMMDD` format
(e.g. `20170315`) — not the native `DATE` type, despite `DATE` being a
cheap natural key like `zip_code_prefix`. See
[ADR 0007](decisions/0007-dim-date-key-strategy-and-placeholders.md)
for why: several `fact_orders` date columns are legitimately `NULL`
for real lifecycle reasons (e.g. undelivered orders have no
`delivered_customer_date` yet), and a `NULL` foreign key causes
`INNER JOIN` to silently drop those fact rows. A surrogate key allows
dedicated placeholder rows instead.

**Date range:** `2016-09-04` to `2018-11-12` — the true overall
min/max across all 7 underlying source date columns (`stg_orders` x5,
`stg_order_items.shipping_limit_date`,
`stg_order_reviews.review_creation_date`), checked via a `UNION ALL`
of per-column `MIN`/`MAX` wrapped in a CTE. Deliberately generated for
this exact range rather than an arbitrary wide range (e.g. covering
future years), since this is a one-time load of a static historical
dataset that won't receive new data — see ADR 0007.

**Placeholder rows (see ADR 0007):**

| date_key | full_date | Meaning |
|---|---|---|
| `-1` | `NULL` | Not applicable / hasn't happened yet (e.g. order not yet delivered, no review submitted) |
| `-2` | `NULL` | Value present in source but known invalid — used only for the 4 corrupted `shipping_limit_date` rows in `stg_order_items` (each dated ~2020, years after the same order's own delivery date — confirmed data entry errors, not real dates) |

| Column | Source | Notes |
|---|---|---|
| `date_key` | generated | surrogate PK, `YYYYMMDD` format |
| `full_date` | generated | the actual calendar date (`NULL` for the 2 placeholder rows) |
| `year` | generated, derived from `full_date` | |
| `quarter` | generated, derived from `full_date` | |
| `month` | generated, derived from `full_date` | |
| `week_number` | generated, derived from `full_date` | |
| `day_of_week` | generated, derived from `full_date` | stored as a name (e.g. `'Monday'`), not a number |
