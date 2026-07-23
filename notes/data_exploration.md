# Data Exploration Notes

## olist_customers_dataset.csv
- 99,441 rows, 5 columns
- No nulls, no duplicate rows
- customer_id: unique per row (99,441) — this is per-ORDER, not per-person
- customer_unique_id: 96,096 unique — the real person identifier
  -> ~3,345 repeat customers
  -> Decide dim_customers grain later: per-order or per-person


## olist_orders_dataset.csv

**Shape:** 99,441 rows, 8 columns

**Keys:** order_id is unique per row (99,441) -- this table is one row per order.

**Dtypes:** All 5 date/timestamp columns (order_purchase_timestamp,
order_approved_at, order_delivered_carrier_date, order_delivered_customer_date,
order_estimated_delivery_date) read as str, not datetime. Pandas doesn't
auto-parse dates -- needs fixing at load time (parse_dates or pd.to_datetime).

**order_status breakdown (value_counts):**
delivered 96478, shipped 1107, canceled 625, unavailable 609,
invoiced 314, processing 301, created 5, approved 2

**Nulls:**
- order_approved_at: 160 nulls
- order_delivered_carrier_date: 1,783 nulls
- order_delivered_customer_date: 2,965 nulls
- all other columns: 0 nulls

**Null investigation (order_delivered_customer_date, by status via groupby):**
approved 2, canceled 619, created 5, delivered 8, invoiced 314,
processing 301, shipped 1107, unavailable 609 (sums to 2965, exact)

Mostly explained by order lifecycle: an order that hasn't reached the
"delivered" stage naturally has no delivery timestamp yet. Two exceptions
worth noting:
- 6 of 625 "canceled" orders DO have a delivery timestamp -- order was
  delivered, then canceled afterward (e.g. a return).
- 8 orders have status "delivered" but NO delivery timestamp -- a genuine
  data quality gap, not explained by lifecycle stage.

**Anomaly deep dive (the 8 delivered-but-null-date rows):**
- 7 of 8 have order_delivered_carrier_date populated (handed to carrier)
  but order_delivered_customer_date is null -- likely a carrier tracking
  gap: package scanned as delivered by the carrier, but final "received by
  customer" confirmation never logged back into Olist's system.
- 1 row (order_id starting 2d858f...) is missing BOTH carrier and customer
  delivery dates despite status="delivered" -- the most anomalous of the 8.
- No obvious date clustering -- spans 2017-11 through 2018-07, not a single
  outage window.

**Design decision for later (fact_orders / star schema):**
Use order_status as the source of truth for "was this order delivered,"
not the presence/absence of order_delivered_customer_date. Don't silently
drop or mis-flag these 8 orders due to the missing timestamp.