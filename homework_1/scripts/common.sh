#!/usr/bin/env bash
set -euo pipefail
HW1_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
EDGE_HOST=team-17-en
SSH_USER=team
HADOOP_USER=hadoop
HADOOP_USER_HOME=/home/hadoop
export HADOOP_HOME=/home/hadoop/hadoop-3.4.0
export JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64
export NN_HOST=team-17-nn
export NN_IP=10.17.0.11
NODES=(team-17-nn team-17-00 team-17-01)
NODE_IPS=(10.17.0.11 10.17.0.12 10.17.0.13)
INTERNAL_KEY=${INTERNAL_KEY:-$HOME/.ssh/team_internal}
[[ ! -f "$HW1_ROOT/cluster.env" ]] || source "$HW1_ROOT/cluster.env"
for value in "$EDGE_HOST" "$SSH_USER" "$HADOOP_USER" "$NN_HOST" "${NODES[@]}"; do
  [[ $value =~ ^[a-zA-Z0-9][a-zA-Z0-9._-]*$ ]] || { echo 'Invalid host or user name' >&2; exit 1; }
done
[[ ${#NODES[@]} == 3 && ${#NODE_IPS[@]} == 3 ]] || { echo 'Exactly three DataNode hosts are required' >&2; exit 1; }
[[ ${NODES[0]} != "${NODES[1]}" && ${NODES[0]} != "${NODES[2]}" && ${NODES[1]} != "${NODES[2]}" ]] || { echo 'DataNode hosts must be distinct' >&2; exit 1; }
[[ ${NODE_IPS[0]} != "${NODE_IPS[1]}" && ${NODE_IPS[0]} != "${NODE_IPS[2]}" && ${NODE_IPS[1]} != "${NODE_IPS[2]}" ]] || { echo 'DataNode IPs must be distinct' >&2; exit 1; }
[[ $NN_HOST == "${NODES[0]}" && $NN_IP == "${NODE_IPS[0]}" ]] || { echo 'The first node must be the NameNode host and IP' >&2; exit 1; }
for value in "$NN_IP" "${NODE_IPS[@]}"; do
  [[ $value =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo 'Use IPv4 addresses' >&2; exit 1; }
done
for value in "$HADOOP_HOME" "$JAVA_HOME" "$HADOOP_USER_HOME"; do
  [[ $value =~ ^/[a-zA-Z0-9/._-]+$ && $value != / && $value != *..* ]] || { echo 'Use absolute installation paths without spaces or parent traversal' >&2; exit 1; }
done
export HADOOP_HOME JAVA_HOME NN_HOST NN_IP HADOOP_USER HADOOP_USER_HOME
SSH_OPTIONS=(-i "$INTERNAL_KEY" -o IdentitiesOnly=yes -o BatchMode=yes -o ConnectTimeout=10)
export HADOOP_SHA512=6f653c0109f97430047bd3677c50da7c8a2809d153b231794cf980b3208a6b4beff8ff1a03a01094299d459a3a37a3fe16731629987165d71f328657dbf2f24c
fail() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
on_node() {
  local host=$1 quoted argument
  shift
  [[ $# -gt 0 ]] || fail 'on_node requires a command'
  quoted=''
  for argument in "$@"; do
    printf -v argument '%q' "$argument"
    quoted+="$argument "
  done
  ssh "${SSH_OPTIONS[@]}" "$SSH_USER@$host" "$quoted"
}
hdfs_cmd() { on_node "$NN_HOST" sudo -n -u "$HADOOP_USER" env "JAVA_HOME=$JAVA_HOME" "$HADOOP_HOME/bin/hdfs" "$@"; }
require_edge() {
  [[ $(id -un) == "$SSH_USER" ]] || fail "Run as $SSH_USER on $EDGE_HOST"
  [[ $(hostname -s) == "$EDGE_HOST" ]] || fail "Run on $EDGE_HOST (edge)"
  [[ -r $INTERNAL_KEY ]] || fail "Missing readable internal key: $INTERNAL_KEY"
  for command in ssh scp; do command -v "$command" >/dev/null || fail "Missing $command"; done
}
assert_stopped() {
  local node=$1
  on_node "$node" bash -se -- "$HADOOP_USER" "$HADOOP_USER_HOME" <<'REMOTE'
set -euo pipefail
if id "$1" >/dev/null 2>&1; then
  if sudo -n pgrep -u "$1" -f 'org.apache.hadoop.' >/dev/null; then
    echo 'Hadoop Java processes are running; stop and inspect the existing installation.' >&2
    exit 1
  else
    result=$?
    [[ $result == 1 ]] || exit "$result"
  fi
fi
REMOTE
}
assert_pristine() {
  local node=$1
  assert_stopped "$node"
  on_node "$node" bash -se -- "$HADOOP_USER" "$HADOOP_USER_HOME" <<'REMOTE'
set -euo pipefail
root=$2/hdfs
sudo -n test ! -L "$root"
if sudo -n test -e "$root"; then
  existing=$(sudo -n find "$root" -mindepth 2 -print -quit)
  [[ -z $existing ]] || { echo 'Existing HDFS state found; refusing initialization.' >&2; exit 1; }
  entries=$(sudo -n find "$root" -mindepth 1 -maxdepth 1 -print)
  while IFS= read -r entry; do
    [[ -n $entry ]] || continue
    case "$entry" in
      "$root/name"|"$root/data"|"$root/checkpoint") sudo -n test -d "$entry"; sudo -n test ! -L "$entry" ;;
      *) echo "Unexpected HDFS entry: $entry" >&2; exit 1 ;;
    esac
  done <<< "$entries"
  sudo -n test ! -L "$root"
fi
REMOTE
}
require_installation() {
  local node
  for node in "${NODES[@]}"; do
    on_node "$node" sudo -n -u "$HADOOP_USER" test -x "$HADOOP_HOME/bin/hdfs"
  done
}

render_config() {
  local text
  text=$(cat "$HW1_ROOT/configs/$1")
  text=${text//__NN_IP__/$NN_IP}
  text=${text//__HADOOP_USER_HOME__/$HADOOP_USER_HOME}
  text=${text//__HADOOP_HOME__/$HADOOP_HOME}
  text=${text//__JAVA_HOME__/$JAVA_HOME}
  printf '%s\n' "$text"
}
