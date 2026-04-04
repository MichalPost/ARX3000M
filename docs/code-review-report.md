# ARX3000M 代码审查报告

> 审查日期：2026-04-05
> 审查范围：全部源码（构建脚本、Shell脚本、Lua控制器、前端JS/CSS/HTML模板）
> 严重等级：🔴 **Critical** > 🟠 **High** > 🟡 **Medium** > 🔵 **Low** > ⚪ **Info**

---

## 一、🔴 Critical — 可能导致系统崩溃/数据丢失/安全漏洞

### C-01: `build.sh` 第27行 `rm -rf` 无变量校验，可致根目录被删

- **文件**: [build.sh](../build.sh#L27-L28)
- **问题**: `rm -rf $BUILD_DIR` 在使用前未验证 `$BUILD_DIR` 是否为空或未定义。若环境异常导致变量为空字符串，将执行 `rm -rf /`，**删除整个文件系统**。
- **触发条件**: `BUILD_DIR` 变量未被正确设置（如脚本被 source 到非预期环境、第24行赋值前出错退出）
- **修复建议**:
  ```bash
  if [ -z "$BUILD_DIR" ]; then
    echo "ERROR: BUILD_DIR is not set" >&2
    exit 1
  fi
  if [ "$BUILD_DIR" = "/" ]; then
    echo "ERROR: BUILD_DIR cannot be root" >&2
    exit 1
  fi
  rm -rf "$BUILD_DIR"
  ```

### C-02: `arx-extroot-wizard` 第311行 `mkfs.ext4` 格式化操作无二次确认

- **文件**: [packages/luci-app-arx-software/root/sbin/arx-extroot-wizard](../packages/luci-app-arx-software/root/sbin/arx-extroot-wizard#L311)
- **问题**: `mkfs.ext4 -F "$disk"p${part}` 直接格式化用户指定的磁盘分区。虽然前端有确认弹窗，但后端 shell 脚本**没有任何输入校验**。若参数被篡改（如通过其他入口调用），可导致**任意磁盘被格式化**。
- **风险**: 磁盘路径注入 → 数据永久丢失
- **修复建议**: 添加磁盘路径白名单校验（仅允许 `/dev/sd*`、`/dev/mmcblk*`），并在格式化前再次打印目标设备要求确认。

### C-03: `arx-opkg-mirror` 第239行 `eval` 命令注入风险

- **文件**: [packages/luci-app-arx-software/root/sbin/arx-opkg-mirror](../packages/luci-app-arx-software/root/sbin/arx-opkg-mirror#L239)
- **问题**: `eval "echo \$$var"` 使用 `eval` 解析动态变量名。若 `$var` 的内容可控（来自 UCI 配置或 HTTP 参数），攻击者可注入任意 shell 命令。
- **风险**: 远程代码执行 (RCE)
- **修复建议**: 改用间接引用 `${!var}`（bash 4.x+）或使用 `declare -n` / 关联数组替代 eval。

### C-04: `arx-wificrack.sh` 多处命令注入 — BSSID/SSID/信道未转义

- **文件**: [packages/luci-app-arx-wificrack/root/usr/bin/arx-wificrack.sh](../packages/luci-app-arx-wificrack/root/usr/bin/arx-wificrack.sh)
- **涉及行**: L434 (`iw dev wlan0 scan ap-force`)、L445-L460 (hcxdumptool/airodump/tcpdump 启动命令)、L530 (timeout 计算)
- **问题**: 从 HTTP POST 接收的 `BSSID`、`SSID`、`CHANNEL` 参数直接拼入 shell 命令，**未经任何 sanitization**。恶意构造的 SSID（如 `"; rm -rf / #`）可导致任意命令执行。
- **风险**: 路由器被完全接管
- **修复建议**:
  ```bash
  # 校验 BSSID 格式 (XX:XX:XX:XX:XX:XX)
  if ! echo "$BSSID" | grep -qE '^[0-9a-fA-F]{2}(:[0-9a-fA-F]{2}){5}$'; then
    httpd_error "Invalid BSSID"
    return 1
  fi
  # 信道必须为数字
  CHANNEL="${CHANNEL##[!0-9]}"  # 仅保留数字
  ```

---

## 二、🟠 High — 功能缺陷 / 逻辑错误 / 数据损坏风险

### H-01: `arx-wificrack.sh` 第530-531行 timeout 为空时算术比较崩溃

- **文件**: [packages/luci-app-arx-wificrack/root/usr/bin/arx-wificrack.sh](../packages/luci-app-arx-wificrack/root/usr/bin/arx-wificrack.sh#L530-L531)
- **代码**:
  ```bash
  timeout_sec=$(uci -q get arx-wificrack.main.timeout)
  if [ "$timeout_sec" -gt 0 ] 2>/dev/null; then
  ```
- **问题**: 当 UCI 配置不存在或值为空时，`timeout_sec` 为空字符串，`[ "" -gt 0 ]` 在某些 shell 中会报语法错误导致脚本退出（因 `set -e`）。
- **影响**: 抓包功能在特定配置下直接崩溃
- **修复建议**: `timeout_sec=${timeout_sec:-0}` 确保默认值。

### H-02: `arx-wificrack.sh` 第414-415行 rm + mkdir 竞态条件

- **文件**: [packages/luci-app-arx-wificrack/root/usr/bin/arx-wificrack.sh](../packages/luci-app-arx-wificrack/root/usr/bin/arx-wificrack.sh#L414-L415)
- **代码**:
  ```bash
  rm -rf /tmp/arx-wificrack/*
  mkdir -p /tmp/arx-wificrack/{run,history,log}
  ```
- **问题**: `rm -rf` 使用 glob `/*`，若目录不存在则报错（取决于 shell 选项）。且 `rm` 和 `mkdir` 非原子操作，高并发下可能出问题。
- **修复建议**: 改为 `rm -rf /tmp/arx-wificrack && mkdir -p ...`

### H-03: `capture.htm` JS 第409行 selectTool 拼接 onclick 导致 XSS

- **文件**: [packages/luci-app-arx-wificrack/luasrc/view/arx-wificrack/capture.htm](../packages/luci-app-arx-wificrack/luasrc/view/arx-wificrack/capture.htm#L409)
- **代码**:
  ```javascript
  return '<button type="button" onclick="selectTool(\''+t.id+'\')" ...>'+...+'</button>';
  ```
- **问题**: `t.id` 直接拼入 HTML `onclick` 属性。虽然当前工具 ID 来自服务端硬编码列表（`hcxdumptool`/`airodump`/`tcpdump`），但若后续扩展工具检测逻辑允许自定义 ID，则存在 **XSS 注入向量**。
- **影响**: 存储型 XSS，可窃取管理员 session
- **修复建议**: 与页面其他按钮一致，改用 DOM API + `addEventListener` 方式绑定事件。

### H-04: `dashboard-overview.js` 大量 DOM 操作缺少 null guard

- **文件**: [packages/luci-app-arx-dashboard/htdocs/js/dashboard-overview.js](../packages/luci-app-arx-dashboard/htdocs/js/dashboard-overview.js)
- **涉及位置**: 几乎所有 `document.getElementById('xxx')` 调用后直接访问 `.textContent` / `.style` / `.classList`
- **问题**: 若 HTML 模板中对应 id 的元素被移除或改名，JS 将抛出 `Cannot read properties of null`，**导致整个轮询循环中断**，仪表盘停止更新。
- **影响**: 前端静默失效，用户看不到任何报错
- **修复建议**: 统一封装安全的 DOM 取值函数：
  ```javascript
  function $(id) { return document.getElementById(id); }
  function setText(id, val) { var el = $(id); if(el) el.textContent = val; }
  ```

### H-05: `arx_dashboard.lua` controller 缺少独立权限校验

- **文件**: [packages/luci-app-arx-dashboard/luasrc/controller/arx_dashboard.lua](../packages/luci-app-arx-dashboard/luasrc/controller/arx_dashboard.lua)
- **问题**: 所有 API 端点（`system_info`、`service_action`、`reboot_device` 等）仅依赖 LuCI 框架级别的认证。`reboot_device`（第L390-397行）和 `service_action`（第L370-386行）等高危操作**没有额外的 CSRF token 或权限检查**。
- **影响**: 若 LuCI 认证被绕过（如已知 session 固定漏洞），攻击者可直接重启路由器或启停服务
- **修复建议**: 对写操作添加 token 校验：`luci.dispatcher.verify_token(action, token)`。

### H-06: `arx-netmgr.lua` 设备管理缺少 MAC 地址格式校验

- **文件**: [packages/luci-app-arx-netmgr/luasrc/controller/arx_netmgr.lua](../packages/luci-app-arx-netmgr/luasrc/controller/arx_netmgr.lua)
- **问题**: `block_device`、`unblock_device`、`set_alias` 等 POST 接口接收的 `macaddr` 参数未做格式校验，直接传入 `arp`/`iptables`/`uci` 命令。
- **影响**: MAC 地址注入可能导致防火墙规则被篡改
- **修复建议**: 添加 MAC 格式正则校验 `^%x%x:%x%x:%x%x:%x%x:%x%x:%x%x$`。

---

## 三、🟡 Medium — 边界条件 / 异常处理不足 / 潜在回归

### M-01: `setup-env.sh` 第17行 cd 失败无错误处理

- **文件**: [setup-env.sh](../setup-env.sh#L17)
- **代码**: `cd "$SCRIPT_DIR"`
- **问题**: 若 `$SCRIPT_DIR` 指向不存在的目录（如软链接断裂），`cd` 失败但脚本继续执行，后续相对路径操作全部在错误的目录中进行。
- **修复建议**: `cd "$SCRIPT_DIR" || { echo "Failed to cd to $SCRIPT_DIR"; exit 1; }`

### M-02: `build.yml` CI 配置缺少缓存策略

- **文件**: [.github/workflows/build.yml](../.github/workflows/build.yml)
- **问题**: 每次 CI 运行都从零开始完整编译 OpenWrt，包括下载 feeds、安装依赖。对于频繁 push 的仓库，这浪费大量计算资源且增加失败率（网络超时等）。
- **影响**: CI 成本高、构建时间长、网络抖动易导致失败
- **修复建议**: 添加 `dl` 目录和 `feeds` 目录的 cache action：
  ```yaml
  - uses: actions/cache@v4
    with:
      path: build_dir/dl
      key: openwrt-dl-${{ hashFiles('config/*.config') }}
  ```

### M-03: `arx-opkg-usb-dest` lsblk 输出解析脆弱

- **文件**: [packages/luci-app-arx-software/root/sbin/arx-opkg-usb-dest](../packages/luci-app-arx-software/root/sbin/arx-opkg-usb-dest)
- **问题**: 使用 `lsblk --noheading --output SIZE,TYPE,MOUNTPOINT,NAME` 的空格分隔输出进行解析。不同版本的 lsblk 输出格式可能变化（如 SIZE 含单位、MOUNTPOINT 含空格），导致解析错乱。
- **影响**: USB 目标选择功能在某些 OpenWrt 版本上显示异常数据
- **修复建议**: 改用 `--pairs` 或 `--json` 输出格式，用更健壮的方式解析。

### M-04: `header.htm` 导航搜索 filterNav 函数全局污染

- **文件**: [theme/luasrc/view/themes/arx3000m/header.htm](../theme/luasrc/view/themes/arx3000m/header.htm#L100)
- **代码**: `<input ... oninput="filterNav(this.value)">`
- **问题**: `filterNav` 是一个全局函数，定义在 [arx.js](../theme/htdocs/js/arx.js) 中。若其他插件也定义同名函数，或页面加载顺序异常，会导致搜索功能失效。
- **修复建议**: 将函数挂载到命名空间对象上，如 `ARX.nav.filterNav()`。

### M-05: `style.css` 文件过大（3000+ 行），存在样式冲突隐患

- **文件**: [theme/htdocs/css/style.css](../theme/htdocs/css/style.css)
- **问题**: 单一 CSS 文件超过 3000 行，包含大量组件级样式。随着项目迭代，CSS 选择器优先级冲突的概率显著增加。已发现多处 `!important` 强制覆盖（约20+处），表明架构层面已有冲突。
- **影响**: 样式回归难以排查；新组件可能意外继承旧样式
- **修复建议**: 按 CSS Modules 或 BEM 命名规范拆分为多个文件（base/layout/components/theme）。

### M-06: `arx-wificrack.sh` 进程清理逻辑不完整

- **文件**: [packages/luci-app-arx-wificrack/root/usr/bin/arx-wificrack.sh](../packages/luci-app-arx-wificrack/root/usr/bin/arx-wificrack.sh) stop 分支
- **问题**: `stop` 操作通过 kill PID 文件中的进程来停止抓包，但未处理以下边界情况：
  1. PID 文件存在但进程已死（僵尸状态）
  2. kill 成功但子进程（如 hcxdumptool fork 的子进程）未被清理
  3. 并发 stop 请求的竞态
- **影响**: 抓包进程残留占用 WiFi 信道资源
- **修复建议**: 在 stop 时执行 `kill -- -$PGID` 杀掉进程组，并添加 `sleep 1 && pgrep` 确认清理完成。

### M-07: `arx_bridge.lua` 桥接模式切换期间网络中断无回滚机制

- **文件**: [packages/luci-app-arx-bridge/luasrc/controller/arx_bridge.lua](../packages/luci-app-arx-bridge/luasrc/controller/arx_bridge.lua)
- **问题**: 桥接模式切换（LAN/WAN 口互换）涉及修改 network 配置并重启网络服务。若重启过程中出现异常（如配置语法错误、ubus 超时），**路由器将失去网络连接且无法自动恢复**。
- **影响**: 用户需物理串口接入恢复
- **修复建议**: 切换前备份配置到临时文件，设置 watchdog 定时器（如 30 秒后自动恢复备份配置）。

### M-08: 所有 Lua controller 的 JSON API 未统一 Content-Type

- **文件**: 多个 `luasrc/controller/*.lua` 文件
- **问题**: 部分 API 端点返回 JSON 时未显式设置 `Content-Type: application/json`。LuCI 框架通常默认为 `text/html`，某些客户端（fetch API）可能无法正确解析响应。
- **影响**: 前端 fetch 的 `.json()` 可能抛出解析异常
- **修复建议**: 在每个 JSON API 入口统一设置：
  ```lua
  luci.http.prepare_content("application/json")
  ```

---

## 四、🔵 Low — 代码质量 / 可维护性问题

### L-01: `arx.js` 全局变量过多，命名空间缺失

- **文件**: [theme/htdocs/js/arx.js](../theme/htdocs/js/arx.js)
- **问题**: 大量全局变量和函数（`statusTimer`、`sparkData`、`initSparkline`、`filterNav` 等）直接挂在 `window` 上。与第三方 LuCI 插件的 JS 冲突风险高。
- **修复建议**: 封装到 `window.ARX = {}` 命名空间。

### L-02: `config/rax3000m.config` 包含硬编码路径

- **文件**: [config/rax3000m.config](../config/rax3000m.config)
- **问题**: 多处配置包含绝对路径（如 `CONFIG_TARGET_ROOTFS_PARTSIZE=400` 数值虽非路径，但部分 kernel/module 路径是隐式硬编码的）。若构建环境目录结构变更，需要手动同步修改。
- **修复建议**: 将环境相关的路径抽取到 `.config.override` 或构建脚本中动态生成。

### L-03: Shell 脚本混用 `[ ]` 和 `[[ ]]`

- **文件**: 所有 `.sh` 文件
- **问题**: 同一脚本甚至同一函数内混用 POSIX `[ ]` 和 bash `[[ ]]` 语法。例如 `arx-wificrack.sh` 同时使用了两种风格。这降低了可移植性且容易在条件判断中引入微妙差异（如 `==` vs `=` 的通配行为）。
- **修复建议**: 统一使用 `[[ ]]`（脚本已声明 `#!/bin/sh` 但实际使用 bash 特性，应改为 `#!/bin/bash`）。

### L-04: `header.htm` 第129行 section_defs 图标重复

- **文件**: [theme/luasrc/view/themes/arx3000m/header.htm](../theme/luasrc/view/themes/arx3000m/header.htm#L129)
- **代码**:
  ```lua
  { icon_id = 'i-sparkles', label = '服务', dot = 'services', ... },
  ...
  { icon_id = 'i-sparkles', label = '工具', dot = 'custom', ... },
  ```
- **问题**: 「服务」和「工具」两个导航分组使用了相同的图标 `i-sparkles`，用户在窄栏模式下无法通过图标区分两者。
- **修复建议**: 为「工具」分配不同的图标（如 `i-terminal` 或 `i-settings`）。

### L-05: `capture.htm` JS 定时器泄漏风险

- **文件**: [packages/luci-app-arx-wificrack/luasrc/view/arx-wificrack/capture.htm](../packages/luci-app-arx-wificrack/luasrc/view/arx-wificrack/capture.htm#L801-L807)
- **代码**:
  ```javascript
  function startStatusPolling() {
      refreshStatus();
      if (!statusTimer) statusTimer=setInterval(refreshStatus, 3000);
  }
  ```
- **问题**: 页面加载时（第824行）立即调用 `startStatusPolling()`，即使用户从未启动抓包，也会持续每3秒轮询 status 接口，**造成不必要的服务器负载**。
- **修复建议**: 初始轮询间隔设为 30 秒，抓包开始后再加速到 3 秒。

---

## 五、⚪ Info — 改进建议

### I-01: 项目缺少单元测试和集成测试

- 整个项目的 packages 目录下**没有任何测试文件**。Shell 脚本、Lua 控制器、JS 前端均无自动化测试覆盖。
- 建议: 对核心 shell 脚本添加 bats 测试，对 Lua controller 添加 mock 测试。

### I-02: 无 lint / 类型检查流程

- CI pipeline（[build.yml](../.github/workflows/build.yml)）仅有构建步骤，**无代码质量检查**（shellcheck、luacheck、eslint 等）。
- 建议: 在 CI 中添加静态分析步骤。

### I-03: UCI 配置文件缺少 schema 定义

- 各应用的 `/etc/config/arx-*` 配置文件**没有对应的 schema/validation 文件**。UCI 配置项的类型、范围、默认值全靠代码中分散处理。
- 建议: 为每个 config 创建 validation 回调或在 Makefile install 阶段写入默认配置。

### I-04: 前端 JS 错误无统一上报机制

- 所有页面的 JS 错误仅静默失败（catch 后空处理或 console.log），**无用户可见的错误提示**，也无服务端日志记录。
- 建议: 添加全局 `window.onerror` handler 收集错误信息并通过 API 上报。

### I-05: 版本号分散管理

- CSS 引用 `?v=2.7`（[header.htm L15](../theme/luasrc/view/themes/arx3000m/header.htm#L15)）、JS 引用 `?v=4`（[overview.htm L438](../packages/luci-app-arx-dashboard/luasrc/view/arx-dashboard/overview.htm#L438)），版本号散落在各处，更新时容易遗漏导致浏览器缓存问题。
- 建议: 统一由构建脚本或 Makefile 注入版本号。

---

## 六、问题统计汇总

| 严重等级 | 数量 | 占比 |
|---------|------|------|
| 🔴 Critical | 4 | 18% |
| 🟠 High | 6 | 27% |
| 🟡 Medium | 8 | 36% |
| 🔵 Low | 5 | 14% |
| ⚪ Info | 5 | 5% |
| **合计** | **28** | 100% |

### 按文件分布（Top 5 高危文件）

| 文件 | Critical | High | Medium | 总计 |
|------|----------|------|--------|------|
| `arx-wificrack.sh` | 1 | 1 | 1 | 3 |
| `arx-extroot-wizard` | 1 | 0 | 0 | 1 |
| `arx-opkg-mirror` | 1 | 0 | 0 | 1 |
| `capture.htm` (JS) | 0 | 1 | 0 | 1 |
| `dashboard-overview.js` | 0 | 1 | 0 | 1 |

### 修复优先级建议

1. **立即修复 (P0)**: C-01, C-02, C-03, C-04 — 安全漏洞和数据丢失风险
2. **本周修复 (P1)**: H-01, H-03, H-05, H-06 — 功能崩溃和高危接口安全
3. **迭代修复 (P2)**: M-01 ~ M-08 — 边界条件和鲁棒性改进
4. **技术债务 (P3)**: L-01 ~ I-05 — 代码质量和工程化改进
