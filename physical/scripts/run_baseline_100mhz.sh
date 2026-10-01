#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

ORFS_DIR="${ORFS_DIR:-$HOME/OpenROAD-flow-scripts}"
FLOW_DIR="$ORFS_DIR/flow"

DESIGN_DIR="$FLOW_DIR/designs/sky130hd/tinyrv32"
RTL_DIR="$FLOW_DIR/designs/src/tinyrv32"

VARIANT="current_baseline_100mhz"
RTL_COMMIT="6ec637b161d326051904ab9ade76cc9e1d15b459"
FLOW_INPUT_COMMIT="91a4b36c688a801eea857a48e4cc4d9744ce7816"
EXPECTED_ORFS_COMMIT="c63a606f9ccede13df8c82bbe31a8f6c6d323f6b"

echo "TinyRV32 single-cycle baseline"
echo "Target: 100 MHz"
echo "Variant: $VARIANT"
echo "RTL commit: $RTL_COMMIT"
echo

if [ ! -d "$FLOW_DIR" ]; then
    echo "ERROR: ORFS not found at:"
    echo "$FLOW_DIR"
    exit 1
fi


git -C "$ROOT" cat-file -e "${RTL_COMMIT}:rtl"
git -C "$ROOT" cat-file -e "${FLOW_INPUT_COMMIT}:physical/config.mk"
git -C "$ROOT" cat-file -e   "${FLOW_INPUT_COMMIT}:physical/experiments/${VARIANT}/constraint.sdc"

if [ "$(git -C "$ORFS_DIR" rev-parse HEAD)" != "$EXPECTED_ORFS_COMMIT" ]; then
    echo "ERROR: ORFS revision differs from the pinned revision." >&2
    exit 1
fi

if ! git -C "$ORFS_DIR" diff --quiet HEAD --; then
    echo "ERROR: ORFS has tracked modifications." >&2
    exit 1
fi

mkdir -p "$DESIGN_DIR"
mkdir -p "$RTL_DIR"

rm -f "$RTL_DIR"/*.sv

git -C "$ROOT" archive "${RTL_COMMIT}:rtl" | tar -x -C "$RTL_DIR"

git -C "$ROOT" show "${FLOW_INPUT_COMMIT}:physical/config.mk" > "$DESIGN_DIR/config.mk"

git -C "$ROOT" show "${FLOW_INPUT_COMMIT}:physical/experiments/${VARIANT}/constraint.sdc" > "$DESIGN_DIR/constraint.sdc"

echo "RTL and configuration copied."
echo

cd "$FLOW_DIR"

docker run --rm -it \
    -u "$(id -u):$(id -g)" \
    -v "$FLOW_DIR:/OpenROAD-flow-scripts/flow" \
    openroad/orfs@sha256:2e5bf6fe865e102ca2313aba1d849da50f5973bc91c4212a2f68e7d905a39c8f \
    bash -lc "
        cd /OpenROAD-flow-scripts/flow &&
        make \
          DESIGN_CONFIG=./designs/sky130hd/tinyrv32/config.mk \
          FLOW_VARIANT=$VARIANT
    "

echo
echo "Baseline implementation complete."
