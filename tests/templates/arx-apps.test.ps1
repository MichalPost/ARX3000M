# Feature: arx-theme-system
# Tests: Property 8 — all ARX app view templates include header and footer partials

$pass = 0; $fail = 0
function Pass($msg) { Write-Host "  PASS: $msg" -ForegroundColor Green; $script:pass++ }
function Fail($msg) { Write-Host "  FAIL: $msg" -ForegroundColor Red;   $script:fail++ }

$root        = Resolve-Path "$PSScriptRoot\..\.."
$packagesDir = "$root\packages"

# ---------------------------------------------------------------------------
Write-Host "`n=== Property 8: ARX app header/footer partials ==="

$htmFiles = Get-ChildItem -Path $packagesDir -Recurse -Filter '*.htm' |
    Where-Object { $_.FullName -match 'luci-app-arx-[^\\]+\\luasrc\\view\\' } |
    Sort-Object FullName

if ($htmFiles.Count -eq 0) {
    Fail "P8: No .htm files found under packages\luci-app-arx-*\luasrc\view\"
    Write-Host "`nResults: $pass passed, $fail failed"
    exit 1
}

foreach ($f in $htmFiles) {
    $content   = Get-Content $f.FullName -Raw
    $rel       = $f.FullName.Substring($packagesDir.Length + 1)
    $hasHeader = $content -match '<%\+header%>'
    $hasFooter = $content -match '<%\+footer%>'

    if ($hasHeader -and $hasFooter) {
        Pass "P8: $rel"
    } elseif (-not $hasHeader -and -not $hasFooter) {
        Fail "P8: $rel — missing both <%+header%> and <%+footer%>"
    } elseif (-not $hasHeader) {
        Fail "P8: $rel — missing <%+header%>"
    } else {
        Fail "P8: $rel — missing <%+footer%>"
    }
}

# ---------------------------------------------------------------------------
Write-Host "`nTotal .htm files checked: $($htmFiles.Count)"
Write-Host "Results: $pass passed, $fail failed"
if ($fail -gt 0) { exit 1 }
