"""Compare architectural commits in order; bubbles and terminal JAL are excluded."""

import argparse
import json
from pathlib import Path
import re
import sys

FIELDS = ("pc", "instruction", "next_pc", "rd", "rd_data", "store",
          "address", "store_data")


def read_trace(path):
    records = []
    for number, line in enumerate(Path(path).read_text().splitlines(), 1):
        values = line.split()
        if len(values) != len(FIELDS) or any(
                not re.fullmatch(r"[0-9a-fA-F]{8}", v) for v in values):
            raise ValueError(f"Malformed/unknown trace at record {number}")
        records.append(dict(zip(FIELDS, (int(v, 16) for v in values))))
    return records


def compare(expected, actual):
    if len(expected) != len(actual):
        raise ValueError(f"Commit count: RTL={len(actual)}, REF={len(expected)}")
    for index, (wanted, observed) in enumerate(zip(expected, actual)):
        if observed != wanted:
            differences = ", ".join(
                f"{key}: RTL={observed[key]:08x}, REF={wanted[key]:08x}"
                for key in wanted if observed[key] != wanted[key])
            raise ValueError(f"Commit {index}, PC={wanted['pc']:08x}: {differences}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--expected", type=Path,
                        default=Path("verification/generated/expected.json"))
    parser.add_argument("--trace", type=Path,
                        default=Path("verification/generated/rtl_trace.txt"))
    args = parser.parse_args()
    try:
        expected = json.loads(args.expected.read_text())["trace"]
        compare(expected, read_trace(args.trace))
    except (ValueError, KeyError, OSError) as error:
        print(f"TRACE TEST FAILED: {error}")
        return 1
    print(f"TRACE TEST PASSED: {len(expected)} ordered commits")
    return 0


if __name__ == "__main__":
    sys.exit(main())
