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

log "========================================="
log "DOWNLOADING CORRECTED DATASETS"
log "========================================="
log "Data directory: $DATA_DIR"
log ""
log "Changes from previous:"
log "  ✓ REGC2023 (Regional Councils) instead of MCON2023 (Māori Constituencies)"
log "  ✓ TradeMe localities for district alias mapping"
log "  ✓ Will create 16 geographic regions (not 22 electoral constituencies)"
log ""

# Check for API keys
if [ -z "$LINZ_API_KEY" ]; then
    log "ERROR: LINZ_API_KEY environment variable not set"
    log "Please set it in config.env or pass as environment variable"
    log "Get your free API key from: https://data.linz.govt.nz/"
    exit 1
fi

# Download addresses (same as before - this is correct)
log "========================================="
log "1. NZ ADDRESSES (2.4M addresses)"
log "========================================="
if [ -f "$DATA_DIR/nz_addresses.csv" ]; then
    FILE_SIZE_MB=$(stat -c%s "$DATA_DIR/nz_addresses.csv" 2>/dev/null | awk '{print int($1/1024/1024)}')
    if [ $FILE_SIZE_MB -gt 700 ]; then
        log "✓ Already downloaded (${FILE_SIZE_MB}MB) - skipping"
    else
        log "File exists but too small - re-downloading..."
        wget --progress=bar:force --timeout=10 --tries=999 --continue \
            -O "$DATA_DIR/nz_addresses.csv" \
            "https://data.linz.govt.nz/services;key=${LINZ_API_KEY}/wfs/layer-105689?service=WFS&version=2.0.0&request=GetFeature&typeNames=layer-105689&outputFormat=csv"
    fi
else
    log "Downloading NZ Addresses..."
    wget --progress=bar:force --timeout=10 --tries=999 --continue \
        -O "$DATA_DIR/nz_addresses.csv" \
        "https://data.linz.govt.nz/services;key=${LINZ_API_KEY}/wfs/layer-105689?service=WFS&version=2.0.0&request=GetFeature&typeNames=layer-105689&outputFormat=csv"
fi

# Download suburbs/localities (same as before - this is correct)
log ""
log "========================================="
log "2. NZ LOCALITIES (6,562 suburbs)"
log "========================================="
if [ -f "$DATA_DIR/suburbs_localities.csv" ] && [ -s "$DATA_DIR/suburbs_localities.csv" ]; then
    log "✓ Already downloaded - skipping"
else
    log "Downloading NZ Localities..."
    wget --progress=bar:force --timeout=60 --tries=10 --continue \
        -O "$DATA_DIR/suburbs_localities.csv" \
        "https://data.linz.govt.nz/services;key=${LINZ_API_KEY}/wfs/layer-113764?service=WFS&version=2.0.0&request=GetFeature&typeNames=layer-113764&outputFormat=csv" \
        || log "⚠ Localities download failed (optional)"
fi

# Download REGC2023 - Regional Councils (16 geographic regions - THIS IS THE FIX!)
log ""
log "========================================="
log "3. REGIONAL COUNCILS (REGC2023)"
log "========================================="
log "Dataset: Stats NZ Regional Council 2023 (Generalised)"
log "Layer: 111183"
log "Expected: 16 geographic regions (Auckland, Wellington, Canterbury, etc.)"
log ""

if [ -f "$DATA_DIR/regional-councils-correct.csv" ] && [ -s "$DATA_DIR/regional-councils-correct.csv" ]; then
    log "✓ Already downloaded - skipping"
else
    log "Downloading REGC2023 (Regional Councils - Geographic Regions)..."
    wget --progress=bar:force --timeout=60 --tries=10 --continue \
        -O "$DATA_DIR/regional-councils-correct.csv" \
        "https://datafinder.stats.govt.nz/services/query/v1/vector.json?key=&layer=111183&x=174.776&y=-41.289&max=1000&geometry=true&with_field_names=true" \
        2>&1 | head -20
    
    # Check if download succeeded
    if [ -f "$DATA_DIR/regional-councils-correct.csv" ] && [ -s "$DATA_DIR/regional-councils-correct.csv" ]; then
        log "✓ Regional Councils downloaded successfully"
    else
        log "⚠ Download may have failed - checking alternative formats..."
        
        # Try CSV format via WFS
        wget --progress=bar:force --timeout=60 --tries=10 --continue \
            -O "$DATA_DIR/regional-councils-correct.csv" \
            "https://datafinder.stats.govt.nz/services/wfs?service=WFS&version=2.0.0&request=GetFeature&typeNames=v:x111183&outputFormat=csv" \
            || log "⚠ Alternative format also failed"
    fi
fi

# Download territorial authorities (same as before - this is correct)
log ""
log "========================================="
log "4. TERRITORIAL AUTHORITIES (TALB2023)"
log "========================================="
log "Dataset: Stats NZ Territorial Authority/Local Board 2023"
log "Layer: 111197"
log "Expected: 88 districts (67 TAs + 21 Auckland local boards)"
log ""

if [ -f "$DATA_DIR/territorial-authorities.csv" ] && [ -s "$DATA_DIR/territorial-authorities.csv" ]; then
    log "✓ Already downloaded - skipping"
else
    log "Downloading TALB2023 (Territorial Authorities)..."
    wget --progress=bar:force --timeout=60 --tries=10 --continue \
        -O "$DATA_DIR/territorial-authorities.csv" \
        "https://datafinder.stats.govt.nz/services/wfs?service=WFS&version=2.0.0&request=GetFeature&typeNames=v:x111197&outputFormat=csv" \
        || log "⚠ Territorial authorities download failed"
fi

# Download TradeMe localities for alias mapping
log ""
log "========================================="
log "5. TRADEME LOCALITIES (for aliases)"
log "========================================="
log "Purpose: Map our districts to TradeMe's legacy city names"
log "Example: Albert-Eden Local Board → Auckland City"
log ""

if [ -f "$DATA_DIR/trademe_localities.json" ] && [ -s "$DATA_DIR/trademe_localities.json" ]; then
    log "✓ Already downloaded - skipping"
else
    log "Downloading TradeMe localities..."
    curl -s "https://api.trademe.co.nz/v1/Localities.json" > "$DATA_DIR/trademe_localities.json"
    
    if [ -f "$DATA_DIR/trademe_localities.json" ] && [ -s "$DATA_DIR/trademe_localities.json" ]; then
        log "✓ TradeMe localities downloaded successfully"
        
        # Show TradeMe region count for verification
        REGION_COUNT=$(grep -o '"LocalityId":' "$DATA_DIR/trademe_localities.json" | wc -l)
        log "   Found $REGION_COUNT TradeMe regions"
    else
        log "⚠ TradeMe localities download failed (optional - for alias mapping)"
    fi
fi

log ""
log "========================================="
log "DOWNLOAD SUMMARY"
log "========================================="
ls -lh "$DATA_DIR"/*.{csv,json} 2>/dev/null | awk '{print $9, "-", $5}' || ls -lh "$DATA_DIR/" | head -20

log ""
log "Next steps:"
log "  1. Run: docker exec -it nz-addresses bash /home/appuser/scripts/load_hierarchy_correct.sh"
log "  2. This will load 16 geographic regions (not 22 electoral constituencies)"
log "  3. Verify: GET http://localhost:8080/regions should show Auckland, Wellington, etc."
