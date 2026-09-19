-- Adds FK constraints from fact_orders to its 4 dimension tables (11
-- constraints total: product_key, seller_key, customer_key, plus 8
-- separate references to dim_date -- one per date-role column, since
-- dim_date is a role-playing dimension reused 8 times for 8 distinct
-- date facts per order line item).
-- - Run after fact_orders is fully built and verified -- adding these
--   up front would reject any row where a lookup key doesn't resolve,
--   which is exactly what the placeholder-key strategy (ADR 0007) is
--   designed to prevent from happening during the build itself.
-- - The 8 dim_date constraints are only possible because every
--   date-key column is guaranteed non-null and always resolves to a
--   real row in dim_date -- including the -1 ("not applicable") and
--   -2 ("known-invalid date") placeholder rows added specifically so
--   these columns could be NOT NULL / FK-constrained without needing
--   to allow NULLs. See ADR 0007.
-- - dim_geolocation has no FK from fact_orders -- it isn't part of the
--   fact table's grain; it's referenced independently via zip code by
--   dim_customers/dim_sellers' zip columns, not joined at the order
--   line item level.

alter table fact_orders
    add constraint fk_fact_orders_product foreign key (product_key) references dim_products(product_key),
    add constraint fk_fact_orders_seller foreign key (seller_key) references dim_sellers(seller_key),
    add constraint fk_fact_orders_customer foreign key (customer_key) references dim_customers(customer_key),
    add constraint fk_fact_orders_purchase_date foreign key (purchase_date_key) references dim_date(date_key),
    add constraint fk_fact_orders_approved_date foreign key (approved_date_key) references dim_date(date_key),
    add constraint fk_fact_orders_delivered_carrier_date foreign key (delivered_carrier_date_key) references dim_date(date_key),
    add constraint fk_fact_orders_delivered_customer_date foreign key (delivered_customer_date_key) references dim_date(date_key),
    add constraint fk_fact_orders_estimated_delivery_date foreign key (estimated_delivery_date_key) references dim_date(date_key),
    add constraint fk_fact_orders_shipping_limit_date foreign key (shipping_limit_date_key) references dim_date(date_key),
    add constraint fk_fact_orders_first_review_date foreign key (first_review_date_key) references dim_date(date_key),
    add constraint fk_fact_orders_most_recent_review_date foreign key (most_recent_review_date_key) references dim_date(date_key);