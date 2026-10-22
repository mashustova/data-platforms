import argparse
import csv
import io
import json
from pathlib import Path
import queue
import subprocess
import threading
import time


def check_clients(command, query, output, timeout=120):
    events = queue.Queue()
    clients = []
    readers = []
    transcripts = [[], []]

    def read(index, stream):
        for line in stream:
            events.put((index, line))
        events.put((index, None))

    try:
        for index in range(2):
            client = subprocess.Popen(command, stdin=subprocess.PIPE,
                                      stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, bufsize=1)
            clients.append(client)
            reader = threading.Thread(target=read, args=(index, client.stdout), daemon=True)
            reader.start()
            readers.append(reader)
            client.stdin.write(f"SELECT 'hw3_client_{index + 1}_ready';\n")
            client.stdin.flush()
        ready = set()
        deadline = time.monotonic() + timeout
        while len(ready) < 2:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise RuntimeError('Both Hive clients did not become ready before the deadline')
            try:
                index, line = events.get(timeout=remaining)
            except queue.Empty:
                raise RuntimeError('Timed out waiting for concurrent Hive sessions') from None
            if line is None:
                raise RuntimeError(f'Client {index + 1} exited before both sessions were open')
            transcripts[index].append(line)
            if line.strip() == f'hw3_client_{index + 1}_ready':
                ready.add(index)
        if any(client.poll() is not None for client in clients):
            raise RuntimeError('A client closed before the concurrency barrier')
        for client in clients:
            client.stdin.write(query.rstrip() + '\n!quit\n')
            client.stdin.close()
        for client in clients:
            if client.wait(timeout=max(1, deadline - time.monotonic())):
                raise RuntimeError('A Hive client returned a failure exit code')
        for reader in readers:
            reader.join(timeout=3)
        while not events.empty():
            index, line = events.get_nowait()
            if line is not None:
                transcripts[index].append(line)
    finally:
        for client in clients:
            if client.poll() is None:
                client.terminate()
                try:
                    client.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    client.kill()
                    client.wait()
        for reader in readers:
            reader.join(timeout=3)
        while not events.empty():
            index, line = events.get_nowait()
            if line is not None:
                transcripts[index].append(line)
        output.mkdir(parents=True, exist_ok=True)
        for index, lines in enumerate(transcripts, start=1):
            (output / f'client-{index}.txt').write_text(''.join(lines))
    return transcripts


def verify_rows(transcript, source):
    expected = sorted((row['order_id'], row['city'], row['category'], row['quantity'],
                       row['unit_price'], row['status'], row['event_date']) for row in source)
    actual = []
    for line in transcript:
        fields = line.rstrip('\r\n').split('\t')
        if len(fields) == 7 and fields[0].isdigit():
            actual.append(tuple(fields))
    from decimal import Decimal
    normalize = lambda rows: sorted((int(r[0]), r[1], r[2], int(r[3]), Decimal(r[4]), r[5], r[6]) for r in rows)
    if normalize(actual) != normalize(expected):
        raise RuntimeError('Hive rows differ from the source fixture')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--data', type=Path, required=True)
    parser.add_argument('--query', type=Path, required=True)
    parser.add_argument('--java-home', required=True)
    parser.add_argument('--hadoop-home', required=True)
    parser.add_argument('--hive-home', required=True)
    parser.add_argument('--jdbc', required=True)
    args = parser.parse_args()
    command = ['sudo', '-n', '-H', '-u', 'hadoop', 'env', f'JAVA_HOME={args.java_home}',
               f'HADOOP_HOME={args.hadoop_home}', f'HADOOP_CONF_DIR={args.hadoop_home}/etc/hadoop',
               f'HIVE_HOME={args.hive_home}', f'HIVE_CONF_DIR={args.hive_home}/conf',
               'HADOOP_HEAPSIZE=256', 'HADOOP_CLIENT_OPTS=-Xmx256m',
               'timeout', '150', f'{args.hive_home}/bin/beeline', '-u', args.jdbc, '-n', 'hadoop',
               '--silent=true', '--showHeader=false', '--outputformat=tsv2', '--color=false', '--force=false']
    transcripts = check_clients(command, args.query.read_text(), args.output)
    source = list(csv.DictReader(io.StringIO(args.data.read_text())))
    for transcript in transcripts:
        verify_rows(transcript, source)
    result = {'concurrent_clients': 2, 'rows_per_client': len(source), 'status': 'PASS'}
    (args.output / 'result.json').write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps(result))


if __name__ == '__main__':
    main()
