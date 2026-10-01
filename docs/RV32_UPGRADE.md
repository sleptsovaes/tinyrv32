# RV32 execution-core upgrade

The upgrade adds a separately verified execution core, a memory interface with
wait states, compiled C firmware, a static branch-prediction experiment and a
small RAM/UART SoC. The historical `cpu_core.sv` and its physical measurements
remain a separate experiment.

## Reproduce the checks

Required: Python 3, Make and Icarus Verilog. The firmware checks additionally
require GNU RISC-V GCC and binutils with an RV32I/ILP32 target. Yosys is needed
for the optional bounded safety and structural synthesis checks.

On Ubuntu 24.04:

```bash
sudo apt-get update
sudo apt-get install iverilog gcc-riscv64-unknown-elf binutils-riscv64-unknown-elf yosys
make test
make upgrade
make formal synth-upgrade
```

`make upgrade` runs the full matrix, including 100 deterministic random
programs. `make upgrade-quick` runs two fixed memory modes with ten random
programs. A compiler-free subset is available with
`python3 verification/run_upgrade.py --skip-c`; it does not test compiled C or
the serial UART SoC. A different compiler prefix can be selected with
`RISCV_PREFIX=riscv32-unknown-elf- make upgrade`.

`IVERILOG`, `VVP` and `YOSYS` can also be overridden. The Python runners accept
executable arguments in those environment variables. Generated images, ELF,
disassembly, state dumps, ordered traces and simulator logs are written below
`build/upgrade/`. The report records the source hashes and tool versions used
in that run. Committed evidence is in
[verification/upgrade/results](../verification/upgrade/results/).

The GitHub Actions workflow runs these commands on pushes and pull requests.
It was added here; its hosted execution has not yet been observed.

## Architectural scope

`rtl/rv32_core.sv` provides these 38 normally completing RV32I instructions:

| Group | Instructions |
|---|---|
| Upper immediate | LUI, AUIPC |
| Jumps | JAL, JALR |
| Conditional branches | BEQ, BNE, BLT, BGE, BLTU, BGEU |
| Immediate operations | ADDI, SLTI, SLTIU, XORI, ORI, ANDI, SLLI, SRLI, SRAI |
| Register operations | ADD, SUB, SLL, SLT, SLTU, XOR, SRL, SRA, OR, AND |
| Loads | LB, LH, LW, LBU, LHU |
| Stores | SB, SH, SW |
| Ordering | FENCE |

ECALL and EBREAK stop precisely and expose causes 11 and 3. An illegal encoding
stops with cause 2. Misaligned instruction targets, loads and stores stop with
causes 0, 4 and 6. `trap_pc` identifies the faulting instruction; that instruction
does not commit or write a link register. An untaken branch does not fault just
because its encoded target is misaligned. JALR clears target bit zero before
checking four-byte alignment.

This is a small execution environment, rather than a privileged machine:
there are no CSRs, interrupt controller, trap-vector handler, M/C extensions or
FENCE.I. There are no bus-error inputs or access-fault handling. FENCE completes
as a no-op because data operations complete in program order. No RISC-V
architectural certification or full ISA formal equivalence is claimed.

All registers are synchronously reset to zero, an implementation choice beyond
the ISA requirement for `x0`. Reset starts execution at address zero and cancels
pending operations. The core does not reset external RAM contents.

Fetch and Execute are the execution stages. A one-entry elastic fetch buffer
holds a prefetched instruction while Execute waits for data memory. Register
operands are read in Execute, after any preceding instruction commits. Each
instruction carries its PC and predicted next PC. A prediction miss discards
the Execute entry and fetch buffer and restarts at the actual next PC.

`STATIC_PREDICT=0` predicts sequential execution. `STATIC_PREDICT=1` predicts
backward conditional branches taken, forward conditional branches not taken,
and the target of direct JAL. JALR resolves in Execute. Both modes execute the
same architectural instruction stream in the regression.

## Memory completion contract

These are completion interfaces, not AXI or a request/response interface with
separate acceptance and response events. At most one instruction request and
one data request are outstanding.

| Signal/event | Contract |
|---|---|
| `imem_valid` / `dmem_valid` | An operation is pending. |
| `valid && ready` at the rising edge | That operation completes; read data must be valid at this edge. |
| `valid && !ready` | The core holds address and data payload stable. |
| Store completion | The memory applies the store once, at this edge. |
| `imem_cancel` | Discard the pending fetch and any response on this edge; cancellation wins over readiness. |
| Reset | Cancels both interfaces and suppresses architectural side effects. |

Data transactions cannot be cancelled except by reset. Instruction transactions
may be cancelled by a redirect or precise stop. A delayed-memory adapter must
drop cancelled fetches rather than return an old response for a new address.

Addresses are byte addresses. Read data is the containing aligned 32-bit word,
in little-endian order. Store data is already shifted to the addressed byte
lane; `dmem_wstrb` selects which lanes to update. Misaligned halfword and word
accesses stop before issuing a memory operation. Valid combinational memories
can complete in the same cycle; registered memories return a later completion.

## Verification and limits

The original differential checker now rejects missing, duplicate, malformed
and unknown fields and checks **all 32 registers and all 64 memory words**.
It additionally checks the ordered commit stream. Eleven checker/oracle unit
tests include mutations of every state field, transient trace corruption,
missing/duplicate/reordered commits and hand-calculated arithmetic/byte-order
goldens. The original 100-program regression also passes.

The upgraded core uses a separate Python RV32 reference model. Every run checks
all 32 registers, all 4096 RAM words, the fault PC and cause, and every ordered
commit. Commits include instruction, next PC, register destination/value, store
address/data and byte strobes. Loads are checked through their instruction,
destination value and final memory; the trace is a project-specific debug
interface and is not RVFI.

The full matrix has 123 test cases and 978 core simulations: both predictor
modes, zero-wait memory, registered data reads with one additional cycle,
registered instruction/data reads with 1/3 additional cycles, and deterministic
random delays of 1–4 cycles. The reset-during-pending-store case uses only the
1/3 mode. Cases include directed coverage of all 38 instructions, all six
branch outcomes, byte/halfword lanes, wrong-path stores, 13 precise-stop cases,
an untaken branch with a misaligned target, six workloads, 100 random programs
and compiled C. The harness checks stable requests and that each accepted store
corresponds to exactly one architectural commit.

Instruction coverage counts in the JSON report count reference execution once
per test case, rather than summing identical executions across memory modes.
Random programs emphasize arithmetic and memory; directed cases and C supply
branch, jump, byte/halfword and fault coverage. This is substantial regression
evidence, not exhaustive coverage of every encoding, value or timing sequence.

`make formal` checks protocol safety through six sampled cycles for both
predictor modes with unconstrained instructions, ready signals and read data.
It assumes a zero initial state and reset at the first sampled cycle. Properties
cover stable waiting requests, `x0`, side-effect suppression, register stability
without a commit and flushing after a prediction miss. This short bounded
check is not an unbounded proof or an instruction-equivalence proof. The depth
can be changed with `python3 verification/run_safety.py --depth 8`;
runtime rises sharply. Eight cycles exceeded the 60-second solver budget in
the initial experiment.

`make synth-upgrade` synthesizes both core configurations without technology
mapping and checks for structural errors and inferred latches. It also checks
the SoC with its 4096-word RAM preserved. This establishes tool acceptance,
not FPGA block-RAM placement, routing, area or achievable frequency.

## C firmware and serial UART

`sw/start.S` initializes the stack, clears BSS, calls `main`, writes its return
value to the status port and ends with EBREAK. The linker reserves a 16 KiB RAM
address space and checks that at least 2 KiB is left for the stack.

GCC compiles `sw/examples.c` with `-march=rv32i -mabi=ilp32 -O2`, without a C
library. Volatile input/data arrays retain the arithmetic and memory work in
the compiled program. The firmware checks CRC32 of `123456789` against
`0xcbf43926`, sorts eight signed integers, checks a 64-byte buffer sum of 10208,
and checks signed halfword accesses. Success returns zero and prints
`CRC SORT BUFFER OK` followed by a newline.

| Address | SoC function |
|---|---|
| `0x00000000`–`0x00003fff` | Unified 16 KiB RAM with registered reads |
| `0x10000000` | UART byte output; store completion waits for transmitter readiness |
| `0x10000004` | Program exit status register |

`rtl/tinyrv32_soc.sv` and `rtl/uart_tx.sv` implement the RAM/UART system. The
serial testbench decodes the actual 8N1 TX waveform, checks stop bits and checks
the 19 received bytes. It uses a divisor of four to keep simulation short and
passes after 4168 testbench clock cycles (including three reset cycles) with
prediction enabled. The UART divisor
must be chosen for a real board's clock and baud rate. No board pin constraints,
FPGA implementation or physical UART demonstration have been completed.

## Controlled prediction comparison

These are cycle counts at an identical simulation clock and memory contract.
Reset cycles are excluded; pipeline fill, firmware startup and the final
trapping cycle are included. EBREAK is not counted as a committed instruction.
For zero-wait memory the harness checks
`cycles = committed instructions + prediction misses + 2`.

| Workload, zero waits | Sequential prediction | Static prediction | Cycle reduction |
|---|---:|---:|---:|
| Taken-branch loop | 389 | 263 | 32.39% |
| JAL chain | 389 | 261 | 32.90% |
| Mixed loop | 1031 | 904 | 12.32% |
| Compiled C | 1975 | 1784 | 9.67% |

With fixed instruction/data waits of 1/3, compiled C takes 4380 versus 4189
cycles, a 4.36% reduction. Straight-line workloads receive no prediction
benefit. The random-delay generator advances with simulation cycles, so its
latency schedule differs between predictor configurations; random modes check
correctness and are excluded from performance claims.

The six inherited workloads relocate data to `0x1000` with one setup LUI so
code and data do not overlap in unified RAM. They end with EBREAK. Their counts
therefore differ from the historical Harvard-memory experiment and must not
be substituted into its 100/113 MHz timing table.

## Remaining physical evidence

The historical **113 MHz** result belongs to `cpu_core.sv`. It does not apply to
`rv32_core.sv` or to the predicted SoC. The next physical experiment must use
both new predictor configurations, identical constraints and a pinned tool
environment, record source hashes, and report timing and mapped area. Only
then can cycle savings be converted into execution-time savings or weighed
against the extra logic. A real FPGA run additionally needs board-specific
clock/reset/pin constraints and confirmation of RAM inference and UART output.
