#!/bin/bash
set -e

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

# Function to expand abbreviations in suburb names
expand_abbreviations() {
    local name="$1"
    local expanded="$name"
    
    # Get abbreviations from database and apply them
    while IFS='|' read -r short long; do
        # Match word boundaries to avoid partial replacements
        expanded=$(echo "$expanded" | sed "s/\b$short\b/$long/g")
    done < <(docker exec -u postgres nz-addresses psql -d nz_addresses_db -t -A -F'|' -c "SELECT short_form, long_form FROM nz_addresses.abbreviations WHERE category = 'prefix' OR category = 'location' ORDER BY LENGTH(short_form) DESC")
    
    echo "$expanded"
}

log "========================================="
log "FETCHING CENTROIDS FROM OPENSTREETMAP"
log "========================================="

# Get suburbs without centroids
SUBURBS_FILE="/tmp/suburbs_missing_centroids.csv"
docker exec -u postgres nz-addresses psql -d nz_addresses_db -t -A -F'|' -c "
    SELECT s.suburb_id, s.name, d.name as district_name
    FROM nz_addresses.suburbs s
    JOIN nz_addresses.districts d ON s.district_id = d.district_id
    WHERE s.centroid IS NULL
    ORDER BY d.name, s.name
" > "$SUBURBS_FILE"

TOTAL=$(wc -l < "$SUBURBS_FILE")
log "Found $TOTAL suburbs without centroids"
log "Estimated time: ~$((TOTAL * 2 / 60)) minutes (with 1.2s rate limiting)"
log ""

SUCCESSFUL=0
FAILED=0
COUNTER=0

# Process each suburb
while IFS='|' read -r suburb_id suburb_name district_name; do
    COUNTER=$((COUNTER + 1))
    log "[$COUNTER/$TOTAL] $suburb_name, $district_name"
    
    LAT=""
    LON=""
    FOUND_IN_LINZ=false
    
    # FIRST: Try to get centroid from LINZ data (original name)
    # Escape single quotes for SQL
    SUBURB_NAME_ESCAPED=$(echo "$suburb_name" | sed "s/'/''/g")
    LINZ_RESULT=$(docker exec -u postgres nz-addresses psql -d nz_addresses_db -t -A -c "
        SELECT ST_Y(ST_Transform(ST_Centroid(geom), 4326)), ST_X(ST_Transform(ST_Centroid(geom), 4326))
        FROM nz_addresses.addresses
        WHERE LOWER(TRIM(suburb_locality)) = LOWER('$SUBURB_NAME_ESCAPED')
        AND geom IS NOT NULL
        LIMIT 1
    ")
    
    if [ -n "$LINZ_RESULT" ] && [ "$LINZ_RESULT" != "|" ]; then
        LAT=$(echo "$LINZ_RESULT" | cut -d'|' -f1)
        LON=$(echo "$LINZ_RESULT" | cut -d'|' -f2)
        if [ -n "$LAT" ] && [ -n "$LON" ]; then
            log "  ✓ Found in LINZ data: $LAT, $LON"
            FOUND_IN_LINZ=true
        fi
    fi
    
    # If not found in LINZ, try with expanded abbreviations
    if [ "$FOUND_IN_LINZ" = false ]; then
        EXPANDED_NAME=$(expand_abbreviations "$suburb_name")
        if [ "$EXPANDED_NAME" != "$suburb_name" ]; then
            log "  → Trying LINZ with expanded: $EXPANDED_NAME"
            EXPANDED_NAME_ESCAPED=$(echo "$EXPANDED_NAME" | sed "s/'/''/g")
            LINZ_RESULT=$(docker exec -u postgres nz-addresses psql -d nz_addresses_db -t -A -c "
                SELECT ST_Y(ST_Transform(ST_Centroid(geom), 4326)), ST_X(ST_Transform(ST_Centroid(geom), 4326))
                FROM nz_addresses.addresses
                WHERE LOWER(TRIM(suburb_locality)) = LOWER('$EXPANDED_NAME_ESCAPED')
                AND geom IS NOT NULL
                LIMIT 1
            ")
            
            if [ -n "$LINZ_RESULT" ] && [ "$LINZ_RESULT" != "|" ]; then
                LAT=$(echo "$LINZ_RESULT" | cut -d'|' -f1)
                LON=$(echo "$LINZ_RESULT" | cut -d'|' -f2)
                if [ -n "$LAT" ] && [ -n "$LON" ]; then
                    log "  ✓ Found in LINZ data (expanded): $LAT, $LON"
                    FOUND_IN_LINZ=true
                fi
            fi
        fi
    fi
    
    # If not in LINZ, proceed to OpenStreetMap
    if [ "$FOUND_IN_LINZ" = false ]; then
        # Special case: "City Centre" suburbs - just use district name
        if [ "$suburb_name" == "City Centre" ]; then
            log "  → City Centre detected, querying OSM with district name only"
            QUERY=$(echo "$district_name, New Zealand" | sed 's/ /%20/g' | sed 's/,/%2C/g')
            RESPONSE=$(curl -s -A "NZ-Addresses-ETL/1.0" \
                "https://nominatim.openstreetmap.org/search?q=$QUERY&format=json&limit=1")
            
            LAT=$(echo "$RESPONSE" | grep -o '"lat":"[^"]*"' | head -1 | cut -d'"' -f4)
            LON=$(echo "$RESPONSE" | grep -o '"lon":"[^"]*"' | head -1 | cut -d'"' -f4)
        else
            # Try original name with OSM
            log "  → Querying OSM"
            QUERY=$(echo "$suburb_name, $district_name, New Zealand" | sed 's/ /%20/g' | sed 's/,/%2C/g')
            RESPONSE=$(curl -s -A "NZ-Addresses-ETL/1.0" \
                "https://nominatim.openstreetmap.org/search?q=$QUERY&format=json&limit=1")
            
            LAT=$(echo "$RESPONSE" | grep -o '"lat":"[^"]*"' | head -1 | cut -d'"' -f4)
            LON=$(echo "$RESPONSE" | grep -o '"lon":"[^"]*"' | head -1 | cut -d'"' -f4)
        fi
    fi
    
    # If not found in OSM with original name, try with expanded abbreviations
    if [ "$FOUND_IN_LINZ" = false ] && [ "$suburb_name" != "City Centre" ] && { [ -z "$LAT" ] || [ -z "$LON" ]; }; then
        EXPANDED_NAME=$(expand_abbreviations "$suburb_name")
        if [ "$EXPANDED_NAME" != "$suburb_name" ]; then
            log "  → Trying OSM with expanded: $EXPANDED_NAME"
            sleep 1.2  # Rate limit for second attempt
            QUERY=$(echo "$EXPANDED_NAME, $district_name, New Zealand" | sed 's/ /%20/g' | sed 's/,/%2C/g')
            RESPONSE=$(curl -s -A "NZ-Addresses-ETL/1.0" \
                "https://nominatim.openstreetmap.org/search?q=$QUERY&format=json&limit=1")
            
            LAT=$(echo "$RESPONSE" | grep -o '"lat":"[^"]*"' | head -1 | cut -d'"' -f4)
            LON=$(echo "$RESPONSE" | grep -o '"lon":"[^"]*"' | head -1 | cut -d'"' -f4)
        fi
    fi
    
    # If still not found, try removing "City" from district name
    if [ -z "$LAT" ] || [ -z "$LON" ]; then
        SIMPLIFIED_DISTRICT=$(echo "$district_name" | sed 's/ City$//')
        if [ "$SIMPLIFIED_DISTRICT" != "$district_name" ]; then
            log "  → Trying simplified district: $SIMPLIFIED_DISTRICT"
            sleep 1.2
            # Try with expanded name if available, otherwise original
            SEARCH_NAME="${EXPANDED_NAME:-$suburb_name}"
            QUERY=$(echo "$SEARCH_NAME, $SIMPLIFIED_DISTRICT, New Zealand" | sed 's/ /%20/g' | sed 's/,/%2C/g')
            RESPONSE=$(curl -s -A "NZ-Addresses-ETL/1.0" \
                "https://nominatim.openstreetmap.org/search?q=$QUERY&format=json&limit=1")
            
            LAT=$(echo "$RESPONSE" | grep -o '"lat":"[^"]*"' | head -1 | cut -d'"' -f4)
            LON=$(echo "$RESPONSE" | grep -o '"lon":"[^"]*"' | head -1 | cut -d'"' -f4)
        fi
    fi
    
    # If still not found and district contains "Island", try without "Island"
    if [ -z "$LAT" ] || [ -z "$LON" ]; then
        if [[ "$district_name" == *" Island" ]]; then
            NO_ISLAND_DISTRICT=$(echo "$district_name" | sed 's/ Island$//')
            log "  → Trying without 'Island': $NO_ISLAND_DISTRICT"
            sleep 1.2
            SEARCH_NAME="${EXPANDED_NAME:-$suburb_name}"
            QUERY=$(echo "$SEARCH_NAME, $NO_ISLAND_DISTRICT, New Zealand" | sed 's/ /%20/g' | sed 's/,/%2C/g')
            RESPONSE=$(curl -s -A "NZ-Addresses-ETL/1.0" \
                "https://nominatim.openstreetmap.org/search?q=$QUERY&format=json&limit=1")
            
            LAT=$(echo "$RESPONSE" | grep -o '"lat":"[^"]*"' | head -1 | cut -d'"' -f4)
            LON=$(echo "$RESPONSE" | grep -o '"lon":"[^"]*"' | head -1 | cut -d'"' -f4)
        fi
    fi
    
    # If still not found and district is "Manukau City", try with "Auckland"
    if [ -z "$LAT" ] || [ -z "$LON" ]; then
        if [[ "$district_name" == "Manukau City" ]] || [[ "$district_name" == "North Shore City" ]] || [[ "$district_name" == "Waitakere City" ]] || [[ "$district_name" == "Rodney" ]] || [[ "$district_name" == "Franklin" ]]; then
            log "  → Trying with Auckland instead of $district_name"
            sleep 1.2
            SEARCH_NAME="${EXPANDED_NAME:-$suburb_name}"
            QUERY=$(echo "$SEARCH_NAME, Auckland, New Zealand" | sed 's/ /%20/g' | sed 's/,/%2C/g')
            RESPONSE=$(curl -s -A "NZ-Addresses-ETL/1.0" \
                "https://nominatim.openstreetmap.org/search?q=$QUERY&format=json&limit=1")
            
            LAT=$(echo "$RESPONSE" | grep -o '"lat":"[^"]*"' | head -1 | cut -d'"' -f4)
            LON=$(echo "$RESPONSE" | grep -o '"lon":"[^"]*"' | head -1 | cut -d'"' -f4)
        fi
    fi
    
    # If still not found, try with region instead of district
    if [ -z "$LAT" ] || [ -z "$LON" ]; then
        REGION=$(docker exec -u postgres nz-addresses psql -d nz_addresses_db -t -A -c "
            SELECT r.name
            FROM nz_addresses.suburbs s
            JOIN nz_addresses.districts d ON s.district_id = d.district_id
            JOIN nz_addresses.regions r ON d.region_id = r.region_id
            WHERE s.suburb_id = '$suburb_id'
        " | tr -d ' \n\r')
        
        if [ -n "$REGION" ] && [ "$REGION" != "$district_name" ]; then
            log "  → Trying with region: $REGION"
            sleep 1.2
            SEARCH_NAME="${EXPANDED_NAME:-$suburb_name}"
            QUERY=$(echo "$SEARCH_NAME, $REGION, New Zealand" | sed 's/ /%20/g' | sed 's/,/%2C/g')
            RESPONSE=$(curl -s -A "NZ-Addresses-ETL/1.0" \
                "https://nominatim.openstreetmap.org/search?q=$QUERY&format=json&limit=1")
            
            LAT=$(echo "$RESPONSE" | grep -o '"lat":"[^"]*"' | head -1 | cut -d'"' -f4)
            LON=$(echo "$RESPONSE" | grep -o '"lon":"[^"]*"' | head -1 | cut -d'"' -f4)
        fi
    fi
    
    if [ -n "$LAT" ] && [ -n "$LON" ]; then
        log "  ✓ Found: $LAT, $LON"
        
        # Transform and update in database
        docker exec -u postgres nz-addresses psql -d nz_addresses_db -c "
            UPDATE nz_addresses.suburbs
            SET centroid = ST_Transform(
                ST_SetSRID(ST_MakePoint($LON, $LAT), 4326),
                2193
            )
            WHERE suburb_id = '$suburb_id';
        " > /dev/null 2>&1
        
        if [ $? -eq 0 ]; then
            log "  ✓ Updated centroid"
            SUCCESSFUL=$((SUCCESSFUL + 1))
        else
            log "  ✗ Database update failed"
            FAILED=$((FAILED + 1))
        fi
    else
        log "  ✗ Not found in OSM"
        FAILED=$((FAILED + 1))
    fi
    
    # Rate limiting (1.2 seconds between requests)
    sleep 1.2
    
done < "$SUBURBS_FILE"

log ""
log "========================================="
log "SUMMARY"
log "========================================="
log "Total processed: $TOTAL"
log "Successful: $SUCCESSFUL"
log "Failed: $FAILED"
log "Success rate: $(awk "BEGIN {printf \"%.1f\", 100*$SUCCESSFUL/$TOTAL}")%"

# Final counts
log ""
log "Final status:"
docker exec -u postgres nz-addresses psql -d nz_addresses_db -t -c "
    SELECT 
        '  Suburbs with centroids: ' || COUNT(*) FILTER (WHERE centroid IS NOT NULL),
        '  Suburbs without centroids: ' || COUNT(*) FILTER (WHERE centroid IS NULL)
    FROM nz_addresses.suburbs
"

log "✓ Complete"
