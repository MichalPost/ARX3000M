#!/bin/bash
# ============================================================
# ARX3000M OpenWrt 固件编译环境一键搭建脚本
# 目标设备: RAX3000M (MT7981B / Filogic 820)
# 适用于: Ubuntu 20.04/22.04/24.04 (WSL2 也可用)
# ============================================================

set -e

# 与 CI .github/workflows/build.yml 中 OPENWRT_BRANCH 保持一致
OPENWRT_BRANCH="${OPENWRT_BRANCH:-main}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}============================================${NC}"
echo -e "${BLUE}  ARX3000M OpenWrt 编译环境搭建工具${NC}"
echo -e "${BLUE}  目标平台: MediaTek MT7981 (filogic)${NC}"
echo -e "${BLUE}============================================${NC}"

# ---- 检测系统 ----
detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
        VER=$VERSION_ID
        echo -e "${GREEN}[✓] 检测到系统: $OS $VER${NC}"
    else
        echo -e "${RED}[✗] 无法检测操作系统${NC}"
        exit 1
    fi
}

# ---- 安装编译依赖 ----
install_dependencies() {
    echo -e "\n${YELLOW}[→] 安装编译依赖...${NC}"

    if [ "$OS" = "ubuntu" ] || [ "$OS" = "debian" ]; then
        sudo apt-get update
        sudo apt-get install -y \
            build-essential ccache ecj fastjar file g++ gcc \
            default-jdk git libncurses5-dev libssl-dev \
            python3-distutils python3-pyelftools python3-setuptools \
            rsync subversion swig unzip wget zlib1g-dev \
            curl python3-pip python3-full flex bison gettext \
            libelf-dev autoconf automake libtool binutils \
            patch bash-completion coreutils quilt \
            re2c xsltproc zstd libzstd-dev \
            python3-yaml python3-werkzeug python3-requests \
            upx-ucl uglifyjs htmlminifier
    else
        echo -e "${RED}[✗] 不支持此系统: $OS${NC}"
        exit 1
    fi

    echo -e "${GREEN}[✓] 编译依赖安装完成${NC}"
}

# ---- 配置 Git ----
setup_git() {
    echo -e "\n${YELLOW}[→] 配置 Git...${NC}"
    # [M11] 仅在 CI 环境（无交互用户）时才设置全局 Git 配置，
    # 本地开发环境跳过，避免覆盖开发者个人配置
    if [ -n "$CI" ] || [ -n "$GITHUB_ACTIONS" ]; then
        git config --global user.name "ARX3000M Builder"
        git config --global user.email "builder@arx3000m.local"
        echo -e "${GREEN}[✓] Git 配置完成（CI 环境）${NC}"
    else
        echo -e "${YELLOW}[!] 本地环境跳过全局 Git 配置，使用已有配置${NC}"
    fi
}

# ---- 创建工作目录 ----
create_workspace() {
    local WORK_DIR="${1:-$HOME/openwrt-build}"
    echo -e "\n${YELLOW}[→] 创建工作目录: $WORK_DIR${NC}"
    mkdir -p "$WORK_DIR"
    cd "$WORK_DIR"
    export ARX3000M_SETUP_WORKDIR="$(pwd)"
    echo -e "${GREEN}[✓] 工作目录就绪${NC}"
}

# ---- 克隆 OpenWrt 源码 ----
clone_openwrt() {
    local WORK_DIR="${ARX3000M_SETUP_WORKDIR:?ARX3000M_SETUP_WORKDIR unset}"
    cd "$WORK_DIR"

    if [ -d "openwrt" ]; then
        echo -e "${YELLOW}[!] openwrt 目录已存在，同步分支 ${OPENWRT_BRANCH}...${NC}"
        cd openwrt
        if ! git fetch origin "${OPENWRT_BRANCH}" --depth 1; then
            echo -e "${RED}[✗] git fetch origin ${OPENWRT_BRANCH} 失败${NC}" >&2
            exit 1
        fi
        if ! git checkout "${OPENWRT_BRANCH}"; then
            echo -e "${RED}[✗] git checkout ${OPENWRT_BRANCH} 失败${NC}" >&2
            exit 1
        fi
        if ! git pull --ff-only origin "${OPENWRT_BRANCH}"; then
            echo -e "${RED}[✗] git pull --ff-only origin ${OPENWRT_BRANCH} 失败（请处理本地提交或改用干净克隆）${NC}" >&2
            exit 1
        fi
    else
        echo -e "\n${YELLOW}[→] 克隆 OpenWrt 官方源码 (${OPENWRT_BRANCH})...${NC}"
        git clone https://github.com/openwrt/openwrt.git --depth 1 --branch "${OPENWRT_BRANCH}"
        cd openwrt
    fi

    local cur_branch
    cur_branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
    if [ "$cur_branch" != "$OPENWRT_BRANCH" ]; then
        echo -e "${RED}[✗] 当前检出不在分支 ${OPENWRT_BRANCH}（当前: ${cur_branch:-unknown}）${NC}" >&2
        exit 1
    fi

    echo -e "${GREEN}[✓] OpenWrt 源码就绪 (版本: $(git describe --tags 2>/dev/null || echo 'latest'))${NC}"
}

# ---- 更新 feeds 并安装软件包 ----
update_feeds() {
    local PROJECT_ROOT="${1:-}"
    echo -e "\n${YELLOW}[→] 更新 feeds...${NC}"
    if [ -n "$PROJECT_ROOT" ] && [ -f "$PROJECT_ROOT/scripts/ensure-extra-feeds.sh" ]; then
        bash "$PROJECT_ROOT/scripts/ensure-extra-feeds.sh" "$(pwd)"
    fi
    ./scripts/feeds update -a
    echo -e "${YELLOW}[→] 安装 feeds 软件包（与 CI build.yml 一致）...${NC}"
    ./scripts/feeds install -a -f -p packages
    ./scripts/feeds install -a -f -p luci
    ./scripts/feeds install -a -f -p routing
    ./scripts/feeds install -a -f -p telephony || true
    ./scripts/feeds install -a -f -p video || true
    ./scripts/feeds install -a -f -p openclash
    if [ -n "$PROJECT_ROOT" ] && [ -f "$PROJECT_ROOT/scripts/patch-packages-feed.sh" ]; then
        bash "$PROJECT_ROOT/scripts/patch-packages-feed.sh" "$(pwd)"
    fi
    echo -e "${GREEN}[✓] Feeds 更新安装完成${NC}"
}

# ---- 复制自定义包 ----
copy_custom_packages() {
    local PROJECT_ROOT="$1"
    if [ -z "$PROJECT_ROOT" ]; then
        echo -e "${YELLOW}[!] 未指定自定义包路径，跳过${NC}"
        return
    fi

    echo -e "\n${YELLOW}[→] 复制自定义 LuCI 包（与 build.sh copy 一致）...${NC}"

    mkdir -p package/custom

    if [ -d "$PROJECT_ROOT/packages" ]; then
        for pkg in "$PROJECT_ROOT/packages/"*/; do
            if [ -d "$pkg" ]; then
                pkg_name=$(basename "$pkg")
                rm -rf "package/custom/$pkg_name"
                cp -r "$pkg" "package/custom/"
                echo -e "${GREEN}  └─ $pkg_name${NC}"
            fi
        done
    fi

    if [ -d "$PROJECT_ROOT/theme" ]; then
        rm -rf package/custom/luci-theme-arx3000m
        cp -r "$PROJECT_ROOT/theme" package/custom/luci-theme-arx3000m
        echo -e "${GREEN}  └─ luci-theme-arx3000m${NC}"
    fi

    echo -e "${GREEN}[✓] 自定义包复制完成${NC}"
}

# ---- 加载预配置 ----
load_config() {
    local PROJECT_ROOT="$1"
    local CONFIG_FILE="$PROJECT_ROOT/config/rax3000m.config"

    if [ -f "$CONFIG_FILE" ]; then
        echo -e "\n${YELLOW}[→] 加载 RAX3000M 预配置...${NC}"
        cp "$CONFIG_FILE" .config
        echo -e "${YELLOW}[→] 运行 defconfig...${NC}"
        make defconfig
        echo -e "${GREEN}[✓] 预配置已加载${NC}"
    else
        echo -e "${YELLOW}[!] 未找到预配置文件，需要手动执行 make menuconfig${NC}"
    fi
}

# ---- 主流程 ----
main() {
    local PROJECT_ROOT="$1"
    local WORK_DIR="${2:-$HOME/openwrt-build}"

    detect_os
    install_dependencies
    setup_git
    create_workspace "$WORK_DIR"
    clone_openwrt
    if [ -f "$PROJECT_ROOT/scripts/apply-openwrt-patches.sh" ]; then
        bash "$PROJECT_ROOT/scripts/apply-openwrt-patches.sh" "$PROJECT_ROOT" "${ARX3000M_SETUP_WORKDIR}/openwrt"
    fi
    copy_custom_packages "$PROJECT_ROOT"
    update_feeds "$PROJECT_ROOT"
    load_config "$PROJECT_ROOT"

    echo -e "\n${BLUE}============================================${NC}"
    echo -e "${GREEN}  ✅ 编译环境搭建完成！${NC}"
    echo -e "${BLUE}============================================${NC}"
    echo -e ""
    echo -e " ${YELLOW}后续步骤:${NC}"
    echo -e "  1. cd ${ARX3000M_SETUP_WORKDIR}/openwrt"
    echo -e "  2. make menuconfig          # 如需调整配置"
    echo -e "  3. make download -j8        # 下载源码"
    echo -e "  4. make -j$(nproc) V=s      # 开始编译（V=s 显示详细日志）"
    echo -e ""
    echo -e " ${YELLOW}编译产物位置:${NC}"
    echo -e "  bin/targets/mediatek/filogic/"
    echo -e ""
    echo -e " ${YELLOW}常用命令:${NC}"
    echo -e "  make clean                  # 清理编译产物（保留配置）"
    echo -e "  make defconfig              # 检查配置完整性"
    echo -e "  ./scripts/diffconfig.sh     # 导出精简配置差异"
    echo -e ""
}

main "$@"
