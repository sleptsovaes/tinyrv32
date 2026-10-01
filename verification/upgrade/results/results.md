# RV32 upgrade verification results

978 RTL runs passed.
All runs compared ordered commits, 32 registers, 4096 RAM words, trap cause and UART output.
Store transfers were checked against committed stores.

Cycles include startup/pipeline fill and the final trapping instruction; reset cycles are excluded.
These are simulated cycle counts. No physical frequency or PPA advantage is claimed for this core.

Memory mode is instruction wait / data wait / random flag. Fixed waits count additional
cycles before completion. Random delays are 1–4 cycles and serve correctness checks only:
the random generator advances with cycles, so the two predictor modes do not receive
an identical latency schedule. Random-mode speedups are intentionally excluded.

| Workload | Memory mode | No prediction cycles | Static prediction cycles | Cycle speedup |
|---|---|---:|---:|---:|
| isa_directed | 0/0/0 | 98 | 97 | 1.0103 |
| isa_directed | 0/1/0 | 124 | 123 | 1.0081 |
| isa_directed | 1/3/0 | 236 | 235 | 1.0043 |
| ecall | 0/0/0 | 2 | 2 | 1.0000 |
| ecall | 0/1/0 | 2 | 2 | 1.0000 |
| ecall | 1/3/0 | 3 | 3 | 1.0000 |
| untaken_unaligned_target | 0/0/0 | 4 | 4 | 1.0000 |
| untaken_unaligned_target | 0/1/0 | 4 | 4 | 1.0000 |
| untaken_unaligned_target | 1/3/0 | 7 | 7 | 1.0000 |
| reset_pending_store | 1/3/0 | 15 | 15 | 1.0000 |
| alu_dependency_chain | 0/0/0 | 518 | 518 | 1.0000 |
| alu_dependency_chain | 0/1/0 | 519 | 519 | 1.0000 |
| alu_dependency_chain | 1/3/0 | 1037 | 1037 | 1.0000 |
| memory_dependency_chain | 0/0/0 | 389 | 389 | 1.0000 |
| memory_dependency_chain | 0/1/0 | 646 | 646 | 1.0000 |
| memory_dependency_chain | 1/3/0 | 1291 | 1291 | 1.0000 |
| branch_not_taken | 0/0/0 | 262 | 262 | 1.0000 |
| branch_not_taken | 0/1/0 | 263 | 263 | 1.0000 |
| branch_not_taken | 1/3/0 | 525 | 525 | 1.0000 |
| taken_branch_loop | 0/0/0 | 389 | 263 | 1.4791 |
| taken_branch_loop | 0/1/0 | 390 | 264 | 1.4773 |
| taken_branch_loop | 1/3/0 | 652 | 526 | 1.2395 |
| jal_flush_chain | 0/0/0 | 389 | 261 | 1.4904 |
| jal_flush_chain | 0/1/0 | 390 | 262 | 1.4885 |
| jal_flush_chain | 1/3/0 | 651 | 523 | 1.2447 |
| mixed_loop | 0/0/0 | 1031 | 904 | 1.1405 |
| mixed_loop | 0/1/0 | 1288 | 1161 | 1.1094 |
| mixed_loop | 1/3/0 | 2447 | 2320 | 1.0547 |
| compiled_c | 0/0/0 | 1975 | 1784 | 1.1071 |
| compiled_c | 0/1/0 | 2307 | 2116 | 1.0903 |
| compiled_c | 1/3/0 | 4380 | 4189 | 1.0456 |
