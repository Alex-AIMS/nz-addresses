#!/bin/bash
set -e

log() { echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"; }

DB_USER="nzuser"
DB_NAME="nz_addresses_db"
CONTAINER="nz-addresses"

log "========================================="
log "LOADING DISTRICTS AND SUBURBS"
log "========================================="

log ""
log "Step 1: Loading Territorial Authorities (Districts)..."

# Create the SQL script for loading districts
cat > /tmp/load_districts_final.sql << 'EOSQL'
-- Create staging table matching CSV structure
DROP TABLE IF EXISTS temp_districts;
CREATE TEMP TABLE temp_districts (
    fid TEXT,
    talb2023_v1_00 TEXT,
    talb2023_v1_00_name TEXT,
    talb2023_v1_00_name_ascii TEXT,
    land_area_sq_km TEXT,
    area_sq_km TEXT,
    shape_length TEXT,
    shape_area TEXT,
    shape TEXT
);

-- Load CSV data
\copy temp_districts FROM '/home/appuser/data/territorial-authorities.csv' WITH (FORMAT csv, HEADER true);

-- Insert into districts table with proper ID generation
-- We need to create short IDs that fit in varchar(10)
INSERT INTO nz_addresses.districts (district_id, region_id, name)
SELECT 
    -- Create short district ID from FID or code
    SUBSTRING(talb2023_v1_00, 1, 10) AS district_id,
    -- Default to Auckland region (R02) - will need mapping table for proper assignment
    'R02' AS region_id,
    talb2023_v1_00_name AS name
FROM temp_districts
WHERE talb2023_v1_00_name IS NOT NULL 
  AND talb2023_v1_00 IS NOT NULL
ON CONFLICT (district_id) DO NOTHING;

-- Update region_id based on district name patterns
UPDATE nz_addresses.districts SET region_id = 'R01' WHERE name LIKE '%Northland%' OR name LIKE '%Far North%' OR name LIKE '%Whangarei%' OR name LIKE '%Kaipara%';
UPDATE nz_addresses.districts SET region_id = 'R03' WHERE name LIKE '%Waikato%' OR name LIKE '%Hamilton%' OR name LIKE '%Thames%' OR name LIKE '%Hauraki%';
UPDATE nz_addresses.districts SET region_id = 'R04' WHERE name LIKE '%Bay of Plenty%' OR name LIKE '%Tauranga%' OR name LIKE '%Western Bay%' OR name LIKE '%Rotorua%';
UPDATE nz_addresses.districts SET region_id = 'R05' WHERE name LIKE '%Gisborne%';
UPDATE nz_addresses.districts SET region_id = 'R06' WHERE name LIKE '%Hawke%' OR name LIKE '%Napier%' OR name LIKE '%Hastings%';
UPDATE nz_addresses.districts SET region_id = 'R07' WHERE name LIKE '%Taranaki%' OR name LIKE '%New Plymouth%';
UPDATE nz_addresses.districts SET region_id = 'R08' WHERE name LIKE '%Manawatu%' OR name LIKE '%Whanganui%' OR name LIKE '%Palmerston North%';
UPDATE nz_addresses.districts SET region_id = 'R09' WHERE name LIKE '%Wellington%' OR name LIKE '%Porirua%' OR name LIKE '%Kapiti%' OR name LIKE '%Hutt%';
UPDATE nz_addresses.districts SET region_id = 'R10' WHERE name LIKE '%Nelson%' OR name LIKE '%Tasman%';
UPDATE nz_addresses.districts SET region_id = 'R11' WHERE name LIKE '%Marlborough%' OR name LIKE '%Blenheim%';
UPDATE nz_addresses.districts SET region_id = 'R12' WHERE name LIKE '%West Coast%' OR name LIKE '%Buller%' OR name LIKE '%Grey%' OR name LIKE '%Westland%';
UPDATE nz_addresses.districts SET region_id = 'R13' WHERE name LIKE '%Canterbury%' OR name LIKE '%Christchurch%' OR name LIKE '%Timaru%' OR name LIKE '%Ashburton%';
UPDATE nz_addresses.districts SET region_id = 'R14' WHERE name LIKE '%Otago%' OR name LIKE '%Dunedin%' OR name LIKE '%Queenstown%' OR name LIKE '%Waitaki%';
UPDATE nz_addresses.districts SET region_id = 'R15' WHERE name LIKE '%Southland%' OR name LIKE '%Invercargill%' OR name LIKE '%Gore%';

DROP TABLE temp_districts;
EOSQL

docker cp /tmp/load_districts_final.sql $CONTAINER:/tmp/ 2>/dev/null
docker exec $CONTAINER psql -U $DB_USER -d $DB_NAME -f /tmp/load_districts_final.sql >/dev/null 2>&1

DISTRICT_COUNT=$(docker exec $CONTAINER psql -U $DB_USER -d $DB_NAME -t -c "SELECT COUNT(*) FROM nz_addresses.districts;")
log "✓ Loaded${DISTRICT_COUNT} districts"

log ""
log "Step 2: Loading Suburbs/Localities..."

# Create the SQL script for loading suburbs
cat > /tmp/load_suburbs_final.sql << 'EOSQL'
-- Create staging table matching CSV structure
DROP TABLE IF EXISTS temp_suburbs;
CREATE TEMP TABLE temp_suburbs (
    fid TEXT,
    id TEXT,
    name TEXT,
    additional_name TEXT,
    type TEXT,
    major_name TEXT,
    major_name_type TEXT,
    territorial_authority TEXT,
    population_estimate TEXT,
    name_ascii TEXT,
    additional_name_ascii TEXT,
    major_name_ascii TEXT,
    territorial_authority_ascii TEXT,
    shape TEXT
);

-- Load CSV data
\copy temp_suburbs FROM '/home/appuser/data/suburbs_localities.csv' WITH (FORMAT csv, HEADER true);

-- Insert into suburbs table with district matching
INSERT INTO nz_addresses.suburbs (suburb_id, district_id, name, name_ascii, major_name)
SELECT 
    -- Use the id from CSV or generate from name
    COALESCE(NULLIF(ts.id, ''), 's' || ts.fid) AS suburb_id,
    -- Match to district by territorial authority name
    COALESCE(
        (SELECT d.district_id 
         FROM nz_addresses.districts d 
         WHERE LOWER(ts.territorial_authority) LIKE '%' || LOWER(d.name) || '%'
            OR LOWER(d.name) LIKE '%' || LOWER(ts.territorial_authority) || '%'
         LIMIT 1),
        -- Fallback: try to find any district
        (SELECT district_id FROM nz_addresses.districts LIMIT 1)
    ) AS district_id,
    ts.name,
    ts.name_ascii,
    ts.major_name
FROM temp_suburbs ts
WHERE ts.name IS NOT NULL AND ts.name != ''
ON CONFLICT (suburb_id) DO NOTHING;

-- Remove suburbs that couldn't be matched to a district
DELETE FROM nz_addresses.suburbs WHERE district_id IS NULL;

DROP TABLE temp_suburbs;
EOSQL

docker cp /tmp/load_suburbs_final.sql $CONTAINER:/tmp/ 2>/dev/null
docker exec $CONTAINER psql -U $DB_USER -d $DB_NAME -f /tmp/load_suburbs_final.sql >/dev/null 2>&1

SUBURB_COUNT=$(docker exec $CONTAINER psql -U $DB_USER -d $DB_NAME -t -c "SELECT COUNT(*) FROM nz_addresses.suburbs;")
log "✓ Loaded${SUBURB_COUNT} suburbs"

log ""
log "Step 3: Creating indexes..."
docker exec $CONTAINER psql -U $DB_USER -d $DB_NAME -c "
CREATE INDEX IF NOT EXISTS idx_suburbs_name_lower ON nz_addresses.suburbs(LOWER(name));
CREATE INDEX IF NOT EXISTS idx_suburbs_name_ascii_lower ON nz_addresses.suburbs(LOWER(name_ascii));
ANALYZE nz_addresses.districts;
ANALYZE nz_addresses.suburbs;
" >/dev/null 2>&1

log "✓ Indexes created"

log ""
log "Step 4: Verifying data..."

# Show sample data
log ""
log "Sample Districts:"
docker exec $CONTAINER psql -U $DB_USER -d $DB_NAME -c "SELECT district_id, region_id, name FROM nz_addresses.districts ORDER BY name LIMIT 10;"

log ""
log "Sample Suburbs:"
docker exec $CONTAINER psql -U $DB_USER -d $DB_NAME -c "SELECT suburb_id, district_id, name, major_name FROM nz_addresses.suburbs ORDER BY name LIMIT 10;"

log ""
log "Districts by Region:"
docker exec $CONTAINER psql -U $DB_USER -d $DB_NAME -c "
SELECT r.name AS region, COUNT(d.district_id) AS district_count
FROM nz_addresses.regions r
LEFT JOIN nz_addresses.districts d ON d.region_id = r.region_id
GROUP BY r.region_id, r.name
ORDER BY r.name;
"

log ""
log "========================================="
log "DISTRICTS AND SUBURBS LOADED!"
log "========================================="
log "Summary:"
log "  - Districts:${DISTRICT_COUNT}"
log "  - Suburbs:${SUBURB_COUNT}"
log ""
log "Next: You may want to update address records to link to suburbs:"
log "  docker exec $CONTAINER psql -U $DB_USER -d $DB_NAME -c \\"
log "    UPDATE nz_addresses.addresses a SET suburb_id = ("
log "      SELECT s.suburb_id FROM nz_addresses.suburbs s"
log "      WHERE LOWER(s.name) = LOWER(a.suburb_locality)"
log "      LIMIT 1"
log "    ) WHERE suburb_id IS NULL;\\"
