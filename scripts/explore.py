import pandas as pd
df=pd.read_csv('raw_csv/olist_order_items_dataset.csv')
print(df.head())
print(df.sample(10))
print(df.shape)
print(df.dtypes)
print(df.isnull().sum())
print(df.duplicated().sum())
print(df['order_id'].nunique())
print(df[df['order_id']=="086928951ba74a6682919fc942c458d0"])
qty = df.groupby(['order_id', 'product_id']).size()
print((qty > 1).sum())

