-- Builds fact_orders from stg_order_items + stg_orders + stg_customers
-- + dim_customers/dim_products/dim_sellers/dim_date, plus two
-- pre-aggregation CTEs for payments and reviews.
-- - Grain is one row per order line item, matching stg_order_items
--   exactly (112,650 rows) -- see ADR 0001.
-- - Natural/composite key: order_id + order_item_id.
-- - customer_key is resolved via a two-hop join (stg_orders.customer_id
--   -> stg_customers.customer_unique_id -> dim_customers), since
--   dim_customers is keyed by the real-person ID, not the per-order ID
--   -- see ADR 0002. product_key/seller_key are direct single-hop
--   lookups.
-- - payment_agg and review_agg pre-aggregate stg_order_payments and
--   stg_order_reviews to one row per order_id before joining in,
--   since both source tables can have multiple rows per order (split
--   payments, multiple reviews) but fact_orders' grain is per line
--   item, not per order -- see ADR 0001/ADR 0003. Both are LEFT
--   JOINed since not every order has payment/review rows.
-- - All 8 date roles resolve to dim_date via LEFT JOIN + COALESCE:
--   convert the raw timestamp to a YYYYMMDD integer, look it up
--   against dim_date, and fall back to date_key -1 ("not applicable")
--   if no match exists (e.g. undelivered orders have no
--   delivered_customer_date). shipping_limit_date_key has one special
--   case: 4 known-corrupted values (real dates, but outside dim_date's
--   generated range) resolve to -2 ("known invalid") instead of -1,
--   per ADR 0007.
-- - Found and fixed a real load-hygiene bug while building this: all
--   8 date/timestamp source columns were stored as TEXT in staging,
--   not a real date type, because the original loader had no
--   parse_dates argument. Fixed in scripts/load_raw_to_postgres.py
--   and the 3 affected staging tables reloaded -- see ADR 0010.
-- - Verified: 112,650 rows (exact match to stg_order_items), zero
--   NULLs across all 8 date-key columns, and exactly 4 rows with
--   shipping_limit_date_key = -2 (matching ADR 0007's documented
--   corrupted-row count).

create table fact_orders (

	order_id text,
	order_item_id integer,
	product_key integer,
	seller_key integer,
	customer_key integer,
	purchase_date_key integer,
	approved_date_key integer,
	delivered_carrier_date_key integer,
	delivered_customer_date_key integer,
	estimated_delivery_date_key integer,
	shipping_limit_date_key integer,
	first_review_date_key integer,
	most_recent_review_date_key integer,
	price numeric,
	freight_value numeric,
	total_payment numeric,
	review_count integer,
	avg_review_score numeric,
	min_review_score numeric,
	max_review_score numeric,
	order_status text,
	primary key (order_id, order_item_id)
);


with payment_agg as (
    select order_id, sum(payment_value) as total_payment
    from stg_order_payments
    group by order_id
),

review_agg as (
    select
        order_id,
        COUNT(*) as review_count,
        avg(review_score) as avg_review_score,
        min(review_score) as min_review_score,
        max(review_score) as max_review_score,
        min(review_creation_date) as first_review_date,
        max(review_creation_date) as most_recent_review_date
    from stg_order_reviews
    group by order_id
)

insert into fact_orders (
	order_id, order_item_id, product_key, seller_key, customer_key,
	purchase_date_key, approved_date_key, delivered_carrier_date_key,
	delivered_customer_date_key, estimated_delivery_date_key,
	shipping_limit_date_key, first_review_date_key, most_recent_review_date_key,
	price, freight_value, total_payment, review_count,
	avg_review_score, min_review_score, max_review_score, order_status
)

select
	oi.order_id,
	oi.order_item_id,
	dp.product_key,
	ds.seller_key,
	dc.customer_key,
	COALESCE(dd_purchase.date_key, -1) as purchase_date_key,
	COALESCE(dd_approved.date_key, -1) as approved_date_key,
	COALESCE(dd_delivered_carrier.date_key, -1) as delivered_carrier_date_key,
	COALESCE(dd_delivered_customer.date_key, -1) as delivered_customer_date_key,
	COALESCE(dd_estimated.date_key, -1) as estimated_delivery_date_key,
	CASE
		WHEN oi.shipping_limit_date IS NOT NULL AND dd_shipping.date_key IS NULL
			THEN -2
		ELSE COALESCE(dd_shipping.date_key, -1)
	END as shipping_limit_date_key,
	COALESCE(dd_first_review.date_key, -1) as first_review_date_key,
	COALESCE(dd_most_recent_review.date_key, -1) as most_recent_review_date_key,
	oi.price,
	oi.freight_value,
	pa.total_payment,
	ra.review_count,
	ra.avg_review_score,
	ra.min_review_score,
	ra.max_review_score,
	o.order_status

from stg_order_items oi
join stg_orders o on oi.order_id = o.order_id
join stg_customers c on o.customer_id = c.customer_id
join dim_customers dc on c.customer_unique_id = dc.customer_unique_id
join dim_products dp on oi.product_id = dp.product_id
join dim_sellers ds on oi.seller_id = ds.seller_id
left join payment_agg pa on oi.order_id = pa.order_id
left join review_agg ra on oi.order_id = ra.order_id
left join dim_date dd_purchase on TO_CHAR(o.order_purchase_timestamp, 'YYYYMMDD')::integer = dd_purchase.date_key
left join dim_date dd_approved on TO_CHAR(o.order_approved_at, 'YYYYMMDD')::integer = dd_approved.date_key
left join dim_date dd_delivered_carrier on
