#!/usr/bin/env python3
"""Render optional Hive 4.1.0 bootstrap templates in a staging directory; adoption does not apply them."""

import argparse
import os
from pathlib import Path
import shlex
import sys
import xml.etree.ElementTree as ET


def parse_args():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--hadoop-home", default="/opt/hadoop-3.4.0")
    parser.add_argument("--java-home", default="/usr/lib/jvm/java-17-openjdk-amd64")
    parser.add_argument("--hive-home", default="/opt/hive")
    parser.add_argument("--host", default="team-17-nn")
    parser.add_argument("--db-name", default="hive_metastore")
    parser.add_argument("--db-user", default="hive")
    parser.add_argument("--warehouse", default="hdfs://team-17-nn:9000/user/hive/warehouse")
    parser.add_argument("--password-stdin", required=True, action="store_true")
    return parser.parse_args()


def write_private(path, content):
    descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(descriptor, "w", encoding="utf-8") as stream:
        os.fchmod(stream.fileno(), 0o600)
        stream.write(content)


def render(args, password):
    warehouse = args.warehouse.rstrip("/")
    scratch = "/tmp/hive"
    properties = {
        "javax.jdo.option.ConnectionURL": "jdbc:postgresql://127.0.0.1:5432/" + args.db_name,
        "javax.jdo.option.ConnectionDriverName": "org.postgresql.Driver",
        "javax.jdo.option.ConnectionUserName": args.db_user,
        "javax.jdo.option.ConnectionPassword": password,
        "hive.metastore.db.type": "POSTGRES",
        "hive.metastore.uris": "thrift://" + args.host + ":9083",
        "hive.metastore.thrift.bind.host": args.host,
        "hive.metastore.port": "9083",
        "hive.metastore.schema.verification": "true",
        "datanucleus.schema.autoCreateAll": "false",
        "hive.metastore.try.direct.sql.ddl": "false",
        "hive.metastore.warehouse.dir": warehouse,
        "hive.server2.thrift.bind.host": args.host,
        "hive.server2.thrift.port": "10000",
        "hive.server2.transport.mode": "binary",
        "hive.server2.authentication": "NONE",
        "hive.server2.enable.doAs": "false",
        "hive.execution.engine": "mr",
        "hive.fetch.task.conversion": "more",
        "hive.fetch.task.conversion.threshold": "10485760",
        "hive.cbo.enable": "false",
        "hive.stats.autogather": "false",
        "hive.stats.column.autogather": "false",
        "hive.exec.scratchdir": scratch,
        "hive.cli.print.header": "false",
    }
    configuration = ET.Element("configuration")
    for name, value in properties.items():
        prop = ET.SubElement(configuration, "property")
        ET.SubElement(prop, "name").text = name
        ET.SubElement(prop, "value").text = value
    ET.indent(configuration, space="  ")
    xml = '<?xml version="1.0" encoding="UTF-8"?>\n' + ET.tostring(configuration, encoding="unicode") + "\n"
    environment = {
        "JAVA_HOME": args.java_home,
        "HADOOP_HOME": args.hadoop_home,
        "HADOOP_CONF_DIR": args.hadoop_home.rstrip("/") + "/etc/hadoop",
        "HIVE_CONF_DIR": args.hive_home.rstrip("/") + "/conf",
    }
    shell = "\n".join("export " + key + "=" + shlex.quote(value) for key, value in environment.items()) + "\n"
    if args.output.resolve().is_relative_to(Path(args.hive_home).resolve()):
        raise ValueError("Use a staging directory outside the installed Hive tree")
    args.output.mkdir(parents=True, exist_ok=True)
    write_private(args.output / "hive-site.xml", xml)
    write_private(args.output / "hive-env.sh", shell)


def main():
    args = parse_args()
    password = sys.stdin.read().rstrip("\r\n")
    if not password or "\n" in password or "\r" in password:
        raise SystemExit("A non-empty, single-line password must be supplied on stdin.")
    render(args, password)


if __name__ == "__main__":
    main()
