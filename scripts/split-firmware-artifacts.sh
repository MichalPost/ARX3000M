#!/usr/bin/env bash
# 将 bin/targets 下收集到的固件文件按用途分目录（与上游一次编译产出多类 ARTIFACTS 对应）。
# - sysupgrade/  日常升级、recovery、manifest、FIT 别名 .bin 等（白名单）
# - nand-boot/   文件名含 nand-ddr* 的 preloader / fip（NAND 裸刷）
# - emmc-boot/   文件名含 emmc 的 preloader / fip（eMMC 算力版裸刷；勿与 NAND 混刷）
# - misc/        未匹配白名单且非上述引导件的上游文件（勿当日常 sysupgrade）
set -euo pipefail

SRC="${1:?用法: $0 <源目录> <输出根目录>}"
OUT="${2:?}"

mkdir -p "$OUT/sysupgrade" "$OUT/nand-boot" "$OUT/emmc-boot" "$OUT/misc"

# 非 emmc / nand-ddr 工件：仅白名单进入 sysupgrade，其余进 misc
sysupgrade_whitelist() {
  local lower="$1"
  case "$lower" in
    sha256sums) return 0 ;;
    *.itb|*.manifest|*.img) return 0 ;;
  esac
  case "$lower" in
    *.bin|*.fip)
      if [[ "$lower" == *sysupgrade* ]] || [[ "$lower" == *recovery* ]] || [[ "$lower" == *initramfs* ]] \
        || [[ "$lower" == *squashfs* ]] || [[ "$lower" == *factory* ]]; then
        return 0
      fi
      ;;
  esac
  return 1
}

shopt -s nullglob
for f in "$SRC"/*; do
  [[ -f "$f" ]] || continue
  base=$(basename "$f")
  lower=$(echo "$base" | tr '[:upper:]' '[:lower:]')
  if [[ "$lower" == *emmc* ]]; then
    cp -a "$f" "$OUT/emmc-boot/"
  elif [[ "$lower" == *nand-ddr* ]] || [[ "$lower" == *nand_ddr* ]]; then
    cp -a "$f" "$OUT/nand-boot/"
  elif sysupgrade_whitelist "$lower"; then
    cp -a "$f" "$OUT/sysupgrade/"
  else
    cp -a "$f" "$OUT/misc/"
  fi
done
shopt -u nullglob

for sub in sysupgrade nand-boot emmc-boot misc; do
  d="$OUT/$sub"
  rm -f "$d/sha256sums"
  has_any=0
  for f in "$d"/*; do
    [[ -f "$f" ]] || continue
    has_any=1
    break
  done
  if (( has_any )); then
    (
      cd "$d" || exit 0
      shopt -s nullglob
      list=( * )
      files=()
      for f in "${list[@]}"; do
        [[ -f "$f" ]] || continue
        [[ "$f" == sha256sums ]] && continue
        files+=( "$f" )
      done
      shopt -u nullglob
      if (( ${#files[@]} > 0 )); then
        mapfile -t sorted < <(printf '%s\n' "${files[@]}" | LC_ALL=C sort)
        sha256sum "${sorted[@]}" >sha256sums
      fi
    )
  fi
done
