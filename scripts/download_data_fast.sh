#!/bin/bash
set -e

# Load configuration if available
CONFIG_FILE="${CONFIG_FILE:-/home/appuser/config.env}"
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
fi

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

DATA_DIR="$(cd "$(dirname "$0")" && pwd)/data"
mkdir -p "$DATA_DIR"

log "Starting FAST data download using LINZ export API..."
log "Data directory: $DATA_DIR"

# Check for LINZ API key
if [ -z "$LINZ_API_KEY" ]; then
    log "ERROR: LINZ_API_KEY environment variable not set"
    log "Please set it in config.env or pass as environment variable"
    log "Get your free API key from: https://data.linz.govt.nz/"
    exit 1
fi

# Check for Stats NZ API key
if [ -z "$STATSNZ_API_KEY" ]; then
    log "ERROR: STATSNZ_API_KEY environment variable not set"
    log "Please set it in config.env or pass as environment variable"
    log "Get your free API key from: https://datafinder.stats.govt.nz/"
    exit 1
fi

# Check if addresses file already exists and is complete
if [ -f "$DATA_DIR/nz_addresses.csv" ]; then
    FILE_SIZE=$(stat -f%z "$DATA_DIR/nz_addresses.csv" 2>/dev/null || stat -c%s "$DATA_DIR/nz_addresses.csv" 2>/dev/null)
    FILE_SIZE_MB=$((FILE_SIZE / 1024 / 1024))
    
    if [ $FILE_SIZE_MB -gt 700 ]; then
        log "✓ NZ Addresses already downloaded (${FILE_SIZE_MB}MB) - skipping"
        SKIP_ADDRESSES=true
    else
        log "⚠ NZ Addresses exists but too small (${FILE_SIZE_MB}MB) - will re-download"
        SKIP_ADDRESSES=false
    fi
else
    SKIP_ADDRESSES=false
fi

if [ "$SKIP_ADDRESSES" = "false" ]; then
    # Use LINZ Export API - creates async export job (much faster than WFS for large datasets)
    log "Method: LINZ Export API (async export, then download prepared file)"
    log ""
    log "Step 1/2: Requesting export of NZ Addresses (layer 105689)..."
    log "This triggers LINZ to prepare a CSV export file in the background"

    # Note: The export API endpoint format (this is conceptual - actual endpoint may vary)
    # For now, using direct layer export which LINZ prepares
    EXPORT_URL="https://data.linz.govt.nz/services;key=${LINZ_API_KEY}/exports/layer-105689-nz-street-address-electoral?format=csv"

log ""
log "Addresses: Using pre-generated export URL (bypasses slow WFS streaming)"
log "If this fails, you'll need to manually request an export from the LINZ website"

# Try direct layer export endpoint
wget --progress=bar:force --timeout=10 --tries=999 --retry-connrefused --waitretry=1 --read-timeout=10 --continue \
    -O "$DATA_DIR/nz_addresses.csv" \
    "https://data.linz.govt.nz/services;key=${LINZ_API_KEY}/layer/105689/export/csv" \
    2>&1 || {
    log "Direct export failed. Using WFS with aggressive retry and timeout settings..."
    log "Download will auto-restart if it stalls for more than 10 seconds"
    
    # WFS with aggressive retry: if no data received for 10s, restart automatically
    wget --progress=bar:force:noscroll \
        --timeout=10 \
        --tries=999 \
        --retry-connrefused \
        --waitretry=1 \
        --read-timeout=10 \
        --continue \
        -O "$DATA_DIR/nz_addresses.csv" \
        "https://data.linz.govt.nz/services;key=${LINZ_API_KEY}/wfs/layer-105689?service=WFS&version=2.0.0&request=GetFeature&typeNames=layer-105689&outputFormat=csv" \
        2>&1
}

log "✓ Addresses downloaded ($(du -h "$DATA_DIR/nz_addresses.csv" | cut -f1))"
else
    log "Addresses download skipped (file already exists)"
fi

# Localities - smaller dataset, WFS is fine
log ""
log "Downloading NZ Localities..."

# Check if already exists
if [ -f "$DATA_DIR/suburbs_localities.csv" ] && [ -s "$DATA_DIR/suburbs_localities.csv" ]; then
    log "✓ Localities already downloaded - skipping"
else
    log "Trying LINZ layer 113764 (NZ Suburbs and Localities)..."
    
    # Try CSV format first (easiest to work with)
    wget --progress=bar:force --timeout=60 --tries=10 --retry-connrefused --waitretry=1 --read-timeout=30 --continue \
        -O "$DATA_DIR/suburbs_localities.csv" \
        "https://data.linz.govt.nz/services;key=${LINZ_API_KEY}/wfs/layer-113764?service=WFS&version=2.0.0&request=GetFeature&typeNames=layer-113764&outputFormat=csv" \
        2>&1 || {
        
        # Fallback to GeoJSON
        log "CSV failed, trying GeoJSON format..."
        wget --progress=bar:force --timeout=60 --tries=10 --retry-connrefused --waitretry=1 --read-timeout=30 --continue \
            -O "$DATA_DIR/suburbs_localities.geojson" \
            "https://data.linz.govt.nz/services;key=${LINZ_API_KEY}/wfs/layer-113764?service=WFS&version=2.0.0&request=GetFeature&typeNames=layer-113764&outputFormat=json" \
            2>&1 || {
            log "⚠ WARNING: Could not download localities automatically"
            log "   This is optional - you can manually download from:"
            log "   https://data.linz.govt.nz/layer/113764-nz-suburbs-and-localities/"
        }
    }
    
    # Check what we got
    if [ -f "$DATA_DIR/suburbs_localities.csv" ] && [ -s "$DATA_DIR/suburbs_localities.csv" ]; then
        log "✓ Localities downloaded successfully (CSV format)"
    elif [ -f "$DATA_DIR/suburbs_localities.geojson" ] && [ -s "$DATA_DIR/suburbs_localities.geojson" ]; then
        log "✓ Localities downloaded successfully (GeoJSON format)"
    else
        log "⚠ Localities download incomplete - skipping (optional)"
    fi
fi

# Stats NZ - Regional Councils (public, fast)
log ""
log "Downloading Stats NZ Regional Councils..."

# Check if already downloaded
log ""
log "Downloading Stats NZ Regional Councils..."
REGIONS_FOUND=false
if ls "$DATA_DIR"/*regional*.shp 2>/dev/null | grep -q .; then
    log "✓ Regional boundaries already downloaded - skipping"
    REGIONS_FOUND=true
fi

if [ "$REGIONS_FOUND" = "false" ]; then
    wget --progress=bar:force --timeout=60 --tries=10 --retry-connrefused --waitretry=1 --read-timeout=30 --continue \
        -O "$DATA_DIR/regional-councils.csv" \
        "https://datafinder.stats.govt.nz/services;key=${STATSNZ_API_KEY}/wfs/layer-111179?service=WFS&version=2.0.0&request=GetFeature&typeNames=layer-111179&outputFormat=csv" \
        2>&1 || {
        log "⚠ WARNING: Could not download regional boundaries automatically"
        log "   Please manually download from:"
        log "   https://datafinder.stats.govt.nz/layer/111179-regional-council-2023-clipped-generalised/"
    }
    
    if [ -f "$DATA_DIR/regional-councils.csv" ] && [ -s "$DATA_DIR/regional-councils.csv" ]; then
        log "✓ Regional councils downloaded successfully"
    fi
fi

log ""
log "Downloading Stats NZ Territorial Authorities..."
DISTRICTS_FOUND=false
if ls "$DATA_DIR"/*territorial*.shp 2>/dev/null | grep -q .; then
    log "✓ Territorial authority boundaries already downloaded - skipping"
    DISTRICTS_FOUND=true
fi

if [ "$DISTRICTS_FOUND" = "false" ]; then
    wget --progress=bar:force --timeout=60 --tries=10 --retry-connrefused --waitretry=1 --read-timeout=30 --continue \
        -O "$DATA_DIR/territorial-authorities.csv" \
        "https://datafinder.stats.govt.nz/services;key=${STATSNZ_API_KEY}/wfs/layer-111183?service=WFS&version=2.0.0&request=GetFeature&typeNames=layer-111183&outputFormat=csv" \
        2>&1 || {
        log "⚠ WARNING: Could not download territorial authority boundaries automatically"
        log "   Please manually download from:"
        log "   https://datafinder.stats.govt.nz/layer/111183-territorial-authority-2023-clipped-generalised/"
    }
    
    if [ -f "$DATA_DIR/territorial-authorities.csv" ] && [ -s "$DATA_DIR/territorial-authorities.csv" ]; then
        log "✓ Territorial authorities downloaded successfully"
    fi
fi

log ""
log "========================================="
log "DOWNLOAD COMPLETE"
log "========================================="
log "Files in $DATA_DIR:"
ls -lh "$DATA_DIR"/*.{csv,gpkg,shp} 2>/dev/null || ls -lh "$DATA_DIR"/ | head -20
log ""
log "Next: Run ETL to load into PostgreSQL"
log "  docker exec -it nz-addresses bash -c 'cd /home/appuser && bash scripts/etl.sh local'"
