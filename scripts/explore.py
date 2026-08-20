import pandas as pd
pd.set_option('display.max_rows', 30)
df = pd.read_csv('raw_csv/product_category_name_translation.csv')

print(df.head())
print(df.sample(5))
print(df.shape)
print(df.dtypes)
print(df.duplicated().sum())
print(df.isnull().sum())
print(df['product_category_name'].unique())
print(df['product_category_name_english'].unique())
print(df.groupby('product_category_name', dropna=False)['product_category_name_english'].size().sort_values(ascending=False))

products_categories = set(pd.read_csv('raw_csv/olist_products_dataset.csv')['product_category_name'].dropna().unique())
translation_categories = set(df['product_category_name'].unique())
print(products_categories - translation_categories)

translation_categories2 = set(df['product_category_name_english'].unique())
print(products_categories - translation_categories2)
