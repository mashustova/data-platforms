import json
from pathlib import Path
import sys
import xml.etree.ElementTree as ET

root = Path(sys.argv[1])
allowed = {
    'core-site.xml': {'fs.defaultFS', 'io.file.buffer.size'},
    'hdfs-site.xml': {'dfs.replication', 'dfs.client.use.datanode.hostname'},
    'yarn-site.xml': {'yarn.resourcemanager.hostname', 'yarn.resourcemanager.address',
                      'yarn.resourcemanager.scheduler.address', 'yarn.resourcemanager.webapp.address',
                      'yarn.resourcemanager.webapp.https.address'},
}
result = {}
for filename, keys in allowed.items():
    properties = ET.parse(root / filename).getroot().findall('property')
    result[filename] = {p.findtext('name'): p.findtext('value', '').strip()
                        for p in properties if p.findtext('name') in keys}
if result['core-site.xml'].get('fs.defaultFS') not in ('hdfs://team-17-nn:9000', 'hdfs://10.17.0.11:9000'):
    raise SystemExit('Unexpected fs.defaultFS; inspect the cluster before copying configs')
if not ({'yarn.resourcemanager.hostname', 'yarn.resourcemanager.address'} & result['yarn-site.xml'].keys()):
    raise SystemExit('No ResourceManager endpoint in the actual cluster configuration')
print(json.dumps(result))
