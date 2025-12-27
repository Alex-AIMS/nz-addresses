-- Data quality checks after ETL
-- Validates row counts, hierarchy integrity, and geometry coverage

\echo '========================================='
\echo 'ETL Data Quality Checks'
\echo '========================================='
\echo ''

\echo 'Table Row Counts:'
\echo '-----------------'
SELECT 'regions' AS table_name, COUNT(*) AS row_count FROM nz_addresses.regions
UNION ALL
SELECT 'districts', COUNT(*) FROM nz_addresses.districts
UNION ALL
SELECT 'suburbs', COUNT(*) FROM nz_addresses.suburbs
UNION ALL
SELECT 'addresses', COUNT(*) FROM nz_addresses.addresses
UNION ALL
SELECT 'streets_by_suburb', COUNT(*) FROM nz_addresses.streets_by_suburb
ORDER BY table_name;

\echo ''
\echo 'Top 10 Suburbs by Street Count:'
\echo '--------------------------------'
SELECT
  s.name AS suburb_name,
  d.name AS district_name,
  COUNT(DISTINCT st.street_name) AS street_count
FROM nz_addresses.suburbs s
LEFT JOIN nz_addresses.districts d ON d.district_id = s.district_id
LEFT JOIN nz_addresses.streets_by_suburb st ON st.suburb_id = s.suburb_id
GROUP BY s.suburb_id, s.name, d.name
ORDER BY street_count DESC
LIMIT 10;

\echo ''
\echo 'Addresses with NULL Geometries:'
\echo '--------------------------------'
SELECT COUNT(*) AS null_geom_count
FROM nz_addresses.addresses
WHERE geom IS NULL;

\echo ''
\echo 'Spatial Index Status:'
\echo '---------------------'
SELECT
  schemaname,
  tablename,
  indexname
FROM pg_indexes
WHERE schemaname = 'nz_addresses'
  AND indexname LIKE 'idx_%_geom'
ORDER BY tablename;

\echo ''
\echo '========================================='
\echo 'Checks Complete'
\echo '========================================='
