#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# ARM Development Environment Setup for x86 Host
# Uses QEMU user-mode emulation + Docker for native ARM
# compilation and testing with good performance.
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ARCH="${1:-aarch64}"
IMAGE_NAME="arm-dev-${ARCH}"

# Supported architectures
SUPPORTED_ARCHS=("aarch64" "armhf" "armv7")

usage() {
    echo "Usage: $0 [aarch64|armhf|armv7]"
    echo ""
    echo "  aarch64  - ARM 64-bit (default, recommended for Kunpeng 920/930)"
    echo "  armhf    - ARM 32-bit hard-float"
    echo "  armv7    - ARM 32-bit generic"
    echo ""
    echo "Commands:"
    echo "  $0 setup      - One-time setup: install QEMU + register binfmt"
    echo "  $0 build      - Build ARM Docker image"
    echo "  $0 run        - Run ARM container interactively"
    echo "  $0 exec       - Execute command in running container"
    echo "  $0 status     - Check environment status"
    echo "  $0 clean      - Remove containers and images"
}

# ---- Prerequisites Check ----

check_docker() {
    if ! command -v docker &>/dev/null; then
        echo "[ERROR] Docker not found. Install: https://docs.docker.com/engine/install/"
        exit 1
    fi
    if ! docker info &>/dev/null 2>&1; then
        echo "[ERROR] Docker daemon not running. Start with: sudo systemctl start docker"
        exit 1
    fi
    echo "[OK] Docker available"
}

check_qemu() {
    if command -v qemu-aarch64-static &>/dev/null || \
       command -v qemu-arm-static &>/dev/null; then
        echo "[OK] QEMU user-static installed"
        return 0
    fi
    echo "[MISSING] QEMU user-static not found"
    return 1
}

install_qemu_ubuntu() {
    echo "[INSTALL] Installing qemu-user-static on Ubuntu/Debian..."
    sudo apt-get update
    sudo apt-get install -y qemu-user-static binfmt-support
    echo "[OK] QEMU installed and binfmt registered"
}

install_qemu_fedora() {
    echo "[INSTALL] Installing qemu-user-static on Fedora/RHEL..."
    sudo dnf install -y qemu-user-static
    sudo systemctl restart systemd-binfmt
    echo "[OK] QEMU installed and binfmt registered"
}

install_qemu_arch() {
    echo "[INSTALL] Installing qemu-user-static on Arch Linux..."
    sudo pacman -S --noconfirm qemu-user-static qemu-user-static-binfmt
    echo "[OK] QEMU installed and binfmt registered"
}

install_qemu() {
    if [ -f /etc/debian_version ]; then
        install_qemu_ubuntu
    elif [ -f /etc/fedora-release ]; then
        install_qemu_fedora
    elif [ -f /etc/arch-release ]; then
        install_qemu_arch
    else
        echo "[ERROR] Unsupported distro. Install qemu-user-static manually."
        echo "  Ubuntu/Debian: sudo apt install qemu-user-static binfmt-support"
        echo "  Fedora/RHEL:   sudo dnf install qemu-user-static"
        echo "  Arch:          sudo pacman -S qemu-user-static"
        exit 1
    fi
}

register_binfmt_docker() {
    echo "[SETUP] Registering QEMU binfmt via Docker..."
    docker run --rm --privileged multiarch/qemu-user-static --reset -p yes
    echo "[OK] binfmt registered — Docker can now run ARM containers"
}

# ---- Build ----

get_dockerfile() {
    case "${ARCH}" in
        aarch64)
            echo "FROM arm64v8/ubuntu:22.04"
            ;;
        armhf)
            echo "FROM arm32v7/ubuntu:22.04"
            ;;
        armv7)
            echo "FROM arm32v7/debian:bullseye"
            ;;
        *)
            echo "[ERROR] Unsupported arch: ${ARCH}"
            exit 1
            ;;
    esac
}

build_image() {
    local df_path="${SCRIPT_DIR}/Dockerfile.${ARCH}"
    cat > "${df_path}" <<'DOCKERFILE'
DOCKERFILE
    # Append arch-specific FROM
    echo "$(get_dockerfile)" > "${df_path}"
    cat >> "${df_path}" <<'DOCKERFILE'

ENV DEBIAN_FRONTEND=noninteractive
ENV LANG=C.UTF-8

# Core build tools
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    gcc \
    g++ \
    cmake \
    make \
    autoconf \
    automake \
    libtool \
    pkg-config \
    git \
    wget \
    curl \
    ca-certificates \
    python3 \
    python3-pip \
    python3-venv \
    gdb \
    valgrind \
    && rm -rf /var/lib/apt/lists/*

# Python tooling
RUN python3 -m pip install --no-cache-dir --upgrade pip && \
    python3 -m pip install --no-cache-dir pydantic click pytest

WORKDIR /workspace
DOCKERFILE

    echo "[BUILD] Building ${IMAGE_NAME} image..."
    docker build -t "${IMAGE_NAME}" -f "${df_path}" "${SCRIPT_DIR}"
    echo "[OK] Image built: ${IMAGE_NAME}"
}

# ---- Run ----

CONTAINER_NAME="arm-dev-${ARCH}"

run_container() {
    if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
        if docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
            echo "[OK] Container ${CONTAINER_NAME} already running"
        else
            echo "[START] Starting existing container ${CONTAINER_NAME}..."
            docker start "${CONTAINER_NAME}"
        fi
    else
        echo "[RUN] Creating new container ${CONTAINER_NAME}..."
        docker run -dit \
            --name "${CONTAINER_NAME}" \
            -v "${SCRIPT_DIR}/workspace:/workspace" \
            -v "${SCRIPT_DIR}/examples:/examples:ro" \
            "${IMAGE_NAME}" \
            /bin/bash
        echo "[OK] Container started: ${CONTAINER_NAME}"
    fi
    echo ""
    echo "Connect with:  docker exec -it ${CONTAINER_NAME} /bin/bash"
    echo "Quick test:    docker exec ${CONTAINER_NAME} uname -m"
}

exec_in_container() {
    local cmd="${*:-/bin/bash}"
    if docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
        docker exec -it "${CONTAINER_NAME}" ${cmd}
    else
        echo "[ERROR] Container ${CONTAINER_NAME} not running. Run '$0 run' first."
        exit 1
    fi
}

# ---- Status ----

show_status() {
    echo "=== ARM Dev Environment Status ==="
    echo ""
    echo "Architecture: ${ARCH}"
    echo ""

    echo "--- QEMU ---"
    if check_qemu 2>/dev/null; then
        :
    else
        echo "  Not installed"
    fi

    echo ""
    echo "--- binfmt ---"
    if [ -f /proc/sys/fs/binfmt_misc/qemu-aarch64 ]; then
        echo "  aarch64: registered"
    else
        echo "  aarch64: NOT registered"
    fi
    if [ -f /proc/sys/fs/binfmt_misc/qemu-arm ]; then
        echo "  arm:     registered"
    else
        echo "  arm:     NOT registered"
    fi

    echo ""
    echo "--- Docker Image ---"
    if docker images --format '{{.Repository}}' | grep -q "^${IMAGE_NAME}$"; then
        local size
        size=$(docker images --format '{{.Size}}' "${IMAGE_NAME}")
        echo "  ${IMAGE_NAME}: ${size}"
    else
        echo "  ${IMAGE_NAME}: NOT built"
    fi

    echo ""
    echo "--- Container ---"
    if docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
        echo "  ${CONTAINER_NAME}: RUNNING"
    elif docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
        echo "  ${CONTAINER_NAME}: STOPPED"
    else
        echo "  ${CONTAINER_NAME}: NOT CREATED"
    fi
}

# ---- Clean ----

clean() {
    echo "[CLEAN] Removing containers and images..."
    docker rm -f "${CONTAINER_NAME}" 2>/dev/null || true
    docker rmi "${IMAGE_NAME}" 2>/dev/null || true
    echo "[OK] Cleaned"
}

# ---- Main ----

COMMAND="${ARCH}"

if [[ " ${SUPPORTED_ARCHS[*]} " =~ " ${COMMAND} " ]]; then
    # Architecture specified as first arg, default to build+run
    check_docker
    if ! check_qemu; then
        install_qemu
    fi
    register_binfmt_docker
    build_image
    run_container
elif [ $# -eq 0 ]; then
    usage
else
    case "${1}" in
        setup)
            check_docker
            if ! check_qemu; then
                install_qemu
            fi
            register_binfmt_docker
            ;;
        build)
            check_docker
            build_image
            ;;
        run)
            check_docker
            run_container
            ;;
        exec)
            exec_in_container "${@:2}"
            ;;
        status)
            show_status
            ;;
        clean)
            clean
            ;;
        -h|--help|help)
            usage
            ;;
        *)
            echo "[ERROR] Unknown command: ${1}"
            usage
            exit 1
            ;;
    esac
fi
