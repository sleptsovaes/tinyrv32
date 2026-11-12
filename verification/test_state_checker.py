"""Verify that corrupted or incomplete architectural dumps cannot pass."""

import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

from compare_state import compare, parse_rtl_state


CHECKER = Path(__file__).with_name("compare_state.py")


class StateCheckerTests(unittest.TestCase):
    def setUp(self):
        self.expected = {
            "pc": 0x100,
            "registers": [0] + [0x10203040 + i for i in range(1, 32)],
            "memory": [0xA0B0C000 + i for i in range(64)],
        }
        self.lines = ["PC 00000100"]
        self.lines += [f"X{i} {value:08x}" for i, value in enumerate(self.expected["registers"])]
        self.lines += [f"M{i} {value:08x}" for i, value in enumerate(self.expected["memory"])]

    def parse(self, lines):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "state.txt"
            path.write_text("\n".join(lines) + "\n", encoding="utf-8")
            return parse_rtl_state(path)

    def run_cli(self, directory, lines):
        directory = Path(directory)
        expected = directory / "expected.json"
        state = directory / "state.txt"
        expected.write_text(json.dumps(self.expected), encoding="utf-8")
        state.write_text("\n".join(lines) + "\n", encoding="utf-8")
        return subprocess.run(
            [sys.executable, str(CHECKER), "--expected", str(expected), "--state", str(state)],
            capture_output=True, text=True, check=False,
        )

    def test_complete_state_passes(self):
        self.assertEqual(compare(self.expected, self.parse(self.lines)), [])

    def test_every_state_value_is_checked(self):
        for index, line in enumerate(self.lines):
            key, value = line.split()
            changed = self.lines.copy()
            changed[index] = f"{key} {int(value, 16) ^ 1:08x}"
            with self.subTest(field=key):
                errors = compare(self.expected, self.parse(changed))
                self.assertEqual(len(errors), 1)
                self.assertTrue(errors[0].startswith(key + ":"))

    def test_every_missing_field_is_rejected(self):
        for index, line in enumerate(self.lines):
            with self.subTest(field=line.split()[0]), self.assertRaises(ValueError):
                self.parse(self.lines[:index] + self.lines[index + 1:])

    def test_duplicate_and_unknown_fields_are_rejected(self):
        for extra in [self.lines[0], self.lines[32], self.lines[-1],
                      "X32 00000000", "M64 00000000", "UNKNOWN 00000000"]:
            with self.subTest(extra=extra), self.assertRaises(ValueError):
                self.parse(self.lines + [extra])

    def test_malformed_values_are_rejected(self):
        for bad in ["X1 xxxxxxxx", "X1 0000000z", "X1 100000000",
                    "X1 -0000001", "X1 1", "X1", "X1 00000000 extra", ""]:
            changed = self.lines.copy()
            changed[2] = bad
            with self.subTest(line=bad), self.assertRaises(ValueError):
                self.parse(changed)

    def test_array_length_mismatches_are_rejected(self):
        pc, registers, memory = self.parse(self.lines)
        for actual in [(pc, registers[:-1], memory), (pc, registers, memory[:-1])]:
            with self.subTest(actual_lengths=(len(actual[1]), len(actual[2]))):
                with self.assertRaises(ValueError):
                    compare(self.expected, actual)
        bad_reference = dict(self.expected, registers=registers[:-1])
        with self.assertRaises(ValueError):
            compare(bad_reference, (pc, registers, memory))

    def test_cli_returns_success_for_valid_state(self):
        with tempfile.TemporaryDirectory() as directory:
            result = self.run_cli(directory, self.lines)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("DIFFERENTIAL TEST PASSED", result.stdout)

    def test_cli_fails_for_previously_missed_corruption(self):
        cases = {}
        for key in ["X31", "M0"]:
            changed = self.lines.copy()
            index = next(i for i, line in enumerate(changed) if line.startswith(key + " "))
            changed[index] = key + " ffffffff"
            cases[key] = changed
        cases["missing_memory"] = self.lines[:33]
        for name, lines in cases.items():
            with self.subTest(case=name), tempfile.TemporaryDirectory() as directory:
                result = self.run_cli(directory, lines)
                self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertIn("DIFFERENTIAL TEST FAILED", result.stdout)


if __name__ == "__main__":
    unittest.main()
