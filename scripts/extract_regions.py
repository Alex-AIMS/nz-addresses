#!/usr/bin/env python3
"""Extract geographic regions from TradeMe localities JSON"""
import json
import sys

# Load TradeMe data
with open("/home/appuser/data/trademe_localities.json") as f:
    data = json.load(f)

# Extract unique regions with sequential IDs
regions = []
for idx, locality in enumerate(data, start=1):
    region_name = locality["Name"]
    # Skip "All" which isn't a real region
    if region_name == "All":
        continue
    
    # Map to stats-like ID format
    region_id = f"R{idx:02d}"
    regions.append({"id": region_id, "name": region_name})

# Write CSV
with open("/tmp/regions_from_trademe.csv", "w") as f:
    f.write("region_id,name\n")
    for region in sorted(regions, key=lambda x: x["name"]):
        f.write(f'{region["id"]},"{region["name"]}"\n')

print(f"✓ Created {len(regions)} regions from TradeMe data", file=sys.stderr)
