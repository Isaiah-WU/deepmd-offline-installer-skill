#!/usr/bin/env bash
# Stage 1 (commit-keyed packaging): build a deepmd-kit conda package FROM A GIT
# COMMIT into a LOCAL channel, so the offline installer can be keyed on a commit
# instead of a released version.
#
# WHY THIS EXISTS: no per-commit deepmd-kit conda package is published anywhere,
# and conda `constructor` can only bundle packages that ALREADY exist. So a commit
# must first be built from source. We drive the MAINTAINED conda-forge feedstock
# (conda-forge/deepmd-kit-feedstock) and rewrite its source from the release
# tarball to a git source at the commit.
#
# !!! MUST BE VALIDATED ON LINUX against the live feedstock. The feedstock layout
# !!! (source section, .ci_support configs, build-locally.py) evolves; this script
# !!! fails loudly when its assumptions don't hold rather than producing junk.
# !!! Building a compiled CUDA package per commit needs Docker and tens of min–>1h.
#
# Usage:
#   bash scripts/build_pkg_from_commit.sh --commit <sha> [options]
#
# Options:
#   --commit <ref>          deepmd-kit git commit/branch/tag to build (REQUIRED)
#   --pkg-version <ver>     conda version label for the build (default: derived via
#                           `git describe` of the commit, e.g. 3.2.0b1.dev17)
#   --cuda <ver>            RUNTIME cuda-version to pin in Stage 2 (e.g. 12.9);
#                           empty = CPU. NOTE: distinct from the COMPILER cuda in --config.
#   --config <stem>         .ci_support config stem to build (e.g.
#                           linux_64_cuda_compiler_version12.6python3.11...). Required
#                           for CUDA; auto-picked for CPU. Run with no --config to list.
#   --mode <m>             'build-locally' (default; Docker, the supported cf way) or
#                          'conda-build' (direct; advanced, needs a working toolchain)
#   --feedstock-ref <ref>   conda-forge/deepmd-kit-feedstock ref (default: main)
#   --feedstock-dir <dir>   existing feedstock checkout (else cloned)
#   --channel-dir <dir>     local channel output (default: ./local-channel)
#   --python <ver>          python version (default 3.11); used for auto config pick
#   -h, --help
#
# Output: <channel-dir> with the built package(s) + a COMMIT_BUILD.env describing
# the EXACT version/build/python. Then run:
#   bash scripts/build.sh --from-commit-channel <channel-dir>

set -euo pipefail

FEEDSTOCK_REPO="https://github.com/conda-forge/deepmd-kit-feedstock"
DEEPMD_REPO="https://github.com/deepmodeling/deepmd-kit"

COMMIT=""
PKG_VERSION=""
CUDA_VERSION=""
CONFIG=""
MODE="build-locally"
FEEDSTOCK_REF="main"
FEEDSTOCK_DIR=""
CHANNEL_DIR="$(pwd)/local-channel"
PYVER="3.11"

usage() { awk 'NR>1 && /^#/{sub(/^# ?/,""); print; next} NR>1{exit}' "${BASH_SOURCE[0]}"; }
fail() { echo "STAGE1 FAILED: $*" >&2; exit 1; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --commit)         COMMIT="$2"; shift 2 ;;
    --pkg-version)    PKG_VERSION="$2"; shift 2 ;;
    --cuda)           CUDA_VERSION="$2"; shift 2 ;;
    --config)         CONFIG="$2"; shift 2 ;;
    --mode)           MODE="$2"; shift 2 ;;
    --feedstock-ref)  FEEDSTOCK_REF="$2"; shift 2 ;;
    --feedstock-dir)  FEEDSTOCK_DIR="$2"; shift 2 ;;
    --channel-dir)    CHANNEL_DIR="$2"; shift 2 ;;
    --python)         PYVER="$2"; shift 2 ;;
    -h|--help)        usage; exit 0 ;;
    *)                echo "ERROR: unknown option: $1" >&2; usage; exit 2 ;;
  esac
done

[[ -n "$COMMIT" ]] || fail "--commit <sha> is required"

echo "==> Stage 1: build deepmd-kit @ commit $COMMIT  (runtime cuda=${CUDA_VERSION:-CPU}, mode=$MODE)"

# --- preflight ----------------------------------------------------------------
command -v conda >/dev/null 2>&1 || fail "conda not found on PATH"
command -v git   >/dev/null 2>&1 || fail "git not found on PATH"
if ! conda list -n base 2>/dev/null | grep -q conda-build; then
  echo "    installing conda-build + libmamba solver..."
  conda install -n base conda-build conda-libmamba-solver -y >/dev/null || fail "could not install conda-build"
fi

# --- workspace + cleanup trap registered IMMEDIATELY (before any clone) --------
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# --- get the maintained feedstock ---------------------------------------------
if [[ -z "$FEEDSTOCK_DIR" ]]; then
  FEEDSTOCK_DIR="$WORK/deepmd-kit-feedstock"
  echo "==> Cloning feedstock $FEEDSTOCK_REPO @ $FEEDSTOCK_REF"
  git clone --depth 1 --branch "$FEEDSTOCK_REF" "$FEEDSTOCK_REPO" "$FEEDSTOCK_DIR" \
    || git clone "$FEEDSTOCK_REPO" "$FEEDSTOCK_DIR" \
    || fail "could not clone feedstock"
fi

RECIPE_DIR="$FEEDSTOCK_DIR/recipe"
META="$RECIPE_DIR/meta.yaml"
[[ -f "$META" ]] || fail "recipe meta.yaml not found at $META (feedstock layout changed?)"

# --- derive a meaningful conda version label from the commit ------------------
if [[ -z "$PKG_VERSION" ]]; then
  echo "==> Deriving version from 'git describe' of $COMMIT"
  DK="$WORK/deepmd-kit"
  if git clone --filter=blob:none --no-checkout "$DEEPMD_REPO" "$DK" >/dev/null 2>&1 \
     && git -C "$DK" fetch --tags --filter=blob:none origin "$COMMIT" >/dev/null 2>&1; then
    desc="$(git -C "$DK" describe --tags "$COMMIT" 2>/dev/null || true)"   # e.g. v3.2.0b1-17-gd3834e2
    if [[ -n "$desc" ]]; then
      d="${desc#v}"
      if [[ "$d" == *-*-g* ]]; then
        base="${d%%-*}"; rest="${d#*-}"; count="${rest%%-*}"
        PKG_VERSION="${base}.dev${count}"
      else
        PKG_VERSION="$d"
      fi
    fi
  fi
fi
if [[ -z "$PKG_VERSION" ]]; then
  FEEDVER="$(grep -oE '\{%[[:space:]]*set[[:space:]]+version[[:space:]]*=[[:space:]]*"[^"]+"' "$META" | grep -oE '"[^"]+"' | tr -d '"' | head -1 || true)"
  PKG_VERSION="${FEEDVER:-0.0.0}.dev0"
  echo "    WARNING: could not derive version from git; using synthetic '$PKG_VERSION'." >&2
  echo "             Pass --pkg-version for a meaningful label." >&2
fi
echo "    version label: $PKG_VERSION"

# --- rewrite recipe: release tarball source -> git source at the commit -------
# Only the deepmd-kit archive line is touched (and the sha256 that immediately
# follows it); any other source (e.g. lammps) is left intact.
echo "==> Rewriting recipe source -> git_rev $COMMIT"
echo "    BEFORE:"; grep -nE 'url:|sha256:|git_url:|git_rev:' "$META" | sed 's/^/      /' || true
awk -v commit="$COMMIT" '
  /url:[[:space:]]*https?:\/\/github.com\/deepmodeling\/[^/]+\/archive/ {
    idx = index($0, "url:");
    prefix = substr($0, 1, idx-1);          # preserve list dash, e.g. "  - " or "  "
    keyind = prefix; gsub(/[^ ]/, " ", keyind);   # align continuation under the key
    print prefix "git_url: https://github.com/deepmodeling/deepmd-kit";
    print keyind "git_rev: " commit;
    drop_next_sha=1; next
  }
  drop_next_sha==1 && /sha256:/ { drop_next_sha=0; next }
  { drop_next_sha=0; print }
' "$META" > "$META.tmp" && mv "$META.tmp" "$META"
# Set the package version label.
sed -i -E "s|(\{%[[:space:]]*set[[:space:]]+version[[:space:]]*=[[:space:]]*)\"[^\"]*\"|\1\"${PKG_VERSION}\"|" "$META"
echo "    AFTER:"; grep -nE 'set version|git_url:|git_rev:' "$META" | sed 's/^/      /' || true
grep -qE '^[[:space:]]*git_rev:' "$META" || fail "source rewrite did not produce a git_rev — recipe layout differs; edit $META manually."

mkdir -p "$CHANNEL_DIR"

# --- choose a .ci_support config ----------------------------------------------
CI_DIR="$FEEDSTOCK_DIR/.ci_support"
list_configs() { ls "$CI_DIR" 2>/dev/null | sed 's/\.yaml$//' | sed 's/^/      /'; }
if [[ -z "$CONFIG" ]]; then
  [[ -d "$CI_DIR" ]] || fail "no .ci_support in feedstock; pass --config or --mode conda-build manually"
  pytoken="python${PYVER}"
  if [[ -z "$CUDA_VERSION" ]]; then
    # CPU: a config with cuda compiler None
    CONFIG="$(ls "$CI_DIR" | sed 's/\.yaml$//' | grep -i "$pytoken" | grep -i 'none' | head -1 || true)"
  fi
  if [[ -z "$CONFIG" ]]; then
    echo "Could not auto-pick a config for python=$PYVER cuda=${CUDA_VERSION:-CPU}." >&2
    echo "Available .ci_support configs:" >&2; list_configs >&2
    fail "pass --config <stem> (the COMPILER cuda in the name may differ from runtime --cuda)"
  fi
fi
CONFIG_FILE="$CI_DIR/${CONFIG}.yaml"
[[ -f "$CONFIG_FILE" ]] || { echo "config not found: $CONFIG_FILE" >&2; echo "Available:" >&2; list_configs >&2; fail "bad --config"; }
echo "==> Using config: $CONFIG"
# Capture the python the package will be built against (for Stage-2 co-pin).
BUILD_PY="$(echo "$CONFIG" | grep -oE 'python[0-9]+\.[0-9]+' | grep -oE '[0-9]+\.[0-9]+' | head -1 || true)"
BUILD_PY="${BUILD_PY:-$PYVER}"

# --- build --------------------------------------------------------------------
case "$MODE" in
  build-locally)
    BL="$FEEDSTOCK_DIR/build-locally.py"
    [[ -f "$BL" ]] || fail "build-locally.py not found; use --mode conda-build with -m $CONFIG_FILE"
    command -v docker >/dev/null 2>&1 || fail "build-locally needs Docker"
    echo "==> CI=1 python build-locally.py $CONFIG  (non-interactive Docker build)"
    ( cd "$FEEDSTOCK_DIR" && CI=1 python build-locally.py "$CONFIG" )
    if [[ -d "$FEEDSTOCK_DIR/build_artifacts" ]]; then
      find "$FEEDSTOCK_DIR/build_artifacts" \( -name '*.conda' -o -name '*.tar.bz2' \) -print0 \
        | while IFS= read -r -d '' p; do
            sub="$(basename "$(dirname "$p")")"; mkdir -p "$CHANNEL_DIR/$sub"; cp "$p" "$CHANNEL_DIR/$sub/";
          done
    fi
    ;;
  conda-build)
    echo "==> conda build recipe -m $CONFIG_FILE (direct; needs a working toolchain)"
    [[ -n "$CUDA_VERSION" ]] && export CONDA_OVERRIDE_CUDA="$CUDA_VERSION"
    conda build "$RECIPE_DIR" -m "$CONFIG_FILE" --output-folder "$CHANNEL_DIR" \
      || fail "conda build failed; try --mode build-locally (Docker)"
    ;;
  *) fail "unknown --mode: $MODE (build-locally|conda-build)" ;;
esac

# --- index + locate the produced deepmd-kit package ---------------------------
echo "==> Indexing local channel: $CHANNEL_DIR"
conda index "$CHANNEL_DIR" >/dev/null 2>&1 || conda-index "$CHANNEL_DIR" >/dev/null 2>&1 || \
  echo "    WARNING: could not run conda index; constructor may still read the channel" >&2

PKG=""
while IFS= read -r p; do
  b="$(basename "$p")"
  if [[ -n "$CUDA_VERSION" && "$b" == *cuda* ]]; then PKG="$p"; break; fi
  if [[ -z "$CUDA_VERSION" && "$b" == *cpu* ]]; then PKG="$p"; break; fi
  [[ -z "$PKG" ]] && PKG="$p"
done < <(find "$CHANNEL_DIR" \( -name 'deepmd-kit-[0-9]*.conda' -o -name 'deepmd-kit-[0-9]*.tar.bz2' \) | sort)
[[ -n "$PKG" ]] || fail "no deepmd-kit package found in $CHANNEL_DIR after build"

base="$(basename "$PKG")"; base="${base%.conda}"; base="${base%.tar.bz2}"
rest="${base#deepmd-kit-}"     # <version>-<build>  (conda versions never contain '-')
GOT_VERSION="${rest%%-*}"
GOT_BUILD="${rest#*-}"

# --- emit the pin file for Stage 2 (values QUOTED; consumed via safe parser) ---
ENV_OUT="$CHANNEL_DIR/COMMIT_BUILD.env"
cat > "$ENV_OUT" <<ENV
# Generated by build_pkg_from_commit.sh — consumed by build.sh --from-commit-channel
DEEPMD_COMMIT="$COMMIT"
DEEPMD_PKG_VERSION="$GOT_VERSION"
DEEPMD_PKG_BUILD="$GOT_BUILD"
DEEPMD_CUDA_VERSION="$CUDA_VERSION"
DEEPMD_PY_VERSION="$BUILD_PY"
ENV

echo ""
echo "STAGE 1 OK."
echo "  package : $base"
echo "  version : $GOT_VERSION"
echo "  build   : $GOT_BUILD"
echo "  python  : $BUILD_PY"
echo "  channel : $CHANNEL_DIR"
echo "  pin file: $ENV_OUT"
echo ""
echo "Next (Stage 2 — bundle this exact commit build into the offline installer):"
echo "  bash $(dirname "${BASH_SOURCE[0]}")/build.sh --from-commit-channel \"$CHANNEL_DIR\""
