# Feature: arx-theme-system
# Tests: unit: no sidebar/topbar elements, login card present,
#        form method=post, inline theme-init script before stylesheet

$pass = 0; $fail = 0
function Pass($msg) { Write-Host "  PASS: $msg" -ForegroundColor Green; $script:pass++ }
function Fail($msg) { Write-Host "  FAIL: $msg" -ForegroundColor Red;   $script:fail++ }

$root  = Resolve-Path "$PSScriptRoot\..\.."
$login = Get-Content "$root\theme\luasrc\view\themes\arx3000m\login.htm" -Raw

# ---------------------------------------------------------------------------
Write-Host "`n=== login.htm unit tests ==="

# No sidebar / topbar structural elements
if ($login -match 'class="main-left|class=''main-left') { Fail "login.htm contains .main-left (sidebar must not be present)" }
else                                                    { Pass "login.htm has no .main-left sidebar element" }

if ($login -match 'class="main-right|class=''main-right') { Fail "login.htm contains .main-right (must not be present)" }
else                                                      { Pass "login.htm has no .main-right element" }

if ($login -match 'class="head[ "]|class=''head[ '']') { Fail "login.htm contains .head topbar element (must not be present)" }
else                                                   { Pass "login.htm has no .head topbar element" }

# Login card / container
if ($login -match 'login-card|login-wrap|login-box|login-container') { Pass "Login card/container element present" }
else                                                                  { Fail "Login card/container missing (expected login-card, login-wrap, login-box, or login-container)" }

# Form with method=post
if ($login -match '(?i)<form[^>]+method=["\x27]?post') { Pass '<form method="post"> present' }
else                                                   { Fail '<form method="post"> missing' }

# Username input
if ($login -match '(?i)type=["\x27]?text|name=["\x27]?(username|luci_username)') { Pass "Username input field present" }
else                                                                              { Fail "Username input field missing" }

# Password input
if ($login -match '(?i)type=["\x27]?password') { Pass "Password input field present" }
else                                           { Fail "Password input field missing" }

# Inline theme-init script (localStorage)
if ($login -match 'localStorage') { Pass "Inline theme-init script (localStorage) present" }
else                              { Fail "Inline theme-init script (localStorage) missing" }

# Inline script must appear BEFORE <link rel="stylesheet">
$lines      = $login -split "`n"
$scriptLine = ($lines | Select-String 'localStorage' | Select-Object -First 1).LineNumber
$linkLine   = ($lines | Select-String '<link rel="stylesheet"' | Select-Object -First 1).LineNumber

if (-not $scriptLine) {
    Fail "Inline theme-init script not found in login.htm"
} elseif (-not $linkLine) {
    Fail '<link rel="stylesheet"> not found in login.htm'
} elseif ($scriptLine -lt $linkLine) {
    Pass "Inline theme-init script (line $scriptLine) appears before <link rel=`"stylesheet`"> (line $linkLine)"
} else {
    Fail "Inline theme-init script (line $scriptLine) does NOT appear before <link rel=`"stylesheet`"> (line $linkLine)"
}

# data-theme on <html>
if ($login -match 'data-theme') { Pass "data-theme attribute present on <html>" }
else                            { Fail "data-theme attribute missing from <html>" }

# Stylesheet via <%=media%>
if ($login -match '<%=media%>/css/style\.css') { Pass "Stylesheet link uses <%=media%>/css/style.css" }
else                                           { Fail "Stylesheet link missing <%=media%>/css/style.css" }

# ---------------------------------------------------------------------------
Write-Host "`nResults: $pass passed, $fail failed"
if ($fail -gt 0) { exit 1 }
