import argparse
import hashlib
import json
from pathlib import Path


def digest(path):
    value = hashlib.sha256()
    with path.open('rb') as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            value.update(chunk)
    return value.hexdigest()


parser = argparse.ArgumentParser()
parser.add_argument('spark_home', type=Path)
parser.add_argument('runtime_dir', type=Path)
parser.add_argument('--record', action='store_true')
parser.add_argument('--installed-root', type=Path)
args = parser.parse_args()
hive_dir = args.runtime_dir / 'hms-4.1.0-client'
manifest = json.loads((hive_dir / 'hive-jars-manifest.json').read_text())
assert manifest['hive_version'] == '4.1.0'
assert len(manifest['jars']) > 4
actual_names = {p.name for p in hive_dir.glob('*.jar')}
assert actual_names == {jar['name'] for jar in manifest['jars']}, 'Unexpected/missing Hive jar'
for jar in manifest['jars']:
    assert Path(jar['name']).name == jar['name']
    path = hive_dir / jar['name']
    assert path.stat().st_size == jar['bytes'] and digest(path) == jar['sha256'], jar['name']
hadoop = []
for artifact in ('hadoop-client-api', 'hadoop-client-runtime'):
    matches = list((args.spark_home / 'jars').glob(artifact + '-3.4.*.jar'))
    assert len(matches) == 1, 'Expected one Spark-bundled Hadoop 3.4 client artifact: ' + artifact
    path = matches[0]
    hadoop.append({'path': str(path), 'bytes': path.stat().st_size, 'sha256': digest(path)})
installed_root = args.installed_root or args.runtime_dir
classpath = ','.join([(installed_root / 'hms-4.1.0-client').as_uri() + '/*.jar'] + [Path(p['path']).as_uri() for p in hadoop])
record = {'spark_version': '4.1.0', 'hive_metastore_version': '4.1.0', 'hive_source_manifest': manifest,
          'hadoop_client_jars': hadoop, 'isolated_hive_client_classpath': classpath}
if args.record:
    (args.runtime_dir / 'runtime-manifest.json').write_text(json.dumps(record, indent=2) + '\n')
    (args.runtime_dir / 'hive-client-classpath.txt').write_text(classpath + '\n')
else:
    previous = json.loads((args.runtime_dir / 'runtime-manifest.json').read_text())
    assert previous == record, 'Runtime differs from installation manifest'
print(classpath)
