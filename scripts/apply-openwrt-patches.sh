#!/usr/bin/env bash
# Apply patches/openwrt/*.patch under OPENWRT_DIR (-p1, skip if already applied).
set -euo pipefail
PROJECT_ROOT="${1:?project root}"
OPENWRT_DIR="${2:?openwrt tree}"
PATCH_DIR="$PROJECT_ROOT/patches/openwrt"
if [[ ! -d "$PATCH_DIR" ]]; then
	exit 0
fi
shopt -s nullglob
patches=( "$PATCH_DIR"/*.patch )
if (( ${#patches[@]} == 0 )); then
	exit 0
fi
echo "[→] Applying ${#patches[@]} OpenWrt patch(es) from $PATCH_DIR"
for p in "${patches[@]}"; do
	echo "    + $(basename "$p")"
	patch -d "$OPENWRT_DIR" -p1 -N -i "$p"
done
echo "[✓] Patches applied"
