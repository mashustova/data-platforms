#!/usr/bin/env bash
set -euo pipefail
HW4_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$HW4_DIR/support/cluster-common.sh"
JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64
PLATFORM_ROOT=/home/hadoop/mashustova/platform
NN_HADOOP_HOME=/opt/hadoop-3.4.0
NN_HIVE_HOME=/opt/hive
NN_CLI_JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64
SPARK_HOME="$PLATFORM_ROOT/spark-4.1.0-bin-hadoop3"
HW4_RUNTIME_DIR="$PLATFORM_ROOT/hw4"
HDFS_URI=hdfs://team-17-nn:9000
HW4_HDFS_ROOT=/user/hadoop/mashustova/hw4
HW4_DATABASE=dp_mashustova_hw4
HMS_URI=thrift://team-17-nn:9083
HIVE_JDBC_URL=jdbc:hive2://10.17.0.11:10000/default
[[ ! -f "$HW4_DIR/local.env" ]] || source "$HW4_DIR/local.env"
for path in "$PLATFORM_ROOT" "$SPARK_HOME" "$HW4_RUNTIME_DIR"; do
  [[ "$path" == /home/hadoop/mashustova/* && "$path" =~ ^/[a-zA-Z0-9/._-]+$ && "$path" != *..* ]] || fail 'Use personal installation paths under /home/hadoop/mashustova'
done
[[ "$HDFS_URI" == hdfs://team-17-nn:9000 && "$HW4_HDFS_ROOT" == /user/hadoop/mashustova/hw4 ]] || fail 'Use the personal team-17 HDFS namespace'
[[ "$HW4_DATABASE" == dp_mashustova_hw4 && "$HMS_URI" == thrift://team-17-nn:9083 ]] || fail 'Unexpected database or metastore endpoint'
HADOOP_CONF_DIR="$HW4_RUNTIME_DIR/conf"
SPARK_CONF_DIR="$HW4_RUNTIME_DIR/conf"
HMS_JARS_DIR="$HW4_RUNTIME_DIR/hms-4.1.0-client"
edge_hadoop() {
  sudo -n -H -u "$HADOOP_USER" env -u HIVE_HOME -u HIVE_CONF_DIR -u HADOOP_HOME -u CLASSPATH -u SPARK_DIST_CLASSPATH -u YARN_CONF_DIR \
    "JAVA_HOME=$JAVA_HOME" "SPARK_HOME=$SPARK_HOME" "HADOOP_CONF_DIR=$HADOOP_CONF_DIR" "SPARK_CONF_DIR=$SPARK_CONF_DIR" "$@"
}
nn_hdfs() {
  on_node "$NN_HOST" sudo -n -H -u "$HADOOP_USER" env "JAVA_HOME=$NN_CLI_JAVA_HOME" "HADOOP_HOME=$NN_HADOOP_HOME" \
    "HADOOP_CONF_DIR=$NN_HADOOP_HOME/etc/hadoop" "$NN_HADOOP_HOME/bin/hdfs" "$@"
}
nn_yarn() {
  on_node "$NN_HOST" sudo -n -H -u "$HADOOP_USER" env "JAVA_HOME=$NN_CLI_JAVA_HOME" "HADOOP_HOME=$NN_HADOOP_HOME" \
    "HADOOP_CONF_DIR=$NN_HADOOP_HOME/etc/hadoop" "$NN_HADOOP_HOME/bin/yarn" "$@"
}
nn_beeline() {
  on_node "$NN_HOST" sudo -n -H -u "$HADOOP_USER" env "JAVA_HOME=$JAVA_HOME" "HADOOP_HOME=$NN_HADOOP_HOME" \
    "HADOOP_CONF_DIR=$NN_HADOOP_HOME/etc/hadoop" "HIVE_HOME=$NN_HIVE_HOME" "HIVE_CONF_DIR=$NN_HIVE_HOME/conf" \
    timeout 180 "$NN_HIVE_HOME/bin/beeline" -u "$HIVE_JDBC_URL" -n "$HADOOP_USER" \
    --silent=true --showHeader=false --outputformat=tsv2 --color=false --force=false "$@"
}
set_run() {
  RUN_ID=${1:?Run ID required}
  [[ "$RUN_ID" =~ ^[a-z][a-z0-9_]{0,47}$ ]] || fail 'Run ID: letter followed by up to 47 lowercase letters, digits or underscores'
  RUN_HDFS="$HW4_HDFS_ROOT/runs/$RUN_ID"
  OUTPUT_URI="$HDFS_URI$RUN_HDFS/daily_sales"
  JOB_DIR="$HW4_RUNTIME_DIR/jobs/$RUN_ID"
  EVIDENCE_DIR="$HW4_DIR/results/$RUN_ID"
  TABLE_NAME="daily_sales_$RUN_ID"
}
