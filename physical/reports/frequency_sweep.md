# Post-Route Frequency Sweep

Physical implementation was performed using OpenROAD Flow Scripts with the
SKY130 HD standard-cell library.

| Target Frequency | Clock Period | Worst Slack | Physical Area | Utilization | Timing |
|---:|---:|---:|---:|---:|---|
| 50 MHz | 20.000 ns | +2.15 ns | 68,527 um² | 40% | PASS |
| 75 MHz | 13.333 ns | +0.43 ns | 69,305 um² | 40% | PASS |
| 80 MHz | 12.500 ns | +0.17 ns | 69,848 um² | 41% | PASS |
| 82 MHz | 12.195 ns | +0.08 ns | 70,377 um² | 41% | PASS |
| 83 MHz | 12.048 ns | +0.16 ns | 70,339 um² | 41% | PASS |
| 85 MHz | 11.765 ns | +0.26 ns | 71,258 um² | 42% | PASS |
| 90 MHz | 11.111 ns | +0.20 ns | 72,804 um² | 43% | PASS |
| 95 MHz | 10.526 ns | +0.09 ns | 74,305 um² | 43% | PASS |
| 98 MHz | 10.204 ns | +0.15 ns | 76,124 um² | 44% | PASS |
| 100 MHz | 10.000 ns | -0.038 ns | 75,989 um² | 44% | FAIL |

Timing closure was achieved at 98 MHz under the selected implementation
constraints.

At the 100 MHz target, static timing analysis reported a setup violation of
approximately 38 ps.

## 100 MHz Critical Path

Startpoint:

`imem_rdata[20]`

Endpoint:

`dmem_addr[29]`

Data arrival time:

`8.038 ns`

Data required time:

`8.000 ns`

Setup slack:

`-0.038 ns`

The critical path passes through instruction-dependent multiplexing and
address-generation logic before reaching the external data-memory address
interface.
