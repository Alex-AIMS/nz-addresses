#!/bin/bash

# Import suburb geometries efficiently using SQL file
set -e

INPUT_FILE="/home/alex/dev/nz-addresses/data/suburbs_with_geometry.geojson"
SQL_FILE="/tmp/update_suburbs_geom.sql"

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

log "Preparing SQL import script..."

# Create SQL file header
cat > "$SQL_FILE" << 'EOF'
ALTER TABLE nz_addresses.suburbs ADD COLUMN IF NOT EXISTS geom geometry(MultiPolygon, 4326);

BEGIN;
EOF

# Generate UPDATE statements
jq -r '.features[] | 
    "UPDATE nz_addresses.suburbs SET geom = ST_SetSRID(ST_GeomFromGeoJSON(\047" + 
    (.geometry | @json | gsub("\047";"\047\047")) + 
    "\047), 4326) WHERE suburb_id = " + 
    (.properties.suburb_id | tostring) + ";"' "$INPUT_FILE" >> "$SQL_FILE"

# Add commit and index creation
cat >> "$SQL_FILE" << 'EOF'
COMMIT;

CREATE INDEX IF NOT EXISTS idx_suburbs_geom ON nz_addresses.suburbs USING GIST(geom);
ANALYZE nz_addresses.suburbs;

SELECT 
    COUNT(*) as total,
    COUNT(geom) as with_geom,
    ROUND(100.0 * COUNT(geom) / COUNT(*), 1) || '%' as coverage
FROM nz_addresses.suburbs;
EOF

log "Executing SQL import (this may take a minute)..."
docker exec -i nz-addresses psql -U nzuser -d nz_addresses_db < "$SQL_FILE"

rm "$SQL_FILE"
log "✓ Import complete"
