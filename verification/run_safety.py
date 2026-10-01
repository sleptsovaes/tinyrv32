#!/usr/bin/env python3
"""Bounded protocol safety checks; deliberately not an ISA equivalence proof."""
import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import shlex
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--depth', type=int, default=6)
    parser.add_argument('--timeout', type=int, default=120)
    parser.add_argument('--output', type=Path, default=ROOT/'build/formal')
    args = parser.parse_args()
    if args.depth < 2 or args.timeout < 1:
        parser.error('Depth must be at least 2 and timeout must be positive')
    out = args.output.resolve(); out.mkdir(parents=True, exist_ok=True)
    yosys = shlex.split(os.getenv('YOSYS', 'yosys'))
    report = dict(executed_at_utc=datetime.now(timezone.utc).isoformat(),
                  method='bounded SAT safety', depth=args.depth, unbounded_proof=False,
                  assumptions=['initial state zero', 'reset at first sampled cycle'],
                  unconstrained_inputs=['instruction/data responses', 'ready', 'subsequent reset'],
                  core_sha256=hashlib.sha256((ROOT/'rtl/rv32_core.sv').read_bytes()).hexdigest(),
                  tool=subprocess.check_output(yosys+['-V'], text=True).strip(), runs=[])
    for predict in (0, 1):
        script = (f'read_verilog -formal -sv rtl/rv32_core.sv; '
                  f'chparam -set STATIC_PREDICT {predict} rv32_core; '
                  'prep -top rv32_core; flatten; memory_map; opt; '
                  f'sat -seq {args.depth} -set-init-zero -set-assumes '
                  f'-prove-asserts -verify -timeout {args.timeout}')
        log = out/f'predict{predict}.log'
        with log.open('w') as stream:
            run = subprocess.run(yosys+['-Q', '-p', script], cwd=ROOT,
                                 stdout=stream, stderr=subprocess.STDOUT,
                                 timeout=args.timeout+60)
        success = run.returncode == 0 and 'no model found: SUCCESS!' in log.read_text()
        report['runs'].append(dict(prediction=predict, passed=success, command=script))
        (out/'results.json').write_text(json.dumps(report, indent=2)+'\n')
        if not success:
            print('\n'.join(log.read_text().splitlines()[-15:]), file=sys.stderr)
            raise RuntimeError(f'Bounded check failed or timed out; inspect {log}')
        print(f'PASS: prediction={predict}, safety checked through {args.depth} sampled cycles', flush=True)
    print('No unbounded or complete ISA proof is claimed.')


if __name__ == '__main__':
    try:
        main()
    except (OSError, RuntimeError, subprocess.SubprocessError) as error:
        print(f'SAFETY CHECK FAILED: {error}', file=sys.stderr)
        sys.exit(1)
