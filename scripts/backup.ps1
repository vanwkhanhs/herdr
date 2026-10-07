<#
.SYNOPSIS
    Hut cau hinh Herdr + tich hop Claude Code tu may hien tai vao repo nay.

.DESCRIPTION
    Chay tu bat ky dau; script tu xac dinh goc repo tu vi tri cua chinh no.
    Khong ghi gi ra ngoai repo. Sau khi chay, commit va push thu cong.

.EXAMPLE
    .\scripts\backup.ps1
    git add -A; git commit -m "backup: cap nhat config"; git push
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$RepoRoot = Split-Path -Parent $PSScriptRoot
$HerdrCfg = Join-Path $env:APPDATA 'herdr'
$ClaudeDir = Join-Path $env:USERPROFILE '.claude'

# nguon -> dich (tuong doi so voi goc repo)
$Items = [ordered]@{
    (Join-Path $HerdrCfg  'config.toml')              = 'config\config.toml'
    (Join-Path $HerdrCfg  'session.json')             = 'config\session.json'
    (Join-Path $ClaudeDir 'settings.json')            = 'claude\settings.json'
    (Join-Path $ClaudeDir 'hooks\herdr-agent-state.ps1') = 'claude\hooks\herdr-agent-state.ps1'
    (Join-Path $ClaudeDir 'skills\herdr\SKILL.md')    = 'claude\skills\herdr\SKILL.md'
    (Join-Path $ClaudeDir 'statusline-usage.py')      = 'claude\statusline-usage.py'
    'E:\Kztek_Firmwave\CLAUDE.md'                     = 'claude\CLAUDE.manager.md'
}

$copied = 0
$missing = 0

foreach ($src in $Items.Keys) {
    $dst = Join-Path $RepoRoot $Items[$src]

    if (-not (Test-Path -LiteralPath $src)) {
        Write-Warning "bo qua (khong co): $src"
        $missing++
        continue
    }

    $dstDir = Split-Path -Parent $dst
    if (-not (Test-Path -LiteralPath $dstDir)) {
        New-Item -ItemType Directory -Path $dstDir -Force | Out-Null
    }

    Copy-Item -LiteralPath $src -Destination $dst -Force
    Write-Host "  OK  $($Items[$src])"
    $copied++
}

# Bang tham chieu moi khoa cau hinh, sinh tu binary dang cai
$herdr = Get-Command herdr -ErrorAction SilentlyContinue
if ($herdr) {
    $defaults = (& $herdr.Source --default-config) -join "`n"
    $utf8NoBom = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText((Join-Path $RepoRoot 'config\config.default.toml'), $defaults + "`n", $utf8NoBom)
    Write-Host "  OK  config\config.default.toml  ($(& $herdr.Source --version))"
} else {
    Write-Warning "khong tim thay 'herdr' trong PATH - bo qua config.default.toml"
}

Write-Host ""
Write-Host "Da sao luu $copied file vao $RepoRoot" -ForegroundColor Green
if ($missing -gt 0) { Write-Host "$missing file nguon khong ton tai (xem canh bao o tren)" -ForegroundColor Yellow }
Write-Host "Buoc tiep: git add -A; git commit -m 'backup: cap nhat config'; git push"
