SET hive.stats.autogather=false;
SET hive.stats.column.autogather=false;
CREATE DATABASE IF NOT EXISTS dp_mashustova_hw3
LOCATION '${hiveconf:hw3_root}/database';

CREATE EXTERNAL TABLE IF NOT EXISTS dp_mashustova_hw3.orders (
    order_id BIGINT,
    city STRING,
    category STRING,
    quantity INT,
    unit_price DECIMAL(10,2),
    status STRING
)
PARTITIONED BY (dt STRING)
ROW FORMAT DELIMITED
FIELDS TERMINATED BY ','
STORED AS TEXTFILE
LOCATION '${hiveconf:hw3_root}/orders'
TBLPROPERTIES ('external.table.purge'='false');
