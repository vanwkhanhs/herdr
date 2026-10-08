# Cau hinh dang ap dung

Moi thu trong file nay deu duoc luu trong repo, nen reset may xong chay lai
`scripts\restore.ps1` la ve nhu cu. Doi gi thi sua dung dong duoc chi o day,
roi `scripts\backup.ps1` + commit.

---

## Orca - layout tung project

**File:** `scripts\orca\orca-layout.ps1`, mang `$Projects` dau file.

| Project | Duong dan | Pane |
|---|---|---|
| KZ_E02.NET | `E:/Kztek_Firmwave/Access_Control/KZ_E02.NET` | builder, reviewer, debug |
| kz_e32.net_firmware-dev1 | `E:/Kztek_Firmwave/Elevator/kz_e32.net_firmware-dev1` | builder, reviewer, debug |
| kz_e16.net_firmware-dev1 | `E:/Kztek_Firmwave/Elevator/kz_e16.net_firmware-dev1` | builder, reviewer, debug |
| smart_lock_control_12ch | `E:/Kztek_Firmwave/iLocker/board_12ch/smart_lock_control_12ch` | builder, reviewer, debug |
| KzFlashTool | `E:/Kztek_Firmwave/KzFlashTool` | builder, reviewer, debug |

`herdr-backup` (hien thi la **orca-backup**) **co y khong quan ly** - do la pane
nguoi dung ngoi lam viec, dua vao danh sach thi watcher se dong no moi lan mo Orca.

Them project: them mot dong vao `$Projects`. `Path` phai trung chinh xac
`worktreePath` Orca bao cao (`orca terminal list --json`), dung dau `/`.
Project khong can du ba pane thi them `Roles = @('builder', 'debug')`.

## Orca - che do quyen khi pane khoi dong

**File:** `scripts\orca\pane.ps1`, bang `$DefaultMode`.

```powershell
$DefaultMode = @{
    builder  = 'auto'
    reviewer = 'auto'
}
```

Gia tri hop le: `acceptEdits` `auto` `bypassPermissions` `manual` `dontAsk` `plan`.

Phai ep tuong minh bang `--permission-mode`, vi che do di theo **phien duoc
resume** chu khong theo `settings.json`. Khong ep thi phien cu tao o bypass se
keo bypass sang.

**Doi che do bang tay trong pane (shift+tab) KHONG duoc luu** - lan dung lai se
quay ve gia tri trong bang nay. Muon giu thi sua bang roi backup.

## Orca - ten pane

Orca hien title song cua tien trinh, nen `orca terminal rename` chi doi duoc ten
**tab**. Ten tung pane do `pane.ps1` dat:
`$host.UI.RawUI.WindowTitle` kem `CLAUDE_CODE_DISABLE_TERMINAL_TITLE=1`.

## Orca - watcher tu dung layout

**File:** `scripts\orca\orca-layout-watcher.ps1` (tham so dau file).

| Tham so | Mac dinh | Y nghia |
|---|---|---|
| `PollSeconds` | 5 | nhip kiem tra Orca da chay chua |
| `SettleSeconds` | 12 | cho sau khi runtime ready moi dung layout |
| `PruneAfterSeconds` | 60 | cho roi chay luot `-Prune` don pane khoi phuc muon |

Dang ky chay luc dang nhap: `scripts\orca\install-watcher.ps1`
(Scheduled Task `OrcaLayoutWatcher`, tu goi lai sau 1 phut neu chet).
Log: `%LOCALAPPDATA%\orca-layout-watcher.log`

## Lich su hoi thoai cua pane

Lay session-id tu Herdr (`herdr pane list`, khop theo `cwd` + nhan pane), dem ra
`scripts\orca\herdr-sessions.json` de dung duoc ca khi Herdr chua chay.
File dem bi gitignore - do la trang thai may, khong phai cau hinh.

Herdr khong chay va khong co dem: builder lui ve `claude --continue`,
reviewer mo phien moi.

## Statusline

**File:** `claude\settings.json` (khoa `statusLine`) + `claude\statusline-model.py`

Dang hien: `ten model | ctx <%> <da dung>/<tong>`, mau xanh duoi 60%, vang tu
60%, do tu 85%. Co y **khong** hien han muc 5h/7d va chi phi.

Muon ban day du: doi `statusLine.command` sang `statusline-usage.py` (van giu).

## Herdr

**File:** `config\config.toml`

```toml
[session]
resume_agents_on_restore = true
startup_per_agent_delay_ms = 100
```

Go `herdr` sau khi bat may la 8 space hien lai, tung pane Claude tu mo dung phien
cu. Herdr luu session-id rieng cho tung pane - do la nguon ma Orca muon lai.

## Quyen cua Claude Code

**File:** `claude\settings.json`

```json
"permissions": { "allow": ["Bash(git -C E:/Kztek_Firmwave/herdr-backup push*)"] }
```

Chi mo cho push dung repo nay. Cac repo firmware GitLab van phai nguoi dung tu chay.

## Moi truong

`HOME` bi OrCAD chiem o muc User (`E:\APP\ORCAD\DATA`). Hai thu da va, **dung go**:

- `core.sshCommand = ssh -F C:/Users/vanwk/.ssh/config` (trong `E:\APP\ORCAD\DATA\.gitconfig`)
- Junction `E:\APP\ORCAD\DATA\.ssh` -> `C:\Users\vanwk\.ssh`

Mat mot trong hai la hong push/pull GitLab va ssh vao board.

---

## Luu lai sau khi doi

```powershell
.\scripts\backup.ps1
git add -A; git commit -m "config: <doi gi>"; git push
```

`backup.ps1` hut 8 file tu may vao repo: config Herdr, `settings.json`, hook,
hai statusline, skill herdr, va `E:\Kztek_Firmwave\CLAUDE.md`.
