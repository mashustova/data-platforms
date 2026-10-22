import argparse
import json
import re
from pathlib import Path
from urllib.parse import urlparse

from pyspark.sql import SparkSession, functions as F, types as T


def normalized_rows(frame):
    rows = frame.orderBy('dt', 'city').limit(101).collect()
    if len(rows) > 100:
        raise ValueError('This fixture check supports at most 100 aggregate rows')
    return [dict(dt=str(r.dt), city=r.city, order_count=r.order_count,
                 total_quantity=r.total_quantity, revenue=str(r.revenue)) for r in rows]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--input', required=True)
    parser.add_argument('--output', required=True)
    parser.add_argument('--expected', required=True)
    parser.add_argument('--table', required=True)
    parser.add_argument('--report', required=True)
    args = parser.parse_args()
    for path in (args.input, args.output):
        if urlparse(path).scheme != 'hdfs':
            raise ValueError('Input and output must use explicit hdfs:// URIs')
    if not re.fullmatch(r'dp_mashustova_hw4[.]daily_sales_[a-z][a-z0-9_]{0,47}', args.table):
        raise ValueError('Use a unique table in the personal homework database')
    if not re.fullmatch(r'hdfs://team-17-nn:9000/user/hadoop/mashustova/hw4/runs/[a-z][a-z0-9_]{0,47}/daily_sales', args.output):
        raise ValueError('Output must be the personal run path')
    expected = json.loads(Path(args.expected).read_text())
    spark = (SparkSession.builder.appName('team17-hw4-daily-sales')
             .config('spark.sql.catalogImplementation', 'hive')
             .config('spark.sql.hive.metastore.version', '4.1.0')
             .config('spark.hadoop.hive.metastore.uris', 'thrift://team-17-nn:9083')
             .config('spark.sql.ansi.enabled', 'true')
             .config('spark.sql.parquet.writeLegacyFormat', 'true')
             .enableHiveSupport().getOrCreate())
    try:
        sc = spark.sparkContext
        if spark.version != '4.1.0':
            raise ValueError('Use the pinned Spark4.1.0 distribution')
        if spark.conf.get('spark.sql.catalogImplementation') != 'hive':
            raise ValueError('Hive catalog must be enabled')
        if spark.conf.get('spark.sql.hive.metastore.jars') != 'path':
            raise ValueError('Use the prepared isolated Hive4.1.0 client classpath')
        if sc._jsc.hadoopConfiguration().get('hive.metastore.uris') != 'thrift://team-17-nn:9083':
            raise ValueError('Refusing local/embedded or another metastore')
        if sc.master != 'yarn':
            raise ValueError('Submit this application with --master yarn')
        report = {'application_id': sc.applicationId, 'master': sc.master,
                  'spark_version': spark.version, 'input': args.input,
                  'output': args.output, 'table': args.table, 'metastore_uri': 'thrift://team-17-nn:9083',
                  'metastore_version': '4.1.0', 'status': 'started'}
        Path(args.report).write_text(json.dumps(report, indent=2) + '\n')
        print('APPLICATION_ID=' + sc.applicationId, flush=True)
        schema = T.StructType([
            T.StructField('order_id', T.LongType()),
            T.StructField('event_date', T.DateType()),
            T.StructField('city', T.StringType()),
            T.StructField('category', T.StringType()),
            T.StructField('quantity', T.IntegerType()),
            T.StructField('unit_price', T.DecimalType(12, 2)),
            T.StructField('status', T.StringType()),
        ])
        orders = (spark.read.schema(schema).option('header', 'true')
                  .option('mode', 'FAILFAST').option('dateFormat', 'yyyy-MM-dd')
                  .csv(args.input)).cache()
        if orders.filter(F.expr(' OR '.join(f'{c} IS NULL' for c in orders.columns))).limit(1).count():
            raise ValueError('Input contains missing or invalid values')
        source_count = orders.count()
        if source_count != expected['source']['order_count']:
            raise ValueError('Unexpected input row count')
        completed = orders.filter((F.col('status') == 'completed') & (F.col('quantity') > 0))
        filtered_count = completed.count()
        if filtered_count != expected['filtered']['order_count']:
            raise ValueError('Unexpected filtered row count')
        enriched = (completed.withColumn('dt', F.date_format('event_date', 'yyyy-MM-dd'))
                    .withColumn('amount', (F.col('quantity') * F.col('unit_price')).cast('decimal(14,2)')))
        result = (enriched.groupBy('dt', 'city')
                  .agg(F.count('*').alias('order_count'),
                       F.sum('quantity').cast('bigint').alias('total_quantity'),
                       F.sum('amount').cast('decimal(14,2)').alias('revenue'))
                  .select('city', 'order_count', 'total_quantity', 'revenue', 'dt'))
        result_rows = normalized_rows(result)
        if result_rows != expected['daily_sales']:
            raise ValueError('Spark aggregate differs from independently calculated fixture')
        database_uri = 'hdfs://team-17-nn:9000/user/hadoop/mashustova/hw4/warehouse'
        spark.sql("CREATE DATABASE IF NOT EXISTS dp_mashustova_hw4 LOCATION '" + database_uri + "'")
        db_metadata = {r.info_name: r.info_value for r in spark.sql('DESCRIBE DATABASE EXTENDED dp_mashustova_hw4').collect()}
        if db_metadata.get('Location', '').rstrip('/') != database_uri:
            raise ValueError('Personal database already exists at another location; inspect before retrying')
        if spark.catalog.tableExists(args.table):
            raise ValueError('Table exists; use a new run ID')
        output_path = sc._jvm.org.apache.hadoop.fs.Path(args.output)
        if output_path.getFileSystem(sc._jsc.hadoopConfiguration()).exists(output_path):
            raise ValueError('Output exists; use a new run ID')
        (result.write.format('parquet').mode('errorifexists')
         .option('path', args.output).partitionBy('dt').saveAsTable(args.table))
        catalog_rows = normalized_rows(spark.table(args.table))
        if catalog_rows != expected['daily_sales']:
            raise ValueError('Hive catalog readback differs from the fixture')
        table_metadata = {r.col_name: r.data_type for r in spark.sql('DESCRIBE FORMATTED ' + args.table).collect()}
        if table_metadata.get('Location', '').rstrip('/') != args.output:
            raise ValueError('Registered table location differs from the run output')
        output_schema = T.StructType([
            T.StructField('city', T.StringType()),
            T.StructField('order_count', T.LongType()),
            T.StructField('total_quantity', T.LongType()),
            T.StructField('revenue', T.DecimalType(14, 2)),
            T.StructField('dt', T.StringType()),
        ])
        saved = spark.read.schema(output_schema).parquet(args.output)
        saved_rows = normalized_rows(saved)
        if saved_rows != expected['daily_sales']:
            raise ValueError('Parquet readback differs from expected rows')
        report.update(status='verified_hive_table_and_parquet', source_count=source_count,
                      filtered_count=filtered_count, daily_sales=saved_rows,
                      schema=saved.schema.jsonValue(), hive_catalog_rows=catalog_rows,
                      table_location=table_metadata['Location'])
        Path(args.report).write_text(json.dumps(report, indent=2) + '\n')
        print(json.dumps(report, indent=2), flush=True)
    finally:
        spark.stop()
        report_path = Path(args.report)
        if report_path.exists():
            final_report = json.loads(report_path.read_text())
            final_report['spark_stopped'] = True
            report_path.write_text(json.dumps(final_report, indent=2) + '\n')


if __name__ == '__main__':
    main()
