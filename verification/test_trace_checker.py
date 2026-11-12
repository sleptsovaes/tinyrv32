"""Fault-detection tests for ordered commits and external memory writes."""

import copy
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

from compare_trace import FIELDS, STORE_FIELDS, compare, compare_stores, read_trace
from reference_model import TinyRV32Reference


class TraceCheckerTests(unittest.TestCase):
    def setUp(self):
        # Hand-calculated ADDI x1, x0, 7; SW x1, 0(x0); ADDI x1, x0, 0.
        self.trace = [
            dict(zip(FIELDS, [0, 0x00700093, 4, 1, 7, 0, 0, 0])),
            dict(zip(FIELDS, [4, 0x00102023, 8, 0, 0, 1, 0, 7])),
            dict(zip(FIELDS, [8, 0x00000093, 12, 1, 0, 0, 0, 0])),
        ]
        self.stores = [dict(zip(STORE_FIELDS, [4, 0, 7]))]

    def test_valid_commits_and_writes(self):
        compare(self.trace, self.trace)
        compare_stores(self.trace, self.stores)

    def test_every_commit_field_is_checked(self):
        for field in FIELDS:
            changed = copy.deepcopy(self.trace)
            changed[0][field] ^= 1
            with self.subTest(field=field), self.assertRaises(ValueError):
                compare(self.trace, changed)

    def test_missing_extra_and_reordered_commits(self):
        for changed in [self.trace[1:], self.trace + self.trace[:1], self.trace[::-1]]:
            with self.subTest(trace=changed), self.assertRaises(ValueError):
                compare(self.trace, changed)

    def test_incomplete_and_extra_record_fields(self):
        for field in FIELDS:
            changed = copy.deepcopy(self.trace)
            del changed[0][field]
            with self.subTest(field=field), self.assertRaises(ValueError):
                compare(self.trace, changed)
        changed = copy.deepcopy(self.trace)
        changed[0]["extra"] = 0
        with self.assertRaises(ValueError):
            compare(self.trace, changed)

    def test_unknown_and_malformed_trace_is_rejected(self):
        for line in ["xxxxxxxx " * 8, "0000000z " * 8,
                     "100000000 " * 8, "00000000 " * 7, ""]:
            with self.subTest(line=line), tempfile.TemporaryDirectory() as directory:
                path = Path(directory) / "trace.txt"
                path.write_text(line + "\n", encoding="utf-8")
                with self.assertRaises(ValueError):
                    read_trace(path)

    def test_actual_write_fields_are_checked_even_when_commits_match(self):
        compare(self.trace, self.trace)
        for field in STORE_FIELDS:
            changed = copy.deepcopy(self.stores)
            changed[0][field] ^= 1
            with self.subTest(field=field), self.assertRaisesRegex(ValueError, "Memory writes"):
                compare_stores(self.trace, changed)

    def test_missing_extra_and_reordered_actual_writes(self):
        second = dict(self.trace[1], pc=12, next_pc=16)
        expected = self.trace + [second]
        actual = self.stores + [dict(self.stores[0], pc=12)]
        for changed in [actual[:1], actual + actual[:1], actual[::-1]]:
            with self.subTest(writes=changed), self.assertRaises(ValueError):
                compare_stores(expected, changed)

    def test_empty_program_trace(self):
        compare([], [])
        compare_stores([], [])

    def test_reference_trace_matches_hand_calculated_goldens(self):
        model = TinyRV32Reference([0x00700093, 0x00102023, 0x00000093, 0x0000006F])
        model.run()
        self.assertEqual(model.trace, self.trace)
        self.assertEqual((model.regs[1], model.dmem[0]), (0, 7))

    def test_cli_rejects_bad_commits_and_bad_writes(self):
        for corrupt in ["commits", "writes"]:
            with self.subTest(corrupt=corrupt), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                expected = root / "expected.json"
                trace = root / "trace.txt"
                stores = root / "stores.txt"
                expected.write_text(json.dumps({"trace": self.trace}), encoding="utf-8")
                observed = copy.deepcopy(self.trace)
                observed_stores = copy.deepcopy(self.stores)
                if corrupt == "commits":
                    observed[0]["rd_data"] = 99
                else:
                    observed_stores[0]["store_data"] = 99
                for path, records, fields in [(trace, observed, FIELDS),
                                               (stores, observed_stores, STORE_FIELDS)]:
                    path.write_text("".join(
                        " ".join(f"{record[field]:08x}" for field in fields) + "\n"
                        for record in records), encoding="utf-8")
                result = subprocess.run(
                    [sys.executable, str(Path(__file__).with_name("compare_trace.py")),
                     "--expected", str(expected), "--trace", str(trace), "--stores", str(stores)],
                    capture_output=True, text=True, check=False,
                )
                self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertIn("TRACE TEST FAILED", result.stdout)


if __name__ == "__main__":
    unittest.main()
