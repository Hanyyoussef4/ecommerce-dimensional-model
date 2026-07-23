import pandas as pd
df = pd.read_csv('raw_csv/olist_orders_dataset.csv')
print(df.head())
print(df.sample(10))
print(df.shape)
print(df.dtypes)
print(df.isnull().sum())
print(df.duplicated().sum())
print(df['order_status'].value_counts())
print(df['order_id'].nunique())
print(df.groupby('order_status')['order_delivered_customer_date'].apply(lambda x: x.isnull().sum()))
print(
    df[
        (df['order_status']=="delivered") & (df['order_delivered_customer_date'].isnull())
        ])
