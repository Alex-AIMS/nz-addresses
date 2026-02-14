-- Map unmapped LINZ suburbs to nearest Market suburb using address centroids

WITH market_suburbs AS (
    SELECT s.suburb_id, s.name, s.district_id,
           ST_Centroid(ST_Collect(a.geom)) as centroid
    FROM nz_addresses.suburbs s
    JOIN nz_addresses.addresses a ON LOWER(TRIM(a.suburb_locality)) = LOWER(TRIM(s.name))
    WHERE s.market_match = true 
      AND a.geom IS NOT NULL
    GROUP BY s.suburb_id, s.name, s.district_id
),
unmapped_suburbs AS (
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
    SELECT DISTINCT ON (u.suburb_id)
        u.suburb_id as linz_suburb_id,
        u.name as linz_suburb_name,
        t.name as market_suburb_name,
        t.district_id as market_district_id,
        ST_Distance(u.centroid, t.centroid) as distance_meters
    FROM unmapped_suburbs u
    CROSS JOIN LATERAL (
        SELECT name, district_id, centroid
        FROM market_suburbs t
        ORDER BY u.centroid <-> t.centroid
        LIMIT 1
    ) t
    ORDER BY u.suburb_id
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
FROM nearest_matches;
