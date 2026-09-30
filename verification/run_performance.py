#!/usr/bin/env python3
"""TinyRV32 cycles/CPI benchmark; uses isolated RTL snapshots from Git/current files."""

from __future__ import annotations

import argparse
import csv
from datetime import datetime, timezone
import hashlib
import json
import math
import os
from pathlib import Path
import shutil
import subprocess
import sys

IMEM_WORDS = 1024
DMEM_WORDS = 256
MASK = 0xFFFFFFFF


def signed(value: int, bits: int) -> int:
    return value - (1 << bits) if value & (1 << (bits - 1)) else value


def immediate(value: int, bits: int, alignment: int = 1) -> int:
    if not -(1 << (bits - 1)) <= value < (1 << (bits - 1)):
        raise ValueError(f"Immediate {value} exceeds signed {bits}-bit range")
    if value % alignment:
        raise ValueError(f"Immediate {value} is not aligned to {alignment}")
    return value & ((1 << bits) - 1)


def addi(rd: int, rs1: int, imm: int) -> int:
    return immediate(imm, 12) << 20 | rs1 << 15 | rd << 7 | 0x13


def add(rd: int, rs1: int, rs2: int) -> int:
    return rs2 << 20 | rs1 << 15 | rd << 7 | 0x33


def lw(rd: int, rs1: int, imm: int) -> int:
    return immediate(imm, 12) << 20 | rs1 << 15 | 2 << 12 | rd << 7 | 0x03


def sw(rs2: int, rs1: int, imm: int) -> int:
    value = immediate(imm, 12)
    return ((value >> 5) << 25 | rs2 << 20 | rs1 << 15 |
            2 << 12 | (value & 31) << 7 | 0x23)


def branch(rs1: int, rs2: int, offset: int, *, ne: bool = False) -> int:
    value = immediate(offset, 13, 2)
    return (((value >> 12) & 1) << 31 | ((value >> 5) & 63) << 25 |
            rs2 << 20 | rs1 << 15 | int(ne) << 12 |
            ((value >> 1) & 15) << 8 | ((value >> 11) & 1) << 7 | 0x63)


def jal(rd: int, offset: int) -> int:
    value = immediate(offset, 21, 2)
    return (((value >> 20) & 1) << 31 | ((value >> 1) & 1023) << 21 |
            ((value >> 11) & 1) << 20 | ((value >> 12) & 255) << 12 |
            rd << 7 | 0x6F)


def workload(name: str, words: list[int], *, regs: dict[int, int],
             memory: dict[int, int], retired: int, branches: int = 0,
             taken: int = 0, jals: int = 0) -> dict:
    last_pc = 4 * (len(words) - 1)
    if words[-1] & 0x7F != 0x23:
        raise ValueError("Last useful instruction must be a signature store")
    words = words + [jal(0, 0)]
    if len(words) > IMEM_WORDS:
        raise ValueError("Workload exceeds instruction memory")
    registers = [0] * 32
    data = [0] * DMEM_WORDS
    for index, value in regs.items():
        registers[index] = value & MASK
    for index, value in memory.items():
        data[index] = value & MASK
    return dict(name=name, words=words, last_pc=last_pc,
                registers=registers, memory=data, retired=retired,
                branches=branches, taken_branches=taken, jals=jals,
                redirects=taken + jals)


def make_workloads(n: int = 128, straight: int = 256) -> list[dict]:
    cases = []
    words = [addi(1, 0, 0), addi(2, 0, 3)]
    for _ in range(straight):
        words += [add(1, 1, 2), addi(1, 1, 1)]
    words += [sw(1, 0, 0)]
    cases.append(workload("alu_dependency_chain", words,
                          regs={1: 4 * straight, 2: 3}, memory={0: 4 * straight},
                          retired=2 * straight + 3))

    words = [addi(1, 0, 7)]
    for _ in range(n):
        words += [sw(1, 0, 4), lw(2, 0, 4), addi(1, 2, 1)]
    words += [sw(1, 0, 0)]
    cases.append(workload("memory_dependency_chain", words,
                          regs={1: 7 + n, 2: 6 + n},
                          memory={0: 7 + n, 1: 6 + n}, retired=3 * n + 2))

    words = [addi(1, 0, 0), addi(2, 0, 1)]
    for _ in range(n):
        words += [branch(1, 2, 8), addi(3, 3, 1)]
    words += [sw(3, 0, 0)]
    cases.append(workload("branch_not_taken", words,
                          regs={2: 1, 3: n}, memory={0: n},
                          retired=2 * n + 3, branches=n))

    words = [addi(1, 0, 0), addi(2, 0, n), addi(1, 1, 1),
             branch(1, 2, -4, ne=True), sw(1, 0, 0)]
    cases.append(workload("taken_branch_loop", words,
                          regs={1: n, 2: n}, memory={0: n},
                          retired=2 * n + 3, branches=n, taken=n - 1))

    words = [addi(1, 0, 0)]
    last_link = 0
    for _ in range(n):
        last_link = 4 * len(words) + 4
        words += [jal(12, 8), addi(31, 31, 1), addi(1, 1, 1)]
    words += [sw(1, 0, 0)]
    cases.append(workload("jal_flush_chain", words,
                          regs={1: n, 12: last_link}, memory={0: n},
                          retired=2 * n + 2, jals=n))

    words = [addi(1, 0, 0), addi(2, 0, n), addi(4, 0, 0), addi(5, 0, 3),
             lw(3, 0, 4), add(3, 3, 5), sw(3, 0, 4), add(4, 4, 3),
             addi(1, 1, 1), branch(1, 2, 12), jal(0, -24),
             addi(31, 31, 1), sw(4, 0, 0)]
    total = 3 * n * (n + 1) // 2
    cases.append(workload("mixed_loop", words,
                          regs={1: n, 2: n, 3: 3 * n, 4: total, 5: 3},
                          memory={0: total, 1: 3 * n}, retired=7 * n + 4,
                          branches=n, taken=1, jals=n - 1))
    return cases


def interpret(case: dict) -> dict:
    """Decode binary words independently to check the workload's closed-form oracle."""
    regs, memory, pc = [0] * 32, [0] * DMEM_WORDS, 0
    stats = dict(retired=0, branches=0, taken_branches=0, jals=0, redirects=0)
    for _ in range(50000):
        if pc % 4 or not 0 <= pc // 4 < len(case["words"]):
            raise ValueError(f"Invalid reference PC {pc}")
        instr = case["words"][pc // 4]
        opcode = instr & 127
        rd, rs1, rs2 = (instr >> 7) & 31, (instr >> 15) & 31, (instr >> 20) & 31
        funct3 = (instr >> 12) & 7
        next_pc = pc + 4
        if opcode == 0x13 and funct3 == 0:
            regs[rd] = (regs[rs1] + signed(instr >> 20, 12)) & MASK
        elif opcode == 0x33 and funct3 == 0 and instr >> 25 == 0:
            regs[rd] = (regs[rs1] + regs[rs2]) & MASK
        elif opcode in (0x03, 0x23) and funct3 == 2:
            imm = (instr >> 20) if opcode == 0x03 else ((instr >> 25) << 5 | (instr >> 7) & 31)
            address = (regs[rs1] + signed(imm, 12)) & MASK
            if address % 4 or address // 4 >= DMEM_WORDS:
                raise ValueError(f"Invalid reference memory address {address}")
            if opcode == 0x03:
                regs[rd] = memory[address // 4]
            else:
                memory[address // 4] = regs[rs2]
        elif opcode == 0x63 and funct3 in (0, 1):
            offset = ((instr >> 31) << 12 | ((instr >> 7) & 1) << 11 |
                      ((instr >> 25) & 63) << 5 | ((instr >> 8) & 15) << 1)
            taken = (regs[rs1] == regs[rs2]) if funct3 == 0 else (regs[rs1] != regs[rs2])
            stats["branches"] += 1
            if taken:
                next_pc = (pc + signed(offset, 13)) & MASK
                stats["taken_branches"] += 1
                stats["redirects"] += 1
        elif opcode == 0x6F:
            offset = ((instr >> 31) << 20 | ((instr >> 12) & 255) << 12 |
                      ((instr >> 20) & 1) << 11 | ((instr >> 21) & 1023) << 1)
            regs[rd] = pc + 4
            next_pc = (pc + signed(offset, 21)) & MASK
            stats["jals"] += 1
            stats["redirects"] += 1
        else:
            raise ValueError(f"Unsupported reference instruction {instr:08x}")
        regs[0] = 0
        stats["retired"] += 1
        if pc == case["last_pc"]:
            return dict(registers=regs, memory=memory, **stats)
        pc = next_pc
    raise ValueError("Reference workload timeout")


def program_self_test(cases: list[dict]) -> None:
    # Fixed encodings from the existing directed TinyRV32 regression.
    encodings = [(addi(1, 0, 5), 0x00500093), (add(3, 1, 2), 0x002081B3),
                 (sw(3, 0, 0), 0x00302023), (lw(4, 0, 0), 0x00002203),
                 (branch(3, 4, 8), 0x00418463), (jal(0, 0), 0x0000006F)]
    for actual, expected in encodings:
        if actual != expected:
            raise ValueError(f"Instruction encoding mismatch: {actual:08x} != {expected:08x}")
    for case in cases:
        observed = interpret(case)
        for key, value in observed.items():
            if value != case[key]:
                raise ValueError(f"Workload oracle mismatch: {case['name']} {key}")
    print(f"PROGRAM SELF-TEST PASSED ({len(cases)} workloads)")


def command(args: list[str], *, cwd: Path, log: Path | None = None) -> str:
    result = subprocess.run(args, cwd=cwd, text=True, stdout=subprocess.PIPE,
                            stderr=subprocess.STDOUT, timeout=120)
    if log is not None:
        log.write_text(result.stdout, encoding="utf-8")
    if result.returncode:
        raise RuntimeError(f"Command failed ({result.returncode}): {' '.join(args)}\n{result.stdout[-6000:]}")
    return result.stdout


def read_state(path: Path) -> dict:
    values = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        key, value = line.split()
        if key in values:
            raise ValueError(f"Duplicate state field {key}")
        values[key] = int(value, 16 if key.startswith(("X", "M")) or key == "LAST_PC" else 10)
    expected_keys = ({"CYCLES", "RETIRED", "BRANCHES", "TAKEN_BRANCHES", "JALS", "REDIRECTS", "LAST_PC"} |
                     {f"X{i}" for i in range(32)} | {f"M{i}" for i in range(DMEM_WORDS)})
    if set(values) != expected_keys:
        raise ValueError(f"Missing/extra state fields in {path}")
    return values


def validate_state(case: dict, state: dict, pipelined: bool) -> None:
    expected = dict(RETIRED=case["retired"], BRANCHES=case["branches"],
                    TAKEN_BRANCHES=case["taken_branches"], JALS=case["jals"],
                    REDIRECTS=case["redirects"], LAST_PC=case["last_pc"])
    expected["CYCLES"] = case["retired"] + (1 + case["redirects"] if pipelined else 0)
    expected.update({f"X{i}": value for i, value in enumerate(case["registers"])})
    expected.update({f"M{i}": value for i, value in enumerate(case["memory"])})
    for key, value in expected.items():
        if state[key] != value:
            arch = "pipeline" if pipelined else "single_cycle"
            raise ValueError(f"{case['name']} {arch}: {key} expected {value}, got {state[key]}")


def snapshot(root: Path, output: Path, baseline: str) -> tuple[dict, dict]:
    sha = command(["git", "rev-parse", "--verify", f"{baseline}^{{commit}}"], cwd=root).strip()
    paths = command(["git", "ls-tree", "-r", "--name-only", sha, "rtl"], cwd=root).splitlines()
    old = output / "rtl_single_cycle"
    new = output / "rtl_pipeline"
    old.mkdir(parents=True, exist_ok=True)
    new.mkdir(parents=True, exist_ok=True)
    files = {"single_cycle": [], "pipeline": []}
    hashes = {"single_cycle": {}, "pipeline": {}}
    for rel in paths:
        source = Path(rel)
        if source.suffix != ".sv":
            continue
        if source.parts[0] != "rtl" or ".." in source.parts:
            raise ValueError("Invalid RTL path from Git")
        dst = old / source.relative_to("rtl")
        dst.parent.mkdir(parents=True, exist_ok=True)
        data = subprocess.check_output(["git", "show", f"{sha}:{rel}"], cwd=root)
        dst.write_bytes(data)
        files["single_cycle"].append(dst)
        hashes["single_cycle"][rel] = hashlib.sha256(data).hexdigest()
    for src in sorted((root / "rtl").rglob("*.sv")):
        relative = src.relative_to(root / "rtl")
        dst = new / relative
        dst.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(src, dst)
        files["pipeline"].append(dst)
        hashes["pipeline"][str(src.relative_to(root))] = hashlib.sha256(dst.read_bytes()).hexdigest()
    if not all(files.values()):
        raise ValueError("Missing RTL sources")
    metadata = dict(baseline_commit=sha,
                    current_head=command(["git", "rev-parse", "HEAD"], cwd=root).strip(),
                    current_rtl_changes=command(["git", "status", "--short", "--", "rtl"], cwd=root).splitlines(),
                    rtl_sha256=hashes)
    return files, metadata


def save_results(output: Path, results: list[dict], manifest: dict) -> None:
    with (output / "results.csv").open("w", newline="", encoding="utf-8") as stream:
        writer = csv.DictWriter(stream, fieldnames=list(results[0]))
        writer.writeheader()
        writer.writerows(results)
    (output / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    lines = ["# TinyRV32 measured performance", "",
             "Cycles include pipeline fill and end on the signature store commit. Reset and the terminal JAL are excluded.", "",
             f"RTL simulation used a 10 ns testbench clock. Execution times below are calculated from cycles at {manifest['single_mhz']:g} MHz (single-cycle) and {manifest['pipeline_mhz']:g} MHz (pipeline), not from wall-clock simulator runtime.", "",
             f"Single-cycle RTL commit: `{manifest['baseline_commit']}`. Pipeline snapshot HEAD: `{manifest['current_head']}`; actual RTL hashes are in `manifest.json`.", "",
             "| Workload | Retired | Redirects | Single cycles | Pipeline cycles | Pipeline CPI | Single time (us) | Pipeline time (us) | Speedup |",
             "|---|---:|---:|---:|---:|---:|---:|---:|---:|"]
    for row in results:
        lines.append(f"| {row['workload']} | {row['retired']} | {row['redirects']} | {row['single_cycles']} | {row['pipeline_cycles']} | {row['pipeline_cpi']:.4f} | {row['single_time_us']:.4f} | {row['pipeline_time_us']:.4f} | {row['speedup']:.4f} |")
    lines += ["", "A speedup above 1 means the pipeline took less calculated execution time; below 1 means more. The single-cycle 100 MHz target is a tested operating point, not its measured maximum frequency.", "",
              "All runs passed closed-form state/count oracles and full architectural-state comparison between the two RTL snapshots.", ""]
    (output / "results.md").write_text("\n".join(lines), encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--baseline", default="6ec637b")
    parser.add_argument("--single-mhz", type=float, default=100.0)
    parser.add_argument("--pipeline-mhz", type=float, default=113.0)
    parser.add_argument("--iterations", type=int, default=128)
    parser.add_argument("--straight-iterations", type=int, default=256)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--self-test", action="store_true", help="Validate program generation/oracles without HDL simulation")
    args = parser.parse_args()
    if not (1 <= args.iterations <= 256 and 1 <= args.straight_iterations <= 256):
        parser.error("Iteration counts must be in 1..256")
    if not (math.isfinite(args.single_mhz) and math.isfinite(args.pipeline_mhz) and
            args.single_mhz > 0 and args.pipeline_mhz > 0):
        parser.error("Frequencies must be positive")
    cases = make_workloads(args.iterations, args.straight_iterations)
    program_self_test(cases)
    if args.self_test:
        return 0

    root = Path(__file__).resolve().parents[1]
    output = (args.output or root / "build" / "performance").resolve()
    output.mkdir(parents=True, exist_ok=True)
    # A failed rerun must not leave an old result table appearing current.
    for name in ("results.csv", "results.md", "manifest.json"):
        (output / name).unlink(missing_ok=True)
    iverilog = os.environ.get("IVERILOG", "iverilog")
    vvp = os.environ.get("VVP", "vvp")
    if not shutil.which(iverilog) or not shutil.which(vvp):
        raise RuntimeError("Icarus Verilog (iverilog and vvp) must be available")
    tb = root / "tb" / "performance_tb.sv"
    if not tb.is_file():
        raise RuntimeError(f"Missing testbench: {tb}")
    files, manifest = snapshot(root, output, args.baseline)
    manifest.update(single_mhz=args.single_mhz, pipeline_mhz=args.pipeline_mhz,
                    executed_at_utc=datetime.now(timezone.utc).isoformat(),
                    iterations=args.iterations, straight_iterations=args.straight_iterations,
                    simulated_clock_period_ns=10, reset_cycles_excluded=True,
                    terminal_jal_excluded=True, rf_initialization="x1..x31 set to zero by testbench during reset",
                    imem_words=IMEM_WORDS, dmem_words=DMEM_WORDS,
                    testbench_sha256=hashlib.sha256(tb.read_bytes()).hexdigest(),
                    runner_sha256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
                    vvp_version=command([vvp, "-V"], cwd=root),
                    iverilog_version=command([iverilog, "-V"], cwd=root))
    bins = {}
    for arch, sources in files.items():
        bins[arch] = output / f"{arch}_sim"
        flags = ["-DBENCH_PIPELINED"] if arch == "pipeline" else []
        command([iverilog, "-g2012", "-s", "performance_tb", *flags,
                 "-o", str(bins[arch]), *map(str, sources), str(tb)],
                cwd=root, log=output / f"{arch}_compile.log")

    results = []
    for case in cases:
        folder = output / case["name"]
        folder.mkdir(exist_ok=True)
        program = folder / "program.hex"
        words = case["words"] + [0x13] * (IMEM_WORDS - len(case["words"]))
        program.write_text("".join(f"{word:08x}\n" for word in words), encoding="utf-8")
        states = {}
        for arch in bins:
            state_path = folder / f"{arch}_state.txt"
            state_path.unlink(missing_ok=True)
            command([vvp, str(bins[arch]), f"+PROGRAM={program}",
                     f"+STATE={state_path}", f"+LAST_PC={case['last_pc']:08x}"],
                    cwd=root, log=folder / f"{arch}.log")
            states[arch] = read_state(state_path)
            validate_state(case, states[arch], arch == "pipeline")
        for key in states["single_cycle"]:
            if key != "CYCLES" and states["single_cycle"][key] != states["pipeline"][key]:
                raise ValueError(f"Architectural comparison failed: {case['name']} {key}")
        single, pipeline = states["single_cycle"]["CYCLES"], states["pipeline"]["CYCLES"]
        single_time, pipeline_time = single / args.single_mhz, pipeline / args.pipeline_mhz
        row = dict(workload=case["name"], retired=case["retired"],
                   branches=case["branches"], taken_branches=case["taken_branches"],
                   jals=case["jals"], redirects=case["redirects"],
                   single_cycles=single, pipeline_cycles=pipeline,
                   single_cpi=single / case["retired"], pipeline_cpi=pipeline / case["retired"],
                   pipeline_cpi_without_fill=(pipeline - 1) / case["retired"],
                   pipeline_bubbles=pipeline - case["retired"] - 1,
                   single_mhz=args.single_mhz, pipeline_mhz=args.pipeline_mhz,
                   single_time_us=single_time, pipeline_time_us=pipeline_time,
                   speedup=single_time / pipeline_time)
        results.append(row)
        print(f"[PASS] {case['name']}: {single} -> {pipeline} cycles; speedup={row['speedup']:.4f}x")
    save_results(output, results, manifest)
    print("ALL PERFORMANCE BENCHMARKS PASSED")
    print(f"Results: {output / 'results.md'}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as error:
        print(f"PERFORMANCE BENCHMARK FAILED: {error}", file=sys.stderr)
        raise SystemExit(1)
