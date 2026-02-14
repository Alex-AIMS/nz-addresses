#!/bin/bash
set -e

# Apply Market suburb-to-district mappings
# This script maps suburbs to districts using Market hierarchy while keeping addresses correctly geo-located

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DATA_DIR="$SCRIPT_DIR/../data"

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*"
}

log "Starting Market suburb-district mapping process..."

# Step 1: Extract Market mappings to CSV
log "Extracting Market suburb-to-district mappings..."
cat "$DATA_DIR/market_localities.json" | jq -r '
  .[] | 
  .Name as $region | 
  .Districts[] | 
  .Name as $district | 
  .Suburbs[] | 
  "\($region)|\($district)|\(.Name)"
' > /tmp/market_suburb_mappings.csv

MAPPING_COUNT=$(wc -l < /tmp/market_suburb_mappings.csv)
log "Extracted $MAPPING_COUNT Market suburb-district mappings"

# Step 2: Create Market mapping table and apply mappings
log "Applying Market mappings to database..."

docker exec -i nz-addresses psql -U nzuser -d nz_addresses_db <<'EOSQL'

-- Create Market suburb mappings table
DROP TABLE IF EXISTS nz_addresses.market_suburb_mappings CASCADE;
CREATE TABLE nz_addresses.market_suburb_mappings (
    region_name VARCHAR(200) NOT NULL,
    district_name VARCHAR(200) NOT NULL,
    suburb_name VARCHAR(200) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_market_mappings_suburb ON nz_addresses.market_suburb_mappings(suburb_name);
CREATE INDEX idx_market_mappings_district ON nz_addresses.market_suburb_mappings(district_name);

EOSQL

# Step 3: Load Market mappings into database
log "Loading Market mappings into database..."
cat /tmp/market_suburb_mappings.csv | docker exec -i nz-addresses psql -U nzuser -d nz_addresses_db -c "COPY nz_addresses.market_suburb_mappings(region_name, district_name, suburb_name) FROM STDIN WITH (FORMAT csv, DELIMITER '|');"

# Step 4: Update suburb-district assignments based on Market mappings
log "Updating suburb-district assignments..."

docker exec -i nz-addresses psql -U nzuser -d nz_addresses_db <<'EOSQL'

-- Reset all suburb district assignments first (to handle suburbs that moved or don't exist in Market)
UPDATE nz_addresses.suburbs SET district_id = NULL;

-- Apply Market mappings
-- Match suburbs to districts based on Market hierarchy
UPDATE nz_addresses.suburbs s
SET district_id = d.district_id
FROM nz_addresses.market_suburb_mappings tm
JOIN nz_addresses.districts d ON (
    -- First try exact match with district name
    LOWER(TRIM(tm.district_name)) = LOWER(TRIM(d.name))
    OR 
    -- Then try match with district alias
    EXISTS (
        SELECT 1 FROM nz_addresses.district_aliases da
        WHERE da.district_id = d.district_id
        AND LOWER(TRIM(tm.district_name)) = LOWER(TRIM(da.market_name))
    )
)
WHERE LOWER(TRIM(s.name)) = LOWER(TRIM(tm.suburb_name));

-- Get statistics
WITH stats AS (
    SELECT 
        COUNT(*) as total_suburbs,
        COUNT(district_id) as mapped_suburbs,
        COUNT(*) - COUNT(district_id) as unmapped_suburbs
    FROM nz_addresses.suburbs
)
SELECT 
    total_suburbs as "Total Suburbs",
    mapped_suburbs as "Mapped to Districts",
    unmapped_suburbs as "Not Mapped"
FROM stats;

-- Show sample Market mappings (Franklin example)
SELECT 
    d.name as district_name,
    COUNT(s.suburb_id) as suburb_count,
    STRING_AGG(s.name, ', ' ORDER BY s.name LIMIT 5) as sample_suburbs
FROM nz_addresses.suburbs s
JOIN nz_addresses.districts d ON s.district_id = d.district_id
WHERE d.name LIKE '%Franklin%'
GROUP BY d.name;

-- Show suburbs that couldn't be mapped
SELECT COUNT(*) as unmapped_count
FROM nz_addresses.suburbs
WHERE district_id IS NULL;

EOSQL

log "Market suburb-district mapping complete!"
log ""
log "Summary:"
log "  - Market mappings loaded: $MAPPING_COUNT"
log "  - Suburbs now mapped according to Market hierarchy"
log "  - Addresses remain correctly geo-located to their suburbs"
log ""
log "Note: Suburbs not in Market data remain unmapped (district_id = NULL)"

# Cleanup
rm -f /tmp/market_suburb_mappings.csv

log "Done!"
