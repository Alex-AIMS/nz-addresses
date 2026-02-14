#!/bin/bash
set -e

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

log "========================================="
log "LOADING NZ ADDRESSES DATA"
log "========================================="

# Database connection
DB_USER="nzuser"
DB_NAME="nz_addresses_db"

log "Step 1: Loading regions from CSV..."
docker exec nz-addresses psql -U $DB_USER -d $DB_NAME <<'EOF'
-- Load regions
\copy nz_addresses.regions(region_id, name) FROM '/home/appuser/data/regional-councils-correct.csv' WITH (FORMAT csv, HEADER true, DELIMITER ',');
EOF

REGION_COUNT=$(docker exec nz-addresses psql -U $DB_USER -d $DB_NAME -t -c "SELECT COUNT(*) FROM nz_addresses.regions;")
log "✓ Loaded ${REGION_COUNT} regions"

log ""
log "Step 2: Loading districts/territorial authorities..."
docker exec nz-addresses psql -U $DB_USER -d $DB_NAME <<'EOF'
-- Create temporary table to parse territorial authorities CSV
CREATE TEMP TABLE temp_ta (
    code TEXT,
    name TEXT,
    regc2023_code TEXT,
    regc2023_name TEXT,
    land_area_km2 TEXT,
    area_km2 TEXT,
    shape_length TEXT
);

-- Load territorial authorities
\copy temp_ta FROM '/home/appuser/data/territorial-authorities.csv' WITH (FORMAT csv, HEADER true, DELIMITER ',');

-- Map REGC2023 codes to our region_ids
-- R02=Auckland, R01=Northland, R03=Waikato, R04=Bay of Plenty, R05=Gisborne
-- R06=Hawke's Bay, R07=Taranaki, R08=Manawatu/Whanganui, R09=Wellington
-- R10=Nelson/Tasman, R11=Marlborough, R12=West Coast, R13=Canterbury
-- R14=Otago, R15=Southland

-- Insert districts from territorial authorities
INSERT INTO nz_addresses.districts (district_id, region_id, code, name)
SELECT 
    LOWER(REGEXP_REPLACE(name, '[^a-zA-Z0-9]+', '-', 'g')) AS district_id,
    CASE regc2023_code
        WHEN 'R02' THEN 'R02'
        WHEN 'R01' THEN 'R01'
        WHEN 'R03' THEN 'R03'
        WHEN 'R04' THEN 'R04'
        WHEN 'R05' THEN 'R05'
        WHEN 'R06' THEN 'R06'
        WHEN 'R07' THEN 'R07'
        WHEN 'R08' THEN 'R08'
        WHEN 'R09' THEN 'R09'
        WHEN 'R10' THEN 'R10'
        WHEN 'R11' THEN 'R11'
        WHEN 'R12' THEN 'R12'
        WHEN 'R13' THEN 'R13'
        WHEN 'R14' THEN 'R14'
        WHEN 'R15' THEN 'R15'
        ELSE 'R02'  -- Default to Auckland
    END AS region_id,
    code,
    name
FROM temp_ta
WHERE name IS NOT NULL AND name != '';

DROP TABLE temp_ta;
EOF

DISTRICT_COUNT=$(docker exec nz-addresses psql -U $DB_USER -d $DB_NAME -t -c "SELECT COUNT(*) FROM nz_addresses.districts;")
log "✓ Loaded ${DISTRICT_COUNT} districts"

log ""
log "Step 3: Loading suburbs/localities..."
docker exec nz-addresses psql -U $DB_USER -d $DB_NAME <<'EOF'
-- Create temporary table for suburbs
CREATE TEMP TABLE temp_suburbs (
    suburb_id TEXT,
    name TEXT,
    major_name TEXT,
    locality_type TEXT,
    territorial_authority TEXT
);

-- Load suburbs from CSV
\copy temp_suburbs FROM '/home/appuser/data/suburbs_localities.csv' WITH (FORMAT csv, HEADER true, DELIMITER ',');

-- Insert suburbs, linking to districts by name matching
INSERT INTO nz_addresses.suburbs (suburb_id, district_id, name, major_name)
SELECT 
    COALESCE(NULLIF(ts.suburb_id, ''), LOWER(REGEXP_REPLACE(ts.name, '[^a-zA-Z0-9]+', '-', 'g'))) AS suburb_id,
    d.district_id,
    ts.name,
    ts.major_name
FROM temp_suburbs ts
LEFT JOIN nz_addresses.districts d ON LOWER(ts.territorial_authority) LIKE '%' || LOWER(REPLACE(d.name, ' District', '')) || '%'
    OR LOWER(ts.territorial_authority) LIKE '%' || LOWER(REPLACE(REPLACE(d.name, ' City', ''), ' District', '')) || '%'
WHERE ts.name IS NOT NULL AND ts.name != '';

-- For suburbs that didn't match, try to assign to a default district based on region
UPDATE nz_addresses.suburbs
SET district_id = (SELECT district_id FROM nz_addresses.districts LIMIT 1)
WHERE district_id IS NULL;

DROP TABLE temp_suburbs;
EOF

SUBURB_COUNT=$(docker exec nz-addresses psql -U $DB_USER -d $DB_NAME -t -c "SELECT COUNT(*) FROM nz_addresses.suburbs;")
log "✓ Loaded ${SUBURB_COUNT} suburbs"

log ""
log "Step 4: Loading addresses (this will take several minutes)..."
docker exec nz-addresses psql -U $DB_USER -d $DB_NAME <<'EOF'
-- Create staging table
DROP TABLE IF EXISTS nz_addresses.stage_addresses;
CREATE UNLOGGED TABLE nz_addresses.stage_addresses (
    address_id BIGINT,
    change_id BIGINT,
    full_address TEXT,
    full_road_name TEXT,
    full_road_name_ascii TEXT,
    road_section_id BIGINT,
    water_route_name TEXT,
    water_name TEXT,
    suburb_locality TEXT,
    town_city TEXT,
    full_address_number TEXT,
    address_number BIGINT,
    address_number_suffix TEXT,
    address_number_high BIGINT,
    water_route_name_ascii TEXT,
    water_name_ascii TEXT,
    suburb_locality_ascii TEXT,
    town_city_ascii TEXT,
    gd2000_xcoord DOUBLE PRECISION,
    gd2000_ycoord DOUBLE PRECISION,
    full_address_ascii TEXT
);

-- Load CSV into staging (this is fast with COPY)
\copy nz_addresses.stage_addresses FROM '/home/appuser/data/nz_addresses.csv' WITH (FORMAT csv, HEADER true, DELIMITER ',', NULL '');
EOF

log "CSV loaded into staging table"

log "Step 5: Transforming addresses to final table..."
docker exec nz-addresses psql -U $DB_USER -d $DB_NAME <<'EOF'
-- Transform and insert into final addresses table
INSERT INTO nz_addresses.addresses (
    address_id,
    full_address,
    full_road_name,
    suburb_locality,
    town_city,
    address_number,
    x_coord,
    y_coord,
    centroid,
    suburb_id
)
SELECT 
    s.address_id,
    s.full_address,
    s.full_road_name,
    s.suburb_locality,
    s.town_city,
    s.address_number,
    s.gd2000_xcoord,  -- x_coord (longitude)
    s.gd2000_ycoord,  -- y_coord (latitude)
    -- Create point geometry from coordinates (NZTM2000 - EPSG:2193)
    ST_Transform(ST_SetSRID(ST_MakePoint(s.gd2000_xcoord, s.gd2000_ycoord), 4167), 2193) AS centroid,
    -- Try to match suburb by name
    (SELECT suburb_id 
     FROM nz_addresses.suburbs sub 
     WHERE LOWER(sub.name) = LOWER(s.suburb_locality) 
        OR LOWER(sub.major_name) = LOWER(s.suburb_locality)
     LIMIT 1) AS suburb_id
FROM nz_addresses.stage_addresses s
WHERE s.gd2000_xcoord IS NOT NULL 
  AND s.gd2000_ycoord IS NOT NULL
  AND s.full_address IS NOT NULL;

-- Drop staging table
DROP TABLE nz_addresses.stage_addresses;

-- Analyze for query optimization
ANALYZE nz_addresses.addresses;
EOF

ADDRESS_COUNT=$(docker exec nz-addresses psql -U $DB_USER -d $DB_NAME -t -c "SELECT COUNT(*) FROM nz_addresses.addresses;")
log "✓ Loaded ${ADDRESS_COUNT} addresses"

log ""
log "Step 6: Creating summary statistics..."
docker exec nz-addresses psql -U $DB_USER -d $DB_NAME <<'EOF'
-- Count addresses by region
SELECT 
    r.name AS region,
    COUNT(a.address_id) AS address_count
FROM nz_addresses.regions r
LEFT JOIN nz_addresses.districts d ON d.region_id = r.region_id
LEFT JOIN nz_addresses.suburbs s ON s.district_id = d.district_id
LEFT JOIN nz_addresses.addresses a ON a.suburb_id = s.suburb_id
GROUP BY r.region_id, r.name
ORDER BY address_count DESC;
EOF

log ""
log "========================================="
log "DATA LOADING COMPLETE!"
log "========================================="
log "Summary:"
log "  - Regions: ${REGION_COUNT}"
log "  - Districts: ${DISTRICT_COUNT}"
log "  - Suburbs: ${SUBURB_COUNT}"
log "  - Addresses: ${ADDRESS_COUNT}"
log ""
log "You can now test the autocomplete endpoint:"
log "  curl 'http://localhost:8080/autocomplete?query=queen&limit=5'"
