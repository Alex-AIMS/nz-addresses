#!/bin/bash

# Fetch LINZ suburb geometries in parallel - ONLY for unmapped suburbs
set -e

LINZ_API_KEY="b41cea1a09884c03b478ec364ca0086b"
LAYER_ID="113764"
OUTPUT_DIR="/home/alex/dev/nz-addresses/data/suburb_geometries"
FINAL_OUTPUT="/home/alex/dev/nz-addresses/data/suburbs_with_geometry.geojson"
PARALLEL_JOBS=10  # Fetch 10 suburbs simultaneously

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

# Create output directory
mkdir -p "$OUTPUT_DIR"
rm -f "$OUTPUT_DIR"/*.json 2>/dev/null || true

log "Fetching UNMAPPED suburb centroids from database..."

# Only get suburbs that are NOT matched to Market
SUBURBS_QUERY="
SELECT 
    s.suburb_id,
    s.name,
    s.district_id,
    ST_X(ST_Transform(ST_Centroid(ST_Collect(a.geom)), 4326)) as lon,
    ST_Y(ST_Transform(ST_Centroid(ST_Collect(a.geom)), 4326)) as lat
FROM nz_addresses.suburbs s
JOIN nz_addresses.addresses a ON LOWER(TRIM(a.suburb_locality)) = LOWER(TRIM(s.name))
WHERE a.geom IS NOT NULL 
  AND s.market_match = false
GROUP BY s.suburb_id, s.name, s.district_id
ORDER BY s.suburb_id;
"

SUBURBS=$(docker exec -i nz-addresses psql -U nzuser -d nz_addresses_db -t -A -F'|' -c "$SUBURBS_QUERY")

if [ -z "$SUBURBS" ]; then
    log "ERROR: No unmapped suburbs found"
    exit 1
fi

TOTAL=$(echo "$SUBURBS" | wc -l)
log "Found $TOTAL unmapped suburbs - fetching geometries in parallel..."

# Function to fetch one suburb's geometry
fetch_suburb() {
    local suburb_id=$1
    local name=$2
    local district_id=$3
    local lon=$4
    local lat=$5
    
    local url="https://data.linz.govt.nz/services/query/v1/vector.json?key=${LINZ_API_KEY}&layer=${LAYER_ID}&x=${lon}&y=${lat}&max_results=1&radius=50000&geometry=true&with_field_names=true"
    
    local response=$(curl -s "$url")
    local feature=$(echo "$response" | jq ".vectorQuery.layers.\"${LAYER_ID}\".features[0]")
    
    if [ "$feature" != "null" ] && [ -n "$feature" ]; then
        echo "$feature" | jq --arg sid "$suburb_id" --arg did "$district_id" '
            .properties.suburb_id = ($sid | tonumber) |
            .properties.district_id = ($did | tonumber)
        ' > "${OUTPUT_DIR}/${suburb_id}.json"
    fi
}

export -f fetch_suburb
export LINZ_API_KEY LAYER_ID OUTPUT_DIR

# Use GNU parallel or xargs for parallel execution
if command -v parallel &> /dev/null; then
    log "Using GNU parallel with $PARALLEL_JOBS jobs..."
    echo "$SUBURBS" | parallel --colsep '|' -j "$PARALLEL_JOBS" fetch_suburb {1} {2} {3} {4} {5}
else
    log "Using xargs with $PARALLEL_JOBS jobs..."
    echo "$SUBURBS" | while IFS='|' read -r sid name did lon lat; do
        echo "$sid|$name|$did|$lon|$lat"
    done | xargs -P "$PARALLEL_JOBS" -I {} bash -c 'IFS="|" read -r sid name did lon lat <<< "{}"; fetch_suburb "$sid" "$name" "$did" "$lon" "$lat"'
fi

# Combine all JSON files into one GeoJSON
log "Combining results into final GeoJSON..."

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
    log "✓ Successfully fetched $FEATURE_COUNT suburb geometries"
    log "✓ Saved to: $FINAL_OUTPUT"
else
    log "ERROR: Invalid GeoJSON"
    exit 1
fi

# Cleanup
rm -rf "$OUTPUT_DIR"
