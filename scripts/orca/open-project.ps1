<#
.SYNOPSIS
    Mo mot project trong Orca: dung tab builder + reviewer + debug.

.DESCRIPTION
    Mac dinh khi mo Orca KHONG co project nao duoc dung san - moi pane Claude an
    ~440 MB, dung du 7 project la ~6,6 GB cho nhung thu chua dung den. Dung script
    nay de mo dung project can lam.

    Khong co tham so thi liet ke cac project co the mo, kem trang thai hien tai.

.PARAMETER Name
    Ten project, khop mot phan cung duoc. Vi du 'e16', 'KZ_E02', 'smart'.

.EXAMPLE
    .\open-project.ps1              # liet ke
    .\open-project.ps1 kz_e16       # mo project kz_e16
    .\open-project.ps1 smart        # khop mot phan cung duoc
#>

[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$Name
)

$ErrorActionPreference = 'Stop'

$LayoutScript = Join-Path $PSScriptRoot 'orca-layout.ps1'
if (-not (Test-Path -LiteralPath $LayoutScript)) { throw "Khong thay orca-layout.ps1" }

# Doc danh sach project tu orca-layout.ps1 - mot nguon su that duy nhat
$projects = @()
foreach ($line in (Get-Content -LiteralPath $LayoutScript)) {
    if ($line -match "Name\s*=\s*'([^']+)'\s*;\s*Path\s*=\s*'([^']+)'") {
        $projects += [pscustomobject]@{ Name = $Matches[1]; Path = $Matches[2] }
    }
}
if ($projects.Count -eq 0) { throw "Khong doc duoc project nao tu orca-layout.ps1" }

# Trang thai hien tai trong Orca
$Orca = (Get-Command orca -ErrorAction SilentlyContinue).Source
if (-not $Orca) {
    $fallback = Join-Path $env:LOCALAPPDATA 'Programs\orca\resources\bin\orca.exe'
    if (Test-Path -LiteralPath $fallback) { $Orca = $fallback }
}
if (-not $Orca) { throw "Khong tim thay orca CLI." }

$openPaths = @{}
try {
    $raw = & $Orca terminal list --json
    $list = ($raw -join "`n") | ConvertFrom-Json
    foreach ($t in $list.result.terminals) {
        if ($t.orphaned) { continue }
        $openPaths[$t.worktreePath] = ($openPaths[$t.worktreePath] + 1)
    }
} catch { }

# ---- Khong co tham so: liet ke ----
if (-not $Name) {
    Write-Host ""
    Write-Host "Project co the mo:" -ForegroundColor Cyan
    foreach ($p in $projects) {
        $n = $openPaths[$p.Path]
        $state = if ($n) { "dang mo ($n pane)" } else { "dang ngu" }
        $color = if ($n) { 'Green' } else { 'DarkGray' }
        Write-Host ("   {0,-26} {1}" -f $p.Name, $state) -ForegroundColor $color
    }
    Write-Host ""
    Write-Host "Mo mot project:  .\open-project.ps1 <ten>" -ForegroundColor DarkGray
    Write-Host "Khop mot phan cung duoc, vi du: .\open-project.ps1 e16"
    Write-Host ""
    return
}

# ---- Co tham so: mo ----
$match = @($projects | Where-Object { $_.Name -like "*$Name*" -or $_.Path -like "*$Name*" })

if ($match.Count -eq 0) {
    Write-Warning "Khong co project nao khop '$Name'. Chay khong tham so de xem danh sach."
    return
}
if ($match.Count -gt 1) {
    Write-Warning "'$Name' khop $($match.Count) project - noi ro hon:"
    foreach ($m in $match) { Write-Host "   $($m.Name)" }
    return
}

$target = $match[0]
if ($openPaths[$target.Path]) {
    Write-Host "$($target.Name) dang mo roi ($($openPaths[$target.Path]) pane)." -ForegroundColor Yellow
    Write-Host "Muon dung lai tu dau thi dong tab do trong Orca roi chay lai lenh nay."
    return
}

Write-Host "Dang mo $($target.Name)..." -ForegroundColor Cyan
& $LayoutScript -Project $target.Name
