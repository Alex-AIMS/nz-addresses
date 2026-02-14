# NZ-Addresses Service

## Overview
The NZ-Addresses service provides comprehensive New Zealand address verification, geocoding, and geographic data lookups. It integrates with official data sources (LINZ, Stats NZ) and provides a REST API for address validation and enrichment used by other PortalCore services.

## Key Responsibilities
- New Zealand address verification and validation
- Address autocomplete and suggestion
- Geocoding (address → coordinates)
- Reverse geocoding (coordinates → address)
- Region, city, suburb, and postcode lookups
- Integration with LINZ (Land Information New Zealand) data
- Integration with Stats NZ geographic boundaries
- PostGIS spatial queries

## Technology Stack
- **.NET 8.0** - Runtime
- **ASP.NET Core Web API** - Framework
- **Entity Framework Core** - ORM
- **PostgreSQL with PostGIS** - Spatial database
- **LINZ Data Service** - Official NZ address data
- **Stats NZ Data** - Geographic boundaries and statistics

## Port Assignment
- **Internal**: 5003
- **External**: 5003 (accessible directly for development)
- **NGINX Gateway**: Routes `/api/addresses/*` to this service

## Project Structure
```
nz-addresses/
├── src/
│   ├── Controllers/
│   │   ├── AddressController.cs
│   │   ├── RegionsController.cs
│   │   └── GeocodeController.cs
│   ├── Services/
│   │   ├── AddressService.cs
│   │   ├── LinzDataService.cs
│   │   └── StatsNzService.cs
│   ├── Models/
│   ├── Data/
│   └── Program.cs
├── data/                           # Persistent storage for LINZ/StatsNZ data
├── scripts/
│   ├── import-linz-data.sh
│   └── import-statsnz-data.sh
├── docs/
├── config.env.example
├── config.env                      # Configuration (gitignored)
├── Dockerfile
└── README.md
```

## Database Schema
**Database**: `nz_addresses_db` (separate from portal database)
**Extension**: PostGIS (spatial/geographic queries)

### Tables
1. **addresses** - NZ address records from LINZ
   - id (serial, PK)
   - address_id (int, unique) - LINZ address ID
   - full_address (text)
   - unit, level, address_number
   - street_name, street_type
   - suburb_locality
   - town_city
   - postcode
   - region
   - coordinates (geography point) - PostGIS geometry
   - source (varchar) - LINZ, Manual, etc.

2. **regions** - NZ regions
   - id (serial, PK)
   - name (varchar)
   - code (varchar)
   - boundary (geography polygon) - PostGIS geometry

3. **suburbs** - NZ suburbs/localities
   - id (serial, PK)
   - name (varchar)
   - city (varchar)
   - region_id (int, FK)
   - postcode (varchar)
   - boundary (geography polygon)

## API Endpoints

### Address Verification
```
POST   /verify                         # Verify and standardize address
POST   /verify/batch                   # Batch verify multiple addresses
GET    /autocomplete?query={text}      # Address autocomplete suggestions
GET    /parse?address={text}           # Parse address into components
```

### Regions, Cities, Suburbs
```
GET    /regions                        # List all NZ regions
GET    /regions/{id}/cities            # Cities in a region
GET    /cities                         # List all cities
GET    /cities/{name}/suburbs          # Suburbs in a city
GET    /suburbs?region={name}          # Suburbs filtered by region
GET    /postcodes                      # List all postcodes
GET    /postcodes/{code}               # Get details for postcode
```

### Geocoding
```
POST   /geocode                        # Convert address to coordinates
POST   /reverse-geocode                # Convert coordinates to address
GET    /nearby?lat={lat}&lng={lng}&radius={m}  # Find addresses near point
```

### Health & Info
```
GET    /health                         # Service health check
GET    /info                           # API version and data freshness
```

## Configuration

### config.env
```bash
# Database
POSTGRES_USER=nzuser
POSTGRES_PASSWORD=secure_password_here
POSTGRES_DB=nz_addresses_db
ConnectionString=Host=nz-postgres;Port=5432;Database=nz_addresses_db;Username=nzuser;Password=secure_password_here

# External API Keys
LINZ_API_KEY=your_linz_api_key_here
STATSNZ_API_KEY=your_statsnz_api_key_here

# Application
ASPNETCORE_URLS=http://+:5003
ASPNETCORE_ENVIRONMENT=Production
```

### Environment Variables
- `POSTGRES_PASSWORD` - Database password
- `LINZ_API_KEY` - LINZ Data Service API key
- `STATSNZ_API_KEY` - Stats NZ API key

## Dependencies

### External Services
- **PostgreSQL with PostGIS** - nz-postgres:5432 (spatial database)
- **LINZ Data Service** - https://data.linz.govt.nz/ (address data)
- **Stats NZ** - https://datafinder.stats.govt.nz/ (geographic boundaries)

### NuGet Packages
- Microsoft.AspNetCore.App
- Npgsql.EntityFrameworkCore.PostgreSQL
- NetTopologySuite - Spatial data support
- NetTopologySuite.IO.PostGis - PostGIS integration

## Address Verification

### Verification Request
```json
POST /verify
{
  "street": "15 Beach Road",
  "city": "Auckland",
  "postalCode": "1010"
}
```

### Verification Response
```json
{
  "valid": true,
  "standardizedAddress": {
    "fullAddress": "15 Beach Road, Auckland Central, Auckland 1010",
    "street": "15 Beach Road",
    "suburb": "Auckland Central",
    "city": "Auckland",
    "region": "Auckland",
    "postalCode": "1010",
    "country": "New Zealand",
    "coordinates": {
      "latitude": -36.8485,
      "longitude": 174.7633
    }
  },
  "confidence": 0.95,
  "source": "LINZ",
  "suggestions": []
}
```

### Failed Verification
```json
{
  "valid": false,
  "message": "Address not found in LINZ database",
  "suggestions": [
    {
      "fullAddress": "15 Beach Haven Road, Beach Haven, Auckland 0626",
      "confidence": 0.75
    },
    {
      "fullAddress": "15 Beach Street, Queenstown 9300",
      "confidence": 0.65
    }
  ]
}
```

## Geocoding

### Geocode Request
```json
POST /geocode
{
  "address": "Sky Tower, Auckland"
}
```

### Geocode Response
```json
{
  "address": "Victoria Street West, Auckland Central, Auckland 1010",
  "coordinates": {
    "latitude": -36.8485,
    "longitude": 174.7633
  },
  "accuracy": "rooftop",
  "source": "LINZ"
}
```

### Reverse Geocode Request
```json
POST /reverse-geocode
{
  "latitude": -36.8485,
  "longitude": 174.7633
}
```

### Reverse Geocode Response
```json
{
  "address": "Victoria Street West, Auckland Central, Auckland 1010",
  "suburb": "Auckland Central",
  "city": "Auckland",
  "region": "Auckland",
  "postalCode": "1010",
  "distanceMeters": 12.5
}
```

## Data Import & Updates

### LINZ Data Import
```bash
# Import latest LINZ address data
./scripts/import-linz-data.sh

# This script:
# 1. Downloads latest LINZ address dataset
# 2. Extracts and processes CSV
# 3. Imports into PostgreSQL
# 4. Updates spatial indexes
```

### Stats NZ Data Import
```bash
# Import Stats NZ geographic boundaries
./scripts/import-statsnz-data.sh

# This script:
# 1. Downloads region/suburb boundaries
# 2. Imports shapefiles into PostGIS
# 3. Creates spatial indexes
```

### Data Freshness
- **LINZ Address Data**: Updated quarterly
- **Stats NZ Boundaries**: Updated annually
- **Last Update**: Check `/info` endpoint

## Spatial Queries (PostGIS)

### Find Nearby Addresses
```sql
-- Find all addresses within 500m of a point
SELECT * FROM addresses
WHERE ST_DWithin(
    coordinates,
    ST_SetSRID(ST_MakePoint(174.7633, -36.8485), 4326)::geography,
    500  -- meters
)
ORDER BY ST_Distance(
    coordinates,
    ST_SetSRID(ST_MakePoint(174.7633, -36.8485), 4326)::geography
)
LIMIT 10;
```

### Point in Polygon (Region Lookup)
```sql
-- Find which region contains a point
SELECT r.name, r.code
FROM regions r
WHERE ST_Contains(
    r.boundary,
    ST_SetSRID(ST_MakePoint(174.7633, -36.8485), 4326)
);
```

## Building & Running

### Local Development
```bash
# Set up configuration
cp config.env.example config.env
nano config.env  # Add API keys

# Build and run
dotnet restore
dotnet build
dotnet run --project src/
```

Service runs at: http://localhost:5003

### Docker
```bash
# Build image
docker build -t nz-addresses .

# Run with PostgreSQL
docker-compose up -d
```

### Via Orchestration
```bash
cd /home/alex/dev/portal-orchestration
docker-compose up -d nz-addresses nz-postgres
```

## Testing

### Health Check
```bash
curl http://localhost:5003/health
```

### Verify Address
```bash
curl -X POST http://localhost:5003/verify \
  -H "Content-Type: application/json" \
  -d '{
    "street": "123 Queen Street",
    "city": "Auckland",
    "postalCode": "1010"
  }'
```

### Get Regions
```bash
curl http://localhost:5003/regions
```

### Geocode Address
```bash
curl -X POST http://localhost:5003/geocode \
  -H "Content-Type: application/json" \
  -d '{"address": "Sky Tower, Auckland"}'
```

## Integration with PortalCore Services

### UserManagement Integration
- Validates addresses during user registration
- Enriches user profiles with standardized addresses

### RealEstate Integration
- Validates property addresses
- Provides geocoding for property listings
- Enables map-based property search
- Enriches listings with suburb/region data

### Usage Example in RealEstate Service
```csharp
// In RealEstate.Business/Services/AddressValidationService.cs
public async Task<Result<ValidatedAddress>> ValidateAddressAsync(string street, string city)
{
    var response = await _nzAddressesClient.PostAsJsonAsync("/verify", new
    {
        street,
        city
    });

    if (response.IsSuccessStatusCode)
    {
        var result = await response.Content.ReadFromJsonAsync<AddressVerificationResponse>();
        return Result<ValidatedAddress>.Success(result.StandardizedAddress);
    }

    return Result<ValidatedAddress>.Failure(
        Error.Validation("INVALID_ADDRESS", "Address could not be verified")
    );
}
```

## Data Sources

### LINZ (Land Information New Zealand)
- **API**: https://data.linz.govt.nz/
- **Dataset**: NZ Street Address (Electoral)
- **Update Frequency**: Quarterly
- **API Key**: Required (register at data.linz.govt.nz)

### Stats NZ
- **API**: https://datafinder.stats.govt.nz/
- **Datasets**: Regional boundaries, meshblocks, area units
- **Update Frequency**: Annual (post-census)
- **API Key**: Required (register at stats.govt.nz)

## Common Issues

### Issue: PostGIS extension not installed
**Solution**:
```sql
-- Connect to database as superuser
CREATE EXTENSION IF NOT EXISTS postgis;
```

### Issue: LINZ API rate limiting
**Solution**: LINZ API has rate limits. Consider:
- Caching frequently requested addresses
- Importing full LINZ dataset locally (quarterly updates)

### Issue: Spatial queries are slow
**Solution**: Ensure spatial indexes exist:
```sql
CREATE INDEX idx_addresses_coordinates ON addresses USING GIST(coordinates);
CREATE INDEX idx_regions_boundary ON regions USING GIST(boundary);
```

## Performance Optimization

### Caching Strategy
- Cache verified addresses for 7 days
- Cache region/suburb lookups indefinitely (static data)
- Use Redis if available (future enhancement)

### Indexing
```sql
-- Create indexes for common queries
CREATE INDEX idx_addresses_suburb ON addresses(suburb_locality);
CREATE INDEX idx_addresses_city ON addresses(town_city);
CREATE INDEX idx_addresses_postcode ON addresses(postcode);
CREATE INDEX idx_addresses_coordinates ON addresses USING GIST(coordinates);
```

## Related Services
- **UserManagement** - Uses for address validation during registration
- **RealEstate** - Uses for property address validation and geocoding
- **NGINX Gateway** - Routes `/api/addresses/*`

## Swagger UI
Access API documentation at:
- Direct: http://localhost:5003/swagger
- Via NGINX: http://localhost/swagger/addresses

## Git Repository
https://github.com/Alex-AIMS/nz-addresses

## Architecture Position
NZ-Addresses is a **specialized data service** providing authoritative New Zealand address data. It operates independently with its own database and external API integrations, serving other PortalCore services through a clean REST API.

## License & Data Usage
- **LINZ Data**: CC BY 4.0 - https://data.linz.govt.nz/license/
- **Stats NZ Data**: CC BY 4.0 - https://datafinder.stats.govt.nz/
- **Service Code**: MIT License (check LICENSE file)

Ensure compliance with LINZ and Stats NZ terms of use when using this service.
