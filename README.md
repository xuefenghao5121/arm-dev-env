# ARM Dev Environment

x86 主机上搭建 ARM 编译/测试环境，基于 QEMU user-mode + Docker。

## 原理

```
x86 Host
  └── Docker (binfmt_misc registered)
        └── ARM64/ARM32 Ubuntu Container (via QEMU user-static)
              └── Native ARM toolchain (gcc, cmake, python3...)
```

QEMU user-mode 在内核 binfmt 层拦截 ARM 二进制，转译执行。对容器内程序来说，它跑在"原生"ARM 环境里，文件系统、库、工具链全是 ARM 版本。性能约为原生 60-80%（计算密集），IO 密集型接近原生。

## 快速开始

```bash
cd ~/arm-dev-env
chmod +x setup.sh

# 一键搭建 aarch64 环境（推荐，鲲鹏 920/930 兼容）
./setup.sh aarch64

# 进入容器
docker exec -it arm-dev-aarch64 /bin/bash

# 在容器内验证
uname -m          # 应输出 aarch64
gcc -v            # ARM gcc
```

## 命令参考

| 命令 | 说明 |
|------|------|
| `./setup.sh aarch64` | 一键搭建 ARM64 环境 |
| `./setup.sh armhf` | 搭建 ARM32 hard-float 环境 |
| `./setup.sh setup` | 仅安装 QEMU + 注册 binfmt |
| `./setup.sh build` | 重建 Docker 镜像 |
| `./setup.sh run` | 启动容器 |
| `./setup.sh exec <cmd>` | 在容器内执行命令 |
| `./setup.sh status` | 查看环境状态 |
| `./setup.sh clean` | 清理容器和镜像 |

## 挂载目录

| 宿主机路径 | 容器路径 | 说明 |
|-----------|---------|------|
| `~/arm-dev-env/workspace` | `/workspace` | 工作目录，持久化 |
| `~/arm-dev-env/examples` | `/examples` | 示例代码（只读） |

## 测试编译

```bash
# 在容器内
cd /examples
mkdir build && cd build
cmake ..
make
./hello_arm
```

## 性能参考

QEMU user-mode 转译开销：
- **计算密集**: ~60-80% 原生速度（鲲鹏对比）
- **编译构建**: ~50-70%（大量小进程，syscall 转译开销大）
- **IO 密集**: ~85-95%（文件操作走宿主内核，几乎无转译）

如果需要更高性能，考虑：
1. **ARM 云主机**（阿里云/华为云鲲鹏实例）
2. **Apple Silicon Mac**（原生 ARM）
3. **Raspberry Pi 4/5**（低成本物理 ARM 环境）

## 系统要求

- Linux x86_64（Ubuntu 20.04+ / Fedora 35+ / Arch）
- Docker 20.10+
- ~3GB 磁盘空间（ARM Ubuntu 镜像 + 工具链）
