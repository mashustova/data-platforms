# HDFS

## Окружение

Debian/Ubuntu x86_64, Hadoop 3.4.0, Java 11, Bash, sudo без пароля. На edge нужны ssh, scp, curl, sha512sum и sha256sum; на внутренних узлах - apt-get, pgrep, timeout и find.

| Узел | IP | Процессы |
|---|---|---|
| team-17-en | 10.17.0.10 | Управление |
| team-17-nn | 10.17.0.11 | NameNode, SecondaryNameNode, DataNode |
| team-17-00 | 10.17.0.12 | DataNode |
| team-17-01 | 10.17.0.13 | DataNode |

Скрипты выполняются на edge пользователем `team`. Процессы Hadoop работают от `hadoop`.

## Параметры

На edge, в каталоге `~/homework_1`:

```bash
cp cluster.env.example cluster.env
```

В `cluster.env` задаются узлы, IP, пользователи, пути и внутренний SSH-ключ. Первая пара `NODES[0]/NODE_IPS[0]` должна совпадать с `NN_HOST/NN_IP`. Узлы и IP должны быть уникальными.

По умолчанию: `JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64`, `HADOOP_HOME=/home/hadoop/hadoop-3.4.0`, `INTERNAL_KEY=$HOME/.ssh/team_internal`. Указанный каталог Java 11 должен существовать на всех узлах. Проверка пути: `readlink -f /usr/bin/java`; версии: `java -version`.

`configure.sh` подставляет параметры в шаблоны `configs/`. Репликация - 3. Порты: RPC 9000, NameNode UI 9870, SecondaryNameNode UI 9868.

## Перенос и доступ

На локальном компьютере, из родительского каталога решения:

```bash
scp -r homework_1 team@178.236.27.243:~/
ssh team@178.236.27.243
```

На edge проверить SSH-доступ к трем узлам и сохранить проверенные ключи хостов:

```bash
ssh -i ~/.ssh/team_internal -o IdentitiesOnly=yes team@team-17-nn 'hostname; sudo -n true'
ssh -i ~/.ssh/team_internal -o IdentitiesOnly=yes team@team-17-00 'hostname; sudo -n true'
ssh -i ~/.ssh/team_internal -o IdentitiesOnly=yes team@team-17-01 'hostname; sudo -n true'
```

## Установка и запуск

На edge:

```bash
cd ~/homework_1
bash scripts/preflight.sh
bash scripts/install.sh
bash scripts/configure.sh
bash scripts/initialize.sh --new-empty-cluster
bash scripts/start.sh
bash scripts/check.sh
```

`initialize.sh` запускать только при первой установке на пустом кластере. При рестарте не выполнять.

## Проверка

`check.sh` проверяет три живых DN, отсутствие мертвых DN, Safe Mode OFF, процессы, запись и чтение файла, три реплики и `fsck HEALTHY`. Результаты сохраняются в `evidence/runtime-<timestamp>-<pid>/`.

На локальном компьютере:

```bash
ssh -N -o ExitOnForwardFailure=yes -L 127.0.0.1:9870:10.17.0.11:9870 team@178.236.27.243
```

Открыть `http://localhost:9870`: 3 Live Nodes, 0 Dead Nodes. Проверить актуальные журналы в `$HADOOP_HOME/logs`, включая успешный checkpoint SecondaryNameNode. Сохранить скриншот и результаты проверки.

## Остановка и рестарт

На edge:

```bash
bash scripts/stop.sh
bash scripts/start.sh
bash scripts/check.sh
```
