local sys = require "luci.sys"
local http = require "luci.http"
local uci = require "luci.model.uci"
local nixio = require "nixio"
local dsp = require "luci.dispatcher"
local jsonc = require "luci.jsonc"

module("luci.controller.arx.flash", package.seeall)

local STAGED = "/tmp/arx-flash-firmware.bin"
local TESTLOG = "/tmp/arx-flash-last-test.log"
local BAKLOG = "/tmp/arx-flash-bak.log"
local MAX_UPLOAD = 128 * 1024 * 1024

function index()
	if not nixio.fs.access("/etc/config/arx-flash") then
		return
	end
	local c = uci.cursor()
	if c:get("arx-flash", "main", "enabled") ~= "1" then
		return
	end

	entry({ "admin", "system", "arx-flash" }, template("arx-flash/overview"), _("ARX 固件与备份"), 9).leaf = true
	entry({ "admin", "system", "arx-flash", "backup" }, call("action_backup_download")).leaf = true
	entry({ "admin", "system", "arx-flash", "receive" }, call("action_receive")).leaf = true
	entry({ "admin", "system", "arx-flash", "test" }, call("action_test")).leaf = true
	entry({ "admin", "system", "arx-flash", "flash" }, call("action_flash")).leaf = true
	entry({ "admin", "system", "arx-flash", "clear" }, call("action_clear")).leaf = true
	entry({ "admin", "system", "arx-flash", "status" }, call("action_status")).leaf = true
end

local function redirect_base(qs)
	http.redirect(dsp.build_url("admin/system/arx-flash") .. (qs and ("?" .. qs) or ""))
end

local function staged_size()
	local st = nixio.fs.stat(STAGED)
	return st and st.size or 0
end

local function tmp_free_bytes()
	local ok, sv = pcall(nixio.fs.statvfs, "/tmp")
	if not ok or not sv then
		return 0
	end
	return (tonumber(sv.bavail) or 0) * (tonumber(sv.bsize) or 4096)
end

function action_status()
	http.prepare_content("application/json")
	local board = {}
	local raw = sys.exec("ubus call system board 2>/dev/null")
	if raw and raw ~= "" then
		local ok, js = pcall(jsonc.parse, raw)
		if ok and type(js) == "table" then
			board = js
		end
	end
	local rel = {}
	local f = io.open("/etc/openwrt_release", "r")
	if f then
		for line in f:lines() do
			local k, v = line:match("^([A-Z_]+)=(.*)$")
			if k and v then
				v = v:match('^"(.*)"$') or v:match("^'(.*)'$") or v
				rel[k] = v
			end
		end
		f:close()
	end
	http.write_json({
		staged = nixio.fs.access(STAGED) and true or false,
		staged_size = staged_size(),
		tmp_free = tmp_free_bytes(),
		board = board,
		release = rel,
	})
end

function action_backup_download()
	local m = (http.getenv("REQUEST_METHOD") or ""):upper()
	if m ~= "GET" and m ~= "POST" then
		http.status(405, "Method Not Allowed")
		return
	end
	local ts = os.date("%Y%m%d-%H%M%S")
	if not ts or not ts:match("^%d%d%d%d%d%d%d%d%-%d%d%d%d%d%d$") then
		redirect_base("bak=err")
		return
	end
	local path = "/tmp/arx-openwrt-backup-" .. ts .. ".tar.gz"
	local rc = sys.call("/sbin/sysupgrade -b " .. path .. " >" .. BAKLOG .. " 2>&1")
	if rc ~= 0 then
		redirect_base("bak=fail")
		return
	end
	if not nixio.fs.access(path) then
		redirect_base("bak=fail")
		return
	end
	local name = path:match("([^/]+)$") or "backup.tar.gz"
	http.header("Content-Disposition", 'attachment; filename="' .. name:gsub('"', "") .. '"')
	http.prepare_content("application/octet-stream")
	local fh = io.open(path, "rb")
	if fh then
		repeat
			local chunk = fh:read(65536)
			if chunk then
				http.write(chunk)
			end
		until not chunk
		fh:close()
	end
	nixio.fs.unlink(path)
end

function action_receive()
	if (http.getenv("REQUEST_METHOD") or ""):upper() ~= "POST" then
		http.status(405, "Method Not Allowed")
		return
	end
	nixio.fs.unlink(STAGED)
	local fp
	local written = 0
	local overflow = false

	http.setfilehandler(function(meta, chunk, eof)
		if not meta then
			return
		end
		if meta.name ~= "firmware" then
			return
		end
		if not fp and (chunk or (meta.file and meta.file ~= "")) then
			fp = io.open(STAGED, "wb")
		end
		if chunk and fp then
			written = written + #chunk
			if written > MAX_UPLOAD then
				overflow = true
			else
				fp:write(chunk)
			end
		end
		if eof and fp then
			fp:close()
			fp = nil
		end
	end)
	http.parse_message_body()

	if overflow or written == 0 or not nixio.fs.access(STAGED) then
		nixio.fs.unlink(STAGED)
		redirect_base("upload=fail")
		return
	end
	if written < 1024 * 1024 then
		nixio.fs.unlink(STAGED)
		redirect_base("upload=small")
		return
	end
	redirect_base("upload=ok")
end

function action_test()
	if (http.getenv("REQUEST_METHOD") or ""):upper() ~= "POST" then
		http.status(405, "Method Not Allowed")
		return
	end
	if not nixio.fs.access(STAGED) then
		redirect_base("test=nofile")
		return
	end
	sys.call("/sbin/sysupgrade -T " .. STAGED .. " >" .. TESTLOG .. " 2>&1")
	redirect_base("test=done")
end

function action_flash()
	if (http.getenv("REQUEST_METHOD") or ""):upper() ~= "POST" then
		http.status(405, "Method Not Allowed")
		return
	end
	if (http.formvalue("confirm_text") or "") ~= "确认刷写" then
		redirect_base("flash=noconfirm")
		return
	end
	if not nixio.fs.access(STAGED) then
		redirect_base("flash=nofile")
		return
	end
	local args = {}
	if http.formvalue("verbose") == "1" then
		table.insert(args, "-v")
	end
	if http.formvalue("keep") ~= "1" then
		table.insert(args, "-n")
	end
	local flagstr = #args > 0 and (table.concat(args, " ") .. " ") or ""
	-- 先返回页面，再延迟执行 sysupgrade，避免 uhttpd 无响应
	http.prepare_content("text/html; charset=utf-8")
	http.write("<!DOCTYPE html><html><head><meta charset=\"utf-8\"><title>刷写</title></head><body><p>刷写已启动，设备将重启，请勿断电。</p></body></html>")
	local inner = "sleep 2; exec /sbin/sysupgrade " .. flagstr .. STAGED
	sys.call("( " .. inner .. " ) >/dev/null 2>&1 &")
end

function action_clear()
	if (http.getenv("REQUEST_METHOD") or ""):upper() ~= "POST" then
		http.status(405, "Method Not Allowed")
		return
	end
	nixio.fs.unlink(STAGED)
	nixio.fs.unlink(TESTLOG)
	redirect_base("cleared=1")
end
