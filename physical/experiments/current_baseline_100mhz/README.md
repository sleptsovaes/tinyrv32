# Current RTL Baseline — 100 MHz

## Configuration

- Target frequency: 100 MHz
- Clock period: 10.000 ns
- Platform: SKY130 HD
- Core utilization target: 35%
- Place density: 0.60

## Final implementation results

| Metric | Result |
|---|---:|
| Critical-path slack | +0.080 ns |
| Data arrival time | 7.920 ns |
| Data required time | 8.000 ns |
| Final TNS | 0 |
| Design area | 75,831 um^2 |
| Utilization | 44% |
| Core area | 173,438.842 um^2 |
| GDS generated | Yes |

## Critical path

Startpoint:

`imem_rdata[19]`

Endpoint:

`dmem_addr[31]`

The design meets the 100 MHz timing target, but with only approximately
80 ps of setup margin on the reported critical I/O path.

This result is used as the pre-optimization baseline for the
timing-driven RTL experiment.
