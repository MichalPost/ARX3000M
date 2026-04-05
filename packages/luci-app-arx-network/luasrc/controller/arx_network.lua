local sys = require "luci.sys"
local http = require "luci.http"
local uci = require "luci.model.uci"
local nixio = require "nixio"
module("luci.controller.arx.network", package.seeall)

-- 与 netmgr 一致：禁止多余前导零、每段 0–255
local function validate_ipv4_strict(ip)
	if not ip or ip == "" then return false end
	local a, b, c, d = ip:match("^(%d%d?%d?)%.(%d%d?%d?)%.(%d%d?%d?)%.(%d%d?%d?)$")
	if not a then return false end
	local function oct(s)
		if #s > 1 and s:sub(1, 1) == "0" then return false end
		local n = tonumber(s)
		return n ~= nil and n >= 0 and n <= 255
	end
	return oct(a) and oct(b) and oct(c) and oct(d)
end

-- 保守 IPv6 校验（供 ping/traceroute）；支持可选 zone id（%iface），校验前剥离
local function validate_ipv6_lite(ip)
	if not ip or ip == "" then return false end
	if ip:sub(1, 1) == "[" and ip:sub(-1) == "]" then
		ip = ip:sub(2, -2)
	end
	if ip == "" or #ip > 50 then return false end
	local zone
	if ip:find("%%", 1, true) then
		local core, z = ip:match("^(.-)%%([^%%]+)$")
		if not core or core == "" or not z or z == "" then return false end
		ip = core
		zone = z
	end
	if zone and #zone > 32 then return false end
	if not ip:find(":", 1, true) then return false end
	if ip:find("[^%x:]") then return false end
	if ip:find(":::", 1, true) then return false end
	local _, dc = ip:gsub("::", "")
	if dc > 1 then return false end
	if not ip:find("%x") then return false end

	local function seg_ok(seg)
		return seg ~= nil and seg:match("^%x%x?%x?%x?$") ~= nil
	end
	local left, right = ip:match("^(.-)::(.*)$")
	if left then
		local ln, rn = 0, 0
		if left ~= "" then
			for seg in left:gmatch("[^:]+") do
				if not seg_ok(seg) then return false end
				ln = ln + 1
			end
		end
		if right ~= "" then
			for seg in right:gmatch("[^:]+") do
				if not seg_ok(seg) then return false end
				rn = rn + 1
			end
		end
		if ln + rn > 8 then return false end
		return true
	end
	local n = 0
	for seg in ip:gmatch("[^:]+") do
		if not seg_ok(seg) then return false end
		n = n + 1
	end
	return n == 8
end

-- [C1] 验证主机名/IP，防止命令注入（主机名含下划线；支持 IPv4/IPv6）
local function validate_host(h)
	if not h or h == "" then return false end
	if validate_ipv4_strict(h) then return true end
	if validate_ipv6_lite(h) then return true end
	if h:find(":", 1, true) then return false end
	if h:match("^%d+$") then return false end
	if not h:match("%a") then return false end
	return #h <= 253 and h:match("^[%a%d%.%-_]+$") ~= nil
end

-- [C1] 验证 ping count，限制 1-10
local function validate_count(c)
	local n = tonumber(c)
	return n and n >= 1 and n <= 10
end

function index()
	if not nixio.fs.access("/etc/config/arx-network") then return end

	entry({"admin", "arx-network"}, alias("admin", "arx-network", "overview"), _("Network Tools"), 30).dependent = true
	entry({"admin", "arx-network", "overview"}, template("arx-network/overview"), _("Overview"), 10).leaf = true
	entry({"admin", "arx-network", "portfw"}, cbi("arx-network/port_forward"), _("Port Forwarding"), 20).leaf = true
	entry({"admin", "arx-network", "firewall_rules"}, cbi("arx-network/firewall"), _("Firewall Rules"), 30).leaf = true
	entry({"admin", "arx-network", "ddns_status"}, call("action_ddns_status")).leaf = true
	entry({"admin", "arx-network", "upnp_status"}, call("action_upnp_status")).leaf = true
	entry({"admin", "arx-network", "diagnostics"}, template("arx-network/diagnostics"), _("Diagnostics"), 50).leaf = true
	entry({"admin", "arx-network", "diag_ping"}, call("action_diag_ping")).leaf = true
	entry({"admin", "arx-network", "diag_traceroute"}, call("action_diag_traceroute")).leaf = true
	entry({"admin", "arx-network", "diag_nslookup"}, call("action_diag_nslookup")).leaf = true
	entry({"admin", "arx-network", "diag_netstat"}, call("action_diag_netstat")).leaf = true
	entry({"admin", "arx-network", "diag_bundle"}, call("action_diag_bundle")).leaf = true
end

local function ddns_init_unit_running(unit)
	if not sys.init or not sys.init.enabled then return false end
	local ok, r = pcall(function() return sys.init.enabled(unit) end)
	return ok and r
end

function action_ddns_status()
	http.prepare_content("application/json")
	local ddns_services = {}

	local u = uci.cursor()
	u:foreach("ddns", "service", function(s)
		local eu = "disabled"
		if s.enabled == "1" then
			eu = ddns_init_unit_running("ddns_" .. s[".name"]) and "running" or "stopped"
		end
		table.insert(ddns_services, {
			name = s[".name"],
			-- [H6] s.enabled 是字符串，非空字符串在 Lua 中均为 truthy，必须与 "1" 比较
			enabled = s.enabled == "1",
			domain = s.domain or s.lookup_host or "-",
			service = s.service_name or "-",
			last_update = s.last_update or "never",
			force_seconds = s.force_seconds or 0,
			enabled_unit = eu
		})
	end)

	http.write_json({ services = ddns_services })
end

function action_upnp_status()
	http.prepare_content("application/json")

	local upnp_status = {
		running = sys.exec("pgrep -f miniupnpd >/dev/null && echo 1 || echo 0"):match("1") == "1",
		rules = {},
		total_redirects = 0,
		total_bytes_in = 0,
		total_bytes_out = 0,
		parse_warning = false
	}

	if upnp_status.running then
		local rules_raw = sys.exec("upnpc -l 2>/dev/null") or ""

		for line in rules_raw:gmatch("[^\r\n]+") do
			-- [M-4] upnpc -l 输出格式：  0 TCP  54321->192.168.1.100:8080  'desc'  1800
			-- 用更宽松的模式匹配，兼容不同版本 upnpc 的输出差异
			local proto, ext_port, int_addr, desc, dur =
				line:match("%s*%d+%s+(%a+)%s+(%d+)%s*%->%s*(%S+)%s+'([^']*)'%s+(%d+)")
			if not proto then
				-- 备用格式（无引号描述）
				proto, ext_port, int_addr, dur =
					line:match("%s*%d+%s+(%a+)%s+(%d+)%s*%->%s*(%S+)%s+(%d+)")
				desc = ""
			end
			if proto and ext_port then
				local int_ip = int_addr and int_addr:match("^([^:]+)") or int_addr or ""
				table.insert(upnp_status.rules, {
					protocol = proto,
					ext_port = ext_port,
					int_ip = int_ip,
					description = desc or "",
					duration = dur or ""
				})
				upnp_status.total_redirects = upnp_status.total_redirects + 1
			end

			local bytes_in_str, bytes_out_str = line:match("Bytes:%s*[(](%d+)[)]%s*[(](%d+)[)]")
			if bytes_in_str then
				upnp_status.total_bytes_in = tonumber(bytes_in_str) or 0
				upnp_status.total_bytes_out = tonumber(bytes_out_str) or 0
			end
		end
		if rules_raw:match("%S") and upnp_status.total_redirects == 0 then
			upnp_status.parse_warning = true
		end
	end

	http.write_json(upnp_status)
end

function action_diag_ping()
	http.prepare_content("text/plain")
	local host = http.formvalue("host") or "8.8.8.8"
	local count = http.formvalue("count") or "4"
	-- [C1] 验证输入，防止命令注入
	if not validate_host(host) then http.write("Invalid host"); return end
	if not validate_count(count) then count = "4" end
	count = tostring(math.floor(tonumber(count)))
	local target = host
	if target:sub(1, 1) == "[" and target:sub(-1) == "]" then
		target = target:sub(2, -2)
	end
	local result
	if validate_ipv6_lite(host) then
		result = sys.exec("ping6 -c " .. count .. " -W 3 " .. target .. " 2>&1")
	else
		result = sys.exec("ping -c " .. count .. " -W 3 " .. target .. " 2>&1")
	end
	http.write(result or "Ping failed")
end

function action_diag_traceroute()
	http.prepare_content("text/plain")
	local host = http.formvalue("host") or "8.8.8.8"
	if not validate_host(host) then http.write("Invalid host"); return end
	-- [H-2] 缩短阻塞时间，避免长时间占满 uhttpd worker（约 5s 量级上限）
	local target = host
	if target:sub(1, 1) == "[" and target:sub(-1) == "]" then
		target = target:sub(2, -2)
	end
	local result
	if validate_ipv6_lite(host) then
		local bin = nil
		if sys.exec("command -v traceroute6 >/dev/null 2>&1 && echo y"):match("y") then
			bin = "traceroute6"
		elseif sys.exec("command -v traceroute >/dev/null 2>&1 && echo y"):match("y") then
			bin = "traceroute -6"
		end
		if not bin then
			http.write("Traceroute6 not available")
			return
		end
		result = sys.exec("timeout 5 " .. bin .. " -n -w 1 -q 1 -m 8 " .. target .. " 2>&1")
	else
		result = sys.exec("timeout 5 traceroute -n -w 1 -q 1 -m 8 " .. target .. " 2>&1")
	end
	http.write(result or "Traceroute failed")
end

function action_diag_nslookup()
	http.prepare_content("text/plain")
	local host = http.formvalue("host") or "openwrt.org"
	-- [C1] 验证输入，防止命令注入
	if not validate_host(host) then http.write("Invalid host"); return end
	local result = sys.exec("nslookup " .. host .. " 2>&1")
	http.write(result or "NSLookup failed")
end

function action_diag_netstat()
	http.prepare_content("application/json")
	local connections = {}

	local function parse_line(line)
		-- netstat: tcp 0 0 local remote ESTABLISHED
		local proto, recv_q, send_q, local_addr, remote_addr, state =
			line:match("(%S+)%s+(%d+)%s+(%d+)%s+(%S+)%s+(%S+)%s+(%S+)")
		if proto then
			table.insert(connections, {
				proto = proto,
				local_addr = local_addr,
				remote_addr = remote_addr,
				state = state,
				recv_q = recv_q,
				send_q = send_q
			})
			return
		end
		-- ss: ESTAB 0 0 local peer（无独立 proto 列）
		local st, rq, sq, la, ra = line:match("^(%S+)%s+(%d+)%s+(%d+)%s+(%S+)%s+(%S+)%s*$")
		if st and la then
			table.insert(connections, {
				proto = "tcp",
				local_addr = la,
				remote_addr = ra,
				state = st,
				recv_q = rq,
				send_q = sq
			})
		end
	end

	-- 优先 ss（BusyBox/OpenWrt 上列更稳定），回退 netstat + grep
	local raw = sys.exec("command -v ss >/dev/null 2>&1 && ss -H -tn state established 2>/dev/null | head -50") or ""
	if raw == "" or not raw:match("%S") then
		raw = sys.exec("netstat -tn 2>/dev/null | grep ESTABLISHED | head -50") or ""
	end
	for line in raw:gmatch("[^\r\n]+") do
		parse_line(line)
	end

	http.write_json({ connections = connections, total = #connections })
end

local function sanitize_diag_text(t)
	if not t or t == "" then return "" end
	-- [M8] 覆盖所有常见 UCI 密码/密钥字段名（单引号、双引号、无引号格式）
	local pwd_keys = { "password", "key", "passphrase", "psk", "secret", "passwd", "pin" }
	for _, k in ipairs(pwd_keys) do
		t = t:gsub("option%s+" .. k .. "%s+'[^']*'", "option " .. k .. " '***'")
		t = t:gsub('option%s+' .. k .. '%s+"[^"]*"', 'option ' .. k .. ' "***"')
		t = t:gsub("option%s+" .. k .. "%s+(%S+)", "option " .. k .. " '***'")
	end
	-- [M-3] 单次扫描替换 MAC，避免多模式 gsub 边界重叠导致重复脱敏
	local macpat = "%x%x:%x%x:%x%x:%x%x:%x%x:%x%x"
	local pos = 1
	while pos <= #t do
		local i, j = t:find(macpat, pos)
		if not i then break end
		local bef = (i > 1) and t:sub(i - 1, i - 1) or ""
		local aft = (j < #t) and t:sub(j + 1, j + 1) or ""
		local edge_ok = (bef == "" or not bef:match("[%x:]"))
			and (aft == "" or not aft:match("[%x:]"))
		if edge_ok then
			local mac = t:sub(i, j)
			local rep = mac:sub(1, 8) .. ":xx:xx:xx"
			t = t:sub(1, i - 1) .. rep .. t:sub(j + 1)
			pos = i + #rep
		else
			pos = j + 1
		end
	end
	return t
end

function action_diag_bundle()
	if (http.getenv("REQUEST_METHOD") or ""):upper() ~= "POST" then
		http.status(405, "Method Not Allowed")
		http.prepare_content("text/plain; charset=utf-8")
		http.write("Method Not Allowed")
		return
	end
	local qdl = http.formvalue("download")
	if qdl == "1" then
		http.header("Content-Disposition", "attachment; filename=arx-network-diag.txt")
	end
	http.prepare_content("text/plain; charset=utf-8")
	local chunks = {}
	local function add(title, body)
		table.insert(chunks, "=== " .. title .. " ===\n")
		table.insert(chunks, sanitize_diag_text(body or "") .. "\n\n")
	end
	add("uname", sys.exec("uname -a 2>/dev/null"))
	add("uptime", sys.exec("cat /proc/uptime 2>/dev/null"))
	add("wan (ifstatus)", sys.exec("ifstatus wan 2>/dev/null"))
	add("ubus wan", sys.exec("ubus call network.interface.wan status 2>/dev/null"))
	add("logread (tail)", sys.exec("logread -l 50 2>/dev/null"))
	add("dmesg (tail)", sys.exec("dmesg 2>/dev/null | tail -c 8192"))
	add("routes", sys.exec("ip route 2>/dev/null | head -40"))
	http.write(table.concat(chunks, ""))
end
