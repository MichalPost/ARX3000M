#!/usr/bin/env bash
# 为 config/rax3000m.config 中启用的第三方包追加 feeds（上游 OpenWrt 默认不带 OpenClash）。
# 用法: ensure-extra-feeds.sh <OpenWrt 源码根目录>
set -e
set -o pipefail
OWRT="${1:?OpenWrt root directory required}"
cd "$OWRT"
FEEDS="feeds.conf.default"
[ -f "$FEEDS" ] || { echo "ensure-extra-feeds: missing $OWRT/$FEEDS" >&2; exit 1; }

append_src_git() {
	local name="$1"
	local url="$2"
	if grep -qE "^src-git[[:space:]]+${name}[[:space:]]" "$FEEDS" 2>/dev/null; then
		return 0
	fi
	printf '\nsrc-git %s %s\n' "$name" "$url" >> "$FEEDS"
	echo "ensure-extra-feeds: appended src-git $name $url"
}

append_src_git openclash https://github.com/vernesong/OpenClash.git
