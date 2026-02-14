-- ============================================================================
-- FIX VIEWS TO MATCH API SERVICE EXPECTATIONS
-- ============================================================================
-- This script updates the views to include all columns expected by the API
-- ============================================================================

-- Drop and recreate v_regions with district_count alias
DROP VIEW IF EXISTS nz_addresses.v_regions CASCADE;

CREATE OR REPLACE VIEW nz_addresses.v_regions AS
WITH market_regions AS (
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
    COALESCE((
        SELECT COUNT(DISTINCT d.district_id)
        FROM nz_addresses.districts d
        INNER JOIN nz_addresses.suburbs s ON s.district_id = d.district_id
        WHERE d.region_id = tr.region_id 
        AND s.market_match = true
    ), 0) AS district_count,  -- API expects this column name
    COALESCE((
        SELECT COUNT(*)
        FROM nz_addresses.suburbs s
        INNER JOIN nz_addresses.districts d ON d.district_id = s.district_id
        WHERE d.region_id = tr.region_id
        AND s.market_match = true
    ), 0) AS market_suburb_count
FROM market_regions tr;

COMMENT ON VIEW nz_addresses.v_regions IS 'Market regions - only includes regions with Market suburbs';
COMMENT ON COLUMN nz_addresses.v_regions.district_count IS 'Count of districts containing Market suburbs (for API)';

-- Drop and recreate v_districts with suburb_count alias
DROP VIEW IF EXISTS nz_addresses.v_districts CASCADE;

CREATE OR REPLACE VIEW nz_addresses.v_districts AS
WITH market_districts AS (
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
    COALESCE((
        SELECT COUNT(*)
        FROM nz_addresses.suburbs s
        WHERE s.district_id = td.district_id
        AND s.market_match = true
    ), 0) AS suburb_count  -- API expects this column name
FROM market_districts td;

COMMENT ON VIEW nz_addresses.v_districts IS 'Market districts - only includes districts with Market suburbs';
COMMENT ON COLUMN nz_addresses.v_districts.suburb_count IS 'Count of Market suburbs in this district (for API)';

-- Drop and recreate v_suburbs with all required columns
DROP VIEW IF EXISTS nz_addresses.v_suburbs CASCADE;

CREATE OR REPLACE VIEW nz_addresses.v_suburbs AS
SELECT 
    s.suburb_id,
    -- Expose all base columns needed by API
    s.name,  -- API expects "name" column
    s.name_ascii,
    s.major_name,
    s.is_major_suburb,
    s.population_category,
    s.sort_priority,
    -- Additional metadata
    s.name AS suburb_name,
    s.district_id,
    d.name AS district_name,
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
    -- Computed street count
    COALESCE((
        SELECT COUNT(DISTINCT street_name)
        FROM nz_addresses.streets_by_suburb
        WHERE suburb_id = s.suburb_id
    ), 0) AS street_count,
    -- Market mapping info
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

COMMENT ON VIEW nz_addresses.v_suburbs IS 'All suburbs with Market mapping - includes all columns needed by API';
COMMENT ON COLUMN nz_addresses.v_suburbs.name IS 'Suburb name (for API compatibility)';
COMMENT ON COLUMN nz_addresses.v_suburbs.street_count IS 'Number of unique streets in this suburb';

-- Grant permissions
GRANT SELECT ON nz_addresses.v_regions TO nzuser;
GRANT SELECT ON nz_addresses.v_districts TO nzuser;
GRANT SELECT ON nz_addresses.v_suburbs TO nzuser;

-- Verification
\echo '============================================================================'
\echo 'Views fixed - checking columns:'
\echo '============================================================================'

SELECT 'v_regions' AS view_name, COUNT(*) AS row_count FROM nz_addresses.v_regions
UNION ALL
SELECT 'v_districts', COUNT(*) FROM nz_addresses.v_districts
UNION ALL
SELECT 'v_suburbs', COUNT(*) FROM nz_addresses.v_suburbs;

\echo ''
\echo 'Sample v_suburbs with all columns:'
SELECT suburb_id, name, street_count, is_major_suburb, population_category
FROM nz_addresses.v_suburbs
LIMIT 3;
