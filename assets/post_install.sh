# --- TensorFlow GPU libdevice safety net -------------------------------------
# TF>=2.19 XLA JIT needs libdevice.10.bc at <prefix>/nvvm/libdevice/. The
# njzjz libdevice-hack provides this via a symlink, but a layout/CUDA-version
# drift can leave it dangling (TF then errors "libdevice not found"). Repair it
# here and point XLA at the prefix via an activate hook, so the env self-heals.
if [ -n "${PREFIX:-}" ]; then
  REAL=$(find "$PREFIX" -name 'libdevice.10.bc' -not -path '*/site-packages/nvidia/cuda_nvcc/*' 2>/dev/null | head -1)
  if [ -n "$REAL" ]; then
    mkdir -p "$PREFIX/nvvm/libdevice"
    ln -sf "$REAL" "$PREFIX/nvvm/libdevice/libdevice.10.bc"
    HOOK="$PREFIX/etc/conda/activate.d/zz-xla-libdevice.sh"
    mkdir -p "$(dirname "$HOOK")"
    printf 'export XLA_FLAGS="--xla_gpu_cuda_data_dir=$CONDA_PREFIX${XLA_FLAGS:+ $XLA_FLAGS}"\n' > "$HOOK"
  fi
fi

cat << EOF
Please activate the environment before using the packages:

source /path/to/deepmd-kit/bin/activate /path/to/deepmd-kit

This package enables TensorFlow, PyTorch, and JAX backends.

The following executable files have been installed:
1. DeePMD-kit CLi: dp -h
2. LAMMPS: lmp -h
3. DeePMD-kit i-Pi interface: dp_ipi
4. MPICH: mpirun -h
5. Horovod: horovod -h

The following Python libraries have been installed:
1. deepmd
2. dpdata
3. pylammps

If you have any questions, seek help from https://github.com/deepmodeling/deepmd-kit/discussions

EOF
