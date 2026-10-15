<#
.SYNOPSIS
    Theo doi Orca: cho moi project ngu khi mo app, va dung layout khi nguoi dung
    bam vao mot project o sidebar.

.DESCRIPTION
    Hai viec, tach bach:

    1. **Lan mo Orca moi** (nhan ra bang runtimeId doi) -> cho tat ca project
       duoc quan ly NGU. Khong dung pane nao. Moi pane Claude an ~440 MB; dung
       du 7 project la ~6,6 GB ngay khi mo Orca cho nhung thu chua dung den.

       Dung 'terminal close --worktree <path> --all', dang nay Orca xoa luon tab,
       layout va resume record - nen lan mo sau no cung khong khoi phuc gi.

    2. **Nguoi dung bam vao mot project o sidebar** -> Orca mo mot PowerShell
       trong, khong Claude, khong lich su. Watcher thay project do co terminal
       nhung chua co pane ten 'builder' thi dung day du builder + reviewer + debug,
       resume dung phien cu.

    Vi buoc 1 da xoa sach tab va resume record, moi terminal xuat hien sau do
    trong mot project deu la do nguoi dung tu bam - khong con nham voi tab Orca
    tu khoi phuc nua.

    Nhan dien lan mo moi bang runtimeId chu khong bang "co thay Orca tat khong":
    watcher poll 5 giay mot lan, nguoi dung dong roi mo lai Orca nhanh hon the
    nen khong bao gio thay khoang trong. Da hong that - 4/5 project mat sach pane
    ma watcher van tuong dang la phien cu.

.PARAMETER PollMs
    Nhip kiem tra, mili giay. Mac dinh 400.

.PARAMETER SettleSeconds
    Cho bao lau sau khi runtime ready moi cho ngu. Mac dinh 12 giay.

.PARAMETER BuildAll
    Tro lai kieu cu: mo Orca la dung du tat ca project. Mac dinh TAT.

.EXAMPLE
    .\orca-layout-watcher.ps1
    .\orca-layout-watcher.ps1 -BuildAll
#>

[CmdletBinding()]
param(
    # Nhip quet 400 ms (truoc la 1 giay - nguoi dung bam phai cho). Re vi vong lap o trang thai thuong chi goi
    # get-active-worktree.js (~74 ms) - re hon han 'orca status' (~243 ms) va
    # 'orca terminal list' (~249 ms), va hai cai do chi goi khi that su can.
    [int]$PollMs        = 400,

    [int]$SettleSeconds = 12,

    # Cua so an han sau khi cho ngu: trong khoang nay, terminal nao xuat hien
    # trong project duoc quan ly deu bi coi la Orca khoi phuc muon va bi cho ngu
    # tiep, KHONG dung layout.
    #
    # Can co vi 'close --all' khong chan het duoc: da do thay Orca van khoi phuc
    # them tab cho mot project khac sau khi da ngu, va watcher tuong nguoi dung
    # bam vao do roi dung layout khong ai yeu cau.
    #
    # Danh doi: bam vao project trong khoang nay se bi dong, bam lai la duoc. Vi
    # vay giu that ngan - dot khoi phuc muon do duoc den trong ~25 giay sau khi ngu.
    [int]$SleepGraceSeconds = 45,

    # Tu dung layout khi thay nguoi dung bam mo mot project. MAC DINH TAT.
    #
    # Tat vi khong co cach dang tin de phan biet "nguoi dung bam" voi "Orca khoi
    # phuc tab cu": ca hai deu chi la terminal xuat hien trong worktree. Da thu
    # phan biet bang thoi gian va bang so pane, van sai - project tu bat len du
    # nguoi dung khong bam, va bat lai ngay sau khi nguoi dung cho ngu.
    #
    # Nay da co tin hieu dang tin: activeWorktreeId trong kho trang thai cua Orca.
    # Bam o sidebar thi no doi, Orca tu khoi phuc tab thi khong. Nen bat mac dinh.
    [bool]$AutoOpen = $true,

    [switch]$BuildAll
)

$ErrorActionPreference = 'Continue'

$LayoutScript = Join-Path $PSScriptRoot 'orca-layout.ps1'
$LogFile      = Join-Path $env:LOCALAPPDATA 'orca-layout-watcher.log'

if (-not (Test-Path -LiteralPath $LayoutScript)) {
    throw "Khong thay orca-layout.ps1 canh watcher: $LayoutScript"
}

function Write-Log {
    param([string]$Message)
    $line = '{0}  {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
    Add-Content -LiteralPath $LogFile -Value $line -Encoding utf8
}

# ---- Tin hieu bam tu MAY KHAC (remote client qua 'orca environment add') ----
#
# Bam project tren may remote KHONG doi activeWorktreeId cua laptop - do that
# 09/10/2026: bam KzFlashTool, KZ_E02, E16 tu may moi, activeWorktreeId dung yen
# o SSC37X_CAM, watcher khong biet gi. Remote client cung khong tu mo terminal.
#
# Dau vet duy nhat: Orca chay 'git check-ignore' trong worktree vua duoc xem, ghi
# vao logs\main.trace.ndjson. Moi lan chuyen sang project khac dung mot lan; dang
# xem thi chay lai moi khi file doi. Nen chi phan ung khi project duoc xem DOI,
# khong phan ung moi lan thay check-ignore - neu khong, nguoi dung cho ngu
# project dang xem xong, Claude/editor sua file la no tu bat lai.
$TraceFile   = Join-Path $env:APPDATA 'orca\logs\main.trace.ndjson'
$traceOffset = 0
$lastViewed  = $null
$traceArmed  = $false

function Reset-TraceCursor {
    # Bo qua moi thu da ghi truoc thoi diem nay (check-ignore luc Orca khoi dong
    # khong phai nguoi dung bam)
    $script:traceOffset = 0
    try { $script:traceOffset = (Get-Item -LiteralPath $TraceFile -ErrorAction Stop).Length } catch { }
    $script:lastViewed = $null
}

function Read-TraceEvents {
    # Tra ve cac su kien moi ke tu lan doc truoc, DUNG THU TU:
    #   Kind='view'  - Orca chay check-ignore trong worktree nay (dang duoc xem)
    #   Kind='close' - MAY REMOTE dong mot tab cua worktree nay
    #
    # Vi sao can 'close': nut Sleep tren may remote khong gui gi sang laptop, cach
    # duy nhat nguoi dung o may remote dep project la DONG TAB. Ma dong tab kieu do
    # de lai ban ghi "agent dang ngu" - do that 22:02:01: 20 giay sau khi dong,
    # Orca tu danh thuc lai bang '--dangerously-skip-permissions --resume', de
    # len layout watcher vua dung. Nen watcher phai dong not bang '--all'.
    try { $len = (Get-Item -LiteralPath $TraceFile -ErrorAction Stop).Length } catch { return @() }
    if ($len -lt $script:traceOffset) { $script:traceOffset = 0 }   # file vua xoay vong
    if ($len -eq $script:traceOffset) { return @() }

    $fs = [IO.File]::Open($TraceFile, 'Open', 'Read', 'ReadWrite')
    try {
        $null = $fs.Seek($script:traceOffset, 'Begin')
        $text = (New-Object IO.StreamReader($fs)).ReadToEnd()
        $script:traceOffset = $fs.Length
    } finally { $fs.Close() }

    $events = @()
    foreach ($line in ($text -split "`n")) {
        if ($line -match '"git\.subcommand":"check-ignore"[^}]*?"cwd":"([^"]+)"') {
            $events += [pscustomobject]@{ Kind = 'view'; Path = ($Matches[1] -replace '\\\\', '/' -replace '\\', '/').TrimEnd('/') }
        } elseif ($line -match '"name":"runtime\.session-tabs\.close"' -and
                  $line -match '"deviceId":"(?!in-process)[^"]+"' -and
                  $line -match '"worktree":"id:[^"]*?::([^"]+)"') {
            $events += [pscustomobject]@{ Kind = 'close'; Path = ($Matches[1] -replace '\\\\', '/' -replace '\\', '/').TrimEnd('/') }
        }
    }
    return $events
}

function Invoke-Layout {
    param([string[]]$LayoutArgs)
    # -WindowStyle Hidden: thieu co nay thi luc dang nhap co mot cua so console
    # nhay len, in ca loi JSON cua 'herdr pane list' khi Herdr chua chay.
    $out = & powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File $LayoutScript @LayoutArgs
    foreach ($l in @($out)) { if ("$l".Trim()) { Write-Log ("  " + $l) } }
}

$Orca = (Get-Command orca -ErrorAction SilentlyContinue).Source
if (-not $Orca) {
    $fallback = Join-Path $env:LOCALAPPDATA 'Programs\orca\resources\bin\orca.exe'
    if (Test-Path -LiteralPath $fallback) { $Orca = $fallback }
}
if (-not $Orca) { throw "Khong tim thay orca CLI." }

# Danh sach project doc tu orca-layout.ps1 - mot nguon su that duy nhat
$Projects = @()
foreach ($line in (Get-Content -LiteralPath $LayoutScript)) {
    if ($line -match "Name\s*=\s*'([^']+)'\s*;\s*Path\s*=\s*'([^']+)'") {
        $Projects += [pscustomobject]@{ Name = $Matches[1]; Path = $Matches[2] }
    }
}
if ($Projects.Count -eq 0) { throw "Khong doc duoc project nao tu orca-layout.ps1" }

Write-Log ("watcher bat dau (poll=${PollMs}ms settle=${SettleSeconds}s, {0} project, BuildAll={1})" -f $Projects.Count, [bool]$BuildAll)

# Neu Orca DANG chay san luc watcher khoi dong, nhan lay runtime do va KHONG coi
# la lan mo moi. Thieu buoc nay thi moi lan khoi dong lai watcher deu cho ngu het,
# dong mat nhung project nguoi dung dang mo - da gap that: nguoi dung vua bam mo
# KZ_E02 luc 15:09:03, watcher khoi dong lai luc 15:09:54 va dong ngay lap tuc.
$lastRuntimeId = $null
try {
    if (Get-Process -Name orca -ErrorAction SilentlyContinue) {
        $s0 = ((& $Orca status --json) -join "`n") | ConvertFrom-Json
        if ($s0.result.runtime.state -eq 'ready') {
            $lastRuntimeId = $s0.result.runtime.runtimeId
            Write-Log "Orca da chay san (runtime $lastRuntimeId) - nhan lay, khong cho ngu"
        }
    }
} catch { }

$graceUntil     = $null
$lastActive     = $null
$builtForActive = $false
$lastStamp      = $null

# Neu Orca dang chay san, nhan lay luon moc khoi dong de khong coi la lan mo moi
$lastOrcaKey = $null
try {
    $p0 = @(Get-Process -Name orca -ErrorAction SilentlyContinue | Sort-Object StartTime)[0]
    if ($p0 -and $lastRuntimeId) { $lastOrcaKey = $p0.StartTime.Ticks }
} catch { }

while ($true) {

    if (-not (Get-Process -Name orca -ErrorAction SilentlyContinue)) {
        if ($lastRuntimeId) { Write-Log "Orca da tat - cho lan mo sau" }
        $lastRuntimeId = $null
        Start-Sleep -Milliseconds $PollMs
        continue
    }

    # Nhan dien lan mo moi bang THOI DIEM KHOI DONG cua tien trinh Orca, khong
    # goi 'orca status' moi nhip - lenh do ton ~243 ms, qua dat de chay moi giay.
    # Chi khi thay Orca vua khoi dong lai moi hoi status de cho chac la da ready.
    $orcaKey = $null
    try {
        $p0 = @(Get-Process -Name orca -ErrorAction SilentlyContinue | Sort-Object StartTime)[0]
        if ($p0) { $orcaKey = $p0.StartTime.Ticks }
    } catch { }

    if ($orcaKey -ne $lastOrcaKey) {
        # Orca vua khoi dong - cho den khi runtime ready roi moi lam gi
        $ready = $false
        try {
            $s = ((& $Orca status --json) -join "`n") | ConvertFrom-Json
            $ready = ($s.result.runtime.state -eq 'ready') -and ($s.result.app.running -eq $true)
            $runtimeId = $s.result.runtime.runtimeId
        } catch { $ready = $false }
        if (-not $ready) { Start-Sleep -Milliseconds $PollMs; continue }
    } else {
        $runtimeId = $lastRuntimeId
    }

    # ---- Lan mo Orca moi ----
    if ($runtimeId -ne $lastRuntimeId) {
        $lastRuntimeId = $runtimeId
        $traceArmed    = $false
        Write-Log "Orca mo moi (runtime $runtimeId) - cho ${SettleSeconds}s"
        Start-Sleep -Seconds $SettleSeconds

        try {
            if ($BuildAll) {
                Write-Log "dung du tat ca project (-BuildAll)"
                Invoke-Layout @()
            } else {
                Write-Log "cho tat ca project ngu"
                Invoke-Layout @('-SleepAll')
                $graceUntil = (Get-Date).AddSeconds($SleepGraceSeconds)
                Write-Log ("an han {0}s - tab Orca khoi phuc muon se bi cho ngu tiep" -f $SleepGraceSeconds)
            }
        } catch {
            Write-Log ("LOI luc mo moi: " + $_.Exception.Message)
        }

        Start-Sleep -Milliseconds $PollMs
        continue
    }

    # ---- Trong cua so an han: cho ngu cac tab Orca khoi phuc muon ----
    #
    # PHAI loai tru project nguoi dung dang mo. Truoc day cho ngu tat ca, ke ca
    # cai vua bam - nguoi dung mo project nao thi no dong project do, lien tiep
    # trong suot 45 giay. Day la loi nang nhat cua co che an han.
    if ($graceUntil -and (Get-Date) -lt $graceUntil) {
        try {
            $activeNow = ''
            try { $activeNow = ((& node (Join-Path $PSScriptRoot 'get-active-worktree.js')) -join '').Trim() } catch { }

            $t = ((& $Orca terminal list --json) -join "`n") | ConvertFrom-Json
            $terms = @($t.result.terminals | Where-Object { -not $_.orphaned })

            foreach ($p in $Projects) {
                if ($activeNow -and $p.Path.TrimEnd('/') -eq $activeNow.TrimEnd('/')) { continue }
                $mine = @($terms | Where-Object { $_.worktreePath -eq $p.Path })
                if ($mine.Count -eq 0) { continue }
                Write-Log ("{0}: tab khoi phuc muon - cho ngu" -f $p.Name)
                Invoke-Layout @('-Project', $p.Name, '-SleepAll')
            }
        } catch { }
        $lastOrcaKey = $orcaKey
        Start-Sleep -Milliseconds $PollMs
        continue
    }

    $lastOrcaKey = $orcaKey

    if (-not $AutoOpen) { Start-Sleep -Milliseconds $PollMs; continue }

    # ---- Bam tu may remote ----
    # Dat TRUOC cua chan WAL: bam tu may remote khong lam WAL doi.
    # Lan dau qua het an han (hoac luc watcher moi chay): bo qua log cu.
    # Cung luc do ghi nhan project DANG CHON san tren laptop, coi nhu da xu ly:
    # project dang chon luc Orca mo (con sot tu lan truoc, dang ngu) khong phai
    # nguoi dung vua bam. Thieu buoc nay thi no tu bat len ngay sau an han.
    if (-not $traceArmed) {
        Reset-TraceCursor; $traceArmed = $true
        try { $lastActive = ((& node (Join-Path $PSScriptRoot 'get-active-worktree.js')) -join '').Trim() } catch { }
        $builtForActive = $true
    }
    $pendingView = $null
    foreach ($ev in @(Read-TraceEvents)) {
        $ep = $Projects | Where-Object { $_.Path.TrimEnd('/') -eq $ev.Path } | Select-Object -First 1
        if ($ev.Kind -eq 'close') {
            # May remote dong tab = nguoi dung muon project nay ngu. Dong not cho
            # sach va coi nhu dang xem no, de check-ignore ngay sau do (Orca lam moi
            # git sau khi dong tab) khong bi hieu la "bam mo" roi dung lai.
            $lastViewed = $ev.Path; $pendingView = $null
            if ($ep) {
                Write-Log ("may remote dong tab {0} - cho ngu han" -f $ep.Name)
                try { Invoke-Layout @('-Project', $ep.Name, '-SleepAll') } catch { }
            }
        } elseif ($ev.Path -ne $lastViewed) {
            $lastViewed = $ev.Path; $pendingView = $ev.Path
        }
    }
    # Chi dung cho project xem CUOI CUNG trong dot - bam lien tiep A, B, C thi
    # chi C duoc dung, khong mo ca ba.
    if ($pendingView) {
        $vp = $Projects | Where-Object { $_.Path.TrimEnd('/') -eq $pendingView } | Select-Object -First 1
        if ($vp) {
            # Goi thang orca-layout, KHONG 'terminal list' truoc de xem co can
            # dung khong: orca-layout tu list va tu bo qua project da lanh. List
            # o day la ~265 ms thua dung luc nguoi dung dang cho.
            # Khac bam tren laptop: remote client khong tu mo terminal nao, nen
            # 0 terminal cung phai dung.
            try {
                # Bam tren laptop cung sinh check-ignore -> chay ca o day, orca-layout
                # se bao 'bo qua' neu nhanh duoi da dung roi. Vo hai.
                Write-Log ("dang xem {0} (laptop hoac may remote) - kiem tra layout" -f $vp.Name)
                Invoke-Layout @('-Project', $vp.Name)
            } catch {
                Write-Log ("LOI luc dung cho may remote: " + $_.Exception.Message)
            }
        }
    }

    # ---- Cua chan re nhat: kho trang thai co vua doi khong ----
    # Goi node moi giay ton ~6% CPU. Xem moc sua cua WAL truoc (~1 ms); khong doi
    # thi chac chan activeWorktreeId cung khong doi, khoi chay node.
    $wal = Join-Path $env:APPDATA 'orca\profiles\local-default\profile-state.db-wal'
    $stamp = $null
    try { $stamp = (Get-Item -LiteralPath $wal -ErrorAction Stop).LastWriteTimeUtc.Ticks } catch { }

    if ($stamp -and $stamp -eq $lastStamp) { Start-Sleep -Milliseconds $PollMs; continue }
    $lastStamp = $stamp

    # ---- Quet: project dang mo tren UI (~74 ms) ----
    $active = ''
    try { $active = ((& node (Join-Path $PSScriptRoot 'get-active-worktree.js')) -join '').Trim() } catch { }

    if (-not $active) { Start-Sleep -Milliseconds $PollMs; continue }

    $activeProject = $Projects | Where-Object { $_.Path.TrimEnd('/') -eq $active.TrimEnd('/') } | Select-Object -First 1
    if (-not $activeProject) { $lastActive = $active; Start-Sleep -Milliseconds $PollMs; continue }

    # Da xu ly project nay roi va no van dang mo -> khong kiem tra lai
    if ($active -eq $lastActive -and $builtForActive) { Start-Sleep -Milliseconds $PollMs; continue }
    if ($active -ne $lastActive) { $builtForActive = $false }
    $lastActive = $active

    # ---- Project dang mo la project duoc quan ly: xem co can dung khong ----
    # Den day moi goi 'terminal list' (~249 ms), va chi mot lan cho moi lan nguoi
    # dung chuyen sang project khac.
    try {
        $t = ((& $Orca terminal list --json) -join "`n") | ConvertFrom-Json
        $mine = @($t.result.terminals | Where-Object { -not $_.orphaned -and $_.worktreePath -eq $activeProject.Path })

        # 0 terminal cung phai dung. Truoc day cho Orca tu mo mot shell roi moi
        # dung, nhung Orca khong phai luc nao cung mo: 15/10/2026 bam EV_CS (tab da
        # bi dong) -> Orca khong mo gi, watcher cho mai, project khong bao gio len.
        # Khong so dung nham luc nguoi dung vua cho ngu project dang xem: luc do
        # activeWorktreeId khong doi nen khong di toi day.
        if (@($mine | ForEach-Object { [string]$_.title }) -contains 'builder') {
            # Da co layout roi - khong dung lai
            $builtForActive = $true
        } else {
            Write-Log ("nguoi dung mo {0} - dung layout" -f $activeProject.Name)
            Invoke-Layout @('-Project', $activeProject.Name)
            $builtForActive = $true
        }
    } catch {
        Write-Log ("LOI luc theo doi: " + $_.Exception.Message)
    }

    Start-Sleep -Milliseconds $PollMs
}
