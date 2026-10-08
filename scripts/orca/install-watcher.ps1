<#
.SYNOPSIS
    Dang ky / go watcher dung layout Orca khoi dong cung phien dang nhap Windows.

.DESCRIPTION
    Tao Scheduled Task 'OrcaLayoutWatcher' chay an khi dang nhap, goi
    orca-layout-watcher.ps1 nam canh file nay. Khong can quyen admin vi task
    chay duoi tai khoan nguoi dung hien tai.

.PARAMETER Uninstall
    Go task thay vi tao.

.EXAMPLE
    .\install-watcher.ps1
    .\install-watcher.ps1 -Uninstall
#>

[CmdletBinding()]
param([switch]$Uninstall)

$ErrorActionPreference = 'Stop'

$TaskName = 'OrcaLayoutWatcher'
$Watcher  = Join-Path $PSScriptRoot 'orca-layout-watcher.ps1'

if ($Uninstall) {
    $existing = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    if ($existing) {
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
        Write-Host "Da go task '$TaskName'." -ForegroundColor Green
    } else {
        Write-Host "Khong co task '$TaskName' de go." -ForegroundColor Yellow
    }
    return
}

if (-not (Test-Path -LiteralPath $Watcher)) { throw "Khong thay watcher: $Watcher" }

$action = New-ScheduledTaskAction -Execute 'powershell.exe' `
    -Argument ('-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "{0}"' -f $Watcher)

$trigger = New-ScheduledTaskTrigger -AtLogOn -User "$env:USERDOMAIN\$env:USERNAME"

# RestartInterval/RestartCount: watcher da tung chet giua chung (LastTaskResult
# 0xC000013A - bi ket thuc cuong buc), va vi no chet nen sau khi bat may lai
# khong co layout nao duoc dung. Co nay bao Windows tu goi lai sau 1 phut.
$settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -ExecutionTimeLimit ([TimeSpan]::Zero) `
    -MultipleInstances IgnoreNew `
    -StartWhenAvailable `
    -RestartInterval (New-TimeSpan -Minutes 1) `
    -RestartCount 999

Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger `
    -Settings $settings -Description 'Dung layout builder/reviewer/debug moi khi Orca duoc mo' -Force | Out-Null

Write-Host "Da dang ky task '$TaskName' (chay khi dang nhap)." -ForegroundColor Green
Write-Host "Log: $env:LOCALAPPDATA\orca-layout-watcher.log"
Write-Host "Go bo: .\install-watcher.ps1 -Uninstall"
