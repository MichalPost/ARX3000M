# Tech Stack

## Platform
- **OpenWrt** (main branch) — embedded Linux distro, build system based on GNU Make
- **Target**: `mediatek/filogic` / `aarch64_cortex-a53` (MT7981B Filogic 820)
- **LuCI** — OpenWrt's web UI framework (Lua + HTML templates)

## Languages
- **Lua** — backend controllers, CBI models, all server-side logic
- **HTML + embedded Lua** — view templates (`.htm` files using LuCI's `<%...%>` syntax)
- **JavaScript** — frontend polling/AJAX, dashboard charts (vanilla JS, no framework)
- **CSS** — theme styling with CSS custom properties (variables)
- **Shell (bash)** — build scripts, init scripts
- **UCI** — OpenWrt's Unified Configuration Interface for all package config files

## Key Libraries / APIs
- `luci.sys` — system calls (exec, hostname, uptime, net devices)
- `luci.http` — HTTP request/response, `http.write_json()` for JSON APIs
- `luci.model.uci` — UCI config read/write
- `nixio` / `nixio.fs` — low-level I/O, filesystem access, process info
- `luci.jsonc` — JSON parsing in Lua
- LuCI CBI — form-based config UI model (`luasrc/model/cbi/`)
- rpcd ACL — permission declarations in `/usr/share/rpcd/acl.d/*.json`

## Build System
Custom packages use the standard **OpenWrt package Makefile** format:
- `include $(TOPDIR)/rules.mk` and `include $(INCLUDE_DIR)/package.mk`
- `define Build/Compile` is empty (no compilation — pure Lua/HTML)
- `define Package/.../install` copies files with `$(INSTALL_DIR)` / `$(INSTALL_CONF)` / `$(INSTALL_DATA)`
- `$(eval $(call BuildPackage,<name>))` at the end

## Common Commands

```bash
# First-time environment setup (Ubuntu 22.04 / WSL2)
./build.sh init

# Copy custom packages into the OpenWrt source tree
./build.sh copy

# Update and install feeds
./build.sh feed

# Load the pre-configured .config for RAX3000M
./build.sh config

# Open interactive config menu
./build.sh menuconfig

# Download all source tarballs
./build.sh download   # or: make download -j$(nproc)

# Full firmware build (logs to build.log)
./build.sh build      # or: make -j$(nproc) V=s

# Quick rebuild (skips download)
./build.sh quick

# Compile a single package only
make package/luci-app-arx-dashboard/compile V=s

# Export minimal config diff back to config/rax3000m.config
./build.sh diffconfig

# Clean build artifacts (keep config)
./build.sh clean      # or: make clean

# Full clean including download cache
./build.sh distclean
```

## CI/CD
GitHub Actions (`.github/workflows/build.yml`):
- Triggers on push to `main`/`master` (ignores `*.md`, docs)
- Two jobs: `prepare` (cache keys) → `build` (compile firmware)
- Optional `release` job: only runs on manual `workflow_dispatch` with `upload_release: true`
- Caches: `dl/` directory + `ccache` (keyed on config + Makefile hashes)
- Build timeout: 120 minutes
- Artifacts: firmware `.bin` files (14-day retention) + build log (7-day retention)
- Firmware output: `bin/targets/mediatek/filogic/`
