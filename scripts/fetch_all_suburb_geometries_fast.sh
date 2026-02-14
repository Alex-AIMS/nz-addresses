#!/bin/bash

# Fetch ALL suburb geometries in parallel using LINZ query API
set -e

LINZ_API_KEY="b41cea1a09884c03b478ec364ca0086b"
LAYER_ID="113764"
OUTPUT_DIR="/home/alex/dev/nz-addresses/data/suburb_geometries"
FINAL_OUTPUT="/home/alex/dev/nz-addresses/data/suburbs_with_geometry.geojson"
PARALLEL_JOBS=20  # Fetch 20 suburbs simultaneously

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

# Create output directory
mkdir -p "$OUTPUT_DIR"
rm -f "$OUTPUT_DIR"/*.json 2>/dev/null || true

log "Fetching ALL suburb centroids from database..."

# Get all suburbs with their centroids
SUBURBS_QUERY="
SELECT 
    s.suburb_id,
    s.name,
    s.district_id,
    ST_X(ST_Centroid(ST_Collect(a.geom))) as lon,
    ST_Y(ST_Centroid(ST_Collect(a.geom))) as lat
FROM nz_addresses.suburbs s
JOIN nz_addresses.addresses a ON LOWER(TRIM(a.suburb_locality)) = LOWER(TRIM(s.name))
WHERE a.geom IS NOT NULL
GROUP BY s.suburb_id, s.name, s.district_id
ORDER BY s.suburb_id;
"

# Fetch suburb centroids using docker with correct credentials
SUBURBS=$(docker exec -i nz-addresses psql -U nzuser -d nz_addresses_db -t -A -F'|' -c "$SUBURBS_QUERY")

if [ -z "$SUBURBS" ]; then
    log "ERROR: No suburbs found in database"
    exit 1
fi

TOTAL=$(echo "$SUBURBS" | wc -l)
log "Found $TOTAL suburbs - fetching geometries in parallel with $PARALLEL_JOBS workers..."

# Function to fetch one suburb's geometry
fetch_suburb() {
    local suburb_id="$1"
    local name="$2"
    local district_id="$3"
    local lon="$4"
    local lat="$5"
    
    local url="https://data.linz.govt.nz/services/query/v1/vector.json?key=${LINZ_API_KEY}&layer=${LAYER_ID}&x=${lon}&y=${lat}&max_results=1&radius=50000&geometry=true&with_field_names=true"
    
    local response=$(curl -s "$url")
    local feature=$(echo "$response" | jq ".vectorQuery.layers.\"${LAYER_ID}\".features[0]" 2>/dev/null)
    
    if [ "$feature" != "null" ] && [ -n "$feature" ] && [ "$feature" != "" ]; then
        echo "$feature" | jq --arg sid "$suburb_id" --arg did "$district_id" '
            .properties.suburb_id = ($sid | tonumber) |
            .properties.district_id = ($did | tonumber)
        ' > "${OUTPUT_DIR}/${suburb_id}.json" 2>/dev/null
        echo "."
    else
        echo "x"
    fi
}

export -f fetch_suburb
export LINZ_API_KEY LAYER_ID OUTPUT_DIR

# Process in parallel using xargs
log "Starting parallel download..."
echo "$SUBURBS" | while IFS='|' read -r sid name did lon lat; do
    echo "$sid|$name|$did|$lon|$lat"
done | xargs -P "$PARALLEL_JOBS" -I {} bash -c 'IFS="|" read -r sid name did lon lat <<< "{}"; fetch_suburb "$sid" "$name" "$did" "$lon" "$lat"'

echo ""
log "Combining results into final GeoJSON..."

# Combine all JSON files into one GeoJSON
echo '{"type":"FeatureCollection","features":[' > "$FINAL_OUTPUT"

FIRST=true
for file in "$OUTPUT_DIR"/*.json; do
    if [ -f "$file" ]; then
        if [ "$FIRST" = true ]; then
            FIRST=false
        else
            echo "," >> "$FINAL_OUTPUT"
        fi
        cat "$file" >> "$FINAL_OUTPUT"
    fi
done

echo ']}' >> "$FINAL_OUTPUT"

# Validate and report
if jq empty "$FINAL_OUTPUT" 2>/dev/null; then
    FEATURE_COUNT=$(jq '.features | length' "$FINAL_OUTPUT")
    log "✓ Successfully fetched $FEATURE_COUNT suburb geometries out of $TOTAL suburbs"
    log "✓ Saved to: $FINAL_OUTPUT"
    
    # Show file size
    SIZE=$(du -h "$FINAL_OUTPUT" | cut -f1)
    log "✓ File size: $SIZE"
else
    log "ERROR: Invalid GeoJSON generated"
    exit 1
fi

# Cleanup temp directory
rm -rf "$OUTPUT_DIR"
log "Done!"
