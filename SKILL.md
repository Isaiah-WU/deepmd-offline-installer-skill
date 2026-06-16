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
  version: '1.2'
---

# DeePMD-kit Offline Installer (local build)

Build a self-contained `.sh` offline installer for DeePMD-kit using conda
`constructor`. The recipe is **bundled in `assets/`**, so the build is
self-contained — no external repo checkout is required.

## Quick Start

Do NOT write build commands by hand. Call the bundled scripts with parameters.

**Mode A — package a RELEASED version (CPU or GPU):**

```bash
# CPU
bash scripts/build.sh --version 3.1.3
bash scripts/verify_offline.sh dist/deepmd-kit-3.1.3-cpu-Linux-x86_64.sh 3.1.3

# GPU (CUDA 12.9 matches upstream). Build on any node; VERIFY on a GPU node.
bash scripts/build.sh --version 3.1.3 --cuda 12.9
bash scripts/verify_offline.sh dist/deepmd-kit-3.1.3-cuda129-Linux-x86_64.sh 3.1.3
```

**Mode B — package a GIT COMMIT of deepmd-kit (two stages):**

```bash
# Stage 1: build the commit from source into a local conda channel (Docker; heavy,
# tens of min–>1h). Emits ./local-channel/COMMIT_BUILD.env (exact version+build+python).
bash scripts/build_pkg_from_commit.sh --commit <sha>                       # CPU (config auto-picked)
# GPU: pass a .ci_support config (run once with no --config to list them):
bash scripts/build_pkg_from_commit.sh --commit <sha> --cuda 12.9 \
     --config linux_64_cuda_compiler_version12.9mpimpichpython3.11.____cpython

# Stage 2: bundle that exact commit build into the offline installer.
bash scripts/build.sh --from-commit-channel ./local-channel
bash scripts/verify_offline.sh dist/*.sh
```

> Stage 1 (building a commit from source) must be validated on Linux against the
> live conda-forge feedstock — see [references/notes.md](references/notes.md).

A build is only "done" when the **verify step passes**, not when a `.sh` appears.

## Why two modes

`constructor` can only bundle conda packages that ALREADY exist on a channel; no
per-commit deepmd-kit conda package is published anywhere. So commit packaging
(Mode B) must FIRST build the commit from source into a local channel (Stage 1),
then constructor consumes it (Stage 2). Releases (Mode A) skip Stage 1.

## Agent responsibilities (orchestration only)

1. Confirm conda is available (`conda --version`). `build.sh` installs
   `constructor` / `conda-libmamba-solver` itself if missing.
2. Decide the mode: released **version** → Mode A; a deepmd-kit **commit** → Mode B.
3. Collect CPU-vs-CUDA (`--cuda <ver>`, recommend `12.9` for GPU).
4. Run the bundled scripts with those parameters. Never run raw `constructor`
   or `conda build` commands — the scripts freeze the error-prone steps.
5. Run `scripts/verify_offline.sh` (GPU mode auto-detected from the filename;
   GPU verify MUST run on a node with an NVIDIA GPU + driver).
6. Report the manifest (absolute path + size + sha256) and the verify result.

## Key parameters

| Flag / env                | Meaning                                       | Default     |
| ------------------------- | --------------------------------------------- | ----------- |
| `--version`               | deepmd-kit version (Mode A)                    | 3.1.3       |
| `--cuda`                  | CUDA version; omit/empty = CPU build           | "" (CPU)    |
| `--from-commit-channel`   | local channel from Stage 1 (Mode B)            | —           |
| `--split <N>`             | split GPU `.sh` into N parts (GitHub 2GiB cap) | off         |
| `--recipe-dir`            | recipe dir with construct.yaml                 | bundled `assets/` |
| `--output-dir`            | where the installer is written                 | `./dist`    |
| `--commit` (Stage 1)      | deepmd-kit git commit to build                 | —           |
| `TF_VERSION`/`LAMMPS_VERSION` env | pin TensorFlow / LAMMPS                 | `>=2.19` / unpinned |

## Agent checklist

- [ ] conda available
- [ ] Mode A: `build.sh --version` (+ `--cuda` if GPU) — OR — Mode B: `build_pkg_from_commit.sh --commit` then `build.sh --from-commit-channel`
- [ ] `.sh` installer produced; manifest reports absolute path + sha256
- [ ] `verify_offline.sh` PASSED (installs + `dp -h`/`lmp -h` offline; GPU mode also checks `nvidia-smi` + TF GPU/XLA)
- [ ] reported version matches the requested version/commit build

## Notes & troubleshooting

- Targets, requirements, the manual `constructor` workflow (for debugging only),
  reproducibility/pinning, the freeze→pin loop, GPU specifics, and the full
  commit-based (two-stage) flow are documented in
  [references/notes.md](references/notes.md).
- GPU builds export `CONDA_OVERRIDE_CUDA` / `CONDA_OVERRIDE_GLIBC` and use the
  libmamba solver so a GPU-less build node can still resolve the CUDA variant;
  the resulting `.sh` is multi-GB (use `--split` for GitHub's 2GiB asset cap).
- For stable releases, do not build off the `deepmd-kit_rc` channel label — see
  the warning at the top of `assets/construct.yaml`.
- CI template to build on every merge: `assets/build-on-merge.yml`.
