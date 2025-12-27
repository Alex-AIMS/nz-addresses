#!/bin/bash
set -euo pipefail

# Simple ETL - load NZ addresses only
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/config.env"

if [[ ! -f "$CONFIG_FILE" ]]; then
  echo "ERROR: Configuration file not found: $CONFIG_FILE"
  exit 1
fi

source "$CONFIG_FILE"

mkdir -p "$LOG_DIR"
LOGFILE="${LOG_DIR}/etl_simple_$(date +%Y%m%d_%H%M%S).log"

log() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOGFILE"
}

log "Starting Simple ETL - Addresses Only"

export PGPASSWORD="$DB_PASS"
PG_CONN="host=$DB_HOST port=$DB_PORT dbname=$DB_NAME user=$DB_USER"

if ! psql "$PG_CONN" -c "SELECT 1" > /dev/null 2>&1; then
  log "ERROR: Cannot connect to database"
  exit 1
fi

log "Database connection successful"

# Load addresses
if [[ -f "$ADDRESSES_CSV_PATH" ]]; then
    log "Creating staging table for addresses"
    psql "$PG_CONN" -f "${SCRIPT_DIR}/sql/linz_stage_addresses.sql" >> "$LOGFILE" 2>&1
    
    log "Loading CSV into staging table (this may take a few minutes...)"
    psql "$PG_CONN" -c "\COPY nz_addresses.stage_addresses FROM '$ADDRESSES_CSV_PATH' WITH (FORMAT csv, HEADER true, DELIMITER ',', ENCODING 'UTF8')" >> "$LOGFILE" 2>&1
    
    log "Transforming staged addresses to final table (building geometry from coordinates...)"
    psql "$PG_CONN" -f "${SCRIPT_DIR}/sql/linz_stage_to_final.sql" >> "$LOGFILE" 2>&1
    
    log "Dropping staging table"
    psql "$PG_CONN" -c "DROP TABLE IF EXISTS nz_addresses.stage_addresses;" >> "$LOGFILE" 2>&1
    
    log "Running ANALYZE on addresses table"
    psql "$PG_CONN" -c "ANALYZE nz_addresses.addresses;" >> "$LOGFILE" 2>&1
    
    log "Getting record count"
    COUNT=$(psql "$PG_CONN" -t -c "SELECT COUNT(*) FROM nz_addresses.addresses;")
    log "Loaded ${COUNT} addresses successfully"
else
    log "ERROR: Addresses CSV not found: $ADDRESSES_CSV_PATH"
    exit 1
fi

log "Simple ETL completed successfully"
log "Log file: $LOGFILE"
