#!/usr/bin/env python3

import json
import subprocess

INPUT_FILE = "/home/alex/dev/nz-addresses/data/suburbs_with_geometry.geojson"
BATCH_SIZE = 100

def run_sql(sql):
    proc = subprocess.Popen(
        ['docker', 'exec', '-i', 'nz-addresses', 'psql', '-U', 'nzuser', '-d', 'nz_addresses_db'],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True
    )
    stdout, stderr = proc.communicate(input=sql)
    if proc.returncode != 0:
        print(f"ERROR: {stderr}")
        return False
    return True

print("[INFO] Loading GeoJSON...")
with open(INPUT_FILE) as f:
    data = json.load(f)

features = data['features']
print(f"[INFO] Processing {len(features)} suburbs in batches of {BATCH_SIZE}...")

# Column should already be created with correct SRID
# (run manually first: ALTER TABLE nz_addresses.suburbs DROP COLUMN IF EXISTS geom CASCADE; 
#  ALTER TABLE nz_addresses.suburbs ADD COLUMN geom geometry(MultiPolygon, 4326);)

# Process in batches
for batch_start in range(0, len(features), BATCH_SIZE):
    batch = features[batch_start:batch_start + BATCH_SIZE]
    
    sql = "BEGIN;\n"
    for feature in batch:
        sid = feature['properties']['suburb_id']
        geom_json = json.dumps(feature['geometry']).replace("'", "''")
        sql += f"UPDATE nz_addresses.suburbs SET geom = ST_GeomFromGeoJSON('{geom_json}') WHERE suburb_id = '{sid}';\n"
    sql += "COMMIT;\n"
    
    if not run_sql(sql):
        print(f"[ERROR] Batch starting at {batch_start} failed!")
        break
    
    print(f"[INFO] Processed {min(batch_start + BATCH_SIZE, len(features))}/{len(features)} suburbs...")

# Create index
print("[INFO] Creating spatial index...")
run_sql("""
CREATE INDEX IF NOT EXISTS idx_suburbs_geom ON nz_addresses.suburbs USING GIST(geom);
ANALYZE nz_addresses.suburbs;
""")

# Show stats
result = subprocess.run(
    ['docker', 'exec', '-i', 'nz-addresses', 'psql', '-U', 'nzuser', '-d', 'nz_addresses_db', '-c',
     "SELECT COUNT(*) as total, COUNT(geom) as with_geom, ROUND(100.0 * COUNT(geom) / COUNT(*), 1) || '%' as coverage FROM nz_addresses.suburbs;"],
    capture_output=True, text=True
)
print(result.stdout)
print("[INFO] ✓ Import complete")
