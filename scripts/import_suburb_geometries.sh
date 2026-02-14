#!/bin/bash

# Import suburb geometries from GeoJSON into database
set -e

INPUT_FILE="/home/alex/dev/nz-addresses/data/suburbs_with_geometry.geojson"

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

log "Importing suburb geometries into database..."

# Create temporary table and import geometries
docker exec -i nz-addresses psql -U nzuser -d nz_addresses_db << 'EOF'

-- Add geom column if it doesn't exist
ALTER TABLE nz_addresses.suburbs ADD COLUMN IF NOT EXISTS geom geometry(MultiPolygon, 4326);

-- Create temporary staging table
DROP TABLE IF EXISTS temp_suburb_geoms;
CREATE TEMP TABLE temp_suburb_geoms (
    suburb_id INTEGER,
    geom_json TEXT
);

\timing on

EOF

log "Extracting geometries from GeoJSON..."

# Extract geometries for each suburb and prepare SQL
jq -r '.features[] | 
    [.properties.suburb_id, (.geometry | tostring)] | 
    @tsv' "$INPUT_FILE" | while IFS=$'\t' read -r sid geom_json; do
    
    # Escape single quotes in JSON
    geom_json_escaped=$(echo "$geom_json" | sed "s/'/''/g")
    
    echo "INSERT INTO temp_suburb_geoms (suburb_id, geom_json) VALUES ($sid, '$geom_json_escaped');"
done | docker exec -i nz-addresses psql -U nzuser -d nz_addresses_db

log "Updating suburbs table with geometries..."

# Update suburbs table
docker exec -i nz-addresses psql -U nzuser -d nz_addresses_db << 'EOF'

UPDATE nz_addresses.suburbs s
SET geom = ST_SetSRID(ST_GeomFromGeoJSON(t.geom_json), 4326)
FROM temp_suburb_geoms t
WHERE s.suburb_id = t.suburb_id;

-- Create spatial index
CREATE INDEX IF NOT EXISTS idx_suburbs_geom ON nz_addresses.suburbs USING GIST(geom);

-- Show statistics
SELECT 
    COUNT(*) as total_suburbs,
    COUNT(geom) as suburbs_with_geom,
    ROUND(100.0 * COUNT(geom) / COUNT(*), 2) as pct_coverage
FROM nz_addresses.suburbs;

EOF

log "✓ Geometry import complete"
