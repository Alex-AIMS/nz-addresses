#!/bin/bash
set -e

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

DATA_DIR="$(cd "$(dirname "$0")" && pwd)/data"
mkdir -p "$DATA_DIR"

log "Starting WFS-based data download..."
log "Data directory: $DATA_DIR"

# Check for LINZ API key
if [ -z "$LINZ_API_KEY" ]; then
    log "ERROR: LINZ_API_KEY environment variable not set"
    log ""
    log "To get your API key:"
    log "1. Visit https://data.linz.govt.nz/"
    log "2. Click 'Log in' (or create free account)"
    log "3. Go to 'My Account' > 'API' section"
    log "4. Copy your API key"
    log ""
    log "Then set it: export LINZ_API_KEY='your-key-here'"
    log "Or pass it when running docker: docker exec -e LINZ_API_KEY='your-key' nz-addresses bash scripts/download_data_wfs.sh"
    exit 1
fi

# Download NZ Addresses from LINZ using WFS API
log "Downloading LINZ NZ Addresses via WFS API (may take 10-15 minutes, ~500MB CSV)..."
log "URL: https://data.linz.govt.nz/services;key=****/wfs/layer-105689"
wget -O "$DATA_DIR/nz_addresses.csv" \
    "https://data.linz.govt.nz/services;key=${LINZ_API_KEY}/wfs/layer-105689?service=WFS&version=2.0.0&request=GetFeature&typeNames=layer-105689&outputFormat=csv" \
    2>&1 || {
    log "ERROR: WFS download failed for addresses"
    log "Please verify:"
    log "- Your API key is valid"
    log "- You have internet connectivity"
    log "- The layer ID (105689) is still active"
    exit 1
}
log "✓ Addresses downloaded successfully"

# Download NZ Localities from LINZ using WFS API
log "Downloading LINZ NZ Localities via WFS API (~5MB)..."
log "Note: Layer 53353 may not be available via WFS. Trying alternative methods..."

# Try CSV format first (most reliable)
log "Trying CSV format download..."
wget -O "$DATA_DIR/suburbs_localities.csv" \
    "https://data.linz.govt.nz/services;key=${LINZ_API_KEY}/wfs/layer-53353?service=WFS&version=2.0.0&request=GetFeature&typeNames=layer-53353&outputFormat=csv" \
    2>&1 && {
    log "✓ Downloaded as CSV, converting to GeoPackage..."
    ogr2ogr -f "GPKG" "$DATA_DIR/suburbs_localities.gpkg" "$DATA_DIR/suburbs_localities.csv" -oo GEOM_POSSIBLE_NAMES=geom -oo KEEP_GEOM_COLUMNS=NO
} || {
    log "CSV download failed. Localities layer may need manual download."
    log "You can continue without localities - the ETL will use address suburb names instead."
    log "To download manually: https://data.linz.govt.nz/layer/53353-nz-locality/"
    log "Continuing with other datasets..."
}
log "✓ Localities step completed (check above for status)"

# Download Regional Council boundaries from Stats NZ
log "Downloading Stats NZ Regional Council boundaries..."
log "Note: Stats NZ WFS is publicly available (no API key required)"
ogr2ogr -f "ESRI Shapefile" "$DATA_DIR/regional-council.shp" \
    "WFS:https://datafinder.stats.govt.nz/services/wfs/layer-111179-regional-council-2023-clipped-generalised" \
    2>&1 || {
    log "WARNING: WFS failed, trying direct query API..."
    wget -O "$DATA_DIR/regions.zip" \
        "https://datafinder.stats.govt.nz/services/query/v1/vector.zip?layer=111179" \
        2>&1 || {
        log "ERROR: Could not download regional boundaries"
        log "Please download manually from: https://datafinder.stats.govt.nz/layer/111179-regional-council-2023-clipped-generalised/"
        exit 1
    }
    
    if [ -f "$DATA_DIR/regions.zip" ]; then
        log "Extracting regional boundaries..."
        unzip -o "$DATA_DIR/regions.zip" -d "$DATA_DIR" 2>&1
    fi
}
log "✓ Regional boundaries downloaded successfully"

# Download Territorial Authority boundaries from Stats NZ
log "Downloading Stats NZ Territorial Authority boundaries..."
ogr2ogr -f "ESRI Shapefile" "$DATA_DIR/territorial-authority.shp" \
    "WFS:https://datafinder.stats.govt.nz/services/wfs/layer-111183-territorial-authority-2023-clipped-generalised" \
    2>&1 || {
    log "WARNING: WFS failed, trying direct query API..."
    wget -O "$DATA_DIR/districts.zip" \
        "https://datafinder.stats.govt.nz/services/query/v1/vector.zip?layer=111183" \
        2>&1 || {
        log "ERROR: Could not download territorial authority boundaries"
        log "Please download manually from: https://datafinder.stats.govt.nz/layer/111183-territorial-authority-2023-clipped-generalised/"
        exit 1
    }
    
    if [ -f "$DATA_DIR/districts.zip" ]; then
        log "Extracting territorial authority boundaries..."
        unzip -o "$DATA_DIR/districts.zip" -d "$DATA_DIR" 2>&1
    fi
}
log "✓ Territorial authority boundaries downloaded successfully"

# Verify all required files exist
log ""
log "Verifying downloaded files..."
MISSING_FILES=0

if [ ! -f "$DATA_DIR/nz_addresses.csv" ]; then
    log "✗ MISSING: nz_addresses.csv"
    MISSING_FILES=1
else
    SIZE=$(du -h "$DATA_DIR/nz_addresses.csv" | cut -f1)
    log "✓ nz_addresses.csv ($SIZE)"
fi

if [ ! -f "$DATA_DIR/suburbs_localities.gpkg" ]; then
    log "⚠ OPTIONAL: suburbs_localities.gpkg (can derive from addresses)"
else
    SIZE=$(du -h "$DATA_DIR/suburbs_localities.gpkg" | cut -f1)
    log "✓ suburbs_localities.gpkg ($SIZE)"
fi

# Check for shapefiles (multiple files per shapefile)
if [ ! -f "$DATA_DIR/regional-council.shp" ] && [ ! -f "$DATA_DIR"/*.shp ]; then
    log "✗ MISSING: Regional council shapefiles"
    MISSING_FILES=1
else
    log "✓ Regional council shapefiles found"
fi

if [ ! -f "$DATA_DIR/territorial-authority.shp" ] && [ ! -f "$DATA_DIR"/*.shp ]; then
    log "✗ MISSING: Territorial authority shapefiles"
    MISSING_FILES=1
else
    log "✓ Territorial authority shapefiles found"
fi

log ""
if [ $MISSING_FILES -eq 0 ]; then
    log "SUCCESS: All data files downloaded!"
    log ""
    log "Next steps:"
    log "1. Run the ETL script to load data into PostgreSQL:"
    log "   docker exec -it nz-addresses bash -c 'cd /home/appuser && bash scripts/etl.sh local'"
    log ""
    log "2. Test the API:"
    log "   curl http://localhost:8080/regions"
else
    log "ERROR: Some files are missing. Please check the logs above."
    exit 1
fi
