import argparse
import csv
from collections import defaultdict
from datetime import date
from decimal import Decimal
import json
import re
from pathlib import Path


def totals(rows):
    return {'order_count': len(rows),
            'total_quantity': sum(int(r['quantity']) for r in rows),
            'revenue': str(sum((int(r['quantity']) * Decimal(r['unit_price'])
                               for r in rows), Decimal('0.00')))}


def beeline_data_lines(path):
    fixed = {
        'SLF4J: Class path contains multiple SLF4J bindings.',
        'SLF4J: See http://www.slf4j.org/codes.html#multiple_bindings for an explanation.',
        'Please remove the `packages` attribute from your configuration file.',
        'See https://logging.apache.org/log4j/2.x/faq.html#package-scanning for details.',
    }
    messages = [
        r'The use of package scanning to locate Log4j plugins is deprecated[.]',
        r'(?:Starting|Stopping) configuration org[.]apache[.]logging[.]log4j[.]core[.]config[.][A-Za-z0-9.$]+@[a-fA-F0-9]+[.]{3}',
        r'Configuration org[.]apache[.]logging[.]log4j[.]core[.]config[.][A-Za-z0-9.$]+@[a-fA-F0-9]+ (?:started|stopped)[.]',
        r'Start watching for changes to jar:file:/[^\t]+/hive-beeline-[^/]+[.]jar!/beeline-log4j2[.]properties every [0-9]+ seconds',
    ]
    for number, line in enumerate(path.read_text().splitlines(), 1):
        if line in fixed:
            continue
        if re.fullmatch(r'SLF4J: Found binding in \[jar:file:/[^\t]+!/org/slf4j/impl/StaticLoggerBinder[.]class\]', line):
            continue
        if re.fullmatch(r'SLF4J: Actual binding is of type \[(?:org[.]apache[.]logging[.]slf4j[.]Log4jLoggerFactory|org[.]slf4j[.]impl[.]Reload4jLoggerFactory)\]', line):
            continue
        log = re.fullmatch(r'[0-9]{4}-[0-9]{2}-[0-9]{2}T\S+ main (?:WARN|INFO) (.+)', line)
        if log and any(re.fullmatch(pattern, log.group(1)) for pattern in messages):
            continue
        yield number, line


def main():
    parser = argparse.ArgumentParser(description='Validate fixture using only Python standard library; no cluster calls')
    parser.add_argument('--hive-rows', type=Path)
    parser.add_argument('--hive-partitions', type=Path)
    args = parser.parse_args()
    data = Path(__file__).resolve().parents[1] / 'data'
    expected = json.loads((data / 'expected.json').read_text())
    with (data / 'orders.csv').open(newline='') as stream:
        reader = csv.DictReader(stream)
        assert reader.fieldnames == ['order_id', 'event_date', 'city', 'category', 'quantity', 'unit_price', 'status']
        rows = list(reader)
    assert len(rows) == len({r['order_id'] for r in rows}) == 15
    assert {r['status'] for r in rows} == {'completed', 'cancelled'}
    for row in rows:
        date.fromisoformat(row['event_date'])
        assert int(row['quantity']) >= 0 and Decimal(row['unit_price']) >= 0
    kept = [r for r in rows if r['status'] == 'completed' and int(r['quantity']) > 0]
    assert totals(rows) == expected['source']
    assert totals(kept) == expected['filtered']
    assert [int(r['order_id']) for r in rows if r not in kept] == expected['excluded_order_ids']
    groups = defaultdict(list)
    for row in kept:
        groups[(row['event_date'], row['city'])].append(row)
    actual = [dict(dt=dt, city=city, **totals(group)) for (dt, city), group in sorted(groups.items())]
    assert actual == expected['daily_sales']
    if args.hive_rows:
        hive_rows = []
        for number, line in beeline_data_lines(args.hive_rows):
            fields = next(csv.reader([line], delimiter='\t'))
            if len(fields) != 5:
                raise ValueError(f'Unexpected Hive stdout at line {number}: expected 5 TSV fields')
            dt, city, count, quantity, revenue = fields
            date.fromisoformat(dt)
            if not re.fullmatch(r'[a-z]+', city) or not re.fullmatch(r'[0-9]+', count) or not re.fullmatch(r'[0-9]+', quantity) or not re.fullmatch(r'[0-9]+(?:[.][0-9]{1,2})?', revenue):
                raise ValueError(f'Malformed Hive data at line {number}')
            hive_rows.append(dict(dt=dt, city=city, order_count=int(count),
                                  total_quantity=int(quantity), revenue=f'{Decimal(revenue):.2f}'))
        assert sorted(hive_rows, key=lambda row: (row['dt'], row['city'])) == expected['daily_sales'], 'Hive rows differ from expected data'
    if args.hive_partitions:
        actual_partitions = []
        for number, line in beeline_data_lines(args.hive_partitions):
            if not re.fullmatch(r'dt=[0-9]{4}-[0-9]{2}-[0-9]{2}', line):
                raise ValueError(f'Malformed Hive partition at line {number}')
            date.fromisoformat(line[3:])
            actual_partitions.append(line)
        assert sorted(actual_partitions) == ['dt=' + dt for dt in expected['partitions']]
    print('Fixture verified: 15 input orders, 11 valid orders, 8 groups, revenue 6909.17')
    if args.hive_rows and args.hive_partitions:
        print('Hive rows and all 3 partitions match the fixture')


if __name__ == '__main__':
    main()
