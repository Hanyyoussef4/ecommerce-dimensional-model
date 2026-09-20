-- Checkpoint query 1 -- Top 10 sellers by total revenue.
-- - Demonstrates: window function (DENSE_RANK()).
-- - Revenue = SUM(f.price) per seller -- the line-item sale price,
--   not freight_value or total_payment (which includes freight and
--   is split across payment installments, not a clean per-seller
--   revenue figure).
-- - DENSE_RANK() ranks by total_revenue directly -- the alias
--   total_revenue can't be reused inside the same SELECT list's
--   OVER(), so the underlying SUM(f.price) expression is repeated
--   inside ORDER BY.
-- - DENSE_RANK() chosen over RANK(): if two sellers ever tied on
--   revenue, DENSE_RANK() would rank the next seller immediately
--   after (no skipped numbers), reading more naturally as "revenue
--   tier" than RANK()'s "sellers ahead of or tied with you" gap
--   behavior. No ties actually occur in this dataset, so the choice
--   doesn't change the result here, but it's the more defensible
--   default.
-- - Verified: 10 rows returned, revenue_rank running 1-10 with no
--   gaps, sorted descending by total_revenue.

select
    s.seller_id,
    s.seller_city,
    s.seller_state,
    SUM(f.price) as total_revenue,
    dense_rank() over (order by sum(f.price) desc) as revenue_rank
from fact_orders f
join dim_sellers s on f.seller_key = s.seller_key
group by s.seller_id, s.seller_city, s.seller_state
order by total_revenue desc
limit 10;
