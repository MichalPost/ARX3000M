local sys = require "luci.sys"
local http = require "luci.http"
local uci = require "luci.model.uci"
local nixio = require "nixio"
local dsp = require "luci.dispatcher"

module("luci.controller.arx.dashboard", package.seeall)

function index()
if not nixio.fs.access("/etc/config/arx-dashboard") then return end

entry({"admin", "arx-dashboard"}, alias("admin", "arx-dashboard", "overview"), _("Dashboard"), 1).dependent = true
entry({"admin", "arx-dashboard", "overview"}, template("arx-dashboard/overview"), _("Overview"), 10).leaf = true
entry({"admin", "arx-dashboard", "realtime"}, call("action_realtime")).leaf = true
entry({"admin", "arx-dashboard", "system_info"}, call("action_system_info")).leaf = true
entry({"admin", "arx-dashboard", "network_stats"}, call("action_network_stats")).leaf = true
entry({"admin", "arx-dashboard", "disk_usage"}, call("action_disk_usage")).leaf = true
entry({"admin", "arx-dashboard", "processes"}, call("action_processes")).leaf = true
entry({"admin", "arx-dashboard", "services"}, call("action_services")).leaf = true
entry({"admin", "arx-dashboard", "service_action"}, call("action_service_action")).leaf = true
entry({"admin", "arx-dashboard", "fw_status"}, call("action_fw_status")).leaf = true
entry({"admin", "arx-dashboard", "logs"}, call("action_logs")).leaf = true
entry({"admin", "arx-dashboard", "network_health"}, call("action_network_health")).leaf = true
entry({"admin", "arx-dashboard", "mwan_status"}, call("action_mwan_status")).leaf = true
entry({"admin", "arx-dashboard", "ipv6_status"}, call("action_ipv6_status")).leaf = true
entry({"admin", "arx-dashboard", "mesh_status"}, call("action_mesh_status")).leaf = true
entry({"admin", "arx-dashboard", "wifi_env"}, call("action_wifi_env")).leaf = true
entry({"admin", "arx-dashboard", "wifi_rssi"}, template("arx-dashboard/wifi_rssi"), _("无线信号"), 15).leaf = true
entry({"admin", "arx-dashboard", "wifi_rssi_data"}, call("action_wifi_rssi_data")).leaf = true
entry({"admin", "arx-dashboard", "recovery"}, template("arx-dashboard/recovery"), _("恢复说明"), 30).leaf = true
entry({"admin", "arx-dashboard", "dns_chain"}, template("arx-dashboard/dns_chain"), _("DNS 解析链"), 31).leaf = true
entry({"admin", "arx-dashboard", "adguard_openclash"}, template("arx-dashboard/adguard_openclash"), _("AdGuard + OpenClash"), 32).leaf = true
entry({"admin", "arx-dashboard", "adguard_oc_apply"}, call("action_adguard_oc_apply")).leaf = true
end

-- AdGuard（非 53）作为 dnsmasq 上游、OpenClash DNS（默认 7874）作为 AdGuard 上游时的端口校验
local function validate_adguard_upstream_port(p)
	local n = tonumber(p)
	if not n or n < 1 or n > 65535 then return nil end
	if n == 53 then return nil end
	return n
end

local function first_dhcp_dnsmasq_section(cur)
	local section
	cur:foreach("dhcp", "dnsmasq", function(s)
		if not section then section = s[".name"] end
	end)
	return section
end

local function normalize_uci_list(val)
	if not val then return {} end
	if type(val) == "table" then return val end
	return { val }
end

function action_adguard_oc_apply()
	local base = dsp.build_url("admin/arx-dashboard/adguard_openclash")
	if (http.getenv("REQUEST_METHOD") or ""):upper() ~= "POST" then
		http.status(405, "Method Not Allowed")
		http.write("Method Not Allowed")
		return
	end
	local act = http.formvalue("arx_oc_action") or "add"
	local adg = validate_adguard_upstream_port(http.formvalue("adg_port"))
	if not adg then
		http.redirect(base .. "?err=badport")
		return
	end
	local cur = uci.cursor()
	local section = first_dhcp_dnsmasq_section(cur)
	if not section then
		http.redirect(base .. "?err=nodnsmasq")
		return
	end
	local want = "127.0.0.1#" .. tostring(adg)
	if act == "remove" then
		cur:del_list("dhcp", section, "server", want)
		cur:commit("dhcp")
		sys.call("/etc/init.d/dnsmasq restart >/dev/null 2>&1")
		http.redirect(base .. "?applied=remove")
		return
	end
	local lst = normalize_uci_list(cur:get_list("dhcp", section, "server"))
	local exists = false
	for _, v in ipairs(lst) do
		if v == want then exists = true break end
	end
	if not exists then
		cur:add_list("dhcp", section, "server", want)
		cur:commit("dhcp")
		sys.call("/etc/init.d/dnsmasq restart >/dev/null 2>&1")
	end
	http.redirect(base .. "?applied=add")
end

local function service_running_short(name)
	if not name or not name:match("^[%w_%-]+$") then return false end
	-- [S3] 使用 pgrep -x 精确匹配进程名，避免 pgrep -f 拼接单引号时潜在注入
	local init_status = sys.exec("/etc/init.d/" .. name .. " status 2>&1 | grep running")
	if init_status and init_status ~= "" then return true end
	local pgrep = sys.exec("pgrep -x " .. name .. " | head -1 2>/dev/null")
	if pgrep and pgrep:match("%S") then return true end
	-- 对于进程名与服务名不同的情况（如 openclash/passwall），回退到 pgrep -f
	-- 用 grep -Fx 精确全词匹配，避免 passwall 误匹配 passwall2
	local pgrep2 = sys.exec("pgrep -f '" .. name .. "' 2>/dev/null | head -1")
	return pgrep2 and pgrep2:match("%S") ~= nil
end

-- L-1: 移除冗余别名，统一使用 service_running_short
local service_running_by_name = service_running_short  -- kept for call-site compatibility

local function init_unit_enabled(name)
	if sys.init and sys.init.enabled then
		local ok, r = pcall(function() return sys.init.enabled(name) end)
		if ok and r then return true end
	end
	return false
end

-- Whitelist for service list + service_action (must stay in sync)
local DASHBOARD_SERVICES = {
	{ name = "firewall",    desc = "防火墙" },
	{ name = "dnsmasq",     desc = "DNS/DHCP 服务" },
	{ name = "network",     desc = "网络服务" },
	{ name = "dropbear",    desc = "SSH 服务" },
	{ name = "uhttpd",      desc = "Web 管理界面" },
	{ name = "samba4",      desc = "文件共享 (SMB)" },
	{ name = "nginx",       desc = "Web 服务器" },
	{ name = "adguardhome", desc = "广告过滤" },
	{ name = "cron",        desc = "定时任务" },
	{ name = "ddns",        desc = "动态 DNS" },
}

local function read_os_release_val(key)
	local f = io.open("/etc/os-release", "r")
	if not f then return nil end
	for line in f:lines() do
		local k, v = line:match("^([A-Z_0-9]+)=(.+)$")
		if k == key and v then
			f:close()
			return v:gsub('^"', ""):gsub('"$', "")
		end
	end
	f:close()
	return nil
end

local function compute_build_date()
	local bd = read_os_release_val("BUILD_ID")
	if bd and bd ~= "" then return bd end
	bd = read_os_release_val("OPENWRT_RELEASE")
	if bd and bd ~= "" then return bd end
	local d = sys.exec("date -r /rom/etc/openwrt_release '+%Y-%m-%d %H:%M' 2>/dev/null") or ""
	d = d:gsub("\n", ""):gsub("%s+$", "")
	if d ~= "" then return d end
	local rev = sys.exec("cat /etc/openwrt_release | grep DISTRIB_REVISION | cut -d'=' -f2 | tr -d '\"'") or ""
	rev = rev:gsub("\n", ""):gsub("%s+$", "")
	if rev ~= "" then return rev end
	return "—"
end

local function overlay_stat_bytes()
	local st = nixio.fs.statvfs("/overlay")
	if not st then
		st = nixio.fs.statvfs("/")
	end
	if not st then return 0, 0 end
	local total = (tonumber(st.blocks) or 0) * (tonumber(st.bsize) or 0)
	local free = (tonumber(st.bfree) or 0) * (tonumber(st.bsize) or 0)
	return free, total
end

function action_realtime()
http.prepare_content("application/json")
local info = {}
info.timestamp = os.time()
info.hostname = sys.hostname()
info.uptime = sys.uptime()
info.loadavg = sys.loadavg()
local meminfo = sys.sysinfo()
info.memory = {
total = meminfo.total,
free = meminfo.free,
buffered = meminfo.buffers or 0,
shared = meminfo.shared or 0,
used = math.max(0, meminfo.total - meminfo.free - (meminfo.buffers or 0) - (meminfo.cached or 0)),
cached = meminfo.cached or 0
}
info.cpu = get_cpu_usage()
info.temperature = get_temperature()
info.interfaces = get_interface_stats()
http.write_json(info)
end

function action_system_info()
http.prepare_content("application/json")
local u = uci.cursor()
local rel_desc = sys.exec("cat /etc/openwrt_release | grep DISTRIB_DESCRIPTION | cut -d'=' -f2 | tr -d '\"'") or "OpenWrt"
rel_desc = rel_desc:gsub("\n", ""):gsub("^%s+", ""):gsub("%s+$", "")
local ov_free, ov_total = overlay_stat_bytes()
local boardinfo = {
hostname = sys.hostname(),
system = sys.exec("cat /tmp/sysinfo/board_name") or "unknown",
model = sys.exec("cat /tmp/sysinfo/model") or "ARX3000M",
release = {
description = rel_desc,
revision = sys.exec("cat /etc/openwrt_release | grep DISTRIB_REVISION | cut -d'=' -f2 | tr -d '\"'") or "",
target = sys.exec("cat /etc/openwrt_release | grep DISTRIB_TARGET | cut -d'=' -f2 | tr -d '\"'") or "",
distribution = sys.exec("cat /etc/openwrt_release | grep DISTRIB_ID | cut -d'=' -f2 | tr -d '\"'") or "OpenWrt"
},
kernel = (sys.exec("uname -r") or "unknown"):gsub("\n", ""):gsub("%s+$", ""),
firmware_version = u:get_first("system", "system", "version") or "custom",
build_date = compute_build_date(),
openwrt_description = rel_desc,
overlay_free = ov_free,
overlay_total = ov_total,
localtime = os.date("%Y-%m-%d %H:%M:%S")
}
boardinfo.model = (boardinfo.model or ""):gsub("\n", ""):gsub("%s+$", "")
boardinfo.system = (boardinfo.system or ""):gsub("\n", ""):gsub("%s+$", "")
http.write_json(boardinfo)
end

function action_network_stats()
http.prepare_content("application/json")
http.write_json(get_interface_stats())
end

local function dash_uci_num(u, k, d, lo, hi)
	local v = tonumber(u:get("arx-dashboard", "main", k))
	if not v then return d end
	if v < lo then v = lo end
	if v > hi then v = hi end
	return v
end

local function disk_mount_interesting(dev, mnt, fst)
	if not mnt or not fst then return false end
	if fst == "tmpfs" or fst == "proc" or fst == "sysfs" or fst == "devtmpfs" or fst == "cgroup2" or fst == "cgroup" then return false end
	if fst == "rootfs" then return false end
	if mnt == "/" or mnt == "/overlay" or mnt == "/rom" then return true end
	-- [M4] Lua string.match 不支持 | 作为或运算符，改用多次 match 判断
	if dev then
		if dev:match("^/dev/sd[a-z][0-9]*$")
		or dev:match("^/dev/mmcblk[0-9]+p?[0-9]*$")
		or dev:match("^/dev/nvme[0-9]+n[0-9]+p?[0-9]*$")
		or dev:match("^/dev/ubiblock[0-9]+_[0-9]+$") then
			return true
		end
	end
	if mnt:match("^/mnt/") or mnt == "/opt" then return true end
	return false
end

local function storage_roles_for_mount(u, mount_point)
	local roles = {}
	local logf = u:get_first("system", "system", "log_file") or ""
	if logf ~= "" and logf:sub(1, #mount_point) == mount_point and (logf:sub(#mount_point + 1, #mount_point + 1) == "" or logf:sub(#mount_point + 1, #mount_point + 1) == "/") then
		table.insert(roles, "syslog")
	end
	if nixio.fs.access("/etc/config/fstab") then
		pcall(function()
			u:foreach("fstab", "mount", function(s)
				local t = s.target or ""
				if t == mount_point and s.enabled ~= "0" then
					if (s.label or ""):lower():match("opkg") or t:match("extroot") then table.insert(roles, "extroot") end
				end
			end)
		end)
	end
	return roles
end

function action_disk_usage()
	http.prepare_content("application/json")
	local u = uci.cursor()
	local warn_pct = dash_uci_num(u, "disk_warn_pct", 85, 50, 99)
	local warn_mb = dash_uci_num(u, "disk_warn_mb", 256, 16, 1048576)
	local seen = {}
	local disks = {}
	for line in io.lines("/proc/mounts") do
		local device, mount_point, fs_type = line:match("^([^%s]+)%s+([^%s]+)%s+([^%s]+)")
		if mount_point and not seen[mount_point] and disk_mount_interesting(device, mount_point, fs_type) then
			local stat = nixio.fs.statvfs(mount_point)
			if stat then
				seen[mount_point] = true
				local blks  = tonumber(stat.blocks) or 0
				local bsize = tonumber(stat.bsize)  or 0
				local bfree = tonumber(stat.bfree)  or 0
				local total = blks * bsize
				local free = bfree * bsize
				local used = total - free
				local pct = total > 0 and math.floor(used * 100 / total + 0.5) or 0
				local free_mb = math.floor(free / 1048576)
				local level = "ok"
				-- [LOW-6] 用 elseif 避免逻辑重叠，提升可读性
				if pct >= warn_pct or free_mb <= warn_mb then
					level = "danger"
				elseif pct >= warn_pct - 7 or free_mb <= warn_mb * 2 then
					level = "warn"
				end
				table.insert(disks, {
					device = device,
					mount = mount_point,
					fs_type = fs_type,
					total = total,
					free = free,
					used = used,
					use_percent = pct,
					free_mb = free_mb,
					warn_level = level,
					roles = storage_roles_for_mount(u, mount_point)
				})
			end
		end
	end
	table.sort(disks, function(a, b)
		if a.mount == "/" then return true end
		if b.mount == "/" then return false end
		if a.mount == "/overlay" then return true end
		if b.mount == "/overlay" then return false end
		return a.mount < b.mount
	end)
	http.write_json(disks)
end

function get_cpu_usage()
	local usage = { user = 0, system = 0, idle = 0, total = 0, percent = 0 }
	-- [HIGH-3] 两次采样取差值，得到真实实时 CPU 使用率（而非开机以来均值）
	local CPU_PREV_FILE = "/tmp/arx-cpu-stat-prev"
	local function read_stat()
		local f = io.open("/proc/stat", "r")
		if not f then return nil end
		local line = f:read("*l"); f:close()
		if not line then return nil end
		local _, u, n, s, id, iow, irq, sirq =
			line:match("(%w+)%s+(%d+)%s+(%d+)%s+(%d+)%s+(%d+)%s+(%d+)%s+(%d+)%s+(%d+)")
		if not u then return nil end
		u,n,s,id,iow,irq,sirq = tonumber(u),tonumber(n),tonumber(s),tonumber(id),tonumber(iow),tonumber(irq),tonumber(sirq)
		local total = u+n+s+id+iow+irq+sirq
		return { user=u, nice=n, system=s, idle=id, total=total }
	end
	local cur = read_stat()
	if not cur then return usage end
	-- 读取上次快照
	local prev_user, prev_idle, prev_total = 0, 0, 0
	local pf = io.open(CPU_PREV_FILE, "r")
	if pf then
		local line = pf:read("*l"); pf:close()
		if line then
			local pu, pi, pt = line:match("^(%d+) (%d+) (%d+)$")
			prev_user, prev_idle, prev_total = tonumber(pu) or 0, tonumber(pi) or 0, tonumber(pt) or 0
		end
	end
	-- 写入当前快照
	local wf = io.open(CPU_PREV_FILE, "w")
	if wf then wf:write(cur.user.." "..cur.idle.." "..cur.total.."\n"); wf:close() end
	local dtotal = cur.total - prev_total
	local didle  = cur.idle  - prev_idle
	usage.user   = cur.user
	usage.system = cur.system
	usage.idle   = cur.idle
	usage.total  = cur.total
	-- 首次调用（无历史）回退到累计均值；之后使用差值
	if dtotal > 0 then
		usage.percent = math.floor(((dtotal - didle) / dtotal) * 100 + 0.5)
	elseif cur.total > 0 then
		usage.percent = math.floor(((cur.total - cur.idle) / cur.total) * 100 + 0.5)
	end
	return usage
end

function get_temperature()
local temps = {}
local zones = nixio.fs.dir("/sys/class/thermal")
if zones then
for zone in zones do
if zone:match("^thermal_zone%d+$") then
local f = io.open("/sys/class/thermal/" .. zone .. "/temp", "r")
if f then
local val = f:read("*n")
f:close()
if val then
table.insert(temps, { name = zone, temp_c = math.floor(val / 1000), temp_raw = val })
end
end
end
end
end
return temps
end

function get_interface_stats()
local interfaces = {}
local uc = uci.cursor()
local lan_bridge = nil
local lan_dev = uc:get("network", "lan", "device") or uc:get("network", "lan", "ifname") or ""
lan_dev = tostring(lan_dev or ""):gsub("^%s+", ""):gsub("%s+$", "")
if lan_dev:match("^br%-") then
	lan_bridge = lan_dev
else
	for part in lan_dev:gmatch("%S+") do
		if part:match("^br%-") then
			lan_bridge = part
			break
		end
	end
end
if not lan_bridge then lan_bridge = "br-lan" end
local ifaces = sys.net.devices()
if ifaces then
-- [M3] 一次性解析 /proc/net/dev，避免对每个接口重复打开文件（O(n²) → O(n)）
local dev_stats = {}
local stats_file = io.open("/proc/net/dev", "r")
if stats_file then
for line in stats_file:lines() do
local name = line:match("^%s*([^:]+):")
if name then
-- [M5] /proc/net/dev: 8 rx字段后才是 tx_bytes tx_packets
local rb, rp, tb, tp =
line:match(":(%d+)%s+(%d+)%s+%d+%s+%d+%s+%d+%s+%d+%s+%d+%s+%d+%s+(%d+)%s+(%d+)")
dev_stats[name] = {
rx_bytes   = tonumber(rb) or 0,
rx_packets = tonumber(rp) or 0,
tx_bytes   = tonumber(tb) or 0,
tx_packets = tonumber(tp) or 0,
}
end
end
stats_file:close()
end
for _, iface in ipairs(ifaces) do
-- B-4: 仅排除 LAN 桥（通常为 br-lan），保留 br-wan 等以便 WAN 统计可见
if iface ~= "lo" and iface ~= lan_bridge then
local s = dev_stats[iface] or {rx_bytes=0,rx_packets=0,tx_bytes=0,tx_packets=0}
local ipv4 = sys.exec("ip -4 addr show " .. iface .. " scope global 2>/dev/null | grep inet | awk '{print $2}' | head -1") or ""
local mac  = sys.exec("cat /sys/class/net/" .. iface .. "/address 2>/dev/null") or ""
table.insert(interfaces, {
name       = iface,
ipv4       = ipv4:gsub("\n$", ""),
mac        = mac:gsub("\n$", ""),
rx_bytes   = s.rx_bytes,
tx_bytes   = s.tx_bytes,
rx_packets = s.rx_packets,
tx_packets = s.tx_packets
})
end
end
end
return interfaces
end

function action_processes()
http.prepare_content("application/json")
local processes = {}

local ps_output = sys.exec("ps -w -o pid,%cpu,%mem,comm --no-headers 2>/dev/null | head -15") or ""
for line in ps_output:gmatch("[^\r\n]+") do
local pid, cpu_pct, mem_pct, name = line:match("%s*(%d+)%s+(%S+)%s+(%S+)%s+(.+)")
if pid and name then
table.insert(processes, {
pid  = tonumber(pid),
cpu  = tonumber(cpu_pct) or 0,
mem  = tonumber(mem_pct) or 0,
name = name:match("^%s*(.-)%s*$")
})
end
end

http.write_json({ processes = processes })
end

function action_services()
http.prepare_content("application/json")
local result_services = {}
for _, svc in ipairs(DASHBOARD_SERVICES) do
local running = service_running_by_name(svc.name)
table.insert(result_services, { name = svc.name, description = svc.desc, running = running })
end
http.write_json({ services = result_services })
end

function action_service_action()
http.prepare_content("application/json")
if (http.getenv("REQUEST_METHOD") or ""):upper() ~= "POST" then
http.status(405, "Method Not Allowed")
http.write_json({ success = false, error = "仅支持 POST" })
return
end
local jsonc = require "luci.jsonc"
local raw = http.content() or ""
local ok_parse, body = pcall(jsonc.parse, raw)
if not ok_parse or type(body) ~= "table" then
http.write_json({ success = false, error = "无效 JSON" })
return
end
local svcname = tostring(body.service or "")
local op = tostring(body.action or "")
if op ~= "start" and op ~= "stop" and op ~= "restart" then
http.write_json({ success = false, error = "无效操作" })
return
end
local allowed = false
for _, s in ipairs(DASHBOARD_SERVICES) do
if s.name == svcname then allowed = true break end
end
if not allowed then
http.write_json({ success = false, error = "服务未授权" })
return
end
if op == "stop" and svcname == "uhttpd" then
http.write_json({ success = false, error = "禁止停止 Web 服务 (uhttpd)" })
return
end
sys.call("/etc/init.d/" .. svcname .. " " .. op .. " >/dev/null 2>&1")
http.write_json({
success = true,
running = service_running_by_name(svcname),
message = svcname .. " " .. op
})
end

function action_fw_status()
http.prepare_content("application/json")
local input_rules   = sys.exec("iptables -L INPUT -n --line-numbers 2>/dev/null | grep -c -E '^[0-9]+'") or "0"
local forward_rules = sys.exec("iptables -L FORWARD -n --line-numbers 2>/dev/null | grep -c -E '^[0-9]+'") or "0"
local nat_rules     = sys.exec("iptables -L POSTROUTING -t nat -n --line-numbers 2>/dev/null | grep -c -E '^[0-9]+'") or "0"
local sfe_out = sys.exec("pgrep -f fast_classifier 2>/dev/null | head -1") or ""
local sfe_running = sfe_out:match("%S") ~= nil
http.write_json({
input   = tonumber(input_rules:match("%d+")) or 0,
forward = tonumber(forward_rules:match("%d+")) or 0,
nat     = tonumber(nat_rules:match("%d+")) or 0,
sfe     = sfe_running
})
end

function action_logs()
http.prepare_content("application/json")
local max_lines = tonumber(http.formvalue("lines")) or 30
-- [M2] 限制范围，防止 DoS
if max_lines < 1 or max_lines > 1000 then max_lines = 30 end

local lines = {}
-- [M1] 修正变量名拼写错误：原代码 logdata 未定义，应为 log_data
local log_data = sys.exec("logread -l " .. max_lines .. " 2>/dev/null") or ""
if log_data ~= "" then
for line in log_data:gmatch("[^\r\n]+") do
table.insert(lines, line)
end
end

if #lines == 0 then
local dmesg_out = sys.exec("dmesg | tail -" .. max_lines .. " 2>/dev/null") or ""
if dmesg_out ~= "" then
for line in dmesg_out:gmatch("[^\r\n]+") do
table.insert(lines, line)
end
end
end

http.write_json({ lines = lines })
end

function action_network_health()
	http.prepare_content("application/json")
	local u = uci.cursor()
	local ddns_total, ddns_enabled, ddns_running = 0, 0, 0
	if nixio.fs.access("/etc/config/ddns") then
		u:foreach("ddns", "service", function(s)
			ddns_total = ddns_total + 1
			if s.enabled == "1" then
				ddns_enabled = ddns_enabled + 1
				local unit = "ddns_" .. s[".name"]
				if init_unit_enabled(unit) then ddns_running = ddns_running + 1 end
			end
		end)
	end

	local wan_up, wan_ip = false, ""
	-- M-6: 不依赖 get_interface_stats()（它过滤了 br- 前缀），直接用 ip 命令查询
	-- 候选接口：UCI wan device、pppoe-wan、"wan" 字面名
	local wan_proto = u:get("network", "wan", "proto") or ""
	local wan_dev = u:get("network", "wan", "ifname") or u:get("network", "wan", "device") or ""
	local pppoe_iface = wan_proto == "pppoe" and "pppoe-wan" or nil
	local candidates = { "wan" }
	if wan_dev ~= "" then candidates[#candidates+1] = wan_dev end
	if pppoe_iface then candidates[#candidates+1] = pppoe_iface end
	for _, cand in ipairs(candidates) do
		if cand ~= "" then
			local ip_out = sys.exec("ip -4 addr show dev " .. cand .. " scope global 2>/dev/null | grep inet | awk '{print $2}' | head -1") or ""
			ip_out = ip_out:gsub("%s+$", "")
			if ip_out ~= "" then
				wan_up = true
				wan_ip = ip_out
				break
			end
		end
	end

	local resolv_hint = ""
	local rf = "/tmp/resolv.conf.d/resolv.conf.auto"
	if nixio.fs.access(rf) then
		local f = io.open(rf, "r")
		if f then
			local n = 0
			for line in f:lines() do
				if line:match("^nameserver%s+") then
					resolv_hint = resolv_hint .. line:gsub("^nameserver%s+", ""):match("^%S+") .. " "
					n = n + 1
					if n >= 3 then break end
				end
			end
			f:close()
		end
	end
	resolv_hint = resolv_hint:gsub("%s+$", "")

	local dnsmasq_port = u:get_first("dhcp", "dnsmasq", "port") or "53"
	local chain_order = "客户端通常先问 dnsmasq（DHCP 下发的 DNS）"
	if service_running_short("smartdns") and service_running_short("dnsmasq") then
		chain_order = "常见：dnsmasq → SmartDNS（若 SmartDNS 接管 53 或 dnsmasq 指向上游 SmartDNS 端口）"
	end
	if service_running_short("adguardhome") then
		chain_order = chain_order .. "；若 AdGuard 独占 53，则客户端 → AdGuard → 上游。"
	end

	http.write_json({
		ddns = {
			total = ddns_total,
			enabled = ddns_enabled,
			running = ddns_running
		},
		wan = { up = wan_up, ipv4 = wan_ip },
		proxy = {
			openclash = service_running_short("openclash"),
			passwall = service_running_short("passwall")
		},
		dns = {
			smartdns = service_running_short("smartdns"),
			adguardhome = service_running_short("adguardhome")
		},
		dns_chain = {
			resolv_auto_ns = resolv_hint,
			dnsmasq_port = dnsmasq_port,
			order_hint = chain_order,
			dnsmasq = service_running_short("dnsmasq")
		}
	})
end

function action_mwan_status()
	http.prepare_content("application/json")
	local out = { available = false }
	if not nixio.fs.access("/etc/config/mwan3") then
		http.write_json(out)
		return
	end
	out.available = true
	local dev = sys.exec("ip -4 route show default 0.0.0.0/0 2>/dev/null | head -1 | awk '{for(i=1;i<=NF;i++) if($i==\"dev\") print $(i+1)}'") or ""
	dev = dev:gsub("\n", ""):gsub("%s+$", "")
	out.active_wan = dev ~= "" and dev or "?"
	local u = uci.cursor()
	local wan_n = 0
	pcall(function()
		u:foreach("mwan3", "interface", function() wan_n = wan_n + 1 end)
	end)
	out.policy = wan_n > 1 and ("mwan3 · " .. wan_n .. " 接口") or "mwan3"
	local le = sys.exec("logread 2>/dev/null | grep -iE 'mwan3|mwan' | tail -n 1") or ""
	out.last_event = le:gsub("^%S+%s+%S+%s+%S+%s+", ""):gsub("%s+$", "")
	out.last_event_time = ""
	out.all_up = true
	local raw = sys.exec("ubus call mwan3 status 2>/dev/null") or ""
	if raw:match("%S") then
		local jsonc = require "luci.jsonc"
		local ok, j = pcall(jsonc.parse, raw)
		if ok and j and type(j) == "table" then
			for _, st in pairs(j) do
				if type(st) == "table" and st.status == "offline" then out.all_up = false end
			end
		end
	end
	http.write_json(out)
end

function action_ipv6_status()
	http.prepare_content("application/json")
	local u = uci.cursor()
	local function cell(state, detail)
		return { state = state or "na", detail = detail or "" }
	end
	local out = {
		pd = cell("na", "未检测"),
		dhcpv6 = cell("na", ""),
		ula = cell("na", ""),
		firewall6 = cell("na", "启发式")
	}

	local wan6_proto = u:get("network", "wan6", "proto")
	if wan6_proto then
		local g6 = sys.exec("ip -6 addr show scope global 2>/dev/null | grep -m1 'inet6 '") or ""
		if g6:match("%S") then
			out.pd = cell("ok", "存在全局 IPv6 地址")
		else
			out.pd = cell("warn", "已配置 IPv6 接口但未见全局地址，检查上游或 PD")
		end
	else
		out.pd = cell("na", "未配置 wan6（可能为纯 IPv4）")
	end

	local ra = u:get("dhcp", "lan", "ra") or "server"
	local dhcpv6 = u:get("dhcp", "lan", "dhcpv6") or "server"
	if ra == "disabled" and (dhcpv6 == "disabled" or dhcpv6 == "none") then
		out.dhcpv6 = cell("na", "LAN RA/DHCPv6 已关闭")
	else
		-- B-3: 原 elseif 条件与首个 if 互补，else 分支是死代码；统一为 else
		out.dhcpv6 = cell("ok", "RA=" .. tostring(ra) .. " DHCPv6=" .. tostring(dhcpv6))
	end

	local ula = u:get("network", "globals", "ula_prefix") or ""
	if ula ~= "" then
		out.ula = cell("ok", ula)
	else
		local ula6 = sys.exec("ip -6 addr show scope link 2>/dev/null | grep -m1 'fd'") or ""
		if ula6:match("fd") then out.ula = cell("ok", "检测到 ULA 类地址") else out.ula = cell("na", "未配置 ULA") end
	end

	local nft = sys.exec("nft list ruleset 2>/dev/null | head -c 6000") or ""
	local ip6t = sys.exec("ip6tables -L FORWARD -n 2>/dev/null | head -n 15") or ""
	local blob = nft .. ip6t
	if blob:match("DROP") or blob:match("reject") then
		if blob:match("established") or blob:match("related") then
			out.firewall6 = cell("ok", "存在 forward 规则（含 established 类，启发式）")
		else
			out.firewall6 = cell("warn", "存在 drop/reject，请确认放行已建立连接与 ICMPv6")
		end
	else
		out.firewall6 = cell("na", "未解析到完整 IPv6 防火墙表（可能使用 nft 集）")
	end

	http.write_json(out)
end

function action_mesh_status()
	http.prepare_content("application/json")
	local out = { present = false }
	local u = uci.cursor()
	if nixio.fs.access("/etc/config/travelmate") then
		local st = sys.exec("ubus call travelmate status 2>/dev/null") or ""
		out.present = true
		out.mode = "travelmate"
		if st:match("%S") then
			local jsonc = require "luci.jsonc"
			local ok, j = pcall(jsonc.parse, st)
			if ok and j and type(j) == "table" then
				out.summary = (j.radio or "") .. " " .. (j.iface or "")
				out.upstream_ssid = j.ssid or j.bssid
				if j.signal then out.signal_dbm = tostring(j.signal) end
			else
				out.summary = "travelmate 运行中（详情见服务页）"
			end
		else
			out.summary = "已安装 travelmate"
		end
		local disc = sys.exec("logread 2>/dev/null | grep -i travelmate | grep -iE 'disconnect|assoc|deauth' | wc -l") or "0"
		local dn = tonumber(disc:match("(%d+)")) or 0
		out.disconnect_hint = "近期日志中含断开类关键词约 " .. tostring(dn) .. " 条（自日志缓冲）"
		http.write_json(out)
		return
	end

	local relay_ct = 0
	pcall(function()
		u:foreach("relayd", "relay", function() relay_ct = relay_ct + 1 end)
	end)
	if relay_ct > 0 then
		out.present = true
		out.mode = "relayd"
		out.summary = "relayd 已配置（" .. relay_ct .. " 条）"
		http.write_json(out)
		return
	end

	local iw = sys.exec("iw dev 2>/dev/null") or ""
	if iw:match("type mesh") or iw:match("type MP") then
		out.present = true
		out.mode = "802.11s mesh"
		out.summary = "检测到 mesh 型无线接口"
		http.write_json(out)
		return
	end

	http.write_json(out)
end

-- M-4: 辅助函数统一放在 action_wifi_env / action_wifi_rssi_data 之前，消除前向引用问题

local function arx_safe_ifname(ifn)
	return type(ifn) == "string" and ifn:match("^[%w%.%-]+$") ~= nil
end

local function arx_band_hint(channel, hw_mode)
	local c = tonumber(channel)
	if c then
		if c <= 14 then return "2.4 GHz" end
		if c <= 177 then return "5 GHz" end
		return "6 GHz"
	end
	local h = hw_mode and tostring(hw_mode):lower() or ""
	if h:find("11ax") or h:find("11be") then return "WiFi 6/7?" end
	if h:find("11ac") or h:find("11a") then return "5 GHz?" end
	if h:find("11g") or h:find("11b") or h:find("11n") then return "2.4 GHz?" end
	return "—"
end

local function arx_parse_iwinfo_info(ifn)
	if not arx_safe_ifname(ifn) then return nil end
	local info = sys.exec("iwinfo " .. ifn .. " info 2>/dev/null") or ""
	if info == "" or not info:match("%S") then return nil end
	local sig = info:match("Signal:%s*([%-%d]+)%s*dBm")
	local noise = info:match("Noise:%s*([%-%d]+)%s*dBm")
	local ch = info:match("Channel:%s*(%d+)")
	local essid = info:match('ESSID:%s*"([^"]*)"')
		or info:match("ESSID:%s*'([^']*)'")
		or info:match("ESSID:%s*(%S+)")
	local hwmode = info:match("HW Mode:%s*(%S+)")
	return {
		signal_dbm = tonumber(sig),
		noise_dbm = tonumber(noise),
		channel = ch,
		ssid = essid and essid:gsub("^%s+", ""):gsub("%s+$", "") or "",
		hw_mode = hwmode or "",
	}
end

-- M-4: 单一权威的 AP 接口枚举函数，action_wifi_env 和 action_wifi_rssi_data 共用
local function arx_list_ap_ifaces_wifi_env_style()
	local res = {}
	local iw = sys.exec("iw dev 2>/dev/null") or ""
	local cur_if, ssid, mode, ch, width = nil, nil, nil, nil, nil
	for line in iw:gmatch("[^\r\n]+") do
		local ifn = line:match("^%s*Interface%s+(%S+)")
		if ifn then
			if cur_if and mode == "AP" then
				table.insert(res, { ifname = cur_if, ssid = ssid or "", channel = ch, bandwidth = width or "", mode = mode })
			end
			cur_if, ssid, mode, ch, width = ifn, nil, nil, nil, nil
		end
		if cur_if then
			local s = line:match("%s*ssid%s+(.+)$")
			if s then ssid = s:gsub("^%s+", ""):gsub("%s+$", "") end
			local t = line:match("%s*type%s+(%S+)")
			if t then mode = t end
			local c = line:match("channel%s+(%d+)")
			if c then ch = c end
			local w = line:match("width%s+(%d+)%s+MHz")
			if w then width = w .. " MHz" end
		end
	end
	if cur_if and mode == "AP" then
		table.insert(res, { ifname = cur_if, ssid = ssid or "", channel = ch, bandwidth = width or "", mode = mode })
	end
	if #res == 0 and nixio.fs.access("/usr/bin/iwinfo") then
		local lst = sys.exec("iwinfo 2>/dev/null | awk '/^wlan|^phy/{print $1}' | head -8") or ""
		for ifn in lst:gmatch("%S+") do
			table.insert(res, { ifname = ifn, ssid = "", channel = nil, bandwidth = "", mode = "AP?" })
		end
	end
	return res
end

function action_wifi_env()
	http.prepare_content("application/json")
	local res = { interfaces = {} }
	-- M-4: 复用 arx_list_ap_ifaces_wifi_env_style，消除重复的 iw dev 解析逻辑
	local ifaces = arx_list_ap_ifaces_wifi_env_style()
	for _, row in ipairs(ifaces) do
		table.insert(res.interfaces, {
			ifname    = row.ifname,
			ssid      = row.ssid or "",
			channel   = row.channel,
			bandwidth = row.bandwidth or "",
			mode      = row.mode or "AP",
		})
	end
	http.write_json(res)
end

function action_wifi_rssi_data()
	http.prepare_content("application/json")
	local radios = {}
	local seen = {}
	for _, row in ipairs(arx_list_ap_ifaces_wifi_env_style()) do
		local ifn = row.ifname
		if ifn and not seen[ifn] then
			seen[ifn] = true
			local p = arx_parse_iwinfo_info(ifn)
			local chs = row.channel
			local ssid = row.ssid or ""
			local hw = ""
			if p then
				chs = p.channel or chs
				ssid = (p.ssid ~= "" and p.ssid) or ssid
				hw = p.hw_mode or ""
			end
			table.insert(radios, {
				ifname = ifn,
				ssid = ssid,
				channel = chs,
				band_hint = arx_band_hint(chs, hw),
				signal_dbm = p and p.signal_dbm or nil,
				noise_dbm = p and p.noise_dbm or nil,
				hw_mode = hw,
			})
		end
	end
	http.write_json({ radios = radios })
end