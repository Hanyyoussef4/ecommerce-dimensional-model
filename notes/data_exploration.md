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