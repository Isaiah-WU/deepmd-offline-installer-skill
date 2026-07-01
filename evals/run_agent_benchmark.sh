#!/usr/bin/env bash
# Layer 2 — agent stability benchmark (the mentor's actual test).
# Drives a real agent (Claude Code / Codex) through each task prompt N times,
# then applies the offline acceptance test to whatever the agent produced.
#
# Usage:
#   RUNS=5 AGENT_CMD='claude -p' bash evals/run_agent_benchmark.sh evals/prompts.md
#
# AGENT_CMD must be a NON-INTERACTIVE agent invocation that reads a prompt on
# stdin (or $1) and runs to completion in this repo with the skill enabled, e.g.:
#   claude -p                 (Claude Code headless: prompt via stdin)
#   codex exec                (Codex non-interactive)
# Adjust the call below to match your agent CLI.
#
# This script is intentionally a TEMPLATE: agent CLIs differ, and only you can
# run them (this environment has no network). Wire AGENT_CMD + the verify glob to
# your setup, then loop across ≥2 models to satisfy "model-agnostic".
set -uo pipefail

RUNS="${RUNS:-5}"
AGENT_CMD="${AGENT_CMD:?set AGENT_CMD, e.g. AGENT_CMD='claude -p'}"
PROMPTS_FILE="${1:?usage: run_agent_benchmark.sh <prompts.md>}"
VERSION="${VERSION:-3.2.0b0}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
RESULTS="$SKILL_ROOT/dist/agent-eval-results.txt"
mkdir -p "$SKILL_ROOT/dist"; : > "$RESULTS"

# Extract each "## Px" prompt block from the prompts file (lines after a `> `).
mapfile -t PROMPTS < <(grep '^> ' "$PROMPTS_FILE" | sed 's/^> //')

total=0; pass=0
for p in "${PROMPTS[@]}"; do
  for i in $(seq 1 "$RUNS"); do
    total=$((total+1))
    echo "### prompt='${p:0:50}...' run=$i ###"
    rm -rf "$SKILL_ROOT/dist"/*/*.sh 2>/dev/null || true

    # ---- run the agent (adapt this line to your CLI) ----
    echo "$p" | $AGENT_CMD

    # ---- objective acceptance: did it produce a verifiable offline installer? ----
    installer="$(ls "$SKILL_ROOT/dist"/*/*.sh 2>/dev/null | head -1)"
    if [[ -n "$installer" ]] && bash "$SKILL_ROOT/scripts/verify_offline.sh" "$installer" "$VERSION"; then
      pass=$((pass+1)); echo "  -> PASS" | tee -a "$RESULTS"
    else
      echo "  -> FAIL" | tee -a "$RESULTS"
    fi
  done
done

rate=$(awk "BEGIN{printf \"%.0f\", ($pass/$total)*100}")
echo "agent pass_rate: $pass/$total = ${rate}%" | tee -a "$RESULTS"
[[ "$pass" -eq "$total" ]] && echo "ACCEPTANCE MET for this model. Repeat with another model." || echo "ACCEPTANCE NOT MET."
