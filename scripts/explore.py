import pandas as pd
pd.set_option('display.max_rows', None)

df = pd.read_csv('raw_csv/olist_sellers_dataset.csv')
print(df.head())
print(df.sample(5))
print(df.shape)
print(df.dtypes)
print(df.duplicated().sum())
print(df.isnull().sum())
print(df['seller_city'].nunique())
print(df['seller_city'].str.strip().nunique())
print(df['seller_state'].nunique())
print(df['seller_state'].str.strip().nunique())
print(df.groupby('seller_state').size().sort_values())

cnt_rws = df.groupby('seller_zip_code_prefix')['seller_city'].nunique().sort_values(ascending=False)
print(cnt_rws[cnt_rws > 1])
print(cnt_rws[cnt_rws > 1].count())
print(df[df['seller_city'].str.contains('@')])
print(df[df['seller_city'] == 'santa catarina'])
example1 = cnt_rws[cnt_rws > 1].index
print(df[df['seller_zip_code_prefix'].isin(example1)].sort_values(['seller_zip_code_prefix', 'seller_city']))
print(df[df['seller_city'].str.contains(r'\d', na=False, regex=True)])  # digits in a city name -- catches things like "04482255"
print(df[df['seller_city'].str.contains('/', na=False)])                # slash -- catches concatenated entries like "ribeirao preto / sao paulo"
print(df[df['seller_city'].str.contains(' - ', na=False)])               # dash with spaces -- catches things like "lages - sc"

df[df['seller_zip_code_prefix'].isin(example1)].sort_values(['seller_zip_code_prefix', 'seller_city']).to_csv('notes/seller_city_anomalies.csv', index=False)