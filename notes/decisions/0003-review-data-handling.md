# 0003 — Review Data Handling in fact_orders

**Status:** Accepted

## Context

`stg_order_reviews` has the same order-vs-line-item grain mismatch
already identified for payments in ADR 0001: it's order-grain
(one row per review), but 547 orders have more than one review
(543 with 2, 4 with 3) — confirmed during exploration, with real
examples showing genuinely mixed causes (a follow-up review days
later with a changed score, a likely technical duplicate submitted
41 seconds apart, and an escalating complaint where the score dropped
from 3 to 1 over time). Joining this directly onto the line-item-grain
`fact_orders` would cause the same fan-out problem solved for payments.

Unlike payments, `review_score` is not a naturally additive value —
summing review scores across an order doesn't mean anything the way
summing payment amounts does. `stg_order_reviews` also contains free
text (`review_comment_title`, `review_comment_message`) which cannot
be aggregated numerically at all.

## Options Considered

**Option 1 — separate `fact_order_reviews` table at review grain.**
Preserves full fidelity: every individual review, its exact score,
comment text, and timestamps, with no information loss. Structurally
identical to Option 1 from ADR 0001 (fact table per grain). Trade-off:
another fact table to maintain and join, for a use case (individual
review detail / free-text analysis) that isn't currently needed by any
planned checkpoint query.

**Option 2 — pre-aggregate reviews to one row per order before
joining into `fact_orders`.** Collapse `stg_order_reviews` via
`GROUP BY order_id` into summary measures: `review_count`,
`avg_review_score`, `min_review_score`, `max_review_score`, plus two
role-playing date keys (`first_review_date_key` =
`MIN(review_creation_date)`, `most_recent_review_date_key` =
`MAX(review_creation_date)`) referencing `dim_date`. Free text columns
(`review_comment_title`, `review_comment_message`) are dropped
entirely — there is no meaningful way to aggregate free text down to
one value per order.

## Decision

**Option 2** — pre-aggregate reviews into `fact_orders` as summary
measures and two role-playing date keys; free-text review columns are
excluded from the star schema.

Reasons:
- Consistent with the payment-handling decision in ADR 0001 — same
  grain-mismatch problem, same resolution pattern (aggregate before
  join), rather than introducing a new pattern for a similar situation.
- `min`/`max`/`avg`/`count` together preserve meaningful signal that a
  single "pick one review" rule would lose — e.g. the min/max spread
  still surfaces cases like the escalating-complaint example found
  during exploration, even after collapsing to one row per order.
- None of the three planned checkpoint queries (top sellers by
  revenue, month-over-month order trends, above-average order value
  customers) require individual review text or exact per-review
  detail — building `fact_order_reviews` now would add maintenance
  scope without serving a concrete, current need.

## Consequences

- Free-text review content (`review_comment_title`,
  `review_comment_message`) and individual review-level detail (which
  specific review had which score, exact single timestamp) will not
  exist in the curated star schema layer (`fact_orders` and the
  dimension tables) — only order-level summary signal
  (min/avg/max/count of score, first/most-recent review date)
  survives at that layer.
- **This is not data loss.** The raw data remains fully intact in
  `stg_order_reviews`, unchanged, in Postgres — nothing about building
  `fact_orders` touches or removes it. This follows a standard
  raw/curated layering pattern (sometimes called a medallion
  architecture: raw/staging → cleaned → curated marts): the staging
  layer is kept as a permanent, complete record, while the star schema
  is a purpose-built model scoped to *currently known* analytical
  needs. If a future need arises for text-level analysis (e.g.
  sentiment analysis on review comments) or individual review detail,
  a new model (e.g. a separate `fact_order_reviews`) can be built
  directly from `stg_order_reviews` at that time — this decision only
  scopes what's in the curated layer today, it doesn't foreclose
  future work.
- `avg_review_score`, like `total_payment` from ADR 0001, is a
  measure computed once per order but will repeat across that order's
  multiple line items in `fact_orders` (line-item grain) — must not be
  blindly re-aggregated (e.g. summed) across fact table rows without
  first rolling back up to one row per order.
