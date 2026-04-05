#!/bin/bash
# ============================================================
# ARX3000M OpenWrt 固件编译脚本
# 目标: RAX3000M (MT7981B, 512MB RAM, WiFi6 AX3000)
# 平台: filogic (MediaTek Filogic 820/830)
# ============================================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OPENWRT_DIR="${OPENWRT_DIR:-$HOME/openwrt-build/openwrt}"
THREADS="${THREADS:-$(nproc)}"

usage() {
    echo -e "${CYAN}用法: $0 <命令> [选项]${NC}"
    echo -e ""
    echo -e " ${YELLOW}命令:${NC}"
    echo -e "   init       初始化编译环境（安装依赖+拉取源码）"
    echo -e "   feed       更新并安装 feeds"
    echo -e "   config     加载 RAX3000M 预配置"
    echo -e "   menuconfig 打开菜单配置界面"
    echo -e "   download   下载所有源码包"
    echo -e "   build      编译固件（完整流程）"
    echo -e "   quick      快速编译（跳过下载与 linux 全量清理，增量重编）"
    echo -e "   clean      清理编译产物"
    echo -e "   distclean  完全清理（含下载缓存）"
    echo -e "   diffconfig 导出精简配置差异"
    echo -e "   info       显示当前编译配置信息"
    echo -e "   copy       复制自定义包到 OpenWrt 目录"
    echo -e ""
    echo -e " ${YELLOW}环境变量:${NC}"
    echo -e "   OPENWRT_DIR   OpenWrt 源码目录 (默认: $HOME/openwrt-build/openwrt)"
    echo -e "   THREADS       编译线程数 (默认: CPU 核心数)"
    echo -e ""
    echo -e " ${YELLOW}示例:${NC}"
    echo -e "   $0 init                    # 首次初始化环境"
    echo -e "   $0 config && $0 build      # 加载配置后编译"
    echo -e "   THREADS=4 $0 build         # 使用 4 线程编译"
}

check_openwrt() {
    if [ ! -d "$OPENWRT_DIR" ]; then
        echo -e "${RED}[✗] OpenWrt 目录不存在: $OPENWRT_DIR${NC}"
        echo -e "${YELLOW}请先运行: $0 init${NC}"
        exit 1
    fi
}

apply_openwrt_patches() {
    if [ -f "$SCRIPT_DIR/scripts/apply-openwrt-patches.sh" ]; then
        bash "$SCRIPT_DIR/scripts/apply-openwrt-patches.sh" "$SCRIPT_DIR" "$OPENWRT_DIR"
    fi
}

cmd_init() {
    echo -e "${BLUE}[→] 运行环境初始化脚本...${NC}"
    if [ ! -f "$SCRIPT_DIR/setup-env.sh" ]; then
        echo -e "${RED}[✗] setup-env.sh 不存在: $SCRIPT_DIR/setup-env.sh${NC}"
        echo -e "${YELLOW}请参考 README 手动准备编译环境，或从项目仓库获取 setup-env.sh${NC}"
        exit 1
    fi
    bash "$SCRIPT_DIR/setup-env.sh" "$SCRIPT_DIR"
}

cmd_feed() {
    check_openwrt
    cd "$OPENWRT_DIR"
    if [ -f "$SCRIPT_DIR/scripts/ensure-extra-feeds.sh" ]; then
        bash "$SCRIPT_DIR/scripts/ensure-extra-feeds.sh" "$(pwd)"
    fi
    echo -e "${YELLOW}[→] 更新 feeds...${NC}"
    ./scripts/feeds update -a
    echo -e "${YELLOW}[→] 安装 feeds 软件包（与 CI build.yml 一致）...${NC}"
    ./scripts/feeds install -a -f -p packages
    ./scripts/feeds install -a -f -p luci
    ./scripts/feeds install -a -f -p routing
    ./scripts/feeds install -a -f -p telephony || true
    ./scripts/feeds install -a -f -p video || true
    ./scripts/feeds install -a -f -p openclash
    echo -e "${GREEN}[✓] Feeds 完成${NC}"
}

cmd_copy() {
    check_openwrt
    cd "$OPENWRT_DIR"

    echo -e "${YELLOW}[→] 复制自定义包...${NC}"
    mkdir -p package/custom

    if [ -d "$SCRIPT_DIR/packages" ]; then
        for pkg in "$SCRIPT_DIR/packages/"*/; do
            if [ -d "$pkg" ]; then
                pkg_name=$(basename "$pkg")
                rm -rf "package/custom/$pkg_name"
                cp -r "$pkg" "package/custom/"
                echo -e "${GREEN}  └─ $pkg_name${NC}"
            fi
        done
    fi

    if [ -d "$SCRIPT_DIR/theme" ]; then
        rm -rf "package/custom/luci-theme-arx3000m"
        cp -r "$SCRIPT_DIR/theme" "package/custom/luci-theme-arx3000m"
        echo -e "${GREEN}  └─ luci-theme-arx3000m${NC}"
    fi

    echo -e "${GREEN}[✓] 自定义包复制完成${NC}"
}

cmd_config() {
    check_openwrt
    apply_openwrt_patches
    cd "$OPENWRT_DIR"

    local CONFIG_FILE="$SCRIPT_DIR/config/rax3000m.config"
    if [ ! -f "$CONFIG_FILE" ]; then
        echo -e "${RED}[✗] 配置文件不存在: $CONFIG_FILE${NC}"
        exit 1
    fi

    cp "$CONFIG_FILE" .config
    echo -e "${YELLOW}[→] 运行 defconfig...${NC}"
    make defconfig
    echo -e "${GREEN}[✓] 配置已加载${NC}"
}

cmd_menuconfig() {
    check_openwrt
    cd "$OPENWRT_DIR"
    make menuconfig
}

cmd_download() {
    check_openwrt
    cd "$OPENWRT_DIR"
    echo -e "${YELLOW}[→] 下载源码包 ($THREADS 线程)...${NC}"
    make download -j"$THREADS"
    echo -e "${GREEN}[✓] 下载完成${NC}"
}

cmd_build() {
    check_openwrt
    apply_openwrt_patches
    cd "$OPENWRT_DIR"

    local START_TIME=$(date +%s)

    echo -e "${BLUE}============================================${NC}"
    echo -e "${BLUE}  开始编译 ARX3000M 固件${NC}"
    echo -e "${BLUE}  目标: MediaTek Filogic (MT7981)${NC}"
    echo -e "${BLUE}  线程数: $THREADS${NC}"
    echo -e "${BLUE}  时间: $(date '+%Y-%m-%d %H:%M:%S')${NC}"
    echo -e "${BLUE}============================================${NC}"

    # [M9] set -o pipefail + 显式判断，失败时打印提示（避免仅依赖 set -e 时无友好信息）
    set -o pipefail
    if ! make -j"$THREADS" V=s 2>&1 | tee "$SCRIPT_DIR/build.log"; then
        set +o pipefail
        echo -e "${RED}[✗] 编译失败，请查看: $SCRIPT_DIR/build.log${NC}"
        exit 1
    fi
    set +o pipefail

    local END_TIME=$(date +%s)
    local DURATION=$((END_TIME - START_TIME))
    local MINUTES=$((DURATION / 60))
    local SECONDS=$((DURATION % 60))

    echo -e "\n${BLUE}============================================${NC}"
    echo -e "${GREEN}  ✅ 编译完成！耗时: ${MINUTES}分${SECONDS}秒${NC}"
    echo -e "${BLUE}============================================${NC}"

    show_output
}

cmd_quick() {
    check_openwrt
    apply_openwrt_patches
    cd "$OPENWRT_DIR"
    echo -e "${YELLOW}[→] 快速增量编译固件...${NC}"
    # [M9] 同 cmd_build
    set -o pipefail
    if ! make -j"$THREADS" V=s 2>&1 | tee "$SCRIPT_DIR/build-quick.log"; then
        set +o pipefail
        echo -e "${RED}[✗] 快速编译失败，请查看: $SCRIPT_DIR/build-quick.log${NC}"
        exit 1
    fi
    set +o pipefail
    show_output
}

cmd_clean() {
    check_openwrt
    cd "$OPENWRT_DIR"
    echo -e "${YELLOW}[→] 清理编译产物...${NC}"
    make clean
    echo -e "${GREEN}[✓] 已清理${NC}"
}

cmd_distclean() {
    check_openwrt
    cd "$OPENWRT_DIR"
    echo -e "${YELLOW}[→] 完全清理（含下载缓存）...${NC}"
    # [L4] 非交互式环境禁止静默「成功」：distclean 会删下载缓存，必须由人工在终端确认
    if [ ! -t 0 ]; then
        echo -e "${RED}[✗] 非交互式环境无法执行 distclean（避免 CI/脚本误以为已清理）${NC}" >&2
        echo -e "${YELLOW}请在本地终端交互运行: $0 distclean${NC}" >&2
        exit 1
    fi
    read -p "  这将删除所有下载的源码和编译产物，确认? [y/N] " confirm
    if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
        make distclean
        echo -e "${GREEN}[✓] 已完全清理${NC}"
    else
        echo -e "${YELLOW}已取消${NC}"
    fi
}

cmd_diffconfig() {
    check_openwrt
    cd "$OPENWRT_DIR"
    local OUT="$SCRIPT_DIR/config/rax3000m.diffconfig.min"
    echo -e "${YELLOW}[→] 导出配置差异到 config/rax3000m.diffconfig.min（不覆盖完整预置 config/rax3000m.config）...${NC}"
    ./scripts/diffconfig.sh > "$OUT"
    echo -e "${GREEN}[✓] 精简差异已导出: $OUT${NC}"
}

cmd_info() {
    check_openwrt
    cd "$OPENWRT_DIR"

    echo -e "${BLUE}============================================${NC}"
    echo -e "${BLUE}  ARX3000M 编译信息${NC}"
    echo -e "${BLUE}============================================${NC}"
    echo -e " ${YELLOW}OpenWrt 版本:${NC} $(git describe --tags 2>/dev/null || echo 'unknown')"
    echo -e " ${YELLOW}源码目录:${NC} $OPENWRT_DIR"
    # [L2] 从 .config 动态读取目标架构，避免硬编码
    local arch_info
    if [ -f .config ]; then
        arch_info=$(grep -E "^CONFIG_TARGET_ARCH_PACKAGES=" .config | cut -d= -f2 | tr -d '"' || echo 'aarch64_cortex-a53')
    fi
    echo -e " ${YELLOW}目标架构:${NC} ${arch_info:-aarch64_cortex-a53} (Mediatek Filogic)"
    echo -e " ${YELLOW}CPU 核心数:${NC} $(nproc)"
    echo -e " ${YELLOW}编译线程:${NC} $THREADS"
    echo ""

    if [ -f .config ]; then
        echo -e " ${YELLOW}当前配置摘要:${NC}"
        grep -E "^CONFIG_TARGET_.*=y$" .config | head -20 | while read line; do
            echo -e "  ${GREEN}✓${NC} ${line#CONFIG_}"
        done
    fi

    echo ""
    if [ -d bin/targets/mediatek/filogic ]; then
        echo -e " ${YELLOW}已有编译产物:${NC}"
        ls -lh bin/targets/mediatek/filogic/*.bin 2>/dev/null | awk '{print "  ", $9, $5}'
    fi
    echo ""
}

show_output() {
    local OUTPUT_DIR="$OPENWRT_DIR/bin/targets/mediatek/filogic"
    if [ -d "$OUTPUT_DIR" ]; then
        echo -e "\n${CYAN}📦 编译产物:${NC}"
        ls -lh "$OUTPUT_DIR"/*sysupgrade* 2>/dev/null | awk '{print "  📄 " $9, "(" $5 ")"}'
        ( ls -lh "$OUTPUT_DIR"/*-squashfs-sysupgrade.bin "$OUTPUT_DIR"/*-squashfs-factory.bin "$OUTPUT_DIR"/*-squashfs-initramfs-kernel.bin 2>/dev/null || true ) | awk '{print "  📦 " $9, "(" $5 ")  (.bin 别名，FIT 与 .itb / recovery 相同)"}'
        ls -lh "$OUTPUT_DIR"/*initramfs* 2>/dev/null | awk '{print "  🧪 " $9, "(" $5 ")  (内存根文件系统 / 临时或救砖)"}'
        ls -lh "$OUTPUT_DIR"/*factory* 2>/dev/null | awk '{print "  🏭 " $9, "(" $5 ")"}'
        echo ""
        echo -e "${YELLOW}⛔ 引导工件:${NC} NAND 机（标签无 EC）裸刷/救砖只使用 ${GREEN}*nand-ddr3-*${NC} 或 ${GREEN}*nand-ddr4-*${NC} 的 preloader + fip；${RED}切勿${NC}刷 ${RED}*emmc-*${NC}（与 sysupgrade.itb 是否为「NAND 专用」无关：.itb 为 NAND/eMMC 共用）。"
        echo ""
        echo -e "${CYAN}📍 产物路径: $OUTPUT_DIR${NC}"
    else
        echo -e "\n${RED}未找到编译产物，请检查 build.log${NC}"
    fi
}

case "${1:-}" in
    init)        cmd_init ;;
    feed)        cmd_feed ;;
    config)      cmd_config ;;
    menuconfig)  cmd_menuconfig ;;
    download)    cmd_download ;;
    build)       cmd_build ;;
    quick)       cmd_quick ;;
    clean)       cmd_clean ;;
    distclean)   cmd_distclean ;;
    diffconfig)  cmd_diffconfig ;;
    info)        cmd_info ;;
    copy)        cmd_copy ;;
    *)           usage ;;
esac
