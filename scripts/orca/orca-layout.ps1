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

    Vai tro theo tung project: mac dinh builder+reviewer+debug. Project chi can
    hai pane thi khai bao Roles trong $Projects, vd herdr-backup khong can reviewer:
      @{ Name = ...; Path = ...; Roles = @('builder', 'debug') }

    Idempotent. Chi bo qua khi layout THUC SU LANH:
      - Du cac pane dung ten theo Roles VA co agent chay -> bo qua.
      - Moi truong hop khac -> dong het roi dung lai.

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
    [switch]$Prune,

    # Dong het terminal cua cac project duoc quan ly, dua tat ca ve trang thai ngu.
    # Dung '--worktree --all' nen Orca xoa luon tab, layout va resume record - lan
    # mo Orca sau no khong khoi phuc gi cho nhung project nay.
    [switch]$SleepAll
)

$ErrorActionPreference = 'Stop'

# ---- Danh sach project. Them project moi = them mot dong o day. ----
$Projects = @(
    @{ Name = 'KZ_E02.NET';               Path = 'E:/Kztek_Firmwave/Access_Control/KZ_E02.NET' }
    @{ Name = 'kz_e32.net_firmware-dev1'; Path = 'E:/Kztek_Firmwave/Elevator/kz_e32.net_firmware-dev1' }
    @{ Name = 'kz_e16.net_firmware-dev1'; Path = 'E:/Kztek_Firmwave/Elevator/kz_e16.net_firmware-dev1' }
    @{ Name = 'smart_lock_control_12ch';  Path = 'E:/Kztek_Firmwave/iLocker/board_12ch/smart_lock_control_12ch' }
    @{ Name = 'KzFlashTool';              Path = 'E:/Kztek_Firmwave/KzFlashTool' }

    # Hai thu muc nay von khong phai git repo - da 'git init' de Orca nhan
    # (orca repo add tu choi thu muc khong phai git). Khong commit gi, chi tao .git.
    @{ Name = 'RV1126B dual cam 5MP';     Path = 'E:/project_kztek/SDK_RV1126B' }
    @{ Name = 'SSC37X_CAM';               Path = 'E:/project_kztek/SSC37X_CAM' }

    # CO Y KHONG quan ly herdr-backup (hien thi trong Orca la 'orca-backup').
    # Day la pane nguoi dung ngoi lam viec truc tiep; dua vao danh sach thi
    # watcher se dong no va dung lai moi lan mo Orca, cat ngang viec dang lam.
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

# ---- Dong terminal mo coi ----
# Khi Orca khoi dong lai, tab tren giao dien mat nhung PTY van song: Orca bao
# chung voi orphaned=true, title=null, va van gan agentIdentity=claude. Nguoi
# dung thay chung hien ra nhu agent thua duoi project (da gap: smart_lock 6 xac,
# 4 trong do mang agent). Chung khong co tab nen khong dung duoc vao viec gi.
#
# Chi dong xac trong worktree cua cac project duoc quan ly - khong dung toi
# project khac, nhat la pane nguoi dung dang ngoi lam viec.
$managed = @($Projects | ForEach-Object { $_.Path })

# ---- -SleepAll: cho tat ca ngu roi thoat ----
if ($SleepAll) {
    $n = 0
    foreach ($p in $targets) {
        $mine = @($all | Where-Object { $_.worktreePath -eq $p.Path })
        if ($mine.Count -eq 0) { continue }
        if ($DryRun) { Write-Host ("  [thu]    cho ngu {0} ({1} terminal)" -f $p.Name, $mine.Count); continue }
        Invoke-Orca @('terminal','close','--worktree',"path:$($p.Path)",'--all','--json') | Out-Null
        Write-Host ("  ngu      {0}  (dong {1} terminal)" -f $p.Name, $mine.Count) -ForegroundColor DarkGray
        $n++
    }
    Write-Host ""
    Write-Host ("Da cho ngu: {0} project" -f $n) -ForegroundColor Cyan
    return
}

$orphans = @($all | Where-Object { $_.orphaned -and ($managed -contains $_.worktreePath) })

if ($orphans.Count -gt 0) {
    if ($DryRun) {
        Write-Host ("  [thu]    se dong {0} terminal mo coi" -f $orphans.Count) -ForegroundColor Yellow
    } else {
        foreach ($t in $orphans) { Invoke-Orca @('terminal','close','--terminal',$t.handle,'--json') | Out-Null }
        Write-Host ("  don     {0} terminal mo coi (xac PTY sau khi Orca khoi dong lai)" -f $orphans.Count) -ForegroundColor Yellow
        $all = @($all | Where-Object { -not $_.orphaned })
    }
}

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
    # Ten pane la bang chung tin cay: chi pane.ps1 moi dat duoc dung cac ten nay
    # (WindowTitle + CLAUDE_CODE_DISABLE_TERMINAL_TITLE=1). Khoi phuc hong thi
    # ten se khac.
    #
    # Vai tro theo tung project: mac dinh du ba, nhung project chi can hai thi
    # khai bao Roles trong $Projects (vd herdr-backup khong can reviewer).
    $roles = if ($p.Roles) { @($p.Roles) } else { @('builder', 'reviewer', 'debug') }

    $live   = @($mine | Where-Object { $_.agentIdentity })
    $titles = @($mine | ForEach-Object { [string]$_.title })
    $named  = $true
    foreach ($r in $roles) { if ($titles -notcontains $r) { $named = $false } }

    if ($live.Count -gt 0 -and $named) {
        # Orca khoi phuc pane cu CHAM hon luc watcher dung layout, nen chung hien
        # ra sau va thanh pane thua (da gap 2 lan trong mot lan reset). Lan chay
        # co -Prune se don: pane nao trong worktree nay ma khong mang dung mot
        # trong cac vai tro cua project deu la do khoi phuc muon.
        if ($Prune) {
            $extra = @($mine | Where-Object { $roles -notcontains [string]$_.title })
            foreach ($t in $extra) { Invoke-Orca @('terminal','close','--terminal',$t.handle,'--json') | Out-Null }
            if ($extra.Count -gt 0) {
                Write-Host ("  don     {0}  (dong {1} pane khoi phuc muon)" -f $p.Name, $extra.Count) -ForegroundColor Yellow
            }
        }
        Write-Host ("  bo qua   {0}  (layout lanh, {1} agent chay)" -f $p.Name, $live.Count) -ForegroundColor DarkGray
        $skipped++; continue
    }

    # Luot -Prune chi DON, khong bao gio dung lai.
    #
    # Luot don dau chay 10 giay sau khi dung layout - luc do pane vua tao con
    # dang khoi dong, chua kip dat ten. Neu de no dung lai thi no pha dung cai
    # vua dung xong. Da gap: mot luot prune dung lai 4 project dang lanh.
    #
    # Viec dung lai thuoc ve luot dau (khong co -Prune). Project that su hong se
    # duoc dung lai o lan mo Orca ke tiep.
    if ($Prune) {
        $skipped++; continue
    }

    if ($live.Count -gt 0) {
        Write-Warning ("{0}: co {1} agent nhung ten pane sai - khoi phuc hong, dung lai" -f $p.Name, $live.Count)
    }

    if ($DryRun) {
        Write-Host ("  [thu]    {0}  (dong {1} terminal, dung {2} pane: {3})" -f $p.Name, $mine.Count, $roles.Count, ($roles -join '+'))
        continue
    }

    # Dong bang '--worktree <path> --all' chu KHONG dong tung pane mot.
    #
    # Dong tung pane de lai "resume record" cho moi pane co agent, nen moi lan
    # dung lai layout Orca cong them mot cap va duoi project hien 4 agent trong
    # khi chi co 2 dang chay. Dang --all duoc tai lieu ghi ro la "durably removes
    # its terminal tabs, layouts, and resume records".
    #
    # Da do: KzFlashTool 4 -> 2 ngay sau khi dong kieu nay, va dung lai van giu 2.
    #
    # Nhung dang '--all' cho ban cho ghi ben nen cham. Chi can no khi co agent
    # dang chay, vi do la luc Orca sinh resume record. Project chi co shell trong
    # - dung luc nguoi dung vua bam mo - thi dong tung cai, nhanh hon han.
    if (@($mine | Where-Object { $_.agentIdentity }).Count -gt 0) {
        Invoke-Orca @('terminal','close','--worktree',"path:$($p.Path)",'--all','--json') | Out-Null
    } else {
        foreach ($t in $mine) { Invoke-Orca @('terminal','close','--terminal',$t.handle,'--json') | Out-Null }
    }

    $key  = $p.Path.TrimEnd('/').ToLowerInvariant()
    $sids = $herdrSessions[$key]
    $tag  = if ($sids.builder -or $sids.reviewer) { 'session tu Herdr' } else { 'khong co session Herdr' }

    # Pane dau tien tao tab moi; cac pane sau tach ra tu pane truoc do.
    # Huong: pane thu hai tach doc (sang phai), tu pane thu ba tach ngang
    # (xuong duoi) - cho ra builder | reviewer tren, debug duoi reviewer.
    $first = $roles[0]
    $bh = Find-Handle (Invoke-Orca @('terminal','create','--worktree',"path:$($p.Path)",'--title',$p.Name,'--command',(New-PaneCommand -Role $first -SessionId $sids.$first),'--json'))
    if (-not $bh) {
        Write-Warning ("{0}: tao pane {1} that bai" -f $p.Name, $first)
        $failed++; continue
    }

    $prev = $bh
    for ($i = 1; $i -lt $roles.Count; $i++) {
        $role = $roles[$i]
        $dir  = if ($i -eq 1) { 'vertical' } else { 'horizontal' }
        $h = Find-Handle (Invoke-Orca @('terminal','split','--terminal',$prev,'--direction',$dir,'--command',(New-PaneCommand -Role $role -SessionId $sids.$role),'--json'))
        if (-not $h) {
            Write-Warning ("{0}: tao pane {1} that bai - tab thieu pane" -f $p.Name, $role)
            break
        }
        $prev = $h
    }

    Invoke-Orca @('terminal','rename','--terminal',$bh,'--title',$p.Name,'--json') | Out-Null

    # Dua tab vua dung len truoc, nhung CHI khi dung mot project cu the.
    #
    # 'terminal create' mac dinh tao tab o nen, nen sau khi watcher dung xong
    # nguoi dung van thay man hinh cu va phai bam them lan nua moi thay project.
    #
    # Khong lam khi dung nhieu project cung luc (-BuildAll): luc do focus se nhay
    # lung tung roi dung o cai cuoi cung, khong phai cai nguoi dung muon.
    if ($Project) {
        Invoke-Orca @('terminal','switch','--terminal',$bh,'--json') | Out-Null
    }

    Write-Host ("  OK       {0}  ({1})" -f $p.Name, $tag) -ForegroundColor Green
    $built++
}

# ---- Don lich su terminal da chet ----
# Moi terminal bi dong de lai mot thu muc scrollback trong
# %APPDATA%\orca\terminal-history\<ptyId ma hoa URL>. Orca liet ke chung duoi
# project nhu agent kem tuoi, nen sau vai lan dung lai layout nguoi dung thay
# 4-6 agent trong khi chi co 2 dang song. Moi lan Orca khoi dong lai lai cong
# them mot bo - don tay mot lan khong giai quyet duoc.
#
# Chi xoa thu muc cua worktree duoc quan ly va KHONG gan voi terminal nao dang
# song. Project khac khong bi dung toi.
if (-not $DryRun) {
    $histRoot = Join-Path $env:APPDATA 'orca\terminal-history'
    if (Test-Path -LiteralPath $histRoot) {
        $after = Invoke-Orca @('terminal','list','--json')
        if ($after) {
            $livePty = @($after.result.terminals | ForEach-Object { $_.ptyId })
            $dead = 0
            foreach ($dir in (Get-ChildItem -LiteralPath $histRoot -Directory -ErrorAction SilentlyContinue)) {
                if ($dir.Name -eq '.pending-delete') { continue }
                $decoded = [System.Uri]::UnescapeDataString($dir.Name)
                if ($livePty -contains $decoded) { continue }
                if (-not ($managed | Where-Object { $decoded -like "*$_*" })) { continue }
                try { Remove-Item -LiteralPath $dir.FullName -Recurse -Force -ErrorAction Stop; $dead++ } catch { }
            }
            if ($dead -gt 0) {
                Write-Host ("  don     {0} thu muc lich su terminal da chet" -f $dead) -ForegroundColor Yellow
            }
        }
    }
}

Write-Host ""
Write-Host ("Dung moi: {0}  |  bo qua: {1}  |  that bai: {2}" -f $built, $skipped, $failed) -ForegroundColor Cyan
