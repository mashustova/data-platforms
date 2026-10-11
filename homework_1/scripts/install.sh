#!/usr/bin/env bash
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/common.sh"
"$HW1_ROOT/scripts/preflight.sh"
for node in "${NODES[@]}"; do
  assert_pristine "$node"
  on_node "$node" sudo -n test ! -e "$HADOOP_HOME"
done
for command in curl sha512sum tar mktemp; do command -v "$command" >/dev/null || fail "Missing $command on edge"; done
[[ $(df -Pk "$HOME" | awk 'NR==2 {print $4}') -ge 2097152 ]] || fail 'Need 2 GiB free on edge for archive'
download_dir=$(mktemp -d "$HOME/hw1-download.XXXXXX")
trap 'rm -rf -- "$download_dir"' EXIT
archive=$download_dir/hadoop-3.4.0.tar.gz
curl --fail --location --retry 2 --output "$archive" https://archive.apache.org/dist/hadoop/common/hadoop-3.4.0/hadoop-3.4.0.tar.gz
printf '%s  %s\n' "$HADOOP_SHA512" "$archive" | sha512sum -c -
for node in "${NODES[@]}"; do
  remote_dir=$(on_node "$node" mktemp -d /tmp/hw1-install.XXXXXX)
  scp "${SSH_OPTIONS[@]}" "$archive" "$SSH_USER@$node:$remote_dir/hadoop-3.4.0.tar.gz"
  on_node "$node" bash -se -- "$remote_dir" "$HADOOP_SHA512" "$HADOOP_USER" "$HADOOP_USER_HOME" "$HADOOP_HOME" "$JAVA_HOME" <<'REMOTE'
set -euo pipefail
stage=$1
archive=$stage/hadoop-3.4.0.tar.gz
user=$3
user_home=$4
hadoop_home=$5
java_home=$6
printf '%s  %s\n' "$2" "$archive" | sha512sum -c -
sudo -n test ! -e "$hadoop_home"
if [[ ! -x $java_home/bin/java ]]; then
  if command -v java >/dev/null && java -version 2>&1 | grep -Eq 'version "11[.\"]'; then
    detected=$(readlink -f "$(command -v java)")
    echo "Java 11 is already installed at ${detected%/bin/java}; set JAVA_HOME in cluster.env to this path and rerun." >&2
    exit 1
  fi
  sudo -n apt-get update
  sudo -n apt-get install -y openjdk-11-jdk-headless
fi
"$java_home/bin/java" -version 2>&1 | tee "$stage/java-version.txt"
grep -Eq 'version "11[.\"]' "$stage/java-version.txt"
if ! id "$user" >/dev/null 2>&1; then sudo -n useradd --create-home --home-dir "$user_home" --shell /bin/bash "$user"; fi
sudo -n install -d -o "$user" -g "$(id -gn "$user")" -m 750 "$user_home/hdfs/data" "$user_home/run" "$hadoop_home"
sudo -n tar -xzf "$archive" --strip-components=1 -C "$hadoop_home"
sudo -n chown -R "$user:$(id -gn "$user")" "$hadoop_home"
sudo -n -u "$user" env "JAVA_HOME=$java_home" "$hadoop_home/bin/hadoop" version
rm -- "$archive" "$stage/java-version.txt"
rmdir -- "$stage"
REMOTE
done
