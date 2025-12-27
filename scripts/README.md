# ETL - Extract, Transform, Load for NZ Addresses

This directory contains scripts to ingest geospatial data from LINZ and Stats NZ into the PostgreSQL/PostGIS database.

## Data Sources

### 1. LINZ NZ Addresses (CSV)
- **Source**: [LINZ Data Service](https://data.linz.govt.nz/)
- **Dataset**: NZ Street Address (Electoral)
- **Format**: CSV with coordinates in NZGD2000 (EPSG:4167)
- **Key Fields**: address_id, full_address, full_road_name, x/y coordinates
- **License**: CC BY 4.0

### 2. Suburbs and Localities (GeoPackage or Shapefile)
- **Source**: LINZ Data Service
- **Dataset**: NZ Locality Boundaries
- **Format**: GeoPackage or Shapefile
- **License**: CC BY 4.0

### 3. Territorial Authority Boundaries (Shapefile)
- **Source**: [Stats NZ](https://datafinder.stats.govt.nz/)
- **Dataset**: Territorial Authority 2023 (clipped)
- **Format**: Shapefile
- **License**: CC BY 4.0

### 4. Regional Council Boundaries (Shapefile)
- **Source**: Stats NZ
- **Dataset**: Regional Council 2023 (clipped)
- **Format**: Shapefile
- **License**: CC BY 4.0

## Modes of Operation

### Local Mode (Default)
Place downloaded files in `etl/data/` directory with these names:
- `regions.shp` (and .shx, .dbf, .prj)
- `territorial_authority.shp` (and .shx, .dbf, .prj)
- `suburbs_localities.gpkg`
- `nz_addresses.csv`

Run:
```bash
bash etl/etl.sh local
```

### WFS Mode (Web Feature Service)
Configure WFS URLs in `config.env`:
- `LDS_WFS_URL_ADDRESSES`
- `LDS_WFS_URL_SUBURBS`
- `STATS_WFS_URL_REGIONS`
- `STATS_WFS_URL_DISTRICTS`

Run:
```bash
bash etl/etl.sh wfs
```

## Coordinate Systems

All data is transformed to **NZTM2000 (EPSG:2193)** for storage:
- **Input LINZ Addresses**: NZGD2000 (EPSG:4167) → Transform to 2193
- **Input Boundaries**: Various (auto-detected) → Transform to 2193
- **Database Storage**: All geometries in SRID 2193

## ETL Process Flow

1. **Load Regions**: Import Stats NZ regional boundaries
2. **Load Districts**: Import Stats NZ territorial authority boundaries
3. **Load Suburbs**: Import LINZ locality boundaries
4. **Stage Addresses**: Create temporary staging table
5. **Load Addresses**: COPY CSV data into staging table
6. **Transform Addresses**: Convert coordinates to geometries, transform SRID
7. **Refresh Streets**: Build streets_by_suburb materialized table
8. **Analyze**: Update PostgreSQL statistics
9. **Validate**: Run data quality checks

## Troubleshooting

### Missing GDAL
```bash
apt-get install gdal-bin
```

### Permission Denied
Ensure `etl.sh` is executable:
```bash
chmod +x etl/etl.sh
```

### SRID Mismatch
The script automatically transforms all inputs to EPSG:2193. If you encounter SRID errors, check that PostGIS extension is installed:
```sql
SELECT PostGIS_Version();
```

### Empty Tables After ETL
Check `etl/logs/etl_YYYYMMDD_HHMMSS.log` for errors during import.

## Data Quality Checks

After ETL completes, the script runs automated checks:
- Row counts for all tables
- Top suburbs by street count
- Count of addresses with NULL geometries
- Spatial index verification

Review output in the ETL log file.

## Incremental Updates

To refresh only addresses (keeping boundaries):
```bash
# Edit etl.sh to comment out region/district/suburb imports
bash etl/etl.sh local
```

To refresh streets after address changes:
```sql
SELECT nz_addresses.refresh_streets_by_suburb();
```
