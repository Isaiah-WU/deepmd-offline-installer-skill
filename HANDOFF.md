# Handoff — how to verify this skill is mentor-grade

This skill builds a DeePMD-kit **offline installer** (`.sh`) with conda
`constructor`, then proves it installs on an air-gapped machine. Your mentor's
bar: **every run succeeds, on any model** (`pass_rate = 100%`, variance = 0).

## What changed (and why it matters for "every run succeeds")
| Fix | Why |
| --- | --- |
| `build.sh` now defaults to the **bundled** `assets/` recipe | Old script required an external repo dir → failed on clean machines → model improvised. Now self-contained. |
| Added repo-root `LICENSE` | `construct.yaml` references `../LICENSE`; it was missing, so even the bundled recipe couldn't build. |
| `build.sh` hardened (`set -euo pipefail`, arg + construct.yaml checks, manifest with abs path + sha256) | Deterministic success/fail signal instead of a bare `ls`. |
| `construct.yaml` parameterized + RC-label warning + `freeze.sh` | Floating specs were the "sometimes fails" root cause. Now pinnable; freeze captures exact versions. |
| New `scripts/verify_offline.sh` | The missing acceptance test: installs the `.sh` with the network cut off and asserts `dp`/`lmp`/version. |
| `SKILL.md` is orchestration-only; raw `constructor` moved to `references/notes.md`; removed `#ler` junk | One path, not two → less model variance. |
| New `evals/` harness | Turns "run it many times, all pass" into a measurable pass_rate + variance. |

## The acceptance flow (run in this order)

### 1. On a Linux build machine WITH internet
```bash
cd deepmd-offline-installer-skill
bash scripts/build.sh --version 3.1.3            # CPU; add --cuda 12.1 for GPU
bash scripts/verify_offline.sh dist/*.sh 3.1.3   # proves offline install works
bash scripts/freeze.sh dist/*.sh                 # capture exact pins -> dist/*.lock.txt
```
Then paste the key versions from the freeze output into `assets/construct.yaml`.

### 2. Deterministic stability (Layer 1)
```bash
RUNS=3 VERSION=3.1.3 bash evals/run_build_verify.sh
```
Want: `pass_rate: 3/3 = 100%` and `build_variance: ZERO`.

### 3. Agent stability (Layer 2 — the mentor's actual test)
```bash
RUNS=5 AGENT_CMD='claude -p' bash evals/run_agent_benchmark.sh evals/prompts.md
# repeat with a second model / Codex to prove model-agnostic
```
Want: `agent pass_rate = 100%` on ≥2 models.

## Sign-off checklist (show the mentor)
- [ ] Layer 1: pass_rate 100%, build_variance ZERO
- [ ] Layer 2: pass_rate 100% across ≥2 models, ≥5 runs each
- [ ] versions pinned in `construct.yaml` (from `freeze.sh`); not building off `deepmd-kit_rc`
- [ ] `dist/*.lock.txt` committed as the reproducibility record

## Known limits / honest gaps
- This was edited on Windows with no network — the scripts are **syntax-checked
  but not run**. The actual constructor build + offline verify must run on a
  Linux box (constructor installers are `Linux-x86_64`).
- CUDA offline-verify needs a GPU host with an NVIDIA driver; on a CPU-only box
  the verify step records SKIP (not PASS).
- GLIBC ≥ 2.17 is required on any target machine.
