import pandas as pd
from sqlalchemy import create_engine, text

engine = create_engine ("postgresql+psycopg2://hany:@localhost:5432/ecommerce_dw")

files ={
    "olist_customers_dataset.csv": "stg_customers",
    "olist_orders_dataset.csv": "stg_orders",
    "olist_order_items_dataset.csv": "stg_order_items",
    "olist_order_payments_dataset.csv": "stg_order_payments",
    "olist_order_reviews_dataset.csv": "stg_order_reviews",
    "olist_products_dataset.csv": "stg_products",
    "olist_sellers_dataset.csv": "stg_sellers",
    "olist_geolocation_dataset.csv": "stg_geolocation",
    "product_category_name_translation.csv": "stg_product_category_translation"
}
zip_columns = {

    "olist_customers_dataset.csv": "customer_zip_code_prefix",
    "olist_sellers_dataset.csv": "seller_zip_code_prefix",
    "olist_geolocation_dataset.csv": "geolocation_zip_code_prefix",
}
conn = engine.connect()
for filename, table_name in files.items():
    dtype = None
    if filename in zip_columns:
        dtype = {zip_columns[filename]: str}
    df = pd.read_csv(f"raw_csv/{filename}", dtype=dtype)
    csv_count = df.shape[0] 
    df.to_sql(table_name,
       engine,
        if_exists="replace",
            index=False
    )
    print(csv_count,f'total records in file {filename}')

#query the count for each stg_table from database
    query = text(f'select count(*) from {table_name}')
    result = conn.execute(query)
    sql_count = result.scalar_one()

#print a comparison to validate rows count
    print(
        table_name,
        "CSV:", csv_count,
        "SQL:", sql_count,
        "Match:", csv_count == sql_count
    )

conn.close()