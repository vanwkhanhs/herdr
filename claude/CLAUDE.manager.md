# Bối cảnh: máy này chạy **hai** trình quản lý agent

Phiên Claude ở máy này có thể nằm trong **Herdr** hoặc trong **Orca**. Hai cái độc lập,
chạy song song, có ID và khái niệm riêng. **Luôn xác định mình đang ở đâu trước khi
chạy lệnh điều khiển** — nhầm là thao tác lên phiên của người khác.

## Bước đầu tiên: xác định đang ở đâu

```bash
echo "$ORCA_PANE_KEY"    # có giá trị -> đang trong Orca
echo "$HERDR_PANE_ID"    # có giá trị -> đang trong Herdr
```

| Biến có mặt | Đang ở | Dùng CLI |
|---|---|---|
| `ORCA_PANE_KEY`, `ORCA_WORKTREE_ID`, `ORCA_TAB_ID` | Orca | `orca` |
| `HERDR_ENV=1`, `HERDR_PANE_ID`, `HERDR_WORKSPACE_ID` | Herdr | `herdr` |
| không có cả hai | terminal thường | không điều khiển gì |

**Cạm bẫy đã gặp thật:** cả hai CLI đều cài sẵn trong PATH, nên `herdr ...` vẫn chạy
được từ trong Orca và ngược lại. Tệ hơn, `herdr pane current --current` khi **không có**
`HERDR_PANE_ID` sẽ **rơi về pane đang focus trên UI Herdr** — trả về một pane Claude
hoàn toàn khác mà không báo lỗi. Cùng kiểu đó, lệnh `orca` không truyền `--worktree`
sẽ dùng worktree đang focus trên UI Orca.

Quy tắc: muốn tác động lên "pane hiện tại", phải có biến môi trường tương ứng. Không có
thì truyền ID/đường dẫn tường minh, hoặc hỏi người dùng.

---

# Herdr

## Từ "space" luôn có nghĩa là Herdr workspace

Khi người dùng nói **space**, **spaces**, **không gian**, họ nói về workspace của Herdr —
**không phải** vùng nhớ firmware, dung lượng ổ đĩa, Notion/Slack hay thư mục project.
Đừng hỏi lại cho những từ này; chạy luôn:

```
herdr workspace list     # danh sách space
herdr pane list          # danh sách pane
herdr agent list         # agent nào đang chạy / idle / blocked
```

Kết quả trả về JSON. Dùng skill `herdr` để biết cú pháp đầy đủ.

## Bố cục — 8 space

| Phím | ID | Tên | Thư mục |
|---|---|---|---|
| 1 | wE | Manager | `E:\Kztek_Firmwave` — pane điều phối |
| 2 | w4 | KZ_E02.NET | `E:\Kztek_Firmwave\Access_Control\KZ_E02.NET` |
| 3 | w7 | E32 | `E:\Kztek_Firmwave\Elevator\kz_e32.net_firmware-dev1` |
| 4 | w8 | E16 | `E:\Kztek_Firmwave\Elevator\kz_e16.net_firmware-dev1` |
| 5 | w9 | iLocker 12CH | `E:\Kztek_Firmwave\iLocker\board_12ch\smart_lock_control_12ch` |
| 6 | wA | KzFlashTool | `E:\Kztek_Firmwave\KzFlashTool` |
| 7 | wC | RV1126B dual cam 5MP | `E:\project_kztek\SDK_RV1126B` |
| 8 | wF | SSC37X_CAM | `E:\project_kztek\SSC37X_CAM` |

Số thứ tự đổi khi thêm/bớt space — **lấy ID từ JSON, đừng suy ra từ bảng này.**

Mỗi space dự án có 3 pane theo quy ước:
- `builder` — Claude viết/sửa code
- `reviewer` — Claude review, **phiên riêng** không dùng chung với builder
- `debug` — terminal thuần, không chạy Claude

Space **Manager** chỉ có pane `manager`: nơi điều phối các space khác.

## Quy tắc khi điều khiển Herdr

- **Không bao giờ** chạy `herdr server stop` trừ khi người dùng nói rõ muốn tắt server —
  lệnh đó giết toàn bộ pane đang chạy.
- Lấy ID từ JSON trả về, đừng suy ra từ thứ tự hiển thị trên sidebar.
- Trước khi gửi prompt sang agent khác, kiểm tra nó không ở trạng thái `blocked`
  (đang chờ người dùng trả lời hộp thoại) — nếu blocked thì hỏi người dùng, đừng tự bấm.
- Pane `debug` là terminal: chạy lệnh build/nạp/ssh ở đó, đừng khởi động Claude trong đó.

## Tự khôi phục sau khi tắt máy — **có**

Đã bật `[session] resume_agents_on_restore = true` trong `%APPDATA%\herdr\config.toml`.
Gõ `herdr` sau khi bật máy là mọi space hiện lại và từng pane Claude tự mở đúng phiên cũ
kèm lịch sử — không cần `claude --continue`. Hook báo session-id nằm ở
`~/.claude/hooks/herdr-agent-state.ps1`.

---

# Orca

Ứng dụng Electron, CLI ở `%LOCALAPPDATA%\Programs\orca\resources\bin\orca.exe` (đã có
trong PATH của PowerShell). Khái niệm: **repo → worktree → tab → pane**. Người dùng gọi
là **project**, không gọi là "space".

```
orca repo list --json          # repo đã đăng ký
orca worktree list --json      # worktree
orca terminal list --json      # mọi terminal đang sống, kèm worktreePath + agentIdentity
orca status --json             # runtime sẵn sàng chưa
```

## 5 project có layout chuẩn

Mỗi project = **một tab mang tên project**, chia 3 pane:

| Pane | Lệnh khởi động | Vai trò |
|---|---|---|
| `builder` | `claude --continue` | resume phiên gần nhất của thư mục |
| `reviewer` | `claude` | phiên mới, tách biệt với builder |
| `debug` | (shell) | PowerShell thuần |

`KZ_E02.NET` · `kz_e32.net_firmware-dev1` · `kz_e16.net_firmware-dev1` ·
`smart_lock_control_12ch` · `KzFlashTool`

Các repo còn lại (`herdr-backup`, `KzUdpTool`, `Fix_old_ver_tu_do`) chỉ có 1 terminal trống.

## Cạm bẫy — ĐỌC TRƯỚC KHI SỬA BẤT CỨ THỨ GÌ VỀ ORCA

Đầy đủ 25 mục kèm triệu chứng và cách đo trong
`herdr-backup/docs/PITFALLS.md` (nhánh `orca-backup`). **Bắt buộc đọc trước khi
đụng vào script Orca** — mọi mục trong đó đều đã làm hỏng thật ít nhất một lần.

Bốn cái hay dẫm nhất:

1. **Tên tab ≠ tên pane.** `orca terminal rename --title` đổi tên **cả tab** — một tab chỉ
   có một tên dù chứa 3 pane. Tên từng pane phải do chính tiến trình đặt:
   `$host.UI.RawUI.WindowTitle='builder'` kèm `CLAUDE_CODE_DISABLE_TERMINAL_TITLE=1`.

2. **Đóng terminal phải dùng `--worktree <path> --all`**, không đóng từng pane bằng
   `--terminal`. Đóng từng pane để lại *resume record*, mỗi lần dựng lại layout cộng
   thêm một cặp và dưới project hiện 4 agent trong khi chỉ có 2 đang chạy.

3. **PowerShell 5.1 làm hỏng nháy kép** khi truyền chuỗi sang file exe. Chuỗi lệnh gửi cho
   `orca.exe` chỉ dùng nháy đơn (lồng nhau bằng cách nhân đôi).

4. **Git Bash nuốt tham số bắt đầu bằng `/`.** `orca terminal send --text "/exit"` biến
   thành `C:/Program Files/Git/exit`. Phải thêm `MSYS_NO_PATHCONV=1` trước lệnh.

`orca-data.json` là **bản xuất và đứng yên hàng chục phút** — đừng đọc nó để kết luận.
Kho thật là `profiles\local-default\profile-state.db` (SQLite, dữ liệu nằm trong WAL).

## Tự khôi phục sau khi tắt máy — **không**, đã bù bằng watcher

Orca không tự khôi phục agent. Scheduled Task **`OrcaLayoutWatcher`** chạy lúc đăng nhập
(qua `wscript.exe watcher-hidden.vbs` để không bật cửa sổ console), nhận diện Orca mở
bằng **`runtimeId`**, rồi:

- đóng terminal mồ côi và dựng lại 5 project
- builder + reviewer resume đúng session-id **mượn từ Herdr** (đệm ở `herdr-sessions.json`
  để dùng được cả khi Herdr chưa chạy), cả hai bật `auto mode`
- dọn 10 lượt nhịp thưa dần trong ~8 phút, bắt tab Orca khôi phục muộn

Script: repo `E:\Kztek_Firmwave\herdr-backup`, nhánh **`orca-backup`**, thư mục
`scripts\orca\` — xem `README.md` trong đó. Mọi mục cấu hình chỉnh được liệt kê kèm
đúng file và đúng dòng trong `CONFIG.md`. Log: `%LOCALAPPDATA%\orca-layout-watcher.log`.

Thêm project vào layout: thêm một dòng vào mảng `$Projects` đầu `orca-layout.ps1`,
`Path` phải trùng chính xác `worktreePath` Orca báo cáo, dùng dấu `/`.

---

# Môi trường chung

`HOME` bị OrCAD chiếm ở mức User của Windows (`E:\APP\ORCAD\DATA`). Hệ quả:

- Git global config thật nằm ở `E:\APP\ORCAD\DATA\.gitconfig`, **không phải**
  `C:\Users\vanwk\.gitconfig` (file này bị bỏ qua hoàn toàn).
- SSH đã được vá bằng `core.sshCommand = ssh -F C:/Users/vanwk/.ssh/config` và junction
  `E:\APP\ORCAD\DATA\.ssh` → `C:\Users\vanwk\.ssh`. Đừng gỡ hai thứ này, mất là hỏng
  push/pull GitLab và ssh vào board.
