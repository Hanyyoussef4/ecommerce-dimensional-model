# 0001 — fact_orders Grain and Payment Handling

**Status:** Accepted

## Context

`fact_orders` needs to be built from four staging tables that each have a
different natural grain:

- `stg_orders` — one row per order (99,441 rows, `order_id` unique)
- `stg_order_items` — one row per product line within an order (112,650
  rows, `order_id` repeats — an order can contain multiple products)
- `stg_order_payments` — one row per payment entry within an order
  (103,886 rows, `order_id` repeats — an order can be paid via multiple
  payment records)
- `stg_order_reviews` — one row per review (99,224 rows, a small number
  of orders have more than one review)

Joining tables of different grains without care causes a **fan-out**:
if a line-item-grain table (3 rows for one order) is joined directly to
a payment-grain table for the same order (2 rows), the join produces
3 × 2 = 6 rows, and any `SUM()` over the payment column after that join
overcounts the true payment total (e.g. a true $45 total payment reads
as $135 — exactly 3x too much, matching the number of line items).

## Options Considered

**Option 1 — separate fact tables per grain.** Build `fact_order_items`
(line-item grain), `fact_order_payments` (payment grain), and
potentially `fact_order_reviews` (review grain) as independent fact
tables, each joining out to shared dimensions. No fan-out risk within
any single table, since each stays at its own true grain. Trade-off:
more tables, and any report that needs to combine products with
payments requires a join across fact tables at query time. Also departs
from the single `fact_orders` design already sketched in the project
README.

**Option 2 — single `fact_orders` table at line-item grain, with
payments pre-aggregated before joining.** Collapse
`stg_order_payments` to one row per order first
(`GROUP BY order_id, SUM(payment_value)`), producing exactly one
payment total per order, then join that pre-aggregated result onto the
line-item-grain fact table. No fan-out, because the sum happens before
the join, not after. Trade-off: the resulting `total_payment` column
repeats identically across every line item of the same order, so it
must never be blindly `SUM()`-ed across fact table rows — only
referenced once per order (e.g. via `DISTINCT` or by rolling back up
with `GROUP BY order_id`).

## Decision

**Option 2** — single `fact_orders` table, line-item grain
(`order_id` + `order_item_id` as the natural key), with
`stg_order_payments` pre-aggregated to order level via a CTE/subquery
before being joined in.

Reasons:
- Matches the single-fact-table design already committed to in the
  project README, rather than introducing new scope.
- Directly practices the CTE/subquery skill this project exists to
  build — pre-aggregating payments before the join is a textbook use
  case. Option 1 would not have required this step.
- Fits the planned checkpoint queries (top sellers by revenue,
  above-average order value customers), which need product/seller
  detail and payment totals available together without cross-fact-table
  joins.
- Matches common real-world practice at small-to-medium warehouse
  scale; Option 1's per-process fact table split tends to appear at
  larger orgs where payments and orders are owned by genuinely separate
  business processes/teams, which isn't the case here.

## Consequences

- `total_payment` (and any other order-level measure attached this way)
  is a repeated value across a given order's line items in
  `fact_orders`. Any query aggregating this column must account for
  that — e.g. `SUM(DISTINCT ...)` won't work reliably either, since
  distinct payment totals could coincidentally match across different
  orders; the safe approach is to aggregate back to order level first
  (`GROUP BY order_id`) before summing payment totals across orders.
- `stg_order_reviews` has the same order-vs-line-item grain mismatch as
  payments (547 orders have more than one review) and hasn't been
  resolved yet — this needs its own decision, likely following the same
  pre-aggregation pattern or a documented rule for picking one review
  per order (e.g. most recent). Tracked as a follow-up, not yet an ADR.
- If a future reporting need requires payment-level detail (e.g.
  payment method mix, installment analysis) that line-item-grain
  `fact_orders` can't answer, that would be a trigger to revisit this
  decision and add `fact_order_payments` as an additional fact table
  (Option 1), without needing to change `fact_orders` itself.
