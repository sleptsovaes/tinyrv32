import json
import sys


def parse_rtl_state(path):
    regs = [0] * 32
    memory = [0] * 64
    pc = None

    with open(path, encoding="utf-8") as f:
        for line in f:
            key, value = line.split()
            if "x" in value.lower() or "z" in value.lower():
                raise ValueError(
                    f"RTL contains unknown value: {key} = {value}"
                )

            value = int(value, 16)

            if key == "PC":
                pc = value

            elif key.startswith("X"):
                index = int(key[1:])
                regs[index] = value

            elif key.startswith("M"):
                index = int(key[1:])
                memory[index] = value

    return pc, regs, memory


def main():
    with open(
        "verification/generated/expected.json",
        encoding="utf-8"
    ) as f:
        expected = json.load(f)

    rtl_pc, rtl_regs, rtl_memory = parse_rtl_state(
        "verification/generated/rtl_state.txt"
    )

    errors = 0

    ref_pc = expected["pc"]

    if rtl_pc != ref_pc:
        print(
            f"FAIL PC: "
            f"RTL=0x{rtl_pc:08X} "
            f"REF=0x{ref_pc:08X}"
        )
        errors += 1

    for i in range(16):
        rtl = rtl_regs[i]
        ref = expected["registers"][i]

        if rtl != ref:
            print(
                f"FAIL X{i}: "
                f"RTL=0x{rtl:08X} "
                f"REF=0x{ref:08X}"
            )
            errors += 1
    if errors:
        print(f"DIFFERENTIAL TEST FAILED: {errors} mismatch(es)")
        sys.exit(1)

    print("DIFFERENTIAL TEST PASSED")
    print("RTL state matches Python reference model")


if __name__ == "__main__":
    main()
