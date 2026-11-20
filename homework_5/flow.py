import argparse
from contextlib import contextmanager
from datetime import datetime, timezone
import fcntl
import getpass
import json
import os
from pathlib import Path
import re
import signal
import socket
import subprocess
import sys
import uuid
from urllib.parse import urlparse

from prefect import flow, task
from prefect.context import get_run_context
from prefect.settings import (PREFECT_API_KEY, PREFECT_API_URL,
                              PREFECT_SERVER_ANALYTICS_ENABLED, temporary_settings)


ROOT = Path(__file__).resolve().parent
STATE_DIR = Path.home() / '.local/state/team17-hw5'
CLEANUP_GRACE_SECONDS = 180
STEPS = ('preflight', 'stage_input', 'spark_etl', 'verify_result')
SCRIPTS = {'preflight': 'preflight.sh', 'stage_input': 'stage_input.sh',
           'spark_etl': 'spark_etl.sh', 'verify_result': 'check.sh'}


class RunInterrupted(Exception):
    pass


def utc_now():
    return datetime.now(timezone.utc).isoformat()


def validate_run_id(value):
    if not re.fullmatch(r'[a-z][a-z0-9_]{0,47}', value):
        raise ValueError('Run ID must start with a lowercase letter and contain at most 48 lowercase letters, digits or underscores')
    return value


def new_run_id():
    return 'r' + datetime.now(timezone.utc).strftime('%Y%m%d_%H%M%S_') + uuid.uuid4().hex[:12]


def require_edge():
    if getpass.getuser() != 'team' or socket.gethostname().split('.')[0] != 'team-17-en':
        raise RuntimeError('Run as team on team-17-en; this command does not run on the local Mac')


@contextmanager
def run_lock():
    STATE_DIR.mkdir(mode=0o700, parents=True, exist_ok=True)
    path = STATE_DIR / 'run.lock'
    with path.open('a+') as lock:
        os.chmod(path, 0o600)
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError as error:
            raise RuntimeError('Another HW5 flow is running; wait for it to finish') from error
        try:
            yield
        finally:
            fcntl.flock(lock, fcntl.LOCK_UN)


def report_path(run_id):
    return ROOT / 'results' / validate_run_id(run_id) / 'flow-report.json'


def save_report(run_id, report):
    path = report_path(run_id)
    temporary = path.with_suffix('.tmp')
    temporary.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
    temporary.replace(path)


def update_report(run_id, **fields):
    report = json.loads(report_path(run_id).read_text())
    report.update(fields)
    save_report(run_id, report)
    return report


def reserve_run(run_id):
    directory = ROOT / 'results' / validate_run_id(run_id)
    directory.parent.mkdir(exist_ok=True)
    directory.mkdir(mode=0o700)
    save_report(run_id, {
        'run_id': run_id,
        'status': 'prepared',
        'started_at_utc': utc_now(),
        'steps': [],
        'table': 'dp_mashustova_hw5.daily_sales_' + run_id,
        'output_uri': 'hdfs://team-17-nn:9000/user/hadoop/mashustova/hw5/runs/' + run_id + '/daily_sales',
        'artifacts': {
            'spark_report': 'spark-report.json',
            'spark_log': 'spark-submit.log',
            'yarn_status': 'yarn-status.txt',
            'hive_rows': 'hive-rows.tsv',
            'hive_partitions': 'hive-partitions.tsv',
            'verification': 'verification.json',
        },
    })


def interrupt_run(signum, _frame):
    raise RunInterrupted('Received ' + signal.Signals(signum).name)


@contextmanager
def signal_handlers():
    previous = {sig: signal.signal(sig, interrupt_run) for sig in (signal.SIGTERM, signal.SIGINT)}
    try:
        yield
    finally:
        for sig, handler in previous.items():
            signal.signal(sig, handler)


def stop_subprocess(process):
    if process.poll() is not None:
        return
    try:
        os.killpg(process.pid, signal.SIGTERM)
    except ProcessLookupError:
        return
    try:
        process.wait(timeout=CLEANUP_GRACE_SECONDS)
    except subprocess.TimeoutExpired as error:
        os.killpg(process.pid, signal.SIGKILL)
        process.wait()
        raise RuntimeError('Backend did not stop within 180 seconds; YARN cleanup is unconfirmed. Inspect this run and run scripts/cleanup.sh RUN_ID on edge before starting another flow') from error


def run_script(step, run_id):
    validate_run_id(run_id)
    script = ROOT / 'scripts' / SCRIPTS[step]
    log_path = ROOT / 'results' / run_id / (step + '.log')
    with log_path.open('w') as output:
        process = subprocess.Popen(['bash', str(script), run_id], cwd=ROOT,
                                   stdout=output, stderr=subprocess.STDOUT, start_new_session=True)
        try:
            return_code = process.wait()
        except BaseException:
            previous = {sig: signal.signal(sig, signal.SIG_IGN) for sig in (signal.SIGTERM, signal.SIGINT)}
            try:
                stop_subprocess(process)
            finally:
                for sig, handler in previous.items():
                    signal.signal(sig, handler)
            raise
    if return_code:
        raise subprocess.CalledProcessError(return_code, ['bash', str(script), run_id])
    return str(log_path)


def execute_step(step, run_id):
    context = get_run_context()
    report = json.loads(report_path(run_id).read_text())
    record = {'name': step, 'status': 'running', 'started_at_utc': utc_now(),
              'prefect_task_run_id': str(context.task_run.id), 'log': step + '.log'}
    report['steps'].append(record)
    save_report(run_id, report)
    try:
        run_script(step, run_id)
    except BaseException as error:
        record.update(status='failed', finished_at_utc=utc_now(), error=str(error))
        save_report(run_id, report)
        raise
    record.update(status='completed', finished_at_utc=utc_now())
    save_report(run_id, report)
    return run_id


@task(name='preflight', retries=0, cache_policy=None)
def preflight(run_id):
    return execute_step('preflight', run_id)


@task(name='stage_input', retries=0, cache_policy=None)
def stage_input(run_id):
    return execute_step('stage_input', run_id)


@task(name='spark_etl', retries=0, cache_policy=None)
def spark_etl(run_id):
    return execute_step('spark_etl', run_id)


@task(name='verify_result', retries=0, cache_policy=None)
def verify_result(run_id):
    return execute_step('verify_result', run_id)


@flow(name='team17-hw5-daily-sales', retries=0)
def hw5_pipeline(run_id):
    context = get_run_context()
    update_report(run_id, status='running', prefect_flow_run_id=str(context.flow_run.id))
    prepared = preflight(run_id)
    staged = stage_input(prepared)
    computed = spark_etl(staged)
    verified = verify_result(computed)
    directory = ROOT / 'results' / verified
    spark_report = json.loads((directory / 'spark-report.json').read_text())
    verification = json.loads((directory / 'verification.json').read_text())
    expected = {'status': 'PASS', 'run_id': verified,
                'application_id': spark_report['application_id'],
                'table': 'dp_mashustova_hw5.daily_sales_' + verified,
                'yarn_final_state': 'SUCCEEDED', 'spark_stopped': True,
                'hdfs_fsck': 'HEALTHY', 'beeline_exact_match': True}
    if (not (directory / 'verified.ok').is_file()
            or any(verification.get(key) != value for key, value in expected.items())
            or spark_report['table'] != expected['table']):
        raise ValueError('Backend artifacts do not confirm a verified HW5 result')
    return {'run_id': verified, 'application_id': spark_report['application_id'], 'table': spark_report['table']}


def execute_run(run_id=None):
    require_edge()
    run_id = validate_run_id(run_id or new_run_id())
    with run_lock():
        reserve_run(run_id)
        try:
            result = hw5_pipeline(run_id)
            update_report(run_id, status='completed', finished_at_utc=utc_now(),
                          application_id=result['application_id'], table=result['table'])
        except BaseException as error:
            update_report(run_id, status='failed', finished_at_utc=utc_now(),
                          error_type=type(error).__name__, error=str(error))
            raise
    return result


def main():
    parser = argparse.ArgumentParser(description='Run the HW5 Prefect flow on team-17 edge')
    parser.add_argument('--run-id')
    args = parser.parse_args()
    try:
        require_edge()
        api_url = os.environ.get('PREFECT_API_URL', 'http://127.0.0.1:4200/api')
        parsed = urlparse(api_url)
        if parsed.scheme != 'http' or parsed.hostname not in ('127.0.0.1', 'localhost', '::1') or parsed.path.rstrip('/') != '/api' or parsed.username or parsed.password or parsed.query or parsed.fragment:
            raise ValueError('PREFECT_API_URL must point to a local HTTP Prefect server ending in /api')
        with temporary_settings({PREFECT_API_URL: api_url, PREFECT_API_KEY: None,
                                 PREFECT_SERVER_ANALYTICS_ENABLED: False}), signal_handlers():
            result = execute_run(args.run_id)
        print(json.dumps(result, indent=2))
        return 0
    except (Exception, KeyboardInterrupt) as error:
        print(str(error), file=sys.stderr)
        return 1


if __name__ == '__main__':
    raise SystemExit(main())
