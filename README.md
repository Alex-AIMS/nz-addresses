# NZ Addresses - Address Verification & Hierarchical Browse Service

A comprehensive New Zealand address verification and hierarchical browse service using LINZ NZ Addresses dataset, Stats NZ geographic boundaries, and TradeMe market locality data.

## Overview

This service provides:
- **Address Verification**: Validate physical addresses against 2.4M official LINZ address records
- **Hierarchical Browse**: Navigate from Region → District → Suburb → Street with 2,320 market-friendly suburb names
- **Geocoding**: Precise NZTM2000 coordinates for every address
- **Spatial Queries**: PostGIS-powered geometry indexing and spatial operations
- **REST API**: Clean .NET 8 Web API with Swagger documentation

## Data Attribution

**Sourced from the LINZ Data Service and licensed for reuse under CC BY 4.0.**

**Stats NZ geographic boundaries licensed under CC BY 4.0.**

**TradeMe locality data used for market-friendly suburb naming.**

## Technology Stack

- **.NET 8.0**: C# web API and service layer
- **PostgreSQL 15 + PostGIS 3.x**: Spatial database with NZTM2000 (EPSG:2193) projection
- **Entity Framework Core**: Data access with NetTopologySuite for spatial types
- **Docker**: Single-container deployment with supervisord
- **Bash/Python**: ETL pipeline scripts for data ingestion

## Quick Start

### Prerequisites

- Docker installed and running
- ~1 GB disk space for data
- Internet connection for initial data download
- Free API keys from LINZ and Stats NZ (see Configuration below)

### 1. Configure Credentials

**Create your configuration file:**

```bash
cp config.env.example config.env
```

**Edit config.env and add your credentials:**

```bash
# Required: Get free API keys
LINZ_API_KEY=your_actual_linz_api_key_here
STATSNZ_API_KEY=your_actual_statsnz_key_here

# Optional: Change database credentials (defaults work fine)
POSTGRES_USER=nzuser
POSTGRES_PASSWORD=nzpass
```

**Get API Keys (free):**
- **LINZ**: https://data.linz.govt.nz/ → Sign in → My API Keys → Generate
- **Stats NZ**: https://datafinder.stats.govt.nz/ → Sign in → My Account → API Keys

⚠️ **Important**: The `config.env` file is in `.gitignore` and will NOT be committed to git.

### 2. Build the Docker Container

```bash
cd /path/to/nz-addresses
docker build -t nz-addresses:latest -f docker/Dockerfile .
```

This creates a container with:
- PostgreSQL 15 with PostGIS 3.4
- .NET 8 Web API
- All required extensions and schemas

### 3. Run the Container

```bash
docker run -d \
  -p 5432:5432 \
  -p 8080:8080 \
  --name nz-addresses \
  --env-file config.env \
  -v "$(pwd)/data:/home/appuser/data" \
  nz-addresses:latest
```

**Key options:**
- `--env-file config.env`: Loads your database credentials and API keys
- `-v $(pwd)/data:/home/appuser/data`: Mounts local data directory (optional, for persistence)

**Ports:**
- `5432`: PostgreSQL database
- `8080`: Web API and Swagger UI

**Check container status:**
```bash
docker logs nz-addresses
```

You should see both PostgreSQL and the Web API starting successfully.

### 4. Access the API

- **Swagger UI**: http://localhost:8080/swagger
- **API Base URL**: http://localhost:8080

**Test endpoint:**
```bash
curl http://localhost:8080/regions
```

## Database Setup

The database schema is automatically created when the container starts. To populate it with data, follow these steps:

### Step 1: Download Data Using Scripts

The easiest way is to use the automated download script inside the container:

```bash
# Download all required data (uses config.env for API keys)
docker exec nz-addresses bash /home/appuser/scripts/download_data_fast.sh
```

**This script automatically downloads:**
- LINZ NZ Addresses (2.4M addresses, ~761 MB)
- LINZ Suburbs/Localities (6,562 official localities)
- Stats NZ Regional Councils (REGC2023)
- Stats NZ Territorial Authorities (TALB2023)

**Alternative:** Download manually if you prefer:
```bash
# On your local machine, create data directory
mkdir -p data

# Then use the download script locally (requires API keys in config.env)
bash scripts/download_data_fast.sh
```

### Step 2: Load Geographic Hierarchy

The hierarchy loading script creates regions, districts, and suburbs with TradeMe market names:

```bash
# Copy script to container
docker cp scripts/load_hierarchy_correct.sh nz-addresses:/tmp/

# Execute hierarchy load
docker exec nz-addresses bash -c "cd /tmp && bash load_hierarchy_correct.sh"
```

**This script:**
1. Downloads TradeMe suburb list (2,320 suburbs)
2. Loads 16 REGC2023 regions
3. Loads TALB2023 territorial authorities + Auckland local boards
4. Creates district aliases (Auckland City, Manukau City, etc.)
5. Flags major suburbs by population category
6. Creates spatial indexes

**Expected output:**
```
Loaded 16 regions
Loaded 77 districts
Loaded 2320 suburbs
Created 21 district aliases
```

### Step 3: Load LINZ Addresses

```bash
# Load addresses using the fast ETL script
docker exec nz-addresses bash /home/appuser/scripts/etl_simple.sh
```

**The ETL process:**
1. Creates staging table
2. Loads CSV with COPY (fast bulk insert)
3. Normalizes address fields
4. Geocodes addresses to NZTM2000 coordinates
5. Links addresses to suburbs via spatial join
6. Creates spatial and text indexes

**Expected output:**
```
Loaded 2,401,234 addresses
Geocoded 2,398,102 addresses (99.87%)
Linked 2,385,441 to suburbs (99.3%)
Created 4 indexes
```

### Step 4: Populate Suburb Centroids

Suburb centroids enable map display and distance calculations:

```bash
# Fetch centroids from LINZ data and OpenStreetMap
# This takes ~30 minutes due to OSM rate limiting (1 req/sec)
docker exec nz-addresses bash /home/appuser/scripts/fetch_osm_centroids.sh
```

**This script:**
1. Checks LINZ addresses for suburb centroids (fast)
2. Falls back to OpenStreetMap Nominatim API
3. Uses intelligent name matching (expands St→Saint, Mt→Mount)
4. Handles special cases (City Centre, Island suffixes)
5. Applies regional fallbacks

**Expected results:**
- 2,301/2,320 suburbs with centroids (99.2%)
- 19 edge cases without centroids (sounds, hills, very small areas)

---

**That's it!** Your service is now fully loaded and ready to use. Visit http://localhost:8080/swagger to test the API.

## Project Structure

```
nz-addresses/
├── README.md                    # This file
├── docker/                      # Container configuration
│   ├── Dockerfile              # Multi-stage build: DB + API
│   ├── supervisord.conf        # Process manager config
│   └── initdb/                 # PostgreSQL initialization
│       ├── 00_init_extensions.sql   # PostGIS, pg_trgm
│       ├── 01_schema.sql            # Tables and types
│       ├── 02_indexes.sql           # Spatial and text indexes
│       ├── 03_functions.sql         # Search and geocoding
│       └── 04_views_and_refresh.sql # Materialized views
├── scripts/                     # ETL and data management
│   ├── load_hierarchy_correct.sh    # Load regions/districts/suburbs
│   ├── etl_simple.sh                # Load LINZ addresses
│   ├── fetch_osm_centroids.sh       # Populate suburb centroids
│   ├── fetch_realestate_suburbs.sh  # Compare RealEstate.co.nz
│   ├── compare_realestate_trademe.sql # Platform comparison
│   ├── download_data_correct.sh     # Download LINZ/Stats NZ data
│   ├── extract_regions.py           # Parse REGC2023 boundaries
│   ├── load_regions_sql.py          # Generate region INSERT SQL
│   └── sql/                         # ETL SQL snippets
│       ├── linz_stage_addresses.sql
│       ├── linz_stage_to_final.sql
│       └── hierarchy_staging.sql
├── docs/                        # Documentation
│   ├── README.md               # ETL detailed documentation
│   ├── TRADEME_COMPARISON.md   # TradeMe vs LINZ analysis
│   ├── FINAL_TRADEME_COMPARISON.md # Naming convention findings
│   └── REALESTATE_COMPARISON.md    # RealEstate.co.nz comparison
├── data/                        # Data files (git-ignored)
│   ├── nz_addresses.csv        # LINZ addresses
│   ├── regional-councils.csv   # REGC2023
│   ├── territorial-authorities.csv # TALB2023
│   └── suburbs_localities.*    # LINZ localities
└── src/                         # .NET 8 solution
    ├── NzAddresses.sln
    ├── NzAddresses.Domain/      # Entities and DTOs
    ├── NzAddresses.Core/        # Services and business logic
    └── NzAddresses.WebApi/      # REST API controllers
```

## API Endpoints

### Base URL
```
http://localhost:8080
```

### Available Endpoints

#### Hierarchy Browse
- `GET /regions` - List all 16 regions
- `GET /regions/{regionId}/districts` - List districts within a region
- `GET /districts/{districtId}/suburbs` - List suburbs within a district
- `GET /suburbs/{suburbId}/streets` - List streets within a suburb

#### Address Verification
- `GET /verify?rawAddress={address}` - Verify address exists in LINZ data

Example:
```bash
curl "http://localhost:8080/verify?rawAddress=14%20School%20Road,%20Auckland"
```

Response:
```json
{
  "exists": true,
  "matches": [
    {
      "fullAddress": "14 School Road, Morningside, Auckland 1025",
      "suburb": "Morningside",
      "district": "Auckland City",
      "region": "Auckland",
      "coordinates": {
        "latitude": -36.8763,
        "longitude": 174.7412,
        "nztm_x": 1756234.5,
        "nztm_y": 5920145.2
      }
    }
  ]
}
```

### Swagger UI

Interactive API documentation and testing:
```
http://localhost:8080/swagger
```

## Database Schema

### Tables

- **nz_addresses.regions** (16 records) - REGC2023 regional councils
- **nz_addresses.districts** (77 records) - TALB2023 + Auckland local boards
- **nz_addresses.district_aliases** (21 records) - Market names (Auckland City, Manukau City)
- **nz_addresses.suburbs** (2,320 records) - TradeMe localities with centroids
- **nz_addresses.addresses** (2.4M records) - LINZ NZ Addresses
- **nz_addresses.abbreviations** (8 records) - Address abbreviation expansion

### Key Features

**Spatial Indexing:**
- GiST indexes on all geometry columns
- NZTM2000 (EPSG:2193) for accurate NZ measurements
- WGS84 (EPSG:4326) for web mapping

**Text Search:**
- GIN indexes with pg_trgm for fuzzy matching
- Functional indexes on LOWER(TRIM(field))
- Full-text search on address components

**Functions:**
- `expand_abbreviations(text)` - St→Saint, Mt→Mount, etc.
- `search_addresses(query)` - Multi-field fuzzy search
- `geocode_address(street, suburb)` - Coordinate lookup

## Development

### Database Connection

**From host machine:**
```
Host: localhost
Port: 5432
Database: nz_addresses_db
Username: nzuser
Password: nzpass
```

**Connection string:**
```
Host=localhost;Port=5432;Database=nz_addresses_db;Username=nzuser;Password=nzpass
```

### Accessing PostgreSQL CLI

```bash
docker exec -it nz-addresses su - postgres -c "psql -d nz_addresses_db"
```

**Useful queries:**
```sql
-- Count addresses by suburb
SELECT s.name, COUNT(a.*) 
FROM nz_addresses.addresses a
JOIN nz_addresses.suburbs s ON a.suburb_id = s.suburb_id
GROUP BY s.name ORDER BY COUNT(*) DESC LIMIT 10;

-- Find addresses without geocodes
SELECT COUNT(*) FROM nz_addresses.addresses WHERE centroid IS NULL;

-- Check suburb centroid coverage
SELECT 
  COUNT(*) FILTER (WHERE centroid IS NOT NULL) AS with_centroid,
  COUNT(*) FILTER (WHERE centroid IS NULL) AS without_centroid
FROM nz_addresses.suburbs;
```

### Building .NET API Locally

Requirements:
- .NET 8 SDK
- Visual Studio 2022+ or VS Code

```bash
cd src
dotnet restore
dotnet build
dotnet run --project NzAddresses.WebApi
```

API will start on http://localhost:5000

### Running Tests

```bash
cd src
dotnet test
```

## Performance

### Database Metrics

- **Address lookup**: <10ms (indexed on suburb_locality + road_name)
- **Spatial queries**: <50ms (GiST indexed geometries)
- **Hierarchy browse**: <5ms (small dimension tables)
- **Full text search**: <100ms (pg_trgm GIN indexes)

### Optimization Tips

**For large imports:**
- Use `COPY` instead of INSERT
- Drop indexes before bulk load, recreate after
- Use `UNLOGGED` tables for staging
- Increase `shared_buffers` and `work_mem`

**For queries:**
- Always filter by suburb first (reduces dataset)
- Use spatial indexes for geometry operations
- Materialize commonly used joins

## Troubleshooting

### Container won't start

Check logs:
```bash
docker logs nz-addresses
```

Common issues:
- Port 5432 or 8080 already in use
- Insufficient memory (needs ~2GB)

### Database connection fails

Verify PostgreSQL is running:
```bash
docker exec nz-addresses su - postgres -c "psql -l"
```

### ETL fails

Check data file paths:
```bash
docker exec nz-addresses ls -lh /tmp/
```

Ensure files are copied to container before running scripts.

### API returns 500 errors

Check .NET logs:
```bash
docker logs nz-addresses | grep -A 10 "error"
```

Verify database connection string in container.

## Data Updates

To refresh data (e.g., quarterly LINZ updates):

1. **Download new address CSV** from LINZ
2. **Truncate addresses table:**
   ```sql
   TRUNCATE TABLE nz_addresses.addresses;
   ```
3. **Re-run ETL:**
   ```bash
   docker exec nz-addresses bash /tmp/etl_simple.sh
   ```

Hierarchy (regions/districts/suburbs) changes rarely - only update when Stats NZ releases new boundaries.

## License

This software is provided as-is for research and development purposes.

**Data sources are subject to their respective licenses:**
- LINZ NZ Addresses: CC BY 4.0
- Stats NZ geographic boundaries: CC BY 4.0
- TradeMe locality data: Used under fair use for reference

## Contributing

For issues, questions, or contributions, please contact the repository maintainer.

## References

- [LINZ Data Service](https://data.linz.govt.nz/)
- [Stats NZ Geographic Boundaries](https://datafinder.stats.govt.nz/)
- [TradeMe Property API](https://developer.trademe.co.nz/)
- [PostGIS Documentation](https://postgis.net/documentation/)
- [NZTM2000 Projection (EPSG:2193)](https://epsg.io/2193)
