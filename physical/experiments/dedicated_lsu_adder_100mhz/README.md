# Experiment: Dedicated Load/Store Address Adder

## Hypothesis

The baseline critical path terminated at `dmem_addr` and originated
from instruction bits.

The hypothesis was that bypassing the general-purpose ALU for load/store
address generation could reduce the combinational delay of:

`rs1 + immediate -> dmem_addr`

A dedicated 32-bit address adder was therefore introduced.

## Functional verification

The modified RTL passed the complete functional verification suite:

- directed RTL unit tests
- CPU integration regression
- independent Python reference model
- 100 randomized differential programs

## Physical results at 100 MHz

| Metric | Baseline | Dedicated LSU adder | Delta |
|---|---:|---:|---:|
| Data arrival time | 7.92 ns | 7.89 ns | -0.03 ns |
| Setup slack | +0.08 ns | +0.11 ns | +0.03 ns |
| Design area | 75,831 um^2 | 76,831 um^2 | +1,000 um^2 |
| Area change | - | - | +1.32% |

The modified design still met the 100 MHz timing target.

## Critical path after modification

Startpoint:

`imem_rdata[17]`

Endpoint:

`dmem_addr[30]`

The critical-path family therefore remained essentially unchanged.

The path still traversed instruction-dependent register selection,
the asynchronous register-file read path, and address-generation logic.

## Conclusion

The experiment produced a measurable but small timing improvement
of approximately 30 ps while increasing final design area by about
1.32%.

The result suggests that the general ALU was not the dominant source
of delay. The asynchronous register-file read/select path remains a
more important timing bottleneck.

For this reason, the dedicated LSU adder is not selected as the final
RTL optimization.
