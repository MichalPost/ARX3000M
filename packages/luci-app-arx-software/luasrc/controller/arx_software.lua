local sys = require "luci.sys"
local http = require "luci.http"
local uci = require "luci.model.uci"
local nixio = require "nixio"

module("luci.controller.arx.software", package.seeall)

-- 与 detect_preset / 镜像探测共用，避免 URL 分两处维护
local PRESET_MIRRORS = {
	{ id = "tuna",    url = "https://mirrors.tuna.tsinghua.edu.cn/openwrt/", needle = "mirrors.tuna.tsinghua.edu.cn/openwrt" },
	{ id = "ustc",    url = "https://mirrors.ustc.edu.cn/openwrt/",         needle = "mirrors.ustc.edu.cn/openwrt" },
	{ id = "official", url = "https://downloads.openwrt.org/",            needle = "downloads.openwrt.org" },
}

local function copy_config_file(src, dst)
	local data = nixio.fs.readfile(src)
	if data == nil then return false end
	local ok = pcall(function() nixio.fs.writefile(dst, data) end)
	return ok
end

function index()
	if not nixio.fs.access("/etc/config/arx-software") then return end

	entry({"admin", "system", "arx-software"}, template("arx-software/overview"), _("ARX Software Mirror"), 11).leaf = true
	entry({"admin", "system", "arx-software", "status"}, call("action_status")).leaf = true
	entry({"admin", "system", "arx-software", "apply"}, call("action_apply")).leaf = true
	entry({"admin", "system", "arx-software", "restore"}, call("action_restore")).leaf = true
	entry({"admin", "system", "arx-software", "opkg_update"}, call("action_opkg_update")).leaf = true
	entry({"admin", "system", "arx-software", "usb_dest_apply"}, call("action_usb_dest_apply")).leaf = true
	entry({"admin", "system", "arx-software", "opkg_install"}, call("action_opkg_install")).leaf = true
	entry({"admin", "system", "arx-software", "extroot_status"}, call("action_extroot_status")).leaf = true
	entry({"admin", "system", "arx-software", "extroot_apply"}, call("action_extroot_apply")).leaf = true
	entry({"admin", "system", "arx-software", "probe_mirrors"}, call("action_probe_mirrors")).leaf = true
	entry({"admin", "system", "arx-software", "curated_meta"}, call("action_curated_meta")).leaf = true
	entry({"admin", "system", "arx-software", "opkg_install_bundle"}, call("action_opkg_install_bundle")).leaf = true
end

local function read_release()
	local out = {}
	local f = io.open("/etc/openwrt_release", "r")
	if f then
		for line in f:lines() do
			local k, v = line:match("^([A-Z_]+)=(.*)$")
			if k and v then
				v = v:match('^"(.*)"$') or v:match("^'(.*)'$") or v
				out[k] = v
			end
		end
		f:close()
	end
	return out
end

local function detect_preset(content)
	if not content or content == "" then return "unknown" end
	for _, m in ipairs(PRESET_MIRRORS) do
		if content:find(m.needle, 1, true) then return m.id end
	end
	return "custom"
end

local function validate_usb_mount_path(mp)
	if not mp or mp == "" or mp:find("%.%.", 1, true) then return false end
	if not mp:match("^/(mnt|media)/[%w/_-]+$") then return false end
	if mp:find("'", 1, true) then return false end
	return true
end

local function usb_mount_candidates()
	local out = {}
	local seen = {}
	local fh, err = io.open("/proc/mounts", "r")
	if not fh then return out end
	for line in fh:lines() do
		local dev, mpoint, fst = line:match("^(%S+) (%S+) (%S+)")
		if dev and mpoint and fst then
			mpoint = mpoint:gsub("\\040", " ")
			local ext = dev:match("^/dev/sd[a-z]+%d*$")
				or dev:match("^/dev/usb[a-z]+%d*$")
			if ext and (mpoint:match("^/mnt/") or mpoint:match("^/media/")) then
				if fst ~= "squashfs" and fst ~= "cifs" and not seen[mpoint] then
					seen[mpoint] = true
					table.insert(out, { device = dev, mount = mpoint, fstype = fst })
				end
			end
		end
	end
	fh:close()
	table.sort(out, function(a, b) return a.mount < b.mount end)
	return out
end

local function overlay_storage_hint()
	local line = sys.exec("df -P /overlay 2>/dev/null | tail -1") or ""
	local dev = line:match("^(%S+)")
	if not dev or dev == "" or dev == "Filesystem" then return "", "unknown" end
	if dev:find("^/dev/sd", 1, true) or dev:find("^/dev/usb", 1, true) then
		return dev, "usb_like"
	end
	return dev, "internal_or_other"
end

local function opkg_has_arxusb()
	local f = io.open("/etc/opkg.conf", "r")
	if not f then return false end
	local c = f:read("*a") or ""
	f:close()
	return c:find("dest arxusb ", 1, true) ~= nil
end

function action_status()
	http.prepare_content("application/json")
	local dist = ""
	local f = io.open("/etc/opkg/distfeeds.conf", "r")
	if f then dist = f:read("*a") or ""; f:close() end
	local bak_exists = nixio.fs.access("/etc/opkg/distfeeds.conf.bak")
	local u = uci.cursor()
	local mirror = u:get("arx-software", "main", "mirror") or "tuna"
	local custom_base = u:get("arx-software", "main", "custom_base") or ""
	local usb_mp = u:get("arx-software", "main", "usb_mountpoint") or ""

	local lines = {}
	local dist_line_count = 0
	for line in dist:gmatch("[^\r\n]+") do
		dist_line_count = dist_line_count + 1
		if #lines < 10 then table.insert(lines, line) end
	end

	local odev, oclass = overlay_storage_hint()

	http.write_json({
		detected = detect_preset(dist),
		uci_mirror = mirror,
		custom_base = custom_base,
		uci_usb_mountpoint = usb_mp,
		release = read_release(),
		distfeeds_preview = lines,
		distfeeds_preview_truncated = dist_line_count > 10,
		backup_exists = bak_exists and true or false,
		usb_mount_candidates = usb_mount_candidates(),
		overlay_device = odev,
		overlay_class = oclass,
		opkg_arxusb_configured = opkg_has_arxusb()
	})
end

local function validate_custom(s)
	if not s or s == "" then return false end
	if #s > 200 then return false end
	if not s:match("^https://[a-zA-Z0-9%.%-]+(/[a-zA-Z0-9_%.%-/]*)?$") then return false end
	local badchars = "|&'\";$`\\"
	for i = 1, #badchars do
		if s:find(badchars:sub(i, i), 1, true) then return false end
	end
	return true
end

local function mirror_apply_log_tail()
	local logf = io.open("/tmp/arx-opkg-mirror.log", "r")
	local err = logf and logf:read("*a") or ""
	if logf then logf:close() end
	return err
end

local function opkg_error_summary(log)
	if not log or log == "" then return "" end
	if log:find("No space left on device", 1, true) or log:find("only have", 1, true) then
		return "磁盘空间不足：请清理 overlay、卸载软件包或使用 extroot/U 盘扩展。"
	end
	if log:find("incompatible with the architectures", 1, true) or log:find("Wrong architecture", 1, true) then
		return "架构与运行环境不匹配（常见于内核模块）：请确认 kmod 与当前内核版本一致。"
	end
	if log:find("cannot install", 1, true) and log:find("depends on", 1, true) then
		return "依赖无法满足：请查看日志中的依赖链，或先 opkg update。"
	end
	if log:find("Collected errors:", 1, true) then
		return "opkg 报错：请展开下方完整日志定位具体包名。"
	end
	if log:find("Failed to download", 1, true) or (log:find("wget", 1, true) and log:find("failed", 1, true)) then
		return "下载索引或包失败：请检查镜像可达性与网络。"
	end
	return ""
end

function action_apply()
	http.prepare_content("application/json")
	if (http.getenv("REQUEST_METHOD") or ""):upper() ~= "POST" then
		http.write_json({ ok = false, error = "需要 POST" })
		return
	end
	local preset = http.formvalue("mirror") or "tuna"
	local custom = http.formvalue("custom_base") or ""
	custom = custom:gsub("/+$", "")

	if preset == "custom" and not validate_custom(custom) then
		http.write_json({ ok = false, error = "自定义地址格式无效（需 https://主机[/路径]，勿含引号、|、& 等）" })
		return
	end
	if preset ~= "tuna" and preset ~= "ustc" and preset ~= "official" and preset ~= "custom" then
		http.write_json({ ok = false, error = "未知镜像类型" })
		return
	end

	local rc
	if preset == "custom" then
		nixio.fs.writefile("/tmp/arx-custom-opkg.url", custom)
		rc = sys.call("env ARX_CUSTOM_BASE_FILE=/tmp/arx-custom-opkg.url /sbin/arx-opkg-mirror apply custom >/tmp/arx-opkg-mirror.log 2>&1")
	else
		rc = sys.call("/sbin/arx-opkg-mirror apply " .. preset .. " >/tmp/arx-opkg-mirror.log 2>&1")
	end

	if rc ~= 0 then
		http.write_json({ ok = false, error = "写入 distfeeds 失败", log = mirror_apply_log_tail() })
		return
	end

	local u = uci.cursor()
	u:set("arx-software", "main", "mirror", preset)
	u:set("arx-software", "main", "custom_base", preset == "custom" and custom or "")
	u:commit("arx-software")

	http.write_json({ ok = true })
end

function action_restore()
	http.prepare_content("application/json")
	if (http.getenv("REQUEST_METHOD") or ""):upper() ~= "POST" then
		http.write_json({ ok = false, error = "需要 POST" })
		return
	end
	local rc = sys.call("/sbin/arx-opkg-mirror restore >/tmp/arx-opkg-mirror.log 2>&1")
	if rc ~= 0 then
		http.write_json({ ok = false, error = "恢复失败（可能无备份）", log = mirror_apply_log_tail() })
		return
	end
	http.write_json({ ok = true })
end

function action_opkg_update()
	http.prepare_content("application/json")
	if (http.getenv("REQUEST_METHOD") or ""):upper() ~= "POST" then
		http.write_json({ ok = false, error = "需要 POST" })
		return
	end
	local rc = sys.call("opkg update >/tmp/arx-opkg-up.log 2>&1")
	local out = ""
	local logf = io.open("/tmp/arx-opkg-up.log", "r")
	if logf then out = logf:read("*a") or ""; logf:close() end
	local lines = {}
	for line in out:gmatch("[^\r\n]+") do
		table.insert(lines, line)
	end
	while #lines > 80 do table.remove(lines, 1) end
	local logtxt = table.concat(lines, "\n")
	http.write_json({
		ok = rc == 0,
		log = logtxt,
		summary = (rc == 0 and "" or opkg_error_summary(logtxt)),
	})
end

function action_usb_dest_apply()
	http.prepare_content("application/json")
	if (http.getenv("REQUEST_METHOD") or ""):upper() ~= "POST" then
		http.write_json({ ok = false, error = "需要 POST" })
		return
	end
	local mp = http.formvalue("usb_mountpoint") or ""
	mp = mp:gsub("/+$", "")

	local u = uci.cursor()
	if mp == "" then
		local rc = sys.call("/sbin/arx-opkg-usb-dest clear >/tmp/arx-usb-dest.log 2>&1")
		if rc ~= 0 then
			local logf = io.open("/tmp/arx-usb-dest.log", "r")
			local lg = logf and logf:read("*a") or ""
			if logf then logf:close() end
			http.write_json({ ok = false, error = "清除 U 盘 opkg 目标失败", log = lg })
			return
		end
		u:set("arx-software", "main", "usb_mountpoint", "")
		u:commit("arx-software")
		http.write_json({ ok = true })
		return
	end

	if not validate_usb_mount_path(mp) then
		http.write_json({ ok = false, error = "挂载点不合法（仅允许 /mnt/ 或 /media/ 下路径）" })
		return
	end
	if not nixio.fs.stat(mp) then
		http.write_json({ ok = false, error = "目录不存在" })
		return
	end

	local rc = sys.call("/sbin/arx-opkg-usb-dest set '" .. mp .. "' >/tmp/arx-usb-dest.log 2>&1")
	if rc ~= 0 then
		local logf = io.open("/tmp/arx-usb-dest.log", "r")
		local lg = logf and logf:read("*a") or ""
		if logf then logf:close() end
		http.write_json({ ok = false, error = "写入失败（请确认分区已挂载）", log = lg })
		return
	end
	u:set("arx-software", "main", "usb_mountpoint", mp)
	u:commit("arx-software")
	http.write_json({ ok = true })
end

local function validate_pkg_name(p)
	if not p or p == "" or #p > 120 then return false end
	return p:match("^[%w%._%-]+$") ~= nil
end

local CURATED_JSON = "/usr/share/arx-software/curated.json"

local function parse_pkg_list_from_form(s)
	if not s or s == "" then return nil, "empty" end
	local out = {}
	local seen = {}
	for token in tostring(s):gmatch("[^,%s]+") do
		if not validate_pkg_name(token) then return nil, token end
		if not seen[token] then
			seen[token] = true
			table.insert(out, token)
		end
	end
	if #out == 0 then return nil, "empty" end
	if #out > 40 then return nil, "too_many" end
	return out
end

local function opkg_meta_for_package(pkg)
	if not validate_pkg_name(pkg) then return nil end
	local info = sys.exec("opkg info '" .. pkg .. "' 2>/dev/null") or ""
	if not info:match("%S") then
		return {
			package = pkg,
			available = false,
			installed = false,
			version = "",
			depends = {},
			installed_size = "",
			installed_size_bytes = nil,
		}
	end
	local ver = info:match("Version:%s*(%S+)") or ""
	local dep_line = info:match("Depends:%s*(.-)\n") or ""
	local deps = {}
	for d in dep_line:gmatch("([^,]+)") do
		local x = d:match("^%s*(.-)%s*$")
		if x and x ~= "" then table.insert(deps, x) end
	end
	local sz_raw = info:match("Installed%-Size:%s*(%d+)")
	local installed = info:match("Status:%s*install%s") ~= nil
	return {
		package = pkg,
		available = true,
		installed = installed,
		version = ver,
		depends = deps,
		installed_size = sz_raw and (sz_raw .. " B") or "",
		installed_size_bytes = tonumber(sz_raw),
	}
end

function action_curated_meta()
	http.prepare_content("application/json")
	local jsonc = require "luci.jsonc"
	local raw = nixio.fs.readfile(CURATED_JSON) or ""
	local ok, catalog = pcall(jsonc.parse, raw)
	if not ok or type(catalog) ~= "table" then
		http.write_json({ ok = false, error = "curated 清单无效或缺失" })
		return
	end
	local cache = {}
	local function meta(p)
		if not cache[p] then cache[p] = opkg_meta_for_package(p) end
		return cache[p]
	end
	local categories = catalog.categories
	if type(categories) ~= "table" then
		http.write_json({ ok = true, disclaimer = catalog.disclaimer or "", categories = {} })
		return
	end
	local out_cats = {}
	for _, cat in ipairs(categories) do
		if type(cat) == "table" and cat.id and cat.title then
			local items_out = {}
			for _, it in ipairs(type(cat.items) == "table" and cat.items or {}) do
				if type(it) == "table" and it.id and it.title and type(it.packages) == "table" then
					local pkgs_meta = {}
					local sum_bytes = 0
					for _, pname in ipairs(it.packages) do
						if type(pname) == "string" then
							local m = meta(pname)
							if m then
								table.insert(pkgs_meta, m)
								if m.installed_size_bytes then sum_bytes = sum_bytes + m.installed_size_bytes end
							end
						end
					end
					table.insert(items_out, {
						id = it.id,
						title = it.title,
						description = it.description or "",
						feed_note = it.feed_note,
						packages = it.packages,
						packages_meta = pkgs_meta,
						estimated_size_sum_bytes = sum_bytes > 0 and sum_bytes or nil,
					})
				end
			end
			table.insert(out_cats, {
				id = cat.id,
				title = cat.title,
				items = items_out,
			})
		end
	end
	http.write_json({
		ok = true,
		disclaimer = catalog.disclaimer or "",
		categories = out_cats,
	})
end

function action_opkg_install_bundle()
	http.prepare_content("application/json")
	if (http.getenv("REQUEST_METHOD") or ""):upper() ~= "POST" then
		http.write_json({ ok = false, error = "需要 POST" })
		return
	end
	local list, err = parse_pkg_list_from_form(http.formvalue("pkgs") or "")
	if not list then
		local msg = err == "too_many" and "一次最多 40 个包" or ("包名无效: " .. tostring(err))
		http.write_json({ ok = false, error = msg })
		return
	end
	local to_usb = http.formvalue("to_usb") == "1" or http.formvalue("to_usb") == "true"
	if to_usb and not opkg_has_arxusb() then
		http.write_json({ ok = false, error = "请先在下方保存 U 盘挂载点，以启用 opkg 目标 arxusb" })
		return
	end
	local arg = table.concat(list, " ")
	local cmd
	if to_usb then
		cmd = "opkg install -d arxusb " .. arg .. " >/tmp/arx-opkg-in.log 2>&1"
	else
		cmd = "opkg install " .. arg .. " >/tmp/arx-opkg-in.log 2>&1"
	end
	local rc = sys.call(cmd)
	local out = ""
	local logf = io.open("/tmp/arx-opkg-in.log", "r")
	if logf then out = logf:read("*a") or ""; logf:close() end
	local lines = {}
	for line in out:gmatch("[^\r\n]+") do
		table.insert(lines, line)
	end
	while #lines > 120 do table.remove(lines, 1) end
	local logtxt = table.concat(lines, "\n")
	http.write_json({
		ok = rc == 0,
		log = logtxt,
		summary = (rc == 0 and "" or opkg_error_summary(logtxt)),
	})
end

function action_probe_mirrors()
	http.prepare_content("application/json")
	local out = {}
	for _, m in ipairs(PRESET_MIRRORS) do
		local ok = sys.call("uclient-fetch -q -T 3 -O /dev/null '" .. m.url .. "' 2>/dev/null") == 0
		if not ok then
			ok = sys.call("wget -T 3 -q -O /dev/null '" .. m.url .. "' 2>/dev/null") == 0
		end
		table.insert(out, { id = m.id, ok = ok, url = m.url })
	end
	http.write_json({ mirrors = out })
end

function action_opkg_install()
	http.prepare_content("application/json")
	if (http.getenv("REQUEST_METHOD") or ""):upper() ~= "POST" then
		http.write_json({ ok = false, error = "需要 POST" })
		return
	end
	local pkg = http.formvalue("pkg") or ""
	pkg = pkg:match("^%s*(.-)%s*$") or ""
	local to_usb = http.formvalue("to_usb") == "1" or http.formvalue("to_usb") == "true"

	if not validate_pkg_name(pkg) then
		http.write_json({ ok = false, error = "包名格式无效（仅字母数字 . _ -）" })
		return
	end

	local cmd
	if to_usb then
		if not opkg_has_arxusb() then
			http.write_json({ ok = false, error = "请先在下方保存 U 盘挂载点，以启用 opkg 目标 arxusb" })
			return
		end
		cmd = "opkg install -d arxusb " .. pkg .. " >/tmp/arx-opkg-in.log 2>&1"
	else
		cmd = "opkg install " .. pkg .. " >/tmp/arx-opkg-in.log 2>&1"
	end

	local rc = sys.call(cmd)
	local out = ""
	local logf = io.open("/tmp/arx-opkg-in.log", "r")
	if logf then out = logf:read("*a") or ""; logf:close() end
	local lines = {}
	for line in out:gmatch("[^\r\n]+") do
		table.insert(lines, line)
	end
	while #lines > 100 do table.remove(lines, 1) end
	local logtxt = table.concat(lines, "\n")
	http.write_json({
		ok = rc == 0,
		log = logtxt,
		summary = (rc == 0 and "" or opkg_error_summary(logtxt)),
	})
end

local function validate_extroot_dev(dev)
	if not dev then return false end
	return dev:match("^/dev/sd[a-z]+[0-9]+$") ~= nil
end

local function delete_fstab_overlay_entries()
	local u = uci.cursor()
	if not nixio.fs.access("/etc/config/fstab") then return end
	u:load("fstab")
	local del = {}
	u:foreach("fstab", "mount", function(s)
		local n = s[".name"]
		if u:get("fstab", n, "target") == "/overlay" then
			table.insert(del, n)
		end
	end)
	for _, n in ipairs(del) do
		u:delete("fstab", n)
	end
	u:commit("fstab")
end

function action_extroot_status()
	http.prepare_content("application/json")
	local precheck_ok = sys.call("/sbin/arx-extroot-wizard precheck >/dev/null 2>&1") == 0
	-- [H4] 用 nixio.fs.dir 遍历 /sys/class/block，避免 io.popen("ls /dev/sd*") 在无匹配时输出错误
	local parts = {}
	local blk_dir = nixio.fs.dir("/sys/class/block")
	if blk_dir then
		for name in blk_dir do
			if name:match("^sd[a-z]+[0-9]+$") then
				local dev_path = "/dev/" .. name
				local sz = ""
				local sf = io.open("/sys/class/block/" .. name .. "/size", "r")
				if sf then
					local sec = sf:read("*n")
					sf:close()
					if sec then
						sz = string.format("%.0f MB", sec * 512 / 1048576)
					end
				end
				table.insert(parts, { device = dev_path, size = sz })
			end
		end
	end
	local has_overlay_fstab = false
	if nixio.fs.access("/etc/config/fstab") then
		local u = uci.cursor()
		u:load("fstab")
		u:foreach("fstab", "mount", function(s)
			local n = s[".name"]
			if u:get("fstab", n, "target") == "/overlay" then
				has_overlay_fstab = true
			end
		end)
	end
	local odev, _ = overlay_storage_hint()
	http.write_json({
		precheck_ok = precheck_ok,
		usb_partitions = parts,
		fstab_has_overlay = has_overlay_fstab,
		overlay_device = odev
	})
end

function action_extroot_apply()
	http.prepare_content("application/json")
	if (http.getenv("REQUEST_METHOD") or ""):upper() ~= "POST" then
		http.write_json({ ok = false, error = "需要 POST" })
		return
	end
	if http.formvalue("confirm") ~= "确认迁移extroot" then
		http.write_json({ ok = false, error = "请在确认框输入：确认迁移extroot" })
		return
	end
	local dev = http.formvalue("device") or ""
	local fmt = http.formvalue("format") == "1" or http.formvalue("format") == "true"
	if not validate_extroot_dev(dev) then
		http.write_json({ ok = false, error = "设备无效（仅允许 /dev/sda1 这类 USB 分区）" })
		return
	end
	if sys.call("test -b '" .. dev .. "'") ~= 0 then
		http.write_json({ ok = false, error = "块设备不存在或不可访问" })
		return
	end

	if nixio.fs.access("/etc/config/fstab") then
		copy_config_file("/etc/config/fstab", "/etc/config/fstab.arx.bak")
	end
	-- [H3] 先备份再删除；失败时用 UCI 重新加载备份文件恢复，避免 commit 后缓存与文件不一致
	delete_fstab_overlay_entries()

	local f = tostring(fmt and 1 or 0)
	local rc = sys.call("/sbin/arx-extroot-wizard apply '" .. dev .. "' " .. f .. " >/tmp/arx-extroot-exec.log 2>&1")
	local logtxt = ""
	local logf = io.open("/tmp/arx-extroot-exec.log", "r")
	if logf then logtxt = logf:read("*a") or ""; logf:close() end
	if rc ~= 0 then
		if nixio.fs.access("/etc/config/fstab.arx.bak") then
			copy_config_file("/etc/config/fstab.arx.bak", "/etc/config/fstab")
		end
		http.write_json({ ok = false, error = "执行失败，已尝试恢复 fstab 备份", log = logtxt })
		return
	end
	http.write_json({ ok = true, log = logtxt, need_reboot = true })
end
