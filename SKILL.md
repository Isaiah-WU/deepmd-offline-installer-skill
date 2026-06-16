---
name: deepmd-offline-installer
description: >
  Build a DeePMD-kit offline installer (.sh) locally using conda constructor.
  Produces a self-contained installer that installs deepmd-kit, lammps and all
  dependencies on machines without internet access.
  USE WHEN the user wants to build, make, or create a DeePMD-kit offline
  installer package locally, package deepmd-kit for offline install, or
  reproduce the installer build outside of CI.
compatibility: Requires conda. Internet access needed at build time. Builds CPU or CUDA variants.
license: LGPL-3.0-or-later
metadata:
  author: Isaiah-WU
  version: '1.1'
---

# DeePMD-kit Offline Installer (local build)

Build a self-contained `.sh` offline installer for DeePMD-kit using conda
`constructor`. The recipe is **bundled in `assets/`**, so the build is
self-contained — no external repo checkout is required.

## Quick Start

Do NOT write build commands by hand. Call the bundled scripts with parameters:

```bash
# 1) Build (CPU). Recipe defaults to the bundled assets/; output goes to ./dist
bash scripts/build.sh --version 3.1.3

# 1b) CUDA build
bash scripts/build.sh --version 3.1.3 --cuda 12.1

# 2) Acceptance test: prove it installs and runs OFFLINE
bash scripts/verify_offline.sh dist/deepmd-kit-3.1.3-cpu-Linux-x86_64.sh 3.1.3
```

A build is only "done" when **step 2 passes**, not when step 1 produces a `.sh`.

## Agent responsibilities (orchestration only)

1. Confirm conda is available (`conda --version`). `build.sh` installs
   `constructor` itself if missing.
2. Collect parameters from the user: `version` and CPU-vs-CUDA (`--cuda <ver>`).
3. Run `scripts/build.sh` with those parameters. Do not run raw `constructor`
   commands — the script freezes the error-prone steps.
4. Run `scripts/verify_offline.sh` on the produced installer.
5. Report the manifest (absolute path + size + sha256) and the verify result.

## Key parameters

| Flag / env      | Meaning                                   | Default     |
| --------------- | ----------------------------------------- | ----------- |
| `--version`     | deepmd-kit version                        | 3.1.3       |
| `--cuda`        | CUDA version; omit/empty = CPU build      | "" (CPU)    |
| `--recipe-dir`  | recipe dir with construct.yaml            | bundled `assets/` |
| `--output-dir`  | where the installer is written            | `./dist`    |
| `TF_VERSION` env    | pin TensorFlow                        | `>=2.19`    |
| `LAMMPS_VERSION` env| pin LAMMPS                            | unpinned    |

## Agent checklist

- [ ] conda available
- [ ] `scripts/build.sh` run with explicit version (+ `--cuda` if GPU)
- [ ] `.sh` installer produced; manifest reports absolute path + sha256
- [ ] `scripts/verify_offline.sh` PASSED (installs + `dp -h`/`lmp -h` work offline)
- [ ] reported version matches the requested version

## Notes & troubleshooting

- Targets, requirements, the manual `constructor` workflow (for debugging only),
  reproducibility/pinning, and the freeze→pin loop are documented in
  [references/notes.md](references/notes.md).
- For stable releases, do not build off the `deepmd-kit_rc` channel label — see
  the warning at the top of `assets/construct.yaml`.
- CI template to build on every merge: `assets/build-on-merge.yml`.
