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

    Idempotent, quyet dinh theo CO AGENT HAY KHONG (khong theo so pane):
      - Project dang co agent chay     -> bo qua, khong dong gi.
      - Project khong co agent nao      -> dong terminal trong roi dung lai 3 pane.

    Khong xet so pane la co y: sau khi tat may bat lai, Orca khoi phuc dung so
    tab cu nhung KHONG chay lai lenh khoi dong, nen 3 pane do chi la shell trong.
    Neu xet theo so pane thi script se bo qua va khong project nao co Claude.

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

# ---- Lenh khoi dong: goi pane.ps1, giu chuoi that ngan.
# ---- Orca go lai chuoi nay vao shell moi lan khoi dong lai; chuoi dai bi cat
# ---- giua chung (da gap that). Moi logic nam trong pane.ps1, khong nam o day.
# ---- Chi dung nhay don - PowerShell 5.1 lam hong nhay kep khi truyen sang exe.
$PaneScript = Join-Path $PSScriptRoot 'pane.ps1'

function New-PaneCommand {
    param([string]$Role, [string]$SessionId)
    $cmd = "& '$PaneScript' -Role $Role"
    if ($SessionId) { $cmd += " -SessionId $SessionId" }
    return $cmd
}

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

# ---- Lay session-id tung pane tu Herdr ----
# Herdr luu session-id rieng cho tung pane (builder/reviewer) va tu resume dung
# phien do sau khi khoi dong lai - do la ly do no hien duoc lich sur ca hai ben.
# Orca khong co co che nay, nen ta muon id cua Herdr de resume y het.
# Herdr khong chay thi tra ve bang rong; pane se lui ve --continue / phien moi.
function Get-HerdrSessions {
    $herdr = (Get-Command herdr -ErrorAction SilentlyContinue)
    if (-not $herdr) { return @{} }

    try { $raw = & $herdr.Source pane list } catch { return @{} }
    if (-not $raw) { return @{} }

    try { $parsed = ($raw -join "`n") | ConvertFrom-Json } catch { return @{} }
    if (-not $parsed.result.panes) { return @{} }

    $map = @{}
    foreach ($pane in $parsed.result.panes) {
        if (-not $pane.agent_session) { continue }
        if ($pane.label -ne 'builder' -and $pane.label -ne 'reviewer') { continue }

        # Herdr tra cwd dung dau '\', Orca dung '/' - chuan hoa de khop duoc
        $key = ($pane.cwd -replace '\\', '/').TrimEnd('/').ToLowerInvariant()
        if (-not $map.ContainsKey($key)) { $map[$key] = @{} }
        $map[$key][$pane.label] = $pane.agent_session.value
    }
    return $map
}

$herdrSessions = Get-HerdrSessions
if ($herdrSessions.Count -gt 0) {
    Write-Host ("  (lay session-id tu Herdr cho {0} thu muc)" -f $herdrSessions.Count) -ForegroundColor DarkGray
} else {
    Write-Host "  (Herdr khong chay hoac khong co session - dung --continue)" -ForegroundColor DarkGray
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

    # Quyet dinh dua tren CO AGENT HAY KHONG, khong dua tren so pane.
    # Sau khi tat may bat lai, Orca khoi phuc dung so tab cu nhung lenh khoi dong
    # KHONG chay lai - 3 pane do chi la shell trong. Neu xet theo so pane thi
    # script se bo qua va khong project nao co Claude.
    $live = @($mine | Where-Object { $_.agentIdentity })
    if ($live.Count -gt 0) {
        Write-Host ("  bo qua   {0}  (da co {1} agent chay)" -f $p.Name, $live.Count) -ForegroundColor DarkGray
        $skipped++; continue
    }

    if ($DryRun) {
        Write-Host ("  [thu]    {0}  (dong {1} terminal trong, dung 3 pane)" -f $p.Name, $mine.Count)
        continue
    }

    foreach ($t in $mine) { Invoke-Orca @('terminal','close','--terminal',$t.handle,'--json') | Out-Null }

    $key = $p.Path.TrimEnd('/').ToLowerInvariant()
    $sids = $herdrSessions[$key]
    $CmdBuilder  = New-PaneCommand -Role builder  -SessionId $sids.builder
    $CmdReviewer = New-PaneCommand -Role reviewer -SessionId $sids.reviewer
    $CmdDebug    = New-PaneCommand -Role debug

    $tag = if ($sids.builder -or $sids.reviewer) { 'session tu Herdr' } else { 'khong co session Herdr' }

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

    Write-Host ("  OK       {0}  ({1})" -f $p.Name, $tag) -ForegroundColor Green
    $built++
}

Write-Host ""
Write-Host ("Dung moi: {0}  |  bo qua: {1}  |  that bai: {2}" -f $built, $skipped, $failed) -ForegroundColor Cyan
