---
name: deepmd-offline-installer
description: >
  Build a DeePMD-kit offline installer (.sh) locally using conda constructor.
  Produces a self-contained installer that installs deepmd-kit, lammps and all
  dependencies on machines without internet access.
  USE WHEN the user wants to build/make a DeePMD-kit offline installer package
  locally, or reproduce the installer build outside of CI.
compatibility: Requires conda. Internet access needed at build time to download packages. Builds CPU or CUDA variants.
license: LGPL-3.0-or-later
metadata:
  author: Isaiah-WU
  version: '1.0'
---

# DeePMD-kit Offline Installer (local build)

Build a self-contained `.sh` offline installer for DeePMD-kit using conda
`constructor`, locally instead of on CI.

## Quick Start

```bash
conda install constructor -y
cd <installer-repo>/deepmd-kit
export VERSION=3.1.3
export CUDA_VERSION=
constructor .
```

## Agent responsibilities

1. Confirm conda is available (`conda --version`).
2. Confirm `constructor` is installed; if not, install it.
3. Confirm the installer recipe directory (with `construct.yaml`) is available.
4. Collect the build parameters:
   - target version (e.g. 3.1.3)
   - CPU or CUDA variant (CUDA version string, or empty for CPU)
5. Run constructor and confirm the `.sh` installer is produced.
6. Report the output file name and size.

## Workflow

### Step 1: Install constructor

```bash
conda install constructor -y
constructor --version
```

### Step 2: Get the recipe

The recipe lives in the deepmd-kit-installer repo, folder `deepmd-kit/`,
containing `construct.yaml`, `pre_install.sh`, `post_install.sh`.

```bash
cd /path/to/deepmd-kit-installer/deepmd-kit
ls
```

### Step 3: Set build parameters

The recipe reads VERSION and CUDA_VERSION from environment variables.

```bash
export VERSION=3.1.3
export CUDA_VERSION=      # empty = CPU build; set e.g. 12.1 for CUDA build
```

### Step 4: Build the installer

```bash
constructor .
```

##mpletes without errors
- [ ] `.sh` installer produced and size reported

## References

- conda constructor docs: https://conda.github.io/constructor/
- deepmd-kit-installer repo: https://github.com/deepmodeling-activity/deepmd-kit-installer

## Bundled files

- `scripts/build.sh`: one-click build script. Run:
  `bash scripts/build.sh <recipe_dir> <version> [cuda_version]`
- `assets/construct.yaml`, `assets/pre_install.sh`, `assets/post_install.sh`:
  the constructor recipe (reference copy).
- `assets/build-on-merge.yml`: GitHub Actions template to auto-build on every
  merge (PyTorch-nightly style).
- `references/notes.md`: build requirements, caution points, smoke test, and
  CI automation notes.
