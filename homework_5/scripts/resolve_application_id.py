import json
from pathlib import Path
import re
import sys

report, log = map(Path, sys.argv[1:])
value = ''
try:
    data = json.loads(report.read_text())
    if isinstance(data, dict):
        value = data.get('application_id', '')
except (OSError, json.JSONDecodeError):
    pass
try:
    values = set(re.findall(r'(?:Submitted application |APPLICATION_ID=)(application_[0-9]+_[0-9]+)', log.read_text()))
except OSError:
    values = set()
if isinstance(value, str) and re.fullmatch(r'application_[0-9]+_[0-9]+', value):
    values.add(value)
if len(values) == 1:
    print(values.pop())
elif len(values) > 1:
    raise SystemExit('Conflicting YARN application IDs; inspect evidence before cleanup')
