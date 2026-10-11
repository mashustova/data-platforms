# YARN и веб-интерфейсы

## Параметры

- Hadoop 3.4.0: `/opt/hadoop-3.4.0`; Java 11: `/usr/lib/jvm/java-11-openjdk-amd64`; работающий HDFS из ДЗ 1.
- Папки обоих ДЗ: `/home/team/mashustova` на edge. Адреса и пути: `homework_1/cluster.env`, параметры YARN: `homework_2/local.env`.
- ResourceManager: `team-17-00`; JobHistory: `team-17-01`; NodeManager: все три внутренних узла.
- Память контейнеров на `nn`, `00`, `01`: 512, 1024, 1536 МБ; по 2 vcores. Контейнеры AM/map/reduce: 512 МБ, heap: 256 МБ.

## Запуск

На edge от пользователя `team`. Для просмотра уже работающего кластера достаточно SSH-туннеля.

```bash
cd /home/team/mashustova
test -f homework_2/local.env || cp homework_2/local.env.example homework_2/local.env
bash homework_2/scripts/stop.sh
bash homework_2/scripts/configure-hosts.sh
bash homework_2/scripts/configure.sh
bash homework_2/scripts/start.sh
```

## Проверка

На edge:

```bash
cd /home/team/mashustova
bash homework_2/scripts/check.sh
```

- 3 NodeManager в состоянии RUNNING.
- Задача `pi 3 1000`: FINISHED/SUCCEEDED, 3 map и 1 reduce в JobHistory.
- Отчет: `homework_2/evidence/yarn-TIMESTAMP.txt`.

## Веб-интерфейсы через SSH

- Указать вместо `~/.ssh/team17` SSH-ключ с доступом к `team@178.236.27.243`.
- Запустить команду в Bash или zsh с OpenSSH. Если порты заняты прежним туннелем, сначала завершить его.

```bash
ssh -N -i ~/.ssh/team17 \
  -o IdentitiesOnly=yes \
  -o ExitOnForwardFailure=yes \
  -o ServerAliveInterval=30 \
  -o ServerAliveCountMax=3 \
  -L 127.0.0.1:9870:10.17.0.11:9870 \
  -L 127.0.0.1:9868:10.17.0.11:9868 \
  -L 127.0.0.1:9864:10.17.0.11:9864 \
  -L 127.0.0.1:9865:10.17.0.12:9864 \
  -L 127.0.0.1:9866:10.17.0.13:9864 \
  -L 127.0.0.1:8088:10.17.0.12:8088 \
  -L 127.0.0.1:8042:10.17.0.11:8042 \
  -L 127.0.0.1:8043:10.17.0.12:8042 \
  -L 127.0.0.1:8044:10.17.0.13:8042 \
  -L 127.0.0.1:19888:10.17.0.13:19888 \
  team@178.236.27.243
```

- Оставить терминал открытым и перейти по нужному адресу в браузере на компьютере.
- Для ссылок на `team-17-*` использовать соответствующий адрес `localhost` из таблицы.

| Интерфейс | Адрес |
|---|---|
| NameNode | http://localhost:9870/dfshealth.html |
| SecondaryNameNode | http://localhost:9868/ |
| DataNode nn | http://localhost:9864/ |
| DataNode 00 | http://localhost:9865/ |
| DataNode 01 | http://localhost:9866/ |
| ResourceManager | http://localhost:8088/cluster |
| NodeManager nn | http://localhost:8042/node |
| NodeManager 00 | http://localhost:8043/node |
| NodeManager 01 | http://localhost:8044/node |
| JobHistory | http://localhost:19888/jobhistory/job/job_1791738599217_0001 |
