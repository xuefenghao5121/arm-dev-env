#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# ARM Development Environment Setup for x86 Host
# Uses QEMU user-mode emulation + Docker for native ARM
# compilation and testing with fine-grained ISA control.
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ---- Architecture Profile Definitions ----
# Each profile maps to: qemu_cpu|gcc_march|docker_base|desc

declare -A PROFILES=(
    [aarch64]="cortex-a57|armv8-a|arm64v8/ubuntu:22.04|ARMv8.0 baseline (default)"
    [armv8.0]="cortex-a53|armv8-a|arm64v8/ubuntu:22.04|ARMv8.0 minimal"
    [armv8.2]="neoverse-n1|armv8.2-a|arm64v8/ubuntu:22.04|ARMv8.2 (Kunpeng 920 class)"
    [armv8.4]="neoverse-v1|armv8.4-a|arm64v8/ubuntu:22.04|ARMv8.4 (Kunpeng 930 target)"
    [armv9.0]="neoverse-v2|armv9-a|arm64v8/ubuntu:24.04|ARMv9.0 with SVE2"
    [thunderx2]="thunderx2t99|armv8.1-a|arm64v8/ubuntu:22.04|Cavium ThunderX2 server"
    [armhf]="cortex-a7|armv7-a|arm32v7/ubuntu:22.04|ARM32 hard-float"
    [armv7]="cortex-a15|armv7-a|arm32v7/debian:bullseye|ARM32 generic"
)

# ---- Feature Definitions ----
# Feature name → GCC march suffix

declare -A FEATURES=(
    [sve]="+sve"
    [sve2]="+sve2"
    [lse]="+lse"
    [crypto]="+crypto"
    [rcpc]="+rcpc"
)

# ---- Parse Arguments ----

PROFILE=""
EXTRA_FEATURES=""

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "${1}" in
            --feature|-f)
                EXTRA_FEATURES="${2}"
                shift 2
                ;;
            --feature=*)
                EXTRA_FEATURES="${1#*=}"
                shift
                ;;
            -h|--help|help)
                usage
                exit 0
                ;;
            setup|build|run|exec|status|clean)
                COMMAND="${1}"
                shift
                ;;
            *)
                if [[ -n "${PROFILE}" ]]; then
                    echo "[ERROR] Unexpected argument: ${1}"
                    usage
                    exit 1
                fi
                PROFILE="${1}"
                shift
                ;;
        esac
    done

    PROFILE="${PROFILE:-aarch64}"

    if [[ ! -v "PROFILES[${PROFILE}]" ]]; then
        echo "[ERROR] Unknown profile: ${PROFILE}"
        echo "Available: ${!PROFILES[*]}"
        exit 1
    fi
}

# ---- Profile Accessors ----

profile_field() {
    local idx="${1}"
    echo "${PROFILES[${PROFILE}]}" | cut -d'|' -f"${idx}"
}

qemu_cpu()    { profile_field 1; }
gcc_march()   { profile_field 2; }
docker_base() { profile_field 3; }
profile_desc() { profile_field 4; }

build_march_flags() {
    local base_march
    base_march="$(gcc_march)"

    if [[ -z "${EXTRA_FEATURES}" ]]; then
        echo "${base_march}"
        return
    fi

    local result="${base_march}"
    IFS=',' read -ra feats <<< "${EXTRA_FEATURES}"
    for feat in "${feats[@]}"; do
        feat="${feat## }"  # trim leading space
        feat="${feat%% }"  # trim trailing space
        if [[ -v "FEATURES[${feat}]" ]]; then
            result+="${FEATURES[${feat}]}"
        else
            echo "[WARN] Unknown feature: ${feat} (skipped)" >&2
        fi
    done
    echo "${result}"
}

IMAGE_NAME="arm-dev-${PROFILE}"
CONTAINER_NAME="arm-dev-${PROFILE}"

# ---- Usage ----

usage() {
    cat <<'EOF'
Usage: setup.sh [PROFILE] [COMMAND] [--feature feat1,feat2]

Profiles:
  aarch64    ARMv8.0 baseline (default)
  armv8.0    ARMv8.0 minimal
  armv8.2    ARMv8.2 (Kunpeng 920 class)
  armv8.4    ARMv8.4 (Kunpeng 930 target)
  armv9.0    ARMv9.0 with SVE2
  thunderx2  Cavium ThunderX2 server
  armhf      ARM32 hard-float
  armv7      ARM32 generic

Features (--feature / -f):
  sve       Scalable Vector Extension
  sve2      SVE second generation (armv9.0 only)
  lse       Large System Extensions (atomics)
  crypto    AES/SHA hardware acceleration
  rcpc      Weakly-ordered load-acquire (LDAPR)

Commands:
  setup     One-time setup: install QEMU + register binfmt
  build     Build ARM Docker image
  run       Run ARM container interactively
  exec      Execute command in running container
  status    Check environment status
  clean     Remove containers and images

Examples:
  setup.sh aarch64                    # ARMv8.0 default
  setup.sh armv8.2 --feature sve,lse  # Kunpeng 920 + SVE + atomics
  setup.sh armv8.4                    # Kunpeng 930 target
  setup.sh armv9.0 --feature sve2     # ARMv9 with SVE2
EOF
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

build_image() {
    local df_path="${SCRIPT_DIR}/Dockerfile.${PROFILE}"
    local base_image
    base_image="$(docker_base)"
    local march_flags
    march_flags="$(build_march_flags)"
    local cpu
    cpu="$(qemu_cpu)"

    cat > "${df_path}" <<EOF
FROM ${base_image}

ENV DEBIAN_FRONTEND=noninteractive
ENV LANG=C.UTF-8

# Target ISA configuration (set by setup.sh)
ENV TARGET_MARCH="${march_flags}"
ENV TARGET_CPU="${cpu}"
ENV QEMU_CPU="${cpu}"

# Core build tools
RUN apt-get update && apt-get install -y --no-install-recommends \\
    build-essential \\
    gcc \\
    g++ \\
    cmake \\
    make \\
    autoconf \\
    automake \\
    libtool \\
    pkg-config \\
    git \\
    wget \\
    curl \\
    ca-certificates \\
    python3 \\
    python3-pip \\
    python3-venv \\
    gdb \\
    valgrind \\
    && rm -rf /var/lib/apt/lists/*

# Python tooling
RUN python3 -m pip install --no-cache-dir --upgrade pip && \\
    python3 -m pip install --no-cache-dir pydantic click pytest

# Entrypoint sets QEMU_CPU for user-mode emulation
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]
WORKDIR /workspace
EOF

    # Write entrypoint script
    cat > "${SCRIPT_DIR}/entrypoint.sh" <<'ENTRYPOINT'
#!/bin/bash
# Set QEMU_CPU if supported (QEMU 8.0+ reads this env var)
export QEMU_CPU="${QEMU_CPU:-}"
exec "$@"
ENTRYPOINT
    chmod +x "${SCRIPT_DIR}/entrypoint.sh"

    echo "[BUILD] Building ${IMAGE_NAME} image..."
    echo "  Profile:    ${PROFILE} ($(profile_desc))"
    echo "  QEMU CPU:   ${cpu}"
    echo "  GCC march:  ${march_flags}"
    echo "  Base image: ${base_image}"
    docker build -t "${IMAGE_NAME}" -f "${df_path}" "${SCRIPT_DIR}"
    echo "[OK] Image built: ${IMAGE_NAME}"
}

# ---- Run ----

run_container() {
    IMAGE_NAME="arm-dev-${PROFILE}"
    CONTAINER_NAME="arm-dev-${PROFILE}"

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
            -e QEMU_CPU="$(qemu_cpu)" \
            -e TARGET_MARCH="$(build_march_flags)" \
            -e TARGET_CPU="$(qemu_cpu)" \
            -v "${SCRIPT_DIR}/workspace:/workspace" \
            -v "${SCRIPT_DIR}/examples:/examples:ro" \
            "${IMAGE_NAME}" \
            /bin/bash
        echo "[OK] Container started: ${CONTAINER_NAME}"
    fi
    echo ""
    echo "Profile:       ${PROFILE} ($(profile_desc))"
    echo "QEMU CPU:      $(qemu_cpu)"
    echo "GCC -march:    $(build_march_flags)"
    echo ""
    echo "Connect with:  docker exec -it ${CONTAINER_NAME} /bin/bash"
    echo "Quick test:    docker exec ${CONTAINER_NAME} uname -m"
}

exec_in_container() {
    local cmd="${*:-/bin/bash}"
    CONTAINER_NAME="arm-dev-${PROFILE}"
    if docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
        docker exec -it "${CONTAINER_NAME}" ${cmd}
    else
        echo "[ERROR] Container ${CONTAINER_NAME} not running. Run './setup.sh ${PROFILE} run' first."
        exit 1
    fi
}

# ---- Status ----

show_status() {
    echo "=== ARM Dev Environment Status ==="
    echo ""
    echo "Profile:    ${PROFILE} ($(profile_desc))"
    echo "QEMU CPU:   $(qemu_cpu)"
    echo "GCC march:  $(build_march_flags)"
    echo ""

    echo "--- QEMU ---"
    if check_qemu 2>/dev/null; then
        :
    else
        echo "  Not installed"
    fi

    echo ""
    echo "--- binfmt ---"
    for binfmt in qemu-aarch64 qemu-arm qemu-aarch64_be; do
        if [ -f "/proc/sys/fs/binfmt_misc/${binfmt}" ]; then
            echo "  ${binfmt}: registered"
        fi
    done

    echo ""
    echo "--- Docker Images ---"
    for p in "${!PROFILES[@]}"; do
        local img="arm-dev-${p}"
        if docker images --format '{{.Repository}}' | grep -q "^${img}$"; then
            local size
            size=$(docker images --format '{{.Size}}' "${img}" 2>/dev/null | head -1)
            echo "  ${img}: ${size}"
        fi
    done

    echo ""
    echo "--- Containers ---"
    for p in "${!PROFILES[@]}"; do
        local ctr="arm-dev-${p}"
        if docker ps --format '{{.Names}}' | grep -q "^${ctr}$"; then
            echo "  ${ctr}: RUNNING"
        elif docker ps -a --format '{{.Names}}' | grep -q "^${ctr}$"; then
            echo "  ${ctr}: STOPPED"
        fi
    done
}

# ---- Clean ----

clean() {
    echo "[CLEAN] Removing containers and images for profile: ${PROFILE}..."
    CONTAINER_NAME="arm-dev-${PROFILE}"
    IMAGE_NAME="arm-dev-${PROFILE}"
    docker rm -f "${CONTAINER_NAME}" 2>/dev/null || true
    docker rmi "${IMAGE_NAME}" 2>/dev/null || true
    echo "[OK] Cleaned"
}

# ---- Main ----

COMMAND=""

parse_args "$@"

# Resolve image/container names after profile is set
IMAGE_NAME="arm-dev-${PROFILE}"
CONTAINER_NAME="arm-dev-${PROFILE}"

if [[ -n "${COMMAND}" ]]; then
    case "${COMMAND}" in
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
            exec_in_container "${@}"
            ;;
        status)
            show_status
            ;;
        clean)
            clean
            ;;
    esac
else
    # No command: full setup (install + build + run)
    check_docker
    if ! check_qemu; then
        install_qemu
    fi
    register_binfmt_docker
    build_image
    run_container
fi
