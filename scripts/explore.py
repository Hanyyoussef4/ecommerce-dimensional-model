import pandas as pd
df = pd.read_csv('raw_csv/olist_products_dataset.csv')
print(df.head())
print(df.shape)
print(df.dtypes)
print(df.groupby('product_category_name')['product_id'].count())
print(df.groupby('product_category_name')['product_id'].count().sum())
print(df['product_category_name'].isnull().sum())
print(df.shape[0] - df['product_category_name'].isnull().sum())
print(df[df['product_category_name'].isnull()].isnull().sum())
print(df.isnull().sum())
print(df[df['product_length_cm'].isnull()]) # find the 2 product taht does not have product dimension values "this approach captures the two rows with Prd_id and doesnt have prd dimensions"
print(df[df['product_weight_g'].isnull() & df['product_category_name'].notnull()]) # this approach to find the one raw has NaN product dimension and is not part of the Nan prodcut category
print(df['product_category_name'].nunique()) # this line -14 and the line-15 after are confirming that no formatting issues in the product_category_name field and it is really 73 unique values
print(df['product_category_name'].str.strip().str.lower().nunique())

## adding variables
cnt_rws = df.groupby('product_category_name')['product_id'].size().sort_values() #creating the groupby series for a data heathcheck 
multi = cnt_rws[cnt_rws <=5] #filter the series to show only product_category_name less/equal 5 orders
print(multi)

for cat in multi.index:
    print(df[df['product_category_name'] == cat])

print(df[df['product_category_name'].str.contains(r'_\d$', na=False, regex=True)]['product_category_name'].unique())
print(df[df['product_category_name'].str.contains('casa_conforto',na = False)]['product_category_name'].value_counts())
print(df[df['product_category_name'].str.contains('eletrodomesticos',na = False)]['product_category_name'].value_counts())
print(df.describe())
print(df[df['product_weight_g'] == 0])
print(df[df['product_photos_qty'] == 20])
cnt_phts = df[df['product_photos_qty'] >= 15]
print(cnt_phts.sort_values(['product_category_name','product_photos_qty']))
print(df[df['product_category_name'] == 'brinquedos']['product_photos_qty'].describe())
print(df[df['product_category_name'] == 'bebes']['product_photos_qty'].describe())