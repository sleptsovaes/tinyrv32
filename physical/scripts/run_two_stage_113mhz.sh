#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

ORFS_DIR="${ORFS_DIR:-$HOME/OpenROAD-flow-scripts}"
FLOW_DIR="$ORFS_DIR/flow"

DESIGN_DIR="$FLOW_DIR/designs/sky130hd/tinyrv32"
RTL_DIR="$FLOW_DIR/designs/src/tinyrv32"

VARIANT="two_stage_pipeline_113mhz"

echo "TinyRV32 two-stage pipeline"
echo "Target: 113 MHz"
echo "Variant: $VARIANT"
echo

if [ ! -d "$FLOW_DIR" ]; then
    echo "ERROR: ORFS not found at:"
    echo "$FLOW_DIR"
    exit 1
fi

mkdir -p "$DESIGN_DIR"
mkdir -p "$RTL_DIR"

rm -f "$RTL_DIR"/*.sv

cp "$ROOT"/rtl/*.sv \
   "$RTL_DIR"/

cp "$ROOT"/physical/config.mk \
   "$DESIGN_DIR/config.mk"

cp \
  "$ROOT/physical/experiments/two_stage_pipeline_113mhz/constraint.sdc" \
  "$DESIGN_DIR/constraint.sdc"

echo "RTL and configuration copied."
echo

cd "$FLOW_DIR"

docker run --rm -it \
    -u "$(id -u):$(id -g)" \
    -v "$FLOW_DIR:/OpenROAD-flow-scripts/flow" \
    openroad/orfs:latest \
    bash -lc "
        cd /OpenROAD-flow-scripts/flow &&
        make \
          DESIGN_CONFIG=./designs/sky130hd/tinyrv32/config.mk \
          FLOW_VARIANT=$VARIANT
    "

echo
echo "113 MHz implementation complete."
