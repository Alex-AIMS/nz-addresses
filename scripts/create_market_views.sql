-- ============================================================================
-- RECREATE ALL VIEWS TO USE MARKET HIERARCHY
-- ============================================================================
-- This script creates views that prioritize Market suburb/district/region
-- hierarchy over LINZ hierarchy for API consumption.
-- 
-- Usage:
--   docker exec -i nz-addresses psql -U nzuser -d nz_addresses_db < create_market_views.sql
-- ============================================================================

-- Step 1: Drop existing views (in reverse dependency order)
DROP VIEW IF EXISTS nz_addresses.v_addresses CASCADE;
DROP VIEW IF EXISTS nz_addresses.v_suburbs CASCADE;
DROP VIEW IF EXISTS nz_addresses.v_districts CASCADE;
DROP VIEW IF EXISTS nz_addresses.v_regions CASCADE;

-- ============================================================================
-- Step 2: Create v_regions view - Market regions aggregated from mappings
-- ============================================================================
CREATE OR REPLACE VIEW nz_addresses.v_regions AS
WITH market_regions AS (
    -- Get all regions that contain Market suburbs
    SELECT DISTINCT
        r.region_id,
        r.name,
        r.geom
    FROM nz_addresses.regions r
    INNER JOIN nz_addresses.districts d ON d.region_id = r.region_id
    INNER JOIN nz_addresses.suburbs s ON s.district_id = d.district_id
    WHERE s.market_match = true
)
SELECT 
    region_id,
    name,
    name AS display_name,
    geom,
    -- Count only Market districts in this region
    COALESCE((
        SELECT COUNT(DISTINCT d.district_id)
        FROM nz_addresses.districts d
        INNER JOIN nz_addresses.suburbs s ON s.district_id = d.district_id
        WHERE d.region_id = tr.region_id 
        AND s.market_match = true
    ), 0) AS market_district_count,
    -- Count all Market suburbs in this region
    COALESCE((
        SELECT COUNT(*)
        FROM nz_addresses.suburbs s
        INNER JOIN nz_addresses.districts d ON d.district_id = s.district_id
        WHERE d.region_id = tr.region_id
        AND s.market_match = true
    ), 0) AS market_suburb_count
FROM market_regions tr;

COMMENT ON VIEW nz_addresses.v_regions IS 'Market regions - only includes regions with Market suburbs';
COMMENT ON COLUMN nz_addresses.v_regions.market_district_count IS 'Count of districts containing Market suburbs';
COMMENT ON COLUMN nz_addresses.v_regions.market_suburb_count IS 'Count of Market suburbs in this region';

-- ============================================================================
-- Step 3: Create v_districts view - Market districts aggregated from mappings
-- ============================================================================
CREATE OR REPLACE VIEW nz_addresses.v_districts AS
WITH market_districts AS (
    -- Get all districts that contain Market suburbs
    SELECT DISTINCT
        d.district_id,
        d.region_id,
        d.name,
        d.geom
    FROM nz_addresses.districts d
    INNER JOIN nz_addresses.suburbs s ON s.district_id = d.district_id
    WHERE s.market_match = true
)
SELECT 
    district_id,
    region_id,
    name AS official_name,
    -- Use market name if available, otherwise official name
    TRIM(BOTH FROM regexp_replace(
        regexp_replace(
            COALESCE((
                SELECT market_name 
                FROM nz_addresses.district_aliases 
                WHERE district_id = td.district_id 
                AND is_primary = true
                LIMIT 1
            ), name), 
            ' District$', '', 'i'
        ), 
        ' Local Board Area$', '', 'i'
    )) AS display_name,
    geom,
    -- Count only Market suburbs in this district
    COALESCE((
        SELECT COUNT(*)
        FROM nz_addresses.suburbs s
        WHERE s.district_id = td.district_id
        AND s.market_match = true
    ), 0) AS market_suburb_count
FROM market_districts td;

COMMENT ON VIEW nz_addresses.v_districts IS 'Market districts - only includes districts with Market suburbs';
COMMENT ON COLUMN nz_addresses.v_districts.official_name IS 'Official LINZ district name';
COMMENT ON COLUMN nz_addresses.v_districts.display_name IS 'Market market name (cleaned)';
COMMENT ON COLUMN nz_addresses.v_districts.market_suburb_count IS 'Count of Market suburbs in this district';

-- ============================================================================
-- Step 4: Create v_suburbs view - Market suburbs with mapping info
-- ============================================================================
CREATE OR REPLACE VIEW nz_addresses.v_suburbs AS
SELECT 
    s.suburb_id,
    s.name AS suburb_name,
    s.district_id,
    d.name AS district_name,
    -- Use market name for display
    COALESCE((
        SELECT market_name 
        FROM nz_addresses.district_aliases 
        WHERE district_id = s.district_id 
        AND is_primary = true
        LIMIT 1
    ), d.name) AS district_display_name,
    d.region_id,
    r.name AS region_name,
    s.market_match,
    s.geom,
    -- Self-reference for Market suburbs (they map to themselves)
    CASE 
        WHEN s.market_match = true THEN s.suburb_id
        ELSE m.market_suburb_id
    END AS market_suburb_id,
    CASE 
        WHEN s.market_match = true THEN s.name
        ELSE m.market_suburb_name
    END AS market_suburb_name,
    CASE 
        WHEN s.market_match = true THEN s.district_id
        ELSE m.market_district_id
    END AS market_district_id,
    CASE 
        WHEN s.market_match = true THEN 'market_suburb'
        ELSE m.mapping_method
    END AS mapping_method,
    CASE 
        WHEN s.market_match = true THEN 0.00
        ELSE m.distance_meters
    END AS distance_meters
FROM nz_addresses.suburbs s
LEFT JOIN nz_addresses.districts d ON s.district_id = d.district_id
LEFT JOIN nz_addresses.regions r ON d.region_id = r.region_id
LEFT JOIN nz_addresses.suburb_to_market_mapping m ON s.suburb_id = m.linz_suburb_id
-- Only include suburbs that are Market suburbs OR have a mapping
WHERE s.market_match = true OR m.linz_suburb_id IS NOT NULL;

COMMENT ON VIEW nz_addresses.v_suburbs IS 'All suburbs with Market mapping - includes both Market suburbs and mapped LINZ suburbs';
COMMENT ON COLUMN nz_addresses.v_suburbs.suburb_name IS 'LINZ suburb name';
COMMENT ON COLUMN nz_addresses.v_suburbs.market_suburb_name IS 'Mapped Market suburb name (same as suburb_name for Market suburbs)';
COMMENT ON COLUMN nz_addresses.v_suburbs.mapping_method IS 'How suburb was mapped: market_suburb, direct_match, or nearest_neighbor';
COMMENT ON COLUMN nz_addresses.v_suburbs.distance_meters IS 'Distance to mapped Market suburb (0 for Market suburbs)';

-- ============================================================================
-- Step 5: Create v_addresses view - All addresses with Market hierarchy
-- ============================================================================
CREATE OR REPLACE VIEW nz_addresses.v_addresses AS
WITH address_suburb_mapping AS (
    -- Map each address to its suburb and then to Market hierarchy
    SELECT 
        a.address_id,
        a.full_address,
        a.full_address_ascii,
        a.full_road_name,
        a.full_road_name_ascii,
        a.address_number_prefix,
        a.address_number,
        a.address_number_suffix,
        a.suburb_locality AS linz_suburb_name,
        a.suburb_locality_ascii,
        a.town_city,
        a.territorial_authority,
        a.x_coord,
        a.y_coord,
        a.geom,
        -- Get LINZ suburb details
        s.suburb_id AS linz_suburb_id,
        s.district_id AS linz_district_id,
        d.region_id AS linz_region_id,
        -- Get Market mapping
        CASE 
            WHEN s.market_match = true THEN s.suburb_id
            ELSE m.market_suburb_id
        END AS market_suburb_id,
        CASE 
            WHEN s.market_match = true THEN s.name
            ELSE m.market_suburb_name
        END AS market_suburb_name,
        CASE 
            WHEN s.market_match = true THEN s.district_id
            ELSE m.market_district_id
        END AS market_district_id,
        CASE 
            WHEN s.market_match = true THEN 'market_suburb'
            ELSE m.mapping_method
        END AS mapping_method,
        CASE 
            WHEN s.market_match = true THEN 0.00
            ELSE m.distance_meters
        END AS distance_meters
    FROM nz_addresses.addresses a
    LEFT JOIN nz_addresses.suburbs s 
        ON LOWER(TRIM(a.suburb_locality)) = LOWER(TRIM(s.name))
    LEFT JOIN nz_addresses.districts d 
        ON s.district_id = d.district_id
    LEFT JOIN nz_addresses.suburb_to_market_mapping m 
        ON s.suburb_id = m.linz_suburb_id
)
SELECT 
    asm.address_id,
    asm.full_address,
    asm.full_address_ascii,
    asm.full_road_name,
    asm.full_road_name_ascii,
    asm.address_number_prefix,
    asm.address_number,
    asm.address_number_suffix,
    -- LINZ original data (for reference)
    asm.linz_suburb_name,
    asm.linz_suburb_id,
    asm.linz_district_id,
    asm.linz_region_id,
    -- Market hierarchy (PRIMARY - use these for display)
    asm.market_suburb_name,
    asm.market_suburb_id,
    asm.market_district_id,
    COALESCE((
        SELECT market_name 
        FROM nz_addresses.district_aliases 
        WHERE district_id = asm.market_district_id 
        AND is_primary = true
        LIMIT 1
    ), td.name) AS market_district_name,
    td.region_id AS market_region_id,
    tr.name AS market_region_name,
    -- Mapping metadata (for debugging/transparency)
    asm.mapping_method,
    asm.distance_meters,
    -- Original address fields
    asm.town_city,
    asm.territorial_authority,
    asm.x_coord,
    asm.y_coord,
    asm.geom
FROM address_suburb_mapping asm
LEFT JOIN nz_addresses.districts td ON asm.market_district_id = td.district_id
LEFT JOIN nz_addresses.regions tr ON td.region_id = tr.region_id;

COMMENT ON VIEW nz_addresses.v_addresses IS 'All addresses with both LINZ and Market hierarchy - use market_* fields for display';
COMMENT ON COLUMN nz_addresses.v_addresses.linz_suburb_name IS 'Original LINZ suburb name from address data';
COMMENT ON COLUMN nz_addresses.v_addresses.market_suburb_name IS 'Mapped Market suburb name - USE THIS for display';
COMMENT ON COLUMN nz_addresses.v_addresses.market_district_name IS 'Market market district name - USE THIS for display';
COMMENT ON COLUMN nz_addresses.v_addresses.market_region_name IS 'Market region name - USE THIS for display';
COMMENT ON COLUMN nz_addresses.v_addresses.mapping_method IS 'How suburb was mapped: market_suburb, direct_match, nearest_neighbor, or NULL if no mapping';
COMMENT ON COLUMN nz_addresses.v_addresses.distance_meters IS 'Distance from LINZ suburb to Market suburb (0 for direct matches)';

-- ============================================================================
-- Grant permissions
-- ============================================================================
GRANT SELECT ON nz_addresses.v_regions TO nzuser;
GRANT SELECT ON nz_addresses.v_districts TO nzuser;
GRANT SELECT ON nz_addresses.v_suburbs TO nzuser;
GRANT SELECT ON nz_addresses.v_addresses TO nzuser;

-- ============================================================================
-- Verification queries
-- ============================================================================
\echo '============================================================================'
\echo 'View Creation Complete - Row Counts:'
\echo '============================================================================'

SELECT 'v_regions' AS view_name, COUNT(*) AS row_count FROM nz_addresses.v_regions
UNION ALL
SELECT 'v_districts', COUNT(*) FROM nz_addresses.v_districts
UNION ALL
SELECT 'v_suburbs', COUNT(*) FROM nz_addresses.v_suburbs
UNION ALL
SELECT 'v_addresses', COUNT(*) FROM nz_addresses.v_addresses;

\echo ''
\echo '============================================================================'
\echo 'Sample Market Mappings:'
\echo '============================================================================'

SELECT 
    suburb_name AS linz_suburb,
    market_suburb_name AS market_suburb,
    mapping_method,
    ROUND(distance_meters::numeric, 2) as distance_m
FROM nz_addresses.v_suburbs
WHERE mapping_method IN ('market_suburb', 'nearest_neighbor')
ORDER BY distance_meters DESC NULLS LAST
LIMIT 5;

\echo ''
\echo '============================================================================'
\echo 'Address Coverage with Market Hierarchy:'
\echo '============================================================================'

SELECT 
    COUNT(*) as total_addresses,
    COUNT(market_suburb_name) as with_market_suburb,
    COUNT(market_district_name) as with_market_district,
    COUNT(market_region_name) as with_market_region,
    ROUND(100.0 * COUNT(market_suburb_name) / COUNT(*), 2) || '%' as coverage
FROM nz_addresses.v_addresses;
