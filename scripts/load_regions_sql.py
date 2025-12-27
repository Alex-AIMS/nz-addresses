#!/usr/bin/env python3
"""Load regions from CSV to database"""
import csv
import psycopg2

# Connect to database
conn = psycopg2.connect("postgresql://nzuser:nzpass@localhost:5432/nz_addresses_db")
cur = conn.cursor()

# Read CSV and insert
with open("/home/appuser/data/regional-councils-correct.csv") as f:
    reader = csv.DictReader(f)
    for row in reader:
        cur.execute(
            "INSERT INTO nz_addresses.regions (region_id, name) VALUES (%s, %s)",
            (row["region_id"], row["name"])
        )

conn.commit()

# Verify
cur.execute("SELECT COUNT(*) FROM nz_addresses.regions")
count = cur.fetchone()[0]
print(f"✓ Loaded {count} regions")

# Show sample
cur.execute("SELECT * FROM nz_addresses.regions ORDER BY name LIMIT 5")
for row in cur.fetchall():
    print(f"  {row[0]}: {row[1]}")

cur.close()
conn.close()
