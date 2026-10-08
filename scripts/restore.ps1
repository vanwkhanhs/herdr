<#
.SYNOPSIS
    Day cau hinh Herdr + tich hop Claude Code tu repo nay ra may hien tai.

.DESCRIPTION
    Moi file bi ghi de deu duoc backup thanh <ten>.bak-<yyyyMMdd-HHmmss> truoc.
    Mac dinh hoi xac nhan; dung -Force de chay thang.

    session.json la trang thai runtime: chi khoi phuc khi herdr server DANG TAT,
    neu khong server se ghi de lai luc thoat. Mac dinh script BO QUA session.json;
    them -IncludeSession de khoi phuc ca bo cuc space.

.PARAMETER Force
    Khong hoi xac nhan.

.PARAMETER IncludeSession
    Khoi phuc ca config\session.json (bo cuc 7 space). Yeu cau server da tat.

.EXAMPLE
    .\scripts\restore.ps1
    .\scripts\restore.ps1 -IncludeSession -Force
#>

[CmdletBinding()]
param(
    [switch]$Force,
    [switch]$IncludeSession
)

$ErrorActionPreference = 'Stop'

$RepoRoot  = Split-Path -Parent $PSScriptRoot
$HerdrCfg  = Join-Path $env:APPDATA 'herdr'
$ClaudeDir = Join-Path $env:USERPROFILE '.claude'
$Stamp     = Get-Date -Format 'yyyyMMdd-HHmmss'

# nguon (tuong doi so voi goc repo) -> dich tuyet doi
$Items = [ordered]@{
    'config\config.toml'                  = (Join-Path $HerdrCfg  'config.toml')
    'claude\settings.json'                = (Join-Path $ClaudeDir 'settings.json')
    'claude\hooks\herdr-agent-state.ps1'  = (Join-Path $ClaudeDir 'hooks\herdr-agent-state.ps1')
    'claude\skills\herdr\SKILL.md'        = (Join-Path $ClaudeDir 'skills\herdr\SKILL.md')
    'claude\statusline-usage.py'          = (Join-Path $ClaudeDir 'statusline-usage.py')
    'claude\statusline-model.py'          = (Join-Path $ClaudeDir 'statusline-model.py')
    'claude\CLAUDE.manager.md'            = 'E:\Kztek_Firmwave\CLAUDE.md'
}

if ($IncludeSession) {
    $Items['config\session.json'] = (Join-Path $HerdrCfg 'session.json')
}

Write-Host "Se ghi cac file sau:" -ForegroundColor Cyan
foreach ($rel in $Items.Keys) { Write-Host "  $rel  ->  $($Items[$rel])" }

if ($IncludeSession) {
    Write-Host ""
    Write-Host "CANH BAO: session.json chi an toan khi herdr server DA TAT." -ForegroundColor Yellow
    Write-Host "          Neu server dang chay, chay 'herdr server stop' truoc (lenh nay giet moi pane)." -ForegroundColor Yellow
}

if (-not $Force) {
    Write-Host ""
    $ans = Read-Host "Tiep tuc? (y/N)"
    if ($ans -ne 'y' -and $ans -ne 'Y') {
        Write-Host "Da huy."
        return
    }
}

$restored = 0

foreach ($rel in $Items.Keys) {
    $src = Join-Path $RepoRoot $rel
    $dst = $Items[$rel]

    if (-not (Test-Path -LiteralPath $src)) {
        Write-Warning "bo qua (khong co trong repo): $rel"
        continue
    }

    $dstDir = Split-Path -Parent $dst
    if (-not (Test-Path -LiteralPath $dstDir)) {
        New-Item -ItemType Directory -Path $dstDir -Force | Out-Null
    }

    if (Test-Path -LiteralPath $dst) {
        Copy-Item -LiteralPath $dst -Destination "$dst.bak-$Stamp" -Force
        Write-Host "  bak $dst.bak-$Stamp" -ForegroundColor DarkGray
    }

    Copy-Item -LiteralPath $src -Destination $dst -Force
    Write-Host "  OK  $dst"
    $restored++
}

Write-Host ""
Write-Host "Da khoi phuc $restored file." -ForegroundColor Green
Write-Host ""
Write-Host "Buoc tiep:"
Write-Host "  1. Kiem tra duong dan tuyet doi trong claude\settings.json (hook + statusline)"
Write-Host "     - may nay: $ClaudeDir"
Write-Host "  2. herdr server reload-config    # neu server dang chay"
Write-Host "  3. herdr                         # mo lai session"
Write-Host "  4. herdr workspace list          # xac nhan so space"
Write-Host "  5. .\scripts\orca\install-watcher.ps1   # bat lai watcher dung layout Orca"
