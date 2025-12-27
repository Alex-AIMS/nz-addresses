-- Compare RealEstate.co.nz suburbs with TradeMe suburbs

DROP TABLE IF EXISTS temp_realestate_suburbs;
CREATE TEMP TABLE temp_realestate_suburbs (
    region TEXT,
    district TEXT,
    suburb TEXT
);

\copy temp_realestate_suburbs FROM '/tmp/realestate_suburbs.csv' CSV HEADER

-- Clean suburb names (remove hyphens, convert to title case for comparison)
UPDATE temp_realestate_suburbs
SET suburb = INITCAP(REPLACE(suburb, '-', ' '));

UPDATE temp_realestate_suburbs
SET district = INITCAP(REPLACE(district, '-', ' '));

-- Summary statistics
\echo ''
\echo '=== SUBURB COMPARISON SUMMARY ==='
SELECT 
    'Total RealEstate.co.nz suburbs' AS metric,
    COUNT(*)::TEXT AS count
FROM temp_realestate_suburbs
UNION ALL
SELECT 
    'Total TradeMe suburbs' AS metric,
    COUNT(*)::TEXT AS count
FROM nz_addresses.suburbs
UNION ALL
SELECT 
    'Suburbs in BOTH platforms' AS metric,
    COUNT(*)::TEXT AS count
FROM temp_realestate_suburbs r
INNER JOIN nz_addresses.suburbs t
    ON LOWER(TRIM(r.suburb)) = LOWER(TRIM(t.name))
UNION ALL
SELECT 
    'Only in RealEstate.co.nz' AS metric,
    COUNT(*)::TEXT AS count
FROM temp_realestate_suburbs r
LEFT JOIN nz_addresses.suburbs t
    ON LOWER(TRIM(r.suburb)) = LOWER(TRIM(t.name))
WHERE t.name IS NULL
UNION ALL
SELECT 
    'Only in TradeMe' AS metric,
    COUNT(*)::TEXT AS count
FROM nz_addresses.suburbs t
LEFT JOIN temp_realestate_suburbs r
    ON LOWER(TRIM(r.suburb)) = LOWER(TRIM(t.name))
WHERE r.suburb IS NULL;

-- Show first 30 suburbs ONLY in RealEstate.co.nz (not in TradeMe)
\echo ''
\echo '=== Sample suburbs in RealEstate.co.nz but NOT in TradeMe ==='
SELECT 
    r.region,
    r.district,
    r.suburb
FROM temp_realestate_suburbs r
LEFT JOIN nz_addresses.suburbs t
    ON LOWER(TRIM(r.suburb)) = LOWER(TRIM(t.name))
WHERE t.name IS NULL
ORDER BY r.region, r.district, r.suburb
LIMIT 30;

-- Show first 30 suburbs ONLY in TradeMe (not in RealEstate.co.nz)
\echo ''
\echo '=== Sample suburbs in TradeMe but NOT in RealEstate.co.nz ==='
SELECT 
    r.region_name,
    d.name AS district_name,
    s.name AS suburb_name,
    s.has_centroid
FROM nz_addresses.suburbs s
JOIN nz_addresses.districts d ON s.district_id = d.district_id
JOIN nz_addresses.regions r ON d.region_id = r.region_id
LEFT JOIN temp_realestate_suburbs re
    ON LOWER(TRIM(re.suburb)) = LOWER(TRIM(s.name))
WHERE re.suburb IS NULL
ORDER BY r.region_name, d.name, s.name
LIMIT 30;
