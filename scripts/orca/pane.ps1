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

    [string]$SessionId
)

$env:CLAUDE_CODE_DISABLE_TERMINAL_TITLE = '1'
$host.UI.RawUI.WindowTitle = $Role

if ($Role -eq 'debug') { return }

if ($SessionId) {
    claude --resume $SessionId
    if ($LASTEXITCODE -eq 0) { return }
    Write-Host "Khong resume duoc phien $SessionId - mo phien khac." -ForegroundColor Yellow
}

if ($Role -eq 'builder') { claude --continue } else { claude }
