"""Compare ordered commits and actual memory writes against the reference."""

import argparse
import json
from pathlib import Path
import re
import sys

FIELDS = ("pc", "instruction", "next_pc", "rd", "rd_data", "store",
          "address", "store_data")
STORE_FIELDS = ("pc", "address", "store_data")


def read_trace(path, fields=FIELDS):
    records = []
    for number, line in enumerate(Path(path).read_text().splitlines(), 1):
        values = line.split()
        if len(values) != len(fields) or any(
                not re.fullmatch(r"[0-9a-fA-F]{8}", v) for v in values):
            raise ValueError(f"Malformed/unknown trace at record {number}")
        records.append(dict(zip(fields, (int(v, 16) for v in values))))
    return records


def compare(expected, actual, fields=FIELDS):
    if len(expected) != len(actual):
        raise ValueError(f"Commit count: RTL={len(actual)}, REF={len(expected)}")
    for index, (wanted, observed) in enumerate(zip(expected, actual)):
        if set(wanted) != set(fields) or set(observed) != set(fields):
            raise ValueError(f"Incomplete or extra fields at record {index}")
        if observed != wanted:
            differences = ", ".join(
                f"{key}: RTL={observed[key]:08x}, REF={wanted[key]:08x}"
                for key in wanted if observed[key] != wanted[key])
            raise ValueError(f"Commit {index}, PC={wanted['pc']:08x}: {differences}")


def compare_stores(expected_trace, actual_stores):
    expected_stores = [
        {field: record[field] for field in STORE_FIELDS}
        for record in expected_trace if record["store"]
    ]
    try:
        compare(expected_stores, actual_stores, STORE_FIELDS)
    except ValueError as error:
        raise ValueError(f"Memory writes: {error}") from error


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--expected", type=Path,
                        default=Path("verification/generated/expected.json"))
    parser.add_argument("--trace", type=Path,
                        default=Path("verification/generated/rtl_trace.txt"))
    parser.add_argument("--stores", type=Path,
                        default=Path("verification/generated/rtl_stores.txt"))
    args = parser.parse_args()
    try:
        expected = json.loads(args.expected.read_text())["trace"]
        compare(expected, read_trace(args.trace))
        stores = read_trace(args.stores, STORE_FIELDS)
        compare_stores(expected, stores)
    except (ValueError, KeyError, OSError) as error:
        print(f"TRACE TEST FAILED: {error}")
        return 1
    print(f"TRACE TEST PASSED: {len(expected)} ordered commits, {len(stores)} memory writes")
    return 0


if __name__ == "__main__":
    sys.exit(main())
