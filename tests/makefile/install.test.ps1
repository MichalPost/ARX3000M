# Feature: arx-theme-system
# Tests: Property 5 (template install paths), Property 12 (build config exclusivity),
#        unit: PKGARCH, Build/Compile empty, postinst, postrm

$pass = 0; $fail = 0
function Pass($msg) { Write-Host "  PASS: $msg" -ForegroundColor Green;  $script:pass++ }
function Fail($msg) { Write-Host "  FAIL: $msg" -ForegroundColor Red;    $script:fail++ }

$root      = Resolve-Path "$PSScriptRoot\..\.."
$makefile  = Get-Content "$root\theme\Makefile" -Raw
$buildCfg  = Get-Content "$root\config\rax3000m.config" -Raw

# ---------------------------------------------------------------------------
Write-Host "`n=== Unit: PKGARCH ==="

if ($makefile -match 'PKGARCH:=all') { Pass "PKGARCH:=all present" }
else                                  { Fail "PKGARCH:=all missing" }

# ---------------------------------------------------------------------------
Write-Host "`n=== Unit: Build/Compile block is empty ==="

$compileBlock = [regex]::Match(
    $makefile,
    'define Build/Compile\r?\n(.*?)endef',
    [System.Text.RegularExpressions.RegexOptions]::Singleline
).Groups[1].Value

if ($compileBlock.Trim() -eq '') { Pass "Build/Compile block is empty" }
else                              { Fail "Build/Compile block is not empty: '$($compileBlock.Trim())'" }

# ---------------------------------------------------------------------------
Write-Host "`n=== Unit: postinst ==="

if ($makefile -match '\. /etc/uci-defaults/luci-theme-arx3000m') { Pass "postinst sources uci-defaults script" }
else                                                               { Fail "postinst missing: . /etc/uci-defaults/luci-theme-arx3000m" }

if ($makefile -match 'rm -f /etc/uci-defaults/luci-theme-arx3000m') { Pass "postinst deletes uci-defaults script" }
else                                                                  { Fail "postinst missing: rm -f /etc/uci-defaults/luci-theme-arx3000m" }

if ($makefile -match 'rm -f /tmp/luci-indexcache') { Pass "postinst clears luci-indexcache" }
else                                                { Fail "postinst missing: rm -f /tmp/luci-indexcache" }

# ---------------------------------------------------------------------------
Write-Host "`n=== Unit: postrm ==="

if ($makefile -match 'uci delete luci\.themes\.arx3000m') { Pass "postrm: uci delete luci.themes.arx3000m present" }
else                                                       { Fail "postrm: uci delete luci.themes.arx3000m missing" }

if ($makefile -match 'uci commit luci') { Pass "postrm: uci commit luci present" }
else                                    { Fail "postrm: uci commit luci missing" }

# ---------------------------------------------------------------------------
Write-Host "`n=== Property 5: All five shell templates installed to correct paths ==="
# P5: install block must use *.htm glob and target /usr/lib/lua/luci/view/themes/arx3000m/

$installBlock = [regex]::Match(
    $makefile,
    'define Package/luci-theme-arx3000m/install(.*?)endef',
    [System.Text.RegularExpressions.RegexOptions]::Singleline
).Groups[1].Value

if ($installBlock -match '\.htm') { Pass "P5: *.htm glob present in install block" }
else                               { Fail "P5: *.htm glob missing from install block" }

if ($installBlock -match 'view/themes/arx3000m') { Pass "P5: destination view/themes/arx3000m/ present" }
else                                              { Fail "P5: destination view/themes/arx3000m/ missing" }

foreach ($tpl in @('header.htm','footer.htm','login.htm','error404.htm','error500.htm')) {
    $tplPath = "$root\theme\luasrc\view\themes\arx3000m\$tpl"
    if (Test-Path $tplPath) { Pass "P5: $tpl exists at source path" }
    else                    { Fail "P5: $tpl missing from theme/luasrc/view/themes/arx3000m/" }
}

# ---------------------------------------------------------------------------
Write-Host "`n=== Property 12: Build config theme exclusivity ==="

if ($buildCfg -match 'CONFIG_PACKAGE_luci-theme-arx3000m=y') { Pass "P12: CONFIG_PACKAGE_luci-theme-arx3000m=y present" }
else                                                           { Fail "P12: CONFIG_PACKAGE_luci-theme-arx3000m=y missing" }

foreach ($theme in @('luci-theme-bootstrap','luci-theme-material','luci-theme-openwrt')) {
    if ($buildCfg -match "(?m)^CONFIG_PACKAGE_${theme}=y") { Fail "P12: $theme is set to =y (must be disabled)" }
    else                                                    { Pass "P12: $theme not set to =y" }
}

# ---------------------------------------------------------------------------
Write-Host "`nResults: $pass passed, $fail failed"
if ($fail -gt 0) { exit 1 }
