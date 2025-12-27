#!/bin/bash
set -euo pipefail

# Download script for NZ Addresses data
# Automatically downloads all required datasets from LINZ and Stats NZ

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DATA_DIR="${SCRIPT_DIR}/data"

# Create data directory
mkdir -p "$DATA_DIR"

log() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*"
}

log "Starting data download..."
log "Data directory: $DATA_DIR"

# LINZ Data Service - NZ Addresses (CSV)
log "Downloading LINZ NZ Addresses (this may take several minutes, ~500MB)..."
ADDRESSES_URL="https://data.linz.govt.nz/services/query/v1/vector.csv?key=&layer=105689&x=-176.0&y=-47.5&x=179.0&y=-34.0"
ADDRESSES_ALT_URL="https://koordinates-tiles-a.global.ssl.fastly.net/services/query/v1/vector.csv?layer=105689&x=-176.0&y=-47.5&x=179.0&y=-34.0"

if command -v wget >/dev/null 2>&1; then
  wget -O "${DATA_DIR}/nz_addresses.csv" \
    "https://data.linz.govt.nz/services/query/v1/vector.csv?layer=105689&x=-180&y=-50&x=180&y=-30" \
    || wget -O "${DATA_DIR}/nz_addresses.csv" \
    "https://data.linz.govt.nz/layer/105689-nz-street-address-electoral/data/" \
    || log "WARNING: Could not download addresses automatically. Please download manually from https://data.linz.govt.nz/layer/105689-nz-street-address-electoral/"
else
  curl -L -o "${DATA_DIR}/nz_addresses.csv" \
    "https://data.linz.govt.nz/services/query/v1/vector.csv?layer=105689&x=-180&y=-50&x=180&y=-30" \
    || log "WARNING: Could not download addresses automatically. Please download manually from https://data.linz.govt.nz/layer/105689-nz-street-address-electoral/"
fi

# LINZ Data Service - Suburbs/Localities (WFS GeoPackage)
log "Downloading LINZ NZ Localities..."
LOCALITIES_LAYER_ID="105689"
LOCALITIES_WFS="https://data.linz.govt.nz/services/query/v1/vector.gpkg?layer=53353"

if command -v ogr2ogr >/dev/null 2>&1; then
  log "Using ogr2ogr to download localities via WFS..."
  ogr2ogr -f GPKG "${DATA_DIR}/suburbs_localities.gpkg" \
    WFS:"https://data.linz.govt.nz/services/wfs/layer-53353" \
    "layer-53353" \
    || log "WARNING: WFS download failed. Trying direct download..."
fi

# Fallback to wget/curl for localities
if [ ! -f "${DATA_DIR}/suburbs_localities.gpkg" ]; then
  if command -v wget >/dev/null 2>&1; then
    wget -O "${DATA_DIR}/suburbs_localities.gpkg" \
      "https://data.linz.govt.nz/layer/53353-nz-locality/data/?format=geopackage" \
      || log "WARNING: Could not download localities. Please download manually from https://data.linz.govt.nz/layer/53353-nz-locality/"
  else
    curl -L -o "${DATA_DIR}/suburbs_localities.gpkg" \
      "https://data.linz.govt.nz/layer/53353-nz-locality/data/?format=geopackage" \
      || log "WARNING: Could not download localities. Please download manually from https://data.linz.govt.nz/layer/53353-nz-locality/"
  fi
fi

# Stats NZ - Regional Council Boundaries 2023
log "Downloading Stats NZ Regional Council boundaries..."
REGIONS_URL="https://datafinder.stats.govt.nz/services;key=/layer/111179-regional-council-2023-clipped-generalised/data/geopackage/"

if command -v wget >/dev/null 2>&1; then
  wget -O "${DATA_DIR}/regions.zip" \
    "https://datafinder.stats.govt.nz/layer/111179-regional-council-2023-clipped-generalised/data/shapefile/" \
    || log "WARNING: Could not download regions. Please download manually from https://datafinder.stats.govt.nz/"
else
  curl -L -o "${DATA_DIR}/regions.zip" \
    "https://datafinder.stats.govt.nz/layer/111179-regional-council-2023-clipped-generalised/data/shapefile/" \
    || log "WARNING: Could not download regions. Please download manually from https://datafinder.stats.govt.nz/"
fi

# Extract regions shapefile
if [ -f "${DATA_DIR}/regions.zip" ]; then
  log "Extracting regional boundaries..."
  unzip -o "${DATA_DIR}/regions.zip" -d "${DATA_DIR}/regions_temp"
  
  # Find the shapefile and copy to expected location
  REGIONS_SHP=$(find "${DATA_DIR}/regions_temp" -name "*.shp" -type f | head -1)
  if [ -n "$REGIONS_SHP" ]; then
    REGIONS_BASE=$(basename "$REGIONS_SHP" .shp)
    REGIONS_DIR=$(dirname "$REGIONS_SHP")
    
    cp "${REGIONS_DIR}/${REGIONS_BASE}.shp" "${DATA_DIR}/regions.shp"
    cp "${REGIONS_DIR}/${REGIONS_BASE}.shx" "${DATA_DIR}/regions.shx" 2>/dev/null || true
    cp "${REGIONS_DIR}/${REGIONS_BASE}.dbf" "${DATA_DIR}/regions.dbf" 2>/dev/null || true
    cp "${REGIONS_DIR}/${REGIONS_BASE}.prj" "${DATA_DIR}/regions.prj" 2>/dev/null || true
    
    log "Regional boundaries extracted successfully"
  fi
  
  rm -rf "${DATA_DIR}/regions_temp"
  rm -f "${DATA_DIR}/regions.zip"
fi

# Stats NZ - Territorial Authority Boundaries 2023
log "Downloading Stats NZ Territorial Authority boundaries..."

if command -v wget >/dev/null 2>&1; then
  wget -O "${DATA_DIR}/districts.zip" \
    "https://datafinder.stats.govt.nz/layer/111191-territorial-authority-2023-clipped-generalised/data/shapefile/" \
    || log "WARNING: Could not download districts. Please download manually from https://datafinder.stats.govt.nz/"
else
  curl -L -o "${DATA_DIR}/districts.zip" \
    "https://datafinder.stats.govt.nz/layer/111191-territorial-authority-2023-clipped-generalised/data/shapefile/" \
    || log "WARNING: Could not download districts. Please download manually from https://datafinder.stats.govt.nz/"
fi

# Extract districts shapefile
if [ -f "${DATA_DIR}/districts.zip" ]; then
  log "Extracting territorial authority boundaries..."
  unzip -o "${DATA_DIR}/districts.zip" -d "${DATA_DIR}/districts_temp"
  
  # Find the shapefile and copy to expected location
  DISTRICTS_SHP=$(find "${DATA_DIR}/districts_temp" -name "*.shp" -type f | head -1)
  if [ -n "$DISTRICTS_SHP" ]; then
    DISTRICTS_BASE=$(basename "$DISTRICTS_SHP" .shp)
    DISTRICTS_DIR=$(dirname "$DISTRICTS_SHP")
    
    cp "${DISTRICTS_DIR}/${DISTRICTS_BASE}.shp" "${DATA_DIR}/territorial_authority.shp"
    cp "${DISTRICTS_DIR}/${DISTRICTS_BASE}.shx" "${DATA_DIR}/territorial_authority.shx" 2>/dev/null || true
    cp "${DISTRICTS_DIR}/${DISTRICTS_BASE}.dbf" "${DATA_DIR}/territorial_authority.dbf" 2>/dev/null || true
    cp "${DISTRICTS_DIR}/${DISTRICTS_BASE}.prj" "${DATA_DIR}/territorial_authority.prj" 2>/dev/null || true
    
    log "Territorial authority boundaries extracted successfully"
  fi
  
  rm -rf "${DATA_DIR}/districts_temp"
  rm -f "${DATA_DIR}/districts.zip"
fi

# Verify downloads
log "Verifying downloaded files..."
MISSING_FILES=()

[ -f "${DATA_DIR}/nz_addresses.csv" ] || MISSING_FILES+=("nz_addresses.csv")
[ -f "${DATA_DIR}/suburbs_localities.gpkg" ] || MISSING_FILES+=("suburbs_localities.gpkg")
[ -f "${DATA_DIR}/regions.shp" ] || MISSING_FILES+=("regions.shp")
[ -f "${DATA_DIR}/territorial_authority.shp" ] || MISSING_FILES+=("territorial_authority.shp")

if [ ${#MISSING_FILES[@]} -eq 0 ]; then
  log "✓ All required files downloaded successfully!"
  log ""
  log "Downloaded files:"
  ls -lh "${DATA_DIR}"
  log ""
  log "You can now run the ETL:"
  log "  bash scripts/etl.sh local"
else
  log "⚠ WARNING: Some files are missing:"
  for file in "${MISSING_FILES[@]}"; do
    log "  - $file"
  done
  log ""
  log "Please download missing files manually:"
  log "  - LINZ Addresses: https://data.linz.govt.nz/layer/105689-nz-street-address-electoral/"
  log "  - LINZ Localities: https://data.linz.govt.nz/layer/53353-nz-locality/"
  log "  - Stats NZ Regions: https://datafinder.stats.govt.nz/layer/111179-regional-council-2023-clipped-generalised/"
  log "  - Stats NZ Districts: https://datafinder.stats.govt.nz/layer/111191-territorial-authority-2023-clipped-generalised/"
fi

log "Download process complete."
