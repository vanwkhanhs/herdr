# Tạm tắt Herdr — và cách quay lại

Ngày tắt: **08/10/2026**. Lý do: tiết kiệm RAM.

## Vì sao tắt

Chạy song song Herdr và Orca nghĩa là **cùng một hội thoại chạy ở hai nơi**. Ví dụ
builder của `kz_e16` bên Herdr và bên Orca đều resume session `df7779c7` — hai tiến
trình, hai lần RAM, cho đúng một cuộc hội thoại.

Đo được lúc tắt:

```
RAM máy 31,8 GB  |  đang dùng 22,1 GB  |  còn trống 9,7 GB

claude      18 tiến trình   7.847 MB   (~420 MB mỗi phiên)
powershell  29 tiến trình   2.214 MB   (shell của từng pane)
Orca         9 tiến trình   1.441 MB

Herdr: 15 agent Claude  ≈ 6,3 GB
```

Bỏ Herdr cắt khoảng **6 GB** mà không mất nội dung — Orca đang resume đúng những
phiên đó.

## Orca có tự chạy được khi không có Herdr không

**Có.** `orca-layout.ps1` lấy session-id theo thứ tự:

1. Hỏi `herdr pane list` nếu Herdr đang chạy → lưu đệm
2. Herdr không chạy → đọc đệm `scripts/orca/herdr-sessions.json`
3. Không có đệm → builder lùi về `claude --continue`, reviewer mở phiên mới

Đệm đã được **đưa vào git** đúng vì lý do này. Nội dung lúc tắt: 7 thư mục, 14
session-id (builder + reviewer mỗi project).

Log sẽ ghi `(Herdr chua chay - dung dem session-id, 7 thu muc)` — đó là bình thường,
không phải lỗi.

## Những gì đã lưu để quay lại

| File trong repo | Nội dung |
|---|---|
| `config/config.toml` | Cấu hình Herdr, có `resume_agents_on_restore = true` |
| `config/session.json` | **Bố cục 8 space** và pane của từng space |
| `config/config.default.toml` | Bảng tham chiếu mọi khoá cấu hình, sinh từ herdr 0.9.3 |
| `claude/hooks/herdr-agent-state.ps1` | Hook báo session-id cho Herdr |
| `claude/skills/herdr/SKILL.md` | Skill điều khiển Herdr |
| `scripts/orca/herdr-sessions.json` | 14 session-id tại thời điểm tắt |

Transcript hội thoại nằm ở `~/.claude/projects/` — **không bị ảnh hưởng**, tắt Herdr
không mất lịch sử nào.

## Cách quay lại dùng Herdr

```powershell
herdr
```

Chỉ vậy. Server dựng lại, 8 space hiện lại, từng pane Claude tự resume đúng phiên cũ
nhờ `resume_agents_on_restore = true`.

Nếu `session.json` trên máy đã mất hoặc sai, khôi phục từ repo — **phải tắt server
trước**, nếu không nó ghi đè lại lúc thoát:

```powershell
.\scripts\restore.ps1 -IncludeSession
```

## Nếu muốn chạy lại cả hai cùng lúc

Chấp nhận RAM gấp đôi phần Claude. Hoặc giảm tải bằng cách bỏ pane `reviewer` ở một
bên — sửa `Roles` trong `$Projects` của `orca-layout.ps1`:

```powershell
@{ Name = '...'; Path = '...'; Roles = @('builder', 'debug') }
```

## Lưu ý khi Herdr tắt lâu

Session-id trong đệm là ảnh chụp lúc tắt. Nếu sau này bác `/clear` trong một pane Orca,
phiên đó có id mới và đệm thành cũ cho pane đó — không sao, builder vẫn lùi về
`claude --continue` lấy đúng hội thoại gần nhất của thư mục.

Bật lại Herdr thì đệm tự được làm tươi ở lần dựng layout kế tiếp.
