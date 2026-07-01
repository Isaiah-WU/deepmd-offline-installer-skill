# DeePMD-kit Offline Installer — Reference Notes

> **范围**:本文件是 **Mode A**(conda constructor,`build.sh` → cpu/cuda129)与
> **Mode B**(commit → 本地 channel,`build_pkg_from_commit.sh`)的构建/排查参考。
> GPU 的 cuda126/cuda128 由 **Mode C**(`build_modec.sh`,pip torch + conda-pack)构建,不在本文;
> 完整架构、nightly 流水线与发布模型见 [verification-log.md](verification-log.md)。

## Build requirements
- conda must be installed; constructor is installed on demand.
- Internet access is required at build time (constructor downloads packages).
- The produced .sh installer and conda packages require GNU C Library 2.17+.
- GPU (CUDA) installers require a compatible NVIDIA driver at runtime.

## Caution points
- Run constructor inside the recipe directory (the folder containing construct.yaml),
  not the deepmd-kit source repo. They have similar names; use the installer repo.
- VERSION and CUDA_VERSION are read from environment variables by the recipe.
  Empty CUDA_VERSION builds the CPU variant.
- CPU build is recommended for first runs (fewer dependencies, fewer failures).
- The .sh installer can be large (GPU builds are multi-GB). Large installers are
  split into three parts (.sh.0/.1/.2) for GitHub's 2GiB per-asset limit; users
  join them with `cat` (or let dpack reassemble automatically).

## Acceptance test (the real "done")
"constructor produced a .sh" is necessary but NOT sufficient — the installer can
still fail on a target machine (dependency/channel issues, post_install errors,
GLIBC/driver mismatch). The real acceptance test is an OFFLINE install:
```bash
bash scripts/verify_offline.sh dist/<variant>/*.sh <version>   # 产物在 dist/<variant>/,名为 ...-<YYYYMMDD>-<hash>-...
```
It installs the .sh into a throwaway prefix with the network cut off (unshare/docker)
and asserts `dp -h`, `lmp -h`, `import deepmd`, and version match. Exit code 0 = pass.

## Manual build (debugging only — NOT the main path)
The main path is `scripts/build.sh`. These raw commands are for diagnosing a build
failure only; the agent should not run them as the normal workflow.
```bash
conda install constructor -y
cd assets                 # the bundled recipe directory (contains construct.yaml)
export VERSION=3.2.0b0
export CUDA_VERSION=      # empty = CPU
constructor . --output-dir ../dist
```

## Reproducibility & pinning (kills "sometimes works, sometimes fails")
constructor downloads packages at build time, so any floating spec can drift.
- Channels are pinned in construct.yaml. WARNING: `deepmd-kit_rc` is a release
  CANDIDATE label whose packages rotate/disappear — use the stable conda-forge
  label for release builds.
- Pin major movers via env vars: VERSION, TF_VERSION, LAMMPS_VERSION, FLAX_VERSION.
- Freeze → pin loop for byte-stable rebuilds:
  1. Build once: `bash scripts/build.sh --version 3.2.0b0`
  2. Capture exact versions: `bash scripts/freeze.sh dist/<variant>/<installer>.sh`
  3. Paste the reported exact versions back into construct.yaml specs.
  The explicit lock (`dist/<variant>/<installer>.lock.txt`) records exactly what was bundled.

## GPU / CUDA builds
> 本节是 **Mode A** 的 GPU 构建(constructor → cuda129,conda-forge 每版本唯一的 CUDA 包)。
> conda-forge 不发布的 cuda126/cuda128 由 **Mode C**(`build_modec.sh`)构建,不走 constructor;
> cuda131 = cuda128 改名给 13.1 机器。

The CUDA variant is already wired into construct.yaml (extra specs gated on a
non-empty CUDA_VERSION: `cuda-version`, `njzjz/noarch::libdevice-hack-for-tensorflow`,
`openmpi`; deepmd-kit/horovod/jaxlib build strings flip `cpu*`→`cuda*`).
- Build node may have NO GPU. `build.sh` exports `CONDA_OVERRIDE_CUDA=$CUDA_VERSION`
  and `CONDA_OVERRIDE_GLIBC=2.28` and uses the libmamba solver (matches upstream
  deepmd-kit-recipes/installer CI) so the CUDA graph resolves without a `__cuda`
  virtual package. Without these the solve fails on a GPU-less node.
- Use `--cuda 12.9` (upstream default for current packages). A `cuda129` build
  runs on any sufficiently new 12.x driver (NVIDIA minor-version compatibility),
  not only driver 12.9.
- `libdevice-hack-for-tensorflow` fixes TF/XLA "libdevice not found"; without it
  the GPU is detected but XLA-compiled ops fail at runtime. The GPU verify runs a
  `tf.function(jit_compile=True)` op specifically to exercise this.
- The GPU `.sh` is multi-GB and exceeds GitHub's 2GiB per-asset limit. Use
  `build.sh --split 3` to produce `.0/.1/.2`; reassemble with
  `cat NAME.0 NAME.1 NAME.2 > NAME`. For local Bohrium verify, skip splitting.
- GPU verify MUST run on a node WITH a GPU + driver. `unshare -rn` cuts network
  but keeps `/dev/nvidia*`, so the GPU stays visible inside the namespace.
  `verify_offline.sh` auto-detects GPU mode from a `*cuda*` filename (override
  with `VERIFY_GPU=1/0`) and adds `nvidia-smi` + TF GPU/XLA + torch.cuda checks.

## Commit-keyed packaging (two-stage; for frequent dev builds)
Goal: package a specific deepmd-kit GIT COMMIT, not a released version.
KEY FACT: no per-commit deepmd-kit conda package exists on any channel, and
`constructor` can only bundle EXISTING conda packages. So a commit must be built
from source FIRST, into a local channel, which constructor then consumes.

> ⚠️ Stage 1 is a real feedstock-engineering step and MUST be validated/iterated
> on Linux against the LIVE conda-forge/deepmd-kit-feedstock. The script fails
> loudly when an assumption breaks rather than emitting junk. Building a compiled
> CUDA package per commit needs Docker and tens of minutes to >1h.

- **Stage 1 — `scripts/build_pkg_from_commit.sh --commit <sha> [--cuda 12.9] [--config <stem>]`**
  Drives the MAINTAINED `conda-forge/deepmd-kit-feedstock` (the stale git-source
  fork `deepmd-kit-recipes/deepmd-kit-feedstock` is frozen at v2.2.11 and cannot
  build a modern commit). It:
  1. clones the feedstock and **rewrites the recipe `source:`** from the release
     tarball (`url:` + `sha256:`) to a git source (`git_url` + `git_rev: <sha>`),
     leaving the second (lammps) source and the `folder:` layout intact;
  2. sets the conda **version label** (`--pkg-version`, else derived via
     `git describe`, e.g. `3.2.0b1.dev17`) — required because the recipe ties
     name/build-string to `{% set version %}`, so changing only `git_rev` would
     mislabel the package;
  3. builds with a **`.ci_support/<config>.yaml` variant** (NOT a hand-crafted
     `--variants`): `CI=1 python build-locally.py <config>` (Docker). The configs
     are named e.g. `linux_64_cuda_compiler_version12.9mpimpichpython3.11...`
     (CUDA 12.9 / None × py3.10/3.11/3.12). CPU config is auto-picked; for CUDA
     pass `--config` (run once with no `--config` to list them). NOTE: the COMPILER
     cuda in the config name is distinct from the RUNTIME `--cuda` pinned in Stage 2.
  4. writes `local-channel/COMMIT_BUILD.env` (quoted) with the EXACT
     version + build string + **python** + cuda + commit.
- **Stage 2 — `scripts/build.sh --from-commit-channel ./local-channel`**
  Safely parses COMMIT_BUILD.env (no `source`), prepends the local channel
  (`DEEPMD_LOCAL_CHANNEL`), pins deepmd-kit to the exact build string
  (`DEEPMD_BUILD`) AND co-pins `python` (`DEEPMD_PY_VERSION`) so floating
  tensorflow/lammps can't drag in an incompatible interpreter. Then constructor +
  verify run as for releases.
- Why not pip-from-git: pip builds only the Python `dp` command, not the `lmp`
  LAMMPS binary / C++ interface (separate CMake build) — it would break the
  existing `lmp -h` offline acceptance test.
- For "very frequent" packaging, automate Stage 1 in CI (matrix cpu + each CUDA),
  cache conda/compiler artifacts. **Cleanest long-term: have upstream (njzjz)
  publish per-commit conda packages to a dedicated label, collapsing Stage 1 to
  "point constructor at that channel"** — worth raising with jinzhe.

## Automating the build (CI)
The live CI is [`.github/workflows/nightly.yml`](../.github/workflows/nightly.yml) (PyTorch-nightly-style):
1. runs daily (cron) or on manual `workflow_dispatch`
2. detects the latest deepmd-kit on PyPI (`detect_latest_deepmd.py`); builds only when it changed
3. builds the FULL matrix — cpu/cuda129 (Mode A) + cuda126/cuda128 (Mode C) + a cuda131 alias — on a no-GPU runner
4. runs a no-GPU smoke test per variant, uploads dated split parts to the per-version Release (tag `v<version>`)
5. a `manifest` job merges the fragments and commits `assets/manifest.json` directly

There is no per-night GPU verify lane; see [verification-log.md](verification-log.md) for the full design and rationale.
