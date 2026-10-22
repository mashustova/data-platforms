import argparse
import json
from pathlib import Path
import xml.etree.ElementTree as ET

parser = argparse.ArgumentParser()
parser.add_argument('output_dir', type=Path)
args = parser.parse_args()
properties = json.load(__import__('sys').stdin)
properties['hive-site.xml'] = {
    'hive.metastore.uris': 'thrift://team-17-nn:9083',
    'hive.metastore.warehouse.dir': 'hdfs://team-17-nn:9000/user/hive/warehouse',
}
args.output_dir.mkdir(parents=True, exist_ok=True)
for filename, values in properties.items():
    if filename not in ('core-site.xml', 'hdfs-site.xml', 'yarn-site.xml', 'hive-site.xml'):
        raise SystemExit('Unexpected configuration filename')
    root = ET.Element('configuration')
    for name, value in sorted(values.items()):
        prop = ET.SubElement(root, 'property')
        ET.SubElement(prop, 'name').text = name
        ET.SubElement(prop, 'value').text = value
    ET.indent(root, space='  ')
    ET.ElementTree(root).write(args.output_dir / filename, encoding='utf-8', xml_declaration=True)
