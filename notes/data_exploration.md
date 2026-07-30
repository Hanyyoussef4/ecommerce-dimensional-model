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