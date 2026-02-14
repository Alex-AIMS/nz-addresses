#!/bin/bash
set -euo pipefail

# ETL script for NZ Addresses
# Loads regions, districts, suburbs, and addresses into PostgreSQL/PostGIS
# Supports local file mode and WFS mode
#
# Data sources:
#   Regions      - Stats NZ Regional Council 2023 (layer 111182), EPSG:2193
#   Districts    - Stats NZ Territorial Authority 2023 (layer 111183), EPSG:2193
#   Suburbs      - LINZ NZ Suburbs & Localities (layer 113764), EPSG:4167
#   Addresses    - LINZ NZ Street Addresses (layer 105689), EPSG:4167

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
# Args: csv_file table_name [source_srid]
# source_srid defaults to $TARGET_SRID (EPSG:2193); set to EPSG:4167 for lat/lon data
import_csv_with_geom() {
  local csv_file="$1"
  local table_name="$2"
  local source_srid="${3:-$TARGET_SRID}"
  local schema="nz_addresses"

  log "Importing CSV $csv_file to $schema.$table_name (source SRID: $source_srid)"

  local OGR_ARGS=(
    -f "PostgreSQL"
    PG:"$PG_CONN"
    "$csv_file"
    -nln "${schema}.${table_name}"
    -lco SCHEMA="$schema"
    -lco GEOMETRY_NAME="$GEOM_COL"
    -lco SPATIAL_INDEX=GIST
    -lco OVERWRITE=YES
    -oo "GEOM_POSSIBLE_NAMES=Shape,shape,WKT,wkt,geometry,GEOMETRY"
    -oo KEEP_GEOM_COLUMNS=NO
    -progress
  )

  # If source SRID differs from target, use -s_srs + -t_srs to transform
  # EXCEPT: for EPSG:4167 data with lat/lon axis order, just assign SRID
  # and let the SQL transform handle reprojection (ogr2ogr axis order issues)
  if [[ "$source_srid" != "$TARGET_SRID" && "$source_srid" != "EPSG:4167" ]]; then
    OGR_ARGS+=(-s_srs "$source_srid" -t_srs "$TARGET_SRID")
  else
    OGR_ARGS+=(-a_srs "$source_srid")
  fi

  ogr2ogr "${OGR_ARGS[@]}"

  log "Imported $table_name successfully"
}

# Helper: Extract the largest polygon from a (multi)polygon geometry,
# flip coordinate axis order (WKT from LINZ/Stats NZ uses northing,easting),
# and cast to Polygon for the target schema.
LARGEST_POLYGON_SQL="
  (SELECT (dp).geom
   FROM ST_Dump(ST_Force2D(ST_FlipCoordinates(geom)))  dp
   ORDER BY ST_Area((dp).geom) DESC
   LIMIT 1)::geometry(Polygon, 2193)
"

# Step 1: Import Regions (Stats NZ Regional Council 2023)
# CSV columns: FID, REGC2023_V1_00, REGC2023_V1_00_NAME, ..., Shape (EPSG:2193)
if [[ "$MODE" == "local" ]]; then
  if [[ -f "$REGIONS_PATH" ]]; then
    import_csv_with_geom "$REGIONS_PATH" "regions_staging" "EPSG:2193"
    log "Transforming regions staging to final table"
    psql "$PG_CONN" -c "
      DELETE FROM nz_addresses.regions;
      INSERT INTO nz_addresses.regions (region_id, name, geom)
      SELECT
        regc2023_v1_00::varchar(10) AS region_id,
        regc2023_v1_00_name::varchar(200) AS name,
        $LARGEST_POLYGON_SQL AS geom
      FROM nz_addresses.regions_staging
      WHERE geom IS NOT NULL;
      DROP TABLE IF EXISTS nz_addresses.regions_staging;
    " >> "$LOGFILE" 2>&1
  else
    log "WARNING: Regions file not found: $REGIONS_PATH"
  fi
else
  log "WFS mode: Skipping regions (WFS URL not configured)"
fi

REGION_COUNT=$(psql "$PG_CONN" -t -c "SELECT COUNT(*) FROM nz_addresses.regions;")
log "Regions loaded: ${REGION_COUNT// /}"

# Step 2: Import Districts (Stats NZ Territorial Authority 2023)
# CSV columns: FID, TALB2023_V1_00, TALB2023_V1_00_NAME, ..., Shape (EPSG:2193)
# Note: TA CSV has no region_id column — we spatial-join to regions
if [[ "$MODE" == "local" ]]; then
  if [[ -f "$DISTRICTS_PATH" ]]; then
    import_csv_with_geom "$DISTRICTS_PATH" "districts_staging" "EPSG:2193"
    log "Transforming districts staging to final table (spatial join to regions)"
    psql "$PG_CONN" -c "
      DELETE FROM nz_addresses.districts;
      INSERT INTO nz_addresses.districts (district_id, region_id, name, geom)
      SELECT
        s.talb2023_v1_00::varchar(10) AS district_id,
        COALESCE(
          (SELECT r.region_id FROM nz_addresses.regions r
           WHERE ST_Intersects(r.geom, ST_PointOnSurface(ST_Force2D(ST_FlipCoordinates(s.geom))))
           LIMIT 1),
          '99'
        )::varchar(10) AS region_id,
        s.talb2023_v1_00_name::varchar(200) AS name,
        $LARGEST_POLYGON_SQL AS geom
      FROM nz_addresses.districts_staging s
      WHERE s.geom IS NOT NULL;
      DROP TABLE IF EXISTS nz_addresses.districts_staging;
    " >> "$LOGFILE" 2>&1
  else
    log "WARNING: Districts file not found: $DISTRICTS_PATH"
  fi
else
  log "WFS mode: Skipping districts (WFS URL not configured)"
fi

DISTRICT_COUNT=$(psql "$PG_CONN" -t -c "SELECT COUNT(*) FROM nz_addresses.districts;")
log "Districts loaded: ${DISTRICT_COUNT// /}"

# Step 3: Import Suburbs (LINZ NZ Suburbs & Localities)
# CSV columns: FID, id, name, ..., territorial_authority, ..., name_ascii, ..., shape (EPSG:4167)
# Note: Suburbs CSV uses EPSG:4167 with lat/lon axis order in WKT.
#       We import as-is (assign EPSG:4167) then flip + reproject in SQL.
# Note: Has TA name (not ID) — spatial-join to districts for district_id
if [[ "$MODE" == "local" ]]; then
  if [[ -f "$SUBURBS_PATH" ]]; then
    import_csv_with_geom "$SUBURBS_PATH" "suburbs_staging" "EPSG:4167"
    log "Transforming suburbs staging to final table (reproject + spatial join to districts)"
    psql "$PG_CONN" -c "
      DELETE FROM nz_addresses.suburbs;
      INSERT INTO nz_addresses.suburbs (suburb_id, district_id, name, name_ascii, major_name, geom)
      SELECT
        s.id::varchar(50) AS suburb_id,
        COALESCE(
          -- First: point-in-polygon match
          (SELECT d.district_id FROM nz_addresses.districts d
           WHERE ST_Contains(d.geom, ST_PointOnSurface(reproj_geom))
           LIMIT 1),
          -- Fallback: nearest district within 10km
          (SELECT d.district_id FROM nz_addresses.districts d
           WHERE ST_DWithin(d.geom, reproj_geom, 10000)
           ORDER BY ST_Distance(d.geom, reproj_geom)
           LIMIT 1),
          -- Last resort: absolute nearest district
          (SELECT d.district_id FROM nz_addresses.districts d
           ORDER BY ST_Distance(d.geom, reproj_geom)
           LIMIT 1)
        )::varchar(10) AS district_id,
        s.name::varchar(200) AS name,
        COALESCE(s.name_ascii, nz_addresses.to_ascii(s.name))::varchar(200) AS name_ascii,
        COALESCE(s.major_name, '')::varchar(200) AS major_name,
        reproj_geom AS geom
      FROM (
        SELECT *,
          -- Flip lat/lon to lon/lat, then reproject 4167 → 2193, extract largest polygon
          (SELECT (dp).geom
           FROM ST_Dump(
             ST_Force2D(
               ST_Transform(
                 ST_SetSRID(ST_FlipCoordinates(geom), 4167),
                 2193
               )
             )
           ) dp
           ORDER BY ST_Area((dp).geom) DESC
           LIMIT 1)::geometry(Polygon, 2193) AS reproj_geom
        FROM nz_addresses.suburbs_staging
        WHERE geom IS NOT NULL AND id IS NOT NULL
      ) s
      WHERE reproj_geom IS NOT NULL;
      DROP TABLE IF EXISTS nz_addresses.suburbs_staging;
    " >> "$LOGFILE" 2>&1
  else
    log "WARNING: Suburbs file not found: $SUBURBS_PATH"
  fi
else
  log "WFS mode: Skipping suburbs (WFS URL not configured)"
fi

SUBURB_COUNT=$(psql "$PG_CONN" -t -c "SELECT COUNT(*) FROM nz_addresses.suburbs;")
log "Suburbs loaded: ${SUBURB_COUNT// /}"

# Step 4: Stage and Load Addresses (LINZ NZ Street Addresses)
# CSV has GD2000/EPSG:4167 coordinates — transform handled in SQL (linz_stage_to_final.sql)
if [[ "$MODE" == "local" ]]; then
  if [[ -f "$ADDRESSES_CSV_PATH" ]]; then
    log "Creating staging table for addresses"
    psql "$PG_CONN" -f "${SCRIPT_DIR}/sql/linz_stage_addresses.sql" >> "$LOGFILE" 2>&1

    log "Loading CSV into staging table"
    psql "$PG_CONN" -c "\COPY nz_addresses.stage_addresses FROM '$ADDRESSES_CSV_PATH' WITH (FORMAT csv, HEADER true, DELIMITER ',', ENCODING 'UTF8')" >> "$LOGFILE" 2>&1

    STAGED_COUNT=$(psql "$PG_CONN" -t -c "SELECT COUNT(*) FROM nz_addresses.stage_addresses;")
    log "Staged ${STAGED_COUNT// /} addresses"

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

ADDRESS_COUNT=$(psql "$PG_CONN" -t -c "SELECT COUNT(*) FROM nz_addresses.addresses;")
log "Addresses loaded: ${ADDRESS_COUNT// /}"

# Step 5: Refresh streets_by_suburb
log "Refreshing streets_by_suburb materialized table"
psql "$PG_CONN" -c "SELECT nz_addresses.refresh_streets_by_suburb();" >> "$LOGFILE" 2>&1

STREETS_COUNT=$(psql "$PG_CONN" -t -c "SELECT COUNT(*) FROM nz_addresses.streets_by_suburb;")
log "Streets by suburb refreshed: ${STREETS_COUNT// /}"

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
psql "$PG_CONN" -f "${SCRIPT_DIR}/sql/checks.sql" 2>&1 | tee -a "$LOGFILE"

log ""
log "========================================="
log "ETL Complete"
log "========================================="
log "  Regions:    ${REGION_COUNT// /}"
log "  Districts:  ${DISTRICT_COUNT// /}"
log "  Suburbs:    ${SUBURB_COUNT// /}"
log "  Addresses:  ${ADDRESS_COUNT// /}"
log "  Streets:    ${STREETS_COUNT// /}"
log "  Log: $LOGFILE"
log "========================================="
