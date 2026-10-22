import hashlib
import io
import json
from pathlib import Path
import sys
import tarfile

lib = Path(sys.argv[1]) / 'lib'
jars = sorted(lib.glob('*.jar'))
for required in ('hive-exec-4.1.0.jar', 'hive-common-4.1.0.jar'):
    if not (lib / required).is_file():
        raise SystemExit('The existing Hive installation is not the expected 4.1.0')
manifest = {'source_node': 'team-17-nn', 'hive_version': '4.1.0', 'source_lib': str(lib), 'jars': []}
with tarfile.open(fileobj=sys.stdout.buffer, mode='w|', dereference=True) as archive:
    for jar in jars:
        digest = hashlib.sha256()
        with jar.open('rb') as stream:
            for chunk in iter(lambda: stream.read(1024 * 1024), b''):
                digest.update(chunk)
        manifest['jars'].append({'name': jar.name, 'bytes': jar.stat().st_size, 'sha256': digest.hexdigest()})
        archive.add(jar, arcname=jar.name, recursive=False)
    content = (json.dumps(manifest, indent=2) + '\n').encode()
    entry = tarfile.TarInfo('hive-jars-manifest.json')
    entry.size = len(content)
    entry.mode = 0o644
    archive.addfile(entry, io.BytesIO(content))
