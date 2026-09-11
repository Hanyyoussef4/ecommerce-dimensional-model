
-- Builds dim_sellers from stg_sellers + seed_seller_city_corrections.
-- - Grain is one row per seller (seller_id unique in stg_sellers, 3,095
--   rows) -- see notes/schema_design.md dim_sellers section.
-- - seller_key uses GENERATED ALWAYS AS IDENTITY, not ROW_NUMBER(), so
--   keys stay stable if this table is ever reloaded (see ADR 0008).
-- - seller_city is corrected via LEFT JOIN + COALESCE against the
--   seed_seller_city_corrections seed table (27 known bad values ->
--   correct spelling) -- see ADR 0005. LEFT JOIN keeps all 3,095
--   sellers even though only ~30 rows actually match a correction;
--   COALESCE falls back to the original seller_city when no match
--   exists. Correction matches on city text alone, not scoped by zip
--   -- verified safe for this dataset, see ADR 0005 consequences.

create table dim_sellers (
		seller_key integer generated always as identity primary key,
		seller_id text unique,
		seller_city text,
		seller_state text,
		seller_zip_code_prefix text
);

insert into dim_sellers (

	seller_id,
    seller_city,
    seller_state,
    seller_zip_code_prefix 
)

select
    st.seller_id,
    COALESCE(se.corrected_value, st.seller_city) as seller_city,
    st.seller_state,
    st.seller_zip_code_prefix
from stg_sellers st
left join seed_seller_city_corrections se
    on st.seller_city = se.raw_value;

-- Verify no rows were lost or duplicated: should equal 3,095, the
-- confirmed distinct seller_id count in stg_sellers.

select count(*) from dim_sellers;