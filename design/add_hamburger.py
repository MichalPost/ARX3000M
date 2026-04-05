import argparse
import os
import re
import sys
from pathlib import Path

HAMBURGER = '<button class="topbar-menu-btn" id="topbar-menu-btn" title="显示侧边栏">☰</button>\n    '
PATTERN = re.compile(r'(<div class="topbar-bc">)')


def main() -> None:
    ap = argparse.ArgumentParser(description='在各 HTML 的 topbar-bc 前注入汉堡菜单按钮')
    ap.add_argument('--dir', type=Path, default=None, help='含目标 .html 的目录（默认：本脚本所在目录）')
    args = ap.parse_args()
    base = args.dir.resolve() if args.dir else Path(__file__).resolve().parent
    if not base.is_dir():
        print(f'错误: 不是目录: {base}', file=sys.stderr)
        sys.exit(1)
    pages = [f for f in os.listdir(base) if f.endswith('.html') and f != 'index.html']
    if not pages:
        print(f'错误: 在 {base} 下未找到除 index.html 外的 .html 文件', file=sys.stderr)
        sys.exit(1)
    for fn in pages:
        path = base / fn
        with open(path, 'r', encoding='utf-8') as f:
            content = f.read()
        if 'topbar-menu-btn' in content:
            print(f'SKIP: {fn}')
            continue
        new_content = PATTERN.sub(HAMBURGER + r'\1', content, count=1)
        if new_content != content:
            with open(path, 'w', encoding='utf-8') as f:
                f.write(new_content)
            print(f'OK: {fn}')
        else:
            print(f'NO MATCH: {fn}')


if __name__ == '__main__':
    main()
