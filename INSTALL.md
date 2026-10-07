# Cài Herdr từ đầu (Windows) và khôi phục cấu hình KZTEK

Phiên bản đang dùng: **herdr 0.9.3** (`x86_64-pc-windows-msvc`).

---

## 1. Cài Herdr

Herdr cài vào thư mục người dùng, không cần quyền admin:

```
%USERPROFILE%\.herdr\packages\standalone\releases\<version>-x86_64-pc-windows-msvc\herdr.exe
```

Cài qua trang chủ https://herdr.dev (chọn bản Windows), hoặc nếu đã có `herdr.exe`
thì chỉ cần đặt đúng cây thư mục trên.

### Thêm vào PATH (user, không phải system)

```powershell
$dir = "$env:USERPROFILE\.herdr\packages\standalone\current"
$old = [Environment]::GetEnvironmentVariable('Path','User')
if ($old -notlike "*$dir*") {
    [Environment]::SetEnvironmentVariable('Path', "$old;$dir", 'User')
}
```

> Trên máy hiện tại PATH đang trỏ thẳng vào thư mục release
> (`...\releases\0.9.3-x86_64-pc-windows-msvc`). Trỏ vào symlink `current` tốt hơn
> vì `herdr update` tự đổi đích, không phải sửa PATH mỗi lần nâng cấp.

Mở terminal mới rồi kiểm tra:

```powershell
herdr --version      # herdr 0.9.3
herdr status
```

### Nâng cấp về sau

```powershell
herdr update                  # tải và cài bản mới nhất
herdr channel set stable      # hoặc preview
```

---

## 2. Cài tích hợp Claude Code

Herdr nhận diện agent trong pane qua hook. Cài tích hợp cho Claude:

```powershell
herdr integration install claude
herdr integration status
```

Lệnh này sinh ra:

- `%USERPROFILE%\.claude\hooks\herdr-agent-state.ps1`
- Mục `hooks.SessionStart` trong `%USERPROFILE%\.claude\settings.json`

Cả hai đều có bản backup trong repo (`claude/`). File hook **do Herdr quản lý** —
cài lại hoặc nâng cấp tích hợp sẽ ghi đè nó. Muốn thêm hook riêng thì tạo file khác
cạnh nó, đừng sửa trực tiếp.

Gỡ: `herdr integration uninstall claude`.

---

## 3. Khôi phục cấu hình từ repo này

```powershell
git clone git@github.com:vanwkhanhs/herdr.git
cd herdr
.\scripts\restore.ps1
```

Script hỏi xác nhận trước khi ghi và tự tạo `.bak-<timestamp>` cho mọi file bị thay.
Mặc định nó **bỏ qua** `session.json` (trạng thái runtime). Muốn khôi phục cả bố cục
7 space thì tắt server trước rồi chạy:

```powershell
herdr server stop            # giết toàn bộ pane đang chạy — chỉ dùng khi cố ý
.\scriptsestore.ps1 -IncludeSession
```

Thứ tự thủ công nếu không dùng script:

```powershell
# Tắt server trước khi chạm session.json
herdr server stop

Copy-Item config\config.toml            "$env:APPDATA\herdr\config.toml"            -Force
Copy-Item config\session.json           "$env:APPDATA\herdr\session.json"           -Force
Copy-Item claude\settings.json          "$env:USERPROFILE\.claude\settings.json"    -Force
Copy-Item claude\hooks\*                "$env:USERPROFILE\.claude\hooks\"           -Force
Copy-Item claude\skills\herdr\SKILL.md  "$env:USERPROFILE\.claude\skills\herdr\SKILL.md" -Force
Copy-Item claude\statusline-usage.py    "$env:USERPROFILE\.claude\statusline-usage.py"   -Force
```

Đổi config khi server **đang chạy** thì nạp lại không cần restart:

```powershell
herdr server reload-config
```

---

## 4. Nội dung cấu hình đang dùng

`%APPDATA%\herdr\config.toml`:

```toml
onboarding = false

[theme]
name = "dracula"
auto_switch = false

[session]
# Khoi phuc pane agent AI vao dung phien hoi thoai cu sau khi herdr server khoi dong lai
resume_agents_on_restore = true
startup_per_agent_delay_ms = 100
```

Ý nghĩa hai khoá `[session]`:

- `resume_agents_on_restore = true` — sau khi tắt máy / restart server, gõ `herdr`
  là mọi space hiện lại và từng pane Claude **tự mở lại đúng phiên cũ kèm lịch sử**,
  không cần `claude --continue`.
- `startup_per_agent_delay_ms = 100` — giãn 100 ms giữa các agent khi khởi động lại,
  tránh 12 tiến trình Claude bật cùng lúc.

Mọi khoá cấu hình khả dụng xem `config/config.default.toml` (sinh bằng
`herdr --default-config`).

---

## 5. Dựng lại bố cục 7 space

Có hai cách:

**a) Khôi phục nguyên trạng** — copy `config/session.json` khi server đang tắt, rồi
gõ `herdr`. Cách này giữ nguyên tên space, tên pane, tỉ lệ chia pane. Chỉ đúng khi
máy mới có cùng đường dẫn dự án `E:\Kztek_Firmwave\...`.

**b) Dựng lại bằng CLI** — nếu đường dẫn khác, xem bảng space và quy ước pane trong
[docs/layout.md](docs/layout.md) rồi tạo lại:

```powershell
herdr workspace create --name "KZ_E02.NET" --cwd "E:\Kztek_Firmwave\Access_Control\KZ_E02.NET"
herdr pane split --pane <root-pane-id> --direction right --label reviewer
herdr pane split --pane <root-pane-id> --direction down  --label debug
```

Lấy ID từ JSON trả về (`.result.workspace`, `.result.root_pane`, `.result.pane`),
đừng suy ra từ thứ tự hiển thị trên sidebar.

---

## 6. Kiểm tra sau khi cài

```powershell
herdr --version
herdr integration status
herdr workspace list     # phải thấy 7 space
herdr pane list
herdr agent list         # agent nào idle / working / blocked
```

Trong pane do Herdr quản lý, biến môi trường phải có:

```powershell
$env:HERDR_ENV           # 1
$env:HERDR_PANE_ID       # vd w4:p1
$env:HERDR_WORKSPACE_ID  # vd w4
```

Nếu `HERDR_ENV` rỗng thì pane đó không chạy dưới Herdr, hook sẽ thoát sớm và Herdr
không nhận diện được agent.

---

## 7. Bẫy thường gặp

- **Không bao giờ** chạy `herdr server stop` khi đang làm việc — lệnh đó giết toàn bộ
  pane đang chạy. Chỉ dùng khi cố ý khôi phục `session.json`.
- Khôi phục `session.json` lúc server đang chạy sẽ bị ghi đè khi server thoát.
- Pane `debug` là terminal thuần, đừng khởi động Claude trong đó.
- `claude/settings.json` tham chiếu `statusline-usage.py` bằng đường dẫn tuyệt đối
  `C:/Users/vanwk/...`. Máy user khác phải sửa lại đường dẫn này (cả đường dẫn hook).
