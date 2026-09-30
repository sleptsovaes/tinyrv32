import json
import argparse
import random

from reference_model import TinyRV32Reference


# SEED = 42
PROGRAM_LENGTH = 40
DMEM_WORDS = 64

# random.seed(SEED)


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


def random_reg():
    return random.randint(1, 15)


def generate():
    program = []

    # Seed several registers with non-zero values
    for rd in range(1, 16):
        value = random.randint(-100, 100)
        program.append(addi(rd, 0, value))

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

        # Use x0 as the memory base so addresses stay valid/aligned
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

    # Terminal loop
    program.append(0x0000006F)

    return program


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--seed", type=int, default=42)
    args = parser.parse_args()

    random.seed(args.seed)

    program = generate()

    cpu = TinyRV32Reference(program, memory_words=DMEM_WORDS)
    cpu.run(max_steps=200)

    with open(
        "verification/generated/program.hex",
        "w",
        encoding="utf-8"
    ) as f:
        for instr in program:
            f.write(f"{instr:08x}\n")

    expected = {
        "seed": args.seed,
        "registers": cpu.regs,
        "memory": cpu.dmem,
        "pc": cpu.pc,
        "steps": cpu.steps,
    }

    with open(
        "verification/generated/expected.json",
        "w",
        encoding="utf-8"
    ) as f:
        json.dump(expected, f, indent=2)

    print(f"Generated {len(program)} words")
    print(f"Reference model executed {cpu.steps} instructions")
    print(f"Seed = {args.seed}")

if __name__ == "__main__":
    main()
