<#
.SYNOPSIS
    Theo doi Orca; moi lan Orca duoc mo len thi dung lai layout 3 pane mot lan.

.DESCRIPTION
    Orca khong tu khoi dong cung Windows va khong co hook luc mo app, nen cach
    duy nhat de "tu chay luc mo Orca" la mot watcher nhe chay nen:

      - Khong co tien trinh orca  -> reset co, cho tiep (khong lam Orca khoi dong).
      - Orca vua len, runtime ready -> cho vai giay cho worktree nap xong,
        goi orca-layout.ps1 dung mot lan, roi dung co lai den khi Orca tat.

    Tieu thu gan nhu bang khong: moi $PollSeconds chi goi Get-Process mot lan,
    chi khi thay Orca song moi hoi 'orca status'.

.PARAMETER PollSeconds
    Khoang cach giua hai lan kiem tra. Mac dinh 5 giay.

.PARAMETER SettleSeconds
    Cho bao lau sau khi runtime ready moi dung layout. Mac dinh 12 giay.

.EXAMPLE
    .\orca-layout-watcher.ps1
#>

[CmdletBinding()]
param(
    [int]$PollSeconds       = 5,
    [int]$SettleSeconds     = 12,
    [int]$PruneAfterSeconds = 60,
    [int]$PruneAttempts     = 6
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

$Orca = (Get-Command orca -ErrorAction SilentlyContinue).Source
if (-not $Orca) {
    $fallback = Join-Path $env:LOCALAPPDATA 'Programs\orca\resources\bin\orca.exe'
    if (Test-Path -LiteralPath $fallback) { $Orca = $fallback }
}
if (-not $Orca) { throw "Khong tim thay orca CLI." }

Write-Log "watcher bat dau (poll=${PollSeconds}s settle=${SettleSeconds}s)"

$appliedForThisLaunch = $false

while ($true) {

    $proc = Get-Process -Name orca -ErrorAction SilentlyContinue

    if (-not $proc) {
        if ($appliedForThisLaunch) { Write-Log "Orca da tat - cho lan mo sau" }
        $appliedForThisLaunch = $false
        Start-Sleep -Seconds $PollSeconds
        continue
    }

    if ($appliedForThisLaunch) {
        Start-Sleep -Seconds $PollSeconds
        continue
    }

    # Orca dang chay va chua dung layout cho lan mo nay
    $ready = $false
    try {
        $raw = & $Orca status --json
        $s = ($raw -join "`n") | ConvertFrom-Json
        $ready = ($s.result.runtime.state -eq 'ready') -and ($s.result.app.running -eq $true)
    } catch {
        $ready = $false
    }

    if (-not $ready) {
        Start-Sleep -Seconds $PollSeconds
        continue
    }

    Write-Log "Orca ready - cho ${SettleSeconds}s roi dung layout"
    Start-Sleep -Seconds $SettleSeconds

    try {
        # -WindowStyle Hidden: thieu co nay thi luc dang nhap co mot cua so console
        # nhay len, in ca loi JSON cua 'herdr pane list' khi Herdr chua chay.
        $out = & powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File $LayoutScript
        foreach ($l in @($out)) { Write-Log ("  " + $l) }
        Write-Log "dung layout xong"

        # Cac luot don. Orca khoi phuc tab cu CHAM hon luc dung layout, va khong
        # phai mot lan ma THANH NHIEU DOT rai ra vai phut. Mot luot don sau 60
        # giay la khong du - da gap that: luot don 11:24:53 bao sach, nhung den
        # 11:26 KZ_E02 lai co them mot tab cu ba pane.
        #
        # Nen don lap lai trong mot cua so thoi gian. Het cua so thi dung han:
        # sau do terminal moi trong project la do nguoi dung tu mo, khong duoc dong.
        for ($k = 1; $k -le $PruneAttempts; $k++) {
            Write-Log "cho ${PruneAfterSeconds}s roi don (luot $k/$PruneAttempts)"
            Start-Sleep -Seconds $PruneAfterSeconds

            if (-not (Get-Process -Name orca -ErrorAction SilentlyContinue)) {
                Write-Log "Orca da tat - bo cac luot don con lai"
                break
            }

            $out2 = & powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File $LayoutScript -Prune
            foreach ($l in @($out2)) { Write-Log ("  " + $l) }
        }
        Write-Log "don xong"
    } catch {
        Write-Log ("LOI khi dung layout: " + $_.Exception.Message)
    }

    $appliedForThisLaunch = $true
    Start-Sleep -Seconds $PollSeconds
}
