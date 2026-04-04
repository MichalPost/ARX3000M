local sys = require "luci.sys"
local http = require "luci.http"
local uci = require "luci.model.uci"
local nixio = require "nixio"
local dsp = require "luci.dispatcher"

module("luci.controller.arx.wizard", package.seeall)

function index()
	if not nixio.fs.access("/etc/config/arx-wizard") then return end
	entry({"admin", "arx-wizard"}, alias("admin", "arx-wizard", "wizard"), _("配置向导"), 3).dependent = true
	entry({"admin", "arx-wizard", "wizard"}, template("arx-wizard/wizard"), _("首次配置"), 10).leaf = true
	entry({"admin", "arx-wizard", "save"}, post("action_save")).leaf = true
	entry({"admin", "arx-wizard", "skip"}, call("action_skip")).leaf = true
end

function action_skip()
	local u = uci.cursor()
	u:set("arx-wizard", "main", "completed", "1")
	u:commit("arx-wizard")
	http.redirect(dsp.build_url("admin/arx-dashboard/overview"))
end

function action_save()
	local u = uci.cursor()
	local pw = http.formvalue("w_password") or ""
	local pw2 = http.formvalue("w_password2") or ""
	if pw ~= "" then
		if pw ~= pw2 then
			http.redirect(dsp.build_url("admin/arx-wizard/wizard") .. "?err=pass")
			return
		end
		if #pw < 6 then
			http.redirect(dsp.build_url("admin/arx-wizard/wizard") .. "?err=short")
			return
		end
		-- [S4] 用 io.popen 写入密码，并检查 close() 返回值判断 chpasswd 是否真正成功
		local changed = false
		local ok, err = pcall(function()
			local p = io.popen("/usr/sbin/chpasswd 2>/dev/null", "w")
			if not p then error("popen failed") end
			p:write("root:" .. pw .. "\n")
			local ok2, reason, code = p:close()
			-- Lua 5.1 (OpenWrt): close() 返回 true/nil, "exit"/"signal", exit_code
			if not ok2 or (code ~= nil and code ~= 0) then
				error("chpasswd exited with error")
			end
			changed = true
		end)
		if not ok or not changed then
			http.redirect(dsp.build_url("admin/arx-wizard/wizard") .. "?err=passchg")
			return
		end
	end

	local wan_proto = http.formvalue("w_wan_proto") or "dhcp"
	if wan_proto ~= "dhcp" and wan_proto ~= "static" and wan_proto ~= "pppoe" then wan_proto = "dhcp" end
	u:set("network", "wan", "proto", wan_proto)
	if wan_proto == "static" then
		local ip   = http.formvalue("w_wan_ip") or ""
		local mask = http.formvalue("w_wan_mask") or "255.255.255.0"
		local gw   = http.formvalue("w_wan_gw") or ""
		-- [M9] 验证 IPv4 格式，防止写入非法值损坏网络配置
		local function valid_ipv4(s)
			if not s or s == "" then return false end
			local a,b,c,d = s:match("^(%d+)%.(%d+)%.(%d+)%.(%d+)$")
			if not a then return false end
			return tonumber(a)<=255 and tonumber(b)<=255 and tonumber(c)<=255 and tonumber(d)<=255
		end
		if ip ~= "" and valid_ipv4(ip) then u:set("network", "wan", "ipaddr", ip) end
		if mask ~= "" and valid_ipv4(mask) then u:set("network", "wan", "netmask", mask) end
		if gw ~= "" and valid_ipv4(gw) then u:set("network", "wan", "gateway", gw) end
	elseif wan_proto == "pppoe" then
		local user = http.formvalue("w_ppp_user") or ""
		local pass = http.formvalue("w_ppp_pass") or ""
		if user ~= "" then u:set("network", "wan", "username", user) end
		if pass ~= "" then u:set("network", "wan", "password", pass) end
	end
	u:commit("network")

	local ssid = http.formvalue("w_ssid")
	local wkey = http.formvalue("w_wifi_key")
	if ssid and ssid ~= "" then
		local ap_name
		u:foreach("wireless", "wifi-iface", function(s)
			if (s.mode == "ap" or s.mode == nil) and not ap_name then
				ap_name = s[".name"]
			end
		end)
		if ap_name then
			u:set("wireless", ap_name, "ssid", ssid)
			if wkey and #wkey >= 8 then
				u:set("wireless", ap_name, "encryption", "psk2")
				u:set("wireless", ap_name, "key", wkey)
			end
			u:commit("wireless")
		end
	end

	local tz = http.formvalue("w_tz") or "CST-8"
	local zn = http.formvalue("w_zonename") or "Asia/Shanghai"
	local sysn = u:get_first("system", "system")
	if sysn then
		u:set("system", sysn, "timezone", tz)
		u:set("system", sysn, "zonename", zn)
	end
	u:commit("system")

	local v6 = http.formvalue("w_ipv6")
	if v6 == "1" then
		u:set("dhcp", "lan", "ra", "server")
		u:set("dhcp", "lan", "dhcpv6", "server")
		u:set("dhcp", "lan", "ra_management", "1")
	else
		u:set("dhcp", "lan", "ra", "disabled")
		u:set("dhcp", "lan", "dhcpv6", "disabled")
	end
	u:commit("dhcp")

	u:set("arx-wizard", "main", "completed", "1")
	u:commit("arx-wizard")

	sys.call("/sbin/reload_config >/dev/null 2>&1; /etc/init.d/network reload >/dev/null 2>&1; /sbin/wifi reload >/dev/null 2>&1")
	http.redirect(dsp.build_url("admin/arx-dashboard/overview") .. "?wiz=1")
end
