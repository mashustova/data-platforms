# HDFS

## Окружение

Ubuntu 24.04 x86_64, Hadoop 3.4.0, Java 11, Bash, sudo без пароля. Используется существующая установка `/opt/hadoop-3.4.0`.

| Узел | IP | Процессы |
|---|---|---|
| team-17-en | 10.17.0.10 | Управление |
| team-17-nn | 10.17.0.11 | NameNode, SecondaryNameNode, DataNode |
| team-17-00 | 10.17.0.12 | DataNode |
| team-17-01 | 10.17.0.13 | DataNode |

Скрипты выполняются на edge пользователем `team`. Процессы Hadoop работают от `hadoop`.

## Перенос и доступ

На локальном компьютере, из родительского каталога решения:

```bash
scp -i ~/.ssh/team17 -o IdentitiesOnly=yes -r homework_1 team@178.236.27.243:~/
ssh -i ~/.ssh/team17 -o IdentitiesOnly=yes team@178.236.27.243
```

На edge:

```bash
ssh -i ~/.ssh/team_internal -o IdentitiesOnly=yes team@team-17-nn 'hostname; sudo -n true'
ssh -i ~/.ssh/team_internal -o IdentitiesOnly=yes team@team-17-00 'hostname; sudo -n true'
ssh -i ~/.ssh/team_internal -o IdentitiesOnly=yes team@team-17-01 'hostname; sudo -n true'
```

## Параметры

На edge:

```bash
cd ~/homework_1
test -f cluster.env || cp cluster.env.example cluster.env
sed -i 's|^HADOOP_HOME=.*|HADOOP_HOME=/opt/hadoop-3.4.0|' cluster.env
```

Параметры `cluster.env`:

```bash
HADOOP_HOME=/opt/hadoop-3.4.0
JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64
HADOOP_USER=hadoop
HADOOP_USER_HOME=/home/hadoop
INTERNAL_KEY=$HOME/.ssh/team_internal
```

Каталоги HDFS: `/home/hadoop/hdfs/name`, `/home/hadoop/hdfs/data`, `/home/hadoop/hdfs/checkpoint`. Репликация - 3. Порты: RPC 9000, NameNode UI 9870, SecondaryNameNode UI 9868.

## Подготовка узлов

Перед первым запуском на edge:

```bash
bash scripts/preflight.sh
source scripts/common.sh
for node in "${NODES[@]}"; do
  on_node "$node" sudo -n bash -se <<'REMOTE'
set -euo pipefail
backup=$(mktemp -d /var/backups/hw1-config.XXXXXX)
cp -a /opt/hadoop-3.4.0/etc/hadoop "$backup/"
diff -qr /opt/hadoop-3.4.0/etc/hadoop "$backup/hadoop"
REMOTE
done
```

На `team-17-nn` пользователь `hadoop` и Java 11 уже подготовлены. На двух рабочих узлах:

```bash
for node in team-17-00 team-17-01; do
  on_node "$node" sudo -n bash -se <<'REMOTE'
set -euo pipefail
if ! getent group hadoop >/dev/null; then
  ! getent group 1001 >/dev/null
  groupadd --gid 1001 hadoop
fi
if ! id hadoop >/dev/null 2>&1; then
  ! getent passwd 1001 >/dev/null
  useradd --uid 1001 --gid hadoop --create-home --home-dir /home/hadoop --shell /bin/bash hadoop
fi
test "$(id -u hadoop)" = 1001
test "$(id -g hadoop)" = 1001
apt-get update -qq
env DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=l apt-get install -y openjdk-11-jdk-headless
/usr/lib/jvm/java-11-openjdk-amd64/bin/java -version
sudo -n -u hadoop test -w /opt/hadoop-3.4.0/logs
REMOTE
done
```

## Первоначальный запуск

На edge, для нового пустого кластера:

```bash
bash scripts/configure.sh &&
bash scripts/initialize.sh --new-empty-cluster &&
bash scripts/start.sh &&
bash scripts/check.sh
```

`configure.sh` заменяет три файла в `/opt/hadoop-3.4.0/etc/hadoop`: `core-site.xml`, `hdfs-site.xml`, `hadoop-env.sh`. `initialize.sh` выполняется один раз; при рестарте его не запускать.

## Проверка

`check.sh` проверяет три живых DataNode, отсутствие мертвых узлов, Safe Mode OFF, процессы, запись и чтение файла, три реплики и `fsck HEALTHY`. Результаты сохраняются в `evidence/runtime-<timestamp>-<pid>/`.

Checkpoint на NameNode:

```bash
ssh -i ~/.ssh/team_internal -o IdentitiesOnly=yes team@team-17-nn \
  'sudo -u hadoop ls -l /home/hadoop/hdfs/checkpoint/current; sudo -u hadoop grep "Checkpoint done" /opt/hadoop-3.4.0/logs/hadoop-hadoop-secondarynamenode-team-17-nn.log | tail -n 1'
```

## Веб-интерфейс

На локальном компьютере:

```bash
ssh -i ~/.ssh/team17 -o IdentitiesOnly=yes -N -o ExitOnForwardFailure=yes \
  -L 127.0.0.1:9870:10.17.0.11:9870 team@178.236.27.243
```

Открыть `http://localhost:9870`. В Overview: 3 Live Nodes, 0 Dead Nodes, Safemode off. В Datanodes: три узла в состоянии In service. В Utilities - Browse the file system: `/user/hadoop/hw1/`, файл `hello.txt` внутри каталога запуска, Replication 3.

Скриншоты: `evidence/screenshots/overview.jpg`, `evidence/screenshots/datanodes.jpg`, `evidence/screenshots/file.jpg`.

## Перезапуск

На edge, в `~/homework_1`:

```bash
bash scripts/stop.sh &&
bash scripts/start.sh &&
bash scripts/check.sh
```
