# 0002 — dim_customers Grain

**Status:** Accepted

## Context

`stg_customers` contains two different identifier columns:

- `customer_id` — unique per row in `stg_customers` (99,441 unique
  values), and this is also the identifier that appears directly in
  `stg_orders`. It's generated fresh for every order, so a person who
  places 3 orders gets 3 different `customer_id` values.
- `customer_unique_id` — only 96,096 unique values across the same
  99,441 rows. This is the real, stable identifier for one actual
  person, confirmed against Olist's own Kaggle dataset documentation.
  About 3,345 people placed more than one order.

`customer_id` is what's directly available on `stg_orders` (and by
extension `stg_order_items`), making it the "easy" choice to join on
without any extra work. `customer_unique_id` requires an additional
join through `stg_customers` to resolve.

## Options Considered

**Option 1 — build `dim_customers` at `customer_id` grain.** Simple:
no extra join needed anywhere, since `customer_id` is already present
on the order-related staging tables. Trade-off: a real repeat customer
(person who ordered 3 times) would appear as 3 separate, disconnected
rows in `dim_customers` — one per order-instance, not one per person.
Any analysis of genuine customer behavior (repeat purchase rate,
lifetime value per customer, unique customer counts) would be wrong,
since the dimension wouldn't actually represent "a customer," it would
represent "an order's customer-slot."

**Option 2 — build `dim_customers` at `customer_unique_id` grain.**
Matches the real business entity (one row per actual person).
Trade-off: requires resolving `customer_id` → `customer_unique_id` via
a join through `stg_customers` whenever `fact_orders` needs to
reference a customer, since `customer_unique_id` isn't present on the
order-related staging tables directly.

## Decision

**Option 2** — `dim_customers` built at `customer_unique_id` grain.
`fact_orders` will store `customer_unique_id` as its customer foreign
key, resolved via a join through `stg_customers` at build time.

Reasons:
- Matches standard Kimball dimensional modeling principle: a dimension
  should represent the real business entity (a person), not a
  source-system transactional artifact (an order-scoped ID).
- Enables correct customer-level analysis — unique customer counts,
  repeat-purchase behavior, customer lifetime value — none of which
  would be answerable correctly at `customer_id` grain.
- This was flagged as an open question during the initial customers
  exploration phase and is being resolved now, at schema design time,
  as originally planned.

## Consequences

- The `fact_orders` build query needs an explicit join through
  `stg_customers` (on `customer_id`) to resolve each order to its
  `customer_unique_id` before that value can be used as the foreign
  key — this isn't a direct 1:1 pass-through from `stg_orders`.
- `dim_customers` will have fewer rows (96,096) than `stg_customers`
  has raw rows (99,441), since multiple `customer_id` values collapse
  into one `customer_unique_id` row. Attributes that vary per-order in
  `stg_customers` (e.g. `customer_zip_code_prefix`, if a person moved
  between orders) need a documented rule for which value "wins" when
  collapsing to one row per person.

### Address collapse rule (resolved 2026-08-29)

Verified against the real data before deciding: out of 96,096 unique
`customer_unique_id` values, 250 (~0.26%) have more than one
`customer_zip_code_prefix` across their orders, 122 (~0.13%) have more
than one `customer_city`, and 39 (~0.04%) have more than one
`customer_state`. All small — this affects a negligible fraction of
customers regardless of which rule is chosen.

This is an instance of a well-known problem in dimensional modeling —
a **Slowly Changing Dimension (SCD)**: an attribute of a real-world
entity (a person's address) changing over time. The simplest standard
strategy, **SCD Type 1**, is to overwrite with the most recent value
rather than preserve history. Given how small the affected population
is here, preserving full address history (SCD Type 2, which would
require effective-dated rows) isn't justified — **decision: use the
most recent order's address** (`customer_zip_code_prefix`,
`customer_city`, `customer_state` from the row associated with the
person's latest order, resolved via a join to `stg_orders` on
`order_purchase_timestamp`) for the small number of people who have
more than one address on file.
