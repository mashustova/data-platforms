#!/usr/bin/env bash
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/common.sh"
require_hive_installation
require_hdfs_cluster
evidence=$HW3_DIR/evidence/$(date -u +%Y%m%dT%H%M%SZ)-$$
mkdir -p "$evidence"
systemctl is-active hive-metastore.service hive-hiveserver2.service > "$evidence/services.txt"
run_hadoop python3 - "$HIVE_HOME/conf/hive-site.xml" "$METASTORE_URI" "$HIVE_HOST" "$METASTORE_DB" "$METASTORE_USER" < "$HW3_DIR/scripts/validate_config.py" > "$evidence/effective-config.json"
schema=$(sudo -n -H -u postgres psql -X -A -t -d "$METASTORE_DB" -v ON_ERROR_STOP=1 -c 'SELECT "SCHEMA_VERSION" FROM "VERSION";')
printf '%s\n' "$schema" > "$evidence/schema.txt"
[[ $schema == 4.1.0 ]] || fail 'Unexpected existing metastore schema'
beeline_cmd -e 'DESCRIBE FORMATTED dp_mashustova_hw3.orders;' > "$evidence/description.tsv" 2> "$evidence/description.stderr"
python3 "$HW3_DIR/scripts/validate_table.py" "$evidence/description.tsv" "$HW3_HDFS_ROOT/orders" > "$evidence/table.json"
beeline_cmd -e 'SHOW PARTITIONS dp_mashustova_hw3.orders;' > "$evidence/partitions.txt" 2> "$evidence/partitions.stderr"
python3 - "$evidence/partitions.txt" "$HW3_DIR/data/expected.json" <<'CHECK'
import json
from pathlib import Path
import sys
actual = sorted(line.strip().removeprefix('dt=') for line in Path(sys.argv[1]).read_text().splitlines() if line.startswith('dt='))
expected = json.loads(Path(sys.argv[2]).read_text())['partitions']
assert actual == sorted(expected), (actual, expected)
CHECK
python3 "$HW3_DIR/scripts/check_clients.py" --output "$evidence" --data "$HW3_DIR/data/orders.csv" --query "$HW3_DIR/sql/read-orders.hql" --java-home "$JAVA_HOME" --hadoop-home "$HADOOP_CLIENT_HOME" --hive-home "$HIVE_HOME" --jdbc "$HIVE_JDBC_URL"
client_hdfs fsck "$HW3_HDFS_ROOT/orders" -files -blocks -locations > "$evidence/fsck.txt" 2>&1
grep -q 'Status: HEALTHY' "$evidence/fsck.txt"
printf 'Evidence: %s\n' "$evidence"
