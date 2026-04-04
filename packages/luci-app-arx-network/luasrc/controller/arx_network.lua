local sys = require "luci.sys"
local http = require "luci.http"
local uci = require "luci.model.uci"
local nixio = require "nixio"
module("luci.controller.arx.network", package.seeall)

-- [C1] 验证主机名/IP，防止命令注入
local function validate_host(h)
	if not h or h == "" then return false end
	if h:match("^%d+%.%d+%.%d+%.%d+$") then
		local a,b,c,d = h:match("^(%d+)%.(%d+)%.(%d+)%.(%d+)$")
		a,b,c,d = tonumber(a),tonumber(b),tonumber(c),tonumber(d)
		return a<=255 and b<=255 and c<=255 and d<=255
	end
	return #h <= 253 and h:match("^[%w%.%-]+$") ~= nil
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

function action_ddns_status()
	http.prepare_content("application/json")
	local ddns_services = {}

	local u = uci.cursor()
	u:foreach("ddns", "service", function(s)
		table.insert(ddns_services, {
			name = s[".name"],
			-- [H6] s.enabled 是字符串，非空字符串在 Lua 中均为 truthy，必须与 "1" 比较
			enabled = s.enabled == "1",
			domain = s.domain or s.lookup_host or "-",
			service = s.service_name or "-",
			last_update = s.last_update or "never",
			force_seconds = s.force_seconds or 0,
			enabled_unit = s.enabled == "1" and (sys.init.enabled("ddns_" .. s[".name"]) and "running" or "stopped") or "disabled"
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
		total_bytes_out = 0
	}

	if upnp_status.running then
		local rules_raw = sys.exec("upnpc -l 2>/dev/null") or ""

		for line in rules_raw:gmatch("[^\r\n]+") do
			local proto, port, ip, desc, remaining = line:match("(%w+)%s+[%[->]%s+(%d+)%s+(%S+)%s+(.*)%s+%((%d+)%)")
			if proto and port then
				table.insert(upnp_status.rules, {
					protocol = proto,
					ext_port = port,
					int_ip = ip,
					description = desc or "",
					duration = remaining or ""
				})
				upnp_status.total_redirects = upnp_status.total_redirects + 1
			end

			local bytes_in_str, bytes_out_str = line:match("Bytes:%s*[(](%d+)[)]%s*[(](%d+)[)]")
			if bytes_in_str then
				upnp_status.total_bytes_in = tonumber(bytes_in_str) or 0
				upnp_status.total_bytes_out = tonumber(bytes_out_str) or 0
			end
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
	local result = sys.exec("ping -c " .. count .. " -W 3 " .. host .. " 2>&1")
	http.write(result or "Ping failed")
end

function action_diag_traceroute()
	http.prepare_content("text/plain")
	local host = http.formvalue("host") or "8.8.8.8"
	-- [C1] 验证输入，防止命令注入
	if not validate_host(host) then http.write("Invalid host"); return end
	local result = sys.exec("traceroute -n -w 2 -q 1 -m 15 " .. host .. " 2>&1")
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

	local netstat_output = sys.exec("netstat -tn 2>/dev/null | grep ESTABLISHED | head -50") or ""
	for line in netstat_output:gmatch("[^\r\n]+") do
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
		end
	end

	http.write_json({ connections = connections, total = #connections })
end

local function sanitize_diag_text(t)
	if not t or t == "" then return "" end
	-- [M8] 覆盖所有常见 UCI 密码/密钥字段名（单引号和双引号格式）
	local pwd_keys = { "password", "key", "passphrase", "psk", "secret", "passwd", "pin" }
	for _, k in ipairs(pwd_keys) do
		t = t:gsub("option%s+" .. k .. "%s+'[^']*'", "option " .. k .. " '***'")
		t = t:gsub('option%s+' .. k .. '%s+"[^"]*"', 'option ' .. k .. ' "***"')
	end
	-- [MED-4] MAC 脱敏：精确匹配 6 组 xx:xx:xx:xx:xx:xx（每组恰好 2 位十六进制），
	-- 避免误匹配 IPv6 地址（IPv6 每组 1-4 位，且分隔符为 :，但组数不同）
	-- 使用词边界锚定：前后不能是十六进制字符或冒号
	t = t:gsub("(%x%x:%x%x:%x%x):%x%x:%x%x:%x%x", function(oui)
		return oui .. ":xx:xx:xx"
	end)
	return t
end

function action_diag_bundle()
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
	add("dmesg (tail)", sys.exec("dmesg 2>/dev/null | tail -n 35"))
	add("routes", sys.exec("ip route 2>/dev/null | head -40"))
	http.write(table.concat(chunks, ""))
end
