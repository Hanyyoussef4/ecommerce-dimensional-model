-- Checkpoint query 2 -- Month-over-month order trends.
-- - Demonstrates: two chained CTEs.
-- - monthly_orders: collapses fact_orders (order-line-item grain)
--   down to one row per calendar month. Joins on purchase_date_key
--   specifically -- the date the order was actually placed -- not
--   approved/delivered/review dates, which measure different
--   lifecycle events and would answer a different question.
--   COUNT(DISTINCT order_id), not COUNT(*), avoids double-counting
--   orders that have multiple line items.
-- - previous_month_orders_table: adds prev_month_orders via LAG(),
--   ordered chronologically across the whole series (no PARTITION
--   BY -- partitioning by year/month would wall off every month into
--   its own 1-row group, leaving LAG() nothing to look back at within
--   a group of one).
-- - Final SELECT computes mom_pct_change from the already-materialized
--   prev_month_orders column (no repeated LAG() call needed, unlike
--   total_revenue in checkpoint 1 -- that's the point of chaining a
--   second CTE instead of a single flat query).
-- - The ::numeric cast on the numerator is required, not optional:
--   COUNT() returns bigint, and Postgres performs integer division
--   (silently truncating toward zero) when dividing two bigint
--   values -- discarding the decimal portion before it can ever be
--   scaled by 100 or rounded. Confirmed by hand-checking against
--   manual calculations, e.g. 2017-02 -> 2017-03:
--   (2,641 - 1,733) / 1,733 * 100 = 52.39%, matching this query's
--   output exactly. Without the cast, the same row silently
--   computed 0%.
-- - First row (2016-09, the earliest month) correctly shows NULL for
--   both prev_month_orders and mom_pct_change -- there is no prior
--   month to compare against.

with monthly_orders as (
    select
        d.year,
        d.month,
        count(distinct f.order_id) as total_orders_count
    from fact_orders f
    join dim_date d on f.purchase_date_key = d.date_key
    group by d.year, d.month
),
previous_month_orders_table as (
    select
        m.*,
        lag(total_orders_count) over (order by year, month) as prev_month_orders
    from monthly_orders m
)
select
    *,
    round(((total_orders_count - prev_month_orders)::numeric / prev_month_orders) * 100, 2) as mom_pct_change
from previous_month_orders_table
order by year, month;
