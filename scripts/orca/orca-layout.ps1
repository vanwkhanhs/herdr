<#
.SYNOPSIS
    Dung layout builder/reviewer/debug cho cac project trong Orca.

.DESCRIPTION
    Moi project thanh MOT tab mang ten project, chia 3 pane:
      builder  - claude --continue, resume phien gan nhat cua thu muc do
      reviewer - claude, phien moi tach biet voi builder
      debug    - PowerShell thuan

    Ten pane ghim bang WindowTitle + CLAUDE_CODE_DISABLE_TERMINAL_TITLE=1, vi Orca
    hien thi title song cua tien trinh chu khong phai ten dat bang 'terminal rename'.
    Ten tab dat bang 'terminal rename' - mot tab chi co mot ten, dung chung cho ca 3 pane.

    Idempotent:
      - Project da co tu 3 pane tro len  -> bo qua.
      - Project dang co agent chay       -> bo qua kem canh bao, khong dong gi.
      - Project chi con terminal trong   -> dong roi dung lai 3 pane.

.PARAMETER Project
    Chi xu ly mot project, khop theo ten hoac duong dan. Bo trong = tat ca.

.PARAMETER DryRun
    Chi in ra se lam gi, khong goi Orca.

.EXAMPLE
    .\orca-layout.ps1
    .\orca-layout.ps1 -Project KZ_E02.NET
    .\orca-layout.ps1 -DryRun
#>

[CmdletBinding()]
param(
    [string]$Project,
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

# ---- Danh sach project. Them project moi = them mot dong o day. ----
$Projects = @(
    @{ Name = 'KZ_E02.NET';               Path = 'E:/Kztek_Firmwave/Access_Control/KZ_E02.NET' }
    @{ Name = 'kz_e32.net_firmware-dev1'; Path = 'E:/Kztek_Firmwave/Elevator/kz_e32.net_firmware-dev1' }
    @{ Name = 'kz_e16.net_firmware-dev1'; Path = 'E:/Kztek_Firmwave/Elevator/kz_e16.net_firmware-dev1' }
    @{ Name = 'smart_lock_control_12ch';  Path = 'E:/Kztek_Firmwave/iLocker/board_12ch/smart_lock_control_12ch' }
    @{ Name = 'KzFlashTool';              Path = 'E:/Kztek_Firmwave/KzFlashTool' }
)

# ---- Lenh khoi dong tung pane.
# ---- Chi dung nhay don (long nhau bang cach nhan doi). PowerShell 5.1 lam hong
# ---- nhay kep khi truyen chuoi sang file exe, nen tuyet doi khong dung nhay kep.
$CmdBuilder  = '$env:CLAUDE_CODE_DISABLE_TERMINAL_TITLE=1; $host.UI.RawUI.WindowTitle=''builder''; claude --continue'
$CmdReviewer = '$env:CLAUDE_CODE_DISABLE_TERMINAL_TITLE=1; $host.UI.RawUI.WindowTitle=''reviewer''; claude'
$CmdDebug    = '$host.UI.RawUI.WindowTitle=''debug'''

# ---- Tim orca CLI ----
$Orca = (Get-Command orca -ErrorAction SilentlyContinue).Source
if (-not $Orca) {
    $fallback = Join-Path $env:LOCALAPPDATA 'Programs\orca\resources\bin\orca.exe'
    if (Test-Path -LiteralPath $fallback) { $Orca = $fallback }
}
if (-not $Orca) { throw "Khong tim thay orca CLI trong PATH va cung khong co o LOCALAPPDATA." }

function Invoke-Orca {
    param([string[]]$OrcaArgs)
    $raw = & $Orca @OrcaArgs
    if (-not $raw) { return $null }
    try { return (($raw -join "`n") | ConvertFrom-Json) } catch { return $null }
}

# Orca doi hinh dang JSON giua cac lenh (result.terminal vs result.pane),
# nen tim thuoc tinh 'handle' o bat ky dau trong cay tra ve.
function Find-Handle {
    param($Node)
    if ($null -eq $Node -or $Node -is [string] -or $Node -is [ValueType]) { return $null }
    foreach ($p in $Node.PSObject.Properties) {
        if ($p.Name -eq 'handle' -and $p.Value -is [string]) { return $p.Value }
    }
    foreach ($p in $Node.PSObject.Properties) {
        $v = Find-Handle $p.Value
        if ($v) { return $v }
    }
    return $null
}

$targets = $Projects
if ($Project) {
    $targets = @($Projects | Where-Object { $_.Name -like "*$Project*" -or $_.Path -like "*$Project*" })
    if ($targets.Count -eq 0) { throw "Khong co project nao khop '$Project'." }
}

$listed = Invoke-Orca @('terminal','list','--json')
if ($null -eq $listed) { throw "Khong doc duoc danh sach terminal - Orca da chay chua?" }
$all = @($listed.result.terminals)

$built = 0; $skipped = 0; $failed = 0

foreach ($p in $targets) {
    $mine = @($all | Where-Object { $_.worktreePath -eq $p.Path })

    if ($mine.Count -ge 3) {
        Write-Host ("  bo qua   {0}  (da co {1} pane)" -f $p.Name, $mine.Count) -ForegroundColor DarkGray
        $skipped++; continue
    }

    $live = @($mine | Where-Object { $_.agentIdentity })
    if ($live.Count -gt 0) {
        Write-Warning ("{0}: dang co {1} agent chay - bo qua de khong dong nham viec dang lam" -f $p.Name, $live.Count)
        $skipped++; continue
    }

    if ($DryRun) {
        Write-Host ("  [thu]    {0}  (dong {1} terminal trong, dung 3 pane)" -f $p.Name, $mine.Count)
        continue
    }

    foreach ($t in $mine) { Invoke-Orca @('terminal','close','--terminal',$t.handle,'--json') | Out-Null }

    $bh = Find-Handle (Invoke-Orca @('terminal','create','--worktree',"path:$($p.Path)",'--title',$p.Name,'--command',$CmdBuilder,'--json'))
    if (-not $bh) {
        Write-Warning ("{0}: tao pane builder that bai" -f $p.Name)
        $failed++; continue
    }

    $rh = Find-Handle (Invoke-Orca @('terminal','split','--terminal',$bh,'--direction','vertical','--command',$CmdReviewer,'--json'))
    if ($rh) {
        Find-Handle (Invoke-Orca @('terminal','split','--terminal',$rh,'--direction','horizontal','--command',$CmdDebug,'--json')) | Out-Null
    } else {
        Write-Warning ("{0}: tao pane reviewer that bai - tab chi co builder" -f $p.Name)
    }

    Invoke-Orca @('terminal','rename','--terminal',$bh,'--title',$p.Name,'--json') | Out-Null

    Write-Host ("  OK       {0}" -f $p.Name) -ForegroundColor Green
    $built++
}

Write-Host ""
Write-Host ("Dung moi: {0}  |  bo qua: {1}  |  that bai: {2}" -f $built, $skipped, $failed) -ForegroundColor Cyan
