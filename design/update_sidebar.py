#!/usr/bin/env python3
"""
Batch-replace <aside class="sidebar">...</aside> in all target HTML files
and inject <script src="js/sidebar.js"></script> before common.js.
"""

import re
from pathlib import Path

FILES = [
    "design/dashboard.html",
    "design/netmgr.html",
    "design/network.html",
    "design/bridge.html",
    "design/wificrack.html",
    "design/evil_twin.html",
    "design/software.html",
    "design/wizard.html",
    "design/wifi_rssi.html",
    "design/dns_chain.html",
    "design/adguard_oc.html",
    "design/recovery.html",
]

NEW_ASIDE = '''\
<aside class="sidebar">
  <div class="sb-logo">
    <div class="sb-logo-icon">📡</div>
    <div><div class="sb-logo-name">ARX3000M</div><div class="sb-logo-sub">OpenWrt · MT7981B</div></div>
  </div>
  <nav class="sb-nav" id="sb-nav"></nav>
  <div class="sb-footer">v2025.04 · RAX3000M</div>
</aside>'''

SIDEBAR_SCRIPT = '<script src="js/sidebar.js"></script>'
COMMON_SCRIPT  = '<script src="js/common.js"></script>'


def replace_aside(html: str) -> tuple[str, bool]:
    """Replace the entire <aside class="sidebar">...</aside> block."""
    # Walk character by character to find the matching </aside>
    pattern = '<aside class="sidebar">'
    start = html.find(pattern)
    if start == -1:
        return html, False

    depth = 0
    i = start
    length = len(html)
    while i < length:
        if html[i:].startswith('<aside'):
            depth += 1
            i += len('<aside')
        elif html[i:].startswith('</aside>'):
            depth -= 1
            if depth == 0:
                end = i + len('</aside>')
                replaced = html[:start] + NEW_ASIDE + html[end:]
                return replaced, True
            else:
                i += len('</aside>')
        else:
            i += 1

    return html, False  # unmatched — leave untouched


def inject_sidebar_script(html: str) -> tuple[str, bool]:
    """Insert sidebar.js script tag before common.js if not already present."""
    if SIDEBAR_SCRIPT in html:
        return html, False  # already there
    idx = html.find(COMMON_SCRIPT)
    if idx == -1:
        return html, False
    injected = html[:idx] + SIDEBAR_SCRIPT + '\n' + html[idx:]
    return injected, True


def process_file(path: str) -> None:
    p = Path(path)
    if not p.exists():
        print(f"  SKIP  {path}  (file not found)")
        return

    original = p.read_text(encoding="utf-8")
    html = original

    html, aside_changed = replace_aside(html)
    html, script_changed = inject_sidebar_script(html)

    if aside_changed or script_changed:
        p.write_text(html, encoding="utf-8")
        tags = []
        if aside_changed:  tags.append("aside replaced")
        if script_changed: tags.append("sidebar.js injected")
        print(f"  OK    {path}  ({', '.join(tags)})")
    else:
        print(f"  NOOP  {path}  (nothing to change)")


if __name__ == "__main__":
    print("=== update_sidebar.py ===")
    for f in FILES:
        process_file(f)
    print("=== done ===")
