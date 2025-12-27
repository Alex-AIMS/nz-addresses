-- Functions for NZ Addresses
-- Utilities for hierarchy resolution, street materialization, and text normalization

-- Function: Refresh the streets_by_suburb materialized table
CREATE OR REPLACE FUNCTION nz_addresses.refresh_streets_by_suburb()
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  -- Create temporary table with distinct streets per suburb
  CREATE TEMP TABLE temp_streets_by_suburb AS
  SELECT DISTINCT
    s.suburb_id,
    a.full_road_name_ascii AS street_name
  FROM nz_addresses.suburbs s
  INNER JOIN nz_addresses.addresses a ON ST_Within(a.geom, s.geom)
  WHERE a.full_road_name_ascii IS NOT NULL
    AND a.full_road_name_ascii <> '';

  -- Clear and repopulate the main table
  TRUNCATE nz_addresses.streets_by_suburb;
  
  INSERT INTO nz_addresses.streets_by_suburb (suburb_id, street_name)
  SELECT suburb_id, street_name
  FROM temp_streets_by_suburb
  ORDER BY suburb_id, street_name;

  DROP TABLE temp_streets_by_suburb;

  RAISE NOTICE 'streets_by_suburb refreshed with % rows', (SELECT COUNT(*) FROM nz_addresses.streets_by_suburb);
END;
$$;

COMMENT ON FUNCTION nz_addresses.refresh_streets_by_suburb IS 'Rebuild streets_by_suburb from spatial join of addresses and suburbs';

-- Function: Resolve hierarchy (region, district, suburb) for a point geometry
CREATE OR REPLACE FUNCTION nz_addresses.resolve_hierarchy(pt GEOMETRY(Point, 2193))
RETURNS TABLE (
  region_id VARCHAR(10),
  district_id VARCHAR(10),
  suburb_id VARCHAR(50)
)
LANGUAGE plpgsql
AS $$
DECLARE
  v_district_id VARCHAR(10);
  v_region_id VARCHAR(10);
  v_suburb_id VARCHAR(50);
BEGIN
  -- Find containing suburb
  SELECT s.suburb_id, s.district_id
  INTO v_suburb_id, v_district_id
  FROM nz_addresses.suburbs s
  WHERE ST_Within(pt, s.geom)
  LIMIT 1;

  -- If suburb found, get its district and region
  IF v_district_id IS NOT NULL THEN
    SELECT d.region_id
    INTO v_region_id
    FROM nz_addresses.districts d
    WHERE d.district_id = v_district_id;
  ELSE
    -- No suburb found, try direct district lookup
    SELECT d.district_id, d.region_id
    INTO v_district_id, v_region_id
    FROM nz_addresses.districts d
    WHERE ST_Within(pt, d.geom)
    LIMIT 1;
  END IF;

  RETURN QUERY SELECT v_region_id, v_district_id, v_suburb_id;
END;
$$;

COMMENT ON FUNCTION nz_addresses.resolve_hierarchy IS 'Determine region, district, and suburb IDs for a given point geometry';

-- Function: Simple ASCII transliteration
CREATE OR REPLACE FUNCTION nz_addresses.to_ascii(input TEXT)
RETURNS TEXT
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
  result TEXT;
BEGIN
  result := input;
  
  -- Basic transliteration table for common diacritics
  result := REPLACE(result, 'ā', 'a');
  result := REPLACE(result, 'ē', 'e');
  result := REPLACE(result, 'ī', 'i');
  result := REPLACE(result, 'ō', 'o');
  result := REPLACE(result, 'ū', 'u');
  result := REPLACE(result, 'Ā', 'A');
  result := REPLACE(result, 'Ē', 'E');
  result := REPLACE(result, 'Ī', 'I');
  result := REPLACE(result, 'Ō', 'O');
  result := REPLACE(result, 'Ū', 'U');
  
  -- Additional common diacritics
  result := REPLACE(result, 'á', 'a');
  result := REPLACE(result, 'é', 'e');
  result := REPLACE(result, 'í', 'i');
  result := REPLACE(result, 'ó', 'o');
  result := REPLACE(result, 'ú', 'u');
  result := REPLACE(result, 'Á', 'A');
  result := REPLACE(result, 'É', 'E');
  result := REPLACE(result, 'Í', 'I');
  result := REPLACE(result, 'Ó', 'O');
  result := REPLACE(result, 'Ú', 'U');
  
  RETURN result;
END;
$$;

COMMENT ON FUNCTION nz_addresses.to_ascii IS 'Simple ASCII transliteration for Māori macrons and common diacritics';
