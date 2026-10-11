#!/usr/bin/env bash
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/common.sh"
require_edge
for index in "${!NODES[@]}"; do
  node=${NODES[$index]}
  on_node "$node" bash -se -- "$node" "${NODE_IPS[$index]}" "$SSH_USER" <<'REMOTE'
set -euo pipefail
[[ $(id -un) == "$3" ]]
[[ $(hostname -s) == "$1" ]]
[[ $(uname -m) == x86_64 ]]
command -v apt-get >/dev/null
sudo -n true
command -v pgrep >/dev/null
getent ahostsv4 "$1" | awk -v expected="$2" '$1==expected {found=1} END {exit !found}'
getent hosts "$1"
free -h
df -h /home /tmp
[[ $(df -Pk /tmp | awk 'NR==2 {print $4}') -ge 2097152 ]] || { echo 'Need at least 2 GiB free on /tmp for the installation archive' >&2; exit 1; }
[[ $(df -Pk /home | awk 'NR==2 {print $4}') -ge 6291456 ]] || { echo 'Need at least 6 GiB free on /home before first installation' >&2; exit 1; }
REMOTE
done
