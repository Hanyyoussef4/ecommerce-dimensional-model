# Data Exploration Notes

## olist_customers_dataset.csv

**Shape:** 99,441 rows, 5 columns

**Nulls/duplicates:** 0 nulls across all columns, 0 duplicate rows.

**Dtypes:** customer_zip_code_prefix is int64 (numeric, correct). All
other columns (customer_id, customer_unique_id, customer_city,
customer_state) are str -- correct, no dates in this file.

**Keys:** customer_id is unique per row (99,441) -- this is per-ORDER,
not per-person. customer_unique_id has only 96,096 unique values -- the
real person identifier. ~3,345 repeat customers (people who ordered more
than once, each getting a new customer_id).

**Decision for later:** dim_customers grain -- per-order (customer_id)
or per-person (customer_unique_id)? Not yet decided.

---

## olist_orders_dataset.csv

**Shape:** 99,441 rows, 8 columns

**Keys:** order_id is unique per row (99,441) -- one row per order.

**Dtypes:** All 5 date/timestamp columns (order_purchase_timestamp,
order_approved_at, order_delivered_carrier_date,
order_delivered_customer_date, order_estimated_delivery_date) read as
str, not datetime. Pandas doesn't auto-parse dates -- needs fixing at
load time (parse_dates or pd.to_datetime).

**order_status breakdown (value_counts):**
delivered 96478, shipped 1107, canceled 625, unavailable 609,
invoiced 314, processing 301, created 5, approved 2

**Nulls:**
- order_approved_at: 160 nulls
- order_delivered_carrier_date: 1,783 nulls
- order_delivered_customer_date: 2,965 nulls
- all other columns: 0 nulls

**Null investigation (order_delivered_customer_date, by status via
groupby):** approved 2, canceled 619, created 5, delivered 8,
invoiced 314, processing 301, shipped 1107, unavailable 609
(sums to 2965, exact)

Mostly explained by order lifecycle: an order that hasn't reached
"delivered" naturally has no delivery timestamp yet. Two exceptions:
- 6 of 625 "canceled" orders DO have a delivery timestamp -- delivered,
  then canceled afterward (e.g. a return).
- 8 orders have status "delivered" but NO delivery timestamp -- a
  genuine data quality gap, not explained by lifecycle stage.

**Anomaly deep dive (the 8 delivered-but-null-date rows):**
- 7 of 8 have order_delivered_carrier_date populated (handed to carrier)
  but order_delivered_customer_date is null -- likely a carrier tracking
  gap: scanned as delivered by carrier, final "received by customer"
  confirmation never logged.
- 1 row (order_id starting 2d858f...) is missing BOTH carrier and
  customer delivery dates despite status="delivered" -- most anomalous.
- No obvious date clustering -- spans 2017-11 through 2018-07.

**Design decision for later:** Use order_status as the source of truth
for "was this order delivered," not the presence/absence of
order_delivered_customer_date. Don't silently drop or mis-flag these
8 orders due to the missing timestamp.

---

## olist_order_items_dataset.csv

**Shape:** 112,650 rows, 7 columns

**Keys:** order_id.nunique() = 98,666, LESS than row count -- confirms
line-item grain, not order grain (~13,984 extra rows from orders with
more than one product).

**Quantity note:** No quantity column exists. Each unit purchased gets
its own row (order_item_id numbers them 1, 2, 3...). Verified directly:
order "086928951ba74a6682919fc942c458d0" has 5 rows, same product_id/
seller_id/price -- 5 units of ONE product, not 5 different products.

groupby(['order_id','product_id']).size() -> 102,425 unique order-product
pairs. Of those, 7,088 (~6.9%) involve more than 1 unit -- multi-unit
purchases are a real but minority pattern.

To get quantity per product per order: groupby(['order_id','product_id']).size(),
not a direct column read.

**Dtypes:** price and freight_value correctly float64 (no fix needed).
shipping_limit_date is str, not datetime -- same load-hygiene issue as
the orders file's date columns.

**Nulls/duplicates:** 0 nulls, 0 duplicate rows -- clean file.

---

## olist_order_payments_dataset.csv

**Shape:** 103,886 rows, 5 columns

**Keys:** order_id.nunique() = 99,440, LESS than row count -- confirms
payment-level grain, not order grain (~4,446 orders have more than one
payment row).

**payment_installments vs payment_sequential (important distinction):**
- payment_installments: a number WITHIN one row -- describes financing
  (e.g. a credit card charge split into N monthly installments). Does
  NOT create extra rows.
- payment_sequential: numbers SEPARATE payment records within an order
  (1, 2, 3...) -- multiple rows happen when an order is paid via more
  than one payment entry (different methods, or multiple vouchers).

**payment_sequential.value_counts():** 1 -> 99,360 (vast majority, single
payment), shrinking fast for 2, 3, 4... long tail up to 29.

**Verified directly (2-row example):** order "0016dfedd97fc2950e388d2971d718c7"
has sequential=1 (credit_card, 5 installments, $52.63) and sequential=2
(voucher, 1 installment, $17.92) -- genuinely mixed payment METHODS.
Total = $70.55 (sum across rows).

**Verified directly (extreme outlier, 29 rows):** order
"fa65dad1b0e818e3ccc5cb0e39231352" has all 29 rows as payment_type=voucher
-- NOT mixed methods, but 29 separate voucher codes stacked on one order.
Total paid = $457.99 (sum across all 29 rows).

**Key lesson:** payment_sequential > 1 does NOT always mean "mixed payment
methods" -- can also mean "many entries of the SAME method." Don't assume;
verify with real examples.

**Dataset-wide validation:** groupby('order_id')['payment_sequential']
.agg(['count','nunique']), compared count vs nunique per order -> 0
mismatches across all ~4,446 multi-row orders. Confirms EVERY multi-payment
order has genuinely distinct, non-duplicated payment_sequential values --
no data corruption hiding in the "multiple rows per order_id" pattern.

**payment_type full distribution (value_counts):**
credit_card 76795, boleto 19784, voucher 5775, debit_card 1529,
not_defined 3

**Zero-value payment investigation (payment_value == 0):**
9 rows total. 6 are voucher (all within the 29-row all-voucher order,
sitting alongside 27 other real-money rows -- likely legitimate
promotional/fully-discounted vouchers, not an error).
3 are payment_type "not_defined" -- and each belongs to an order that
has NO OTHER payment row. These 3 orders (4637ca194b6387e2d538dc89b124b0ee,
00b1cb0320190ca0daa2c88b35206009, c8c528189310eaa44a745b8d9d26908b)
appear to have NO real payment recorded at all -- genuine data quality
issue, distinct from the voucher-zero case.

**Dtypes:** payment_type is str (categorical, fine). payment_installments
int64, payment_value float64 -- both correctly typed. No date columns in
this file, no load-hygiene date issue here.

**SCHEMA IMPLICATIONS:**
- fact_orders needs total payment_value per order as a SUM across
  payment rows, not a direct read of one row's value.
- Decide how fact_orders should handle the 3 orders with zero/no real
  payment -- exclude, flag with a data-quality indicator, or keep as-is.

**Investigated min credit_card value ($0.01) and sub-$1 credit_card
payments (91 rows total):** NOT a data error. Verified directly: order
"5262eaeb971616ffef822379ed91896f" has sequential=1 (credit_card, $0.67)
and sequential=2 (voucher, $47.55) -- the tiny credit_card amount is the
small leftover balance after a voucher covered most of the order. Same
split-payment pattern as the earlier examples, just at the small end
instead of the large end.

**Dataset-wide confirmation of the small credit_card payments:** mapped
all 91 sub-$1 credit_card rows against each order's total row count
(multi) -- 0 of them belong to an order with only 1 payment row. Every
single one is part of a multi-payment order (voucher/etc covering the
rest). Fully confirms this is the split-payment remainder pattern, not
a data quality issue -- genuinely closed, no further digging needed.

---

## olist_order_reviews_dataset.csv

**Shape:** 99,224 rows, 7 columns

**Dtypes:** review_id, order_id, review_comment_title,
review_comment_message, review_creation_date, review_answer_timestamp
are str. review_score is int64. Date columns are str, not datetime --
same load-hygiene issue as every other file with dates.

**Nulls:**
- review_comment_title: 87,656 nulls
- review_comment_message: 58,247 nulls
- all other columns: 0 nulls

Likely normal -- customers can leave just a score with no title/message.
Worth noting comment_title has more nulls than comment_message, meaning
some customers write a message without a title.

**Duplicates:** 0 duplicate rows.

**review_score distribution (groupby.size()):**
1: 11,424, 2: 3,151, 3: 8,179, 4: 19,142, 5: 57,328

**ASSUMPTION (not explicitly confirmed in the CSV):** 5 = most satisfied,
1 = least satisfied. Based on standard review-scale convention (matches
Olist's public dataset documentation) and supported by the distribution
shape itself -- heavy concentration at 5, smaller cluster at 1, consistent
with typical satisfaction-rating patterns. Worth confirming against
Kaggle's dataset card if used in any customer-facing analysis later.

**Date column investigation:** review_creation_date always shows time as
00:00:00 for 99,139 of 99,224 rows (99.9%) -- it's really a DATE with a
zeroed-out time placeholder, not a genuine timestamp. The 85 exceptions
all show 01:00:00 instead, and are entirely explained by Brazilian DST:
the two unique exception values are "2017-10-15 01:00:00" and
"2016-10-16 01:00:00" -- exactly matching Brazil's historical DST start
dates (third Sunday of October) in those two years. Timezone artifact
from the source system, not meaningful data. No special handling needed
at load -- truncating to DATE (dropping time) resolves it naturally.

Exact breakdown of the 85 exceptions: 2017-10-15 01:00:00 -> 84 rows,
2016-10-16 01:00:00 -> 1 row. Heavily concentrated on the 2017 DST
transition, not evenly split across both years.

review_answer_timestamp, by contrast, has genuine varying times of day
throughout -- a real timestamp, should load as full DATETIME.

**Keys:** order_id.nunique() = 98,673, LESS than row count (99,224) --
confirms some orders have more than one review.

**Multi-review orders investigation:** 547 orders have more than one
review (543 with exactly 2, 4 with exactly 3) -- reconciles exactly with
the earlier order_id.nunique() gap (99,224 - 98,673 = 551 extra rows).

Checked 4 real examples -- NOT one single explanation, genuinely mixed:
- Some are real follow-up reviews with a DIFFERENT score days apart
  (e.g. 5 -> 4 over 10 days) -- opinion changed.
- At least one looks like a straight technical duplicate: identical
  score, identical creation date, answer timestamps only 41 seconds
  apart -- likely a double-submission bug, not two real reviews.
- At least one shows a genuinely evolving complaint: score got WORSE
  over time (3 -> 1) with different complaint text each time, one
  mentioning a delivery issue -- looks like a real escalating situation.

**SCHEMA IMPLICATIONS:**
- Don't assume "latest review" or "first review" is always the "correct"
  one to keep for a dim/fact design -- the reasons for multiple reviews
  vary (duplicate vs. genuine follow-up), so any decision to collapse to
  one review per order needs a documented rule (e.g. "keep most recent")
  while acknowledging it may discard a meaningful earlier complaint in
  some cases.
- review_creation_date should load as DATE (not datetime) -- the time
  portion is a placeholder/DST artifact, never meaningful.
- review_answer_timestamp should load as full DATETIME -- genuine
  time-of-day information.

---
  
  ## olist_products_dataset.csv

**Shape:** 32,951 rows, 9 columns

**Dtypes:** product_id and product_category_name are str. All other
columns (product_name_lenght, product_description_lenght,
product_photos_qty, product_weight_g, product_length_cm,
product_height_cm, product_width_cm) are float64.

**Null investigation:** 610 rows missing product_category_name are
PERFECTLY correlated with also missing product_name_lenght,
product_description_lenght, and product_photos_qty (all exactly 610) --
these look like incomplete product listings where the seller never
filled in any descriptive fields, not independent random gaps.

Separately, only 2 rows total are missing dimension fields (weight/
length/height/width):
- Row "5eb564652db742ff8f28759cd8d2652a" is part of the 610-row
  incomplete-listing cluster (everything null).
- Row "09ff539a621711667c43eba6a3bd8466" is an ISOLATED case -- has a
  completely normal category ("bebes"), name_length, and
  description_length filled in, but is missing all 4 dimension fields.
  A separate, unrelated data gap on an otherwise complete listing.

**Category name investigation:** 73 unique categories confirmed genuine
(nunique matches before/after .str.strip().str.lower(), no hidden
spacing/casing duplicates). Checked the 5 rare categories (<=5 products
each: cds_dvds_musicais, seguros_e_servicos, pc_gamer,
fashion_roupa_infanto_juvenil, casa_conforto_2) directly -- all look
like legitimate distinct categories.

FOUND (via regex sweep for names ending in "_<digit>"): TWO pairs of
near-duplicate categories exist in the source data:
- "casa_conforto" (111 products) and "casa_conforto_2" (5 products)
- "eletrodomesticos" (370 products) and "eletrodomesticos_2" (90 products)
Confirmed via .str.contains(regex) + value_counts(). Not formatting
glitches -- genuinely separate category strings, likely representing the
same or overlapping real-world category. This looks like a recurring
naming pattern in Olist's category taxonomy, not a one-off anomaly.

**product_weight_g outlier investigation (via describe(), min=0):**
Exactly 4 rows have weight=0, ALL in the same category "cama_mesa_banho"
(bed/table/bath). NOT part of the 610-row incomplete-listing cluster --
these are otherwise complete records: dimensions (30x25x30cm), name_length,
description_length, photos_qty all populated normally. Only weight is
impossible (0g for a physical product). Clustering in a single category
suggests a systematic data entry issue (e.g. one seller/batch upload for
this category), not random scattered bad data.

**product_photos_qty outlier investigation (via describe(), max=20 vs
75th percentile=3 overall):** MIXED finding, not one clean explanation --
- pet_shop shows a genuine category-wide pattern: MANY different
  products in this category have 15-18 photos.
- brinquedos: real WITHIN-CATEGORY outlier. Scoped describe() (1,411
  products) shows mean=2.46, 75th percentile=3, but this one product
  has 20 photos.
- bebes: same pattern. Scoped describe() (919 products) shows mean=2.35,
  75th percentile=3, but one product has 19 photos.
- NOTABLE: the brinquedos and bebes outlier products have IDENTICAL
  weight (8900g) and dimensions (32x49x34cm), and near-identical
  name/description lengths, despite different product_ids and
  categories -- possibly the same physical item listed under two
  different categorizations by different sellers. Not fully chased
  down, worth remembering.

Lesson: don't generalize "high value belongs to category X, therefore
X explains high values" from a mixed list without checking each
category's own distribution individually -- verify per-category, not
just from a mixed overall list.

**SCHEMA IMPLICATIONS:**
- dim_products: decide whether to merge casa_conforto/casa_conforto_2
  and eletrodomesticos/eletrodomesticos_2 pairs, or preserve as-is per
  source data. Check for similar patterns before finalizing.
- The 610 no-category products need a decision: exclude, or bucket as
  "uncategorized"/"unknown."
- The 4 weight=0 rows will break freight/shipping calculations if
  joined with order_items -- decide: exclude, impute category-average
  weight, or flag with a data-quality indicator.

  ## olist_sellers_dataset.csv

**Shape:** 3,095 rows, 4 columns

**Dtypes:** seller_id, seller_city, seller_state are str.
seller_zip_code_prefix is int64.

**Nulls/duplicates:** 0 nulls across all columns, 0 duplicate rows.

**seller_city / seller_state uniqueness:** 611 unique cities, 23 unique
states -- confirmed genuine via two independent methods (direct
.nunique(), and value_counts().index.nunique()), both before and after
.str.strip().str.lower() normalization. No hidden whitespace/casing
duplicates at the surface level (real issues found below are NOT
whitespace/casing -- they're typos, formatting, and outright bad values).

**seller_state distribution (groupby.size(), sorted):** heavily skewed --
SP alone has 1,849 of 3,095 total sellers (~60%). Long tail down to
several states with just 1 seller each (AC, PI, MA, PA, AM). Only 23 of
Brazil's 27 states/federal district appear at all -- some states have
zero sellers in this dataset, which is real, not missing data.

**seller_city data quality investigation (major finding):** Cross-checked
via seller_zip_code_prefix -- 34 zip prefixes have more than one distinct
seller_city value attached. Investigated ALL 34 directly (not a sample).
Full flagged dataset exported to notes/seller_city_anomalies.csv (112
rows) for reference during schema-building/cleaning.

NOT legitimate zip-boundary overlap in most cases -- found multiple
distinct categories of real data quality issues:

- **Simple misspellings** (10 pairs): garulhos/guarulhos, mogi das
  cruses/mogi das cruzes, sando andre/santo andre, sao bernardo do
  campo/sao bernardo do capo, scao jose do rio pardo/sao jose do rio
  pardo, robeirao preto/ribeirao preto, riberao preto/ribeirao preto,
  belo horizont/belo horizonte, cascavael/cascavel, floranopolis/
  florianopolis, balenario camboriu/balneario camboriu.
- **Missing space:** portoferreira vs porto ferreira.
- **Apostrophe/punctuation variants:** santa barbara d oeste vs santa
  barbara d'oeste; sao miguel d'oeste vs sao miguel do oeste.
- **Full state name used as a city name** (3 instances): "santa
  catarina" (zip 88135), "minas gerais" (zip 37165), "parana" (zip 87083).
- **Email address as city:** vendas@creditparts.com.br (zip 87025).
- **Zip code number as city:** "04482255" (zip 22790).
- **Malformed/duplicated concatenations** (15 total, found via
  .str.contains('/') across the FULL column, not just the 34 flagged
  zips): self-duplicates like "sao paulo / sao paulo", "sp / sp", "rio
  de janeiro / rio de janeiro"; city-slash-state combos like
  "auriflama/sp", "sbc/sp", "pinhais/pr", "barbacena/ minas gerais";
  city-slash-city combos like "santo andre/sao paulo", "mogi das cruzes
  / sp", "carapicuiba / sao paulo", "jacarei / sao paulo", "sao
  sebastiao da grama/sp", "cariacica / es", "ribeirao preto / sao
  paulo", "maua/sao paulo".
- **Dash-separated state suffix** (4 total, via .str.contains(' - ')):
  "lages - sc", "sao paulo - sp" (x3).
- **State mismatch (different bug -- wrong seller_state, not just
  city):** zip 88075 has one row with city "florianopolis" but state
  "SP", while another row at the same zip has city "sao jose" with
  state "SC". Florianopolis is a well-known real city in Santa Catarina,
  so SP here is very likely a wrong seller_state value, not just a
  messy city string.
- **Possibly legitimate, NOT errors** -- genuinely different real city
  names sharing a zip prefix, may reflect real geographic zip-boundary
  overlap: sao caetano do sul/sao paulo (zip 9560), jaguariuna/monte
  alegre do sul (zip 13820), laranjal paulista/tatui (zip 18500).
  Worth a second look, cities are geographically far apart (more likely
  real errors than boundary overlap): mage/rio de janeiro (zip 25900),
  campos dos goytacazes/rio de janeiro (zip 28035), santa rita do
  sapucai/sao paulo (zip 37540, MG vs SP -- large distance).

**Methodological insight:** the zip-cross-check technique only catches
INCONSISTENCY (same zip, disagreeing city values). A zip prefix where
every seller was entered with the same messy format consistently (e.g.
always "city / state") would NOT be flagged by this method, since
there'd be no disagreement to detect. This is why the standalone regex
sweeps (digit, slash, dash) mattered -- they scan the whole column
independent of zip grouping, catching format issues even when a zip's
rows are internally consistent with each other.

**SCHEMA IMPLICATIONS:**
- seller_city cannot be trusted as-is for dim_sellers. This is a
  genuine, non-trivial cleaning problem (112+ flagged rows across many
  distinct failure types), not a couple of stray values.
- Recommend a systematic cleaning approach for schema-building phase:
  cross-reference seller_city against a canonical Brazilian city list
  (e.g. IBGE municipality list) rather than manual pattern-matching,
  given how many different failure types exist.
- seller_state may also have at least 1 confirmed wrong value (the
  florianopolis/SP mismatch) -- don't assume seller_state is fully
  reliable either, though it appears far less affected than seller_city.
- seller_zip_code_prefix itself looks structurally reliable; the data
  quality problem is isolated to the free-text seller_city (and
  occasionally seller_state) fields.

  ## olist_geolocation_dataset.csv

**Shape:** 1,000,163 rows, 5 columns

**Dtypes:** geolocation_zip_code_prefix is int64. geolocation_lat and
geolocation_lng are float64. geolocation_city and geolocation_state
are str.

**Nulls:** 0 across all columns.

**Duplicates:** 261,831 EXACT duplicate rows (~26% of the file) --
identical zip, lat/lng, city, and state. Simple .drop_duplicates()
resolves this, no interpretation needed (unlike sellers' messy data).
Deduplicated dataset (738,332 rows) exported to
notes/geolocation_deduplicated.csv for reference.

**Grain:** 19,015 unique zip prefixes across 1,000,163 rows (~52 rows
per prefix on average). Many lat/long geocode points exist per zip
area -- this table needs aggregation (e.g. average lat/lng per prefix)
before use as a clean geo lookup, not usable as raw rows.

**geolocation_zip_code_prefix range check (describe()):** min 1,001,
max 99,990 -- fully within the plausible 5-digit Brazilian CEP range.
No structural issues.

**geolocation_state:** exactly 27 unique values, ALL valid 2-letter
Brazilian state codes (confirmed via sorted unique list). Clean,
no contamination -- unlike seller_state, no issues found here.

**geolocation_city investigation:** 8,011 raw unique values -- too
large to catalog individually like sellers' 611. Checked accent-mark
normalization (unicodedata NFD decomposition + lowercase + strip):
count drops to 5,968 (~25.5% reduction). Confirms a large portion of
the raw "distinctness" was accent/casing/whitespace noise (e.g. "sao
paulo" vs "são paulo" counted as 2 different cities), not genuine city
variety. Full raw unique city list exported to
notes/geolocation_unique_cities.csv (8,011 rows) for reference. Remaining
~5,968 likely still contains some real typos (similar to sellers), but
full manual cataloging wasn't pursued given this table's primary value
is lat/lng coordinates, not the city/state text, and it requires
aggregation regardless.

**SCHEMA IMPLICATIONS:**
- This table must be aggregated (drop exact duplicates, likely average
  lat/lng per zip_code_prefix) before use in a geo dimension -- not
  usable as raw rows.
- If geolocation_city is ever used directly (not just for reference),
  apply accent/case/whitespace normalization first -- this alone
  resolves ~25% of apparent inconsistency cheaply.
- geolocation_state and geolocation_zip_code_prefix are both clean and
  reliable as-is.