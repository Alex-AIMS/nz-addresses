#!/usr/bin/env python3

import json
import subprocess
import sys

INPUT_FILE = "/home/alex/dev/nz-addresses/data/suburbs_with_geometry.geojson"

print("[INFO] Loading GeoJSON...")
with open(INPUT_FILE) as f:
    data = json.load(f)

features = data['features']
print(f"[INFO] Processing {len(features)} suburbs...")

# Build SQL
sql = """
ALTER TABLE nz_addresses.suburbs ADD COLUMN IF NOT EXISTS geom geometry(MultiPolygon, 4326);
BEGIN;
"""

for i, feature in enumerate(features):
    sid = feature['properties']['suburb_id']
    geom_json = json.dumps(feature['geometry']).replace("'", "''")
    sql += f"UPDATE nz_addresses.suburbs SET geom = ST_SetSRID(ST_GeomFromGeoJSON('{geom_json}'), 4326) WHERE suburb_id = {sid};\n"
    
    if (i + 1) % 500 == 0:
        print(f"[INFO] Prepared {i+1}/{len(features)} updates...")

sql += """
COMMIT;
CREATE INDEX IF NOT EXISTS idx_suburbs_geom ON nz_addresses.suburbs USING GIST(geom);
ANALYZE nz_addresses.suburbs;
SELECT COUNT(*) as total, COUNT(geom) as with_geom, ROUND(100.0 * COUNT(geom) / COUNT(*), 1) || '%' as coverage FROM nz_addresses.suburbs;
"""

print("[INFO] Executing SQL...")
proc = subprocess.Popen(
    ['docker', 'exec', '-i', 'nz-addresses', 'psql', '-U', 'nzuser', '-d', 'nz_addresses_db'],
    stdin=subprocess.PIPE,
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
    text=True
)

stdout, stderr = proc.communicate(input=sql)

if proc.returncode == 0:
    print(stdout)
    print("[INFO] ✓ Import complete")
else:
    print("[ERROR]", stderr, file=sys.stderr)
    sys.exit(1)
