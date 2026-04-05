import os, re

# Remove the layout picker div block that was injected
PATTERN = re.compile(
    r'<div style="position:relative">\s*'
    r'<button class="layout-btn".*?</div>\s*'
    r'</div>\s*',
    re.DOTALL
)

pages = [f for f in os.listdir('.') if f.endswith('.html') and f != 'index.html']
for fn in pages:
    with open(fn, 'r', encoding='utf-8') as f:
        content = f.read()
    new_content = PATTERN.sub('', content)
    if new_content != content:
        with open(fn, 'w', encoding='utf-8') as f:
            f.write(new_content)
        print(f'OK: {fn}')
    else:
        print(f'NO MATCH: {fn}')
