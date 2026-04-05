# ARX3000M 代码审查报告

> 审查范围：`packages/` 下所有 Lua 控制器、JS 前端、Makefile  
> 日期：2026-04-05

---

## 严重（Critical）

### C-1 · Evil Twin SSID 过滤模式存在残留注入风险
**文件：** `packages/luci-app-arx-wificrack/luasrc/controller/arx_wificrack.lua` 第 ~970 行  
**代码：**
```lua
ssid = ssid:gsub('[\\\"\'%c]', "_")
```
过滤模式仅覆盖反斜杠、双引号、单引号和控制字符，**未过滤 `$`、反引号（`` ` ``）、`|`、`&`、`;`**。  
虽然 SSID 最终通过 `ARX_ET_SSID=$(cat ssid_file)` 传入 shell，但 `ssid_file` 的内容仍会被 `$(cat ...)` 展开——若 shell 脚本 `arx-et.sh` 内部再次将 `$ARX_ET_SSID` 不加引号地拼入命令，则仍可触发命令注入。  
**建议：** 在写入 `ssid_file` 前，将 SSID 中所有非 `[%w%-_ ]` 字符替换为 `_`；同时确保 `arx-et.sh` 始终以 `"$ARX_ET_SSID"` 双引号形式引用该变量。

---

### C-2 · `action_start` 中 SSID 仅过滤控制字符，未过滤 shell 元字符
**文件：** `packages/luci-app-arx-wificrack/luasrc/controller/arx_wificrack.lua` 第 ~310 行  
**代码：**
```lua
local ssid = (http.formvalue("ssid") or "unknown"):gsub("[%c]", ""):sub(1, 32)
```
SSID 被写入 `INFO_FILE`（`target_info.txt`），后续 `read_info()` 读取后拼入日志消息并通过 `http.write_json` 返回。虽然此处不直接执行 shell，但若未来代码将 `info.ssid` 拼入 shell 命令（如超时子 shell 中的 `conv_cmd`），则 `$`、反引号等字符仍可被展开。  
**建议：** 与 C-1 统一，写入文件前用白名单 `[%w%-_ ]` 过滤 SSID。

---

## 高危（High）

### H-1 · `validate_ipv6_lite` 校验不完整，可接受格式错误的 IPv6 地址
**文件：** `packages/luci-app-arx-network/luasrc/controller/arx_network.lua` 第 18–30 行  
**问题：**
- `#ip > 128` 的长度限制过于宽松（IPv6 最长 39 字符，含 zone id 也不超过 50）
- 允许 `::1::2` 这类格式（`:::` 被拒绝，但 `::1::2` 不含 `:::`）
- 不验证段数（`2001:db8:1` 只有 3 段，仍可通过）

虽然 `ping6`/`traceroute6` 本身会拒绝格式错误的地址，但错误地址会导致命令返回错误输出，前端无法区分"目标不可达"与"参数非法"。  
**建议：** 增加段数校验，或将长度上限收紧至 `#ip > 50`。

---

### H-2 · `action_wizard` 中 `valid_ipv4` 允许前导零
**文件：** `packages/luci-app-arx-wizard/luasrc/controller/arx_wizard.lua` 第 ~65 行  
**代码：**
```lua
local a,b,c,d = s:match("^(%d+)%.(%d+)%.(%d+)%.(%d+)$")
if not a then return false end
return tonumber(a)<=255 and ...
```
`192.168.001.001` 可通过校验并被写入 UCI，但部分工具（如 `iproute2`）会将前导零解释为八进制，导致实际配置的 IP 与用户输入不符。  
**建议：** 参照 `arx_netmgr.lua` 中的 `validate_ipv4`，拒绝每段有前导零的输入。

---

### H-3 · `action_service_action` 中 `pgrep -f` 拼接服务名未加 `--` 分隔符
**文件：** `packages/luci-app-arx-dashboard/luasrc/controller/arx_dashboard.lua` 第 ~80 行  
**代码：**
```lua
local pgrep2 = sys.exec('pgrep -f -- "' .. name .. '" 2>/dev/null | head -1')
```
`name` 来自 `DASHBOARD_SERVICES` 白名单，本身安全。但 `service_running_short` 同时被 `action_network_health` 调用，传入的服务名来自 UCI 读取（`smartdns`、`openclash` 等），若 UCI 被篡改为含双引号的值，则双引号拼接会破坏命令结构。  
**建议：** 在 `service_running_short` 入口处统一校验 `name:match("^[%w_%-]+$")`（已有但仅在 `service_running_short` 内部，`action_network_health` 的调用路径未经过该检查）。

---

### H-4 · `action_history_dl` 未校验 `Content-Disposition` 中的文件名
**文件：** `packages/luci-app-arx-wificrack/luasrc/controller/arx_wificrack.lua` 第 ~790 行  
**代码：**
```lua
http.header("Content-Disposition", 'attachment; filename="'..name..'.22000"')
```
`validate_name` 已确保 `name` 仅含 `[%w%-_]`，但 `Content-Disposition` 中的 `filename` 参数未做 RFC 5987 编码。若浏览器对文件名解析宽松，含 Unicode 的 SSID 衍生名称（虽已被 `safe_ssid` 过滤）可能引发问题。  
**建议：** 使用 `filename*=UTF-8''...` 格式或确保文件名仅含 ASCII。

---

### H-5 · `action_diag_bundle` 输出中 UCI 密码脱敏正则可被绕过
**文件：** `packages/luci-app-arx-network/luasrc/controller/arx_network.lua` 第 ~200 行  
**代码：**
```lua
t = t:gsub("option%s+" .. k .. "%s+'[^']*'", "option " .. k .. " '***'")
```
仅匹配单引号和双引号格式，不匹配无引号格式（`option password mypass`）。OpenWrt UCI 允许无引号值，若密码不含空格则不会被脱敏。  
**建议：** 增加无引号格式的匹配：`option%s+k%s+(%S+)`。

---

## 中危（Medium）

### M-1 · `action_history` 中历史记录截断方向错误
**文件：** `packages/luci-app-arx-wificrack/luasrc/controller/arx_wificrack.lua` 第 ~740 行  
**代码：**
```lua
while #records > MAX_HISTORY do table.remove(records) end
```
`table.remove(records)` 不传索引时删除**最后一个**元素，而记录已按时间降序排列，因此删除的是**最旧**的记录——逻辑正确，但依赖排序顺序的隐式假设，脆弱。  
**建议：** 改为 `table.remove(records, #records)` 明确语义，或在排序前截断。

---

### M-2 · `get_cpu_usage` 写 `/tmp/arx-cpu-stat-prev` 无错误处理
**文件：** `packages/luci-app-arx-dashboard/luasrc/controller/arx_dashboard.lua` 第 ~290 行  
**代码：**
```lua
local wf = io.open(CPU_PREV_FILE, "w")
if wf then wf:write(...); wf:close() end
```
若 `/tmp` 满（嵌入式设备常见），`io.open` 返回 `nil`，下次调用将回退到累计均值而非差值，导致 CPU 使用率显示偏低但无任何错误提示。  
**建议：** 写失败时在 JSON 响应中加入 `cpu_stat_warn` 字段提示前端。

---

### M-3 · `action_devices` 中 ARP 表与 DHCP 租约合并时 MAC 大小写不一致
**文件：** `packages/luci-app-arx-netmgr/luasrc/controller/arx_netmgr.lua` 第 ~130 行  
**代码：**
```lua
local exp_time, mac, ip, name = line:match("(%S+)%s+(%S+)%s+(%S+)%s+(.*)")
dhcp_leases[mac:upper()] = { ... }
```
DHCP 租约 MAC 已转大写，ARP 表 MAC 也转大写（`mac = arp["MAC Address"]:upper()`），合并逻辑正确。但 `wifi_clients` 的键来自 `iwinfo assoclist` 输出，已在 `get_wifi_clients` 中转大写。若某个 `iwinfo` 版本输出小写，则 `wifi_clients[mac]` 查找会失败，WiFi 信息丢失。  
**建议：** 在 `get_wifi_clients` 返回前统一 `mac = mac:upper()`（已有，但依赖 `iwinfo` 输出格式）。

---

### M-4 · `action_disk_usage` 中 `bsize = 0` 时磁盘用量全为零
**文件：** `packages/luci-app-arx-dashboard/luasrc/controller/arx_dashboard.lua` 第 ~370 行  
**代码：**
```lua
local bsize = tonumber(stat.bsize) or 0
local total = blks * bsize   -- bsize=0 → total=0
local used  = total - free   -- 0 - 0 = 0
```
`nixio.fs.statvfs` 在某些文件系统（如 `ubifs`）上可能返回 `bsize = 0`，导致磁盘用量显示为 0/0，告警逻辑失效。  
**建议：** `local bsize = tonumber(stat.bsize) or 4096; if bsize == 0 then bsize = 4096 end`

---

### M-5 · `action_upnp_status` 中 `upnpc -l` 输出解析依赖固定格式
**文件：** `packages/luci-app-arx-network/luasrc/controller/arx_network.lua` 第 ~90 行  
**代码：**
```lua
local proto, ext_port, int_addr, desc, dur =
    line:match("%s*%d+%s+(%a+)%s+(%d+)%s*%->%s*(%S+)%s+'([^']*)'%s+(%d+)")
```
`upnpc` 不同版本输出格式差异较大，备用模式（无引号描述）也可能漏匹配。解析失败时静默跳过，前端显示规则数为 0，用户无法区分"无规则"与"解析失败"。  
**建议：** 增加 `parse_error` 字段，或改用 `upnpc -l` 的 XML 输出（`-x` 参数）。

---

### M-6 · `action_et_start` 中 `ap_iface` 构造方式可能产生空字符串
**文件：** `packages/luci-app-arx-wificrack/luasrc/controller/arx_wificrack.lua` 第 ~975 行  
**代码：**
```lua
local ap_iface = iface:gsub("[^%w]", "") .. "ap"
```
若 `iface` 全为非字母数字字符（极端情况），`gsub` 结果为空字符串，`ap_iface = "ap"`，传给 `arx-et.sh` 后可能创建名为 `ap` 的接口，与系统已有接口冲突。  
**建议：** 校验 `ap_iface ~= "ap"` 且长度 > 2，否则拒绝启动。

---

### M-7 · `action_adguard_oc_apply` 中 `validate_adguard_upstream_port` 拒绝端口 53 但不拒绝特权端口
**文件：** `packages/luci-app-arx-dashboard/luasrc/controller/arx_dashboard.lua` 第 ~45 行  
**代码：**
```lua
if n == 53 then return nil end
return n
```
端口 1–1023（除 53 外）均可通过，允许将 dnsmasq 上游指向 `127.0.0.1#80`（Web 服务）等，可能导致 DNS 解析异常。  
**建议：** 限制端口范围为 `1024–65535`（或已知安全端口白名单）。

---

### M-8 · `action_diag_bundle` 中 `sanitize_diag_text` MAC 脱敏边界检测有误
**文件：** `packages/luci-app-arx-network/luasrc/controller/arx_network.lua` 第 ~185 行  
**代码：**
```lua
local edge_ok = (bef == "" or (not bef:match("%x") and bef ~= ":"))
    and (aft == "" or (not aft:match("%x") and aft ~= ":"))
```
`bef:match("%x")` 匹配单个十六进制字符，但 `%x` 在 Lua 中匹配 `[0-9a-fA-F]`，而 `g`、`h` 等字母不在其中。若 MAC 地址紧跟字母（如 `aa:bb:cc:dd:ee:ffGHz`），`bef` 为 `f`（十六进制），`edge_ok` 为 false，该 MAC 不会被脱敏。  
**建议：** 改用 `bef:match("[%x:]")` 统一判断。

---

## 低危（Low）

### L-1 · `action_scan` 中 SSID 清理仅过滤控制字符，未限制长度
**文件：** `packages/luci-app-arx-wificrack/luasrc/controller/arx_wificrack.lua` 第 ~230 行  
**代码：**
```lua
if ssid then cur.ssid = ssid:gsub("[%c]", "") end
```
扫描结果中的 SSID 未做长度截断，若 AP 广播超长 SSID（理论上 802.11 限制 32 字节，但某些驱动可能不强制），会导致 JSON 响应体膨胀。  
**建议：** 加 `:sub(1, 64)` 截断。

---

### L-2 · `action_logs` 中 `max_lines` 参数边界检查逻辑可简化
**文件：** `packages/luci-app-arx-dashboard/luasrc/controller/arx_dashboard.lua` 第 ~430 行  
**代码：**
```lua
if max_lines < 1 or max_lines > 1000 then max_lines = 30 end
```
超出范围时重置为默认值而非截断，用户传入 `lines=2000` 会静默变为 30，行为不直观。  
**建议：** 改为 `max_lines = math.min(math.max(max_lines, 1), 1000)`。

---

### L-3 · `action_ddns_status` 中 `sys.init.enabled` 调用未做 pcall 保护
**文件：** `packages/luci-app-arx-network/luasrc/controller/arx_network.lua` 第 ~60 行  
**代码：**
```lua
enabled_unit = s.enabled == "1" and (sys.init.enabled("ddns_" .. s[".name"]) and "running" or "stopped") or "disabled"
```
`sys.init.enabled` 在某些 OpenWrt 版本中可能不存在或抛出异常，导致整个 `action_ddns_status` 崩溃，返回 500。  
**建议：** 用 `pcall` 包裹，或先检查 `sys.init and sys.init.enabled`（dashboard 中已有此模式，network 中未使用）。

---

### L-4 · `action_extroot_apply` 中 fstab 备份恢复使用 `sys.call("cp ...")` 而非 `nixio.fs`
**文件：** `packages/luci-app-arx-software/luasrc/controller/arx_software.lua` 第 ~340 行  
**代码：**
```lua
sys.call("cp /etc/config/fstab.arx.bak /etc/config/fstab")
```
`cp` 命令路径硬编码，在精简 BusyBox 环境中 `cp` 可能不在 PATH 中。  
**建议：** 改用 `nixio.fs.writefile(dst, nixio.fs.readfile(src))`。

---

### L-5 · `action_probe_mirrors` 中镜像探测 URL 硬编码，与 `action_apply` 中的镜像列表重复维护
**文件：** `packages/luci-app-arx-software/luasrc/controller/arx_software.lua` 第 ~290 行  
镜像 URL 在 `action_probe_mirrors` 和 `detect_preset` 中各维护一份，若新增镜像只更新一处会导致不一致。  
**建议：** 提取为模块级常量表。

---

### L-6 · 前端 JS 中 `en === 0` 类型比较可能失效
**文件：** `packages/luci-app-arx-dashboard/htdocs/js/dashboard-overview.js` 第 ~290 行  
**代码：**
```javascript
var en = dd.enabled || 0, run = dd.running || 0;
if (en === 0) { ... }
```
若后端返回 `"enabled": "0"`（字符串），`dd.enabled || 0` 结果为 `"0"`（非空字符串为 truthy），`en === 0` 为 false，DDNS 状态显示错误。  
**建议：** `var en = parseInt(dd.enabled) || 0`。

---

## 信息（Info）

- `arx_netmgr.lua` 中 `get_vendor` 函数线性扫描 OUI 文件，设备数量多时每次请求均重复扫描，建议缓存结果或改用二分查找。
- `action_topn_traffic_data` 中 conntrack 采样上限为 600 行，注释已说明，但前端未展示采样截断提示。
- `arx_wizard.lua` 中 PPPoE 密码写入 UCI 前未做长度限制，建议加 `#pass <= 64` 检查。
- `action_wificrack` 系列接口均未校验 `REQUEST_METHOD`（除 `action_tools`），建议 POST-only 接口统一加方法检查。

---

*报告基于源码静态分析，不含运行时测试。部分发现需结合 `arx-et.sh` 等 shell 脚本的实际实现进一步确认。*
