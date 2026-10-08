<#
.SYNOPSIS
    Xoa ban ghi "sleeping agent session" thua cua cac project duoc quan ly.

.DESCRIPTION
    Moi lan dung lai layout, Orca ghi them mot cap ban ghi resume theo pane-key
    moi va giu lai cap cu. Ket qua: duoi moi project hien 4 agent trong khi chi
    co 2 dang chay - hai cai kia tro ve dung hai hoi thoai do, chi la ban ghi
    resume thua.

    Script nay xoa cac ban ghi do khoi kho trang thai cua Orca
    (profiles\local-default\profile-state.db, document 'workspaceSession').

    Chi dong den worktree cua cac project liet ke trong orca-layout.ps1.
    Worktree khac - vi du herdr-backup - duoc giu nguyen de van tu resume duoc.

    BAT BUOC tat han Orca truoc khi chay, neu khong Orca se ghi de lai tu bo nho.
    Script tu kiem tra va tu sao luu CSDL truoc khi sua.

    Luu y: sau lan mo Orca ke tiep, con so se lai thanh 4 - vi moi lan dung layout
    deu de lai mot cap. Day la don mot lan, khong phai sua tan goc.

.EXAMPLE
    .\clean-sleeping-sessions.ps1
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

# ---- 1. Orca phai tat han ----
$orcaProcs = @(Get-Process -Name orca -ErrorAction SilentlyContinue)
if ($orcaProcs.Count -gt 0) {
    Write-Host ""
    Write-Host "Orca dang chay ($($orcaProcs.Count) tien trinh)." -ForegroundColor Red
    Write-Host "Tat han Orca roi chay lai script nay - neu khong no se ghi de lai tu bo nho."
    Write-Host ""
    return
}

# ---- 2. node phai co ----
$node = (Get-Command node -ErrorAction SilentlyContinue)
if (-not $node) { throw "Khong tim thay node - can node de doc CSDL SQLite cua Orca." }

$Db = Join-Path $env:APPDATA 'orca\profiles\local-default\profile-state.db'
if (-not (Test-Path -LiteralPath $Db)) { throw "Khong thay CSDL: $Db" }

# ---- 3. Lay danh sach project tu orca-layout.ps1 (mot nguon su that duy nhat) ----
$LayoutScript = Join-Path $PSScriptRoot 'orca-layout.ps1'
if (-not (Test-Path -LiteralPath $LayoutScript)) { throw "Khong thay orca-layout.ps1" }

$paths = @()
foreach ($line in (Get-Content -LiteralPath $LayoutScript)) {
    if ($line -match "Path\s*=\s*'([^']+)'") { $paths += $Matches[1] }
}
if ($paths.Count -eq 0) { throw "Khong doc duoc duong dan project nao tu orca-layout.ps1" }

Write-Host "Project duoc quan ly ($($paths.Count)):" -ForegroundColor Cyan
foreach ($p in $paths) { Write-Host "   $p" }

# ---- 4. Sao luu ----
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
foreach ($ext in @('', '-wal', '-shm')) {
    $src = "$Db$ext"
    if (Test-Path -LiteralPath $src) {
        Copy-Item -LiteralPath $src -Destination "$src.bak-$stamp" -Force
    }
}
Write-Host ""
Write-Host "Da sao luu CSDL: $Db.bak-$stamp" -ForegroundColor DarkGray

# ---- 5. Sua ----
$js = Join-Path $PSScriptRoot 'clean-sleeping-sessions.js'
if (-not (Test-Path -LiteralPath $js)) { throw "Khong thay clean-sleeping-sessions.js" }

Write-Host ""
& $node.Source $js $Db @paths
Write-Host ""
Write-Host "Xong. Mo lai Orca de thay ket qua." -ForegroundColor Green
Write-Host "Muon hoan tac: chep de len $Db tu file .bak-$stamp (khi Orca dang tat)."
