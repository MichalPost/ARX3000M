import os, re

LAYOUT_HTML = '''<div style="position:relative">
        <button class="layout-btn" id="layout-picker-btn">⊞ <span id="layout-btn-label">展开</span> ▾</button>
        <div class="layout-menu" id="layout-menu">
          <button class="layout-opt" data-layout="expanded">⊞ 展开</button>
          <button class="layout-opt" data-layout="narrow">▐ 窄栏</button>
          <button class="layout-opt" data-layout="hidden">✕ 隐藏</button>
        </div>
      </div>'''

# Insert before theme-picker div
PATTERN = re.compile(r'(<div class="theme-picker">)', re.DOTALL)

pages = [f for f in os.listdir('.') if f.endswith('.html') and f != 'index.html']
for fn in pages:
    with open(fn, 'r', encoding='utf-8') as f:
        content = f.read()
    if 'layout-picker-btn' in content:
        print(f'SKIP (already has): {fn}')
        continue
    new_content = PATTERN.sub(LAYOUT_HTML + '\n      \\1', content, count=1)
    if new_content != content:
        with open(fn, 'w', encoding='utf-8') as f:
            f.write(new_content)
        print(f'OK: {fn}')
    else:
        print(f'NO MATCH: {fn}')
