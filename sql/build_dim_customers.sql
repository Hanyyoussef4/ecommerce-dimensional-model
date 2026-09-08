
-- Builds dim_customers from stg_customers + stg_orders.
-- - Grain is one row per real person (customer_unique_id), not per order
--   (customer_id is per-order in the source data) -- see ADR 0002.
-- - Address (city/state/zip) is taken from each person's MOST RECENT order,
--   not an arbitrary one, per the SCD Type 1 collapse rule in ADR 0002 --
--   see comment below near the window function for how "most recent" is
--   resolved deterministically.
-- - customer_key uses GENERATED ALWAYS AS IDENTITY, not ROW_NUMBER(), so
--   keys stay stable if this table is ever reloaded (see ADR 0008).

create table dim_customers (

  	customer_key INTEGER generated always as identity primary key,
	customer_unique_id TEXT unique,
	customer_city TEXT,
	customer_state TEXT,
	customer_zip_code_prefix TEXT
);


with cst_table as (

	select *,
	
	-- ROW_NUMBER() ranks each customer's orders from most recent to oldest.
	-- order_id DESC is a tiebreaker for the rare case where two orders from
	-- the same customer share the exact same purchase timestamp -- without
	-- it, which row ranks first would be arbitrary/non-deterministic and
	-- could change between runs on the same data.
		row_number() over(
		partition by customer_unique_id
		order by order_purchase_timestamp desc,
		order_id DESC
		)as row_num
	
	from stg_customers c
	inner join stg_orders o on c.customer_id = o.customer_id
)

insert into dim_customers (

	customer_unique_id,
	customer_city,
	customer_state,
	customer_zip_code_prefix
)

select
	customer_unique_id,
	customer_city,
	customer_state,
	customer_zip_code_prefix
from cst_table
where row_num = 1; --Filter CTE result to first rows only order by order_purchase_timestamp DESC (only most recent order date)

-- Verify no rows were lost or duplicated: should equal 96,096, the
-- confirmed distinct customer_unique_id count in stg_customers.

select count(*) from dim_customers;

		
