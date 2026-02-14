#!/bin/bash

# Import suburb geometries - simple version using direct UPDATE
set -e

INPUT_FILE="/home/alex/dev/nz-addresses/data/suburbs_with_geometry.geojson"

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

log "Importing $( jq '.features | length' "$INPUT_FILE") suburb geometries..."

# Add geom column
docker exec -i nz-addresses psql -U nzuser -d nz_addresses_db -c "
ALTER TABLE nz_addresses.suburbs ADD COLUMN IF NOT EXISTS geom geometry(MultiPolygon, 4326);
"

# Process each feature and update directly
jq -r '.features[] | @json' "$INPUT_FILE" | while read -r feature; do
    suburb_id=$(echo "$feature" | jq -r '.properties.suburb_id')
    geom_json=$(echo "$feature" | jq -c '.geometry')
    
    # Update this suburb's geometry
    docker exec -i nz-addresses psql -U nzuser -d nz_addresses_db -c "
UPDATE nz_addresses.suburbs 
SET geom = ST_SetSRID(ST_GeomFromGeoJSON('$geom_json'), 4326)
WHERE suburb_id = $suburb_id;
" > /dev/null
    
    # Progress indicator
    if [ $((suburb_id % 100)) == 0 ]; then
        log "Processed $suburb_id suburbs..."
    fi
done

log "Creating spatial index..."
docker exec -i nz-addresses psql -U nzuser -d nz_addresses_db << 'EOF'

CREATE INDEX IF NOT EXISTS idx_suburbs_geom ON nz_addresses.suburbs USING GIST(geom);
ANALYZE nz_addresses.suburbs;

SELECT 
    COUNT(*) as total_suburbs,
    COUNT(geom) as suburbs_with_geom,
    ROUND(100.0 * COUNT(geom) / COUNT(*), 2) || '%' as coverage
FROM nz_addresses.suburbs;

EOF

log "✓ Import complete"
