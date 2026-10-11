#!/usr/bin/env python3
import argparse
import pathlib
import shlex
import xml.etree.ElementTree as ET

p = argparse.ArgumentParser()
p.add_argument('--output', required=True)
p.add_argument('--rm', default='team-17-00')
p.add_argument('--jhs', default='team-17-01')
p.add_argument('--hadoop-home', default='/opt/hadoop-3.4.0')
p.add_argument('--java-home', default='/usr/lib/jvm/java-11-openjdk-amd64')
p.add_argument('--memory', type=int, default=512)
p.add_argument('--vcores', type=int, default=2)
a = p.parse_args()
if a.memory < 512 or a.memory % 512 or a.vcores < 1:
    p.error('Container budget must be a multiple of 512 MiB; minimum 1 vcore')
out = pathlib.Path(a.output)
out.mkdir(parents=True, exist_ok=True)
def xml(name, properties):
    root = ET.Element('configuration')
    for key, value in properties.items():
        item = ET.SubElement(root, 'property')
        ET.SubElement(item, 'name').text = key
        ET.SubElement(item, 'value').text = str(value)
    ET.indent(root, space='  ')
    ET.ElementTree(root).write(out / name, encoding='utf-8', xml_declaration=True)
xml('yarn-site.xml', {
    'yarn.resourcemanager.hostname': a.rm,
    'yarn.resourcemanager.bind-host': '0.0.0.0',
    'yarn.resourcemanager.webapp.address': f'{a.rm}:8088',
    'yarn.nodemanager.webapp.address': '0.0.0.0:8042',
    'yarn.nodemanager.aux-services': 'mapreduce_shuffle',
    'yarn.nodemanager.aux-services.mapreduce_shuffle.class': 'org.apache.hadoop.mapred.ShuffleHandler',
    'yarn.nodemanager.env-whitelist': 'JAVA_HOME,HADOOP_COMMON_HOME,HADOOP_HDFS_HOME,HADOOP_CONF_DIR,CLASSPATH_PREPEND_DISTCACHE,HADOOP_YARN_HOME,HADOOP_HOME,PATH,LANG,TZ,HADOOP_MAPRED_HOME',
    'yarn.nodemanager.resource.memory-mb': a.memory,
    'yarn.nodemanager.resource.cpu-vcores': a.vcores,
    'yarn.scheduler.minimum-allocation-mb': 512,
    'yarn.scheduler.maximum-allocation-mb': 1536,
    'yarn.scheduler.maximum-allocation-vcores': a.vcores,
    'yarn.nodemanager.local-dirs': '/data/hadoop/yarn/local',
    'yarn.nodemanager.log-dirs': '/data/hadoop/yarn/logs',
    'yarn.nodemanager.vmem-check-enabled': 'false',
    'yarn.log-aggregation-enable': 'true',
    'yarn.log-aggregation.retain-seconds': 604800,
    'yarn.nodemanager.remote-app-log-dir': '/yarn-logs',
    'yarn.log.server.url': f'http://{a.jhs}:19888/jobhistory/logs',
})
xml('mapred-site.xml', {
    'mapreduce.framework.name': 'yarn',
    'mapreduce.application.classpath': '$HADOOP_MAPRED_HOME/share/hadoop/mapreduce/*:$HADOOP_MAPRED_HOME/share/hadoop/mapreduce/lib/*',
    'mapreduce.map.env': f'JAVA_HOME={a.java_home},HADOOP_MAPRED_HOME={a.hadoop_home}',
    'mapreduce.reduce.env': f'JAVA_HOME={a.java_home},HADOOP_MAPRED_HOME={a.hadoop_home}',
    'yarn.app.mapreduce.am.env': f'JAVA_HOME={a.java_home},HADOOP_MAPRED_HOME={a.hadoop_home}',
    'yarn.app.mapreduce.am.resource.mb': 512,
    'yarn.app.mapreduce.am.command-opts': '-Xmx256m',
    'mapreduce.map.memory.mb': 512,
    'mapreduce.map.java.opts': '-Xmx256m',
    'mapreduce.reduce.memory.mb': 512,
    'mapreduce.reduce.java.opts': '-Xmx256m',
    'mapreduce.jobhistory.address': f'{a.jhs}:10020',
    'mapreduce.jobhistory.webapp.address': f'{a.jhs}:19888',
    'mapreduce.jobhistory.bind-host': '0.0.0.0',
    'mapreduce.jobhistory.intermediate-done-dir': '/mr-history/tmp',
    'mapreduce.jobhistory.done-dir': '/mr-history/done',
})
env = f'''export JAVA_HOME={shlex.quote(a.java_home)}
export HADOOP_HOME={shlex.quote(a.hadoop_home)}
export HADOOP_MAPRED_HOME="$HADOOP_HOME"
export HADOOP_COMMON_HOME="$HADOOP_HOME"
export HADOOP_HDFS_HOME="$HADOOP_HOME"
export HADOOP_YARN_HOME="$HADOOP_HOME"
export HADOOP_LOG_DIR=/data/hadoop/logs
export HADOOP_PID_DIR=/data/hadoop/pids
'''
(out / 'yarn-env.sh').write_text(env + 'export YARN_RESOURCEMANAGER_OPTS="-Xmx512m"\nexport YARN_NODEMANAGER_OPTS="-Xmx256m"\n')
(out / 'mapred-env.sh').write_text(env + 'export MAPRED_HISTORYSERVER_OPTS="-Xmx256m"\n')
