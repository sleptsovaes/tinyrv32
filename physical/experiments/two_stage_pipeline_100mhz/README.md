# Experiment: Two-Stage Pipeline at 100 MHz

The Fetch/Execute pipeline boundary registers the instruction, its PC and
a valid bit before decode and execution.

## Constraints

- Clock period: 10 ns.
- Input delay: 2 ns.
- Output delay: 2 ns.
- Platform: SKY130 HD.
- Flow: OpenROAD Flow Scripts.

## Measured Results

| Metric | Single-cycle | Two-stage pipeline |
|---|---:|---:|
| Worst setup-path data arrival | 7.92 ns | 7.79 ns |
| Worst setup slack | +0.08 ns | +0.21 ns |
| Physical design area | 75,831 µm² | 73,084 µm² |
| Utilization | 44% | 41% |
| Routing DRC violations | 0 | 0 |

The pipeline improved setup margin by 0.13 ns and reduced area by 3.62%.

The single-cycle critical path started at `imem_rdata[19]` and ended at
`dmem_addr[31]`. The pipeline path started at a mapped flip-flop and ended
at `dmem_addr[30]`.

The pipeline boundary eliminated the direct instruction-input-to-data-address
path. Taken branches and JAL incur one flush bubble.

Functional checks passed: unit tests, CPU regression, wrong-path flush
verification and 100 randomized differential programs.

See the [project README](../../../README.md) for the frequency sweep,
workload measurements and reproduction commands.
