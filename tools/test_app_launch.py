#!/usr/bin/env python3
"""Launch the real app twice with isolated idle data; the second must exit."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import tempfile
import time


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--binary', required=True)
    args = parser.parse_args()
    processes = []
    with tempfile.TemporaryDirectory(prefix='pomodoro-launch-test-') as directory:
        data = Path(directory)
        (data / 'pomodoro.json').write_text(json.dumps({'version': 4, 'phase': 'focus', 'running': False,
            'endAt': 0, 'remainingSeconds': 1500, 'completedFocus': 0, 'cycleDateKey': '', 'activeNote': '',
            'phaseStartedAt': 0, 'phaseRunStartedAt': 0, 'phaseElapsedSeconds': 0,
            'phasePlannedSeconds': 0, 'phaseSegments': [], 'phaseRang': False}))
        # Missing bridges prevent any service requests; the timer stays idle.
        env = {**os.environ, 'POMODORO_DATA_DIR': directory, 'POMODORO_SCRIPT_DIR': str(data / 'no-bridges')}
        try:
            first = subprocess.Popen([args.binary], env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            processes.append(first)
            time.sleep(2)
            assert first.poll() is None, 'Primary app unexpectedly exited'
            second = subprocess.Popen([args.binary], env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            processes.append(second)
            try:
                second.wait(timeout=3)
            except subprocess.TimeoutExpired:
                raise AssertionError('Duplicate launch started a second live app/timer') from None
            assert second.returncode == 0, 'Duplicate launch should exit cleanly'
            assert first.poll() is None, 'Duplicate launch must not kill the primary app'
            blocked = subprocess.run([args.binary, '--report-dump', str(data / 'blocked.json')], env=env,
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=5)
            assert blocked.returncode != 0 and not (data / 'blocked.json').exists(), 'A report dump must not construct a second timer'
            first.terminate(); first.wait(timeout=5)
            assert (data / '.pomodoro-app.lock').exists(), 'Lock paths must never be deleted'
            recovered = subprocess.Popen([args.binary], env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            processes.append(recovered)
            time.sleep(2)
            assert recovered.poll() is None, 'A terminated app must not leave a stale lease'
            print('PASS: duplicate launch exits; diagnostics cannot clone a timer; crash recovery works')
        finally:
            for process in processes:
                if process.poll() is None: process.terminate()
            for process in processes:
                try: process.wait(timeout=3)
                except subprocess.TimeoutExpired: process.kill(); process.wait()


if __name__ == '__main__': main()
