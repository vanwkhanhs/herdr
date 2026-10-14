<#
.SYNOPSIS
    Cho mot project ngu - dung thay nut Sleep cua Orca khi dang remote.

.DESCRIPTION
    Nut Sleep tren may remote (ket noi qua 'orca environment add') KHONG gui gi
    sang laptop - do that 09/10/2026: bam Sleep tren may moi, laptop khong ghi
    nhan su kien nao, ca 3 pane Claude van chay.

    Lenh nay chay ngay tren laptop (pane debug la terminal cua laptop), nen go tu
    may nao cung duoc. Dong bang orca-layout.ps1 -SleepAll, tuc 'close --worktree
    --all' - khong de lai resume record (xem PITFALLS #4).

    Pane debug cua moi project co san ham 'ngu' (pane.ps1 dat luc khoi dong).

.PARAMETER Path
    Thu muc project. Mac dinh: thu muc pane debug luc khoi dong.

.EXAMPLE
    ngu
    & 'E:\Kztek_Firmwave\herdr-backup\scripts\orca\ngu.ps1' -Path E:/Kztek_Firmwave/KzFlashTool
#>

[CmdletBinding()]
param([string]$Path)

if (-not $Path) { $Path = $global:OrcaProjectDir }
if (-not $Path) { $Path = (Get-Location).Path }
$Path = $Path.Replace('\', '/').TrimEnd('/')

$layout = Join-Path $PSScriptRoot 'orca-layout.ps1'
Write-Host "Cho ngu $Path ..." -ForegroundColor DarkGray

# Lenh nay dong ca chinh pane dang chay no - khong in gi sau dong nay duoc nua.
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $layout -Project $Path -SleepAll
