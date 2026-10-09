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
| RV1126B dual cam 5MP | `E:/project_kztek/SDK_RV1126B` | builder, reviewer, debug |
| SSC37X_CAM | `E:/project_kztek/SSC37X_CAM` | builder, reviewer, debug |

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

## Orca - model cho tung pane

**File:** `scripts\orca\pane.ps1`, tham so `-Model` (mac dinh `opus[1m]`).

Phai ep `--model` y nhu `--permission-mode`: phien duoc resume mang theo model luc
no **duoc tao**, khong theo `model` trong `settings.json`. Da gap: builder cua
SSC37X_CAM chay Opus 4.8 trong khi reviewer cung thu muc chay Opus 5.

## Orca - ten pane

Orca hien title song cua tien trinh, nen `orca terminal rename` chi doi duoc ten
**tab**. Ten tung pane do `pane.ps1` dat:
`$host.UI.RawUI.WindowTitle` kem `CLAUDE_CODE_DISABLE_TERMINAL_TITLE=1`.

## Orca - tu dong terminal mo coi

Khi Orca khoi dong lai, tab tren giao dien mat nhung PTY van song. Orca bao
chung `orphaned=true`, `title=null`, va van gan `agentIdentity=claude` - nguoi
dung thay chung hien ra nhu **agent thua** duoi project.

`orca-layout.ps1` tu dong chung moi lan chay, **chi trong worktree cua cac
project duoc quan ly**. Project khac - nhat la pane dang ngoi lam viec - khong
bi dung toi.

## Orca - watcher tu dung layout

**File:** `scripts\orca\orca-layout-watcher.ps1` (tham so dau file).

| Tham so | Mac dinh | Y nghia |
|---|---|---|
| `PollSeconds` | 5 | nhip kiem tra Orca da chay chua |
| `SettleSeconds` | 12 | cho sau khi runtime ready moi dung layout |
| nhip don | 10,10,15,15,30,30,60,60,120,120 giay | don tai moc 10s..470s sau khi dung layout (10 luot, ~8 phut) |

Watcher nhan dien lan mo moi bang **runtimeId** cua Orca (`orca status --json`),
khong phai bang "co thay Orca tat khong" - no poll 5 giay mot lan nen dong mo
nhanh la khong bao gio thay khoang trong.

Dang ky chay luc dang nhap: `scripts\orca\install-watcher.ps1`
(Scheduled Task `OrcaLayoutWatcher`, tu goi lai sau 1 phut neu chet).
Log: `%LOCALAPPDATA%\orca-layout-watcher.log`

## Danh sach agent duoi project trong Orca

Orca dung danh sach nay tu **thu muc scrollback** trong
`%APPDATA%orca	erminal-history<ptyId ma hoa URL>`. Moi terminal bi dong de lai
mot thu muc va van hien ra nhu agent kem tuoi, nen sau vai lan dung lai layout se
thay 4-6 agent trong khi chi co 2 dang song.

`orca-layout.ps1` tu xoa cac thu muc **khong gan voi terminal nao dang song**,
chi trong worktree duoc quan ly, moi lan chay.

Orca giu danh sach trong bo nho va chi nap lai luc khoi dong, nen sau khi don
phai dong mo lai Orca moi thay.

## Lich su hoi thoai cua pane

Lay session-id tu Herdr (`herdr pane list`, khop theo `cwd` + nhan pane), dem ra
`scripts\orca\herdr-sessions.json` de dung duoc ca khi Herdr chua chay.
File dem bi gitignore - do la trang thai may, khong phai cau hinh.

Herdr khong chay va khong co dem: builder lui ve `claude --continue`,
reviewer mo phien moi.

## Statusline

**File:** `claude\settings.json` (khoa `statusLine`) + `claude\statusline-model.py`

Dang hien: `ten model | <effort> | ctx <%> <da dung>/<tong>`
(effort: low | medium | high | xhigh, lay tu `effort.level`), mau xanh duoi 60%, vang tu
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

## Mo project theo nhu cau (mac dinh tu 09/10/2026)

Mo Orca thi **moi project deu ngu** - khong pane nao chay. Bam vao project o
sidebar thi watcher dung `builder | reviewer | debug` cho dung project do, resume
lich su cu. Khoang **5 giay**, phan lon la do tre cua chinh CLI Orca:
create 844 ms + split 389 + split 246 + rename 447 + switch 513 = 2,44 s, cong
khoi dong PowerShell va doc du lieu.

Ly do: moi pane Claude an ~440 MB, dung du 7 project la ~6,6 GB cho nhung thu
chua dung den.

**File:** `scripts\orca\orca-layout-watcher.ps1`

| Tham so | Mac dinh | Y nghia |
|---|---|---|
| `PollSeconds` | 1 | nhip quet |
| `SettleSeconds` | 12 | cho sau khi Orca ready moi cho ngu |
| `SleepGraceSeconds` | 45 | an han sau khi ngu; bam trong khoang nay se bi dong |
| `AutoOpen` | `$true` | tu dung layout khi bam vao project |
| `BuildAll` | tat | bat de tro lai kieu cu: mo Orca la dung du 7 project |

Cach phan biet "nguoi dung bam" voi "Orca tu khoi phuc tab": doc
`activeWorktreeId` tu kho trang thai (`get-active-worktree.js`). Bam o sidebar thi
no doi, Orca tu khoi phuc thi khong. Nhin vao terminal **khong** phan biet duoc -
da thu bang thoi gian va bang so pane, deu sai.

Vong lap duoc xep theo gia: moc sua WAL (~1 ms) -> `get-active-worktree.js`
(~74 ms) -> `orca terminal list` (~249 ms) -> dung layout (~1,4 s). Cai dat chi
goi khi that su can, nen nhip 1 giay van chi ton ~4% cua mot nhan.
