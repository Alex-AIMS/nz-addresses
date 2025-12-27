-- Views for NZ Addresses
-- Provide convenient access to hierarchical counts

-- View: Regions with district count
CREATE OR REPLACE VIEW nz_addresses.v_regions AS
SELECT
  r.region_id,
  r.name,
  r.geom,
  COUNT(DISTINCT d.district_id) AS district_count
FROM nz_addresses.regions r
LEFT JOIN nz_addresses.districts d ON d.region_id = r.region_id
GROUP BY r.region_id, r.name, r.geom
ORDER BY r.name;

COMMENT ON VIEW nz_addresses.v_regions IS 'Regions with count of child districts';

-- View: Districts with suburb count
CREATE OR REPLACE VIEW nz_addresses.v_districts AS
SELECT
  d.district_id,
  d.region_id,
  d.name,
  d.geom,
  COUNT(DISTINCT s.suburb_id) AS suburb_count
FROM nz_addresses.districts d
LEFT JOIN nz_addresses.suburbs s ON s.district_id = d.district_id
GROUP BY d.district_id, d.region_id, d.name, d.geom
ORDER BY d.name;

COMMENT ON VIEW nz_addresses.v_districts IS 'Districts with count of child suburbs';

-- View: Suburbs with street count
CREATE OR REPLACE VIEW nz_addresses.v_suburbs AS
SELECT
  s.suburb_id,
  s.district_id,
  s.name,
  s.name_ascii,
  s.major_name,
  s.geom,
  COUNT(DISTINCT st.street_name) AS street_count
FROM nz_addresses.suburbs s
LEFT JOIN nz_addresses.streets_by_suburb st ON st.suburb_id = s.suburb_id
GROUP BY s.suburb_id, s.district_id, s.name, s.name_ascii, s.major_name, s.geom
ORDER BY s.name;

COMMENT ON VIEW nz_addresses.v_suburbs IS 'Suburbs with count of streets';

-- Initial refresh of streets_by_suburb
-- This will be empty until ETL loads data, but the call is here for completeness
SELECT nz_addresses.refresh_streets_by_suburb();
