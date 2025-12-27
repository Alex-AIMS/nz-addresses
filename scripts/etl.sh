#!/bin/bash
set -euo pipefail

# ETL script for NZ Addresses
# Loads regions, districts, suburbs, and addresses into PostgreSQL/PostGIS
# Supports local file mode and WFS mode

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/config.env"

# Load configuration
if [[ ! -f "$CONFIG_FILE" ]]; then
  echo "ERROR: Configuration file not found: $CONFIG_FILE"
  exit 1
fi

source "$CONFIG_FILE"

# Parse mode argument (default: local)
MODE="${1:-local}"

if [[ "$MODE" != "local" && "$MODE" != "wfs" ]]; then
  echo "ERROR: Invalid mode. Use 'local' or 'wfs'"
  echo "Usage: $0 [local|wfs]"
  exit 1
fi

# Create log directory
mkdir -p "$LOG_DIR"
LOGFILE="${LOG_DIR}/etl_$(date +%Y%m%d_%H%M%S).log"

log() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOGFILE"
}

log "Starting ETL in $MODE mode"

# PostgreSQL connection string
export PGPASSWORD="$DB_PASS"
PG_CONN="host=$DB_HOST port=$DB_PORT dbname=$DB_NAME user=$DB_USER"

# Test database connection
if ! psql "$PG_CONN" -c "SELECT 1" > /dev/null 2>&1; then
  log "ERROR: Cannot connect to database"
  exit 1
fi

log "Database connection successful"

# Function: Import shapefile/geopackage to PostgreSQL
import_spatial() {
  local source="$1"
  local table_name="$2"
  local schema="nz_addresses"
  local fid_col="$3"
  
  log "Importing $source to $schema.$table_name"
  
  ogr2ogr -f "PostgreSQL" \
    PG:"$PG_CONN" \
    "$source" \
    -nln "${schema}.${table_name}" \
    -lco SCHEMA="$schema" \
    -lco GEOMETRY_NAME="$GEOM_COL" \
    -lco FID="$fid_col" \
    -lco SPATIAL_INDEX=GIST \
    -lco OVERWRITE=YES \
    -t_srs "$TARGET_SRID" \
    -nlt PROMOTE_TO_MULTI \
    -progress
  
  log "Imported $table_name successfully"
}

# Function: Import CSV with WKT geometry to PostgreSQL
import_csv_with_geom() {
  local csv_file="$1"
  local table_name="$2"
  local schema="nz_addresses"
  
  log "Importing CSV $csv_file to $schema.$table_name"
  
  # Use ogr2ogr which can handle WKT geometry in CSV
  ogr2ogr -f "PostgreSQL" \
    PG:"$PG_CONN" \
    "$csv_file" \
    -nln "${schema}.${table_name}" \
    -lco SCHEMA="$schema" \
    -lco GEOMETRY_NAME="$GEOM_COL" \
    -lco SPATIAL_INDEX=GIST \
    -lco OVERWRITE=YES \
    -oo GEOM_POSSIBLE_NAMES=WKT,wkt,geometry,GEOMETRY \
    -oo KEEP_GEOM_COLUMNS=NO \
    -a_srs "$TARGET_SRID" \
    -progress
  
  log "Imported $table_name successfully"
}

# Step 1: Import Regions
if [[ "$MODE" == "local" ]]; then
  if [[ -f "$REGIONS_PATH" ]]; then
    import_csv_with_geom "$REGIONS_PATH" "regions_staging"
    log "Transforming regions staging to final table"
    psql "$PG_CONN" -c "
      DELETE FROM nz_addresses.regions;
      INSERT INTO nz_addresses.regions (region_id, name, geom)
      SELECT 
        COALESCE(regc2023_v1_00, regc2023__1, fid::text)::varchar(10) AS region_id,
        COALESCE(regc2023_1, regc2023__1_name, regc202_1, name)::varchar(200) AS name,
        ST_Multi(ST_Force2D(wkb_geometry))::geometry(MultiPolygon, 2193) AS geom
      FROM nz_addresses.regions_staging;
      DROP TABLE IF EXISTS nz_addresses.regions_staging;
    " >> "$LOGFILE" 2>&1
  else
    log "WARNING: Regions file not found: $REGIONS_PATH"
  fi
else
  log "WFS mode: Skipping regions (WFS URL not configured)"
fi

# Step 2: Import Districts
if [[ "$MODE" == "local" ]]; then
  if [[ -f "$DISTRICTS_PATH" ]]; then
    import_csv_with_geom "$DISTRICTS_PATH" "districts_staging"
    log "Transforming districts staging to final table"
    psql "$PG_CONN" -c "
      DELETE FROM nz_addresses.districts;
      INSERT INTO nz_addresses.districts (district_id, region_id, name, geom)
      SELECT 
        COALESCE(ta2023_v1_00, ta2023__1_0, fid::text)::varchar(10) AS district_id,
        COALESCE(regc2023_v1_00, regc2023__1, '99')::varchar(10) AS region_id,
        COALESCE(ta2023_v1_00_name, ta2023__1, name)::varchar(200) AS name,
        ST_Multi(ST_Force2D(wkb_geometry))::geometry(MultiPolygon, 2193) AS geom
      FROM nz_addresses.districts_staging;
      DROP TABLE IF EXISTS nz_addresses.districts_staging;
    " >> "$LOGFILE" 2>&1
  else
    log "WARNING: Districts file not found: $DISTRICTS_PATH"
  fi
else
  log "WFS mode: Skipping districts (WFS URL not configured)"
fi

# Step 3: Import Suburbs
if [[ "$MODE" == "local" ]]; then
  if [[ -f "$SUBURBS_PATH" ]]; then
    import_csv_with_geom "$SUBURBS_PATH" "suburbs_staging"
    log "Transforming suburbs staging to final table"
    psql "$PG_CONN" -c "
      DELETE FROM nz_addresses.suburbs;
      INSERT INTO nz_addresses.suburbs (suburb_id, district_id, name, name_ascii, major_name, geom)
      SELECT 
        COALESCE(suburb_locality_id, id, fid::text)::varchar(50) AS suburb_id,
        COALESCE(territorial_authority_id, ta_id, '99')::varchar(10) AS district_id,
        COALESCE(suburb_locality, name)::varchar(200) AS name,
        nz_addresses.to_ascii(COALESCE(suburb_locality, name))::varchar(200) AS name_ascii,
        COALESCE(major_name, '')::varchar(200) AS major_name,
        ST_Multi(ST_Force2D(wkb_geometry))::geometry(MultiPolygon, 2193) AS geom
      FROM nz_addresses.suburbs_staging;
      DROP TABLE IF EXISTS nz_addresses.suburbs_staging;
    " >> "$LOGFILE" 2>&1
  else
    log "WARNING: Suburbs file not found: $SUBURBS_PATH"
  fi
else
  log "WFS mode: Skipping suburbs (WFS URL not configured)"
fi

# Step 4: Stage and Load Addresses
if [[ "$MODE" == "local" ]]; then
  if [[ -f "$ADDRESSES_CSV_PATH" ]]; then
    log "Creating staging table for addresses"
    psql "$PG_CONN" -f "${SCRIPT_DIR}/sql/linz_stage_addresses.sql" >> "$LOGFILE" 2>&1
    
    log "Loading CSV into staging table"
    psql "$PG_CONN" -c "\COPY nz_addresses.stage_addresses FROM '$ADDRESSES_CSV_PATH' WITH (FORMAT csv, HEADER true, DELIMITER ',', ENCODING 'UTF8')" >> "$LOGFILE" 2>&1
    
    log "Transforming staged addresses to final table"
    psql "$PG_CONN" -f "${SCRIPT_DIR}/sql/linz_stage_to_final.sql" >> "$LOGFILE" 2>&1
    
    log "Dropping staging table"
    psql "$PG_CONN" -c "DROP TABLE IF EXISTS nz_addresses.stage_addresses;" >> "$LOGFILE" 2>&1
  else
    log "WARNING: Addresses CSV not found: $ADDRESSES_CSV_PATH"
  fi
else
  log "WFS mode: Skipping addresses (WFS URL not configured)"
fi

# Step 5: Refresh streets_by_suburb
log "Refreshing streets_by_suburb materialized table"
psql "$PG_CONN" -c "SELECT nz_addresses.refresh_streets_by_suburb();" >> "$LOGFILE" 2>&1

# Step 6: Analyze tables
log "Running ANALYZE on all tables"
psql "$PG_CONN" -c "
  ANALYZE nz_addresses.regions;
  ANALYZE nz_addresses.districts;
  ANALYZE nz_addresses.suburbs;
  ANALYZE nz_addresses.addresses;
  ANALYZE nz_addresses.streets_by_suburb;
" >> "$LOGFILE" 2>&1

# Step 7: Run data quality checks
log "Running data quality checks"
psql "$PG_CONN" -f "${SCRIPT_DIR}/sql/checks.sql" >> "$LOGFILE" 2>&1

log "ETL completed successfully"
log "Log file: $LOGFILE"
