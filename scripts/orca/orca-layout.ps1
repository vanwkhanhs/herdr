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

    Idempotent. Chi bo qua khi layout THUC SU LANH:
      - Du ba pane dung ten builder/reviewer/debug VA co agent chay -> bo qua.
      - Moi truong hop khac -> dong het roi dung lai 3 pane.

    Hai dieu kien, thieu mot la dung lai:
      * Khong xet so pane: sau khi tat may bat lai, Orca khoi phuc dung so tab
        cu nhung KHONG chay lai lenh khoi dong - do chi la shell trong.
      * Khong chi xet 'co agent': Orca van bao agentIdentity=claude cho pane
        khoi phuc hong (lenh bi cat cut, ten pane ve '* Claude Code'). Da gap
        that - script bo qua va de nguyen trang thai hong.

    Ten pane la bang chung tin cay vi chi pane.ps1 moi dat duoc dung ba ten do.

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
    [switch]$DryRun,
    [switch]$Prune
)

$ErrorActionPreference = 'Stop'

# ---- Danh sach project. Them project moi = them mot dong o day. ----
$Projects = @(
    @{ Name = 'KZ_E02.NET';               Path = 'E:/Kztek_Firmwave/Access_Control/KZ_E02.NET' }
    @{ Name = 'kz_e32.net_firmware-dev1'; Path = 'E:/Kztek_Firmwave/Elevator/kz_e32.net_firmware-dev1' }
    @{ Name = 'kz_e16.net_firmware-dev1'; Path = 'E:/Kztek_Firmwave/Elevator/kz_e16.net_firmware-dev1' }
    @{ Name = 'smart_lock_control_12ch';  Path = 'E:/Kztek_Firmwave/iLocker/board_12ch/smart_lock_control_12ch' }
    @{ Name = 'KzFlashTool';              Path = 'E:/Kztek_Firmwave/KzFlashTool' }

    # Khong co space tuong ung ben Herdr nen khong co session-id trong dem:
    # builder lui ve 'claude --continue', reviewer la phien moi.
    @{ Name = 'herdr-backup';             Path = 'E:/Kztek_Firmwave/herdr-backup' }
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

    # Herdr chua chay thi lenh nay in loi JSON ra console. Nuot di: day la
    # truong hop binh thuong (watcher chay truoc khi nguoi dung go 'herdr'),
    # khong phai loi can hien ra man hinh.
    try { $raw = & $herdr.Source pane list 2>$null } catch { return @{} }
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

# ---- Nho dem session-id ra dia ----
# Watcher chay ngay khi Orca mo, thuong SOM HON luc nguoi dung go 'herdr'. Luc do
# Herdr chua chay -> khong lay duoc id -> reviewer mat sach lich su (builder con
# nho --continue). Da gap that sau lan reset: 5/5 reviewer la phien moi.
# Session-id cua Herdr on dinh qua cac lan khoi dong lai, nen dem lai dung duoc.
$SessionCache = Join-Path $PSScriptRoot 'herdr-sessions.json'

function Save-SessionCache {
    param($Map)
    try { ($Map | ConvertTo-Json -Depth 5) | Set-Content -LiteralPath $SessionCache -Encoding utf8 } catch { }
}

function Read-SessionCache {
    if (-not (Test-Path -LiteralPath $SessionCache)) { return @{} }
    try { $obj = (Get-Content -LiteralPath $SessionCache -Raw) | ConvertFrom-Json } catch { return @{} }
    if (-not $obj) { return @{} }

    # ConvertFrom-Json tra PSCustomObject, phai doi nguoc ve hashtable
    $map = @{}
    foreach ($entry in $obj.PSObject.Properties) {
        $inner = @{}
        foreach ($role in $entry.Value.PSObject.Properties) { $inner[$role.Name] = $role.Value }
        $map[$entry.Name] = $inner
    }
    return $map
}

$herdrSessions = Get-HerdrSessions
if ($herdrSessions.Count -gt 0) {
    Save-SessionCache $herdrSessions
    Write-Host ("  (session-id tu Herdr dang chay, {0} thu muc - da luu dem)" -f $herdrSessions.Count) -ForegroundColor DarkGray
} else {
    $herdrSessions = Read-SessionCache
    if ($herdrSessions.Count -gt 0) {
        Write-Host ("  (Herdr chua chay - dung dem session-id, {0} thu muc)" -f $herdrSessions.Count) -ForegroundColor DarkGray
    } else {
        Write-Host "  (khong co session-id nao - dung --continue / phien moi)" -ForegroundColor DarkGray
    }
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

    # Chi bo qua khi layout THUC SU LANH: du ba pane dung ten VA co agent chay.
    #
    # Khong xet so pane: sau khi tat may bat lai, Orca khoi phuc dung so tab cu
    # nhung do chi la shell trong.
    #
    # Khong chi xet 'co agent': Orca van bao agentIdentity=claude cho nhung pane
    # khoi phuc hong (lenh khoi dong bi cat cut, ten pane ve '* Claude Code').
    # Da gap that - script bo qua va de nguyen trang thai hong.
    #
    # Ten pane la bang chung tin cay: chi pane.ps1 moi dat duoc dung ba ten nay
    # (WindowTitle + CLAUDE_CODE_DISABLE_TERMINAL_TITLE=1). Khoi phuc hong thi
    # ten se khac.
    $live   = @($mine | Where-Object { $_.agentIdentity })
    $titles = @($mine | ForEach-Object { [string]$_.title })
    $named  = ($titles -contains 'builder') -and ($titles -contains 'reviewer') -and ($titles -contains 'debug')

    if ($live.Count -gt 0 -and $named) {
        # Orca khoi phuc pane cu CHAM hon luc watcher dung layout, nen chung hien
        # ra sau va thanh pane thua (da gap 2 lan trong mot lan reset). Lan chay
        # co -Prune se don: pane nao trong worktree nay ma khong mang dung mot
        # trong ba ten builder/reviewer/debug deu la do khoi phuc muon.
        if ($Prune) {
            $extra = @($mine | Where-Object { @('builder','reviewer','debug') -notcontains [string]$_.title })
            foreach ($t in $extra) { Invoke-Orca @('terminal','close','--terminal',$t.handle,'--json') | Out-Null }
            if ($extra.Count -gt 0) {
                Write-Host ("  don     {0}  (dong {1} pane khoi phuc muon)" -f $p.Name, $extra.Count) -ForegroundColor Yellow
            }
        }
        Write-Host ("  bo qua   {0}  (layout lanh, {1} agent chay)" -f $p.Name, $live.Count) -ForegroundColor DarkGray
        $skipped++; continue
    }

    if ($live.Count -gt 0) {
        Write-Warning ("{0}: co {1} agent nhung ten pane sai - khoi phuc hong, dung lai" -f $p.Name, $live.Count)
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
