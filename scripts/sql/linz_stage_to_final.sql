-- Transform staged addresses to final table
-- Converts GD2000 coordinates (EPSG:4167) to NZTM2000 (EPSG:2193) point geometries

INSERT INTO nz_addresses.addresses (
  address_id,
  full_address,
  full_address_ascii,
  full_road_name,
  full_road_name_ascii,
  address_number_prefix,
  address_number,
  address_number_suffix,
  suburb_locality,
  suburb_locality_ascii,
  town_city,
  territorial_authority,
  x_coord,
  y_coord,
  geom
)
SELECT
  address_id,
  full_address,
  COALESCE(full_address_ascii, nz_addresses.to_ascii(full_address)) AS full_address_ascii,
  full_road_name,
  COALESCE(full_road_name_ascii, nz_addresses.to_ascii(full_road_name)) AS full_road_name_ascii,
  address_number_prefix,
  address_number,
  address_number_suffix,
  suburb_locality,
  COALESCE(suburb_locality_ascii, nz_addresses.to_ascii(suburb_locality)) AS suburb_locality_ascii,
  town_city,
  territorial_authority,
  gd2000_xcoord AS x_coord,
  gd2000_ycoord AS y_coord,
  ST_Transform(
    ST_SetSRID(
      ST_MakePoint(gd2000_xcoord, gd2000_ycoord),
      4167  -- NZGD2000
    ),
    2193  -- NZTM2000
  )::geometry(Point, 2193) AS geom
FROM nz_addresses.stage_addresses
WHERE gd2000_xcoord IS NOT NULL
  AND gd2000_ycoord IS NOT NULL
  AND address_lifecycle = 'Current'
ON CONFLICT (address_id) DO UPDATE
SET
  full_address = EXCLUDED.full_address,
  full_address_ascii = EXCLUDED.full_address_ascii,
  full_road_name = EXCLUDED.full_road_name,
  full_road_name_ascii = EXCLUDED.full_road_name_ascii,
  address_number_prefix = EXCLUDED.address_number_prefix,
  address_number = EXCLUDED.address_number,
  address_number_suffix = EXCLUDED.address_number_suffix,
  suburb_locality = EXCLUDED.suburb_locality,
  suburb_locality_ascii = EXCLUDED.suburb_locality_ascii,
  town_city = EXCLUDED.town_city,
  territorial_authority = EXCLUDED.territorial_authority,
  x_coord = EXCLUDED.x_coord,
  y_coord = EXCLUDED.y_coord,
  geom = EXCLUDED.geom;