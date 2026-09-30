MASK32 = 0xFFFFFFFF


def u32(value):
    return value & MASK32


def s32(value):
    value &= MASK32
    if value & 0x80000000:
        return value - 0x100000000
    return value


def sign_extend(value, bits):
    sign_bit = 1 << (bits - 1)
    return (value & (sign_bit - 1)) - (value & sign_bit)


class TinyRV32Reference:
    def __init__(self, program, memory_words=64):
        self.regs = [0] * 32
        self.pc = 0

        self.imem = list(program)
        self.dmem = [0] * memory_words

        self.steps = 0

    def fetch(self):
        index = self.pc >> 2

        if index < 0 or index >= len(self.imem):
            raise RuntimeError(
                f"PC out of instruction memory: 0x{self.pc:08X}"
            )

        return self.imem[index]

    def write_reg(self, rd, value):
        if rd != 0:
            self.regs[rd] = u32(value)

        self.regs[0] = 0

    def load_word(self, address):
        if address & 0x3:
            raise RuntimeError(
                f"Unaligned LW address: 0x{address:08X}"
            )

        index = address >> 2

        if index < 0 or index >= len(self.dmem):
            raise RuntimeError(
                f"LW outside data memory: 0x{address:08X}"
            )

        return self.dmem[index]

    def store_word(self, address, value):
        if address & 0x3:
            raise RuntimeError(
                f"Unaligned SW address: 0x{address:08X}"
            )

        index = address >> 2

        if index < 0 or index >= len(self.dmem):
            raise RuntimeError(
                f"SW outside data memory: 0x{address:08X}"
            )

        self.dmem[index] = u32(value)

    def step(self):
        instr = self.fetch()

        opcode = instr & 0x7F
        rd = (instr >> 7) & 0x1F
        funct3 = (instr >> 12) & 0x7
        rs1 = (instr >> 15) & 0x1F
        rs2 = (instr >> 20) & 0x1F
        funct7 = (instr >> 25) & 0x7F

        a = self.regs[rs1]
        b = self.regs[rs2]

        next_pc = u32(self.pc + 4)

        # R-TYPE

        if opcode == 0b0110011:

            if funct3 == 0b000:
                if funct7 == 0b0100000:
                    result = a - b          # SUB
                else:
                    result = a + b          # ADD

            elif funct3 == 0b111:
                result = a & b              # AND

            elif funct3 == 0b110:
                result = a | b              # OR

            elif funct3 == 0b100:
                result = a ^ b              # XOR

            elif funct3 == 0b001:
                result = a << (b & 0x1F)    # SLL

            elif funct3 == 0b101:
                result = a >> (b & 0x1F)    # SRL

            elif funct3 == 0b010:
                result = int(s32(a) < s32(b))  # SLT

            else:
                raise RuntimeError(
                    f"Unsupported R-type funct3={funct3:03b}"
                )

            self.write_reg(rd, result)

        # ADDI

        elif opcode == 0b0010011:

            if funct3 != 0b000:
                raise RuntimeError("Unsupported OP-IMM instruction")

            imm = sign_extend(instr >> 20, 12)

            self.write_reg(rd, a + imm)

        # LW

        elif opcode == 0b0000011:

            if funct3 != 0b010:
                raise RuntimeError("Unsupported LOAD instruction")

            imm = sign_extend(instr >> 20, 12)
            address = u32(a + imm)

            self.write_reg(
                rd,
                self.load_word(address)
            )

        # SW

        elif opcode == 0b0100011:

            if funct3 != 0b010:
                raise RuntimeError("Unsupported STORE instruction")

            imm_raw = (
                ((instr >> 25) & 0x7F) << 5
            ) | (
                (instr >> 7) & 0x1F
            )

            imm = sign_extend(imm_raw, 12)
            address = u32(a + imm)

            self.store_word(address, b)

        # BEQ / BNE

        elif opcode == 0b1100011:

            imm_raw = (
                ((instr >> 31) & 0x1) << 12
                | ((instr >> 7) & 0x1) << 11
                | ((instr >> 25) & 0x3F) << 5
                | ((instr >> 8) & 0xF) << 1
            )

            imm = sign_extend(imm_raw, 13)

            if funct3 == 0b000:       # BEQ
                taken = a == b

            elif funct3 == 0b001:     # BNE
                taken = a != b

            else:
                raise RuntimeError("Unsupported BRANCH instruction")

            if taken:
                next_pc = u32(self.pc + imm)

        # JAL

        elif opcode == 0b1101111:

            imm_raw = (
                ((instr >> 31) & 0x1) << 20
                | ((instr >> 12) & 0xFF) << 12
                | ((instr >> 20) & 0x1) << 11
                | ((instr >> 21) & 0x3FF) << 1
            )

            imm = sign_extend(imm_raw, 21)

            self.write_reg(rd, self.pc + 4)
            next_pc = u32(self.pc + imm)

        else:
            raise RuntimeError(
                f"Unsupported opcode 0x{opcode:02X} "
                f"at PC 0x{self.pc:08X}"
            )

        self.pc = next_pc
        self.regs[0] = 0
        self.steps += 1

    def run(self, max_steps=100):
        for _ in range(max_steps):

            instr = self.fetch()

            # jal x0, 0
            # Used by our RTL test program as a terminal loop.
            if instr == 0x0000006F:
                return

            self.step()

        raise RuntimeError(
            f"Program did not terminate after {max_steps} steps"
        )


PROGRAM = [
    0x00500093,  # addi x1, x0, 5
    0x00700113,  # addi x2, x0, 7
    0x002081B3,  # add  x3, x1, x2
    0x00302023,  # sw   x3, 0(x0)
    0x00002203,  # lw   x4, 0(x0)
    0x00000313,  # addi x6, x0, 0
    0x00418463,  # beq  x3, x4, +8
    0x06300313,  # addi x6, x0, 99 -- must be skipped
    0x02A00293,  # addi x5, x0, 42
    0x0000006F,  # jal  x0, 0
]


def check(name, actual, expected):
    if actual != expected:
        raise AssertionError(
            f"{name}: expected {expected}, got {actual}"
        )

    print(f"PASS: {name} = {actual}")


if __name__ == "__main__":

    cpu = TinyRV32Reference(PROGRAM)
    cpu.run()

    check("x0", cpu.regs[0], 0)
    check("x1", cpu.regs[1], 5)
    check("x2", cpu.regs[2], 7)
    check("x3", cpu.regs[3], 12)
    check("x4", cpu.regs[4], 12)
    check("x5", cpu.regs[5], 42)
    check("x6", cpu.regs[6], 0)

    check("memory[0]", cpu.dmem[0], 12)

    print("REFERENCE MODEL PASSED")
    print(f"Executed instructions: {cpu.steps}")
