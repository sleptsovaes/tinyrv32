"""Fault-detection tests for the verification infrastructure itself."""
import copy
from pathlib import Path
import tempfile
import unittest
from compare_state import compare as compare_state, parse_rtl_state
from compare_trace import compare as compare_trace, read_trace, FIELDS

class StateCheckerTests(unittest.TestCase):
    def setUp(self):
        self.expected = dict(pc=0x100, registers=[0]*32, memory=[0]*64)
        self.lines = ['PC 00000100'] + [f'X{i} 00000000' for i in range(32)] + [f'M{i} 00000000' for i in range(64)]

    def parse(self, lines):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)/'state.txt'
            path.write_text('\n'.join(lines)+'\n')
            return parse_rtl_state(path)

    def test_valid_state(self):
        self.assertEqual(compare_state(self.expected, self.parse(self.lines)), [])

    def test_every_state_field_is_checked(self):
        for index, line in enumerate(self.lines):
            with self.subTest(field=line.split()[0]):
                changed = self.lines.copy()
                key, old = changed[index].split()
                changed[index] = f'{key} {int(old,16)^1:08x}'
                self.assertTrue(compare_state(self.expected, self.parse(changed)))

    def test_every_missing_field_is_rejected(self):
        for index in range(len(self.lines)):
            with self.subTest(index=index), self.assertRaises(ValueError):
                self.parse(self.lines[:index]+self.lines[index+1:])

    def test_bad_dump_is_rejected(self):
        for replacement in ['X1 xxxxxxxx','X1 0000000z','X1 100000000','X1 -0000001','bad line extra']:
            with self.subTest(replacement=replacement), self.assertRaises(ValueError):
                self.parse(self.lines[:2]+[replacement]+self.lines[3:])
        for extra in ['X1 00000000','X32 00000000','M64 00000000']:
            with self.subTest(extra=extra), self.assertRaises(ValueError):
                self.parse(self.lines+[extra])

class TraceCheckerTests(unittest.TestCase):
    def setUp(self):
        self.trace = [dict(zip(FIELDS, [0,0x13,4,1,5,0,0,0])),
                      dict(zip(FIELDS, [4,0x13,8,1,0,0,0,0]))]

    def test_transient_error_is_detected(self):
        bad = copy.deepcopy(self.trace)
        bad[0]['rd_data'] = 99
        with self.assertRaisesRegex(ValueError, 'Commit 0'):
            compare_trace(self.trace,bad)

    def test_each_trace_field_is_checked(self):
        for field in FIELDS:
            bad=copy.deepcopy(self.trace); bad[0][field] ^= 1
            with self.subTest(field=field), self.assertRaises(ValueError):
                compare_trace(self.trace,bad)

    def test_missing_duplicate_and_reordered_commits(self):
        for bad in [self.trace[:1], self.trace+[self.trace[-1]], self.trace[::-1]]:
            with self.assertRaises(ValueError): compare_trace(self.trace,bad)

    def test_unknown_trace(self):
        with tempfile.TemporaryDirectory() as directory:
            path=Path(directory)/'trace.txt'; path.write_text('xxxxxxxx '*8)
            with self.assertRaises(ValueError): read_trace(path)

if __name__ == '__main__': unittest.main()
