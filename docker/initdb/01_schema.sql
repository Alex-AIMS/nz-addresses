-- Schema and table definitions for NZ Addresses
-- SRID: 2193 (NZTM2000 - New Zealand Transverse Mercator 2000)

CREATE SCHEMA IF NOT EXISTS nz_addresses;

-- Regions (Regional Council boundaries from Stats NZ)
CREATE TABLE nz_addresses.regions (
  region_id VARCHAR(10) PRIMARY KEY,
  name VARCHAR(200) NOT NULL,
  geom GEOMETRY(Polygon, 2193)
);

-- Districts (Territorial Authority boundaries from Stats NZ)
CREATE TABLE nz_addresses.districts (
  district_id VARCHAR(10) PRIMARY KEY,
  region_id VARCHAR(10) NOT NULL,
  name VARCHAR(200) NOT NULL,
  geom GEOMETRY(Polygon, 2193),
  CONSTRAINT fk_district_region FOREIGN KEY (region_id) REFERENCES nz_addresses.regions(region_id)
);

-- Suburbs and Localities (from LINZ)
CREATE TABLE nz_addresses.suburbs (
  suburb_id VARCHAR(50) PRIMARY KEY,
  district_id VARCHAR(10) NOT NULL,
  name VARCHAR(200) NOT NULL,
  name_ascii VARCHAR(200),
  major_name VARCHAR(200),
  geom GEOMETRY(Polygon, 2193),
  CONSTRAINT fk_suburb_district FOREIGN KEY (district_id) REFERENCES nz_addresses.districts(district_id)
);

-- Addresses (LINZ NZ Addresses)
CREATE TABLE nz_addresses.addresses (
  address_id BIGINT PRIMARY KEY,
  full_address TEXT,
  full_address_ascii TEXT,
  full_road_name VARCHAR(200),
  full_road_name_ascii VARCHAR(200),
  address_number_prefix VARCHAR(10),
  address_number INT,
  address_number_suffix VARCHAR(10),
  suburb_locality VARCHAR(200),
  suburb_locality_ascii VARCHAR(200),
  town_city VARCHAR(200),
  territorial_authority VARCHAR(200),
  x_coord DOUBLE PRECISION,
  y_coord DOUBLE PRECISION,
  geom GEOMETRY(Point, 2193)
);

-- Streets by Suburb (materialized join for performance)
CREATE TABLE nz_addresses.streets_by_suburb (
  suburb_id VARCHAR(50) NOT NULL,
  street_name VARCHAR(200) NOT NULL,
  PRIMARY KEY (suburb_id, street_name),
  CONSTRAINT fk_street_suburb FOREIGN KEY (suburb_id) REFERENCES nz_addresses.suburbs(suburb_id)
);

COMMENT ON SCHEMA nz_addresses IS 'Authoritative NZ address verification and hierarchy data';
COMMENT ON TABLE nz_addresses.regions IS 'Regional council boundaries from Stats NZ';
COMMENT ON TABLE nz_addresses.districts IS 'Territorial authority boundaries from Stats NZ';
COMMENT ON TABLE nz_addresses.suburbs IS 'Suburb and locality boundaries from LINZ';
COMMENT ON TABLE nz_addresses.addresses IS 'NZ address points from LINZ';
COMMENT ON TABLE nz_addresses.streets_by_suburb IS 'Materialized street list per suburb for fast lookup';
