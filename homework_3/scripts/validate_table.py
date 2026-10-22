import json
from pathlib import Path
import sys

path, location = sys.argv[1:]
rows = [[field.strip() for field in line.split('\t')] for line in Path(path).read_text().splitlines()]
properties = {row[0]: row[1] for row in rows if len(row) > 1 and row[0]}
expected = {'order_id': 'bigint', 'city': 'string', 'category': 'string', 'quantity': 'int',
            'unit_price': 'decimal(10,2)', 'status': 'string', 'dt': 'string'}
for column, dtype in expected.items():
    if properties.get(column) != dtype:
        raise SystemExit(f'Unexpected schema for {column}; no partition overwrite allowed')
if properties.get('Location:') != location:
    raise SystemExit('Table location differs from personal namespace; no partition overwrite allowed')
if properties.get('Table Type:') != 'EXTERNAL_TABLE':
    raise SystemExit('Expected an external homework table')
purge = next((row[i+1] for row in rows for i, item in enumerate(row[:-1]) if item == 'external.table.purge'), None)
if purge is None or purge.lower() != 'false':
    raise SystemExit('Expected external.table.purge=false')
print(json.dumps({'database': 'dp_mashustova_hw3', 'table': 'orders', 'location': location,
                  'table_type': 'EXTERNAL_TABLE', 'external_table_purge': False, 'schema': expected}, indent=2))
