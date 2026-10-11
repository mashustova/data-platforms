#!/usr/bin/env bash
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/common.sh"
require_edge
require_installation
for node in "${NODES[@]}"; do assert_stopped "$node"; done
stage=$(mktemp -d /tmp/hw1-config.XXXXXX)
trap 'rm -rf -- "$stage"' EXIT
for file in core-site.xml hdfs-site.xml hadoop-env.sh; do render_config "$file" > "$stage/$file"; done
for node in "${NODES[@]}"; do
  remote_dir=$(on_node "$node" mktemp -d /tmp/hw1-config.XXXXXX)
  scp "${SSH_OPTIONS[@]}" "$stage/core-site.xml" "$stage/hdfs-site.xml" "$stage/hadoop-env.sh" "$SSH_USER@$node:$remote_dir/"
  on_node "$node" bash -se -- "$remote_dir" "$HADOOP_USER" "$HADOOP_USER_HOME" "$HADOOP_HOME" <<'REMOTE'
set -euo pipefail
stage=$1
user=$2
user_home=$3
hadoop_home=$4
for file in core-site.xml hdfs-site.xml hadoop-env.sh; do
  sudo -n install -o "$user" -g "$(id -gn "$user")" -m 640 "$stage/$file" "$hadoop_home/etc/hadoop/$file"
  rm -- "$stage/$file"
done
rmdir -- "$stage"
sudo -n install -d -o "$user" -g "$(id -gn "$user")" -m 750 "$user_home/hdfs/data" "$user_home/run"
REMOTE
done
on_node "$NN_HOST" sudo -n install -d -o "$HADOOP_USER" -g "$(on_node "$NN_HOST" id -gn "$HADOOP_USER")" -m 750 "$HADOOP_USER_HOME/hdfs/name" "$HADOOP_USER_HOME/hdfs/checkpoint"
