#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"
require_edge
set_run "${1:?Usage: preflight.sh RUN_ID}"
[[ ! -e "$EVIDENCE_DIR/stage.started" && ! -e "$EVIDENCE_DIR/submission.started" ]] || fail 'This run has already attempted external changes; use check.sh or a new run ID'
mkdir -p "$EVIDENCE_DIR"
rm -f "$EVIDENCE_DIR/preflight.ok"
for command in python3 sudo timeout sha256sum; do
  command -v "$command" >/dev/null || fail "Missing $command"
done
python3 "$HW5_DIR/scripts/validate_fixture.py" > "$EVIDENCE_DIR/fixture.txt"
edge_hadoop test -x "$SPARK_HOME/bin/spark-submit"
edge_hadoop test -x "$JAVA_HOME/bin/java"
edge_hadoop /usr/bin/python3 -c 'import sys; assert sys.version_info >= (3, 10), "Spark requires Python >= 3.10"'
read_classpath > "$EVIDENCE_DIR/client-classpath.txt"
edge_hadoop cat "$SHARED_RUNTIME_DIR/runtime-manifest.json" > "$EVIDENCE_DIR/runtime-manifest.json"
edge_hadoop /usr/bin/python3 - "$HADOOP_CONF_DIR" > "$EVIDENCE_DIR/client-config.json" <<'PY'
import json
from pathlib import Path
import sys
import xml.etree.ElementTree as ET

conf = Path(sys.argv[1])
def properties(name):
    root = ET.parse(conf / name).getroot()
    values = {}
    for prop in root.findall('property'):
        key, value = prop.findtext('name'), prop.findtext('value')
        if key in values:
            raise SystemExit('Duplicate client config property: ' + key)
        values[key] = value
    return values
core, yarn, hive = (properties(name) for name in ('core-site.xml', 'yarn-site.xml', 'hive-site.xml'))
if core.get('fs.defaultFS') not in ('hdfs://team-17-nn:9000', 'hdfs://10.17.0.11:9000'):
    raise SystemExit('Client fs.defaultFS differs from the expected HDFS')
if hive.get('hive.metastore.uris') != 'thrift://team-17-nn:9083':
    raise SystemExit('Client Hive metastore differs from the expected shared HMS')
host = yarn.get('yarn.resourcemanager.hostname')
address = yarn.get('yarn.resourcemanager.address')
if host is None and address is None:
    raise SystemExit('Missing ResourceManager endpoint')
if host is not None and host not in ('team-17-nn', '10.17.0.11'):
    raise SystemExit('Unexpected ResourceManager hostname')
for name, port in [('address', 8032), ('scheduler.address', 8030), ('webapp.address', 8088), ('webapp.https.address', 8090)]:
    key = 'yarn.resourcemanager.' + name
    if key in yarn and yarn[key] not in (f'team-17-nn:{port}', f'10.17.0.11:{port}'):
        raise SystemExit('Unexpected ResourceManager endpoint: ' + key)
print(json.dumps({'fs.defaultFS': core['fs.defaultFS'], 'hive.metastore.uris': hive['hive.metastore.uris'],
                  'resource_manager': {key: value for key, value in yarn.items() if key.startswith('yarn.resourcemanager.')}}, indent=2))
PY
edge_hadoop test ! -e "$JOB_DIR" || fail 'Job directory exists; use a new run ID'
if nn_hdfs dfs -test -e "$RUN_HDFS"; then
  fail 'HDFS run directory exists; use a new run ID'
else
  code=$?
  [[ $code == 1 ]] || fail 'Cannot inspect HDFS run directory'
fi
nn_hdfs dfsadmin -safemode get > "$EVIDENCE_DIR/hdfs-safemode.txt"
grep -Fq 'Safe mode is OFF' "$EVIDENCE_DIR/hdfs-safemode.txt" || fail 'HDFS is in safe mode'
nn_hdfs dfsadmin -report > "$EVIDENCE_DIR/hdfs-report.txt"
nn_hdfs dfs -ls / > "$EVIDENCE_DIR/hdfs-root.txt"
on_node "$NN_HOST" sudo -n -H -u "$HADOOP_USER" python3 - "$NN_HADOOP_HOME" > "$EVIDENCE_DIR/scheduler-resources.json" <<'PY'
import json
from pathlib import Path
import sys
import xml.etree.ElementTree as ET
import zipfile

home = Path(sys.argv[1])
site = {p.findtext('name'): p.findtext('value') for p in ET.parse(home / 'etc/hadoop/yarn-site.xml').getroot().findall('property')}
jars = list((home / 'share/hadoop/yarn').glob('hadoop-yarn-common-*.jar'))
if len(jars) != 1:
    raise SystemExit('Cannot identify the installed Hadoop YARN defaults')
with zipfile.ZipFile(jars[0]) as archive:
    defaults = {p.findtext('name'): p.findtext('value') for p in ET.fromstring(archive.read('yarn-default.xml')).findall('property')}
settings = {}
for suffix in ('minimum-allocation-mb', 'maximum-allocation-mb', 'minimum-allocation-vcores', 'maximum-allocation-vcores'):
    name = 'yarn.scheduler.' + suffix
    source = 'yarn-site.xml' if name in site else str(jars[0]) + '!/yarn-default.xml'
    settings[suffix] = {'value': int(site[name] if name in site else defaults[name]), 'source': source}
if site.get('yarn.resourcemanager.scheduler.class', defaults.get('yarn.resourcemanager.scheduler.class')) != 'org.apache.hadoop.yarn.server.resourcemanager.scheduler.capacity.CapacityScheduler':
    raise SystemExit('Resource check supports the existing CapacityScheduler only')
if any(name.startswith('yarn.resource-types.memory-mb.') or name.startswith('yarn.resource-types.vcores.') for name in site):
    raise SystemExit('Explicit resource-type allocation overrides need review before running')
print(json.dumps(settings, indent=2))
PY
python3 - "$EVIDENCE_DIR" <<'PY' > "$EVIDENCE_DIR/running-hosts.txt"
import json
from pathlib import Path
import sys
import urllib.request

base = 'http://team-17-nn:8088/ws/v1/cluster/'
def fetch(endpoint):
    with urllib.request.urlopen(base + endpoint, timeout=10) as response:
        return json.load(response)
nodes = fetch('nodes')['nodes']['node']
metrics = fetch('metrics')['clusterMetrics']
hosts = [node['nodeHostName'] for node in nodes]
if not set(hosts) <= {'team-17-nn', 'team-17-00', 'team-17-01'} or len(hosts) != len(set(hosts)):
    raise SystemExit('Unexpected or duplicate YARN node hostname')
if not {'team-17-00', 'team-17-01'} <= set(hosts) or any(node['state'] != 'RUNNING' or node.get('healthReport', '').strip() for node in nodes):
    raise SystemExit('Expected healthy RUNNING worker00 and worker01; NN NodeManager is optional')
(Path(sys.argv[1]) / 'yarn-resources.json').write_text(json.dumps({'nodes': nodes, 'metrics': metrics}, indent=2) + '\n')
print('\n'.join(hosts))
PY
while IFS= read -r host; do
  case "$host" in team-17-nn|team-17-00|team-17-01) ;; *) fail 'Unexpected worker hostname' ;; esac
  on_node "$host" python3 - > "$EVIDENCE_DIR/physical-$host.json" <<'PY'
import json
from pathlib import Path
import re
import socket
import subprocess

memory = Path('/proc/meminfo').read_text()
print(json.dumps({'host': socket.gethostname().split('.')[0],
                  'available_mib': int(re.search(r'^MemAvailable:\s+(\d+)', memory, re.M)[1]) // 1024,
                  'cpu_count': int(subprocess.check_output(['nproc'], text=True))}))
PY
done < "$EVIDENCE_DIR/running-hosts.txt"
python3 - "$EVIDENCE_DIR" <<'PY'
import json
from pathlib import Path
import re
import socket
import sys
import urllib.request

evidence = Path(sys.argv[1])
meminfo = Path('/proc/meminfo').read_text()
available_mib = int(re.search(r'^MemAvailable:\s+(\d+)', meminfo, re.M)[1]) // 1024
if available_mib < 1536:
    raise SystemExit('Need at least 1536 MiB MemAvailable on edge before Spark; stop and inspect resources')
report = (evidence / 'hdfs-report.txt').read_text()
if not re.search(r'Live datanodes\s*\(3\)', report):
    raise SystemExit('Expected three live HDFS DataNodes')
for label in ('Dead datanodes', 'Decommissioning datanodes'):
    match = re.search(re.escape(label) + r'\s*\((\d+)\)', report)
    if match and int(match[1]):
        raise SystemExit('Unexpected ' + label)
snapshot = json.loads((evidence / 'yarn-resources.json').read_text())
nodes, metrics = snapshot['nodes'], snapshot['metrics']
hosts = [node['nodeHostName'] for node in nodes]
if (not set(hosts) <= {'team-17-nn', 'team-17-00', 'team-17-01'} or len(hosts) != len(set(hosts))
        or not {'team-17-00', 'team-17-01'} <= set(hosts)
        or any(node['state'] != 'RUNNING' or node.get('healthReport', '').strip() for node in nodes)):
    raise SystemExit('Expected healthy RUNNING known workers; NN NodeManager is optional')
scheduler = json.loads((evidence / 'scheduler-resources.json').read_text())
minimum = scheduler['minimum-allocation-mb']['value']
maximum = scheduler['maximum-allocation-mb']['value']
core_minimum = scheduler['minimum-allocation-vcores']['value']
core_maximum = scheduler['maximum-allocation-vcores']['value']
if minimum <= 0 or maximum < minimum or core_minimum <= 0 or core_maximum < core_minimum:
    raise SystemExit('Invalid scheduler allocation bounds')
executor_memory = ((896 + minimum - 1) // minimum) * minimum
am_memory = ((512 + minimum - 1) // minimum) * minimum
container_cores = core_minimum
if max(executor_memory, am_memory) > maximum or container_cores > core_maximum:
    raise SystemExit('Spark requests exceed current scheduler maximum allocation')
physical = {}
budgets = []
for node in nodes:
    host = node['nodeHostName']
    actual = json.loads((evidence / ('physical-' + host + '.json')).read_text())
    if actual['host'] != host:
        raise SystemExit('Physical resource probe returned a different host')
    physical_memory = max(0, int(actual['available_mib']) - 512)
    physical_cores = int(actual['cpu_count'])
    reported_memory, reported_cores = int(node['availMemoryMB']), int(node['availableVirtualCores'])
    memory, cores = min(reported_memory, physical_memory), min(reported_cores, physical_cores)
    subsets = [(am_memory, container_cores), (executor_memory, container_cores),
               (am_memory + executor_memory, 2 * container_cores)]
    for requested_memory, requested_cores in subsets:
        if (reported_memory >= requested_memory and reported_cores >= requested_cores
                and (physical_memory < requested_memory or physical_cores < requested_cores)):
            raise SystemExit('YARN over-advertises resources on ' + host + '; unsafe possible container placement')
    budgets.append((memory, cores))
    physical[host] = {**actual, 'reserve_mib': 512, 'usable_memory_mib': memory, 'usable_cores': cores}
can_fit = False
for executor_node in range(len(budgets)):
    remaining = [list(pair) for pair in budgets]
    remaining[executor_node][0] -= executor_memory
    remaining[executor_node][1] -= container_cores
    if min(remaining[executor_node]) < 0:
        continue
    if any(memory >= am_memory and cores >= container_cores for memory, cores in remaining):
        can_fit = True
if not can_fit or int(metrics['availableMB']) < executor_memory + am_memory:
    raise SystemExit('YARN cannot currently place both containers within physical and scheduler budgets')
with socket.create_connection(('team-17-nn', 9083), timeout=10):
    pass
summary = {'edge_available_mib': available_mib, 'hdfs_live_nodes': 3,
           'yarn_nodes': nodes, 'yarn_metrics': metrics, 'physical_nodes': physical,
           'scheduler': scheduler, 'container_requests': {'executor_mib': executor_memory, 'am_mib': am_memory, 'cores_each': container_cores},
           'hms_tcp_reachable': True, 'status': 'read_only_checks_passed'}
(evidence / 'preflight-health.json').write_text(json.dumps(summary, indent=2) + '\n')
PY
nn_beeline -e 'SELECT 1;' > "$EVIDENCE_DIR/hive-preflight.tsv" 2> "$EVIDENCE_DIR/hive-preflight.log"
grep -Eq '^1[[:space:]]*$' "$EVIDENCE_DIR/hive-preflight.tsv" || fail 'HiveServer2 did not return SELECT 1'
printf '%s\n' "$RUN_ID" > "$EVIDENCE_DIR/preflight.ok"
