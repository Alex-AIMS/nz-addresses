#!/bin/bash
set -e

# Map LINZ suburbs to Market suburbs using nearest neighbor approach
# This handles the 4,590 suburbs not in Market data

cd "$(dirname "$0")"

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*"
}

log "Starting suburb-to-Market mapping process..."

# Step 1: Create materialized view of Market suburb centroids for performance
log "Creating Market suburb centroids..."
docker exec -i nz-addresses psql -U nzuser -d nz_addresses_db <<'SQL'
DROP MATERIALIZED VIEW IF EXISTS nz_addresses.market_suburb_centroids CASCADE;

CREATE MATERIALIZED VIEW nz_addresses.market_suburb_centroids AS
SELECT 
    s.suburb_id,
    s.name,
    s.district_id,
    ST_Centroid(ST_Collect(a.geom)) as centroid,
    COUNT(a.address_id) as address_count
FROM nz_addresses.suburbs s
JOIN nz_addresses.addresses a ON LOWER(TRIM(a.suburb_locality)) = LOWER(TRIM(s.name))
WHERE s.market_match = true 
  AND a.geom IS NOT NULL
GROUP BY s.suburb_id, s.name, s.district_id;

CREATE INDEX idx_market_centroids_geom ON nz_addresses.market_suburb_centroids USING GIST(centroid);

SELECT COUNT(*) as market_suburbs_with_centroids FROM nz_addresses.market_suburb_centroids;
SQL

# Step 2: Map unmapped suburbs in batches
log "Mapping unmapped suburbs to nearest Market suburbs..."
docker exec -i nz-addresses psql -U nzuser -d nz_addresses_db <<'SQL'
WITH unmapped_suburbs AS (
    SELECT 
        s.suburb_id,
        s.name,
        ST_Centroid(ST_Collect(a.geom)) as centroid
    FROM nz_addresses.suburbs s
    JOIN nz_addresses.addresses a ON LOWER(TRIM(a.suburb_locality)) = LOWER(TRIM(s.name))
    WHERE (s.market_match = false OR s.market_match IS NULL)
      AND a.geom IS NOT NULL
      AND NOT EXISTS (
          SELECT 1 FROM nz_addresses.suburb_to_market_mapping m
          WHERE m.linz_suburb_id = s.suburb_id
      )
    GROUP BY s.suburb_id, s.name
),
nearest_matches AS (
    SELECT 
        u.suburb_id as linz_suburb_id,
        u.name as linz_suburb_name,
        (SELECT t.name 
         FROM nz_addresses.market_suburb_centroids t
         ORDER BY u.centroid <-> t.centroid
         LIMIT 1) as market_suburb_name,
        (SELECT t.district_id 
         FROM nz_addresses.market_suburb_centroids t
         ORDER BY u.centroid <-> t.centroid
         LIMIT 1) as market_district_id,
        (SELECT ST_Distance(u.centroid, t.centroid) 
         FROM nz_addresses.market_suburb_centroids t
         ORDER BY u.centroid <-> t.centroid
         LIMIT 1) as distance_meters
    FROM unmapped_suburbs u
)
INSERT INTO nz_addresses.suburb_to_market_mapping 
    (linz_suburb_id, linz_suburb_name, market_suburb_name, market_district_id, mapping_method, distance_meters)
SELECT 
    linz_suburb_id,
    linz_suburb_name,
    market_suburb_name,
    market_district_id,
    'nearest_neighbor',
    ROUND(distance_meters::numeric, 2)
FROM nearest_matches
WHERE market_suburb_name IS NOT NULL;

-- Show results
SELECT 
    mapping_method,
    COUNT(*) as suburb_count,
    ROUND(AVG(distance_meters)::numeric, 0) as avg_distance_m,
    ROUND(MAX(distance_meters)::numeric, 0) as max_distance_m
FROM nz_addresses.suburb_to_market_mapping
GROUP BY mapping_method
ORDER BY mapping_method;
SQL

log "Mapping complete!"
