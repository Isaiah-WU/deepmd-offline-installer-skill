#!/usr/bin/env bash
# One-click build script for the DeePMD-kit offline installer.
#
# Design goal (per mentor): the agent NEVER writes build commands itself. It only
# calls this script with parameters. Everything error-prone is frozen here so a
# weak model produces the same result as a strong one.
#
# Usage:
#   bash scripts/build.sh [options]
#
# Options (ALL optional; zero-arg run uses sane defaults):
#   -v, --version <ver>     deepmd-kit version           (default: $VERSION or 3.1.3)
#   -c, --cuda <ver>        CUDA version, e.g. 12.1;
#                           empty/omitted = CPU build     (default: $CUDA_VERSION or "")
#   -r, --recipe-dir <dir>  dir containing construct.yaml (default: bundled assets/)
#   -o, --output-dir <dir>  where to write the installer  (default: ./dist)
#   -h, --help              show this help
#
# The recipe (construct.yaml + pre/post_install.sh + LICENSE) is bundled in the
# skill's assets/ directory and used BY DEFAULT, so the build is self-contained
# and reproducible on a clean machine with no external repo checkout.

set -euo pipefail

# --- locate the skill root so the bundled recipe is found from any cwd --------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DEFAULT_RECIPE="$SKILL_ROOT/assets"

# --- defaults -----------------------------------------------------------------
VERSION="${VERSION:-3.1.3}"
CUDA_VERSION="${CUDA_VERSION:-}"
RECIPE_DIR="$DEFAULT_RECIPE"
OUTPUT_DIR="$(pwd)/dist"

usage() { awk 'NR>1 && /^#/{sub(/^# ?/,""); print; next} NR>1{exit}' "${BASH_SOURCE[0]}"; }

# --- parse args (also accepts two positional args for backward compatibility) -
POSITIONAL=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    -v|--version)     VERSION="$2"; shift 2 ;;
    -c|--cuda)        CUDA_VERSION="$2"; shift 2 ;;
    -r|--recipe-dir)  RECIPE_DIR="$2"; shift 2 ;;
    -o|--output-dir)  OUTPUT_DIR="$2"; shift 2 ;;
    -h|--help)        usage; exit 0 ;;
    -*)               echo "ERROR: unknown option: $1" >&2; usage; exit 2 ;;
    *)                POSITIONAL+=("$1"); shift ;;
  esac
done
# Backward compat: build.sh <recipe_dir> <version> [cuda]
if [[ ${#POSITIONAL[@]} -ge 1 ]]; then RECIPE_DIR="${POSITIONAL[0]}"; fi
if [[ ${#POSITIONAL[@]} -ge 2 ]]; then VERSION="${POSITIONAL[1]}"; fi
if [[ ${#POSITIONAL[@]} -ge 3 ]]; then CUDA_VERSION="${POSITIONAL[2]}"; fi

export VERSION CUDA_VERSION

fail() { echo "BUILD FAILED: $*" >&2; exit 1; }

# --- preflight checks ---------------------------------------------------------
echo "==> Preflight checks"
command -v conda >/dev/null 2>&1 || fail "conda not found on PATH. Install Miniconda/Mambaforge first."

if ! command -v constructor >/dev/null 2>&1; then
  echo "    constructor not found, installing into the current conda env..."
  conda install constructor -y >/dev/null || fail "could not install constructor"
fi
constructor --version

[[ -d "$RECIPE_DIR" ]] || fail "recipe dir does not exist: $RECIPE_DIR"
[[ -f "$RECIPE_DIR/construct.yaml" ]] || fail "no construct.yaml in recipe dir: $RECIPE_DIR"

# construct.yaml references ../LICENSE relative to the recipe dir; make sure it exists.
if [[ ! -f "$RECIPE_DIR/../LICENSE" && ! -f "$RECIPE_DIR/LICENSE" ]]; then
  fail "LICENSE referenced by construct.yaml (license_file: ../LICENSE) is missing"
fi

mkdir -p "$OUTPUT_DIR"

echo "==> Build parameters"
echo "    recipe dir : $RECIPE_DIR"
echo "    version    : $VERSION"
echo "    variant    : ${CUDA_VERSION:+CUDA $CUDA_VERSION}${CUDA_VERSION:-CPU}"
echo "    output dir : $OUTPUT_DIR"

# --- build --------------------------------------------------------------------
BUILD_LOG="$OUTPUT_DIR/build-${VERSION}.log"
echo "==> Running constructor (full log: $BUILD_LOG)"
# Run in a subshell so we don't leave the caller in the recipe dir.
( cd "$RECIPE_DIR" && constructor . --output-dir "$OUTPUT_DIR" ) 2>&1 | tee "$BUILD_LOG"

# --- verify artifact & emit manifest -----------------------------------------
echo "==> Collecting produced installer(s)"
shopt -s nullglob
INSTALLERS=("$OUTPUT_DIR"/*.sh)
shopt -u nullglob
[[ ${#INSTALLERS[@]} -gt 0 ]] || fail "constructor produced no .sh installer in $OUTPUT_DIR"

MANIFEST="$OUTPUT_DIR/manifest-${VERSION}.txt"
{
  echo "deepmd-kit offline installer build manifest"
  echo "version       : $VERSION"
  echo "variant       : ${CUDA_VERSION:+cuda$CUDA_VERSION}${CUDA_VERSION:-cpu}"
  echo "recipe_dir    : $RECIPE_DIR"
  echo "constructor   : $(constructor --version 2>&1)"
  echo "build_log     : $BUILD_LOG"
  echo "artifacts     :"
  for f in "${INSTALLERS[@]}"; do
    abs="$(cd "$(dirname "$f")" && pwd)/$(basename "$f")"
    size="$(du -h "$f" | cut -f1)"
    sha="$(sha256sum "$f" | cut -d' ' -f1)"
    echo "  - path   : $abs"
    echo "    size   : $size"
    echo "    sha256 : $sha"
  done
} | tee "$MANIFEST"

echo ""
echo "BUILD OK. Manifest: $MANIFEST"
echo "Next: verify it really installs OFFLINE with:"
echo "  bash $SKILL_ROOT/scripts/verify_offline.sh \"${INSTALLERS[0]}\" \"$VERSION\""
