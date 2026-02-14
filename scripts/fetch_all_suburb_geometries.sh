#!/bin/bash

# Fetch all LINZ suburb geometries using the query API
# This script queries the database for all suburbs, then fetches geometry for each

set -e

LINZ_API_KEY="b41cea1a09884c03b478ec364ca0086b"
LAYER_ID="113764"
OUTPUT_FILE="/home/alex/dev/nz-addresses/data/suburbs_with_geometry.geojson"

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

# Get database connection details from environment or defaults
DB_HOST="${DB_HOST:-localhost}"
DB_PORT="${DB_PORT:-5433}"
DB_NAME="${DB_NAME:-nz_addresses}"
DB_USER="${DB_USER:-postgres}"

log "Fetching suburb centroids from database..."

# Get all suburbs with their centroids (computed from addresses)
SUBURBS_QUERY="
SELECT 
    s.suburb_id,
    s.name,
    s.district_id,
    ST_X(ST_Centroid(ST_Collect(a.geom))) as lon,
    ST_Y(ST_Centroid(ST_Collect(a.geom))) as lat,
    COUNT(a.address_id) as address_count
FROM nz_addresses.suburbs s
JOIN nz_addresses.addresses a ON LOWER(TRIM(a.suburb_locality)) = LOWER(TRIM(s.name))
WHERE a.geom IS NOT NULL
GROUP BY s.suburb_id, s.name, s.district_id
ORDER BY s.suburb_id;
"

# Fetch suburb centroids
SUBURBS=$(PGPASSWORD=postgres psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -t -A -F'|' -c "$SUBURBS_QUERY")

if [ -z "$SUBURBS" ]; then
    log "ERROR: No suburbs found in database"
    exit 1
fi

SUBURB_COUNT=$(echo "$SUBURBS" | wc -l)
log "Found $SUBURB_COUNT suburbs with address centroids"

# Initialize GeoJSON file
cat > "$OUTPUT_FILE" << 'EOF'
{
  "type": "FeatureCollection",
  "features": [
EOF

COUNTER=0
TOTAL=$SUBURB_COUNT

# Fetch geometry for each suburb
while IFS='|' read -r suburb_id name district_id lon lat address_count; do
    COUNTER=$((COUNTER + 1))
    
    # Progress indicator
    if [ $((COUNTER % 100)) -eq 0 ]; then
        log "Progress: $COUNTER / $TOTAL suburbs processed..."
    fi
    
    # Query LINZ API for suburb geometry at this location
    QUERY_URL="https://data.linz.govt.nz/services/query/v1/vector.json?key=${LINZ_API_KEY}&layer=${LAYER_ID}&x=${lon}&y=${lat}&max_results=1&radius=50000&geometry=true&with_field_names=true"
    
    # Fetch suburb geometry
    RESPONSE=$(curl -s "$QUERY_URL")
    
    # Extract the feature from response
    FEATURE=$(echo "$RESPONSE" | jq ".vectorQuery.layers.\"${LAYER_ID}\".features[0]")
    
    if [ "$FEATURE" != "null" ] && [ -n "$FEATURE" ]; then
        # Add our custom properties
        ENHANCED_FEATURE=$(echo "$FEATURE" | jq --arg sid "$suburb_id" --arg did "$district_id" --arg ac "$address_count" '
            .properties.suburb_id = ($sid | tonumber) |
            .properties.district_id = ($did | tonumber) |
            .properties.address_count = ($ac | tonumber)
        ')
        
        # Add comma if not first feature
        if [ $COUNTER -gt 1 ]; then
            echo "," >> "$OUTPUT_FILE"
        fi
        
        echo "$ENHANCED_FEATURE" >> "$OUTPUT_FILE"
    else
        log "WARNING: No geometry found for suburb: $name (ID: $suburb_id) at location ($lon, $lat)"
    fi
    
    # Rate limiting - don't overwhelm the API
    sleep 0.1
    
done <<< "$SUBURBS"

# Close GeoJSON
cat >> "$OUTPUT_FILE" << 'EOF'
  ]
}
EOF

log "Successfully fetched geometry for $COUNTER suburbs"
log "Output saved to: $OUTPUT_FILE"
log "Validating GeoJSON..."

# Validate JSON
if jq empty "$OUTPUT_FILE" 2>/dev/null; then
    FEATURE_COUNT=$(jq '.features | length' "$OUTPUT_FILE")
    log "✓ Valid GeoJSON with $FEATURE_COUNT features"
else
    log "ERROR: Invalid GeoJSON generated"
    exit 1
fi
