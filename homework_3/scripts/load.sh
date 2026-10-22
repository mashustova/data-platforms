#!/usr/bin/env bash
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/common.sh"
require_hive_installation
require_hdfs_cluster
group=$(id -gn "$HADOOP_USER")
sudo -n install -d -o "$HADOOP_USER" -g "$group" -m 750 /home/hadoop/mashustova "$HW3_STAGE_DIR"
client_hdfs dfs -mkdir -p "$HW3_HDFS_ROOT"
run_sql "$HW3_DIR/sql/create-orders.hql" --hiveconf "hw3_root=$HW3_HDFS_ROOT"
stage=$(mktemp -d /tmp/hw3-load.XXXXXX)
trap 'rm -rf -- "$stage"' EXIT
beeline_cmd -e 'DESCRIBE FORMATTED dp_mashustova_hw3.orders;' > "$stage/description.tsv"
python3 "$HW3_DIR/scripts/validate_table.py" "$stage/description.tsv" "$HW3_HDFS_ROOT/orders"
printf 'SET hive.stats.autogather=false;\nSET hive.stats.column.autogather=false;\n' > "$stage/load.hql"
for partition in "$HW3_DIR"/data/partitions/dt=*; do
  dt=${partition##*/dt=}
  [[ $dt =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || fail 'Invalid partition date'
  sudo -n install -d -o "$HADOOP_USER" -g "$group" -m 750 "$HW3_STAGE_DIR/dt=$dt"
  sudo -n install -o "$HADOOP_USER" -g "$group" -m 640 "$partition/orders.csv" "$HW3_STAGE_DIR/dt=$dt/orders.csv"
  printf "LOAD DATA LOCAL INPATH '%s/dt=%s/orders.csv' OVERWRITE INTO TABLE dp_mashustova_hw3.orders PARTITION(dt='%s');\n" "$HW3_STAGE_DIR" "$dt" "$dt" >> "$stage/load.hql"
done
run_sql "$stage/load.hql"
beeline_cmd -e 'SHOW PARTITIONS dp_mashustova_hw3.orders;'
client_hdfs dfs -ls "$HW3_HDFS_ROOT/orders"
