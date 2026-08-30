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

## dim_sellers

*(Not yet designed — includes known cleanup needed from exploration:
`seller_city` data quality issues across 34 zip prefixes, see
`notes/seller_city_anomalies.csv`.)*

## dim_geolocation

*(Not yet designed — includes known cleanup needed from exploration:
261,831 exact duplicate rows, city name accent/casing normalization.
Connects to `dim_customers`/`dim_sellers`, not directly to
`fact_orders`.)*

## dim_date

*(Not yet designed — day grain, one row per calendar date, with
month/quarter/year and similar attributes as columns. Referenced
multiple times by `fact_orders` as a role-playing dimension — see
table above.)*
