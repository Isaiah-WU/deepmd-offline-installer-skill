# DeePMD-kit Offline Installer — Reference Notes

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
- The .sh installer can be large (~1.4 GB CPU build). Large installers may be
  split into two files due to GitHub size limits; users join them with `cat`.

## Acceptance test (the real "done")
"constructor produced a .sh" is necessary but NOT sufficient — the installer can
still fail on a target machine (dependency/channel issues, post_install errors,
GLIBC/driver mismatch). The real acceptance test is an OFFLINE install:
```bash
bash scripts/verify_offline.sh dist/deepmd-kit-<version>-<variant>-Linux-x86_64.sh <version>
```
It installs the .sh into a throwaway prefix with the network cut off (unshare/docker)
and asserts `dp -h`, `lmp -h`, `import deepmd`, and version match. Exit code 0 = pass.

## Manual build (debugging only — NOT the main path)
The main path is `scripts/build.sh`. These raw commands are for diagnosing a build
failure only; the agent should not run them as the normal workflow.
```bash
conda install constructor -y
cd assets                 # the bundled recipe directory (contains construct.yaml)
export VERSION=3.1.3
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
  1. Build once: `bash scripts/build.sh --version 3.1.3`
  2. Capture exact versions: `bash scripts/freeze.sh dist/<installer>.sh`
  3. Paste the reported exact versions back into construct.yaml specs.
  The explicit lock (`dist/<installer>.lock.txt`) records exactly what was bundled.

## Automating the build on every PR (CI)
The local build can be automated so a new installer is built whenever a PR is
merged (similar to PyTorch nightly builds). This is done with a CI workflow
(e.g. GitHub Actions) that runs the same steps as scripts/build.sh:
1. trigger on merge to the main branch
2. set up conda + constructor
3. run constructor with the desired VERSION / CUDA_VERSION
4. upload the resulting .sh to the release page

A minimal GitHub Actions workflow template is provided in
assets/build-on-merge.yml as a starting point.
