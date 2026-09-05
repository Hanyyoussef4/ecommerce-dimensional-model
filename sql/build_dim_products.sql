
-- Builds dim_products from stg_products.
-- - Merges near-duplicate categories (casa_conforto/_2, eletrodomesticos/_2)
--   before joining to the translation table -- see comment near the CASE
--   block below for why order matters here.
-- - Missing product_category_name is replaced with 'not specified' (ADR 0004).
-- - Missing English translation falls back to the Portuguese name itself
--   (not a hardcoded list of known-missing categories), so it self-generalizes
--   to any future category with no translation.
-- - product_key uses GENERATED ALWAYS AS IDENTITY, not ROW_NUMBER(), so keys
--   stay stable if this table is ever reloaded (see ADR 0008).

create table dim_products (

	product_key INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY key,
	product_id text unique,
	product_category_name text,
	product_category_name_english text,
	product_name_lenght integer,
	product_description_lenght integer,
	product_photos_qty integer,
	product_weight_g integer,
	product_length_cm integer,
	product_height_cm integer,
	product_width_cm integer
);

	-- Merging casa_conforto_2 -> casa_conforto (and the eletrodomesticos pair)
	-- must happen here, before the translation join below, not after.
	-- Verified both variants have different English translations in
	-- stg_product_category_translation (e.g. 'home_confort' vs 'home_comfort_2') --
	-- joining first and merging after would leave some rows with one
	-- translation and some with the other, despite showing the same category.

with merged_products as (
	select
	product_id,
	product_name_lenght,
	product_description_lenght,
	product_photos_qty,
	product_weight_g,
	product_length_cm,
	product_height_cm,
	product_width_cm,
	case
		when product_category_name = 'casa_conforto_2' then 'casa_conforto'
		when product_category_name = 'eletrodomesticos_2' then 'eletrodomesticos'
		when product_category_name is null then 'not specified'
		else product_category_name
 	end as product_category_name
 from stg_products
)
insert into dim_products(
	product_id,
	product_category_name,
	product_category_name_english,
	product_name_lenght,
	product_description_lenght,
	product_photos_qty,
	product_weight_g,
	product_length_cm,
	product_height_cm,
	product_width_cm
	)
select
    m.product_id,
    m.product_category_name,
	coalesce (product_category_name_english,m.product_category_name) as product_category_name_english,
	m.product_name_lenght,
	m.product_description_lenght,
	m.product_photos_qty,
	m.product_weight_g,
	m.product_length_cm,
	m.product_height_cm,
	m.product_width_cm
from merged_products m
left join stg_product_category_translation p
on m.product_category_name = p.product_category_name;


-- Verify no rows were lost or duplicated by the translation join: should equal
-- 32,951, the confirmed distinct product_id count in stg_products.

select count(*) from dim_products;