# Feature: arx-theme-system
# Tests: unit: inline script order, data-theme attr, data-arx-sidebar attr,
#        footer arx.js tag, js loop with defer

$pass = 0; $fail = 0
function Pass($msg) { Write-Host "  PASS: $msg" -ForegroundColor Green; $script:pass++ }
function Fail($msg) { Write-Host "  FAIL: $msg" -ForegroundColor Red;   $script:fail++ }

$root   = Resolve-Path "$PSScriptRoot\..\.."
$header = Get-Content "$root\theme\luasrc\view\themes\arx3000m\header.htm" -Raw
$footer = Get-Content "$root\theme\luasrc\view\themes\arx3000m\footer.htm" -Raw

# ---------------------------------------------------------------------------
Write-Host "`n=== header.htm unit tests ==="

if ($header -match 'data-theme')      { Pass "data-theme attribute present on <html>" }
else                                  { Fail "data-theme attribute missing from <html>" }

if ($header -match 'data-arx-sidebar') { Pass "data-arx-sidebar attribute present on <html>" }
else                                   { Fail "data-arx-sidebar attribute missing from <html>" }

# Inline theme-init script must appear BEFORE <link rel="stylesheet">
$lines       = $header -split "`n"
$scriptLine  = ($lines | Select-String 'localStorage' | Select-Object -First 1).LineNumber
$linkLine    = ($lines | Select-String '<link rel="stylesheet"' | Select-Object -First 1).LineNumber

if (-not $scriptLine) {
    Fail "Inline theme-init script (localStorage) not found in header.htm"
} elseif (-not $linkLine) {
    Fail '<link rel="stylesheet"> not found in header.htm'
} elseif ($scriptLine -lt $linkLine) {
    Pass "Inline theme-init script (line $scriptLine) appears before <link rel=`"stylesheet`"> (line $linkLine)"
} else {
    Fail "Inline theme-init script (line $scriptLine) does NOT appear before <link rel=`"stylesheet`"> (line $linkLine)"
}

if ($header -match 'arx-theme')        { Pass "Inline script references arx-theme localStorage key" }
else                                   { Fail "Inline script missing arx-theme localStorage key" }

if ($header -match 'arx-sidebar-mode') { Pass "Inline script references arx-sidebar-mode localStorage key" }
else                                   { Fail "Inline script missing arx-sidebar-mode localStorage key" }

if ($header -match '<%=media%>/css/style\.css') { Pass "Stylesheet link uses <%=media%>/css/style.css" }
else                                            { Fail "Stylesheet link missing <%=media%>/css/style.css" }

if ($header -match 'ipairs\(css\)') { Pass "Per-page CSS injection loop present" }
else                                { Fail "Per-page CSS injection loop missing" }

# ---------------------------------------------------------------------------
Write-Host "`n=== footer.htm unit tests ==="

if ($footer -match 'arx\.js')                   { Pass "arx.js script tag present in footer.htm" }
else                                            { Fail "arx.js script tag missing from footer.htm" }

if ($footer -match '<%=media%>/js/arx\.js')     { Pass "arx.js loaded via <%=media%>/js/arx.js" }
else                                            { Fail "arx.js not loaded via <%=media%>/js/arx.js" }

if ($footer -match 'ipairs\(js\)')              { Pass "Per-page JS injection loop present in footer.htm" }
else                                            { Fail "Per-page JS injection loop missing from footer.htm" }

if ($footer -match 'defer')                     { Pass "defer attribute present in footer.htm JS loop" }
else                                            { Fail "defer attribute missing from footer.htm JS loop" }

if ($footer -match '</body>')                   { Pass "</body> closing tag present in footer.htm" }
else                                            { Fail "</body> closing tag missing from footer.htm" }

if ($footer -match '</html>')                   { Pass "</html> closing tag present in footer.htm" }
else                                            { Fail "</html> closing tag missing from footer.htm" }

# ---------------------------------------------------------------------------
Write-Host "`nResults: $pass passed, $fail failed"
if ($fail -gt 0) { exit 1 }
