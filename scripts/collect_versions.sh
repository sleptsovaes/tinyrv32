#!/usr/bin/env bash

set -u

OUTPUT="reproducibility/tool_versions.txt"

mkdir -p reproducibility

{
    echo "TinyRV32 Reproducibility Environment"
    echo "===================================="
    echo

    echo "[Host]"
    echo "Date (UTC): $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
    echo "Kernel: $(uname -a)"
    echo

    echo "[Operating System]"
    if command -v lsb_release >/dev/null 2>&1; then
        lsb_release -ds || echo "Unavailable"
    elif [ -f /etc/os-release ]; then
        grep '^PRETTY_NAME=' /etc/os-release || echo "Unavailable"
    else
        echo "Unavailable"
    fi
    echo

    echo "[Python]"
    if command -v python3 >/dev/null 2>&1; then
        python3 --version || echo "Unavailable"
    else
        echo "Not installed"
    fi
    echo

    echo "[Icarus Verilog]"
    if command -v iverilog >/dev/null 2>&1; then
        iverilog -V 2>&1 | head -n 4 || true
    else
        echo "Not installed"
    fi
    echo

    echo "[Git]"
    if command -v git >/dev/null 2>&1; then
        git --version || echo "Unavailable"
    else
        echo "Not installed"
    fi
    echo

    echo "[TinyRV32 repository]"
    if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        echo "Commit: $(git rev-parse HEAD 2>/dev/null || echo unavailable)"
        echo "Branch: $(git branch --show-current 2>/dev/null || echo unavailable)"
    else
        echo "Not inside a Git repository"
    fi
    echo

    echo "[Docker]"
    if command -v docker >/dev/null 2>&1; then
        docker --version 2>/dev/null || echo "Docker CLI unavailable"
    else
        echo "Not installed"
    fi
    echo

    echo "[ORFS Docker image]"
    if command -v docker >/dev/null 2>&1 && \
       docker image inspect openroad/orfs:latest >/dev/null 2>&1; then

        echo "Image: openroad/orfs:latest"

        IMAGE_ID=$(
            docker image inspect \
                openroad/orfs:latest \
                --format '{{.Id}}' \
                2>/dev/null || true
        )

        if [ -n "$IMAGE_ID" ]; then
            echo "Image ID: $IMAGE_ID"
        else
            echo "Image ID: unavailable"
        fi

        REPO_DIGEST=$(
            docker image inspect \
                openroad/orfs:latest \
                --format '{{json .RepoDigests}}' \
                2>/dev/null || true
        )

        if [ -n "$REPO_DIGEST" ]; then
            echo "Repo digests: $REPO_DIGEST"
        else
            echo "Repo digests: unavailable"
        fi

        echo
        echo "[OpenROAD inside ORFS image]"

        docker run --rm \
            openroad/orfs:latest \
            bash -lc '
                openroad -version 2>/dev/null ||
                openroad --version 2>/dev/null ||
                echo "OpenROAD version unavailable"
            ' 2>/dev/null || echo "Unable to execute ORFS container"

    else
        echo "openroad/orfs:latest not available locally"
    fi
    echo

    echo "[OpenROAD-flow-scripts]"
    if [ -d "$HOME/OpenROAD-flow-scripts/.git" ]; then
        ORFS_COMMIT=$(
            git -C "$HOME/OpenROAD-flow-scripts" \
                rev-parse HEAD \
                2>/dev/null || true
        )

        ORFS_BRANCH=$(
            git -C "$HOME/OpenROAD-flow-scripts" \
                branch --show-current \
                2>/dev/null || true
        )

        echo "Commit: ${ORFS_COMMIT:-unavailable}"
        echo "Branch: ${ORFS_BRANCH:-detached/unknown}"
    else
        echo "$HOME/OpenROAD-flow-scripts not found"
    fi
    echo

    echo "[Physical design configuration]"

    if [ -f physical/config.mk ]; then
        grep -E \
            'PLATFORM|DESIGN_NAME|CORE_UTILIZATION|CORE_ASPECT_RATIO|CORE_MARGIN|PLACE_DENSITY' \
            physical/config.mk || true
    else
        echo "physical/config.mk not found"
    fi

    echo

    echo "[Timing constraints]"

    if [ -f physical/constraint.sdc ]; then
        grep -E \
            'clk_period|create_clock|set_input_delay|set_output_delay' \
            physical/constraint.sdc || true
    else
        echo "physical/constraint.sdc not found"
    fi

} > "$OUTPUT"

echo "Environment report written to:"
echo "$OUTPUT"

exit 0
