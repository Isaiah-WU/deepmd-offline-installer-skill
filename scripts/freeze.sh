#!/usr/bin/env bash
# Capture the EXACT package versions baked into a built offline installer, so you
# can pin them in assets/construct.yaml for byte-stable rebuilds.
#
# Usage:
#   bash scripts/freeze.sh <installer.sh> [output_lock.txt]
#
# It installs the .sh into a throwaway prefix and dumps:
#   - an explicit conda lock (exact package URLs)         -> <lock>
#   - a human-readable version table for the key packages -> stdout
#
# Paste the key versions back into construct.yaml (deepmd-kit/tensorflow/lammps/
# jax/flax/...) to eliminate build-time variance.

set -euo pipefail

INSTALLER="${1:?usage: freeze.sh <installer.sh> [output_lock.txt]}"
[[ -f "$INSTALLER" ]] || { echo "ERROR: installer not found: $INSTALLER" >&2; exit 1; }
INSTALLER="$(cd "$(dirname "$INSTALLER")" && pwd)/$(basename "$INSTALLER")"

OUT_LOCK="${2:-$(dirname "$INSTALLER")/$(basename "$INSTALLER" .sh).lock.txt}"

WORK="$(mktemp -d)"
PREFIX="$WORK/dpenv"
trap 'rm -rf "$WORK"' EXIT

echo "==> Installing into throwaway prefix to inspect bundled versions..."
bash "$INSTALLER" -b -p "$PREFIX"

echo "==> Writing explicit lock -> $OUT_LOCK"
conda list --explicit -p "$PREFIX" > "$OUT_LOCK"

echo "==> Key bundled versions (paste these as pins in construct.yaml):"
conda list -p "$PREFIX" \
  | grep -Ei '^(deepmd-kit|lammps|tensorflow|jax|jaxlib|flax|horovod|mpi4py|orbax-checkpoint|cuda-version) ' \
  || echo "(could not grep key packages; inspect $OUT_LOCK manually)"

echo ""
echo "FREEZE OK. Lock written to: $OUT_LOCK"
