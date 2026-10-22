import json
from pathlib import Path
import sys
from urllib.parse import unquote, urlsplit

expected, uri, actual_uri, directories = sys.argv[1:]
if actual_uri != uri:
    raise SystemExit('Unexpected fs.defaultFS; no writes allowed')
checked = []
for directory in directories.split(','):
    parsed = urlsplit(directory)
    if parsed.scheme not in ('', 'file') or parsed.netloc:
        raise SystemExit('Expected local NameNode metadata directories')
    path = Path(unquote(parsed.path)).resolve()
    if not path.is_relative_to('/data/hdfs'):
        raise SystemExit('NameNode metadata is outside the expected /data/hdfs tree')
    version = path / 'current' / 'VERSION'
    props = dict(line.split('=', 1) for line in version.read_text().splitlines() if '=' in line and not line.startswith('#'))
    if props.get('clusterID') != expected or props.get('storageType') != 'NAME_NODE':
        raise SystemExit('Unexpected HDFS cluster identity; no writes allowed')
    checked.append(str(version))
print(json.dumps({'cluster_id': expected, 'name_node_version_files': checked, 'fs_defaultFS': actual_uri}))
