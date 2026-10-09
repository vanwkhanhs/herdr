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

.PARAMETER PollSeconds
    Nhip kiem tra. Mac dinh 5 giay.

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
    [int]$PollSeconds   = 5,
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

Write-Log ("watcher bat dau (poll=${PollSeconds}s settle=${SettleSeconds}s, {0} project, BuildAll={1})" -f $Projects.Count, [bool]$BuildAll)

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

$graceUntil = $null

while ($true) {

    if (-not (Get-Process -Name orca -ErrorAction SilentlyContinue)) {
        if ($lastRuntimeId) { Write-Log "Orca da tat - cho lan mo sau" }
        $lastRuntimeId = $null
        Start-Sleep -Seconds $PollSeconds
        continue
    }

    $ready = $false
    $runtimeId = $null
    try {
        $s = ((& $Orca status --json) -join "`n") | ConvertFrom-Json
        $ready = ($s.result.runtime.state -eq 'ready') -and ($s.result.app.running -eq $true)
        $runtimeId = $s.result.runtime.runtimeId
    } catch { $ready = $false }

    if (-not $ready) { Start-Sleep -Seconds $PollSeconds; continue }

    # ---- Lan mo Orca moi ----
    if ($runtimeId -ne $lastRuntimeId) {
        $lastRuntimeId = $runtimeId
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

        Start-Sleep -Seconds $PollSeconds
        continue
    }

    # ---- Trong cua so an han: cho ngu tiep, khong dung gi ----
    if ($graceUntil -and (Get-Date) -lt $graceUntil) {
        try {
            $t = ((& $Orca terminal list --json) -join "`n") | ConvertFrom-Json
            $terms = @($t.result.terminals | Where-Object { -not $_.orphaned })
            $paths = @($Projects | ForEach-Object { $_.Path })
            if (@($terms | Where-Object { $paths -contains $_.worktreePath }).Count -gt 0) {
                Write-Log "con tab khoi phuc muon - cho ngu tiep"
                Invoke-Layout @('-SleepAll')
            }
        } catch { }
        Start-Sleep -Seconds $PollSeconds
        continue
    }

    if (-not $AutoOpen) { Start-Sleep -Seconds $PollSeconds; continue }

    # ---- Cung mot lan mo: theo doi nguoi dung bam vao project ----
    # Project nao co terminal nhung chua co pane ten 'builder' nghia la nguoi dung
    # vua bam mo no va Orca chi cho mot PowerShell trong -> dung layout cho no.
    try {
        $t = ((& $Orca terminal list --json) -join "`n") | ConvertFrom-Json
        $terms = @($t.result.terminals | Where-Object { -not $_.orphaned })

        # Project nao co terminal nhung chua co pane 'builder' la ung vien.
        $candidates = @()
        foreach ($p in $Projects) {
            $mine = @($terms | Where-Object { $_.worktreePath -eq $p.Path })
            if ($mine.Count -eq 0) { continue }
            if (@($mine | ForEach-Object { [string]$_.title }) -contains 'builder') { continue }
            $candidates += $p
        }

        # Chi dung cho project NGUOI DUNG DANG MO tren giao dien.
        #
        # Day la cho duy nhat phan biet duoc "nguoi dung bam" voi "Orca tu khoi
        # phuc tab cu": bam o sidebar thi Orca doi activeWorktreeId, con tu khoi
        # phuc thi khong. Nhin vao terminal khong phan biet duoc - da thu bang
        # thoi gian va bang so pane, deu sai, project tu bat len du khong ai bam.
        #
        # Doc kho trang thai chi khi co ung vien, de khong phai cop CSDL moi nhip.
        if ($candidates.Count -gt 0) {
            $active = ''
            try { $active = (& node (Join-Path $PSScriptRoot 'get-active-worktree.js')) -join '' } catch { }

            if (-not $active) {
                Write-Log "khong xac dinh duoc project dang mo - khong dung gi"
            } else {
                foreach ($p in $candidates) {
                    if ($active.TrimEnd('/') -ne $p.Path.TrimEnd('/')) { continue }
                    Write-Log ("nguoi dung mo {0} - dung layout" -f $p.Name)
                    Invoke-Layout @('-Project', $p.Name)
                }
            }
        }
    } catch {
        Write-Log ("LOI luc theo doi: " + $_.Exception.Message)
    }

    Start-Sleep -Seconds $PollSeconds
}
