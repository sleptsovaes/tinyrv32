import subprocess
import sys


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

    for seed in range(NUM_TESTS):

        gen = run(
            f"python3 verification/generate_program.py --seed {seed}"
        )

        if gen.returncode != 0:
            print(f"[SEED {seed}] GENERATOR FAILED")
            print(gen.stdout)
            print(gen.stderr)
            sys.exit(1)

        sim = run("vvp diff_test")

        if sim.returncode != 0:
            print(f"[SEED {seed}] RTL SIMULATION FAILED")
            print(sim.stdout)
            print(sim.stderr)
            sys.exit(1)

        compare = run(
            "python3 verification/compare_state.py"
        )

        if compare.returncode != 0:
            print(f"[SEED {seed}] DIFFERENTIAL MISMATCH")
            print(compare.stdout)
            print(compare.stderr)
            print()
            print(
                f"Reproduce with:\n"
                f"python3 verification/generate_program.py "
                f"--seed {seed}\n"
                f"vvp diff_test\n"
                f"python3 verification/compare_state.py"
            )
            sys.exit(1)

        print(f"[{seed + 1:3}/{NUM_TESTS}] seed={seed:<3} PASS")

    print()
    print(f"ALL {NUM_TESTS} DIFFERENTIAL TESTS PASSED")


if __name__ == "__main__":
    main()
