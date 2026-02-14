-- Add Market alignment to nz-addresses database
-- Run this after initial data load to add district aliases and suburb matching

-- Create district_aliases table
CREATE TABLE IF NOT EXISTS nz_addresses.district_aliases (
    alias_id SERIAL PRIMARY KEY,
    district_id VARCHAR(10) REFERENCES nz_addresses.districts(district_id),
    market_name VARCHAR(200) NOT NULL,
    alias_type VARCHAR(50) DEFAULT 'market',
    is_primary BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_district_aliases_district ON nz_addresses.district_aliases(district_id);
CREATE INDEX IF NOT EXISTS idx_district_aliases_market ON nz_addresses.district_aliases(market_name);

GRANT SELECT ON nz_addresses.district_aliases TO nzuser;
GRANT ALL ON SEQUENCE nz_addresses.district_aliases_alias_id_seq TO nzuser;

-- Populate Auckland local board → legacy city mappings
INSERT INTO nz_addresses.district_aliases (district_id, market_name, is_primary) 
SELECT district_id, 'Auckland City', true FROM nz_addresses.districts WHERE name = 'Albert-Eden Local Board Area'
UNION ALL SELECT district_id, 'Auckland City', false FROM nz_addresses.districts WHERE name = 'Orakei Local Board Area'
UNION ALL SELECT district_id, 'Auckland City', false FROM nz_addresses.districts WHERE name = 'Maungakiekie-Tamaki Local Board Area'
UNION ALL SELECT district_id, 'Auckland City', false FROM nz_addresses.districts WHERE name = 'Puketapapa Local Board Area'
UNION ALL SELECT district_id, 'Auckland City', false FROM nz_addresses.districts WHERE name = 'Waitemata Local Board Area'
UNION ALL SELECT district_id, 'Auckland City', false FROM nz_addresses.districts WHERE name = 'Whau Local Board Area'
UNION ALL SELECT district_id, 'Manukau City', true FROM nz_addresses.districts WHERE name = 'Manurewa Local Board Area'
UNION ALL SELECT district_id, 'Manukau City', false FROM nz_addresses.districts WHERE name = 'Mangere-Otahuhu Local Board Area'
UNION ALL SELECT district_id, 'Manukau City', false FROM nz_addresses.districts WHERE name = 'Otara-Papatoetoe Local Board Area'
UNION ALL SELECT district_id, 'Manukau City', false FROM nz_addresses.districts WHERE name = 'Howick Local Board Area'
UNION ALL SELECT district_id, 'North Shore City', true FROM nz_addresses.districts WHERE name = 'Hibiscus and Bays Local Board Area'
UNION ALL SELECT district_id, 'North Shore City', false FROM nz_addresses.districts WHERE name = 'Kaipatiki Local Board Area'
UNION ALL SELECT district_id, 'North Shore City', false FROM nz_addresses.districts WHERE name = 'Devonport-Takapuna Local Board Area'
UNION ALL SELECT district_id, 'Waitakere City', true FROM nz_addresses.districts WHERE name = 'Henderson-Massey Local Board Area'
UNION ALL SELECT district_id, 'Waitakere City', false FROM nz_addresses.districts WHERE name = 'Waitakere Ranges Local Board Area'
UNION ALL SELECT district_id, 'Papakura', true FROM nz_addresses.districts WHERE name = 'Papakura Local Board Area'
UNION ALL SELECT district_id, 'Rodney', true FROM nz_addresses.districts WHERE name = 'Rodney Local Board Area'
UNION ALL SELECT district_id, 'Franklin', true FROM nz_addresses.districts WHERE name = 'Franklin Local Board Area'
UNION ALL SELECT district_id, 'Waiheke Island', true FROM nz_addresses.districts WHERE name = 'Waiheke Local Board Area'
UNION ALL SELECT district_id, 'Hauraki Gulf Islands', true FROM nz_addresses.districts WHERE name = 'Aotea/Great Barrier Local Board Area'
ON CONFLICT DO NOTHING;

-- Add primary aliases for all other districts
INSERT INTO nz_addresses.district_aliases (district_id, market_name, is_primary)
SELECT district_id, name, true
FROM nz_addresses.districts
WHERE district_id NOT IN (SELECT district_id FROM nz_addresses.district_aliases)
ON CONFLICT DO NOTHING;

-- Recreate v_districts to use district aliases
DROP VIEW IF EXISTS nz_addresses.v_districts CASCADE;

CREATE VIEW nz_addresses.v_districts AS
SELECT 
    d.district_id,
    d.region_id,
    d.name AS official_name,
    COALESCE(
        (SELECT market_name FROM nz_addresses.district_aliases 
         WHERE district_id = d.district_id AND is_primary = true LIMIT 1),
        d.name
    ) AS display_name,
    d.geom,
    COALESCE((SELECT COUNT(*) FROM nz_addresses.suburbs s WHERE s.district_id = d.district_id), 0) AS suburb_count,
    COALESCE((SELECT COUNT(*) FROM nz_addresses.suburbs s WHERE s.district_id = d.district_id AND s.is_major_suburb = true), 0) AS major_suburb_count
FROM nz_addresses.districts d;

GRANT SELECT ON nz_addresses.v_districts TO nzuser;
