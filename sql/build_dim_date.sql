-- Builds dim_date via generate_series(), not from a staging table --
-- this is the one dimension with no direct source table, since a
-- calendar doesn't come from anywhere but a date-generating function.
-- - Grain is one row per calendar date, plus 2 dedicated placeholder
--   rows -- see notes/schema_design.md dim_date section. Referenced
--   8 times by fact_orders as a role-playing dimension (purchase,
--   approved, delivered_carrier, delivered_customer,
--   estimated_delivery, shipping_limit, first_review, and
--   most_recent_review dates).
-- - date_key is a surrogate integer in YYYYMMDD format (e.g.
--   20170315), computed from the date itself -- not GENERATED ALWAYS
--   AS IDENTITY like the other dimensions' surrogate keys, and not a
--   native DATE either. See ADR 0007: several fact_orders date
--   columns are legitimately NULL for real lifecycle reasons (e.g.
--   undelivered orders have no delivered_customer_date yet), and a
--   NULL foreign key would cause INNER JOIN to silently drop those
--   fact rows. A surrogate key allows dedicated placeholder rows
--   instead of NULL.
-- - Date range 2016-09-04 to 2018-11-12 is the true overall min/max
--   across all 7 underlying source date columns, established during
--   design (see ADR 0007) -- generated with generate_series(), not an
--   arbitrary wide range, since this is a one-time load of a static
--   historical dataset.
-- - Placeholder rows (see ADR 0007): date_key -1 = not applicable /
--   hasn't happened yet; date_key -2 = a value was present in the
--   source but known-invalid (the 4 corrupted shipping_limit_date
--   rows found during exploration). Both added via UNION ALL, since
--   they have no real date and aren't part of the generated calendar.

create table dim_date (

	date_key integer primary key,
	full_date date,
	year integer,
	quarter integer,
	month integer,
	week_number integer,
	day_of_week text
);

insert into dim_date (date_key, full_date, year, quarter, month, week_number, day_of_week)

select
	TO_CHAR(d, 'YYYYMMDD')::integer as date_key,
	d as full_date,
	EXTRACT(year from d) as year,
	EXTRACT(quarter from d) as quarter,
	EXTRACT(month from d) as month,
	EXTRACT(week from d) as week_number,
	TO_CHAR(d, 'FMDay') as day_of_week
from generate_series('2016-09-04'::date, '2018-11-12'::date, '1 day'::interval) as d

union all

select -1, NULL, NULL, NULL, NULL, NULL, NULL   -- placeholder: not applicable / hasn't happened yet
union all
select -2, NULL, NULL, NULL, NULL, NULL, NULL;  -- placeholder: known-invalid date in source

-- Verify no dates were lost or duplicated: should equal 802 (800
-- calendar days in range + 2 placeholder rows).

select count(*) from dim_date;