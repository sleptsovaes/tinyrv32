import json
import subprocess
import sys
from pathlib import Path


NUM_TESTS = 100


def run(cmd):
    return subprocess.run(
        cmd,
        shell=True,
        text=True,
        capture_output=True
    )


def main():
    print(f"Running {NUM_TESTS} differential tests...")
    print()

    total_coverage = {}
    total_instructions = 0

    for seed in range(NUM_TESTS):

        # -----------------------------------------------------
        # Generate randomized program + reference result
        # -----------------------------------------------------

        gen = run(
            f"python3 verification/generate_program.py "
            f"--seed {seed}"
        )

        if gen.returncode != 0:
            print(f"[SEED {seed}] GENERATOR FAILED")
            print(gen.stdout)
            print(gen.stderr)
            sys.exit(1)

        # -----------------------------------------------------
        # Run RTL simulation
        # -----------------------------------------------------

        sim = run("vvp diff_test")

        if sim.returncode != 0:
            print(f"[SEED {seed}] RTL SIMULATION FAILED")
            print(sim.stdout)
            print(sim.stderr)
            sys.exit(1)

        # -----------------------------------------------------
        # Compare RTL architectural state against reference
        # -----------------------------------------------------

        compare = run(
            "python3 verification/compare_state.py"
        )

        if compare.returncode != 0:
            print(
                f"[SEED {seed}] DIFFERENTIAL MISMATCH"
            )

            print(compare.stdout)
            print(compare.stderr)
            print()

            print(
                "Reproduce with:\n"
                f"python3 verification/generate_program.py "
                f"--seed {seed}\n"
                "vvp diff_test\n"
                "python3 verification/compare_state.py"
            )

            sys.exit(1)

        # -----------------------------------------------------
        # Collect architectural coverage
        # -----------------------------------------------------

        with open(
            "verification/generated/expected.json",
            encoding="utf-8"
        ) as f:
            expected = json.load(f)

        total_instructions += expected["steps"]

        for name, count in expected["coverage"].items():
            total_coverage[name] = (
                total_coverage.get(name, 0)
                + count
            )

        print(
            f"[{seed + 1:3}/{NUM_TESTS}] "
            f"seed={seed:<3} PASS"
        )

    # =========================================================
    # Regression summary
    # =========================================================

    print()
    print("========================================")
    print(
        f"ALL {NUM_TESTS} DIFFERENTIAL TESTS PASSED"
    )
    print("========================================")

    print()
    print("Architectural coverage:")
    print()

    for name, count in sorted(
        total_coverage.items()
    ):
        print(
            f"{name:16} {count}"
        )

    print()
    print(
        f"Executed instructions: "
        f"{total_instructions}"
    )

    # =========================================================
    # Write Markdown coverage report
    # =========================================================

    results_dir = Path(
        "verification/results"
    )

    results_dir.mkdir(
        parents=True,
        exist_ok=True
    )

    report_path = (
        results_dir
        / "coverage_summary.md"
    )

    with report_path.open(
        "w",
        encoding="utf-8"
    ) as f:

        f.write(
            "# Differential Verification Coverage\n\n"
        )

        f.write(
            f"Random programs: {NUM_TESTS}\n\n"
        )

        f.write(
            "Executed reference-model instructions: "
            f"{total_instructions}\n\n"
        )

        f.write(
            "| Instruction / outcome | Executions |\n"
        )

        f.write(
            "|---|---:|\n"
        )

        for name, count in sorted(
            total_coverage.items()
        ):
            f.write(
                f"| {name} | {count} |\n"
            )

        f.write("\n")

        f.write(
            "All generated programs matched the "
            "SystemVerilog RTL architectural state.\n"
        )

    print()
    print(
        f"Coverage report written to: "
        f"{report_path}"
    )


if __name__ == "__main__":
    main()
