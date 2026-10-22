import json
import sys
import xml.etree.ElementTree as ET

path, metastore_uri, host, database, user = sys.argv[1:]
properties = {item.findtext('name'): item.findtext('value', '').strip() for item in ET.parse(path).getroot().findall('property')}
required = {'hive.metastore.uris': metastore_uri,
            'hive.server2.thrift.port': '10000',
            'javax.jdo.option.ConnectionUserName': user}
defaults = {'hive.server2.thrift.port': '10000'}
for name, expected in required.items():
    if properties.get(name, defaults.get(name)) != expected:
        raise SystemExit(f'Unexpected effective {name}; inspect existing configuration before adoption')
url = properties.get('javax.jdo.option.ConnectionURL', '')
if url not in (f'jdbc:postgresql://localhost:5432/{database}', f'jdbc:postgresql://127.0.0.1:5432/{database}'):
    raise SystemExit('Metastore must use the expected local PostgreSQL database')
if properties.get('hive.server2.thrift.bind.host', host) not in (host, 'team-17-nn', '0.0.0.0'):
    raise SystemExit('Unexpected HiveServer2 bind host')
allowlist = ['hive.metastore.uris', 'hive.server2.thrift.bind.host', 'hive.server2.thrift.port',
             'hive.server2.authentication', 'hive.server2.enable.doAs', 'hive.execution.engine',
             'hive.metastore.warehouse.dir', 'hive.metastore.warehouse.external.dir',
             'javax.jdo.option.ConnectionURL', 'javax.jdo.option.ConnectionUserName']
print(json.dumps({key: properties.get(key, defaults.get(key, '(default)')) for key in allowlist}, indent=2))
