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
| `product_id` | `dim_products` | direct from `stg_order_items` |
| `seller_id` | `dim_sellers` | direct from `stg_order_items` |
| `customer_unique_id` | `dim_customers` | resolved via join through `stg_customers` on `customer_id` — not a direct pass-through. See [ADR 0002](decisions/0002-dim-customers-grain.md). |
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

*(Not yet designed — includes known cleanup needed from exploration:
near-duplicate category pairs `casa_conforto`/`casa_conforto_2`,
`eletrodomesticos`/`eletrodomesticos_2`; 2 categories missing English
translations.)*

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
