#!/usr/bin/env bash

set -euo pipefail

ORFS_DIR="${ORFS_DIR:-$HOME/OpenROAD-flow-scripts}"
FLOW_DIR="$ORFS_DIR/flow"

TINyrv32_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

ORFS_DESIGN_DIR="$FLOW_DIR/designs/sky130hd/tinyrv32"
ORFS_RTL_DIR="$FLOW_DIR/designs/src/tinyrv32"

echo "TinyRV32 RTL-to-GDS reproduction"
echo "================================"
echo
echo "TinyRV32 repo : $TINyrv32_DIR"
echo "ORFS repo     : $ORFS_DIR"
echo

if [ ! -d "$FLOW_DIR" ]; then
    echo "ERROR: ORFS flow directory not found:"
    echo "$FLOW_DIR"
    exit 1
fi

if ! command -v docker >/dev/null 2>&1; then
    echo "ERROR: Docker is not installed."
    exit 1
fi

if ! docker image inspect openroad/orfs:latest >/dev/null 2>&1; then
    echo "ERROR: openroad/orfs:latest is not available locally."
    echo "Run:"
    echo "docker pull openroad/orfs:latest"
    exit 1
fi

echo "Preparing ORFS design files..."

mkdir -p "$ORFS_DESIGN_DIR"
mkdir -p "$ORFS_RTL_DIR"

cp "$TINyrv32_DIR"/rtl/*.sv \
   "$ORFS_RTL_DIR"/

cp "$TINyrv32_DIR"/physical/config.mk \
   "$ORFS_DESIGN_DIR/config.mk"

cp "$TINyrv32_DIR"/physical/constraint.sdc \
   "$ORFS_DESIGN_DIR/constraint.sdc"

echo "Files copied."
echo
echo "Starting OpenROAD-flow-scripts..."
echo

cd "$FLOW_DIR"

docker run --rm -it \
    -u "$(id -u):$(id -g)" \
    -v "$FLOW_DIR:/OpenROAD-flow-scripts/flow" \
    openroad/orfs:latest \
    bash -lc '
        cd /OpenROAD-flow-scripts/flow &&
        make DESIGN_CONFIG=./designs/sky130hd/tinyrv32/config.mk
    '

echo
echo "================================"
echo "RTL-to-GDS flow completed."
echo "================================"
