#!/usr/bin/env bash
set -euo pipefail
HW2_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$HW2_DIR/../homework_1/scripts/common.sh"
[[ ! -f "$HW2_DIR/local.env" ]] || source "$HW2_DIR/local.env"
: "${RM_HOST:=${NODES[1]}}" "${JHS_HOST:=${NODES[2]}}"
: "${NN_CONTAINER_MB:=512}" "${WORKER0_CONTAINER_MB:=1024}" "${WORKER1_CONTAINER_MB:=1536}" "${CONTAINER_VCORES:=2}"
NM_MEMORY_MB=("$NN_CONTAINER_MB" "$WORKER0_CONTAINER_MB" "$WORKER1_CONTAINER_MB")
for host in "$RM_HOST" "$JHS_HOST"; do
  [[ " ${NODES[*]} " == *" $host "* ]] || fail "YARN host must be in NODES"
done
for mb in "${NM_MEMORY_MB[@]}"; do
  [[ "$mb" =~ ^[0-9]+$ ]] && (( mb >= 512 && mb % 512 == 0 )) || fail "Use container budgets in multiples of 512 MiB"
done
yarn_cmd() { on_node "$NN_HOST" sudo -n -u "$HADOOP_USER" env "JAVA_HOME=$JAVA_HOME" "HADOOP_HOME=$HADOOP_HOME" "$HADOOP_HOME/bin/yarn" "$@"; }
