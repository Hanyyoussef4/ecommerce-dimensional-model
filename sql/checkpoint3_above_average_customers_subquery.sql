-- Checkpoint query 3 -- Customers whose average order value is above
-- the overall average order value across all orders.
-- - Demonstrates: subquery (a scalar subquery inside a WHERE clause).
-- - order_grain: collapses fact_orders (order-line-item grain) down
--   to one row per order via SUM(price) -- same grain-first pattern
--   as checkpoint 2. Averaging raw line-item price instead of
--   order-level totals would measure something different (item
--   price, not order value).
-- - customer_grain: collapses order_grain further, from order grain
--   to customer grain, via GROUP BY customer_key. avg_total_per_cust
--   is each customer's own average order value across all their
--   orders; total_price_per_cust (lifetime spend) is included
--   alongside it for context, even though only the average is used
--   in the filter below.
-- - The WHERE clause's subquery computes the overall average order
--   value as a single scalar -- no GROUP BY inside it, since a
--   scalar subquery used in a comparison must return exactly one
--   row/value. It queries order_grain (order grain), not
--   customer_grain, so every order counts equally toward the overall
--   average rather than every customer counting equally regardless
--   of how many orders they placed.
-- - Note: many qualifying customers show total_price_per_cust equal
--   to avg_total_per_cust -- expected, not a bug. That happens
--   whenever a customer placed exactly one order (the sum of one
--   value equals the average of one value), and a large share of
--   this dataset's customers are one-time buyers, a known
--   characteristic of the Olist dataset.
-- - See checkpoint3_above_average_customers_window_function.sql for
--   an equivalent version built with window functions instead --
--   same result, different technique, kept for comparison.
-- - overall_avg is included in the SELECT list too (same subquery,
--   repeated), purely so the output is self-documenting -- readers
--   can see both a customer's average and the benchmark it's being
--   compared against without running a separate query. It's a
--   non-correlated subquery, so Postgres only evaluates it once and
--   reuses the result, not once per output row.

with order_grain as (
    select
        customer_key,
        order_id,
        count(order_item_id) as total_items,
        sum(price) as total_price_per_order,
        avg(price) as avg_price_per_order
    from fact_orders
    group by customer_key, order_id
),
customer_grain as (
    select
        customer_key,
        sum(total_price_per_order) as total_price_per_cust,
        avg(total_price_per_order) as avg_total_per_cust
    from order_grain
    group by customer_key
)
select
    *,
    round((select avg(total_price_per_order) from order_grain), 2) as overall_avg
from customer_grain
where avg_total_per_cust > (
    select avg(total_price_per_order)
    from order_grain
)
order by avg_total_per_cust desc;
