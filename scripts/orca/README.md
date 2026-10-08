# Tu dung layout Orca

Orca khong tu khoi phuc agent sau khi tat may (khac Herdr, vn co
`resume_agents_on_restore = true`). Orca chi giu scrollback terminal va cho
*resume* phien agent **bang tay** qua AI Vault. Bo script nay bu phan con thieu.

## Layout duoc dung

Moi project = **mot tab mang ten project**, chia 3 pane:

| Pane | Lenh | Vai tro |
|---|---|---|
| `builder` | `claude --continue` | resume phien gan nhat cua thu muc |
| `reviewer` | `claude` | phien moi, tach biet voi builder |
| `debug` | (shell) | PowerShell thuan, chay build/nap/ssh |

## File

| File | Viec |
|---|---|
| `orca-layout.ps1` | Dung layout. Idempotent, chay lai khong tao trung. |
| `orca-layout-watcher.ps1` | Theo doi Orca, moi lan Orca mo len thi dung layout dung mot lan. |
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
(`orca terminal list --json`), dung dau `/`.

## Hai dieu de sai

1. **Ten tab va ten pane la hai thu khac nhau.**
   `orca terminal rename` doi ten **ca tab** - mot tab chi co mot ten, du chua
   3 pane. Ten tung pane phai do chinh tien trinh dat:
   `$host.UI.RawUI.WindowTitle='builder'` kem `CLAUDE_CODE_DISABLE_TERMINAL_TITLE=1`
   de Claude khong ghi de bang chu de hoi thoai.

2. **PowerShell 5.1 lam hong nhay kep khi truyen chuoi sang file exe.**
   Cac bien `$CmdBuilder/$CmdReviewer/$CmdDebug` chi dung nhay don (long nhau
   bang cach nhan doi). Dung nhay kep ben trong se hong lenh.

## An toan

Script bo qua project **dang co agent chay** va canh bao, khong dong viec dang lam.
Chi project con terminal trong moi bi dong de dung lai.
