#!/bin/bash
# One-click build script for DeePMD-kit offline installer
# Usage: bash build.sh <recipe_dir> <version> [cuda_version]
#   recipe_dir   : path to deepmd-kit-installer/deepmd-kit (contains construct.yaml)
#   version      : deepmd-kit version, e.g. 3.1.3
#   cuda_version : optional; empty = CPU build, e.g. 12.1 = CUDA build

set -e  # stop on any error

RECIPE_DIR="$1"
export VERSION="$2"
export CUDA_VERSION="${3:-}"   # default empty (CPU)

echo "==> Checking constructor..."
if ! command -v constructor &> /dev/null; then
    echo "constructor not found, installing..."
    conda install constructor -y
fi

echo "==> Recipe dir : $RECIPE_DIR"
echo "==> Version    : $VERSION"
echo "==> CUDA       : ${CUDA_VERSION:-(CPU build)}"

cd "$RECIPE_DIR"

echo "==> Building installer..."
constructor .

echo "==> Done. Produced installer(s):"
ls -lh *.sh
