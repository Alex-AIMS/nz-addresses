#!/bin/bash
set -e

# Simple script to download LINZ suburbs via their web interface download link
# This uses the direct download URL format from LINZ

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DATA_DIR="$SCRIPT_DIR/../data"
mkdir -p "$DATA_DIR"

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*"
}

log "Downloading LINZ Suburbs via web download..."
log "Note: This downloads a ZIP file that you'll need to extract"
log ""

# LINZ download URL (this is the public download, no auth needed for some layers)
DOWNLOAD_URL="https://nz-geodetic.s3.ap-southeast-2.amazonaws.com/linz-data/nz-suburbs-and-localities-SHP.zip"

# Try the public S3 bucket first
OUTPUT_ZIP="$DATA_DIR/suburbs_shp.zip"

curl -L -o "$OUTPUT_ZIP" "$DOWNLOAD_URL" 2>&1 || {
    log "Public download failed. You need to download manually:"
    log ""
    log "Option 1 - Via Browser:"
    log "  1. Go to: https://data.linz.govt.nz/layer/113764-nz-suburbs-and-localities/"
    log "  2. Sign in (free account)"
    log "  3. Click 'Export' > Select 'Shapefile' or 'GeoPackage'"
    log "  4. Save to: $DATA_DIR/"
    log ""
    log "Option 2 - Using wget with your API key:"
    log "  wget -O $OUTPUT_ZIP 'https://data.linz.govt.nz/services/api/v1/exports/<export-id>/download/'"
    exit 1
}

if [ -f "$OUTPUT_ZIP" ] && [ -s "$OUTPUT_ZIP" ]; then
    log "Downloaded: $OUTPUT_ZIP"
    log "Extracting..."
    unzip -o "$OUTPUT_ZIP" -d "$DATA_DIR/suburbs_geometry/"
    log "Files extracted to: $DATA_DIR/suburbs_geometry/"
    log ""
    log "Next: Run import_suburb_geometries.sh to load into database"
else
    log "Download failed - file is empty or doesn't exist"
    exit 1
fi
