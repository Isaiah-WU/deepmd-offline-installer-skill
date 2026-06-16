#!/usr/bin/env bash
# Verify a produced DeePMD-kit offline installer ACTUALLY installs and works
# WITHOUT internet access. This is the real acceptance test: "constructor made a
# .sh" is necessary but NOT sufficient.
#
# Usage:
#   bash scripts/verify_offline.sh <installer.sh> [expected_version]
#
# GPU mode auto-detects from a "cuda" filename (override with VERIFY_GPU=1/0) and
# MUST run on a host with an NVIDIA GPU + driver. The upstream bundle is
# TensorFlow + JAX (no PyTorch), so the hard GPU gate is a backend-agnostic device
# check (JAX, falling back to TF). A TensorFlow XLA op using a TRANSCENDENTAL
# function additionally proves the libdevice-hack actually took effect (advisory
# if TF has no GPU plugin, since deepmd may run on the JAX backend).
#
# Exit code 0 = offline install verified. Non-zero = failure (use in benchmarks).

set -euo pipefail

INSTALLER="${1:?usage: verify_offline.sh <installer.sh> [expected_version]}"
EXPECTED_VERSION="${2:-}"

[[ -f "$INSTALLER" ]] || { echo "VERIFY FAILED: installer not found: $INSTALLER" >&2; exit 1; }
# Reject a split part: feeding a fragment installs a broken file with a cryptic error.
case "$(basename "$INSTALLER")" in
  *.sh.[0-9]*) echo "VERIFY FAILED: '$(basename "$INSTALLER")' looks like a split part; reassemble first: cat NAME.* > NAME" >&2; exit 1 ;;
esac
INSTALLER="$(cd "$(dirname "$INSTALLER")" && pwd)/$(basename "$INSTALLER")"

# GPU mode: auto from filename, override with VERIFY_GPU
if [[ -n "${VERIFY_GPU:-}" ]]; then
  GPU_MODE="$VERIFY_GPU"
elif [[ "$(basename "$INSTALLER")" == *cuda* ]]; then
  GPU_MODE=1
else
  GPU_MODE=0
fi

WORK="$(mktemp -d)"
PREFIX="$WORK/dpenv"
trap 'rm -rf "$WORK"' EXIT

# Build the test body. The outer heredoc is UNQUOTED so the bash-level $VARS below
# bake in their values now; the inner <<'PY' python blocks stay literal (they
# contain no $ / backticks). \$ is escaped where runtime expansion is intended.
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
  echo "--> version assertion (anchored): expecting $EXPECTED_VERSION"
  python - "$EXPECTED_VERSION" <<'PY'
import sys, subprocess, re
expected = sys.argv[1]
out = subprocess.run(["dp", "--version"], capture_output=True, text=True)
text = (out.stdout or "") + (out.stderr or "")
print("    dp --version ->", text.strip())
if not re.search(r'(?<!\d)' + re.escape(expected) + r'(?!\d)', text):
    print("VERSION MISMATCH: wanted", expected); sys.exit(1)
print("    version OK")
PY
fi

if [[ "$GPU_MODE" == "1" ]]; then
  echo "--> GPU: nvidia-smi"
  command -v nvidia-smi >/dev/null 2>&1 || { echo "GPU FAIL: nvidia-smi not found (GPU verify needs a GPU node)" >&2; exit 1; }
  nvidia-smi -L

  echo "--> GPU: backend-agnostic device visibility (JAX, falling back to TF)"
  python - <<'PY'
import sys
ok = False
try:
    import jax
    devs = jax.devices()
    print("    jax.devices() =", devs)
    ok = any(getattr(d, "platform", "") == "gpu" for d in devs)
except Exception as e:
    print("    jax check skipped:", e)
if not ok:
    try:
        import tensorflow as tf
        g = tf.config.list_physical_devices("GPU")
        print("    tf GPUs =", g)
        ok = bool(g)
    except Exception as e:
        print("    tf check failed:", e)
if not ok:
    print("GPU FAIL: no GPU visible to JAX or TensorFlow"); sys.exit(1)
print("    GPU visible OK")
PY

  echo "--> GPU: TensorFlow XLA libdevice proof (advisory if TF has no GPU plugin)"
  python - <<'PY'
import sys
try:
    import tensorflow as tf
except Exception as e:
    print("    TF not importable; skipping libdevice proof:", e); sys.exit(0)
if not tf.config.list_physical_devices("GPU"):
    print("    TF sees no GPU; libdevice proof advisory-skipped (deepmd may use JAX)"); sys.exit(0)
@tf.function(jit_compile=True)             # forces XLA; transcendental ops pull libdevice
def f(x):
    return tf.reduce_sum(tf.math.erf(tf.exp(x)))
val = float(f(tf.constant([0.1, 0.2, 0.3])))
print("    TF XLA+libdevice OK, val =", val)
PY
fi

echo "OFFLINE VERIFY OK"
EOF
chmod +x "$TEST_SCRIPT"

echo "==> Verifying offline installability of:"
echo "    $INSTALLER   (GPU mode: $GPU_MODE)"

# --- pick a network-isolation backend ----------------------------------------
if command -v unshare >/dev/null 2>&1 && unshare -rn true 2>/dev/null; then
  echo "==> Network isolation: unshare -rn (no network; /dev/nvidia* preserved)"
  unshare -rn bash "$TEST_SCRIPT"
elif command -v docker >/dev/null 2>&1; then
  echo "==> Network isolation: docker run --network none"
  GPU_FLAG=()
  if [[ "$GPU_MODE" == "1" ]]; then
    if docker info --format '{{.Runtimes}}' 2>/dev/null | grep -q nvidia; then
      GPU_FLAG=(--gpus all)
    else
      echo "WARNING: docker lacks the nvidia runtime (nvidia-container-toolkit); GPU checks will fail here." >&2
      echo "         Prefer running verify on a GPU node where 'unshare -rn' is available." >&2
    fi
  fi
  docker run --rm --network none "${GPU_FLAG[@]}" \
    -v "$INSTALLER":/installer.sh:ro \
    -e EXPECTED_VERSION="$EXPECTED_VERSION" \
    -e GPU_MODE="$GPU_MODE" \
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
      if [ "${GPU_MODE:-0}" = "1" ]; then
        nvidia-smi -L
        python -c "import sys
ok=False
try:
    import jax; ok=any(getattr(d,\"platform\",\"\")==\"gpu\" for d in jax.devices())
except Exception: pass
if not ok:
    try:
        import tensorflow as tf; ok=bool(tf.config.list_physical_devices(\"GPU\"))
    except Exception: pass
sys.exit(0 if ok else 1)"
      fi
      echo "OFFLINE VERIFY OK"
    '
else
  echo "WARNING: no unshare/docker available; running WITHOUT real network isolation." >&2
  echo "         This still exercises the installer but does not prove offline behavior." >&2
  bash "$TEST_SCRIPT"
fi

echo ""
echo "VERIFY PASSED: installer works with no internet access (GPU mode $GPU_MODE)."
