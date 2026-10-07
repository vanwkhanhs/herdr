# Bối cảnh: phiên này chạy bên trong Herdr

Mọi phiên Claude ở máy này chạy trong **Herdr** — trình quản lý terminal cho agent
(`HERDR_ENV=1`, `HERDR_PANE_ID` cho biết pane hiện tại).

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

## Bố cục hiện tại — 7 space

| Phím | ID | Tên | Thư mục |
|---|---|---|---|
| 1 | w4 | KZ_E02.NET | `E:\Kztek_Firmwave\Access_Control\KZ_E02.NET` |
| 2 | w7 | E32 | `E:\Kztek_Firmwave\Elevator\kz_e32.net_firmware-dev1` |
| 3 | w8 | E16 | `E:\Kztek_Firmwave\Elevator\kz_e16.net_firmware-dev1` |
| 4 | w9 | iLocker 12CH | `E:\Kztek_Firmwave\iLocker\board_12ch\smart_lock_control_12ch` |
| 5 | wA | KzFlashTool | `E:\Kztek_Firmwave\KzFlashTool` |
| 6 | wC | RV1126B dual cam 5MP | `E:\project_kztek\SDK_RV1126B` |
| 7 | wE | Manager | `E:\Kztek_Firmwave` — pane điều phối |

Sáu space dự án mỗi cái có 3 pane theo quy ước:
- `builder` — Claude viết/sửa code
- `reviewer` — Claude review, **phiên riêng** không dùng chung với builder
- `debug` — terminal thuần, không chạy Claude

Space **Manager** chỉ có pane `manager`: nơi điều phối các space khác, tạo thêm pane
hoặc space khi cần.

## Quy tắc khi điều khiển Herdr

- **Không bao giờ** chạy `herdr server stop` trừ khi người dùng nói rõ muốn tắt server —
  lệnh đó giết toàn bộ pane đang chạy.
- Lấy ID từ JSON trả về, đừng suy ra từ thứ tự hiển thị trên sidebar.
- Trước khi gửi prompt sang agent khác, kiểm tra nó không ở trạng thái `blocked`
  (đang chờ người dùng trả lời hộp thoại) — nếu blocked thì hỏi người dùng, đừng tự bấm.
- Pane `debug` là terminal: chạy lệnh build/nạp/ssh ở đó, đừng khởi động Claude trong đó.

## Tự khôi phục sau khi tắt máy

Đã bật `[session] resume_agents_on_restore = true` trong `%APPDATA%\herdr\config.toml`.
Gõ `herdr` sau khi bật máy là mọi space hiện lại và từng pane Claude tự mở đúng phiên cũ
kèm lịch sử — không cần `claude --continue`. Hook báo session-id nằm ở
`~/.claude/hooks/herdr-agent-state.ps1`.
