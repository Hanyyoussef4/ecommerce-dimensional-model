import pandas as pd
df=pd.read_csv('raw_csv/olist_order_reviews_dataset.csv')
print(df.head())
print(df.sample(10))
print(df.shape)
print(df.dtypes)
print(df.isnull().sum())
print(df.duplicated().sum())
print(df['order_id'].nunique())
print(df.groupby('review_score').size())
print((df['review_creation_date'].str.endswith('00:00:00')).sum())
print(df[~df['review_creation_date'].str.endswith('00:00:00')])
print(df[~df['review_creation_date'].str.endswith('00:00:00')]['review_creation_date'].nunique())
print(df[~df['review_creation_date'].str.endswith('00:00:00')]['review_creation_date'].unique())
cnt_rws=df.groupby('order_id').size() ##count_rows_that has same order ID
multi= cnt_rws[cnt_rws > 1] ##filter result to include only orders with more then one row (multi reviews)
print(multi.value_counts())
example_order=multi.index[0]
print(df[df['order_id'] == example_order])

example_order=multi.index[1]
print(df[df['order_id'] == example_order])

example_order=multi.index[2]
print(df[df['order_id'] == example_order])

example_order=multi.index[3]
print(df[df['order_id'] == example_order])
