#!/usr/bin/env python3
"""
Fetch centroids from OpenStreetMap Nominatim API for suburbs without centroids.
Respects rate limiting (1 request per second) and transforms coordinates to NZTM2000.
"""

import sys
import time
import json
import urllib.request
import urllib.parse
import psycopg2
from datetime import datetime

# Database configuration
DB_CONFIG = {
    'host': 'localhost',
    'port': 5432,
    'database': 'nz_addresses_db',
    'user': 'postgres',
    'password': 'postgres'
}

# Nominatim API configuration
NOMINATIM_URL = 'https://nominatim.openstreetmap.org/search'
USER_AGENT = 'NZ-Addresses-ETL/1.0'
RATE_LIMIT_DELAY = 1.1  # Seconds between requests (slightly over 1s to be safe)

def log(message):
    """Print timestamped log message."""
    print(f"[{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}] {message}", flush=True)

def fetch_osm_centroid(suburb_name, district_name):
    """
    Query Nominatim API for suburb centroid.
    Returns (lat, lon) tuple or None if not found.
    """
    # Build search query
    query = f"{suburb_name}, {district_name}, New Zealand"
    
    params = {
        'q': query,
        'format': 'json',
        'limit': 1,
        'addressdetails': 1
    }
    
    url = f"{NOMINATIM_URL}?{urllib.parse.urlencode(params)}"
    
    try:
        req = urllib.request.Request(url, headers={'User-Agent': USER_AGENT})
        with urllib.request.urlopen(req, timeout=10) as response:
            data = json.loads(response.read().decode('utf-8'))
            
            if data and len(data) > 0:
                result = data[0]
                lat = float(result['lat'])
                lon = float(result['lon'])
                return (lat, lon)
            else:
                return None
    except Exception as e:
        log(f"  ⚠ Error fetching {suburb_name}: {e}")
        return None

def transform_to_nztm(conn, lat, lon):
    """
    Transform WGS84 coordinates to NZTM2000 using PostGIS.
    Returns EWKT string for Point geometry.
    """
    with conn.cursor() as cur:
        cur.execute("""
            SELECT ST_AsText(
                ST_Transform(
                    ST_SetSRID(ST_MakePoint(%s, %s), 4326),
                    2193
                )
            )
        """, (lon, lat))  # Note: ST_MakePoint takes (lon, lat)
        result = cur.fetchone()
        return result[0] if result else None

def update_suburb_centroid(conn, suburb_id, wkt_point):
    """Update suburb centroid with NZTM2000 point geometry."""
    with conn.cursor() as cur:
        cur.execute("""
            UPDATE nz_addresses.suburbs
            SET centroid = ST_GeomFromText(%s, 2193)
            WHERE suburb_id = %s
        """, (wkt_point, suburb_id))
        conn.commit()

def main():
    """Main execution function."""
    log("=" * 60)
    log("FETCHING CENTROIDS FROM OPENSTREETMAP")
    log("=" * 60)
    
    # Connect to database
    try:
        conn = psycopg2.connect(**DB_CONFIG)
        log("✓ Connected to database")
    except Exception as e:
        log(f"✗ Database connection failed: {e}")
        sys.exit(1)
    
    # Get suburbs without centroids
    with conn.cursor() as cur:
        cur.execute("""
            SELECT s.suburb_id, s.name, d.name as district_name
            FROM nz_addresses.suburbs s
            JOIN nz_addresses.districts d ON s.district_id = d.district_id
            WHERE s.centroid IS NULL
            ORDER BY d.name, s.name
        """)
        suburbs = cur.fetchall()
    
    total = len(suburbs)
    log(f"Found {total} suburbs without centroids")
    log(f"Estimated time: ~{int(total * RATE_LIMIT_DELAY / 60)} minutes")
    log("")
    
    # Process each suburb
    successful = 0
    failed = 0
    
    for i, (suburb_id, suburb_name, district_name) in enumerate(suburbs, 1):
        log(f"[{i}/{total}] {suburb_name}, {district_name}")
        
        # Fetch from OSM
        coords = fetch_osm_centroid(suburb_name, district_name)
        
        if coords:
            lat, lon = coords
            log(f"  ✓ Found: {lat:.6f}, {lon:.6f}")
            
            # Transform to NZTM2000
            wkt = transform_to_nztm(conn, lat, lon)
            if wkt:
                # Update database
                update_suburb_centroid(conn, suburb_id, wkt)
                log(f"  ✓ Updated centroid")
                successful += 1
            else:
                log(f"  ✗ Coordinate transformation failed")
                failed += 1
        else:
            log(f"  ✗ Not found in OSM")
            failed += 1
        
        # Rate limiting (except for last item)
        if i < total:
            time.sleep(RATE_LIMIT_DELAY)
    
    # Summary
    log("")
    log("=" * 60)
    log("SUMMARY")
    log("=" * 60)
    log(f"Total processed: {total}")
    log(f"Successful: {successful}")
    log(f"Failed: {failed}")
    log(f"Success rate: {100 * successful / total:.1f}%")
    
    # Final counts
    with conn.cursor() as cur:
        cur.execute("""
            SELECT 
                COUNT(*) FILTER (WHERE centroid IS NOT NULL) as with_centroid,
                COUNT(*) FILTER (WHERE centroid IS NULL) as without_centroid
            FROM nz_addresses.suburbs
        """)
        with_centroid, without_centroid = cur.fetchone()
        log(f"")
        log(f"Final status:")
        log(f"  Suburbs with centroids: {with_centroid}")
        log(f"  Suburbs without centroids: {without_centroid}")
    
    conn.close()
    log("✓ Complete")

if __name__ == '__main__':
    main()
