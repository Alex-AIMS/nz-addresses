#!/bin/bash

# Fetch all realestate.co.nz suburbs from regional sitemaps
# and compare with Market suburb list in database

REGIONS=(
    "auckland"
    "bay-of-plenty"
    "canterbury"
    "central-north-island"
    "central-otago-lakes-district"
    "coromandel"
    "gisborne"
    "hawkes-bay"
    "manawatu-whanganui"
    "marlborough"
    "nelson-bays"
    "northland"
    "otago"
    "southland"
    "taranaki"
    "waikato"
    "wairarapa"
    "wellington"
    "west-coast"
)

# Output file
OUTPUT_FILE="/tmp/realestate_suburbs.csv"
echo "region,district,suburb" > "$OUTPUT_FILE"

echo "Downloading realestate.co.nz suburb listings..."

for region in "${REGIONS[@]}"; do
    echo "  Fetching $region..."
    curl -s "https://www.realestate.co.nz/${region}-suburbs.xml" -H "User-Agent: Mozilla/5.0" | \
        grep -oP 'residential/sale/[^<"]+' | \
        awk -F/ '{if (NF==5) print $3"|"$4"|"$5}' | \
        tr '|' ',' | \
        sort -u >> "$OUTPUT_FILE"
    sleep 0.3  # Be polite to their server
done

# Remove duplicates and sort
sort -u "$OUTPUT_FILE" -o "$OUTPUT_FILE"

TOTAL=$(tail -n +2 "$OUTPUT_FILE" | wc -l)
echo ""
echo "Downloaded $TOTAL unique suburb listings from realestate.co.nz"
echo "Saved to: $OUTPUT_FILE"
echo ""
echo "Sample entries:"
head -20 "$OUTPUT_FILE"
