#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"
require_edge
for node in "${NODES[@]}"; do
  on_node "$node" sudo -n python3 - "${NODES[@]}" "${NODE_IPS[@]}" <<'PY'
import datetime
import pathlib
import shutil
import sys

hosts = sys.argv[1:4]
ips = sys.argv[4:7]
aliases = {alias for host in hosts for alias in (host, host + '.hse.c.mws')}
path = pathlib.Path('/etc/hosts')
original = path.read_text()
lines = []
for line in original.splitlines():
    body, marker, comment = line.partition('#')
    fields = body.split()
    if len(fields) > 1 and aliases.intersection(fields[1:]):
        remaining = [name for name in fields[1:] if name not in aliases]
        if remaining:
            lines.append(fields[0] + '\t' + ' '.join(remaining) + (' #' + comment if marker else ''))
        elif marker:
            lines.append('#' + comment)
    else:
        lines.append(line)
for host, ip in zip(hosts, ips):
    lines.append(f'{ip}\t{host} {host}.hse.c.mws')
updated = '\n'.join(lines) + '\n'
if updated != original:
    stamp = datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')
    shutil.copy2(path, f'/etc/hosts.before-hw2.{stamp}')
    path.write_text(updated)
PY
done
