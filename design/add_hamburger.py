import os, re

HAMBURGER = '<button class="topbar-menu-btn" id="topbar-menu-btn" title="显示侧边栏">☰</button>\n    '
PATTERN = re.compile(r'(<div class="topbar-bc">)')

pages = [f for f in os.listdir('.') if f.endswith('.html') and f != 'index.html']
for fn in pages:
    with open(fn, 'r', encoding='utf-8') as f:
        content = f.read()
    if 'topbar-menu-btn' in content:
        print(f'SKIP: {fn}'); continue
    new_content = PATTERN.sub(HAMBURGER + r'\1', content, count=1)
    if new_content != content:
        with open(fn, 'w', encoding='utf-8') as f:
            f.write(new_content)
        print(f'OK: {fn}')
    else:
        print(f'NO MATCH: {fn}')
