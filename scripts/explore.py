import pandas as pd
df=pd.read_csv('raw_csv/olist_order_reviews_dataset.csv')
print(df.head())
print(df.sample(10))
print(df.shape)
print(df.dtypes)
print(df.isnull().sum())
print(df.duplicated().sum())
print(df['order_id'].nunique())
