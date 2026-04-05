import argparse
import os
import re
import sys
from pathlib import Path

# Remove the layout picker div block that was injected
PATTERN = re.compile(
    r'<div style="position:relative">\s*'
    r'<button class="layout-btn".*?</div>\s*'
    r'</div>\s*',
    re.DOTALL
)


def main() -> None:
    ap = argparse.ArgumentParser(description='移除注入的 layout 选择器 HTML 块')
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
        new_content = PATTERN.sub('', content)
        if new_content != content:
            with open(path, 'w', encoding='utf-8') as f:
                f.write(new_content)
            print(f'OK: {fn}')
        else:
            print(f'NO MATCH: {fn}')


if __name__ == '__main__':
    main()
