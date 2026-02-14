# NZ Addresses Service

## Overview
The NZ Addresses service provides New Zealand address verification and hierarchical browsing using LINZ address data and Stats NZ geographic boundaries. It offers geocoding, reverse geocoding, and spatial queries via a .NET 8 Minimal API backed by PostgreSQL with PostGIS.

## Key Responsibilities
- Address verification against 2.4M official LINZ address records
- Hierarchical browse: Region → District → Suburb → Street
- Geocoding (address to coordinates)
- Reverse geocoding (coordinates to address)
- Spatial queries using PostGIS geometry operations

## Technology Stack
- **.NET 8.0** - Runtime
- **ASP.NET Core Minimal API** - Framework (no controllers, uses `MapGet`)
- **Entity Framework Core** - ORM with NetTopologySuite for spatial types
- **Dapper** - Lightweight data access (used alongside EF Core)
- **PostgreSQL 15 + PostGIS 3.4** - Spatial database (consolidated into portal-postgres)
- **NZTM2000 (EPSG:2193)** - Internal spatial projection

## Port Assignment
- **Internal**: 5003
- **External**: 5003 (accessible directly for development)
- **NGINX Gateway**: Routes `/api/addresses/*` to this service

## Project Structure
```
nz-addresses/
├── src/
│   ├── NzAddresses.WebApi/      # Minimal API (Program.cs with MapGet endpoints)
│   ├── NzAddresses.Core/        # Business logic (services, parsing)
│   │   ├── Services/
│   │   │   ├── INzAddressService.cs
│   │   │   └── NzAddressService.cs
│   │   └── Parsing/
│   │       └── LibpostalNormalizer.cs
│   ├── NzAddresses.Data/        # Data access (DbContext)
│   │   └── NzAddressesDbContext.cs
│   └── NzAddresses.Domain/      # Entities and DTOs
│       ├── Entities/
│       │   ├── Region.cs
│       │   ├── District.cs
│       │   ├── Suburb.cs
│       │   └── Address.cs
│       └── Dtos/
│           └── HierarchyDtos.cs
├── test/
│   └── NzAddresses.Tests/
├── scripts/
│   ├── download_data.sh         # Downloads LINZ/StatsNZ geospatial data
│   ├── etl.sh                   # ETL pipeline for importing data
│   └── README.md                # Pipeline documentation
├── docker/
│   ├── initdb/                  # SQL init scripts (also copied to portal-orchestration)
│   │   ├── 00_init_extensions.sql
│   │   ├── 01_schema.sql
│   │   ├── 02_indexes.sql
│   │   ├── 03_functions.sql
│   │   └── 04_views_and_refresh.sql
│   └── supervisord.conf         # Legacy (pre DB consolidation)
├── docs/
├── Dockerfile
├── .dockerignore
├── .gitignore
├── .env.example
├── README.md
├── CLAUDE.md
└── NzAddresses.sln
```

## Database Schema
Schema: `nz_addresses` (in consolidated portal-postgres)

### Tables
| Table | Purpose |
|-------|---------|
| `regions` | Regional council boundaries (Stats NZ), PostGIS Polygon geometry |
| `districts` | Territorial authority boundaries (Stats NZ), FK → regions |
| `suburbs` | Suburb/locality boundaries (LINZ), FK → districts |
| `addresses` | 2.4M NZ address points (LINZ), PostGIS Point geometry |
| `streets_by_suburb` | Materialized street list per suburb for fast lookup |

### Views
- `v_regions` - Regions with district count
- `v_districts` - Districts with suburb count
- `v_suburbs` - Suburbs with street count

### Key Functions
- `refresh_streets_by_suburb()` - Rebuild street lookup from spatial join
- `resolve_hierarchy(point)` - Determine region/district/suburb for a coordinate
- `to_ascii(text)` - Transliterate Māori macrons to ASCII

## API Endpoints
Uses Minimal API pattern (endpoints defined in `Program.cs`):

| Method | Path | Description |
|--------|------|-------------|
| GET | `/regions` | List all regions with district counts |
| GET | `/regions/{regionId}/districts` | List districts within a region |
| GET | `/districts/{districtId}/suburbs` | List suburbs within a district |
| GET | `/suburbs/{suburbId}/streets` | List streets within a suburb |
| GET | `/verify?rawAddress=...` | Verify address against LINZ data |
| GET | `/addressForCoordinates?latitude=...&longitude=...` | Reverse geocode |
| GET | `/coordinatesForAddress?rawAddress=...` | Forward geocode |
| GET | `/health` | Health check |

## Connection Configuration
```
ConnectionString: Host=portal-postgres;Port=5432;Database=portal;Username=portaladmin;Password=${PORTAL_DB_PASSWORD};SearchPath=nz_addresses
```

## ETL Pipeline
Located in `scripts/`. Requires `ogr2ogr` (GDAL), `psql`, `wget`.

1. `download_data.sh` - Downloads ~500MB from LINZ and Stats NZ APIs
2. `etl.sh` - Imports regions, districts, suburbs, addresses into PostGIS
3. Runs spatial joins to build `streets_by_suburb` materialized lookup

Required API keys: `LINZ_API_KEY`, `STATSNZ_API_KEY`

## Dependencies
- **External APIs**: LINZ Data Service, Stats NZ Data Finder
- **Database**: portal-postgres (consolidated PostgreSQL + PostGIS instance)
- **No PortalCore.Common**: This service operates independently

## Development

### Build
```bash
cd /home/alex/portal/nz-addresses
dotnet build NzAddresses.sln
```

### Run Locally
```bash
export CONNECTION_STRING="Host=localhost;Port=5433;Database=portal;Username=portaladmin;Password=YOUR_PASSWORD;SearchPath=nz_addresses"
dotnet run --project src/NzAddresses.WebApi
```

### Run Tests
```bash
dotnet test NzAddresses.sln
```
