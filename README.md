# TinyRV32

Two small SystemVerilog RISC-V cores used to study pipeline control, memory
latency and static branch prediction. Both cores and their checks are on `main`.

## Cores and measured results

| Core | Experiment | Result and evidence |
|---|---|---|
| [`cpu_core.sv`](rtl/cpu_core.sv) | Historical 14-instruction subset; single-cycle baseline versus two-stage pipeline | SKY130 pipeline closed setup timing at the highest tested passing target, **113 MHz (+0.15 ns slack)**. Workload benefits depend on redirect frequency. [Architecture and physical reports](docs/HISTORICAL_CORE.md) |
| [`rv32_core.sv`](rtl/rv32_core.sv) | 38 normally completing RV32I instructions; memory waits, precise stops and optional static prediction | **978 core simulations passed**. With zero memory waits, prediction reduced the compiled-C workload from **1975 to 1784 cycles (9.67%)**. [Architecture and verification](docs/RV32_UPGRADE.md) · [Recorded results](verification/upgrade/results/results.md) |

The expanded core also runs freestanding C in a 16 KiB RAM/UART SoC. A separate
serial test checks 19 bytes decoded from the UART TX waveform:
`CRC SORT BUFFER OK` followed by a newline.

**The 113 MHz result belongs to the historical core.** Frequency and mapped
area have not been measured for the expanded core or SoC; its cycle reductions
are not measured physical execution-time or PPA improvements.

## Run the checks

Use a full Git clone: the historical benchmark extracts its baseline from
commit history. Required for `make test`: Python 3, Make and Icarus Verilog
(`iverilog` and `vvp`). The expanded C/SoC checks also need GNU RISC-V GCC and
binutils for RV32I/ILP32. Yosys is needed for the last two commands.

```bash
make test           # Historical core, checker/oracle tests and fault injection
make upgrade        # Expanded core: both predictor modes, memory waits, C, UART
make formal         # Bounded protocol safety through six sampled cycles
make synth-upgrade  # Generic structural synthesis of expanded core and SoC
```

Installation commands, tested tool versions and smaller/compiler-free runs
are described in the [expanded-core guide](docs/RV32_UPGRADE.md#reproduce-the-checks).
The [GitHub Actions workflow](.github/workflows/verify.yml) runs the full set.

## What the verification checks

- The historical regression compares final PC, all 32 registers and all 64 RAM
  words, plus ordered instruction commits and actual memory writes.
- Fault-injection tests include wrong register values and missing/corrupt stores
  that are overwritten later. These tests require the trace check to fail even
  when final state matches.
- The expanded regression checks ordered commits, all 32 registers, all 4096 RAM
  words, precise-stop state and store-completion consistency under memory waits.
- `make checker` runs 18 state/trace checker tests and three reference-model
  tests; `make trace-regression` runs seven directed historical-core RTL tests.
  Both targets are included in `make test`.

These are project-specific reference models and traces, not RVFI or RISC-V
architectural certification. The formal checks are bounded protocol checks,
not complete instruction-equivalence proofs. No FPGA-board demonstration is
claimed.

## Documentation and evidence

- [Expanded core](docs/RV32_UPGRADE.md): instruction scope, memory contract,
  prediction, firmware, verification and remaining limitations.
- [Historical core](docs/HISTORICAL_CORE.md): pipeline structure, verification,
  SKY130 timing/area sweep, workload interpretation and physical rerun inputs.
- [Historical benchmark methodology](verification/PERFORMANCE_BENCHMARK.md)
  and [saved results](verification/performance/results/results.md): identical
  programs at selected 100 MHz / 113 MHz operating points.
- [Physical source pins](reproducibility/physical_sources.json) and
  [environment record](reproducibility/physical_environment.json): input
  revisions, hashes and environment provenance.

Committed reports retain their original run dates and source hashes. New
verification runs write fresh outputs under `build/`; they do not replace the
saved measurement snapshots automatically. The historical differential test
also refreshes its sample dumps under `verification/generated/`.
