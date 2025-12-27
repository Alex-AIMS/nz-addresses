# NZ Addresses Data Comparison: Our Data vs TradeMe REST Service

## Executive Summary

**CRITICAL FINDING**: Our loaded hierarchy data is **FUNDAMENTALLY INCOMPATIBLE** with real estate/property market applications like TradeMe.

- **Our Data Source**: Stats NZ MCON2023 (Māori Electoral Constituencies) + TALB2023 (Territorial Authorities/Local Boards)
- **TradeMe Data**: Geographic regions and market-recognized district/suburb names
- **Impact**: Cascading dropdown filtering won't match user expectations for property searches

---

## Region-Level Comparison

### Our Regions (22 Māori Constituencies)
```
0101 - Te Raki Māori Constituency
0199 - Area Outside Māori Constituency
0201 - Nga Hau e Wha Māori Constituency
0299 - Area Outside Māori Constituency
0301 - Nga Tai ki Uta Māori Constituency
0302 - Nga Hau e Wha Māori Constituency
0399 - Area Outside Māori Constituency
0401 - Maueo Māori Constituency
0402 - Okurei Māori Constituency
0403 - Kohi Māori Constituency
0499 - Area Outside Māori Constituency
0601 - Māui ki te Raki Māori Constituency
0602 - Māui ki te Tonga Māori Constituency
0699 - Area Outside Māori Constituency
0701 - Taranaki Māori Constituency
0799 - Area Outside Māori Constituency
0801 - Raki Māori Constituency
0802 - Tonga Māori Constituency
0899 - Area Outside Māori Constituency
1699 - Area Outside Māori Constituency
9999 - Area Outside Māori Constituency
```

**Total**: 22 regions (11 named Māori constituencies + 11 "Area Outside" entries)

### TradeMe Regions (16 Geographic Regions)
```
 1. Northland
 2. Auckland
 3. Waikato
 4. Bay Of Plenty
 5. Gisborne
 6. Hawke's Bay
 7. Taranaki
 8. Manawatu / Whanganui
 9. Wellington
10. Nelson / Tasman
11. Marlborough
12. West Coast
13. Canterbury
14. Otago
15. Southland
16. All (special category)
```

**Total**: 16 regions (15 real geographic regions + 1 "All" category)

### Key Differences at Region Level

| Aspect | Our Data | TradeMe |
|--------|----------|---------|
| **Purpose** | Electoral boundaries for Māori representation | Geographic market regions |
| **Count** | 22 | 16 |
| **Structure** | Māori constituencies (voting districts) | Traditional NZ regions (North Island to South Island) |
| **User Recognition** | Low (unfamiliar to most users) | High (well-known region names) |
| **Example** | "Te Raki Māori Constituency" | "Northland" |

**Impact**: Users searching for properties in "Auckland" won't find a region called "Auckland" in our data. Instead, they'd see "Nga Hau e Wha Māori Constituency" or "Area Outside Māori Constituency".

---

## District-Level Comparison

### Our Districts (88 Administrative Units)

**Structure**:
- Territorial Authorities (67): e.g., "Far North District", "Whangarei District", "Christchurch City"
- Auckland Local Board Areas (21): e.g., "Albert-Eden Local Board Area", "Orakei Local Board Area"

**Examples**:
```
00100 - Far North District
00200 - Whangarei District
07608 - Aotea/Great Barrier Local Board Area
07612 - Albert-Eden Local Board Area
07613 - Orakei Local Board Area
```

**Total**: 88 districts

### TradeMe Districts (79 Market Districts)

**Structure**:
- Organized under 16 geographic regions
- Uses legacy city names (pre-2010 Auckland Super City amalgamation)
- Market-recognized district names

**Auckland Examples**:
```
- Auckland City (61 suburbs)
- Manukau City (63 suburbs)
- North Shore City (51 suburbs)
- Waitakere City (46 suburbs)
- Papakura (10 suburbs)
- Rodney (77 suburbs)
- Franklin (39 suburbs)
- Waiheke Island (25 suburbs)
- Hauraki Gulf Islands (3 suburbs)
```

**Total**: 79 districts

### Key Differences at District Level

| Aspect | Our Data | TradeMe |
|--------|----------|---------|
| **Count** | 88 | 79 |
| **Auckland Structure** | 21 Local Board Areas | 9 legacy city names |
| **Administrative Status** | Current 2023 boundaries | Pre-2010 city boundaries (familiar to market) |
| **User Expectation** | "Albert-Eden Local Board Area" | "Auckland City" |
| **Recognition** | Low (government admin names) | High (legacy city names) |

**Impact**: Users looking for properties in "Auckland City" won't find it. Instead, they'd need to know which local board area (e.g., "Albert-Eden", "Orakei") to select.

---

## Suburb-Level Comparison

### Our Suburbs (6,562 Localities)

**Source**: LINZ NZ Localities (suburbs_localities.csv)
- Includes ALL official localities from Land Information New Zealand
- Very granular - includes small settlements, rural areas
- Government-defined boundaries

**Examples**:
```
1 - Kaitaia
2 - Awanui
3 - Paparore
4 - Broadwood
5 - Herekino
6 - Kohukohu
... (6,556 more)
```

**Total**: 6,562 suburbs

### TradeMe Suburbs (2,320 Market Suburbs)

**Source**: Curated market suburbs
- Property-market relevant suburbs only
- Combines small localities into recognized suburb names
- Focuses on populated areas with property activity

**Auckland City Examples**:
```
- Arch Hill
- Avondale
- Balmoral
- Blockhouse Bay
- City Centre
- Eden Terrace
- Ellerslie
- Epsom
- Freemans Bay
- Glen Innes
... (51 more in Auckland City)
```

**Total**: 2,320 suburbs

### Key Differences at Suburb Level

| Aspect | Our Data | TradeMe |
|--------|----------|---------|
| **Count** | 6,562 | 2,320 |
| **Difference** | +4,242 more suburbs | Curated subset |
| **Coverage** | Every LINZ locality | Market-relevant suburbs |
| **Granularity** | Very granular (includes tiny settlements) | Aggregated to market-recognized names |
| **Rural Areas** | Extensive coverage | Limited to areas with property activity |

**Impact**: Our data is **much more granular** than TradeMe's. This could be beneficial (more precise location data) or overwhelming (too many options in dropdown).

---

## Hierarchy Comparison Summary

```
OUR DATA HIERARCHY:
Region (22 Māori Constituencies)
  └── District (88 Territorial Authorities + Local Boards)
        └── Suburb (6,562 LINZ Localities)

TRADEME HIERARCHY:
Region (16 Geographic Regions)
  └── District (79 Market Districts)
        └── Suburb (2,320 Market Suburbs)
```

### Counts Table

| Level | Our Data | TradeMe | Difference |
|-------|----------|---------|------------|
| **Regions** | 22 | 16 | +6 (but different structure) |
| **Districts** | 88 | 79 | +9 |
| **Suburbs** | 6,562 | 2,320 | +4,242 |

---

## Critical Issues Identified

### 1. **Region Structure Mismatch** (CRITICAL)
- **Problem**: We use Māori Electoral Constituencies, TradeMe uses geographic regions
- **Example**: No "Auckland" region in our data, instead "Nga Hau e Wha Māori Constituency"
- **Impact**: Users cannot find familiar region names
- **Severity**: ⚠️ **BLOCKER** for real estate applications

### 2. **Auckland District Fragmentation** (HIGH)
- **Problem**: Auckland split into 21 local board areas vs. 9 legacy cities
- **Example**: Users expect "Auckland City", we have "Albert-Eden Local Board Area"
- **Impact**: Confusing user experience, low adoption
- **Severity**: ⚠️ **HIGH** - Major usability issue

### 3. **Suburb Granularity** (MEDIUM)
- **Problem**: 6,562 suburbs vs. 2,320 (nearly 3x more)
- **Example**: Tiny rural settlements vs. curated market suburbs
- **Impact**: Overwhelming dropdown options, performance concerns
- **Severity**: ⚠️ **MEDIUM** - Can be mitigated with search/filtering

### 4. **Naming Conventions** (MEDIUM)
- **Problem**: Government administrative names vs. market-familiar names
- **Example**: "Territorial Authority" vs. "City", "Local Board" vs. suburb clusters
- **Impact**: Lower discoverability, user confusion
- **Severity**: ⚠️ **MEDIUM** - UX issue

---

## Recommendations

### Option 1: **Reload with Correct Datasets** ✅ RECOMMENDED
**Use Stats NZ Regional Council boundaries instead of Māori Constituencies**

**Action Items**:
1. Download Stats NZ **REGC2023** (Regional Councils 2023) instead of MCON2023
   - URL: https://datafinder.stats.govt.nz/layer/111183-regional-council-2023-generalised/
   - This gives 16 geographic regions matching TradeMe structure

2. Keep TALB2023 districts but **add mapping table** to legacy city names:
   ```sql
   CREATE TABLE district_aliases (
     district_id VARCHAR(10),
     market_name VARCHAR(200),  -- e.g., "Auckland City", "Manukau City"
     official_name VARCHAR(200)  -- e.g., "Albert-Eden Local Board Area"
   );
   ```

3. Keep LINZ suburbs (6,562) but **add popularity/filtering**:
   ```sql
   ALTER TABLE suburbs ADD COLUMN is_major_suburb BOOLEAN DEFAULT FALSE;
   ALTER TABLE suburbs ADD COLUMN population_category VARCHAR(20);
   ```

4. Rebuild hierarchy with spatial joins using corrected region dataset

**Benefits**:
- ✅ Users find familiar region names (Auckland, Wellington, Canterbury)
- ✅ Cascading dropdowns match market expectations
- ✅ Still maintain government-accurate boundaries
- ✅ Can offer both "market view" and "administrative view"

**Effort**: Medium (3-4 hours to download, reload, test)

---

### Option 2: **Add Mapping Layer** (Alternative)
Keep existing data but add translation tables:

```sql
CREATE TABLE region_market_mapping (
  maori_constituency_id VARCHAR(10),
  geographic_region_name VARCHAR(100),
  geographic_region_id INT
);

-- Example:
INSERT INTO region_market_mapping VALUES
  ('0101', 'Northland', 9),
  ('0201', 'Auckland', 1),
  ('0801', 'Canterbury', 3);
```

**Benefits**:
- ✅ Keep existing loaded data
- ✅ Add market-facing view
- ✅ Maintain electoral data for potential future use

**Drawbacks**:
- ❌ Complex mapping required (many-to-many relationships)
- ❌ Spatial boundaries won't align perfectly
- ❌ More maintenance overhead

**Effort**: Medium-High (complex mapping logic)

---

### Option 3: **Hybrid Approach** (Most Flexible)
Maintain **both** hierarchies side-by-side:

```sql
-- Government hierarchy
regions_govt (electoral constituencies)
districts_govt (territorial authorities + local boards)
suburbs_govt (all LINZ localities)

-- Market hierarchy
regions_market (geographic regions)
districts_market (legacy city names)
suburbs_market (curated market suburbs)

-- Cross-reference
locality_mapping (govt_suburb_id, market_suburb_id)
```

**Benefits**:
- ✅ Support both government admin and market views
- ✅ Maximum flexibility for different use cases
- ✅ Accurate for official purposes + user-friendly for property

**Drawbacks**:
- ❌ Double the storage
- ❌ More complex queries
- ❌ Maintenance burden

**Effort**: High (significant refactoring)

---

## Conclusion

**Current Status**: ❌ **NOT SUITABLE** for real estate/property applications

**Root Cause**: Loaded Māori Electoral Constituencies (MCON2023) instead of Geographic Regions (REGC2023)

**Immediate Action Required**: 
1. **Reload region data** with Stats NZ REGC2023 (Regional Councils) dataset
2. **Add district alias table** mapping local boards to legacy city names
3. **Flag major suburbs** to improve dropdown usability
4. **Test** cascading dropdowns match TradeMe structure

**Expected Outcome After Fix**:
- ✅ Users see "Auckland", "Wellington", "Canterbury" (familiar names)
- ✅ Districts show "Auckland City", "Manukau City" (market-recognized names)
- ✅ Suburb counts remain comprehensive (6,562 vs TradeMe's 2,320)
- ✅ Hierarchy navigation matches user expectations

**Time to Fix**: 3-4 hours (download datasets, reload, rebuild views, test)

---

## Data Source Links

### Correct Datasets to Use:
1. **Regions**: Stats NZ Regional Council 2023 (REGC2023)
   - https://datafinder.stats.govt.nz/layer/111183-regional-council-2023-generalised/
   - 16 geographic regions (matches TradeMe structure)

2. **Districts**: Keep TALB2023 but add aliases
   - Current: https://datafinder.stats.govt.nz/layer/111197-territorial-authority-local-board-2023-generalised/
   - Add mapping to legacy city names

3. **Suburbs**: Keep LINZ Localities
   - Current: https://data.linz.govt.nz/layer/105689-nz-localities/
   - Add major_suburb flag and filtering

### TradeMe Reference:
- API: https://api.trademe.co.nz/v1/Localities.json
- Documentation: https://developer.trademe.co.nz/api-reference/

---

**Generated**: 2025-01-14
**Data Comparison**: NZ Addresses Database vs TradeMe REST Service
