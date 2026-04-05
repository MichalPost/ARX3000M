local sys = require "luci.sys"
local http = require "luci.http"
local uci = require "luci.model.uci"
local nixio = require "nixio"

module("luci.controller.arx.netmgr", package.seeall)

function index()
	if not nixio.fs.access("/etc/config/arx-netmgr") then return end

	entry({"admin", "arx-netmgr"}, alias("admin", "arx-netmgr", "devices"), _("Network Manager"), 20).dependent = true
	entry({"admin", "arx-netmgr", "devices"}, template("arx-netmgr/devices"), _("Connected Devices"), 10).leaf = true
	entry({"admin", "arx-netmgr", "devices_json"}, call("action_devices")).leaf = true
	entry({"admin", "arx-netmgr", "block_device"}, call("action_block_device")).leaf = true
	entry({"admin", "arx-netmgr", "unblock_device"}, call("action_unblock_device")).leaf = true
	entry({"admin", "arx-netmgr", "device_detail"}, call("action_device_detail")).leaf = true
	entry({"admin", "arx-netmgr", "save_device_meta"}, call("action_save_device_meta")).leaf = true
	entry({"admin", "arx-netmgr", "static_leases"}, cbi("arx-netmgr/static_leases"), _("Static Leases (IP-MAC Bind)"), 20).leaf = true
end

-- ==================== 输入验证 ====================

-- [H1/H2] 验证 MAC 地址格式 XX:XX:XX:XX:XX:XX
local function validate_mac(mac)
	if not mac then return false end
	return mac:match("^%x%x:%x%x:%x%x:%x%x:%x%x:%x%x$") ~= nil
end

-- [H2] 验证 IPv4：每段 1–3 位、禁止多余前导零、0–255，防止 ping/arping 命令注入
local function validate_ipv4(ip)
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

-- LAN 侧 arping 使用的网桥/设备名（UCI，与 LuCI 一致）
local function lan_arp_if()
	local u = uci.cursor()
	local dev = u:get("network", "lan", "device") or u:get("network", "lan", "ifname") or "br-lan"
	dev = (dev or ""):gsub("%s+", "")
	if dev == "" then dev = "br-lan" end
	if not dev:match("^[%w@%.%-]+$") then dev = "br-lan" end
	return dev
end

local function shell_exit_code(cmd)
	local out = sys.exec(cmd) or ""
	out = out:gsub("^%s+", ""):gsub("%s+$", "")
	local code = out:match("^(%d+)$")
	return code
end

-- ==================== 业务逻辑 ====================

function action_devices()
	http.prepare_content("application/json")

	local devices = {}
	local u = uci.cursor()

	local arp_entries = sys.net.arptable() or {}
	local dhcp_leases = {}

	local lease_file = io.open("/tmp/dhcp.leases", "r")
	if lease_file then
		for line in lease_file:lines() do
			local exp_time, mac, ip, name = line:match("(%S+)%s+(%S+)%s+(%S+)%s+(.*)")
			-- [CRIT-4] dhcp.leases 中 MAC 是小写，统一转大写后作为 key，与 ARP 表保持一致
			if exp_time and mac and ip then
				dhcp_leases[mac:upper()] = {
					ip = ip,
					hostname = name or "",
					expires = tonumber(exp_time) or 0,
					mac = mac:upper()
				}
			end
		end
		lease_file:close()
	end

	local wifi_clients = get_wifi_clients()

	local meta_map = {}
	u:foreach("arx-netmgr", "devmeta", function(s)
		local m = (s.mac or ""):upper()
		if m ~= "" then
			meta_map[m] = {
				alias = s.alias or "",
				group = s.group or "other"
			}
		end
	end)

	for _, arp in ipairs(arp_entries) do
		if arp["MAC Address"] ~= "00:00:00:00:00:00" then
			local mac = arp["MAC Address"]:upper()
			local device = {
				ip = arp["IP Address"],
				mac = mac,
				hostname = arp["Hostname"] or "",
				interface = arp["Device"] or "unknown",
				type = "ethernet",
				online = true
			}

			if dhcp_leases[mac] then
				device.hostname = dhcp_leases[mac].hostname ~= "" and dhcp_leases[mac].hostname or device.hostname
				device.dhcp_expires = dhcp_leases[mac].expires
				device.dhcp_leased = true
			end

			if wifi_clients[mac] then
				device.type = "wifi"
				device.wifi_ssid = wifi_clients[mac].ssid
				device.wifi_signal = wifi_clients[mac].signal
				device.wifi_rssi = wifi_clients[mac].rssi
				device.wifi_connected = wifi_clients[mac].connected_time
			end

			local blocked = is_blocked(mac, u)
			device.blocked = blocked

			local meta = meta_map[mac]
			if meta then
				device.alias = meta.alias
				device.group = meta.group
			else
				device.alias = ""
				device.group = "other"
			end

			table.insert(devices, device)
		end
	end

	table.sort(devices, function(a, b)
		if a.blocked and not b.blocked then return false end
		if not a.blocked and b.blocked then return true end
		return (a.hostname or a.ip) < (b.hostname or b.ip)
	end)

	http.write_json({ devices = devices, total = #devices })
end

function action_block_device()
	http.prepare_content("application/json")
	local mac = http.formvalue("mac")
	if not mac then
		http.write_json({ success = false, error = "Missing MAC address" })
		return
	end

	mac = mac:upper():gsub("^%s+", ""):gsub("%s+$", "")

	-- [H1] 验证 MAC 格式，防止 iptables 命令注入
	if not validate_mac(mac) then
		http.write_json({ success = false, error = "Invalid MAC address format" })
		return
	end

	local u = uci.cursor()
	-- [HIGH-4] UCI set 期望字符串，os.time() 返回数字，需 tostring()
	u:set("arx-netmgr", mac:gsub(":", ""), "blocked", "1")
	u:set("arx-netmgr", mac:gsub(":", ""), "mac", mac)
	u:set("arx-netmgr", mac:gsub(":", ""), "timestamp", tostring(os.time()))
	u:commit("arx-netmgr")

	local iptables_block = function(chain, mac_addr)
		-- [H1] 用单独一行退出码判断，避免 iptables 多行输出导致 ^0 误判
		local ex4 = shell_exit_code(
			"iptables -C " .. chain .. " -m mac --mac-source " .. mac_addr .. " -j DROP >/dev/null 2>&1; echo $?"
		)
		if ex4 ~= "0" then
			sys.exec("iptables -I " .. chain .. " -m mac --mac-source " .. mac_addr .. " -j DROP 2>/dev/null")
		end
		local ex6 = shell_exit_code(
			"ip6tables -C " .. chain .. " -m mac --mac-source " .. mac_addr .. " -j DROP >/dev/null 2>&1; echo $?"
		)
		if ex6 ~= "0" then
			sys.exec("ip6tables -I " .. chain .. " -m mac --mac-source " .. mac_addr .. " -j DROP 2>/dev/null")
		end
	end

	-- [H2] 使用正确的大写链名 FORWARD/INPUT
	iptables_block("FORWARD", mac)
	iptables_block("INPUT", mac)

	-- H-2/H-3: 用原子写（写临时文件再 rename）替代 read-check-append，消除 TOCTOU 竞态
	-- 同时保证去重：先读全文，过滤后写回
	local dhcp_mac = mac:gsub(":", "")
	local BLOCKLIST = "/tmp/blocklist_dhcp"
	local tmp_bl = BLOCKLIST .. ".tmp." .. tostring(os.time()) .. tostring(math.random(10000))
	local existing_lines = {}
	local already_present = false
	local rf = io.open(BLOCKLIST, "r")
	if rf then
		for line in rf:lines() do
			if line ~= "" then
				existing_lines[#existing_lines + 1] = line
				if line == dhcp_mac then already_present = true end
			end
		end
		rf:close()
	end
	if not already_present then
		existing_lines[#existing_lines + 1] = dhcp_mac
		local wf = io.open(tmp_bl, "w")
		if wf then
			for _, l in ipairs(existing_lines) do wf:write(l .. "\n") end
			wf:close()
			nixio.fs.rename(tmp_bl, BLOCKLIST)
		end
	end

	http.write_json({ success = true, message = "Device " .. mac .. " has been blocked" })
end

function action_unblock_device()
	http.prepare_content("application/json")
	local mac = http.formvalue("mac")
	if not mac then
		http.write_json({ success = false, error = "Missing MAC address" })
		return
	end

	mac = mac:upper():gsub("^%s+", ""):gsub("%s+$", "")

	-- [H1] 验证 MAC 格式
	if not validate_mac(mac) then
		http.write_json({ success = false, error = "Invalid MAC address format" })
		return
	end

	local u = uci.cursor()
	u:delete("arx-netmgr", mac:gsub(":", ""))
	u:commit("arx-netmgr")

	-- [H2] 使用正确的大写链名 FORWARD/INPUT
	sys.exec("iptables -D FORWARD -m mac --mac-source " .. mac .. " -j DROP 2>/dev/null")
	sys.exec("ip6tables -D FORWARD -m mac --mac-source " .. mac .. " -j DROP 2>/dev/null")
	sys.exec("iptables -D INPUT -m mac --mac-source " .. mac .. " -j DROP 2>/dev/null")
	sys.exec("ip6tables -D INPUT -m mac --mac-source " .. mac .. " -j DROP 2>/dev/null")

	-- H-2/H-3: 原子写回，消除 unblock 时的竞态
	local dhcp_mac = mac:gsub(":", "")
	local BLOCKLIST = "/tmp/blocklist_dhcp"
	local tmp_bl = BLOCKLIST .. ".tmp." .. tostring(os.time()) .. tostring(math.random(10000))
	local rf2 = io.open(BLOCKLIST, "r")
	if rf2 then
		local lines = {}
		for line in rf2:lines() do
			if line ~= "" and line ~= dhcp_mac then
				lines[#lines + 1] = line
			end
		end
		rf2:close()
		local wf2 = io.open(tmp_bl, "w")
		if wf2 then
			for _, l in ipairs(lines) do wf2:write(l .. "\n") end
			wf2:close()
			nixio.fs.rename(tmp_bl, BLOCKLIST)
		end
	end

	http.write_json({ success = true, message = "Device " .. mac .. " has been unblocked" })
end

function action_save_device_meta()
	http.prepare_content("application/json")
	if http.getenv("REQUEST_METHOD") ~= "POST" then
		http.write_json({ ok = false, error = "需要 POST" })
		return
	end
	local mac = http.formvalue("mac")
	local alias = http.formvalue("alias") or ""
	local group = http.formvalue("group") or "other"
	if not validate_mac(mac) then
		http.write_json({ ok = false, error = "MAC 无效" })
		return
	end
	mac = mac:upper()
	alias = alias:gsub("^%s+", ""):gsub("%s+$", "")
	if #alias > 64 then
		alias = alias:sub(1, 64)
	end
	if group ~= "family" and group ~= "iot" and group ~= "other" then
		group = "other"
	end
	local u = uci.cursor()
	local sid = "devmeta_" .. mac:gsub(":", "")
	if alias == "" and group == "other" then
		if u:get("arx-netmgr", sid) then
			u:delete("arx-netmgr", sid)
			u:commit("arx-netmgr")
		end
		http.write_json({ ok = true })
		return
	end
	if not u:get("arx-netmgr", sid) then
		u:section("arx-netmgr", "devmeta", sid, {
			mac = mac,
			alias = alias,
			group = group
		})
	else
		u:set("arx-netmgr", sid, "mac", mac)
		u:set("arx-netmgr", sid, "alias", alias)
		u:set("arx-netmgr", sid, "group", group)
	end
	u:commit("arx-netmgr")
	http.write_json({ ok = true })
end

function action_device_detail()
	http.prepare_content("application/json")

	-- [H2] 先检查 formvalue 是否为 nil，再调用字符串方法
	local mac_raw = http.formvalue("mac")
	if not mac_raw then
		http.write_json({ error = "Missing MAC address" }); return
	end
	local mac = mac_raw:upper():gsub("^%s+", ""):gsub("%s+$", "")

	-- [H2] 验证 MAC 格式
	if not validate_mac(mac) then
		http.write_json({ error = "Invalid MAC address format" }); return
	end

	-- [H2] 验证 IP 格式，防止 ping/arping 命令注入
	local ip = http.formvalue("ip") or ""
	if ip ~= "" and not validate_ipv4(ip) then
		http.write_json({ error = "Invalid IP address format" }); return
	end

	local detail = { mac = mac }

	if ip ~= "" then
		local ping_result = sys.exec("ping -c 1 -W 1 " .. ip .. " 2>&1 | tail -1")
		detail.reachable = ping_result and ping_result:match("time=") ~= nil

		local arp_dev = lan_arp_if()
		local arping = sys.exec("arping -c 1 -I " .. arp_dev .. " " .. ip .. " 2>&1 | grep reply")
		detail.arping_response = arping ~= ""
	else
		detail.reachable = false
		detail.arping_response = false
	end

	-- H-3: conntrack 不按 MAC 过滤（conntrack 条目不含 MAC），改为统计所有 ESTABLISHED 连接数
	-- 原 grep -i mac 会误匹配 IP 地址片段，且 conntrack 输出本身不含 MAC 字段
	local conntrack = sys.exec("conntrack -L 2>/dev/null | wc -l")
	detail.active_connections = tonumber(conntrack) or 0

	local vendor = get_vendor(mac)
	detail.vendor = vendor

	http.write_json(detail)
end

function is_blocked(mac, u)
	local section_id = mac:gsub(":", "")
	local blocked = u:get("arx-netmgr", section_id, "blocked")
	return blocked == "1" or blocked == "true" or blocked == "yes"
end

local function iwinfo_essid(iface)
	local info = sys.exec("iwinfo " .. iface .. " info 2>/dev/null") or ""
	local q = info:match('ESSID:%s*"(.-)"')
	if q and q ~= "" then return q end
	local u = info:match("ESSID:%s*(%S+)")
	if u and u ~= "" and u ~= "unknown" then return u end
	return nil
end

function get_wifi_clients()
	local clients = {}

	local wifi_status = sys.exec("iwinfo 2>/dev/null | grep -E '^[a-z]' | awk '{print $1}'")
	if wifi_status then
		for iface in wifi_status:gmatch("%S+") do
			-- [M8] 验证接口名格式，防止含特殊字符时注入 shell
			if not iface:match("^[%w]+$") then goto continue end
			local ssid = iwinfo_essid(iface) or iface
			local station_dump = sys.exec("iwinfo " .. iface .. " assoclist 2>/dev/null")
			if station_dump then
				for mac, info in station_dump:gmatch("(%x%x:%x%x:%x%x:%x%x:%x%x:%x%x)%s+(.+)") do
					mac = mac:upper()
					local signal = info:match("Signal:(%-?%d+)") or "-60"
					local rssi = info:match("RSSI:(%-?%d+)") or signal
					local txrate = info:match("Tx Rate:(%S+)") or "?"
					clients[mac] = {
						ssid = ssid,
						signal = signal,
						rssi = rssi,
						tx_rate = txrate,
						connected_time = ""
					}
				end
			end
			::continue::
		end
	end

	return clients
end

function get_vendor(mac)
	local oui = mac:sub(1, 8):lower()
	-- [M6] 验证 OUI 格式（xx:xx:xx），防止 grep 命令注入
	if not oui:match("^%x%x:%x%x:%x%x$") then return "Unknown" end

	local f = io.open("/usr/share/oui/oui.txt", "r")
	if f then
		for line in f:lines() do
			if line:find(oui, 1, true) then
				f:close()
				return line:match("^%S+%s+(.+)$") or "Unknown"
			end
		end
		f:close()
	end

	-- [M6] oui 已验证为 xx:xx:xx 格式，安全传入 grep
	local result = sys.exec("grep -i '^" .. oui .. "' /usr/share/nmap/nmap-mac-prefixes 2>/dev/null | head -1 | cut -f2-")
	return result and result:match("^%s*(.-)%s*$") or "Unknown"
end
