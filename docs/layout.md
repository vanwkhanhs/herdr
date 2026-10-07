# Bố cục Herdr — 7 space

Chụp tại 2026-10-07, từ `%APPDATA%\herdr\session.json` (bản sao ở `config/session.json`).

> Trong mọi hội thoại với Claude ở máy này, **"space"** luôn có nghĩa là Herdr
> workspace — không phải vùng nhớ firmware, dung lượng ổ đĩa, Notion/Slack hay thư
> mục dự án.

| Phím | ID | Tên space | Thư mục gốc | Pane |
|---|---|---|---|---|
| 1 | `w4` | KZ_E02.NET | `E:\Kztek_Firmwave\Access_Control\KZ_E02.NET` | builder, reviewer, debug |
| 2 | `w7` | E32 | `E:\Kztek_Firmwave\Elevator\kz_e32.net_firmware-dev1` | builder, reviewer, debug |
| 3 | `w8` | E16 | `E:\Kztek_Firmwave\Elevator\kz_e16.net_firmware-dev1` | builder, reviewer, debug |
| 4 | `w9` | iLocker 12CH | `E:\Kztek_Firmwave\iLocker\board_12ch\smart_lock_control_12ch` | builder, reviewer, debug |
| 5 | `wA` | KzFlashTool | `E:\Kztek_Firmwave\KzFlashTool` | builder, reviewer, debug |
| 6 | `wC` | RV1126B dual cam 5MP | `E:\project_kztek\SDK_RV1126B` | builder, reviewer, debug |
| 7 | `wE` | Manager | `E:\Kztek_Firmwave` | manager |

Chỉ `w4` (KZ_E02.NET) được đăng ký là **worktree space** — Herdr nhận ra nó là git
repo và gắn `repo_root` tương ứng. Sáu space còn lại là space thường theo `cwd`.

## Quy ước pane

Sáu space dự án mỗi cái có 3 pane:

| Pane | Vai trò |
|---|---|
| `builder` | Claude viết/sửa code |
| `reviewer` | Claude review — **phiên riêng**, không dùng chung với builder |
| `debug` | Terminal thuần — build, nạp bo, ssh. **Không** chạy Claude trong đây |

Space **Manager** (`wE`) chỉ có một pane `manager`: nơi điều phối các space khác,
tạo thêm pane hoặc space khi cần.

Bố cục chia pane mặc định: tách ngang 50/50 (builder bên trái), nửa phải tách dọc
50/50 (reviewer trên, debug dưới).

## Lệnh hay dùng

```bash
herdr workspace list     # danh sách space
herdr pane list          # danh sách pane
herdr agent list         # agent nào đang idle / working / blocked
```

Kết quả trả về JSON — lấy ID từ đó, đừng suy ra từ thứ tự hiển thị trên sidebar.

## Quy tắc điều khiển

- **Không bao giờ** chạy `herdr server stop` trừ khi cố ý tắt server — lệnh đó giết
  toàn bộ pane đang chạy.
- Trước khi gửi prompt sang agent khác, kiểm tra nó không ở trạng thái `blocked`
  (đang chờ người dùng trả lời hộp thoại). Nếu blocked thì hỏi người dùng, đừng tự bấm.
- `idle` và `done` đều nghĩa là agent sẵn sàng nhận input. `unknown` nghĩa là có agent
  nhưng Herdr không phân loại chắc chắn — không chứng minh là đã xong.

## Tự khôi phục sau khi tắt máy

`[session] resume_agents_on_restore = true` trong `config.toml`. Gõ `herdr` sau khi
bật máy là mọi space hiện lại và từng pane Claude tự mở đúng phiên cũ kèm lịch sử —
không cần `claude --continue`. Hook báo session-id nằm ở
`~/.claude/hooks/herdr-agent-state.ps1`.
