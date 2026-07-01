# Objective pass/fail assertions

A run counts as PASS only if ALL of these are objectively true. No "the script
didn't error" hand-waving — offline-install success is the bar.

## Build-side (must all hold)
1. `scripts/build.sh` exits 0.
2. An installer `.sh` exists under `dist/<variant>/` (GPU builds may be 3 split parts `.sh.0/.1/.2`).
3. A manifest exists reporting an absolute path, size, and sha256.
4. The agent called `scripts/build.sh` (orchestration), NOT raw `constructor`
   commands typed from scratch.

## Install-side (the real acceptance — must all hold)
5. `scripts/verify_offline.sh <installer> <version>` exits 0, meaning in a
   network-isolated environment:
   - the installer installs into a clean prefix,
   - `dp -h` runs,
   - `lmp -h` runs,
   - `python -c "import deepmd"` succeeds,
   - `dp --version` matches the requested version.

## Stability (across runs)
6. pass_rate over N runs = 100%.
7. Build variance = 0: every run's installer sha256 is identical (Layer 1), OR
   the same package versions are bundled (check `dist/<variant>/*.lock.txt` from freeze.sh).

## Recording rule
- A skipped check (e.g. CUDA verify on a CPU-only box) is recorded as SKIP, never
  as PASS. A benchmark with skips is incomplete, not green.
