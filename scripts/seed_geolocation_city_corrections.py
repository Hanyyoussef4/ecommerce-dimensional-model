import pandas as pd
from sqlalchemy import create_engine, text
df = pd.read_csv('notes/geolocation_city_corrections.csv')

engine = create_engine ('postgresql+psycopg2://hany:@localhost:5432/ecommerce_dw')

df.to_sql('seed_geolocation_city_corrections', engine, if_exists='replace', index=False)

conn = engine.connect()

result = conn.execute(text("select count(*) from seed_geolocation_city_corrections"))

print(f'total rows loaded is {result.scalar()}')

conn.close()




