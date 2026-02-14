#!/bin/bash
set -e

log() { echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"; }

log "========================================="
log "LOADING NZ ADDRESSES DATA"
log "========================================="

DB_USER="nzuser"
DB_NAME="nz_addresses_db"
CONTAINER="nz-addresses"

log "Step 1: Loading regions..."
docker exec $CONTAINER psql -U $DB_USER -d $DB_NAME -c "\copy nz_addresses.regions(region_id, name) FROM '/home/appuser/data/regional-councils-correct.csv' WITH (FORMAT csv, HEADER true);"
REGION_COUNT=$(docker exec $CONTAINER psql -U $DB_USER -d $DB_NAME -t -c "SELECT COUNT(*) FROM nz_addresses.regions;")
log "✓ Loaded${REGION_COUNT} regions"

log ""
log "Step 2: Loading districts..."
cat > /tmp/load_districts.sql << 'EOSQL'
CREATE TEMP TABLE temp_ta (
    fid TEXT, code TEXT, name TEXT, name_ascii TEXT, land_area_km2 TEXT, 
    area_km2 TEXT, shape_length TEXT, shape_area TEXT, shape TEXT
);
\copy temp_ta FROM '/home/appuser/data/territorial-authorities.csv' WITH (FORMAT csv, HEADER true);
INSERT INTO nz_addresses.districts (district_id, region_id, name)
SELECT LOWER(REGEXP_REPLACE(name, '[^a-zA-Z0-9]+', '-', 'g')), 'R02', name
FROM temp_ta WHERE name IS NOT NULL LIMIT 100;
EOSQL

docker cp /tmp/load_districts.sql $CONTAINER:/tmp/ 2>/dev/null
docker exec $CONTAINER psql -U $DB_USER -d $DB_NAME -f /tmp/load_districts.sql >/dev/null

DISTRICT_COUNT=$(docker exec $CONTAINER psql -U $DB_USER -d $DB_NAME -t -c "SELECT COUNT(*) FROM nz_addresses.districts;")
log "✓ Loaded${DISTRICT_COUNT} districts"

log ""
log "Step 3: Loading suburbs (this may take a minute)..."
cat > /tmp/load_suburbs.sql << 'EOSQL'
CREATE TEMP TABLE temp_suburbs (
    fid TEXT, id TEXT, name TEXT, additional_name TEXT, type TEXT, major_name TEXT,
    major_name_type TEXT, territorial_authority TEXT, population_estimate TEXT,
    name_ascii TEXT, additional_name_ascii TEXT, major_name_ascii TEXT,
    territorial_authority_ascii TEXT, shape TEXT
);
\copy temp_suburbs FROM '/home/appuser/data/suburbs_localities.csv' WITH (FORMAT csv, HEADER true);
INSERT INTO nz_addresses.suburbs (suburb_id, district_id, name, name_ascii, major_name)
SELECT 
    COALESCE(NULLIF(id, ''), LOWER(REGEXP_REPLACE(name, '[^a-zA-Z0-9]+', '-', 'g'))),
    (SELECT district_id FROM nz_addresses.districts LIMIT 1),
    name, name_ascii, major_name
FROM temp_suburbs WHERE name IS NOT NULL;
EOSQL

docker cp /tmp/load_suburbs.sql $CONTAINER:/tmp/ 2>/dev/null
docker exec $CONTAINER psql -U $DB_USER -d $DB_NAME -f /tmp/load_suburbs.sql >/dev/null

SUBURB_COUNT=$(docker exec $CONTAINER psql -U $DB_USER -d $DB_NAME -t -c "SELECT COUNT(*) FROM nz_addresses.suburbs;")
log "✓ Loaded${SUBURB_COUNT} suburbs"

log ""
log "Step 4: Loading addresses (this will take ~3-5 minutes)..."
cat > /tmp/load_addresses.sql << 'EOSQL'
CREATE TEMP TABLE temp_addresses (
    fid TEXT, address_id BIGINT, source_dataset TEXT, change_id BIGINT,
    full_address_number TEXT, full_road_name TEXT, full_address TEXT,
    territorial_authority TEXT, unit_type TEXT, unit_value TEXT,
    level_type TEXT, level_value TEXT, address_number_prefix TEXT,
    address_number INT, address_number_suffix TEXT, address_number_high INT,
    road_name_prefix TEXT, road_name TEXT, road_type_name TEXT, road_suffix TEXT,
    water_name TEXT, water_body_name TEXT, suburb_locality TEXT, town_city TEXT,
    address_class TEXT, address_lifecycle TEXT,
    gd2000_xcoord DOUBLE PRECISION, gd2000_ycoord DOUBLE PRECISION,
    road_name_ascii TEXT, water_name_ascii TEXT, water_body_name_ascii TEXT,
    suburb_locality_ascii TEXT, town_city_ascii TEXT,
    full_road_name_ascii TEXT, full_address_ascii TEXT, shape TEXT
);

\copy temp_addresses FROM '/home/appuser/data/nz_addresses.csv' WITH (FORMAT csv, HEADER true, NULL '');

INSERT INTO nz_addresses.addresses (
    address_id, full_address, full_address_ascii, full_road_name, full_road_name_ascii,
    address_number_prefix, address_number, address_number_suffix,
    suburb_locality, suburb_locality_ascii, town_city, territorial_authority,
    x_coord, y_coord, geom
)
SELECT 
    address_id, full_address, full_address_ascii, full_road_name, full_road_name_ascii,
    address_number_prefix, address_number, address_number_suffix,
    suburb_locality, suburb_locality_ascii, town_city, territorial_authority,
    gd2000_xcoord, gd2000_ycoord,
    ST_Transform(ST_SetSRID(ST_MakePoint(gd2000_xcoord, gd2000_ycoord), 4167), 2193)
FROM temp_addresses
WHERE gd2000_xcoord IS NOT NULL AND gd2000_ycoord IS NOT NULL;

ANALYZE nz_addresses.addresses;
EOSQL

docker cp /tmp/load_addresses.sql $CONTAINER:/tmp/ 2>/dev/null
log "Loading CSV (this takes time)..."
docker exec $CONTAINER psql -U $DB_USER -d $DB_NAME -f /tmp/load_addresses.sql 2>&1 | grep -E "(COPY|INSERT|rows)"

ADDRESS_COUNT=$(docker exec $CONTAINER psql -U $DB_USER -d $DB_NAME -t -c "SELECT COUNT(*) FROM nz_addresses.addresses;")
log "✓ Loaded${ADDRESS_COUNT} addresses"

log ""
log "========================================="
log "DATA LOADING COMPLETE!"
log "========================================="
log "Summary: ${REGION_COUNT} regions, ${DISTRICT_COUNT} districts, ${SUBURB_COUNT} suburbs, ${ADDRESS_COUNT} addresses"
log ""
log "Test autocomplete: curl 'http://localhost:8080/autocomplete?query=queen&limit=5' | jq '.'"
