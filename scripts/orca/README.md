# Tu dung layout Orca

Orca khong tu khoi phuc agent sau khi tat may. Herdr thi co
(`resume_agents_on_restore = true`): no luu session-id rieng cho tung pane va
spawn lai Claude dung phien do. Bo script nay bu phan con thieu cho Orca -
**bang cach muon chinh session-id ma Herdr dang giu**.

## Layout duoc dung

Moi project = **mot tab mang ten project**, chia 3 pane:

| Pane | Phien Claude | Vai tro |
|---|---|---|
| `builder` | resume session-id cua pane `builder` ben Herdr | viet/sua code |
| `reviewer` | resume session-id cua pane `reviewer` ben Herdr | review, tach biet voi builder |
| `debug` | khong co | PowerShell thuan |

Herdr khong chay thi lui ve: builder `claude --continue`, reviewer phien moi.

## File

| File | Viec |
|---|---|
| `orca-layout.ps1` | Dung layout. Doc session-id tu `herdr pane list`. |
| `pane.ps1` | Launcher cho tung pane. Dat ten pane, chon resume hay tao moi. |
| `orca-layout-watcher.ps1` | Theo doi Orca, moi lan Orca mo len dung layout mot lan. |
| `install-watcher.ps1` | Dang ky watcher thanh Scheduled Task chay khi dang nhap. |

## Dung

```powershell
.\install-watcher.ps1              # bat tu dong (chay 1 lan la xong)
.\install-watcher.ps1 -Uninstall   # tat

.\orca-layout.ps1                  # dung tay ngay bay gio
.\orca-layout.ps1 -Project KZ_E02  # chi mot project
.\orca-layout.ps1 -DryRun          # xem se lam gi, khong goi Orca
```

Log watcher: `%LOCALAPPDATA%\orca-layout-watcher.log`

## Them project

Them mot dong vao mang `$Projects` dau file `orca-layout.ps1`:

```powershell
@{ Name = 'ten-hien-thi'; Path = 'E:/duong/dan/project' }
```

`Path` phai trung chinh xac `worktreePath` ma Orca bao cao
(`orca terminal list --json`), dung dau `/`. Muon co lich su thi project do
phai co space tuong ung ben Herdr voi pane dat ten `builder` / `reviewer`.

## Nam cho da sai that

1. **Lenh khoi dong dai bi Orca cat cut.** Khi khoi dong lai, Orca **go lai**
   lenh khoi dong vao shell chu khong chay sach. Chuoi dai bi cat giua chung -
   da gap: `$env:CLAUDE_CODE_DISABLE_TERMINAL_TITL` cut o day, keo theo mat ten
   pane va chay nham lenh. Vi vay moi logic nam trong `pane.ps1`, lenh Orca luu
   chi la mot loi goi ngan.

2. **Dung ghim `claude --resume <id>` cung vao lenh khoi dong.** Session-id doi
   theo thoi gian; lan sau Orca go lai se bao `No conversation found with session
   ID: ...`. Phai lay id moi tu Herdr o thoi diem dung layout.

3. **Ten tab va ten pane la hai thu khac nhau.** `orca terminal rename` doi ten
   **ca tab** - mot tab chi co mot ten du chua 3 pane. Ten tung pane phai do
   chinh tien trinh dat: `$host.UI.RawUI.WindowTitle` kem
   `CLAUDE_CODE_DISABLE_TERMINAL_TITLE=1` de Claude khong ghi de bang chu de
   hoi thoai.

4. **PowerShell 5.1 lam hong nhay kep** khi truyen chuoi sang file exe. Chuoi
   gui cho `orca.exe` chi dung nhay don.

5. **`claude --session-id <uuid>` khong dung lai duoc id cu** - lan hai bao
   `Session ID ... is already in use.`. Muon noi tiep phai la `--resume`.

## An toan

Chi bo qua khi layout **thuc su lanh**: du ba pane dung ten builder/reviewer/debug
VA co agent chay. Thieu mot trong hai la dung lai.

Hai dieu kien chu khong mot, vi ca hai deu da tung sai:

- Chi xet **so pane** -> sau khi bat may lai, Orca khoi phuc du tab nhung do la
  shell trong, script bo qua, khong project nao co Claude.
- Chi xet **co agent** -> Orca van bao agentIdentity=claude cho pane khoi phuc
  hong (lenh bi cat cut, ten pane ve `* Claude Code`), script bo qua va de
  nguyen trang thai hong.

Ten pane la bang chung tin cay vi chi `pane.ps1` moi dat duoc dung ba ten do.

Che do quyen (`auto mode` / `bypass permissions`) di theo phien duoc resume,
khong phai theo `settings.json`.

## Luot don pane khoi phuc muon

Orca khoi phuc mot so tab **cham hon** luc watcher dung layout, nen chung hien ra
sau va thanh pane thua - da gap 2 lan chi trong mot lan reset.

Watcher vi vay chay hai luot moi lan Orca mo:

1. Dung layout (ngay khi runtime ready + 12 giay).
2. Doi 60 giay roi chay lai voi `-Prune`: project nao da lanh thi dong moi pane
   khong mang dung mot trong ba ten `builder` / `reviewer` / `debug`.

Chay tay cung duoc: `.\orca-layout.ps1 -Prune`. Khong co `-Prune` thi khong bao
gio dong pane thua - de khi can mo them terminal trong project ma khong bi don.

## Project khong can du ba pane

Mac dinh moi project duoc dung `builder` + `reviewer` + `debug`. Project nao chi
can mot phan thi khai bao `Roles`:

```powershell
@{ Name = 'herdr-backup'; Path = 'E:/Kztek_Firmwave/herdr-backup'; Roles = @('builder', 'debug') }
```

Pane dau tien tao tab moi, cac pane sau tach ra: pane thu hai tach doc (sang
phai), tu pane thu ba tach ngang (xuong duoi).

Kiem tra lanh/hong va luot `-Prune` deu bam theo `Roles` cua chinh project do,
nen project hai pane khong bi coi la thieu pane.

## Vi sao phai dong bang --worktree --all

`orca-layout.ps1` dong terminal bang `terminal close --worktree <path> --all`,
**khong** dong tung pane bang `--terminal`.

Dong tung pane de lai mot "resume record" cho moi pane co agent, nen moi lan dung
lai layout Orca cong them mot cap va duoi project hien **4 agent** trong khi chi
co 2 dang chay. Tai lieu cua `--all` ghi ro: *"durably removes its terminal tabs,
layouts, and resume records"*.

Da do: KzFlashTool 4 -> 2 ngay sau khi dong kieu nay, dung lai van giu 2. Ap cho
ca 5 project thi tat ca ve dung 2.

## Don ban ghi "sleeping agent session" thua

Moi lan dung lai layout, Orca ghi them mot cap ban ghi resume theo pane-key moi
va giu lai cap cu. Duoi moi project se hien **4 agent** trong khi chi co 2 dang
chay - hai cai kia tro ve **dung hai hoi thoai do**, chi la ban ghi resume thua.
Con so dung yen o 4, khong phinh them.

Muon ve dung 2:

```powershell
# tat han Orca truoc
.\clean-sleeping-sessions.ps1
# mo lai Orca
```

Script tu kiem tra Orca da tat chua, tu sao luu CSDL, va chi dong den worktree
cua cac project liet ke trong `orca-layout.ps1` (doc truc tiep tu file do).
Worktree khac - vi du `herdr-backup` - giu nguyen de van tu resume duoc.

`content_hash` trong bang la **sha256 hex cua payload**, script tinh lai sau khi
sua va tang `revision` len 1, nen Orca khong coi ban ghi la hong.

Tu khi `orca-layout.ps1` dong bang `--worktree --all`, van de nay **da duoc sua
tan goc** - khong con sinh ban ghi thua nua. Script duoi day chi con dung de don
tan du cu, hoac khi can kiem tra.

## Chi dan rieng cho pane reviewer

Pane `reviewer` duoc khoi dong kem `--append-system-prompt-file reviewer-prompt.md`,
nen no biet vai tro cua minh ngay tu dau: review doc lap, mac dinh chi doc va nhan
xet, va dung dung cong cu - agent `fw-reviewer` cho mot luot review day du, skill
`arm-cortex-expert` va `embedded-systems` khi can chieu sau ve chip.

Sua noi dung: `reviewer-prompt.md`. Khong can dung lai script.

Hai ly do khong lam cach khac:

- **Khong dat vao `CLAUDE.md` cua project**: builder dung chung thu muc nen se bi
  coi la reviewer luon.
- **Dung dang `-file`, khong dung `--append-system-prompt "<text>"`**: noi dung nam
  trong file nen lenh khoi dong van ngan. Orca go lai lenh do moi khi khoi dong lai
  va chuoi dai bi cat cut.

Builder khong nhan chi dan nay.
