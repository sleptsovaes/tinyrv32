#!/usr/bin/env python3
"""Verify RV32 core, wait states, precise stops, compiled C and prediction A/B."""
import argparse
from collections import Counter
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import random
import shlex
import subprocess
import sys

from compare_state import compare as state_compare, parse_rtl_state
from compare_trace import compare as trace_compare
from rv32_reference import RV32Reference, TRACE_FIELDS
from run_performance import make_workloads

ROOT = Path(__file__).resolve().parents[1]
EBREAK=0x00100073
REQUIRED = set('LUI AUIPC JAL JALR BEQ BNE BLT BGE BLTU BGEU ADDI SLTI SLTIU XORI ORI ANDI SLLI SRLI SRAI ADD SUB SLL SLT SLTU XOR SRL SRA OR AND LB LH LW LBU LHU SB SH SW FENCE'.split())


def cmd(args,cwd=ROOT):
    run=subprocess.run(args,cwd=cwd,text=True,capture_output=True,timeout=120)
    if run.returncode:
        raise RuntimeError(f"Command failed: {shlex.join(args)}\n{run.stdout[-2000:]}\n{run.stderr[-3000:]}")
    return run.stdout


def i_type(op,f3,rd,rs1,imm): return ((imm&4095)<<20)|(rs1<<15)|(f3<<12)|(rd<<7)|op

def r_type(f7,f3,rd,r1,r2): return (f7<<25)|(r2<<20)|(r1<<15)|(f3<<12)|(rd<<7)|0x33

def store(f3,r1,r2,off):
    off&=4095
    return ((off>>5)<<25)|(r2<<20)|(r1<<15)|(f3<<12)|((off&31)<<7)|0x23

def branch(f3,r1,r2,off):
    off&=8191
    return ((off>>12)<<31)|(((off>>5)&63)<<25)|(r2<<20)|(r1<<15)|(f3<<12)|(((off>>1)&15)<<8)|(((off>>11)&1)<<7)|0x63

def jal(rd,off):
    off&=(1<<21)-1
    return ((off>>20)<<31)|(((off>>1)&1023)<<21)|(((off>>11)&1)<<20)|(((off>>12)&255)<<12)|(rd<<7)|0x6f

def image(words): return b''.join(w.to_bytes(4,'little') for w in words)


def directed():
    words=[i_type(0x13,0,1,0,0x600),0xdeadc137,i_type(0x13,0,2,2,-273),
           i_type(0x13,0,3,0,-1),i_type(0x13,0,4,0,31)]
    for f7,f3 in [(0,f) for f in range(8)]+[(32,0),(32,5)]:
        words.append(r_type(f7,f3,5+f3,3,4))
    for f3 in [0,2,3,4,6,7]: words.append(i_type(0x13,f3,16+f3,3,-2048))
    for f3,imm in [(1,31),(5,31),(5,0x41f)]: words.append(i_type(0x13,f3,24,3,imm))
    words += [store(2,1,2,0),store(1,1,3,2),store(0,1,2,1)]
    for f3 in [0,1,2,4,5]: words.append(i_type(0x03,f3,25+f3%5,1,0 if f3 in (1,2,5) else 1))
    # Check every byte lane and halfword lane, signed/unsigned extension.
    for lane in range(4):
        words += [store(0,1,3,lane),i_type(0x03,0,8,1,lane),i_type(0x03,4,9,1,lane)]
    for lane in [0,2]:
        words += [store(1,1,3,lane),i_type(0x03,1,8,1,lane),i_type(0x03,5,9,1,lane)]
    words += [i_type(0x13,0,30,0,-1),i_type(0x13,0,31,0,1)]
    for f3 in [0,1,4,5,6,7]:
        for r1,r2 in [(30,30),(30,31),(31,30)]:
            words += [branch(f3,r1,r2,8),i_type(0x13,0,10,10,1)]
    words += [jal(6,8),store(2,1,3,16)]
    words += [0x00000297,i_type(0x13,0,5,5,16),i_type(0x67,0,6,5,1),store(2,1,3,20)]
    words += [0x0ff0000f,i_type(0x13,0,0,3,123),EBREAK]
    return words


def randomized(seed):
    rng=random.Random(seed)
    words=[]
    for rd in range(1,32):
        words += [(rng.getrandbits(20)<<12)|(rd<<7)|0x37,
                  i_type(0x13,0,rd,rd,rng.randint(-2048,2047))]
    for _ in range(80):
        rd,r1,r2=[rng.randrange(32) for _ in range(3)]
        kind=rng.randrange(4)
        if kind==0:
            f3=rng.randrange(8); f7=rng.choice([0,32]) if f3 in (0,5) else 0
            words.append(r_type(f7,f3,rd,r1,r2))
        elif kind==1:
            f3=rng.choice([0,2,3,4,6,7]); words.append(i_type(0x13,f3,rd,r1,rng.randint(-2048,2047)))
        elif kind==2:
            f3=rng.choice([1,5]); off=rng.randrange(32)|(rng.choice([0,0x400]) if f3==5 else 0)
            words.append(i_type(0x13,f3,rd,r1,off))
        else:
            address=0x600+rng.randrange(16)*4
            words += [store(2,0,r2,address),i_type(0x03,2,rd,0,address)]
    words += [jal(0,8),store(2,0,31,0x640),EBREAK]
    return words


def cases(count):
    out=[('isa_directed',image(directed()),3,False,None)]
    faults={
        'illegal_mul':[r_type(1,0,1,0,0)],
        'illegal_slli':[i_type(0x13,1,1,0,32)],
        'illegal_srai':[i_type(0x13,5,1,0,0x420)],
        'illegal_csr':[0x300010f3], 'illegal_fence_i':[0x0000100f],
        'misaligned_jal':[jal(1,2)],
        'misaligned_jalr':[i_type(0x13,0,2,0,6),i_type(0x67,0,1,2,0)],
        'misaligned_taken_branch':[branch(0,0,0,2)],
        'misaligned_lw':[i_type(0x03,2,1,0,1)],
        'misaligned_lh':[i_type(0x03,1,1,0,1)],
        'misaligned_sw':[store(2,0,0,1)],
        'misaligned_sh':[store(1,0,0,1)], 'ecall':[0x00000073],
    }
    for name,words in faults.items():
        cause=11 if name=='ecall' else 0 if name.startswith('misaligned_j') or name=='misaligned_taken_branch' else 4 if name in ('misaligned_lw','misaligned_lh') else 6 if name in ('misaligned_sw','misaligned_sh') else 2
        out.append((name,image(words+[EBREAK]),cause,False,None))
    out.append(('untaken_unaligned_target',image([i_type(0x13,0,1,0,1),branch(0,0,1,2),EBREAK]),3,False,None))
    reset_words=[i_type(0x13,0,1,0,0x600),i_type(0x13,0,2,0,85),store(2,1,2,0),i_type(0x03,2,3,1,0),EBREAK]
    out.append(('reset_pending_store',image(reset_words),3,True,None))
    for case in make_workloads():
        words=case['words'][:-1]
        for n,ins in enumerate(words):
            if ins&127==0x23:
                off=((ins>>25)<<5)|((ins>>7)&31)
                words[n]=store(2,29,(ins>>20)&31,off)
            elif ins&127==0x03:
                words[n]=i_type(0x03,2,(ins>>7)&31,29,ins>>20)
        # x29 is unused by these workloads. One setup LUI places data at
        # 0x1000, outside the longest program in the unified RAM image.
        out.append((case['name'],image([0x00001eb7]+words+[EBREAK]),3,False,case['retired']+1))
    for seed in range(count): out.append((f'random_{seed:03}',image(randomized(seed)),3,False,None))
    return out


def build_c(out,prefix):
    gcc=prefix+'gcc'; objcopy=prefix+'objcopy'; objdump=prefix+'objdump'
    elf=out/'examples.elf'; binary=out/'examples.bin'
    cmd([gcc,'-march=rv32i','-mabi=ilp32','-O2','-ffreestanding','-fno-builtin',
         '-fno-pic','-msmall-data-limit=0','-mno-relax','-nostdlib','-Wall','-Wextra',
         '-Wl,--no-relax','-T',str(ROOT/'sw/link.ld'),str(ROOT/'sw/start.S'),
         str(ROOT/'sw/examples.c'),'-o',str(elf)])
    cmd([objcopy,'-O','binary',str(elf),str(binary)])
    (out/'examples.disasm').write_text(cmd([objdump,'-d',str(elf)]))
    return binary.read_bytes(),cmd([gcc,'--version']).splitlines()[0]


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--random-programs',type=int,default=100)
    parser.add_argument('--output',type=Path,default=ROOT/'build/upgrade')
    parser.add_argument('--skip-c',action='store_true')
    parser.add_argument('--quick',action='store_true',help='Use zero-wait and fixed 3-cycle memory modes')
    args=parser.parse_args()
    if args.random_programs < 0:
        parser.error('--random-programs must be nonnegative')
    out=args.output.resolve(); out.mkdir(parents=True,exist_ok=True)
    iv=shlex.split(os.getenv('IVERILOG','iverilog')); vvp=shlex.split(os.getenv('VVP','vvp'))
    for prediction in [0,1]:
        cmd(iv+['-g2012','-s','rv32_system_tb']+(['-DSTATIC_PREDICT'] if prediction else [])+
            ['-o',str(out/f'core{prediction}'),str(ROOT/'rtl/rv32_core.sv'),str(ROOT/'tb/rv32_system_tb.sv')])
    test_cases=cases(args.random_programs)
    tool_versions={'iverilog':cmd(iv+['-V']).splitlines()[0]}
    if not args.skip_c:
        binary,version=build_c(out,os.getenv('RISCV_PREFIX','riscv64-unknown-elf-'))
        oracle=RV32Reference(binary); oracle.run()
        if oracle.status!=0 or bytes(oracle.uart)!=b'CRC SORT BUFFER OK\n':
            raise ValueError('Compiled C failed mathematical signature checks in oracle')
        test_cases.append(('compiled_c',binary,3,False,None)); tool_versions['gcc']=version
    modes=[(0,0,0),(0,1,0),(1,3,0),(0,0,1)]
    if args.quick: modes=[modes[0],modes[2]]
    rows=[]; coverage=Counter()
    for index,(name,binary,wanted_trap,reset_test,wanted_count) in enumerate(test_cases):
        oracle=RV32Reference(binary); oracle.run(); expected=oracle.expected()
        if oracle.trap!=wanted_trap: raise ValueError(f'Wrong oracle trap: {name}')
        if wanted_count is not None and len(oracle.trace)!=wanted_count:
            raise ValueError(f'Closed-form instruction-count mismatch: {name}')
        coverage.update(oracle.coverage)
        for prediction in [0,1]:
            for iw,dw,rw in modes:
                if reset_test and dw!=3: continue
                run=out/f'{name}_p{prediction}_i{iw}_d{dw}_r{rw}'; run.mkdir(exist_ok=True)
                padded=binary+bytes((-len(binary))%4)
                (run/'image.hex').write_text('\n'.join(f'{int.from_bytes(padded[n:n+4],"little"):08x}' for n in range(0,len(padded),4))+'\n')
                argv=vvp+[str(out/f'core{prediction}')]+[f'+{key}={run/path}' for key,path in
                     [('IMAGE','image.hex'),('STATE','state.txt'),('TRACE','trace.txt'),('UART','uart.txt'),('STATS','stats.txt')]]
                argv += [f'+IWAIT={iw}',f'+DWAIT={dw}',f'+RANDOM_WAIT={rw}',f'+RESET_PENDING={int(reset_test)}']
                (run/'simulation.log').write_text(cmd(argv))
                errors=state_compare(expected,parse_rtl_state(run/'state.txt',4096))
                if errors: raise ValueError(f'{run.name}: {errors[:5]}')
                # The v2 bus trace adds byte strobes to the legacy commit format.
                actual=[]
                for line in (run/'trace.txt').read_text().splitlines():
                    tokens=line.split()
                    if len(tokens)!=9 or any(len(x)!=8 or any(c not in '0123456789abcdefABCDEF' for c in x) for x in tokens):
                        raise ValueError(f'Malformed or unknown v2 trace: {run.name}')
                    actual.append(dict(zip(TRACE_FIELDS,(int(x,16) for x in tokens))))
                trace_compare(oracle.trace,actual)
                stats=dict(line.split() for line in (run/'stats.txt').read_text().splitlines())
                stats={k:int(v) for k,v in stats.items()}
                uart=[int(line,16) for line in (run/'uart.txt').read_text().splitlines()]
                if stats['TRAP']!=wanted_trap or stats['COMMITS']!=len(oracle.trace) or uart!=oracle.uart:
                    raise ValueError(f'Run metadata/UART mismatch: {run.name}')
                if stats['STATUS_WRITTEN']!=int(oracle.status is not None) or (oracle.status is not None and stats['STATUS']!=oracle.status):
                    raise ValueError(f'Status mismatch: {run.name}')
                if stats['STORES']!=sum(r['store'] for r in oracle.trace):
                    raise ValueError(f'Duplicate/missing store: {run.name}')
                if iw==dw==rw==0 and stats['CYCLES']!=len(oracle.trace)+stats['MISPREDICTIONS']+2:
                    raise ValueError(f'Zero-wait cycle identity failed: {run.name}')
                rows.append(dict(case=name,prediction=prediction,iwait=iw,dwait=dw,random_wait=rw,**stats))
        print(f'[{index+1}/{len(test_cases)}] {name}: PASS',flush=True)
    missing=REQUIRED-set(coverage)
    if missing: raise ValueError(f'Missing instruction coverage: {sorted(missing)}')
    soc_result=None
    if not args.skip_c:
        firmware=out/'compiled_c_p1_i0_d0_r0/image.hex'
        cmd(iv+['-g2012','-s','soc_uart_tb','-o',str(out/'soc_uart')]+
            [str(ROOT/p) for p in ('rtl/rv32_core.sv','rtl/uart_tx.sv','rtl/tinyrv32_soc.sv','tb/soc_uart_tb.sv')])
        log=cmd(vvp+[str(out/'soc_uart'),f'+IMAGE={firmware}',f'+UART={out/"serial_uart.txt"}'])
        (out/'soc_uart.log').write_text(log)
        received=bytes(int(x,16) for x in (out/'serial_uart.txt').read_text().splitlines())
        if received!=b'CRC SORT BUFFER OK\n': raise ValueError('Serial-line UART decode mismatch')
        soc_result=dict(result='PASS',decoded_text=received.decode('ascii'),baud_divisor=4)
        print(log.strip(),flush=True)
    source_files=['rtl/rv32_core.sv','tb/rv32_system_tb.sv','verification/rv32_reference.py',
                  'verification/run_upgrade.py','verification/compare_state.py','verification/compare_trace.py',
                  'verification/run_performance.py',
                  'sw/start.S','sw/link.ld','sw/examples.c','rtl/uart_tx.sv',
                  'rtl/tinyrv32_soc.sv','tb/soc_uart_tb.sv']
    revision=subprocess.run(['git','rev-parse','HEAD'],cwd=ROOT,text=True,
                            capture_output=True,timeout=10)
    report=dict(executed_at_utc=datetime.now(timezone.utc).isoformat(),
                source_state='source-file snapshot',
                base_commit=revision.stdout.strip() if revision.returncode==0 else None,
                sha256={p:hashlib.sha256((ROOT/p).read_bytes()).hexdigest() for p in source_files},
                tools=tool_versions,random_programs=args.random_programs,
                instruction_coverage=dict(sorted(coverage.items())),runs=rows,soc_uart=soc_result)
    (out/'results.json').write_text(json.dumps(report,indent=2)+'\n')
    lines=['# RV32 upgrade verification results','',f'{len(rows)} RTL runs passed.',
           'All runs compared ordered commits, 32 registers, 4096 RAM words, trap cause and UART output.',
           'Store transfers were checked against committed stores.','',
           'Cycles include startup/pipeline fill and the final trapping instruction; reset cycles are excluded.',
           'These are simulated cycle counts. No physical frequency or PPA advantage is claimed for this core.','',
           'Memory mode is instruction wait / data wait / random flag. Fixed waits count additional',
           'cycles before completion. Random delays are 1–4 cycles and serve correctness checks only:',
           'the random generator advances with cycles, so the two predictor modes do not receive',
           'an identical latency schedule. Random-mode speedups are intentionally excluded.','',
           '| Workload | Memory mode | No prediction cycles | Static prediction cycles | Cycle speedup |',
           '|---|---|---:|---:|---:|']
    selected=[r for r in rows if not r['case'].startswith(('random_','illegal_','misaligned_'))
              and not r['prediction'] and not r['random_wait']]
    for row in selected:
        other=next(r for r in rows if r['case']==row['case'] and r['prediction']==1 and
                   (r['iwait'],r['dwait'],r['random_wait'])==(row['iwait'],row['dwait'],row['random_wait']))
        lines.append(f"| {row['case']} | {row['iwait']}/{row['dwait']}/{row['random_wait']} | {row['CYCLES']} | {other['CYCLES']} | {row['CYCLES']/other['CYCLES']:.4f} |")
    (out/'results.md').write_text('\n'.join(lines)+'\n')
    print(f'ALL {len(rows)} RV32 UPGRADE RUNS PASSED; results: {out}',flush=True)

if __name__=='__main__':
    try: main()
    except (RuntimeError,ValueError,OSError) as error:
        print(f'UPGRADE FAILED: {error}',file=sys.stderr); sys.exit(1)
