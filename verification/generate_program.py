import argparse
import json
import random

from reference_model import TinyRV32Reference


PROGRAM_LENGTH = 55
DMEM_WORDS = 64

# x1..x12 are available to random arithmetic instructions
# x13 is reserved as JAL link register
# x14 and x15 are reserved for deterministic branch conditions
GENERAL_REG_MAX = 12
JAL_LINK_REG = 13
CTRL_A = 14
CTRL_B = 15


def r_type(funct7, funct3, rs2, rs1, rd):
    return (
        (funct7 << 25)
        | (rs2 << 20)
        | (rs1 << 15)
        | (funct3 << 12)
        | (rd << 7)
        | 0b0110011
    )


def add(rd, rs1, rs2):
    return r_type(0b0000000, 0b000, rs2, rs1, rd)


def sub(rd, rs1, rs2):
    return r_type(0b0100000, 0b000, rs2, rs1, rd)


def and_(rd, rs1, rs2):
    return r_type(0b0000000, 0b111, rs2, rs1, rd)


def or_(rd, rs1, rs2):
    return r_type(0b0000000, 0b110, rs2, rs1, rd)


def xor(rd, rs1, rs2):
    return r_type(0b0000000, 0b100, rs2, rs1, rd)


def sll(rd, rs1, rs2):
    return r_type(0b0000000, 0b001, rs2, rs1, rd)


def srl(rd, rs1, rs2):
    return r_type(0b0000000, 0b101, rs2, rs1, rd)


def slt(rd, rs1, rs2):
    return r_type(0b0000000, 0b010, rs2, rs1, rd)


def addi(rd, rs1, imm):
    imm &= 0xFFF

    return (
        (imm << 20)
        | (rs1 << 15)
        | (0b000 << 12)
        | (rd << 7)
        | 0b0010011
    )


def lw(rd, rs1, imm):
    imm &= 0xFFF

    return (
        (imm << 20)
        | (rs1 << 15)
        | (0b010 << 12)
        | (rd << 7)
        | 0b0000011
    )


def sw(rs2, rs1, imm):
    imm &= 0xFFF

    imm_11_5 = (imm >> 5) & 0x7F
    imm_4_0 = imm & 0x1F

    return (
        (imm_11_5 << 25)
        | (rs2 << 20)
        | (rs1 << 15)
        | (0b010 << 12)
        | (imm_4_0 << 7)
        | 0b0100011
    )


def branch(funct3, rs1, rs2, imm):
    if imm % 2 != 0:
        raise ValueError("Branch offset must be even")

    imm &= 0x1FFF

    bit12 = (imm >> 12) & 0x1
    bit11 = (imm >> 11) & 0x1
    bits10_5 = (imm >> 5) & 0x3F
    bits4_1 = (imm >> 1) & 0xF

    return (
        (bit12 << 31)
        | (bits10_5 << 25)
        | (rs2 << 20)
        | (rs1 << 15)
        | (funct3 << 12)
        | (bits4_1 << 8)
        | (bit11 << 7)
        | 0b1100011
    )


def beq(rs1, rs2, imm):
    return branch(0b000, rs1, rs2, imm)


def bne(rs1, rs2, imm):
    return branch(0b001, rs1, rs2, imm)


def jal(rd, imm):
    if imm % 2 != 0:
        raise ValueError("JAL offset must be even")

    imm &= 0x1FFFFF

    bit20 = (imm >> 20) & 0x1
    bits10_1 = (imm >> 1) & 0x3FF
    bit11 = (imm >> 11) & 0x1
    bits19_12 = (imm >> 12) & 0xFF

    return (
        (bit20 << 31)
        | (bits10_1 << 21)
        | (bit11 << 20)
        | (bits19_12 << 12)
        | (rd << 7)
        | 0b1101111
    )


def random_reg():
    return random.randint(1, GENERAL_REG_MAX)


def random_payload():
    return addi(
        random_reg(),
        random_reg(),
        random.randint(-64, 63)
    )


def generate():
    program = []

    # Initialize every register available to random datapath operations.
    for rd in range(1, GENERAL_REG_MAX + 1):
        value = random.randint(-100, 100)
        program.append(addi(rd, 0, value))

    # Reserved control-flow registers.
    program.append(addi(JAL_LINK_REG, 0, 0))
    program.append(addi(CTRL_A, 0, 1))
    program.append(addi(CTRL_B, 0, 2))

    # Guaranteed control-flow coverage in every generated test.
    # Offset +8 means: skip exactly one 32-bit instruction.

    # BEQ taken: 1 == 1
    program.append(beq(CTRL_A, CTRL_A, 8))
    program.append(random_payload())

    # BEQ not taken: 1 != 2
    program.append(beq(CTRL_A, CTRL_B, 8))
    program.append(random_payload())

    # BNE taken: 1 != 2
    program.append(bne(CTRL_A, CTRL_B, 8))
    program.append(random_payload())

    # BNE not taken: 1 == 1
    program.append(bne(CTRL_A, CTRL_A, 8))
    program.append(random_payload())

    # JAL always taken and writes return address to x13
    program.append(jal(JAL_LINK_REG, 8))
    program.append(random_payload())

    generators = [
        lambda: add(random_reg(), random_reg(), random_reg()),
        lambda: sub(random_reg(), random_reg(), random_reg()),
        lambda: and_(random_reg(), random_reg(), random_reg()),
        lambda: or_(random_reg(), random_reg(), random_reg()),
        lambda: xor(random_reg(), random_reg(), random_reg()),
        lambda: sll(random_reg(), random_reg(), random_reg()),
        lambda: srl(random_reg(), random_reg(), random_reg()),
        lambda: slt(random_reg(), random_reg(), random_reg()),

        lambda: addi(
            random_reg(),
            random_reg(),
            random.randint(-128, 127)
        ),

        lambda: sw(
            random_reg(),
            0,
            random.randrange(0, 64, 4)
        ),

        lambda: lw(
            random_reg(),
            0,
            random.randrange(0, 64, 4)
        ),
    ]

    while len(program) < PROGRAM_LENGTH:
        program.append(random.choice(generators)())

    # Terminal infinite loop
    program.append(0x0000006F)

    return program


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--seed", type=int, default=42)
    args = parser.parse_args()

    random.seed(args.seed)

    program = generate()

    cpu = TinyRV32Reference(
        program,
        memory_words=DMEM_WORDS
    )

    cpu.run(max_steps=200)

    # Pad instruction memory to 64 words
    padded_program = program + [
        0x00000013
    ] * (64 - len(program))

    with open(
        "verification/generated/program.hex",
        "w",
        encoding="utf-8"
    ) as f:
        for instr in padded_program:
            f.write(f"{instr:08x}\n")

    expected = {
        "seed": args.seed,
        "registers": cpu.regs,
        "memory": cpu.dmem,
        "pc": cpu.pc,
        "steps": cpu.steps,
        "coverage": cpu.coverage,
        "trace": cpu.trace,
    }

    with open(
        "verification/generated/expected.json",
        "w",
        encoding="utf-8"
    ) as f:
        json.dump(expected, f, indent=2)

    print(f"Generated program for seed {args.seed}")
    print(f"Program words: {len(program)}")
    print(f"Executed instructions: {cpu.steps}")


if __name__ == "__main__":
    main()
