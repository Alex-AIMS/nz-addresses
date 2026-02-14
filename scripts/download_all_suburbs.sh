#!/bin/bash

# Fetch ALL suburb geometries in parallel - fixed version
set -e

LINZ_API_KEY="b41cea1a09884c03b478ec364ca0086b"
LAYER_ID="113764"
OUTPUT_DIR="/home/alex/dev/nz-addresses/data/suburb_geometries"
FINAL_OUTPUT="/home/alex/dev/nz-addresses/data/suburbs_with_geometry.geojson"
PARALLEL_JOBS=30

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

mkdir -p "$OUTPUT_DIR"

log "Fetching ALL suburb centroids from database..."

# Get all suburbs with centroids transformed to WGS84
docker exec -i nz-addresses psql -U nzuser -d nz_addresses_db -t -A -F$'\t' -c "
SELECT 
    s.suburb_id,
    s.district_id,
    ST_X(ST_Transform(ST_Centroid(ST_Collect(a.geom)), 4326)) as lon,
    ST_Y(ST_Transform(ST_Centroid(ST_Collect(a.geom)), 4326)) as lat
FROM nz_addresses.suburbs s
JOIN nz_addresses.addresses a ON LOWER(TRIM(a.suburb_locality)) = LOWER(TRIM(s.name))
WHERE a.geom IS NOT NULL
GROUP BY s.suburb_id, s.district_id
ORDER BY s.suburb_id;
" > /tmp/suburbs_to_fetch.tsv

TOTAL=$(wc -l < /tmp/suburbs_to_fetch.tsv)
log "Found $TOTAL suburbs to fetch"

# Check how many already downloaded
EXISTING=$(ls "$OUTPUT_DIR"/*.json 2>/dev/null | wc -l)
if [ "$EXISTING" -gt 0 ]; then
    log "Found $EXISTING already downloaded, skipping those..."
fi

log "Starting parallel download with $PARALLEL_JOBS workers..."

# Parallel download function
fetch_one() {
    local line="$1"
    IFS=$'\t' read -r sid did lon lat <<< "$line"
    
    # Skip if already exists
    if [ -f "${OUTPUT_DIR}/${sid}.json" ]; then
        return 0
    fi
    
    local url="https://data.linz.govt.nz/services/query/v1/vector.json?key=${LINZ_API_KEY}&layer=${LAYER_ID}&x=${lon}&y=${lat}&max_results=1&radius=50000&geometry=true&with_field_names=true"
    
    local response=$(curl -s "$url")
    
    if echo "$response" | jq -e ".vectorQuery.layers.\"${LAYER_ID}\".features[0]" > /dev/null 2>&1; then
        echo "$response" | jq ".vectorQuery.layers.\"${LAYER_ID}\".features[0] | .properties.suburb_id = ${sid} | .properties.district_id = ${did}" > "${OUTPUT_DIR}/${sid}.json" 2>/dev/null && echo -n "." || echo -n "x"
    else
        echo -n "x"
    fi
}

export -f fetch_one
export LINZ_API_KEY LAYER_ID OUTPUT_DIR

# Use GNU parallel if available, otherwise xargs
if command -v parallel &> /dev/null; then
    cat /tmp/suburbs_to_fetch.tsv | parallel -j $PARALLEL_JOBS fetch_one
else
    cat /tmp/suburbs_to_fetch.tsv | xargs -P $PARALLEL_JOBS -I{} bash -c 'fetch_one "{}"'
fi

echo ""
log "Combining JSON files..."

echo '{"type":"FeatureCollection","features":[' > "$FINAL_OUTPUT"
FIRST=true
for file in "$OUTPUT_DIR"/*.json; do
    if [ -f "$file" ]; then
        [ "$FIRST" = false ] && echo "," >> "$FINAL_OUTPUT"
        cat "$file" >> "$FINAL_OUTPUT"
        FIRST=false
    fi
done
echo ']}' >> "$FINAL_OUTPUT"

FEATURE_COUNT=$(jq '.features | length' "$FINAL_OUTPUT")
SIZE=$(du -h "$FINAL_OUTPUT" | cut -f1)

log "✓ Downloaded $FEATURE_COUNT geometries out of $TOTAL suburbs"
log "✓ Output: $FINAL_OUTPUT ($SIZE)"

rm -rf "$OUTPUT_DIR" /tmp/suburbs_to_fetch.tsv
