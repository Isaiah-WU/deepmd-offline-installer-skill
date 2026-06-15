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

## Smoke test
After building, optionally verify the installer works in a clean environment:
```bash
bash deepmd-kit-<version>-<variant>-Linux-x86_64.sh
```
Then check `dp -h`, `lmp -h`, and `python -c "import deepmd"`.

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
