#!/usr/bin/env python3
"""Generic synthesis and structural checks; no target library or PPA estimates."""
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import shlex
import subprocess

ROOT = Path(__file__).resolve().parents[1]


def main():
    out = ROOT/'build/synthesis'; out.mkdir(parents=True, exist_ok=True)
    yosys = shlex.split(os.getenv('YOSYS', 'yosys'))
    report = dict(executed_at_utc=datetime.now(timezone.utc).isoformat(),
                  tool=subprocess.check_output(yosys+['-V'], text=True).strip(),
                  technology_mapped=False, sha256={}, runs=[])
    for source in ('rtl/rv32_core.sv', 'rtl/tinyrv32_soc.sv', 'rtl/uart_tx.sv'):
        report['sha256'][source] = hashlib.sha256((ROOT/source).read_bytes()).hexdigest()
    for predict in (0, 1):
        script = (f'read_verilog -sv rtl/rv32_core.sv; '
                  f'chparam -set STATIC_PREDICT {predict} rv32_core; '
                  'synth -noabc -top rv32_core; check -assert; '
                  f'write_json {out}/core{predict}.json; stat')
        with (out/f'core{predict}.log').open('w') as stream:
            subprocess.run(yosys+['-Q', '-p', script], cwd=ROOT, check=True,
                           stdout=stream, stderr=subprocess.STDOUT, timeout=120)
        netlist = json.loads((out/f'core{predict}.json').read_text())
        cells = netlist['modules']['rv32_core']['cells'].values()
        if any('LATCH' in cell['type'].upper() for cell in cells):
            raise RuntimeError('Unexpected latch in synthesized core')
        report['runs'].append(dict(top='rv32_core', prediction=predict,
                                   structural_check='PASS', inferred_latches=0))
        print(f'PASS: generic core synthesis, prediction={predict}', flush=True)
    script = ('read_verilog -sv rtl/rv32_core.sv rtl/uart_tx.sv rtl/tinyrv32_soc.sv; '
              'hierarchy -check -top tinyrv32_soc; proc; opt; memory_dff; '
              f'memory_collect; opt; check -assert; write_json {out}/soc.json; stat')
    with (out/'soc.log').open('w') as stream:
        subprocess.run(yosys+['-Q', '-p', script], cwd=ROOT, check=True,
                       stdout=stream, stderr=subprocess.STDOUT, timeout=120)
    netlist = json.loads((out/'soc.json').read_text())
    memories = [cell for cell in netlist['modules']['tinyrv32_soc']['cells'].values()
                if cell['type'].startswith('$mem')]
    if len(memories) != 1 or int(memories[0]['parameters']['SIZE'], 2) != 4096:
        raise RuntimeError('Expected one 4096-word SoC RAM')
    report['runs'].append(dict(top='tinyrv32_soc', structural_check='PASS',
                               ram_words=4096, board_mapping_verified=False))
    (out/'results.json').write_text(json.dumps(report, indent=2)+'\n')
    print('PASS: SoC structural check with RAM preserved. FPGA mapping and PPA remain unmeasured.')


if __name__ == '__main__':
    main()
