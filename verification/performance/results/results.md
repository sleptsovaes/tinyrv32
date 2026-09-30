# TinyRV32 measured performance

Cycles include pipeline fill and end on the signature store commit. Reset and the terminal JAL are excluded.

RTL simulation used a 10 ns testbench clock. Execution times below are calculated from cycles at 100 MHz (single-cycle) and 113 MHz (pipeline), not from wall-clock simulator runtime.

Single-cycle RTL commit: `6ec637b161d326051904ab9ade76cc9e1d15b459`. Pipeline snapshot HEAD: `7adbbe89e1d305c76d00afaf7a129d0430c45b28`; actual RTL hashes are in `manifest.json`.

| Workload | Retired | Redirects | Single cycles | Pipeline cycles | Pipeline CPI | Single time (us) | Pipeline time (us) | Speedup |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| alu_dependency_chain | 515 | 0 | 515 | 516 | 1.0019 | 5.1500 | 4.5664 | 1.1278 |
| memory_dependency_chain | 386 | 0 | 386 | 387 | 1.0026 | 3.8600 | 3.4248 | 1.1271 |
| branch_not_taken | 259 | 0 | 259 | 260 | 1.0039 | 2.5900 | 2.3009 | 1.1257 |
| taken_branch_loop | 259 | 127 | 259 | 387 | 1.4942 | 2.5900 | 3.4248 | 0.7563 |
| jal_flush_chain | 258 | 128 | 258 | 387 | 1.5000 | 2.5800 | 3.4248 | 0.7533 |
| mixed_loop | 900 | 128 | 900 | 1029 | 1.1433 | 9.0000 | 9.1062 | 0.9883 |

A speedup above 1 means the pipeline took less calculated execution time; below 1 means more. The single-cycle 100 MHz target is a tested operating point, not its measured maximum frequency.

All runs passed closed-form state/count oracles and full architectural-state comparison between the two RTL snapshots.
