#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
REPORT_DIR="$ROOT/physical/reports/baseline"
MANIFEST="$REPORT_DIR/manifest.txt"

{
    echo "TinyRV32 Baseline Physical-Design Report Manifest"
    echo "================================================="
    echo
    echo "Generated (UTC): $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
    echo "TinyRV32 commit: $(git -C "$ROOT" rev-parse HEAD)"
    echo
    echo "SHA256:"
    echo

    find "$REPORT_DIR" \
        -type f \
        ! -name manifest.txt \
        -print0 \
        | sort -z \
        | xargs -0 sha256sum

} > "$MANIFEST"

echo "Manifest written to:"
echo "$MANIFEST"
