#!/bin/bash
set -e

echo "Loading hierarchy data (regions, districts, suburbs)..."

# Database connection parameters
export PGHOST=localhost
export PGPORT=5432
export PGDATABASE=nz_addresses_db
export PGUSER=nzuser
export PGPASSWORD=nzpass

DATA_DIR=/tmp

echo "1. Loading regional councils..."
psql -c "TRUNCATE TABLE nz_addresses.regions CASCADE;"
psql << EOF
\copy nz_addresses.regions_staging FROM '$DATA_DIR/regional-councils.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8');
EOF
psql -c "
INSERT INTO nz_addresses.regions (region_id, name, geom)
SELECT 
    mcon2023_v1_00,
    mcon2023_v1_00_name,
    ST_GeomFromText(shape, 2193)
FROM nz_addresses.regions_staging
WHERE shape IS NOT NULL AND shape != ''
ON CONFLICT (region_id) DO NOTHING;
"
REGION_COUNT=$(psql -t -c "SELECT COUNT(*) FROM nz_addresses.regions;")
echo "   Loaded $REGION_COUNT regions"

echo "2. Loading territorial authorities (districts)..."
psql -c "TRUNCATE TABLE nz_addresses.districts CASCADE;"
psql << EOF
\copy nz_addresses.districts_staging FROM '$DATA_DIR/territorial-authorities.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8');
EOF
psql -c "
INSERT INTO nz_addresses.districts (district_id, region_id, name, geom)
SELECT 
    talb2023_v1_00,
    -- Match to region by spatial intersection (find which region contains this district)
    (SELECT region_id FROM nz_addresses.regions r 
     WHERE ST_Intersects(r.geom, ST_GeomFromText(s.shape, 2193))
     ORDER BY ST_Area(ST_Intersection(r.geom, ST_GeomFromText(s.shape, 2193))) DESC
     LIMIT 1),
    talb2023_v1_00_name,
    ST_GeomFromText(shape, 2193)
FROM nz_addresses.districts_staging s
WHERE shape IS NOT NULL AND shape != ''
ON CONFLICT (district_id) DO NOTHING;
"
DISTRICT_COUNT=$(psql -t -c "SELECT COUNT(*) FROM nz_addresses.districts;")
echo "   Loaded $DISTRICT_COUNT districts"

echo "3. Loading suburbs/localities..."
psql -c "TRUNCATE TABLE nz_addresses.suburbs CASCADE;"
psql << EOF
\copy nz_addresses.suburbs_staging FROM '$DATA_DIR/suburbs_localities.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8');
EOF
psql -c "
INSERT INTO nz_addresses.suburbs (suburb_id, district_id, name, major_name, geom)
SELECT 
    id::text,
    -- Match to district by spatial intersection
    (SELECT district_id FROM nz_addresses.districts d 
     WHERE ST_Intersects(d.geom, ST_GeomFromText(s.shape, 2193))
     ORDER BY ST_Area(ST_Intersection(d.geom, ST_GeomFromText(s.shape, 2193))) DESC
     LIMIT 1),
    name,
    major_name,
    ST_GeomFromText(shape, 2193)
FROM nz_addresses.suburbs_staging s
WHERE shape IS NOT NULL AND shape != '' AND id IS NOT NULL
ON CONFLICT (suburb_id) DO NOTHING;
"
SUBURB_COUNT=$(psql -t -c "SELECT COUNT(*) FROM nz_addresses.suburbs;")
echo "   Loaded $SUBURB_COUNT suburbs"

echo "4. Refreshing materialized views..."
psql -c "REFRESH MATERIALIZED VIEW nz_addresses.v_regions;"
psql -c "REFRESH MATERIALIZED VIEW nz_addresses.v_districts;"
psql -c "REFRESH MATERIALIZED VIEW nz_addresses.v_suburbs;"

echo ""
echo "Hierarchy data loaded successfully!"
echo "  Regions: $REGION_COUNT"
echo "  Districts: $DISTRICT_COUNT"
echo "  Suburbs: $SUBURB_COUNT"
