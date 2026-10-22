#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"
require_edge
[[ "$SPARK_HOME" == "$PLATFORM_ROOT/spark-4.1.0-bin-hadoop3" ]] || fail 'Installer expects the fixed versioned SPARK_HOME'
sudo -n test ! -e "$SPARK_HOME" || fail 'SPARK_HOME already exists; inspect it instead of reinstalling'
sudo -n test ! -L "$SPARK_HOME" || fail 'SPARK_HOME is a symbolic link; inspect it instead of reinstalling'
hadoop_group=$(id -gn "$HADOOP_USER")
if ! sudo -n test -d "$PLATFORM_ROOT"; then
  sudo -n install -d -o "$HADOOP_USER" -g "$hadoop_group" -m 750 "$PLATFORM_ROOT"
fi
sudo -n test ! -e "$HW4_RUNTIME_DIR" || fail 'Runtime already exists; inspect instead of replacing it'
available_kib=$(sudo -n df -Pk "$PLATFORM_ROOT" | awk 'NR==2 { print $4 }')
[[ "$available_kib" =~ ^[0-9]+$ ]] && (( available_kib >= 4194304 )) || fail 'At least 4 GiB of free disk space is required'
work=$(mktemp -d /tmp/team17-hw4-install.XXXXXX)
staging=''
cleanup() {
  rm -rf -- "$work"
  [[ -z "$staging" ]] || edge_hadoop rm -rf -- "$staging"
}
trap cleanup EXIT
chmod 755 "$work"
tmp_available_kib=$(df -Pk "$work" | awk 'NR==2 { print $4 }')
[[ "$tmp_available_kib" =~ ^[0-9]+$ ]] && (( tmp_available_kib >= 1048576 )) || fail 'At least 1 GiB of free space in /tmp is required for the archive'
archive=spark-4.1.0-bin-hadoop3.tgz
base=https://archive.apache.org/dist/spark/spark-4.1.0
curl --fail --location --retry 2 "$base/$archive" -o "$work/$archive"
curl --fail --location --retry 2 "$base/$archive.sha512" -o "$work/$archive.sha512"
python3 - "$work/$archive" "$work/$archive.sha512" <<'PY'
import hashlib
from pathlib import Path
import re
import sys

archive, checksum = map(Path, sys.argv[1:])
hashes = re.findall(r'\b[0-9a-fA-F]{128}\b', checksum.read_text())
if len(hashes) != 1:
    raise SystemExit('Expected exactly one SHA-512 in the official checksum')
pinned = 'fff7f929d98779b096a2d2395b1b9db1ce277660f3852dd45e1457c373013f2669074315252181a3cea291d8f3a726c70f7f9b247e723edbf8080f40888edde1'
if hashes[0].lower() != pinned:
    raise SystemExit('Official checksum differs from pinned Spark 4.1.0 checksum')
digest = hashlib.sha512()
with archive.open('rb') as stream:
    for chunk in iter(lambda: stream.read(1024 * 1024), b''):
        digest.update(chunk)
if digest.hexdigest() != hashes[0].lower():
    raise SystemExit('SHA-512 mismatch')
print('Official SHA-512 verified: ' + digest.hexdigest())
PY
chmod 644 "$work/$archive"
staging=$(edge_hadoop mktemp -d "$PLATFORM_ROOT/.spark-install.XXXXXX")
[[ "$staging" == "$PLATFORM_ROOT"/.spark-install.* ]] || fail 'Unexpected extraction directory'
edge_hadoop tar -xzf "$work/$archive" -C "$staging" --no-same-owner
edge_hadoop test -x "$staging/spark-4.1.0-bin-hadoop3/bin/spark-submit"
sudo -n chown -R "$HADOOP_USER:$hadoop_group" "$staging"
edge_hadoop test ! -e "$SPARK_HOME" || fail 'Destination appeared during installation; refusing to replace it'
edge_hadoop test ! -L "$SPARK_HOME" || fail 'Destination became a symbolic link during installation'
edge_hadoop mv -T --no-clobber "$staging/spark-4.1.0-bin-hadoop3" "$SPARK_HOME"
edge_hadoop test -x "$SPARK_HOME/bin/spark-submit"
edge_hadoop mkdir -p "$staging/runtime/conf" "$staging/runtime/hms-4.1.0-client"
on_node "$NN_HOST" sudo -n -H -u "$HADOOP_USER" python3 - "$NN_HADOOP_HOME/etc/hadoop" \
  < "$HW4_DIR/scripts/export_hadoop_conf.py" > "$work/hadoop-conf.json"
python3 "$HW4_DIR/scripts/render_runtime.py" "$work/conf" < "$work/hadoop-conf.json"
for name in core-site.xml hdfs-site.xml yarn-site.xml hive-site.xml; do
  edge_hadoop tee "$staging/runtime/conf/$name" < "$work/conf/$name" >/dev/null
done
on_node "$NN_HOST" sudo -n -H -u "$HADOOP_USER" python3 - "$NN_HIVE_HOME" \
  < "$HW4_DIR/scripts/export_hive_jars.py" \
  | edge_hadoop tar -xf - -C "$staging/runtime/hms-4.1.0-client" --no-same-owner --no-same-permissions
edge_hadoop tee "$staging/runtime/verify_runtime.py" < "$HW4_DIR/scripts/verify_runtime.py" >/dev/null
edge_hadoop test ! -e "$HW4_RUNTIME_DIR" || fail 'Runtime destination appeared; refusing to replace it'
edge_hadoop python3 "$staging/runtime/verify_runtime.py" "$SPARK_HOME" "$staging/runtime" --installed-root "$HW4_RUNTIME_DIR" --record
edge_hadoop mv -T --no-clobber "$staging/runtime" "$HW4_RUNTIME_DIR"
printf 'Prepared Spark4.1.0 and isolated Hive4.1.0 client; no application has been launched.\n'
