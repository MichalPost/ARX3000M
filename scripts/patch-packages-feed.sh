#!/usr/bin/env bash
# feeds 安装后修正 packages feed 中与 OpenWrt 仓库不同步的 Makefile，避免 make defconfig 报「依赖包不存在」。
# 用法: patch-packages-feed.sh <OpenWrt 源码根目录>
set -euo pipefail
OWRT="${1:?OpenWrt root}"

patch_onionshare_cli() {
	local mk="$OWRT/package/feeds/packages/onionshare-cli/Makefile"
	[[ -f "$mk" ]] || return 0
	if ! grep -q 'python3-pysocks\|python3-unidecode' "$mk"; then
		return 0
	fi
	# feeds 中无 python3-pysocks / python3-unidecode 包名；保留其余 DEPENDS（未编入固件时仅消除扫描告警）
	if sed --version >/dev/null 2>&1; then
		sed -i '/+python3-pysocks/d' "$mk"
		sed -i '/+python3-unidecode/d' "$mk"
	else
		sed -i '' '/+python3-pysocks/d' "$mk"
		sed -i '' '/+python3-unidecode/d' "$mk"
	fi
	echo "[✓] packages feed: onionshare-cli Makefile（移除不存在的 python3-pysocks / python3-unidecode 依赖）"
}

patch_onionshare_cli
