-- Staging table for regional councils
CREATE TABLE IF NOT EXISTS nz_addresses.regions_staging (
    fid TEXT,
    mcon2023_v1_00 TEXT,
    mcon2023_v1_00_name TEXT,
    mcon2023_v1_00_name_ascii TEXT,
    land_area_sq_km NUMERIC,
    area_sq_km NUMERIC,
    shape_length NUMERIC,
    shape_area NUMERIC,
    shape TEXT
);

-- Staging table for territorial authorities (districts)
CREATE TABLE IF NOT EXISTS nz_addresses.districts_staging (
    fid TEXT,
    talb2023_v1_00 TEXT,
    talb2023_v1_00_name TEXT,
    talb2023_v1_00_name_ascii TEXT,
    land_area_sq_km NUMERIC,
    area_sq_km NUMERIC,
    shape_length NUMERIC,
    shape_area NUMERIC,
    shape TEXT
);

-- Staging table for suburbs/localities
CREATE TABLE IF NOT EXISTS nz_addresses.suburbs_staging (
    fid TEXT,
    id INTEGER,
    name TEXT,
    additional_name TEXT,
    type TEXT,
    major_name TEXT,
    major_name_type TEXT,
    territorial_authority TEXT,
    population_estimate INTEGER,
    name_ascii TEXT,
    additional_name_ascii TEXT,
    major_name_ascii TEXT,
    territorial_authority_ascii TEXT,
    shape TEXT
);
