import pandas as pd
pd.set_option('display.max_rows', 30)
df = pd.read_csv('raw_csv/olist_geolocation_dataset.csv')
print(df.head())
print(df.sample(5))
print(df.shape)
print(df.dtypes)
print(df.isnull().sum())
print(df.duplicated().sum())
print(df['geolocation_zip_code_prefix'].nunique())
print(df['geolocation_city'].nunique())
print(df['geolocation_state'].nunique())
print(sorted(df['geolocation_state'].unique()))
#df['geolocation_city'].drop_duplicates().to_csv('notes/geolocation_unique_cities.csv', index=False)
#df.drop_duplicates().to_csv('notes/geolocation_deduplicated.csv', index=False)
print(df['geolocation_zip_code_prefix'].describe())
import unicodedata

def strip_accents(text):
    return ''.join(c for c in unicodedata.normalize('NFD', text) if unicodedata.category(c) != 'Mn')

print(df['geolocation_city'].apply(strip_accents).str.lower().str.strip().nunique())