-- Staging table for LINZ NZ Addresses CSV import
-- Matches the structure of the LINZ NZ Street Address dataset (Layer 105689)

DROP TABLE IF EXISTS nz_addresses.stage_addresses;

CREATE TABLE nz_addresses.stage_addresses (
  fid TEXT,
  address_id BIGINT,
  source_dataset TEXT,
  change_id BIGINT,
  full_address_number TEXT,
  full_road_name TEXT,
  full_address TEXT,
  territorial_authority TEXT,
  unit_type TEXT,
  unit_value TEXT,
  level_type TEXT,
  level_value TEXT,
  address_number_prefix TEXT,
  address_number INT,
  address_number_suffix TEXT,
  address_number_high TEXT,
  road_name_prefix TEXT,
  road_name TEXT,
  road_type_name TEXT,
  road_suffix TEXT,
  water_name TEXT,
  water_body_name TEXT,
  suburb_locality TEXT,
  town_city TEXT,
  address_class TEXT,
  address_lifecycle TEXT,
  gd2000_xcoord DOUBLE PRECISION,
  gd2000_ycoord DOUBLE PRECISION,
  road_name_ascii TEXT,
  water_name_ascii TEXT,
  water_body_name_ascii TEXT,
  suburb_locality_ascii TEXT,
  town_city_ascii TEXT,
  full_road_name_ascii TEXT,
  full_address_ascii TEXT,
  shape TEXT
);

COMMENT ON TABLE nz_addresses.stage_addresses IS 'Temporary staging table for LINZ address CSV import (Layer 105689)';
