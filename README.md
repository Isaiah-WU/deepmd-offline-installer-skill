# dpack — DeepModeling 包管理器

[中文版](#中文版) | [English Version](#english-version)

> 一行命令，在任何机器（包括断网超算）装上 DeePMD-kit 全套。
> 自动识别 GPU/CUDA → 选版本 → 下载 → 安装。对标 pixi / brew / conda。

---

## 中文版

### 1 · 安装 dpack

装到用户目录，**不需要 root**：

```bash
curl -fsSL https://raw.githubusercontent.com/Isaiah-WU/deepmd-dpack/main/install.sh | bash
```

如提示 `dpack` 找不到，执行 `export PATH="$HOME/.local/bin:$PATH"` 或重开终端。

### 2 · 用 dpack 装工具

```bash
# 有网机器：自动检测 GPU/CUDA，下载对应版本并安装
dpack install dp

# 断网机器（超算）：先手动把离线包拷过去，再指向本地文件
dpack install dp --file ./deepmd-kit-3.2.0b0-20260624-a1b2c3d-cuda129-Linux-x86_64.sh

# 装完按提示激活即可
source <安装路径>/bin/activate <安装路径>
dp --version
```

> GPU 用户只装这一个包就行：它覆盖**整个 CUDA 12.x ~ 13.x 驱动**，不用对版本
> （靠 [NVIDIA 向后兼容](https://docs.nvidia.com/deploy/cuda-compatibility/)）。

### 3 · 命令一览

| 命令 | 作用 |
|------|------|
| `dpack install dp` | 在线安装：自动选版本 → 下载 → 装 |
| `dpack install dp --file <pkg.sh>` | 离线安装：从本地离线包安装 |
| `dpack install dp --prefix <dir>` | 指定安装目录 |
| `dpack list` | 查看已安装的工具 |

#### 离线安装与分片包

GPU 离线包很大（约 6 GB），超过 GitHub 单文件 2 GB 上限，所以被切成 3 片：
`...sh.0`、`...sh.1`、`...sh.2`。**你不用手动合并——`--file` 指向去掉 `.0` 的“基础文件名”，dpack 会自动把同目录下的分片拼好再安装。**

```bash
# 情况一：单个完整 .sh（CPU 包，没切片）—— 直接指它
dpack install dp --file ./deepmd-kit-3.2.0b0-20260624-8f40cf6-cpu-Linux-x86_64.sh

# 情况二：分片包（GPU 包）—— 把 3 片放同一个目录：
#   deepmd-kit-...-cuda129-Linux-x86_64.sh.0
#   deepmd-kit-...-cuda129-Linux-x86_64.sh.1
#   deepmd-kit-...-cuda129-Linux-x86_64.sh.2
# 然后 --file 指向【不带 .0 的基础名】，dpack 自动 cat 合并再装：
dpack install dp --file ./deepmd-kit-3.2.0b0-20260624-8f40cf6-cuda129-Linux-x86_64.sh
#                              ↑ 注意：结尾是 .sh，不是 .sh.0
```

> 超算场景：在有网机器从 [Release](https://github.com/Isaiah-WU/deepmd-dpack/releases) 下载 3 片 →
> U 盘拷到断网机器同一目录 → 上面那条命令一行装好（无需联网、无需 root）。
> 也可以手动合并：`cat *.sh.0 *.sh.1 *.sh.2 > full.sh && bash full.sh -b -p /opt/deepmd`。

### 4 · 支持的工具

| 工具 | 说明 | 状态 |
|------|------|------|
| `dp` | DeePMD-kit + LAMMPS + TF/JAX/PyTorch | 可用 |
| `dpgen` | 自动数据生成 | 规划中 |
| 更多 | 采样 / 蒸馏 / … | 规划中 |

目标：**一个 `dpack` 装整个 DeepModeling 生态**（`dpack install dpgen`、`dpack upgrade dp` 等逐步支持）。

### 5 · 装完能用什么

| 组件 | 用途 |
|------|------|
| `dp` | 训练 / 冻结 / 测试神经网络势函数 |
| `lmp` | LAMMPS 分子动力学推理 |
| `dp_ipi` | i-PI 接口 |
| `mpirun` / `horovod` | 多节点并行训练 |
| Python `deepmd` / `dpdata` / `pylammps` | 脚本化调用 |

### 6 · 环境要求

| 条件 | 说明 |
|------|------|
| 操作系统 | Linux x86_64 |
| 联网 | 在线安装需要；离线 `--file` 模式不需要 |
| 权限 | 无需 root（装到用户目录） |
| GLIBC | ≥ 2.17 |
| GPU 版 | 需兼容的 NVIDIA 驱动（CUDA 12.x ~ 13.x） |

### 它怎么工作（选读）

```
deepmd 出新版
  → nightly CI 自动构建各变体离线包
      → 安装包(.sh)上传到 GitHub Release
      → manifest.json 提交到仓库(记录每个包的下载地址 + sha256)
  → dpack 读 manifest,按你的机器选变体 → 下载 → 校验 sha256 → 安装
    (或你手动下载安装包 → --file 离线安装)
```

科学计算集群通常**断网**，`conda install` / `pip install` 用不了。dpack 把 deepmd-kit +
LAMMPS + TF/JAX/PyTorch + MPI + 全部依赖打包成单个自包含文件——U 盘拷过去一行命令就装好，
无需联网、无需 root、无需手动设 CUDA_HOME。

---

> 维护者信息（构建/发布内幕、三种构建模式、nightly 流水线）见
> [references/verification-log.md](references/verification-log.md)。

### License

LGPL-3.0-or-later

---

## English Version

### 1 · Install dpack

Installs to your user directory, **no root needed**:

```bash
curl -fsSL https://raw.githubusercontent.com/Isaiah-WU/deepmd-dpack/main/install.sh | bash
```

If `dpack` isn't found, run `export PATH="$HOME/.local/bin:$PATH"` or open a new shell.

### 2 · Install tools with dpack

```bash
# Online: auto-detect GPU/CUDA, download + install the right build
dpack install dp

# Air-gapped (HPC): copy the offline package over, then point at the local file
dpack install dp --file ./deepmd-kit-3.2.0b0-20260624-a1b2c3d-cuda129-Linux-x86_64.sh

# Activate as printed, then:
source <prefix>/bin/activate <prefix>
dp --version
```

> GPU users install just one package: it covers the entire **CUDA 12.x ~ 13.x driver line** —
> no version-matching ([NVIDIA backward compatibility](https://docs.nvidia.com/deploy/cuda-compatibility/)).

### 3 · Commands

| Command | What it does |
|---------|--------------|
| `dpack install dp` | Online install: auto-pick variant → download → install |
| `dpack install dp --file <pkg.sh>` | Offline install from a local package |
| `dpack install dp --prefix <dir>` | Install to a specific directory |
| `dpack list` | List installed tools |

#### Offline install & split packages

A GPU package is large (~6 GB) and exceeds GitHub's 2 GB per-file limit, so it ships as 3 parts:
`...sh.0`, `...sh.1`, `...sh.2`. **You don't merge them by hand — point `--file` at the base name
(without `.0`) and dpack reassembles the parts in that directory before installing.**

```bash
# Case 1: a single complete .sh (CPU package, not split) — point at it directly
dpack install dp --file ./deepmd-kit-3.2.0b0-20260624-8f40cf6-cpu-Linux-x86_64.sh

# Case 2: a split package (GPU) — put the 3 parts in one directory:
#   deepmd-kit-...-cuda129-Linux-x86_64.sh.0 / .sh.1 / .sh.2
# then point --file at the BASE name (no .0); dpack cats them and installs:
dpack install dp --file ./deepmd-kit-3.2.0b0-20260624-8f40cf6-cuda129-Linux-x86_64.sh
#                              ↑ note: ends in .sh, not .sh.0
```

> HPC flow: download the 3 parts from the [Release](https://github.com/Isaiah-WU/deepmd-dpack/releases)
> on a networked machine → copy them into one directory on the air-gapped machine → run the command
> above (no network, no root). Or merge manually: `cat *.sh.0 *.sh.1 *.sh.2 > full.sh && bash full.sh -b -p /opt/deepmd`.

### 4 · Supported Tools

| Tool | Description | Status |
|------|-------------|--------|
| `dp` | DeePMD-kit + LAMMPS + TF/JAX/PyTorch | available |
| `dpgen` | Automated data generation | planned |
| more | sampling / distillation / … | planned |

Goal: **one `dpack` for the whole DeepModeling ecosystem** (`dpack install dpgen`, `dpack upgrade dp`, …).

### 5 · What You Get

| Component | Purpose |
|-----------|---------|
| `dp` | train / freeze / test neural-network potentials |
| `lmp` | LAMMPS molecular dynamics inference |
| `dp_ipi` | i-PI interface |
| `mpirun` / `horovod` | multi-node parallel training |
| Python `deepmd` / `dpdata` / `pylammps` | scripting |

### 6 · Requirements

| Requirement | Detail |
|-------------|--------|
| OS | Linux x86_64 |
| Network | needed for online install; not for offline `--file` |
| Privileges | none (installs to user dir) |
| GLIBC | ≥ 2.17 |
| GPU variant | compatible NVIDIA driver (CUDA 12.x ~ 13.x) |

### How It Works (optional)

```
a new deepmd release
  → nightly CI builds each variant
      → installers (.sh) are uploaded to a GitHub Release
      → manifest.json is committed to the repo (each package's URL + sha256)
  → dpack reads the manifest, auto-picks the build for your machine → download → verify sha256 → install
    (or download an installer yourself → install with --file)
```

HPC clusters are usually disconnected — `conda install` / `pip install` don't work. dpack packs
deepmd-kit + LAMMPS + TF/JAX/PyTorch + MPI + every dependency into one self-extracting archive:
copy it over a USB stick and one command installs it. No network, no root, no manual CUDA_HOME.

---

> Maintainers: build/release internals, the three build modes, and the nightly pipeline are
> documented in [references/verification-log.md](references/verification-log.md).

### License

LGPL-3.0-or-later
