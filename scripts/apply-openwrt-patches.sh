#!/usr/bin/env bash
# Apply patches/openwrt/*.patch under OPENWRT_DIR (-p1)。
# 补丁按路径名 LC_ALL=C sort 后依次应用；若有依赖顺序请用 01-foo.patch 风格命名。
# 若需对同一 OpenWrt 树重复执行，请先在 OPENWRT_DIR 内 git checkout -- . 或重新克隆，否则已应用过的补丁会导致 patch 失败（避免 -N 静默跳过）。
set -euo pipefail
PROJECT_ROOT="${1:?project root}"
OPENWRT_DIR="${2:?openwrt tree}"
PATCH_DIR="$PROJECT_ROOT/patches/openwrt"
if [[ ! -d "$PATCH_DIR" ]]; then
	exit 0
fi
mapfile -t patches < <(find "$PATCH_DIR" -maxdepth 1 -type f -name '*.patch' -print | LC_ALL=C sort)
if (( ${#patches[@]} == 0 )); then
	exit 0
fi
echo "[→] Applying ${#patches[@]} OpenWrt patch(es) from $PATCH_DIR"
for p in "${patches[@]}"; do
	echo "    + $(basename "$p")"
	patch -d "$OPENWRT_DIR" -p1 -i "$p"
done
echo "[✓] Patches applied"
