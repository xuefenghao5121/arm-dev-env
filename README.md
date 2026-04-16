# ARM Dev Environment

x86 主机上搭建 ARM 编译/测试环境，基于 QEMU user-mode + Docker。支持多种 ARM 指令集子版本和 CPU 特性开关。

## 原理

```
x86 Host
  └── Docker (binfmt_misc registered)
        └── ARM Container (via QEMU user-static)
              └── Native ARM toolchain (gcc, cmake, python3...)
              └── QEMU_CPU=neoverse-n1  ← 指定模拟的 CPU 型号
              └── TARGET_MARCH=armv8.2-a+sve  ← 编译目标 ISA
```

QEMU user-mode 在内核 binfmt 层拦截 ARM 二进制，转译执行。对容器内程序来说，它跑在"原生"ARM 环境里，文件系统、库、工具链全是 ARM 版本。通过 `QEMU_CPU` 控制模拟的 CPU 型号，`TARGET_MARCH` 控制编译目标指令集。

## Profile 一览

| Profile | QEMU CPU | GCC -march | 说明 |
|---------|----------|------------|------|
| `aarch64` | cortex-a57 | armv8-a | ARMv8.0 基线（默认） |
| `armv8.0` | cortex-a53 | armv8-a | ARMv8.0 最小子集 |
| `armv8.2` | neoverse-n1 | armv8.2-a | 鲲鹏 920 同级 |
| `armv8.4` | neoverse-v1 | armv8.4-a | 鲲鹏 930 目标级 |
| `armv9.0` | neoverse-v2 | armv9-a | ARMv9 + SVE2 |
| `thunderx2` | thunderx2t99 | armv8.1-a | Cavium ThunderX2 |
| `armhf` | cortex-a7 | armv7-a | ARM32 hard-float |
| `armv7` | cortex-a15 | armv7-a | ARM32 通用 |

## 特性开关

通过 `--feature` 追加 ISA 扩展到编译目标：

| 特性 | GCC 后缀 | 说明 |
|------|---------|------|
| `sve` | +sve | 可伸缩向量扩展 |
| `sve2` | +sve2 | SVE 第二代（需 armv9.0） |
| `lse` | +lse | 大系统扩展（原子指令） |
| `crypto` | +crypto | AES/SHA 硬件加速 |
| `rcpc` | +rcpc | LDAPR 弱有序加载 |

## 快速开始

```bash
cd ~/arm-dev-env
chmod +x setup.sh

# ARMv8.0 默认环境
./setup.sh aarch64

# 鲲鹏 920 环境 + SVE + 原子指令
./setup.sh armv8.2 --feature sve,lse

# 鲲鹏 930 目标环境
./setup.sh armv8.4

# ARMv9 + SVE2
./setup.sh armv9.0 --feature sve2
```

进入容器：
```bash
docker exec -it arm-dev-armv8.2 /bin/bash

# 验证环境
uname -m              # aarch64
echo $TARGET_MARCH    # armv8.2-a+sve
echo $TARGET_CPU      # neoverse-n1
echo $QEMU_CPU        # neoverse-n1
```

## 命令参考

| 命令 | 说明 |
|------|------|
| `./setup.sh <profile>` | 一键搭建（安装 + 构建 + 运行） |
| `./setup.sh <profile> --feature sve,lse` | 带特性开关搭建 |
| `./setup.sh setup` | 仅安装 QEMU + 注册 binfmt |
| `./setup.sh <profile> build` | 重建 Docker 镜像 |
| `./setup.sh <profile> run` | 启动容器 |
| `./setup.sh <profile> exec <cmd>` | 在容器内执行命令 |
| `./setup.sh status` | 查看所有环境状态 |
| `./setup.sh <profile> clean` | 清理容器和镜像 |

## 测试编译

```bash
# 在容器内 — 使用环境变量自动适配
cd /examples
mkdir build && cd build
cmake -DCMAKE_C_FLAGS="-march=$TARGET_MARCH" ..
make
./hello_arm

# 或直接用 gcc
gcc -march=$TARGET_MARCH -o /tmp/test /examples/hello_arm.c
/tmp/test
```

`hello_arm` 会输出当前 ISA 特性检测结果（SVE/LSE/Crypto/RCPC 等）。

## 性能参考

QEMU user-mode 转译开销：
- **计算密集**: ~60-80% 原生速度
- **编译构建**: ~50-70%（syscall 转译开销大）
- **IO 密集**: ~85-95%

**注意**：QEMU 模拟的 PMU 事件不可用于性能剖析，真机 perf 采集仍需物理 ARM 环境。

## 系统要求

- Linux x86_64（Ubuntu 20.04+ / Fedora 35+ / Arch）
- Docker 20.10+
- QEMU user-static 7.0+（`QEMU_CPU` 环境变量支持）
- ~3GB 磁盘空间（每个 profile 约 500MB-1GB）
