#!/usr/bin/env bash
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/common.sh"
[[ ${1:-} == --new-empty-cluster && $# == 1 ]] || fail 'Usage: initialize.sh --new-empty-cluster (only for first initialization)'
require_edge
require_installation
for node in "${NODES[@]}"; do
  assert_pristine "$node"
  for file in core-site.xml hdfs-site.xml hadoop-env.sh; do
    expected=$(render_config "$file" | sha256sum | awk '{print $1}')
    actual=$(on_node "$node" sudo -n sha256sum "$HADOOP_HOME/etc/hadoop/$file" | awk '{print $1}')
    [[ $actual == "$expected" ]] || fail "Configuration differs on $node: $file"
  done
done
on_node "$NN_HOST" sudo -n -u "$HADOOP_USER" env "JAVA_HOME=$JAVA_HOME" "$HADOOP_HOME/bin/hdfs" namenode -format -nonInteractive
