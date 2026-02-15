-- Indexes for NZ Addresses schema
-- Spatial indexes (GIST) and text search indexes (GIN with pg_trgm)

-- Spatial indexes on geometries
CREATE INDEX idx_regions_geom ON nz_addresses.regions USING GIST (geom);
CREATE INDEX idx_districts_geom ON nz_addresses.districts USING GIST (geom);
CREATE INDEX idx_suburbs_geom ON nz_addresses.suburbs USING GIST (geom);
CREATE INDEX idx_addresses_geom ON nz_addresses.addresses USING GIST (geom);

-- Foreign key helper indexes
CREATE INDEX idx_districts_region_id ON nz_addresses.districts(region_id);
CREATE INDEX idx_suburbs_district_id ON nz_addresses.suburbs(district_id);

-- Address text search indexes
CREATE INDEX idx_addresses_full_road_name ON nz_addresses.addresses(full_road_name);
CREATE INDEX idx_addresses_full_road_name_ascii ON nz_addresses.addresses(full_road_name_ascii);
CREATE INDEX idx_addresses_suburb_locality ON nz_addresses.addresses(suburb_locality);
CREATE INDEX idx_addresses_suburb_locality_ascii ON nz_addresses.addresses(suburb_locality_ascii);
CREATE INDEX idx_addresses_address_number ON nz_addresses.addresses(address_number);

-- Trigram indexes for fuzzy text matching
CREATE INDEX idx_addresses_road_trgm ON nz_addresses.addresses USING GIN (full_road_name_ascii gin_trgm_ops);
CREATE INDEX idx_addresses_suburb_trgm ON nz_addresses.addresses USING GIN (suburb_locality_ascii gin_trgm_ops);
CREATE INDEX idx_addresses_full_address_trgm ON nz_addresses.addresses USING GIN (full_address_ascii gin_trgm_ops);

-- Streets by suburb index
CREATE INDEX idx_streets_suburb_id ON nz_addresses.streets_by_suburb(suburb_id);

-- Analyze tables for optimal query planning
ANALYZE nz_addresses.regions;
ANALYZE nz_addresses.districts;
ANALYZE nz_addresses.suburbs;
ANALYZE nz_addresses.addresses;
ANALYZE nz_addresses.streets_by_suburb;
