#!/bin/bash

# Map unmapped LINZ suburbs to nearest Market suburbs using geometries
set -e

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

log "Mapping unmapped LINZ suburbs to nearest Market suburbs..."

docker exec -i nz-addresses psql -U nzuser -d nz_addresses_db << 'EOF'

-- Create or update the mapping table
CREATE TABLE IF NOT EXISTS nz_addresses.suburb_to_market_mapping (
    linz_suburb_id VARCHAR PRIMARY KEY,
    linz_suburb_name VARCHAR NOT NULL,
    market_suburb_id VARCHAR NOT NULL,
    market_suburb_name VARCHAR NOT NULL,
    market_district_id VARCHAR NOT NULL,
    mapping_method VARCHAR(50) NOT NULL,
    distance_meters NUMERIC
);

-- Insert direct name matches (already done, but ensure they're there)
INSERT INTO nz_addresses.suburb_to_market_mapping 
    (linz_suburb_id, linz_suburb_name, market_suburb_id, market_suburb_name, market_district_id, mapping_method)
SELECT 
    l.suburb_id,
    l.name,
    t.suburb_id,
    t.name,
    t.district_id,
    'name_match'
FROM nz_addresses.suburbs l
JOIN nz_addresses.suburbs t ON LOWER(TRIM(l.name)) = LOWER(TRIM(t.name))
WHERE l.market_match = false 
  AND t.market_match = true
ON CONFLICT (linz_suburb_id) DO NOTHING;

-- Map unmapped suburbs using spatial proximity
\timing on

WITH unmapped_suburbs AS (
    SELECT suburb_id, name, geom, district_id
    FROM nz_addresses.suburbs
    WHERE market_match = false
      AND geom IS NOT NULL
      AND suburb_id NOT IN (SELECT linz_suburb_id FROM nz_addresses.suburb_to_market_mapping)
),
market_suburbs AS (
    SELECT suburb_id, name, geom, district_id
    FROM nz_addresses.suburbs
    WHERE market_match = true
      AND geom IS NOT NULL
),
nearest_matches AS (
    SELECT DISTINCT ON (u.suburb_id)
        u.suburb_id as linz_suburb_id,
        u.name as linz_name,
        t.suburb_id as market_suburb_id,
        t.name as market_name,
        t.district_id as market_district_id,
        ST_Distance(ST_Transform(u.geom, 2193), ST_Transform(t.geom, 2193)) as distance
    FROM unmapped_suburbs u
    CROSS JOIN LATERAL (
        SELECT suburb_id, name, geom, district_id
        FROM market_suburbs t
        ORDER BY u.geom <-> t.geom
        LIMIT 5
    ) t
    ORDER BY u.suburb_id, ST_Distance(ST_Transform(u.geom, 2193), ST_Transform(t.geom, 2193))
)
INSERT INTO nz_addresses.suburb_to_market_mapping 
    (linz_suburb_id, linz_suburb_name, market_suburb_id, market_suburb_name, market_district_id, mapping_method, distance_meters)
SELECT 
    linz_suburb_id,
    linz_name,
    market_suburb_id,
    market_name,
    market_district_id,
    'spatial_nearest',
    distance
FROM nearest_matches
ON CONFLICT (linz_suburb_id) DO NOTHING;

-- Show mapping statistics
SELECT 
    mapping_method,
    COUNT(*) as count,
    ROUND(AVG(distance_meters), 0) as avg_distance_m,
    ROUND(MAX(distance_meters), 0) as max_distance_m
FROM nz_addresses.suburb_to_market_mapping
GROUP BY mapping_method
ORDER BY mapping_method;

-- Overall coverage
SELECT 
    COUNT(DISTINCT s.suburb_id) as total_linz_suburbs,
    COUNT(DISTINCT m.linz_suburb_id) as mapped_suburbs,
    ROUND(100.0 * COUNT(DISTINCT m.linz_suburb_id) / COUNT(DISTINCT s.suburb_id), 2) || '%' as coverage
FROM nz_addresses.suburbs s
LEFT JOIN nz_addresses.suburb_to_market_mapping m ON s.suburb_id = m.linz_suburb_id
WHERE s.market_match = false;

EOF

log "✓ Mapping complete"
