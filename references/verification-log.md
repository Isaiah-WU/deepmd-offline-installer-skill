# Verification Log（内部验证记录）

> 测试平台：Bohrium，Tesla V100 / T4，驱动 CUDA 13.0 / 13.1。deepmd-kit `3.2.0b0`。

## 关键事实：deepmd-kit 3.2.0b0 的 LAMMPS 插件是 **CUDA 12** 编译的
deepmd 的 LAMMPS 插件（libdeepmd_op.so）运行时**硬 dlopen `libcudart.so.12`**（CUDA 12）。PyPI 只有一个通用 wheel = CUDA 12；conda-forge 也是 cuda-version 12.9。**deepmd 3.2.0b0 没有任何 CUDA 13 构建。** 由此：

- **CUDA 12 的包（cuda126 / cuda128）LAMMPS 正常**，且靠 NVIDIA 驱动向后兼容**覆盖 13.x 机器（含 13.1）**。
- **CUDA 13 的包（cuda130）已弃**：CUDA-13 torch + CUDA-12 deepmd 同进程，torch 的 JIT 融合内核会崩（13.1/T4 实测 `fused_add_…` 崩溃，3 次 1 通 2 崩，不可靠）。
- PyTorch 也无 cu131（`download.pytorch.org/whl/cu131` = 404）→ **原生 CUDA 13.1 包做不出**。
- **给 CUDA 13.1 机器的可靠安装包 = `cuda128`**（13.1/T4 实测 train+freeze+lammps 跑通）。

## 变体与后端
| 变体 | torch CUDA | 覆盖驱动 | GPU 后端 | 构建 |
|---|---|---|---|---|
| `cpu`     | —    | 全部（CPU）       | TF + JAX + PyTorch | Mode A |
| `cuda126` | 12.6 | ≥ 12.6（含 13.x） | PyTorch            | Mode C |
| `cuda128` | 12.8 | ≥ 12.8（含 13.x） | PyTorch            | Mode C |
| `cuda129` | 12.9 | ≥ 12.9（含 13.x） | TF + JAX + PyTorch | Mode A |

> `cuda130` 已从构建与 manifest 中移除（原因见上）。

## 验证状态
| 变体 | 安装 + GPU 可见 | 完整 train → freeze → lammps |
|---|:---:|---|
| `cpu`     | ✅ | ✅ Mode A 基线 |
| `cuda126` | ✅ | ✅ |
| `cuda128` | ✅ | ✅ **含 13.1 / T4 实测跑通** |
| `cuda129` | ✅ | ⏳ Mode A，新 GPU 节点 LAMMPS 待严格验证（现 dpack 对 13.x/12.9 默认选它） |

> ⚠️ 更正：早前"5 变体全部完整验证"对 `cuda130` 是**过度宣称**（当时 LAMMPS 未真跑）。
> 经 13.1/T4 严格测试，`cuda130` 的 LAMMPS 崩溃，已弃。本表只标实际跑通的结果。

## 安装方式
| 方式 | 命令 |
|---|---|
| dpack 引导（用户目录、无 root） | `curl install.sh \| bash` |
| dpack 在线（自动选版本 → 下载 → 校验 → 装） | `dpack install dp` |
| dpack 离线（无网） | `dpack install dp --file <pkg.sh> [--sha256 <hex>]` |
