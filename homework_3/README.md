# Hive

В работе используются отдельный сервер Hive и два одновременных клиента. Данные загружаются в таблицу с партициями по дате.

## Окружение

Ubuntu 24.04, Hadoop 3.4.0, Hive 4.1.0, Java 17, PostgreSQL 16, Bash, sudo без пароля. Используется работающий HDFS.

Команды выполняются на `team-17-nn` пользователем `team`. Hive работает от `hadoop`. В карточке рекомендован Hive 4.0.0-alpha2; на стенде уже установлен и проверен Hive 4.1.0, поэтому работа выполнена с ним.

## Параметры

| Компонент | Путь или адрес |
|---|---|
| Hadoop | `/opt/hadoop-3.4.0` |
| Hive | `/opt/hive` |
| Java | `/usr/lib/jvm/java-17-openjdk-amd64` |
| Metastore | `thrift://team-17-nn:9083` |
| HiveServer2 | `jdbc:hive2://10.17.0.11:10000/default` |
| PostgreSQL | База `hive_metastore`, роль `hive` на NN |

Metastore хранит описание таблиц в PostgreSQL. Клиенты подключаются к HiveServer2 через Beeline. Оба сервиса работают отдельными процессами.

Таблица работы: `dp_mashustova_hw3.orders`. Каталог данных в HDFS: `/user/hadoop/mashustova/hw3`.

## Установка Hive

Раздел относится к новой установке на NN с подготовленными Hadoop, HDFS и пользователем `hadoop`. На team-17 Hive уже работал, поэтому установка с нуля по этим командам не выполнялась. Для существующего стенда работа начинается с раздела «Загрузка данных».

### Подготовка

На NN от `team`, в одной Bash-сессии. Блоки выполняются по порядку; при ошибке сеанс завершается:

```bash
set -euo pipefail
sudo apt-get update
sudo apt-get install -y openjdk-17-jdk-headless postgresql-16 postgresql-client-16 libpostgresql-jdbc-java curl ca-certificates
id hadoop
```

Hadoop находится в `/opt/hadoop-3.4.0`. Команды ниже устанавливают Hive в свободный каталог и не форматируют HDFS.

Загрузка Hive и проверка SHA-256 по официальной контрольной сумме:

```bash
stage=$(mktemp -d /tmp/hive-bootstrap.XXXXXX)
curl --fail --location https://archive.apache.org/dist/hive/hive-4.1.0/apache-hive-4.1.0-bin.tar.gz -o "$stage/hive.tar.gz"
printf '%s  %s\n' 9d160af85f0f44ea7e0ccaf0a8c876e36ac35abfd9f8c506504a11e6daaff9aa "$stage/hive.tar.gz" | sha256sum -c -
test ! -e /opt/hive
test ! -e /opt/apache-hive-4.1.0-bin
sudo tar -xzf "$stage/hive.tar.gz" -C /opt
sudo chown -R hadoop:hadoop /opt/apache-hive-4.1.0-bin
sudo ln -s /opt/apache-hive-4.1.0-bin /opt/hive
sudo install -o hadoop -g hadoop -m 640 /usr/share/java/postgresql.jar /opt/hive/lib/postgresql-jdbc.jar
```

### PostgreSQL и конфигурация

В PostgreSQL создаются роль `hive` и пустая база `hive_metastore`. Metastore обращается к базе с того же NN. Команда `createuser` запрашивает пароль:

```bash
sudo systemctl start postgresql
pg_isready -h localhost -p 5432
sudo -H -u postgres createuser --pwprompt hive
sudo -H -u postgres createdb -O hive hive_metastore
```

На NN, из папки работы. Здесь вводится тот же пароль роли `hive`:

```bash
cd /home/team/mashustova/homework_3
read -r -s -p 'Metastore password: ' metastore_password
printf '\n'
printf '%s' "$metastore_password" | python3 scripts/render.py --output "$stage/conf" --password-stdin
unset metastore_password
sudo install -o hadoop -g hadoop -m 600 "$stage/conf/hive-site.xml" /opt/hive/conf/hive-site.xml
sudo install -o hadoop -g hadoop -m 600 "$stage/conf/hive-env.sh" /opt/hive/conf/hive-env.sh
```

`render.py` создает настройки подключения к PostgreSQL, Metastore и HiveServer2. Пароль записывается в `hive-site.xml`, доступный только владельцу. Файлы сначала создаются во временной папке, затем копируются в `/opt/hive/conf`. Другие адреса и пути задаются параметрами скрипта; их описание доступно через `python3 scripts/render.py --help`.

Создание каталогов HDFS и таблиц Metastore в новой пустой базе:

```bash
source scripts/common.sh
client_hdfs dfs -mkdir -p /tmp/hive /user/hive/warehouse
client_hdfs dfs -chmod 700 /tmp/hive
schema_tables=$(sudo -H -u postgres psql -X -A -t -d hive_metastore -c "SELECT count(*) FROM information_schema.tables WHERE table_schema='public' AND table_type='BASE TABLE'")
test "$schema_tables" = 0
hive_hadoop /opt/hive/bin/schematool -dbType postgres -initSchema
hive_hadoop /opt/hive/bin/schematool -dbType postgres -info
hive_hadoop /opt/hive/bin/schematool -dbType postgres -validate
```

`-initSchema` используется только для пустой базы. Для существующей базы выполняются проверка схемы и, при необходимости, отдельное обновление.

### Запуск

Metastore и HiveServer2 запускаются как службы от `hadoop`. На новой установке, где этих служб еще нет:

```bash
test ! -e /etc/systemd/system/hive-metastore.service
test ! -e /etc/systemd/system/hive-hiveserver2.service
sudo install -m 644 configs/hive-metastore.service.example /etc/systemd/system/hive-metastore.service
sudo install -m 644 configs/hive-hiveserver2.service.example /etc/systemd/system/hive-hiveserver2.service
sudo systemctl daemon-reload
sudo systemctl start hive-metastore
sudo systemctl start hive-hiveserver2
systemctl is-active hive-metastore hive-hiveserver2
beeline_cmd -e 'SET hive.metastore.uris;'
beeline_cmd -e "SELECT 'hive_ready';"
```

Сначала запускается Metastore, затем HiveServer2. Запрос `SET hive.metastore.uris` показывает адрес общего Metastore. Журналы служб доступны через `sudo journalctl -u hive-metastore` и `sudo journalctl -u hive-hiveserver2`.

Для чтения маленькой таблицы используется fetch task: Hive возвращает строки без запуска задания MapReduce. На team-17 это проверено с Hadoop 3.4.0. В документации Hive 4.1.0 указан Hadoop 3.4.1; вычисления через MapReduce или Tez в этой работе не проверялись.

После установки временная папка `$stage` с архивом и копиями настроек больше не нужна. Установленный Hive и данные остаются в своих каталогах.

## Загрузка данных

На NN от `team`, папка работы `/home/team/mashustova/homework_3`. В `local.env.example` сохранены параметры team-17. Для другого кластера в `local.env` указываются его проверенный clusterID, адреса и пути.

```bash
cd /home/team/mashustova/homework_3
test -f local.env || cp local.env.example local.env
source scripts/common.sh
require_hive_installation
require_hdfs_cluster
systemctl is-active hive-metastore.service hive-hiveserver2.service
run_hadoop python3 - "$HIVE_HOME/conf/hive-site.xml" "$METASTORE_URI" "$HIVE_HOST" "$METASTORE_DB" "$METASTORE_USER" < scripts/validate_config.py
schema=$(sudo -n -H -u postgres psql -X -A -t -d "$METASTORE_DB" -v ON_ERROR_STOP=1 -c 'SELECT "SCHEMA_VERSION" FROM "VERSION";')
test "$schema" = 4.1.0
beeline_cmd -e "SELECT 'hive_ready';"
bash scripts/load.sh
```

`load.sh` создает внешнюю таблицу и загружает три партиции через `LOAD DATA LOCAL ... OVERWRITE`. Исходные данные содержат 15 заказов, разделенных по датам. В файлах для загрузки нет заголовка и столбца даты: дата задается партицией `dt`.

`LOCAL` читает файлы на узле HiveServer2, поэтому скрипт копирует их в `/home/hadoop/mashustova/hw3` на NN. Перед записью проверяются clusterID, схема и путь таблицы. Повторная загрузка заменяет три партиции этой таблицы.

## Проверка

На NN от `team`:

```bash
cd /home/team/mashustova/homework_3
bash scripts/check.sh
```

`check.sh` открывает две одновременные сессии Beeline и читает таблицу из каждой. Все значения 15 строк сравниваются с исходным CSV. Также проверяются три партиции и `fsck HEALTHY`. Отчеты сохраняются в `evidence/`.

Просмотр партиций и строк на NN, в той же Bash-сессии:

```bash
beeline_cmd -e 'SHOW PARTITIONS dp_mashustova_hw3.orders;'
run_sql sql/read-orders.hql
```

## Результат

22 октября 2026 года, 20:29 МСК: две одновременно открытые Beeline-сессии прочитали по 15 строк, все значения совпали с исходным CSV. Загружены `dt=2026-10-01`, `dt=2026-10-02`, `dt=2026-10-03`, по 5 строк. HDFS fsck: HEALTHY, три файла по три реплики. Службы Hive остались работать; клиенты завершились после чтения.
