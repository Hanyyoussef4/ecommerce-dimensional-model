"""
create_database.py

One-time setup script: creates the `ecommerce_dw` Postgres database.

CREATE DATABASE cannot run inside a transaction block, so this script
uses psycopg2 directly (not SQLAlchemy) and explicitly enables
autocommit mode on the connection before running it.
"""

import psycopg2

# --- Configuration ----------------------------------------------------
# Update these to match your local Postgres install.
PG_HOST = "localhost"
PG_PORT = 5432
PG_USER = "hany"
PG_PASSWORD = ""

# WHY: ecommerce_dw doesn't exist yet, so we need to connect to an
# existing database first -- just to have a place to run CREATE DATABASE
# from. Most Postgres installs ship a default "postgres" database for
# exactly this purpose.
#
# If your install doesn't have one (uncommon, but possible depending on
# how Postgres was installed -- this repo's own author needed to use
# "template1" instead), change this to any other existing database on
# your system.
LANDING_DB = "template1"

NEW_DB_NAME = "ecommerce_dw"

# --- Connect to Postgres ------------------------------------------------
conn = psycopg2.connect(
    host=PG_HOST,
    port=PG_PORT,
    dbname=LANDING_DB,
    user=PG_USER,
    password=PG_PASSWORD
)

# Required before running CREATE DATABASE -- see module docstring.
conn.autocommit = True

cur = conn.cursor()

cur.execute("SELECT 1 FROM pg_database WHERE datname = %s", (NEW_DB_NAME,))
result = cur.fetchone()

if result is None:
    cur.execute(f"CREATE DATABASE {NEW_DB_NAME}")
    print(f"Database '{NEW_DB_NAME}' created.")
else:
    print(f"Database '{NEW_DB_NAME}' already exists — nothing to do.")


cur.close()
conn.close()