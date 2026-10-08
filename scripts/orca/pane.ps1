<#
.SYNOPSIS
    Khoi dong mot pane Orca dung vai tro: builder / reviewer / debug.

.DESCRIPTION
    Ton tai de lenh khoi dong ma Orca luu lai that NGAN. Orca go lai lenh nay vao
    shell moi khi khoi dong lai; chuoi cang dai cang de bi cat giua chung - da gap
    that: '$env:CLAUDE_CODE_DISABLE_TERMINAL_TITL' bi cut, keo theo mat ten pane
    va chay nham lenh. Moi logic do day nam trong file, khong nam trong chuoi.

    Ten pane: Orca hien thi title song cua tien trinh, nen phai tu dat WindowTitle
    va cam Claude ghi de bang CLAUDE_CODE_DISABLE_TERMINAL_TITLE=1.

.PARAMETER Role
    builder | reviewer | debug

.PARAMETER SessionId
    Session-id lay tu Herdr (herdr pane list). Thu resume dung phien do truoc;
    that bai thi lui ve --continue (builder) hoac phien moi (reviewer).

.EXAMPLE
    .\pane.ps1 -Role builder -SessionId 6bd5ee92-d1ba-47d7-886d-21c14c355cd1
    .\pane.ps1 -Role debug
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('builder', 'reviewer', 'debug')]
    [string]$Role,

    [string]$SessionId,

    [ValidateSet('acceptEdits', 'auto', 'bypassPermissions', 'manual', 'dontAsk', 'plan')]
    [string]$PermissionMode
)

$env:CLAUDE_CODE_DISABLE_TERMINAL_TITLE = '1'
$host.UI.RawUI.WindowTitle = $Role

if ($Role -eq 'debug') { return }

# ---- Che do quyen mac dinh cho tung vai tro ----
# DOI O DAY neu muon pane khoi dong o che do khac. Gia tri hop le:
# acceptEdits | auto | bypassPermissions | manual | dontAsk | plan
#
# Phai ep tuong minh: che do quyen di theo phien duoc resume chu khong theo
# settings.json, nen phien cu tao o bypass se keo bypass sang day.
$DefaultMode = @{
    builder  = 'auto'
    reviewer = 'auto'
}

if (-not $PermissionMode) {
    $PermissionMode = $DefaultMode[$Role]
    if (-not $PermissionMode) { $PermissionMode = 'auto' }
}
$claudeArgs = @('--permission-mode', $PermissionMode)

# ---- Chi dan rieng cho vai tro reviewer ----
# Dung --append-system-prompt-file chu khong phai --append-system-prompt: noi dung
# nam trong file nen lenh van ngan (Orca go lai lenh khoi dong khi khoi dong lai,
# chuoi dai bi cat cut), va sua noi dung chi o mot cho.
#
# Khong dat chi dan nay vao CLAUDE.md cua project vi builder dung chung thu muc -
# lam vay thi builder cung bi coi la reviewer.
if ($Role -eq 'reviewer') {
    $promptFile = Join-Path $PSScriptRoot 'reviewer-prompt.md'
    if (Test-Path -LiteralPath $promptFile) {
        $claudeArgs += @('--append-system-prompt-file', $promptFile)
    } else {
        Write-Host "Khong thay reviewer-prompt.md - bo qua chi dan vai tro." -ForegroundColor Yellow
    }
}

if ($SessionId) {
    claude @claudeArgs --resume $SessionId
    if ($LASTEXITCODE -eq 0) { return }
    Write-Host "Khong resume duoc phien $SessionId - mo phien khac." -ForegroundColor Yellow
}

if ($Role -eq 'builder') { claude @claudeArgs --continue } else { claude @claudeArgs }
