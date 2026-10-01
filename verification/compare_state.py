"""Strict architectural-state comparison: all registers and every memory word."""

import argparse
import json
from pathlib import Path
import re
import sys


def parse_rtl_state(path, memory_words=64):
    fields = {}
    for number, line in enumerate(Path(path).read_text().splitlines(), 1):
        parts = line.split()
        if len(parts) != 2:
            raise ValueError(f"Malformed state line {number}")
        key, value = parts
        if key in fields:
            raise ValueError(f"Duplicate state field {key}")
        if not re.fullmatch(r"[0-9a-fA-F]{8}", value):
            raise ValueError(f"Invalid or unknown 32-bit value: {key} = {value}")
        fields[key] = int(value, 16)
    required = {"PC"} | {f"X{i}" for i in range(32)} | {
        f"M{i}" for i in range(memory_words)
    }
    if set(fields) != required:
        missing = sorted(required - set(fields))
        extra = sorted(set(fields) - required)
        raise ValueError(f"Incomplete state: missing={missing}, extra={extra}")
    return (fields["PC"], [fields[f"X{i}"] for i in range(32)],
            [fields[f"M{i}"] for i in range(memory_words)])


def compare(expected, actual):
    pc, registers, memory = actual
    if len(expected["registers"]) != 32:
        raise ValueError("Reference must contain all 32 registers")
    errors = []
    pairs = [("PC", pc, expected["pc"])]
    pairs += [(f"X{i}", value, expected["registers"][i])
              for i, value in enumerate(registers)]
    pairs += [(f"M{i}", value, expected["memory"][i])
              for i, value in enumerate(memory)]
    for name, observed, wanted in pairs:
        if observed != wanted:
            errors.append(f"{name}: RTL=0x{observed:08X}, REF=0x{wanted:08X}")
    return errors


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--expected", type=Path,
                        default=Path("verification/generated/expected.json"))
    parser.add_argument("--state", type=Path,
                        default=Path("verification/generated/rtl_state.txt"))
    args = parser.parse_args()
    try:
        expected = json.loads(args.expected.read_text())
        actual = parse_rtl_state(args.state, len(expected["memory"]))
        errors = compare(expected, actual)
        if errors:
            print("DIFFERENTIAL TEST FAILED\n" + "\n".join(errors))
            return 1
    except (ValueError, KeyError, OSError) as error:
        print(f"DIFFERENTIAL TEST FAILED: {error}")
        return 1
    print(f"DIFFERENTIAL TEST PASSED: PC, 32 registers, {len(actual[2])} memory words")
    return 0


if __name__ == "__main__":
    sys.exit(main())
