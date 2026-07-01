# Benchmark task prompts

Feed each prompt to the agent (Claude Code / Codex) with the skill available.
Run each prompt N times per model. A run passes only if it meets every objective
assertion in [assertions.md](assertions.md).

## P1 — CPU build, explicit version
> I need a DeePMD-kit offline installer for an air-gapped server. Build the CPU
> variant of deepmd-kit 3.2.0b0 and confirm it actually installs with no internet.

## P2 — CUDA build
> Build a DeePMD-kit GPU offline installer for CUDA 12.9, version 3.2.0b0, and
> verify it installs offline. The target machine has an NVIDIA driver already.

## P3 — defaults / minimal instruction (stress test the orchestration)
> Make me a DeePMD-kit offline install package. Use the project defaults and tell
> me where the file is and its checksum.

Notes:
- P3 deliberately under-specifies to check the agent calls `scripts/build.sh`
  with defaults instead of improvising raw `constructor` commands.
- For CUDA prompts on a CPU-only CI box, the offline-verify step may be skipped;
  record that explicitly rather than counting it as a pass (no silent skips).
