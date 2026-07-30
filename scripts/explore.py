import pandas as pd
df=pd.read_csv('raw_csv/olist_order_payments_dataset.csv')
print(df.head())
print(df.sample(10))
print(df.shape)
print(df.dtypes)
print(df.isnull().sum())
print(df.duplicated().sum())
print(df['order_id'].nunique())
print(df['payment_sequential'].value_counts())
multi=df.groupby('order_id').size()
example_id = multi[multi > 1].index[0]
print(df[df['order_id'] == example_id])
df_filtered = df[df['payment_sequential']==29]
example_id2 = df_filtered['order_id'].iloc[0]
print(df[df['order_id']== example_id2].sort_values('payment_sequential'))
print(df[df['order_id']== example_id2]['payment_value'].sum())
check=df.groupby('order_id')['payment_sequential'].agg(['count','nunique'])
print((check['count'] != check['nunique']).sum())
print(df[df['payment_value']==0 ].count())
print(df[df['payment_value']==0].sum())
print(df[df['payment_value']==0])
print(df[df['payment_value']==0]['payment_type'].value_counts(dropna=False))
print(df['payment_type'].value_counts(dropna=False))
pay_not_defined = df[df['payment_type'] == 'not_defined']
print(pay_not_defined)
for oid in pay_not_defined['order_id']:
    print(df[df['order_id']==oid])

agg_field=df.groupby('payment_type').agg(
    avg_pay=('payment_value','mean'),
    total_pay=('payment_value','sum'),
    mx_pay=('payment_value','max'),
    mn_pay=('payment_value', 'min')
).sort_values('mx_pay',ascending=True)

print(agg_field)


print (df[(df['payment_type']=='credit_card') & (df['payment_value'] < 1)])

below_dollar=df[df['payment_value'] <1 ]

print(below_dollar.groupby('payment_type').size())

exmaple=below_dollar[below_dollar['payment_type']=='credit_card'].iloc[0]
print(df[df['order_id']== exmaple['order_id']])

below_dollar_credit= below_dollar[below_dollar['payment_type']=='credit_card']
counts_for_these= below_dollar_credit['order_id'].map(multi)
print((counts_for_these == 1).sum())