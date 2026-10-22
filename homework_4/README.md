# Spark на YARN

Spark читает данные из HDFS, обрабатывает их на YARN и сохраняет таблицу с партициями. Результат читается через Beeline.

## Окружение

Ubuntu 24.04, Spark 4.1.0 bin-hadoop3, Java 17, Python 3.10+, Bash, sudo без пароля. Используются работающие HDFS, YARN и Hive из предыдущих работ.

| Узел | IP | Назначение |
|---|---|---|
| team-17-en | 10.17.0.10 | Запуск скриптов и драйвер Spark |
| team-17-nn | 10.17.0.11 | HDFS, ResourceManager, NodeManager, Hive |
| team-17-00 | 10.17.0.12 | DataNode, NodeManager |
| team-17-01 | 10.17.0.13 | DataNode, NodeManager |

Скрипты выполняются на edge пользователем `team`. Spark работает от `hadoop`. YARN и JobHistory используют Java 11, Hive и Spark - Java 17.

## Параметры

- Hadoop на NN: `/opt/hadoop-3.4.0`, HDFS: `hdfs://team-17-nn:9000`.
- Hive 4.1.0 на NN: `/opt/hive`, Metastore: `thrift://team-17-nn:9083`.
- HiveServer2: `jdbc:hive2://10.17.0.11:10000/default`.
- Java 17 на всех узлах: `/usr/lib/jvm/java-17-openjdk-amd64`.
- SSH с edge на NN: пользователь `team`, ключ `~/.ssh/team_internal`. Другой путь задается через `INTERNAL_KEY`.

Драйвер работает на edge в режиме `client`; остальные узлы подключаются к нему по адресу `10.17.0.10`. Команды от `hadoop` выполняются через `sudo -n -H -u hadoop`.

Для общего Metastore 4.1.0 Spark использует библиотеки Hive с NN и два клиентских JAR Hadoop из своего дистрибутива. Установщик подготавливает их отдельно, а `run.sh` передает пути в Spark. Это нужно, потому что встроенный в Spark клиент Hive имеет другую версию.

## Установка

На edge от `team`, в папке `/home/team/mashustova/homework_4`.

Установка выполняется один раз, если Spark и библиотеки для подключения к Hive еще не подготовлены:

```bash
cd /home/team/mashustova/homework_4
bash scripts/install.sh
```

`install.sh` скачивает Spark 4.1.0, проверяет SHA-512 и устанавливает его в `/home/hadoop/mashustova/platform/spark-4.1.0-bin-hadoop3`. Для установки нужны 4 ГБ свободного места в этом каталоге и 1 ГБ в `/tmp`.

В `/home/hadoop/mashustova/platform/hw4` сохраняются настройки HDFS, YARN, адрес Metastore и библиотеки для подключения к Hive. Их контрольные суммы проверяются перед запуском. Пароль PostgreSQL не копируется, существующая установка Spark не заменяется.

На team-17 Spark уже установлен. Новый расчет начинается с раздела «Запуск».

## Запуск

Исходные данные содержат 15 заказов за три даты. Приложение создает SparkSession с `enableHiveSupport` и читает CSV из HDFS. Затем оставляет завершенные заказы с положительным количеством товара, считает сумму продаж через `DECIMAL` и группирует данные по дате и городу.

Результат сохраняется в Parquet через `partitionBy('dt').saveAsTable(...)`. Таблица появляется в общем Metastore с партициями по дате.

На edge, из папки работы:

```bash
cd /home/team/mashustova/homework_4
bash scripts/run.sh r20261022_02
```

`r20261022_02` - имя запуска. При повторном расчете используется новое имя; без аргумента оно формируется из даты и времени. Допустимы строчные латинские буквы, цифры и `_`, первая буква - латинская, всего до 48 символов.

В этом примере создаются:

- Таблица `dp_mashustova_hw4.daily_sales_r20261022_02`.
- Данные `/user/hadoop/mashustova/hw4/runs/r20261022_02/daily_sales` в HDFS.
- Локальные отчеты и журналы `results/r20261022_02/`.

Каталог базы в HDFS: `/user/hadoop/mashustova/hw4/warehouse`.

Память драйвера на edge - 512 МБ. Для executor выделены 1 ядро, 512 МБ heap и 384 МБ дополнительной памяти; для ApplicationMaster - 256 + 256 МБ. С учетом округления это два контейнера YARN на 1024 и 512 МБ. Автоматическое добавление executor отключено, параллелизм - 2.

## Проверка

`run.sh` сверяет результат с ожидаемыми значениями, читает таблицу и Parquet-файлы через Spark, затем вызывает `spark.stop()`. После завершения Spark проверяется статус `SUCCEEDED` в YARN. Beeline читает таблицу через HiveServer2: сравниваются все восемь строк и три партиции.

На edge, повторная проверка того же запуска. Для нее нужен сохраненный каталог `results/r20261022_02/`:

```bash
cd /home/team/mashustova/homework_4
bash scripts/check.sh r20261022_02
```

Просмотр строк и партиций через HiveServer2, из той же папки на edge:

```bash
source scripts/common.sh
nn_beeline -e 'SELECT dt, city, order_count, total_quantity, revenue FROM dp_mashustova_hw4.daily_sales_r20261022_02;'
nn_beeline -e 'SHOW PARTITIONS dp_mashustova_hw4.daily_sales_r20261022_02;'
```

Отчеты сохраняются в `results/`; эта папка исключена из Git. Проверка исходных данных на локальном компьютере, из папки работы:

```bash
python3 scripts/validate_fixture.py
```

## Результат

22 октября 2026 года, 21:21 МСК, запуск `r20261022_01`, приложение `application_1792691543008_0003`: YARN `SUCCEEDED`. Таблица `dp_mashustova_hw4.daily_sales_r20261022_01` создана через `saveAsTable`; Spark и Beeline прочитали одинаковые ожидаемые значения.

| Показатель | Результат |
|---|---:|
| Входные заказы | 15 |
| Заказы после фильтра | 11 |
| Единицы товара после фильтра | 25 |
| Сумма продаж | 6909.17 |
| Строки результата | 8 |
| Партиции по дате | 3 |

В HDFS получены три Parquet-файла общим размером 4071 байт, по три реплики. Проверка fsck: `HEALTHY`. После расчета контейнеры Spark освобождены, Hive продолжил работу на Java 17.
