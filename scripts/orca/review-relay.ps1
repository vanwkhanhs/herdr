<#
.SYNOPSIS
    Stop hook cua Claude Code: builder xong -> gui reviewer review; reviewer xong
    -> bao ket qua lai cho builder.

.DESCRIPTION
    Goi tu hooks.Stop trong ~/.claude/settings.json cho MOI phien Claude, nen phai
    thoat ngay neu khong phai pane builder/reviewer cua Orca:
      - khong co ORCA_PANE_KEY            -> Herdr hoac terminal thuong
      - ten pane khong phai builder/reviewer -> herdr-backup, pane le...

    Vai tro lay tu TEN PANE (do pane.ps1 dat), tra bang ORCA_PANE_KEY = tabId:leafId.
    Pane doi dien la pane cung tab mang ten con lai.

    Chong lap vo han:
      - Builder chi gui khi code DOI so voi lan gui truoc (dau van tay = HEAD +
        git status + git diff). Builder chi tra loi cau hoi, khong sua gi -> im.
      - Reviewer chi gui khi tin nhan cuoi co dong 'KET LUAN: OK|CON LOI'.
      - Toi da $MaxRounds vong tu dong lien tiep. Nguoi dung tu go vao builder
        thi dem lai tu dau.

    Noi dung dai (tom tat cua builder, ban review) ghi ra file trong .git/orca-review/
    cua project - nam trong project nen Claude doc khong phai xin quyen, nam trong
    .git nen khong lam ban git status. Tin nhan gui sang pane chi la MOT DONG tro
    toi file: xuong dong trong 'terminal send' se gui tin nhan giua chung.

    Tat tam thoi: dat bien moi truong ORCA_REVIEW_RELAY=0 truoc khi mo Orca, hoac
    tao file .git/orca-review/off trong project.
#>

$ErrorActionPreference = 'Stop'
$MaxRounds = 3
$Marker    = '[auto-review]'

if ($env:ORCA_REVIEW_RELAY -eq '0') { exit 0 }
if (-not $env:ORCA_PANE_KEY) { exit 0 }

$LogFile = Join-Path $env:LOCALAPPDATA 'orca-review-relay.log'
function Write-Log([string]$m) {
    try { Add-Content -LiteralPath $LogFile -Value ('{0}  {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $m) -Encoding utf8 } catch { }
}

try {
    # ---- Dau vao cua hook (JSON, UTF-8) ----
    [Console]::InputEncoding = [Text.Encoding]::UTF8
    $hook = [Console]::In.ReadToEnd() | ConvertFrom-Json

    # ---- Minh la pane nao, pane doi dien la pane nao ----
    $Orca = (Get-Command orca -ErrorAction SilentlyContinue).Source
    if (-not $Orca) { $Orca = Join-Path $env:LOCALAPPDATA 'Programs\orca\resources\bin\orca.exe' }
    $terms = @((((& $Orca terminal list --json) -join "`n") | ConvertFrom-Json).result.terminals | Where-Object { -not $_.orphaned })

    $me = $terms | Where-Object { "$($_.tabId):$($_.leafId)" -eq $env:ORCA_PANE_KEY } | Select-Object -First 1
    if (-not $me) { exit 0 }
    $role = [string]$me.title
    if ($role -notin @('builder', 'reviewer')) { exit 0 }

    $otherRole = if ($role -eq 'builder') { 'reviewer' } else { 'builder' }
    $other = $terms | Where-Object { $_.tabId -eq $me.tabId -and [string]$_.title -eq $otherRole } | Select-Object -First 1
    if (-not $other) { exit 0 }   # project chi co builder (vd herdr-backup)

    # ---- Project va thu muc trang thai ----
    $root = $me.worktreePath
    $gitDir = (& git -C $root rev-parse --absolute-git-dir 2>$null)
    if (-not $gitDir) { exit 0 }
    $stateDir = Join-Path $gitDir 'orca-review'
    if (-not (Test-Path -LiteralPath $stateDir)) { New-Item -ItemType Directory -Path $stateDir | Out-Null }
    if (Test-Path -LiteralPath (Join-Path $stateDir 'off')) { exit 0 }

    $stateFile = Join-Path $stateDir 'state.json'
    $state = $null
    if (Test-Path -LiteralPath $stateFile) { try { $state = Get-Content -LiteralPath $stateFile -Raw -Encoding utf8 | ConvertFrom-Json } catch { } }
    if (-not $state) { $state = [pscustomobject]@{ fingerprint = ''; head = ''; rounds = 0 } }

    # ---- Doc luot vua xong: cau lenh nguoi dung + tin nhan cuoi cua Claude ----
    $lastText = [string]$hook.last_assistant_message
    $lastPrompt = ''
    if ($hook.transcript_path -and (Test-Path -LiteralPath $hook.transcript_path)) {
        $lines = @(Get-Content -LiteralPath $hook.transcript_path -Tail 600 -Encoding utf8)
        for ($i = $lines.Count - 1; $i -ge 0; $i--) {
            try { $e = $lines[$i] | ConvertFrom-Json } catch { continue }
            $c = $e.message.content
            if (-not $lastText -and $e.type -eq 'assistant' -and $c -is [array]) {
                $t = @($c | Where-Object { $_.type -eq 'text' } | ForEach-Object { $_.text }) -join "`n"
                if ($t.Trim()) { $lastText = $t }
            }
            if ($e.type -eq 'user' -and -not $e.isMeta) {
                if ($c -is [string]) { $lastPrompt = $c; break }
                if ($c -is [array] -and -not ($c | Where-Object { $_.type -eq 'tool_result' })) {
                    $lastPrompt = @($c | Where-Object { $_.type -eq 'text' } | ForEach-Object { $_.text }) -join "`n"
                    break
                }
            }
        }
    }
    $autoTurn = $lastPrompt.TrimStart().StartsWith($Marker)

    # ORCA_REVIEW_RELAY_DRYRUN=1: in ra thay vi gui, khong ghi trang thai - de thu
    $dry = $env:ORCA_REVIEW_RELAY_DRYRUN -eq '1'
    function Save-State { if (-not $dry) { $state | ConvertTo-Json | Set-Content -LiteralPath $stateFile -Encoding utf8 } }
    function Send-To($text) {
        if ($dry) { Write-Host ("[thu] {0} -> {1}: {2}" -f $role, $otherRole, $text); return }
        $r = & $Orca terminal send --terminal $other.handle --text $text --enter --json
        Write-Log ("{0} -> {1}  [{2}]  {3}" -f $role, $otherRole, (Split-Path $root -Leaf), $text.Substring(0, [Math]::Min(90, $text.Length)))
    }
    function Write-Utf8($path, $text) { if ($dry) { return }; [IO.File]::WriteAllText($path, $text, (New-Object Text.UTF8Encoding($false))) }

    if ($role -eq 'builder') {
        # ---- Builder xong: co sua code khong? ----
        $head   = (& git -C $root rev-parse HEAD 2>$null)
        $status = (& git -C $root status --porcelain 2>$null) -join "`n"
        $diff   = (& git -C $root diff HEAD 2>$null) -join "`n"
        $sha    = [Security.Cryptography.SHA256]::Create()
        $fp     = [BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes("$head`n$status`n$diff"))).Replace('-', '')

        if ($fp -eq $state.fingerprint) { exit 0 }                       # khong doi gi tu lan gui truoc
        if (-not $status -and (-not $state.head -or $head -eq $state.head)) {
            # cay sach, khong commit moi -> khong co gi de review
            $state.fingerprint = $fp; $state.head = $head; Save-State; exit 0
        }

        $rounds = if ($autoTurn) { [int]$state.rounds + 1 } else { 1 }
        if ($rounds -gt $MaxRounds) {
            Write-Log ("builder [{0}] da {1} vong tu dong - dung, cho nguoi dung" -f (Split-Path $root -Leaf), $MaxRounds)
            $state.fingerprint = $fp; Save-State; exit 0
        }

        $summary = Join-Path $stateDir 'builder-last.md'
        Write-Utf8 $summary $lastText

        $since = if ($state.head -and $state.head -ne $head) { " va cac commit moi tu $($state.head.Substring(0,8)) den HEAD" } else { '' }
        $rel   = '.git/orca-review/builder-last.md'
        Send-To ("$Marker Vong $rounds/$MaxRounds. Builder vua sua code. Tom tat cua builder o file $rel. " +
                 "Hay review cac thay doi chua commit (git status, git diff HEAD)$since theo chi dan reviewer: chi neu loi that, kem file:dong va kich ban hong. " +
                 "Khong sua code. Dong CUOI CUNG cua tra loi ghi dung mot trong hai: KET LUAN: OK  hoac  KET LUAN: CON LOI")

        $state.fingerprint = $fp; $state.head = $head; $state.rounds = $rounds; Save-State
    }
    else {
        # ---- Reviewer xong: chi chuyen khi day la mot ban review co ket luan ----
        if ($lastText -notmatch 'KET LUAN:\s*(OK|CON LOI)') { exit 0 }
        $verdict = $Matches[1]

        $review = Join-Path $stateDir 'review-last.md'
        Write-Utf8 $review $lastText
        $rel = '.git/orca-review/review-last.md'

        if ($verdict -eq 'OK') {
            Send-To ("$Marker Reviewer ket luan OK - khong con loi. Chi tiet o file $rel. Khong can sua gi, chi xac nhan mot dong.")
        } else {
            Send-To ("$Marker Reviewer bao CON LOI (vong $($state.rounds)/$MaxRounds). Chi tiet o file $rel. " +
                     "Doc va sua cac loi ban dong y; loi nao khong dong y thi neu ly do. Sua xong khong can goi reviewer - he thong tu gui lai.")
        }
    }
}
catch {
    Write-Log ("LOI: " + $_.Exception.Message)
}
exit 0
