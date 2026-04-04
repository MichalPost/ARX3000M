# Project Structure

```
ARX3000M/
├── build.sh                  # Main build script (init/copy/feed/config/build/clean/etc.)
├── setup-env.sh              # One-shot environment setup (Ubuntu deps + OpenWrt clone)
├── config/
│   └── rax3000m.config       # OpenWrt .config (minimal diff format via diffconfig)
├── theme/                    # luci-theme-arx3000m (compiled as package/custom/luci-theme-arx3000m)
│   ├── Makefile
│   ├── htdocs/               # Static assets → /www/luci-static/arx3000m/
│   │   ├── css/style.css     # CSS variables: --primary, --accent, --success, --warning, --danger
│   │   └── js/arx.js
│   ├── luasrc/view/themes/arx3000m/
│   │   ├── header.htm
│   │   └── footer.htm
│   └── root/etc/uci-defaults/ # Theme registration via UCI
└── packages/
    ├── luci-app-arx-dashboard/
    ├── luci-app-arx-netmgr/
    ├── luci-app-arx-network/
    ├── luci-app-arx-software/
    ├── luci-app-arx-bridge/
    ├── luci-app-arx-wizard/
    └── luci-app-arx-wificrack/
```

`luci-app-arx-nas` 不在本仓库中；预置配置 `config/rax3000m.config` 中对应包为禁用（`CONFIG_PACKAGE_luci-app-arx-nas=n`）。

## Package Internal Layout (consistent across all packages)

```
luci-app-arx-<name>/
├── Makefile                          # OpenWrt package definition
├── luasrc/
│   ├── controller/arx_<name>.lua    # LuCI controller: index() + action_*() functions
│   ├── view/arx-<name>/*.htm        # Page templates (LuCI <%...%> syntax)
│   └── model/cbi/arx-<name>/*.lua  # CBI form models (optional, for config forms)
├── htdocs/                           # Static JS/CSS (optional, dashboard/theme only)
│   ├── css/
│   └── js/
└── root/
    ├── etc/config/arx-<name>        # Default UCI config file
    └── usr/share/rpcd/acl.d/
        └── luci-app-arx-<name>.json # rpcd permission declarations
```

## Controller Conventions

- Module declaration: `module("luci.controller.arx.<name>", package.seeall)`
- All routes registered in `index()` under `{"admin", "arx-<name>", ...}`
- JSON API actions: `call("action_<name>")` with `.leaf = true`
- Page templates: `template("arx-<name>/overview")` with `.leaf = true`
- Always guard `index()` with a config file existence check:
  ```lua
  if not nixio.fs.access("/etc/config/arx-<name>") then return end
  ```
- JSON responses: `http.prepare_content("application/json")` then `http.write_json(data)`

## Input Validation Rules (security-critical)
- MAC addresses: validate with `^%x%x:%x%x:%x%x:%x%x:%x%x:%x%x$` before use in shell commands
- Channel numbers: validate as integer in range 0–196
- File/history names: whitelist `^[%w%-_]+$` only
- Interface names: validate as `^[%w]+$` before use in shell commands
- File paths from user input: must be within expected directories, reject `..`
- Use `nixio.fs.dir()` instead of shell glob/`ls` for directory listing
- Numeric inputs from UCI: always clamp to `[min, max]` range

## UCI Config Pattern
Each package ships a default config at `root/etc/config/arx-<name>`:
```
config main 'main'
    option key 'value'
```
Read in Lua via `uci:get("arx-<name>", "main", "key")`.

## Frontend Pattern (dashboard/JS-heavy pages)
- Config values injected from Lua into `window.ARX_DASH_CFG = { ... }` in the `.htm` template
- API URLs injected into `window.ARX_DASH_URLS = { ... }` using `<%=url(...)%>`
- JS files loaded via `js = { "path/to/file.js" }` before `<%+footer%>`
- CSS loaded via `css = { "path/to/file.css" }` before `<%+header%>`
- Polling uses `visibility_pause` + `hidden_poll_multiplier` to reduce load on background tabs

## Makefile Install Path Mapping
Install `.htm` with an explicit glob (e.g. `$(INSTALL_CONF) ./luasrc/view/arx-<name>/*.htm ...`) so `install` never receives a directory operand. Theme: `$(CP) ./luasrc/view/themes/arx3000m/*.htm .../view/themes/arx3000m/`.

| Source | Destination |
|--------|-------------|
| `luasrc/controller/*.lua` | `/usr/lib/lua/luci/controller/arx/` |
| `luasrc/view/arx-<name>/*.htm` | `/usr/lib/lua/luci/view/arx-<name>/` |
| `luasrc/model/cbi/arx-<name>/` | `/usr/lib/lua/luci/model/cbi/arx-<name>/` |
| `htdocs/css/` | `/www/luci-static/resources/arx-<name>/css/` |
| `htdocs/js/` | `/www/luci-static/resources/arx-<name>/js/` |
| `root/etc/config/arx-<name>` | `/etc/config/arx-<name>` |
| `root/usr/share/rpcd/acl.d/*.json` | `/usr/share/rpcd/acl.d/` |
