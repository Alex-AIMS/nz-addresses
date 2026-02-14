# NZ-Addresses Database Persistence Setup

## Overview
The nz-addresses container now has persistent PostgreSQL data storage using a Docker named volume. This ensures that the 2.4M LINZ addresses remain available even when the container is rebuilt or restarted.

## Volume Configuration

### Named Volume
- **Volume Name**: `nz-addresses-pgdata`
- **Mount Point**: `/var/lib/postgresql/data`
- **Purpose**: Persists PostgreSQL database files between container rebuilds

### Data Directories
- **Local Path**: `/home/alex/dev/nz-addresses/data` → **Container**: `/home/appuser/data`
- **Local Path**: `/home/alex/dev/nz-addresses/scripts` → **Container**: `/home/appuser/scripts`

## Container Startup Command

```bash
docker run -d \
  -p 5432:5432 \
  -p 8080:8080 \
  --name nz-addresses \
  -e ConnectionStrings__DefaultConnection="Host=localhost;Port=5432;Database=nz_addresses_db;Username=nzuser;Password=nzpass" \
  -e POSTGRES_USER=nzuser \
  -e POSTGRES_PASSWORD=nzpass \
  -e POSTGRES_DB=nz_addresses_db \
  -v nz-addresses-pgdata:/var/lib/postgresql/data \
  -v /home/alex/dev/nz-addresses/data:/home/appuser/data \
  -v /home/alex/dev/nz-addresses/scripts:/home/appuser/scripts \
  nz-addresses:latest
```

## Database Statistics

After initial data load:
- **Regions**: 15 (REGC2023)
- **Districts**: 0 (schema exists, not populated)
- **Suburbs**: 0 (schema exists, not populated)
- **Addresses**: 2,400,341 (LINZ NZ Addresses)

## Data Loading Process

The data was loaded using a custom script: `scripts/load_all_data.sh`

### What the script does:
1. **Loads regions** from `regional-councils-correct.csv` (15 regions)
2. **Loads addresses** from `nz_addresses.csv` (2.4M records)
   - Creates temporary staging table
   - Bulk loads CSV with `\copy` command
   - Transforms coordinates from NZGD2000 (EPSG:4167) to NZTM2000 (EPSG:2193)
   - Creates spatial geometry points
   - Analyzes tables for query optimization

### To reload data:
```bash
cd /home/alex/dev/nz-addresses
bash scripts/load_all_data.sh
```

## Autocomplete Endpoint

### Endpoint
```
GET http://localhost:8080/autocomplete?query={search}&limit={number}
```

### Example Requests
```bash
# Search for "queen"
curl 'http://localhost:8080/autocomplete?query=queen&limit=5' | jq '.'

# Search for "ponsonby"
curl 'http://localhost:8080/autocomplete?query=ponsonby&limit=3' | jq '.'
```

### Example Response
```json
[
  {
    "addressId": 2060708,
    "fullAddress": "1001/171 Queen Street, Auckland Central, Auckland",
    "streetName": "Queen Street",
    "suburb": "Auckland Central",
    "city": "Auckland",
    "x": 174.76498137,
    "y": -36.8479131
  }
]
```

### Features
- Searches both `full_address` and `full_address_ascii` fields
- Case-insensitive matching using LOWER()
- Prioritizes addresses that start with the query string
- Returns up to `limit` results (default: 10)
- Includes coordinates in WGS84 (latitude/longitude)

## Persistence Benefits

### Data Survives:
- ✅ Container restarts (`docker restart nz-addresses`)
- ✅ Container recreation (`docker stop/rm/run`)
- ✅ System reboots
- ✅ Docker daemon restarts

### What's Preserved:
- All 2.4M address records
- All indexes (spatial and text)
- All table structures
- Query performance statistics

### What's NOT Preserved:
- Container configuration (must use same docker run command)
- Environment variables (must specify again)
- Bind mounts (must specify paths again)

## Rebuilding the Container

If you rebuild the Docker image (e.g., after code changes):

```bash
# Build new image
cd /home/alex/dev/nz-addresses
docker build -t nz-addresses:latest -f docker/Dockerfile .

# Stop and remove old container
docker stop nz-addresses
docker rm nz-addresses

# Start new container with SAME volume mount
docker run -d \
  -p 5432:5432 \
  -p 8080:8080 \
  --name nz-addresses \
  -e ConnectionStrings__DefaultConnection="Host=localhost;Port=5432;Database=nz_addresses_db;Username=nzuser;Password=nzpass" \
  -e POSTGRES_USER=nzuser \
  -e POSTGRES_PASSWORD=nzpass \
  -e POSTGRES_DB=nz_addresses_db \
  -v nz-addresses-pgdata:/var/lib/postgresql/data \
  -v /home/alex/dev/nz-addresses/data:/home/appuser/data \
  -v /home/alex/dev/nz-addresses/scripts:/home/appuser/scripts \
  nz-addresses:latest
```

**Important**: Use the same volume name (`nz-addresses-pgdata`) to preserve data.

## Volume Management

### Check volume exists:
```bash
docker volume ls | grep nz-addresses
```

### Inspect volume:
```bash
docker volume inspect nz-addresses-pgdata
```

### Backup volume:
```bash
# Create backup directory
mkdir -p ~/backups/nz-addresses

# Backup database
docker exec nz-addresses pg_dump -U nzuser -d nz_addresses_db -F c -f /tmp/nz_addresses_backup.dump
docker cp nz-addresses:/tmp/nz_addresses_backup.dump ~/backups/nz-addresses/nz_addresses_$(date +%Y%m%d).dump
```

### Restore from backup:
```bash
docker cp ~/backups/nz-addresses/nz_addresses_20251229.dump nz-addresses:/tmp/restore.dump
docker exec nz-addresses pg_restore -U nzuser -d nz_addresses_db -c /tmp/restore.dump
```

### Delete volume (WARNING: destroys all data):
```bash
docker stop nz-addresses
docker rm nz-addresses
docker volume rm nz-addresses-pgdata
```

## Connection Details

### From host machine:
- **Host**: localhost
- **Port**: 5432
- **Database**: nz_addresses_db
- **Username**: nzuser
- **Password**: nzpass

### Connection string:
```
Host=localhost;Port=5432;Database=nz_addresses_db;Username=nzuser;Password=nzpass
```

### Using psql:
```bash
docker exec -it nz-addresses psql -U nzuser -d nz_addresses_db
```

## Troubleshooting

### Container won't start
```bash
# Check logs
docker logs nz-addresses

# Check if port is already in use
sudo lsof -i :8080
sudo lsof -i :5432
```

### Data not persisting
```bash
# Verify volume is mounted
docker inspect nz-addresses | jq '.[0].Mounts'

# Check volume exists
docker volume ls | grep nz-addresses
```

### Autocomplete returns empty results
```bash
# Check database connection
docker logs nz-addresses 2>&1 | grep -i "error\|connection"

# Verify data exists
docker exec nz-addresses psql -U nzuser -d nz_addresses_db -c "SELECT COUNT(*) FROM nz_addresses.addresses;"

# Test database query directly
docker exec nz-addresses psql -U nzuser -d nz_addresses_db -c "SELECT * FROM nz_addresses.addresses WHERE LOWER(full_address) LIKE '%queen%' LIMIT 5;"
```

### Performance is slow
```bash
# Check indexes
docker exec nz-addresses psql -U nzuser -d nz_addresses_db -c "\d nz_addresses.addresses"

# Run ANALYZE
docker exec nz-addresses psql -U nzuser -d nz_addresses_db -c "ANALYZE nz_addresses.addresses;"
```

## Next Steps

For integration with portal-core profile editing:
1. Add autocomplete UI component to profile.html
2. Call `/autocomplete` endpoint with debounced search
3. Display dropdown with address suggestions
4. Populate address fields when user selects an address
5. Add address verification indicator

Example JavaScript integration:
```javascript
async function searchAddresses(query) {
    const response = await fetch(`http://localhost:8080/autocomplete?query=${encodeURIComponent(query)}&limit=10`);
    return await response.json();
}

// Usage with debounce
let debounceTimer;
addressInput.addEventListener('input', (e) => {
    clearTimeout(debounceTimer);
    debounceTimer = setTimeout(async () => {
        const results = await searchAddresses(e.target.value);
        displaySuggestions(results);
    }, 300);
});
```

## References

- LINZ Data Service: https://data.linz.govt.nz/
- Stats NZ Geographic Boundaries: https://datafinder.stats.govt.nz/
- PostGIS Documentation: https://postgis.net/documentation/
- Docker Volumes: https://docs.docker.com/storage/volumes/
