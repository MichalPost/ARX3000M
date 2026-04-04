local sys = require "luci.sys"
local http = require "luci.http"
local uci = require "luci.model.uci"
local nixio = require "nixio"

module("luci.controller.arx.bridge", package.seeall)

-- [C1] 网络设备名白名单，防止注入 shell / 路径遍历
local function safe_netdev(n)
	if not n or n == "" then return nil end
	if not n:match("^[%w_%-%.@]+$") then return nil end
	return n
end

local function netdev_ipv4(dev)
	dev = safe_netdev(dev)
	if not dev then return nil end
	local out = sys.exec("ip -4 -o addr show dev " .. dev .. " 2>/dev/null") or ""
	local ip = out:match("inet%s+([%d%.]+)")
	return ip
end

local function netdev_up(dev)
	dev = safe_netdev(dev)
	if not dev then return false end
	local f = io.open("/sys/class/net/" .. dev .. "/operstate", "r")
	if not f then return false end
	local st = f:read("*l") or ""
	f:close()
	st = st:gsub("%s+", "")
	return st == "up"
end

local function default_route()
	local line = sys.exec("ip -4 route show default 0.0.0.0/0 2>/dev/null | head -1") or ""
	line = line:gsub("%s+$", "")
	local via, dev = line:match("default%s+via%s+(%S+)%s+dev%s+(%S+)")
	if not dev then
		dev = line:match("default%s+dev%s+(%S+)")
	end
	if not dev then return nil, nil end
	if not safe_netdev(dev) then return nil, nil end
	return via, dev
end

local function wan_device(u)
	local dev = u:get("network", "wan", "device")
		or u:get("network", "wan", "ifname")
	if dev and dev:match("^@") then
		local x = dev:match("^@(%S+)")
		if x then dev = u:get("network", x, "device") or u:get("network", x, "ifname") end
	end
	return safe_netdev(dev)
end

function index()
	if not nixio.fs.access("/etc/config/arx-bridge") then return end

	entry({"admin", "arx-bridge"}, alias("admin", "arx-bridge", "overview"), _("上行 / 桥接"), 26).dependent = true
	entry({"admin", "arx-bridge", "overview"}, template("arx-bridge/overview"), _("概览"), 10).leaf = true
	entry({"admin", "arx-bridge", "status"}, call("action_status")).leaf = true
end

function action_status()
	http.prepare_content("application/json")
	local u = uci.cursor()
	local out = {
		wan = {},
		wifi_sta = {},
		relayd = { config = false, relay_count = 0 },
		mwan3 = { config = false, interface_count = 0 },
		travelmate = { config = false },
		default_route = {}
	}

	local wdev = wan_device(u)
	local proto = u:get("network", "wan", "proto") or "?"
	out.wan = {
		section = "wan",
		proto = proto,
		device = wdev or "",
		up = wdev and netdev_up(wdev) or false,
		ipv4 = wdev and netdev_ipv4(wdev) or nil
	}

	local via, drdev = default_route()
	out.default_route = {
		via = via or "",
		dev = drdev or ""
	}

	u:foreach("wireless", "wifi-iface", function(s)
		if (s.mode or "") == "sta" then
			local net = s.network or ""
			local ndev = ""
			if net ~= "" then
				ndev = u:get("network", net, "device")
					or u:get("network", net, "ifname") or ""
			end
			local sdev = safe_netdev(ndev) or ""
			table.insert(out.wifi_sta, {
				iface_section = s[".name"],
				network = net,
				ssid = s.ssid or "",
				disabled = (s.disabled == "1"),
				device = s.device or "",
				net_device = sdev,
				ipv4 = sdev ~= "" and netdev_ipv4(sdev) or nil,
				net_up = sdev ~= "" and netdev_up(sdev) or false
			})
		end
	end)

	if nixio.fs.access("/etc/config/relayd") then
		out.relayd.config = true
		pcall(function()
			u:foreach("relayd", "relay", function()
				out.relayd.relay_count = out.relayd.relay_count + 1
			end)
		end)
	end

	if nixio.fs.access("/etc/config/mwan3") then
		out.mwan3.config = true
		pcall(function()
			u:foreach("mwan3", "interface", function()
				out.mwan3.interface_count = out.mwan3.interface_count + 1
			end)
		end)
	end

	if nixio.fs.access("/etc/config/travelmate") then
		out.travelmate.config = true
		local raw = sys.exec("ubus call travelmate status 2>/dev/null") or ""
		if raw:match("%S") then
			local jsonc = require "luci.jsonc"
			local ok, j = pcall(jsonc.parse, raw)
			if ok and j and type(j) == "table" then
				out.travelmate.ssid = j.ssid or j.bssid
				out.travelmate.radio = j.radio
				out.travelmate.iface = j.iface
				out.travelmate.signal = j.signal
			end
		end
	end

	http.write_json(out)
end
