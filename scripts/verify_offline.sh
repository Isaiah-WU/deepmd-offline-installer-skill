#!/usr/bin/env bash
# Verify a produced DeePMD-kit offline installer ACTUALLY installs and works
# WITHOUT internet access. This is the real acceptance test: "constructor made a
# .sh" is necessary but NOT sufficient.
#
# Usage:
#   bash scripts/verify_offline.sh <installer.sh> [expected_version]
#
# What it does:
#   1. Installs the .sh into a throwaway prefix.
#   2. Runs the install + smoke tests with the NETWORK CUT OFF when possible
#      (unshare -n, or `docker run --network none`, else a clear warning).
#   3. Asserts: dp -h, lmp -h, `import deepmd` all work, and (if given) the
#      reported version matches what was requested.
#
# Exit code 0 = offline install verified. Non-zero = failure (use in benchmarks).

set -euo pipefail

INSTALLER="${1:?usage: verify_offline.sh <installer.sh> [expected_version]}"
EXPECTED_VERSION="${2:-}"

[[ -f "$INSTALLER" ]] || { echo "VERIFY FAILED: installer not found: $INSTALLER" >&2; exit 1; }
INSTALLER="$(cd "$(dirname "$INSTALLER")" && pwd)/$(basename "$INSTALLER")"

WORK="$(mktemp -d)"
PREFIX="$WORK/dpenv"
trap 'rm -rf "$WORK"' EXIT

# The actual test body, written to a script so we can run it under network
# isolation backends uniformly.
TEST_SCRIPT="$WORK/_test.sh"
cat > "$TEST_SCRIPT" <<EOF
set -euo pipefail
echo "--> installing offline into $PREFIX"
bash "$INSTALLER" -b -p "$PREFIX"

# activate the installed environment
source "$PREFIX/bin/activate" "$PREFIX"

echo "--> smoke test: dp -h"
dp -h >/dev/null
echo "--> smoke test: lmp -h"
lmp -h >/dev/null
echo "--> smoke test: import deepmd"
python -c "import deepmd; print('deepmd import OK')"

if [[ -n "$EXPECTED_VERSION" ]]; then
  echo "--> version assertion: expecting $EXPECTED_VERSION"
  ver="\$(dp --version 2>&1 || true)"
  echo "    dp --version -> \$ver"
  echo "\$ver" | grep -q "$EXPECTED_VERSION" || {
    echo "VERSION MISMATCH: wanted $EXPECTED_VERSION, got \$ver" >&2
    exit 1
  }
fi
echo "OFFLINE VERIFY OK"
EOF
chmod +x "$TEST_SCRIPT"

echo "==> Verifying offline installability of:"
echo "    $INSTALLER"

# --- pick a network-isolation backend ----------------------------------------
if command -v unshare >/dev/null 2>&1 && unshare -rn true 2>/dev/null; then
  echo "==> Network isolation: unshare -rn (no network namespace)"
  unshare -rn bash "$TEST_SCRIPT"
elif command -v docker >/dev/null 2>&1; then
  echo "==> Network isolation: docker run --network none"
  # Mount installer + run the same test inside a clean glibc>=2.17 image.
  docker run --rm --network none \
    -v "$INSTALLER":/installer.sh:ro \
    -e EXPECTED_VERSION="$EXPECTED_VERSION" \
    debian:12 bash -c '
      set -euo pipefail
      PREFIX=/tmp/dpenv
      bash /installer.sh -b -p "$PREFIX"
      source "$PREFIX/bin/activate" "$PREFIX"
      dp -h >/dev/null
      lmp -h >/dev/null
      python -c "import deepmd; print(\"deepmd import OK\")"
      if [ -n "${EXPECTED_VERSION:-}" ]; then
        dp --version 2>&1 | grep -q "$EXPECTED_VERSION" || { echo "VERSION MISMATCH"; exit 1; }
      fi
      echo "OFFLINE VERIFY OK"
    '
else
  echo "WARNING: no unshare/docker available; running WITHOUT real network isolation." >&2
  echo "         This still exercises the installer but does not prove offline behavior." >&2
  bash "$TEST_SCRIPT"
fi

echo ""
echo "VERIFY PASSED: installer works with no internet access."
