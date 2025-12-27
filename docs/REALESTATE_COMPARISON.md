# RealEstate.co.nz vs TradeMe Suburb Comparison

## Summary

| Platform | Total Suburbs |
|----------|---------------|
| **RealEstate.co.nz** | 1,890 |
| **TradeMe** | 2,320 |
| **In BOTH platforms** | 1,795 (95% of RealEstate, 77% of TradeMe) |
| **Only in RealEstate.co.nz** | 95 |
| **Only in TradeMe** | 525 |

## Key Findings

1. **TradeMe has 430 more suburbs** (2,320 vs 1,890) - TradeMe's list is more comprehensive
2. **95% overlap** - Most RealEstate.co.nz suburbs are also in TradeMe
3. **TradeMe has 525 unique suburbs** not found on RealEstate.co.nz

## Sample Suburbs ONLY in RealEstate.co.nz (not in TradeMe)

Examples of suburbs that appear on RealEstate.co.nz but not in TradeMe database:

| Region | District | Suburb |
|--------|----------|--------|
| auckland | Auckland City | Waiotaiki Bay |
| auckland | Franklin | Whangape |
| auckland | Hauraki Gulf Islands | Other Islands |
| auckland | Manukau City | Auckland Airport |
| auckland | Manukau City | Hillpark |
| auckland | Manukau City | Middlemore Hospital |
| auckland | North Shore City | Stanley Point |
| auckland | Papakura | Hingaia |
| auckland | Rodney | Port Albert |
| auckland | Rodney | Wayby Valley |
| bay-of-plenty | Rotorua | Rotorua Central |
| bay-of-plenty | Tauranga | Tauranga Central |

**Observations:**
- Some are very specific locations (airports, hospitals)
- Some are "Surrounds" or "Central" variants
- Some are very small localities

## Analysis

### Why does TradeMe have more suburbs?

1. **Historical listings**: TradeMe has been operating longer and accumulated more locality names from seller submissions
2. **User-generated data**: TradeMe likely accepts custom suburb names from sellers
3. **Rural coverage**: TradeMe may have better coverage of small rural localities
4. **Legacy names**: TradeMe preserves historical suburb names that may no longer be actively marketed

### Naming conventions differ slightly:
- RealEstate.co.nz uses "Central" suffix (e.g., "Rotorua Central")
- Both use similar district naming (Auckland City, Manukau City, etc.)
- Both follow similar region/district/suburb hierarchy

## Recommendation

**Use TradeMe as primary source** for suburb list because:
1. More comprehensive (2,320 vs 1,890 suburbs)
2. Better coverage of rural and smaller localities
3. 95% overlap means minimal risk of missing major areas
4. Current database already based on TradeMe structure

**Consider adding RealEstate.co.nz unique suburbs** selectively:
- Filter out special cases (airports, hospitals)
- Consider "Central" and "Surrounds" variants if they represent distinct market areas
- Validate with LINZ address data to ensure they correspond to real localities

## Data Sources

- **RealEstate.co.nz**: 1,890 suburbs from XML sitemaps
  - URL: `https://www.realestate.co.nz/{region}-suburbs.xml`
  - Hierarchy: region/district/suburb
  
- **TradeMe**: 2,320 suburbs from TradeMe Property API
  - URL: `https://api.trademe.co.nz/v1/Localities.json`
  - Already loaded in database: `nz_addresses.suburbs`

