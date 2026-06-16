#!/usr/bin/env bash
# Layer 1 — deterministic stability benchmark for the FROZEN scripts.
# Runs build.sh + verify_offline.sh RUNS times, reports pass_rate and build
# variance (byte-identical installers across runs?).
#
# Usage (on a Linux build machine WITH internet):
#   RUNS=3 VERSION=3.1.3 bash evals/run_build_verify.sh
#   RUNS=3 VERSION=3.1.3 CUDA_VERSION=12.1 bash evals/run_build_verify.sh
#
# NOTE: do not use `set -e` here — we must keep looping past a failed run to
# compute an honest pass_rate.
set -uo pipefail

RUNS="${RUNS:-3}"
VERSION="${VERSION:-3.1.3}"
CUDA_VERSION="${CUDA_VERSION:-}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
RESULTS="$SKILL_ROOT/dist/eval-results.txt"
mkdir -p "$SKILL_ROOT/dist"
: > "$RESULTS"

variant_label="${CUDA_VERSION:+cuda$CUDA_VERSION}"; variant_label="${variant_label:-cpu}"
echo "Benchmark: version=$VERSION variant=$variant_label runs=$RUNS"
echo "================================================================"

pass=0
declare -a shas=()

cuda_flag=()
[[ -n "$CUDA_VERSION" ]] && cuda_flag=(--cuda "$CUDA_VERSION")

for i in $(seq 1 "$RUNS"); do
  echo ""
  echo "### RUN $i/$RUNS ###"
  out="$SKILL_ROOT/dist/run-$i"
  rm -rf "$out"; mkdir -p "$out"

  if bash "$SKILL_ROOT/scripts/build.sh" --version "$VERSION" "${cuda_flag[@]}" --output-dir "$out"; then
    installer="$(ls "$out"/*.sh 2>/dev/null | head -1)"
    if [[ -n "$installer" ]] && bash "$SKILL_ROOT/scripts/verify_offline.sh" "$installer" "$VERSION"; then
      sha="$(sha256sum "$installer" | cut -d' ' -f1)"
      shas+=("$sha")
      pass=$((pass+1))
      echo "RUN $i: PASS  sha256=$sha" | tee -a "$RESULTS"
    else
      echo "RUN $i: FAIL  (offline verify failed or no installer)" | tee -a "$RESULTS"
    fi
  else
    echo "RUN $i: FAIL  (build failed)" | tee -a "$RESULTS"
  fi
done

echo ""
echo "================================================================"
rate=$(awk "BEGIN{printf \"%.0f\", ($pass/$RUNS)*100}")
echo "pass_rate: $pass/$RUNS = ${rate}%" | tee -a "$RESULTS"

# build variance: are all passing installers byte-identical?
if [[ ${#shas[@]} -gt 0 ]]; then
  uniq_count="$(printf '%s\n' "${shas[@]}" | sort -u | wc -l)"
  if [[ "$uniq_count" -eq 1 ]]; then
    echo "build_variance: ZERO (all installers byte-identical)" | tee -a "$RESULTS"
  else
    echo "build_variance: NONZERO ($uniq_count distinct sha256 across passing runs) -> PIN versions (see freeze.sh)" | tee -a "$RESULTS"
  fi
fi

echo ""
if [[ "$pass" -eq "$RUNS" ]]; then
  echo "ACCEPTANCE: pass_rate=100%. Now confirm build_variance is ZERO before sign-off."
  exit 0
else
  echo "ACCEPTANCE: NOT MET. Fix the failing runs (see $RESULTS and dist/run-*/build-*.log)."
  exit 1
fi
