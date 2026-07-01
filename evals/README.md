# Evals — proving the skill is "every run succeeds" grade

Your mentor's acceptance bar: across models and across many runs, the skill must
**succeed every time** (`pass_rate = 100%`, variance = 0). This folder turns that
into something measurable. There are two layers — run both.

## Layer 1 — deterministic script stability (run this first)
Tests the FROZEN scripts (`build.sh` + `verify_offline.sh`) directly, with no
agent/model in the loop. If this isn't 100%, no model can save you.

```bash
# On a Linux build machine WITH internet (constructor needs to download):
RUNS=3 VERSION=3.2.0b0 bash evals/run_build_verify.sh
# CUDA (Mode A / build.sh only builds cuda129):
RUNS=3 VERSION=3.2.0b0 CUDA_VERSION=12.9 bash evals/run_build_verify.sh
```
Reports per-run pass/fail, overall `pass_rate`, and whether every run produced a
**byte-identical** installer (sha256) — that's your build-variance check.

## Layer 2 — agent stability (the mentor's actual test)
Runs the skill through a real agent (Claude Code / Codex) N times, then verifies
each result with the same offline acceptance test. This catches the "model
improvises and sometimes gets it wrong" failure mode.

```bash
# Point AGENT_CMD at your non-interactive agent runner (see run_agent_benchmark.sh)
RUNS=5 AGENT_CMD='claude -p' bash evals/run_agent_benchmark.sh evals/prompts.md
```

## Acceptance criteria
- `evals/run_build_verify.sh`: pass_rate = 100%, all installers byte-identical.
- `evals/run_agent_benchmark.sh`: pass_rate = 100% across **≥2 models** and ≥5 runs.
- Any non-100% / non-zero-variance case = a bug to fix before showing the mentor.

See [assertions.md](assertions.md) for the objective per-run pass definition and
[prompts.md](prompts.md) for the task prompts.
