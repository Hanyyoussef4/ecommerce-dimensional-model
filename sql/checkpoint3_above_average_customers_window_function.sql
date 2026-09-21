-- Checkpoint query 3 (alternate version) -- same result as
-- checkpoint3_above_average_customers_subquery.sql, built with
-- window functions instead of GROUP BY + a scalar subquery. Kept
-- alongside the subquery version deliberately, to show both
-- techniques solving the same problem.
-- - A window function can't be referenced inside a WHERE clause in
--   the same query -- WHERE evaluates before window functions do,
--   same evaluation-order rule that applies to SELECT-list aliases
--   (see checkpoint 1 / checkpoint 2 comments). So this version has
--   to compute the window functions in a CTE first, then filter the
--   CTE's *output* in an outer SELECT, rather than filtering inline
--   the way the subquery version does.
-- - avg(total_price_per_order) over (partition by customer_key)
--   computes each customer's average order value without collapsing
--   rows. avg(total_price_per_order) over () -- no PARTITION BY --
--   computes the same single overall average as the subquery
--   version's scalar subquery, just repeated identically on every
--   row instead of computed once.
-- - SELECT DISTINCT is required here specifically because window
--   functions never reduce row count. Without it, a qualifying
--   customer with N orders would appear N identical times in the
--   result, since avg_table is still built at order grain underneath
--   the window functions.
-- - In practice, prefer the subquery version -- it's simpler, needs
--   no DISTINCT workaround, and matches what this checkpoint is
--   actually meant to demonstrate.

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
avg_table as (
    select distinct
        customer_key,
        avg(total_price_per_order) over (partition by customer_key) as avg_order_value_per_customer,
        avg(total_price_per_order) over () as overall_avg
    from order_grain
)
select *
from avg_table
where avg_order_value_per_customer > overall_avg
order by avg_order_value_per_customer desc;
