# TinyRV32 performance benchmark

This package adds `tb/performance_tb.sv` and `verification/run_performance.py`.
Extract it into the TinyRV32 repository root, with the `two-stage-pipeline`
branch checked out.

Requirements: Python 3.10+, Git, Icarus Verilog (`iverilog` and `vvp`).

## Run

```bash
cd ~/tinyrv32
python3 verification/run_performance.py \
  --baseline 6ec637b \
  --single-mhz 100 \
  --pipeline-mhz 113
```

The baseline defaults to the pre-pipeline commit identified in the supplied
history, `6ec637b`. The testbench expects that version's `dut.pc_value` and
`dut.rf.regs` signals. The pipeline build uses the current working-tree RTL
and expects `dut.exec_pc`, `dut.exec_instr`, and `dut.exec_valid`.

The runner extracts the baseline RTL through Git and copies current RTL into
separate build directories. It compiles each microarchitecture with an explicit
top-level module, then runs exactly the same six generated programs on both.

Default output directory: `build/performance/`.

```bash
cat build/performance/results.md
```

The final `ALL PERFORMANCE BENCHMARKS PASSED` message and result tables are
produced only after all workload, state, and cycle/count checks pass.

## Measurement boundary

- Hold reset for three rising clock edges and release on a falling edge.
- Initialize x1 through x31 to zero during reset in the testbench, identically
  for both microarchitectures. Data memory also starts at zero.
- Count every active clock edge from the first edge after reset release.
- Count an instruction when it is valid in execute immediately before its
  committing edge. Single-cycle execute is valid on every active edge.
- Stop on the committing edge of the designated final signature `sw` to address
  zero. All six workloads end with this store.
- Wait 1 ns after that edge before reading register and data-memory state, so
  nonblocking updates, including the signature store, have completed.
- Exclude reset and the terminal `jal x0, 0` from both cycles and retired counts.

For this RTL, the expected identities are:

```text
single_cycle_cycles = retired
pipeline_cycles = retired + 1 + redirects
redirects = taken_conditional_branches + JAL_instructions
```

The extra one is initial pipeline fill. Each redirect inserts one execute
bubble. The runner checks these identities against the simulator's counts.

`LAST_PC` in state files denotes the last committed useful instruction, rather
than the fetch PC. All 32 architectural register values and all 256 data-memory
words are checked against closed-form workload oracles and compared between
the two implementations.

## Workloads and analytical count expectations

These are expected counts, not measured RTL results. Defaults use 128 loop
iterations and 256 iterations for the straight-line ALU sequence.

| Workload | Retired | Redirects | Expected single cycles | Expected pipeline cycles |
|---|---:|---:|---:|---:|
| ALU dependency chain | 515 | 0 | 515 | 516 |
| Store/load/use dependency chain | 386 | 0 | 386 | 387 |
| Not-taken branches | 259 | 0 | 259 | 260 |
| Taken-branch loop | 259 | 127 | 259 | 387 |
| JAL flush chain | 258 | 128 | 258 | 387 |
| Mixed arithmetic/memory/control loop | 900 | 128 | 900 | 1029 |

JAL and mixed-control programs contain skipped `addi x31, x31, 1` sentinels.
The expected x31 remains zero. JAL also uses x12 as a link destination and checks
the final link address.

The instruction memory model has 1024 words and data memory has 256 words.
Reads are combinational, writes are synchronous, and there are no memory waits.
Thus these workloads evaluate the current ideal-memory core interface.

## Execution time and interpretation

The RTL simulator uses a 10 ns clock to obtain cycle counts. The supplied
frequency arguments are used afterward to calculate execution time:

```text
time_us = cycles / frequency_MHz
speedup = single_cycle_time / pipeline_time
```

A speedup greater than one means less calculated execution time for the
pipeline; less than one means more. These values describe the selected tested
operating points: single-cycle at 100 MHz and pipeline at 113 MHz. The baseline
has not been swept to establish its highest timing-closed target.

`pipeline_cpi` includes pipeline fill. `pipeline_cpi_without_fill` excludes the
one initial fill cycle but still includes redirect bubbles.

## Outputs and reproducibility

- `results.md`: readable measured results and interpretation.
- `results.csv`: cycles, CPI, branch counts, bubbles, frequencies, times, speedup.
- `manifest.json`: resolved baseline commit, current HEAD, working-tree RTL
  changes, SHA-256 hashes of every RTL file and both benchmark tools, timestamp,
  simulator versions, and measurement settings.
- `rtl_single_cycle/`, `rtl_pipeline/`: source snapshots used for compilation.
- Per-workload directories: hex program, simulator logs, and complete state
  dumps for both implementations.

For an alternative output directory:

```bash
python3 verification/run_performance.py --output build/performance_repeat
```

For the common 100 MHz operating point:

```bash
python3 verification/run_performance.py \
  --single-mhz 100 --pipeline-mhz 100 \
  --output build/performance_100mhz
```

## Validation status before delivery

Python syntax and the binary-program/closed-form-oracle self-tests passed for
1, 128, and 256 iterations. Mutation checks verified that state and count
errors are rejected. A separate binary instruction decoder exercised the
generated programs, including backward BNE/JAL offsets and wrong-path skips.

HDL compilation and simulation were not run in the preparation environment,
which has no Icarus Verilog installed. The first command above performs those
checks against the actual repository RTL and emits no final result table on
failure.

To run only the program self-test, without Git or an HDL simulator:

```bash
python3 verification/run_performance.py --self-test
```
