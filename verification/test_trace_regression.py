"""RTL fault injection: detect transient errors hidden by matching final state."""

import os
from pathlib import Path
import shlex
import subprocess
import tempfile
import unittest

from compare_state import compare as compare_state, parse_rtl_state
from compare_trace import compare as compare_trace, compare_stores, read_trace, STORE_FIELDS
from reference_model import TinyRV32Reference


ROOT = Path(__file__).resolve().parents[1]
RTL = sorted((ROOT / "rtl").glob("*.sv"))
TERMINAL = 0x0000006F
PROGRAM = [
    0x00700093,  # ADDI x1, x0, 7
    0x00102023,  # SW x1, 0(x0): a later store masks faults here
    0x00900093,  # ADDI x1, x0, 9: later instructions overwrite this result
    0x00000093,  # ADDI x1, x0, 0
    0x00700093,  # ADDI x1, x0, 7
    0x00102023,  # SW x1, 0(x0)
    0x00000093,  # ADDI x1, x0, 0
    TERMINAL,
]


class TraceRegressionTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)

    def simulate(self, words=PROGRAM, injection="", max_cycles=350):
        source = (ROOT / "tb/differential_tb.sv").read_text()
        prefix, suffix = source.rsplit("endmodule", 1)
        bench = self.root / "differential_tb.sv"
        bench.write_text(prefix + injection + "\nendmodule" + suffix)
        executable = self.root / "simulation"
        compiler = shlex.split(os.environ.get("IVERILOG", "iverilog"))
        build = subprocess.run(
            compiler + ["-g2012", "-s", "differential_tb", "-o", str(executable)]
            + [str(path) for path in RTL] + [str(bench)],
            capture_output=True, text=True, timeout=60, check=False,
        )
        self.assertEqual(build.returncode, 0, build.stdout + build.stderr)
        image = self.root / "program.hex"
        image.write_text("".join(f"{word:08x}\n" for word in words + [0x13] * (64 - len(words))))
        self.state = self.root / "state.txt"
        self.trace = self.root / "trace.txt"
        self.stores = self.root / "stores.txt"
        simulator = shlex.split(os.environ.get("VVP", "vvp"))
        return subprocess.run(
            simulator + [str(executable), f"+IMAGE={image}", f"+STATE={self.state}",
                         f"+TRACE={self.trace}", f"+STORES={self.stores}",
                         f"+MAX_CYCLES={max_cycles}"],
            capture_output=True, text=True, timeout=60, check=False,
        )

    def reference(self, words=PROGRAM):
        model = TinyRV32Reference(words)
        model.run()
        expected = dict(pc=model.pc, registers=model.regs, memory=model.dmem)
        return model, expected

    def assert_final_state_matches(self, expected):
        self.assertEqual(compare_state(expected, parse_rtl_state(self.state)), [])

    @staticmethod
    def force_at_pc(pc, signal, value):
        return f"""
    initial begin
        wait (!reset && dut.exec_valid && dut.exec_pc == 32'd{pc});
        #1; force dut.{signal} = {value};
        @(posedge clk); #1; release dut.{signal};
    end
"""

    def test_correct_rtl_matches_all_three_checks(self):
        run = self.simulate()
        self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
        model, expected = self.reference()
        self.assert_final_state_matches(expected)
        compare_trace(model.trace, read_trace(self.trace))
        compare_stores(model.trace, read_trace(self.stores, STORE_FIELDS))

    def test_high_registers_load_and_x0(self):
        words = [0x00700F93, 0x01F02223, 0x00402F03, 0x003F8013, TERMINAL]
        run = self.simulate(words)
        self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
        model, expected = self.reference(words)
        self.assertEqual((model.regs[0], model.regs[30], model.regs[31]), (0, 7, 7))
        self.assert_final_state_matches(expected)
        compare_trace(model.trace, read_trace(self.trace))
        compare_stores(model.trace, read_trace(self.stores, STORE_FIELDS))

    def test_transient_register_error_survives_only_in_trace(self):
        run = self.simulate(injection=self.force_at_pc(8, "write_data", "32'd10"))
        self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
        model, expected = self.reference()
        self.assert_final_state_matches(expected)
        compare_stores(model.trace, read_trace(self.stores, STORE_FIELDS))
        with self.assertRaises(ValueError):
            compare_trace(model.trace, read_trace(self.trace))

    def test_missing_first_store_is_detected_after_later_repair(self):
        run = self.simulate(injection=self.force_at_pc(4, "dmem_we", "1'b0"))
        self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
        model, expected = self.reference()
        self.assert_final_state_matches(expected)
        with self.assertRaises(ValueError):
            compare_trace(model.trace, read_trace(self.trace))
        with self.assertRaisesRegex(ValueError, "Memory writes"):
            compare_stores(model.trace, read_trace(self.stores, STORE_FIELDS))

    def test_wrong_first_store_data_is_detected_after_later_repair(self):
        run = self.simulate(injection=self.force_at_pc(4, "dmem_wdata", "32'd8"))
        self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
        model, expected = self.reference()
        self.assert_final_state_matches(expected)
        with self.assertRaises(ValueError):
            compare_trace(model.trace, read_trace(self.trace))
        with self.assertRaisesRegex(ValueError, "Memory writes"):
            compare_stores(model.trace, read_trace(self.stores, STORE_FIELDS))

    def test_write_from_invalid_execute_slot_fails_simulation(self):
        injection = """
    initial begin
        @(negedge reset); #1;
        force dut.dmem_we = 1'b1;
        @(posedge clk); #1; release dut.dmem_we;
    end
"""
        run = self.simulate(injection=injection)
        self.assertNotEqual(run.returncode, 0, run.stdout + run.stderr)
        self.assertIn("Side effect from invalid execute slot", run.stdout)

    def test_nonterminating_program_fails_simulation(self):
        run = self.simulate([0x00000063], max_cycles=20)  # BEQ x0, x0, 0
        self.assertNotEqual(run.returncode, 0, run.stdout + run.stderr)
        self.assertIn("Differential program timed out", run.stdout)


if __name__ == "__main__":
    unittest.main()
