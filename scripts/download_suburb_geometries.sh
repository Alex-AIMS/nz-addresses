#!/bin/bash
set -e

# Download LINZ Suburbs and Localities with geometry data
# Layer: 113764 - NZ Suburbs and Localities
# Using ogr2ogr to download via WFS since it handles the LINZ WFS service correctly

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DATA_DIR="$SCRIPT_DIR/../data"
LINZ_API_KEY="b41cea1a09884c03b478ec364ca0086b"
LAYER_ID="113764"

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*"
}

log "Starting download of LINZ Suburbs and Localities geometry data..."

# Create data directory if it doesn't exist
mkdir -p "$DATA_DIR"

OUTPUT_FILE="$DATA_DIR/suburbs_with_geometry.geojson"

# Check if ogr2ogr is available
if command -v ogr2ogr &> /dev/null; then
    log "Using ogr2ogr to download via WFS..."
    WFS_URL="WFS:https://data.linz.govt.nz/services/wfs/layer-${LAYER_ID}?key=${LINZ_API_KEY}"
    
    ogr2ogr -f GeoJSON "$OUTPUT_FILE" "$WFS_URL" \
      -t_srs EPSG:4326 \
      2>&1 | grep -v "^  %" || true
else
    log "ogr2ogr not found. Please download manually:"
    log ""
    log "1. Visit: https://data.linz.govt.nz/layer/113764-nz-suburbs-and-localities/"
    log "2. Click 'Export' button"
    log "3. Select format: GeoJSON or GeoPackage"
    log "4. Download and save as: $OUTPUT_FILE"
    log ""
    log "Or install GDAL tools: sudo apt-get install gdal-bin"
    exit 1
fi

if [ ! -f "$OUTPUT_FILE" ]; then
    log "ERROR: Download failed!"
    exit 1
fi

FILE_SIZE=$(du -h "$OUTPUT_FILE" | cut -f1)
FEATURE_COUNT=$(cat "$OUTPUT_FILE" | jq '.features | length' 2>/dev/null || echo "unknown")

log "Download complete!"
log "  File: $OUTPUT_FILE"
log "  Size: $FILE_SIZE"
log "  Features: $FEATURE_COUNT"
log ""
log "Next steps:"
log "  1. Run import_suburb_geometries.sh to load into database"
log "  2. Then run map_linz_to_market_suburbs.sh to create mappings"

# Preview first feature
log ""
log "Sample feature:"
cat "$OUTPUT_FILE" | jq '.features[0] | {name: .properties.name, type: .geometry.type}' 2>/dev/null || echo "Could not parse GeoJSON"
