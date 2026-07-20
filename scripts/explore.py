import pandas as pd
df = pd.read_csv('raw_csv/olist_customers_dataset.csv')
print(df.head())
print(df.sample(10))
print(df.shape)
print(df.dtypes)