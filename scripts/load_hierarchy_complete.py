#!/usr/bin/env python3
"""
Load complete NZ address hierarchy from TradeMe data:
- Districts with region mapping
- Suburbs with district mapping and major suburb flags
"""
import json
import csv
import sys

def load_hierarchy(trademe_file, districts_output, suburbs_output):
    """Extract districts and suburbs from TradeMe JSON"""
    
    with open(trademe_file, 'r') as f:
        regions_data = json.load(f)
    
    districts = []
    suburbs = []
    
    # Map region names to IDs (must match our loaded regions)
    region_name_to_id = {
        'Northland': 'R01',
        'Auckland': 'R02',
        'Waikato': 'R03',
        'Bay Of Plenty': 'R04',
        'Gisborne': 'R05',
        "Hawke's Bay": 'R06',
        'Taranaki': 'R07',
        'Manawatu / Whanganui': 'R08',
        'Wellington': 'R09',
        'Nelson / Tasman': 'R10',
        'Marlborough': 'R11',
        'West Coast': 'R12',
        'Canterbury': 'R13',
        'Otago': 'R14',
        'Southland': 'R15'
    }
    
    for region in regions_data:
        region_name = region['Name']
        if region_name == 'All':
            continue  # Skip aggregate
        
        region_id = region_name_to_id.get(region_name)
        if not region_id:
            print(f"Warning: Unknown region '{region_name}'", file=sys.stderr)
            continue
        
        # Extract districts
        if 'Districts' in region:
            for district in region['Districts']:
                district_id = f"D{district['DistrictId']:04d}"
                district_name = district['Name']
                
                districts.append({
                    'district_id': district_id,
                    'region_id': region_id,
                    'name': district_name,
                    'display_name': district_name  # Use TradeMe name as display name
                })
                
                # Extract suburbs
                if 'Suburbs' in district:
                    for suburb in district['Suburbs']:
                        suburb_id = f"S{suburb['SuburbId']:05d}"
                        suburb_name = suburb['Name']
                        
                        suburbs.append({
                            'suburb_id': suburb_id,
                            'district_id': district_id,
                            'name': suburb_name,
                            'is_major_suburb': True,  # All TradeMe suburbs are major
                            'population_category': 'high'  # TradeMe curates popular suburbs
                        })
    
    # Write districts CSV
    with open(districts_output, 'w', newline='') as f:
        writer = csv.DictWriter(f, fieldnames=['district_id', 'region_id', 'name', 'display_name'])
        writer.writeheader()
        writer.writerows(districts)
    
    # Write suburbs CSV
    with open(suburbs_output, 'w', newline='') as f:
        writer = csv.DictWriter(f, fieldnames=['suburb_id', 'district_id', 'name', 'is_major_suburb', 'population_category'])
        writer.writeheader()
        writer.writerows(suburbs)
    
    print(f"Extracted {len(districts)} districts and {len(suburbs)} suburbs", file=sys.stderr)
    return len(districts), len(suburbs)

if __name__ == '__main__':
    trademe_file = '/home/appuser/data/trademe_localities.json'
    districts_output = '/tmp/districts.csv'
    suburbs_output = '/tmp/suburbs.csv'
    
    district_count, suburb_count = load_hierarchy(trademe_file, districts_output, suburbs_output)
    print(f"SUCCESS: {district_count} districts, {suburb_count} suburbs")
