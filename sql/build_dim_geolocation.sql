-- Builds dim_geolocation from stg_geolocation + seed_geolocation_city_corrections.
-- - Grain is one row per zip_code_prefix (19,015 distinct values),
--   aggregated from stg_geolocation which has ~1M raw rows -- many
--   repeated/near-duplicate lat/lng readings per zip, not one row per
--   zip -- see notes/schema_design.md dim_geolocation section.
-- - Primary key is zip_code_prefix itself (natural key, TEXT), not a
--   surrogate -- unlike dim_customers/dim_products/dim_sellers, the
--   zip prefix is already short and cheap to join directly, so the
--   fan-out cost that justifies a surrogate key elsewhere doesn't
--   apply here.
-- - City normalization + correction follows ADR 0009: unaccent() +
--   LOWER() resolves ~25% of apparent city-name duplication
--   automatically (accent/casing noise), then a LEFT JOIN + COALESCE
--   against seed_geolocation_city_corrections (13 rows) fixes the
--   genuine leftover corruption (HTML entities, charset mis-decodes,
--   full-address-as-city values) that normalization alone can't
--   catch. The seed table is matched against the *normalized* text,
--   not the raw geolocation_city column.
-- - Two chained CTEs do the row-level cleanup (normalize, then
--   correct) before the final aggregation collapses many raw rows
--   per zip into one: AVG() for latitude/longitude (a representative
--   point), MODE() WITHIN GROUP for city/state (the most common
--   value per zip, since text can't be averaged).

create table dim_geolocation (

	zip_code_prefix text primary key,
	latitude numeric,
	longitude numeric,
	city text,
	state text
);


with normalized as (

	-- Step 1: pull the raw columns, normalizing geolocation_city
	-- (lowercase + strip accents) so it can be matched against the
	-- seed correction table's already-normalized raw_value column.
	select
		geolocation_zip_code_prefix as zip_code_prefix,
		geolocation_lat,
		geolocation_lng,
		unaccent(lower(geolocation_city)) as normalized_city,
		geolocation_state
	from stg_geolocation
),

corrected as (

	-- Step 2: apply the manual correction seed table on top of the
	-- normalized city text. LEFT JOIN keeps every row even though
	-- only a small fraction match a correction; COALESCE falls back
	-- to the normalized city when no correction exists.
	select
		n.zip_code_prefix,
		n.geolocation_lat,
		n.geolocation_lng,
		COALESCE(se.corrected_value, n.normalized_city) as city,
		n.geolocation_state
	from normalized n
	left join seed_geolocation_city_corrections se
		on n.normalized_city = se.raw_value
)

-- Step 3: collapse the many cleaned rows per zip down to one row per
-- zip (the required grain) -- AVG() for the numeric lat/lng columns,
-- MODE() WITHIN GROUP for the most common city/state text per zip.
insert into dim_geolocation (

	zip_code_prefix,
	latitude,
	longitude,
	city,
	state
)

select
	zip_code_prefix,
	AVG(geolocation_lat) as latitude,
	AVG(geolocation_lng) as longitude,
	MODE() WITHIN GROUP (order by city) as city,
	MODE() WITHIN GROUP (order by geolocation_state) as state
from corrected
group by zip_code_prefix;

-- Verify no zips were lost or duplicated: should equal 19,015, the
-- confirmed distinct geolocation_zip_code_prefix count in stg_geolocation.

select count(*) from dim_geolocation;