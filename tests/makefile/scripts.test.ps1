# Feature: arx-theme-system
# Tests: Property 11 (UCI defaults idempotency), unit: script content

$pass = 0; $fail = 0
function Pass($msg) { Write-Host "  PASS: $msg" -ForegroundColor Green;  $script:pass++ }
function Fail($msg) { Write-Host "  FAIL: $msg" -ForegroundColor Red;    $script:fail++ }

$root      = Resolve-Path "$PSScriptRoot\..\.."
$uciScript = Get-Content "$root\theme\root\etc\uci-defaults\luci-theme-arx3000m" -Raw

# ---------------------------------------------------------------------------
Write-Host "`n=== Unit: UCI defaults script content ==="

if ($uciScript -match "luci\.main\.lang='zh_cn'") { Pass "uci set luci.main.lang='zh_cn' present" }
else                                               { Fail "uci set luci.main.lang='zh_cn' missing" }

if ($uciScript -match 'luci\.themes\.arx3000m') { Pass "luci.themes.arx3000m registration block present" }
else                                             { Fail "luci.themes.arx3000m registration block missing" }

if ($uciScript -match "luci\.themes\.arx3000m\.name='ARX3000M'") { Pass "theme name='ARX3000M' present" }
else                                                              { Fail "theme name='ARX3000M' missing" }

if ($uciScript -match '\[ -z') { Pass "mediaurlbase guard condition [ -z ... ] present" }
else                            { Fail "mediaurlbase guard condition [ -z ... ] missing" }

if ($uciScript -match 'uci commit luci') { Pass "uci commit luci present" }
else                                     { Fail "uci commit luci missing" }

if ($uciScript -match '/luci-static/arx3000m') { Pass "mediaurlbase value /luci-static/arx3000m present" }
else                                            { Fail "mediaurlbase value /luci-static/arx3000m missing" }

# ---------------------------------------------------------------------------
Write-Host "`n=== Property 11: UCI defaults idempotency for mediaurlbase ==="
# P11: The guard [ -z "$(uci -q get luci.main.mediaurlbase)" ] ensures the
# mediaurlbase line is only executed when the value is empty.
# We verify this statically: the uci set mediaurlbase line must be inside
# a conditional block that checks for an empty/unset value.

# Extract the mediaurlbase assignment line and the surrounding guard
$guardPattern  = '\[\s*-z\s*["\x27]\$\(uci\s+-q\s+get\s+luci\.main\.mediaurlbase[^)]*\)["\x27]\s*\]'
$setPattern    = 'uci\s+set\s+luci\.main\.mediaurlbase'

if ($uciScript -match $guardPattern) { Pass 'P11: [ -z $(uci -q get luci.main.mediaurlbase) ] guard present' }
else                                  { Fail "P11: mediaurlbase guard expression not found" }

if ($uciScript -match $setPattern) { Pass "P11: uci set luci.main.mediaurlbase present" }
else                                { Fail "P11: uci set luci.main.mediaurlbase missing" }

# Verify the set line appears on the SAME line as (or after) the guard —
# i.e. the guard and the set are combined with && (one-liner idempotency pattern)
if ($uciScript -match $guardPattern + '.*' + $setPattern) {
    Pass "P11: guard and set are on the same line (idempotent one-liner)"
} else {
    # They may be on separate lines; check that guard line number < set line number
    # and that no unconditional set exists before the guard
    $lines = $uciScript -split "`n"
    $guardLine = ($lines | Select-String -Pattern $guardPattern | Select-Object -First 1).LineNumber
    $setLine   = ($lines | Select-String -Pattern $setPattern   | Select-Object -First 1).LineNumber

    # Check there is no unconditional set before the guard
    $unconditionalSet = $false
    for ($i = 0; $i -lt ($guardLine - 1); $i++) {
        if ($lines[$i] -match $setPattern) { $unconditionalSet = $true; break }
    }

    if (-not $unconditionalSet) { Pass "P11: no unconditional mediaurlbase set before guard" }
    else                        { Fail "P11: unconditional uci set mediaurlbase found before guard — not idempotent" }
}

# ---------------------------------------------------------------------------
Write-Host "`nResults: $pass passed, $fail failed"
if ($fail -gt 0) { exit 1 }
