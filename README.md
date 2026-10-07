# Herdr config backup — KZTEK Firmware

Sao lưu toàn bộ cấu hình [Herdr](https://herdr.dev) (trình quản lý terminal cho AI
coding agent) cùng phần tích hợp Claude Code đang dùng trên máy phát triển firmware
của KZTEK.

- Herdr: `0.9.3-x86_64-pc-windows-msvc`
- Máy nguồn: Windows 11, user `vanwk`
- Bố cục: 7 workspace (space) — xem [docs/layout.md](docs/layout.md)

## Repo chứa gì

| Đường dẫn trong repo | Vị trí thật trên máy | Vai trò |
|---|---|---|
| `config/config.toml` | `%APPDATA%\herdr\config.toml` | Cấu hình chính của Herdr |
| `config/config.default.toml` | — (sinh bởi `herdr --default-config`) | Bản tham chiếu mọi khoá cấu hình |
| `config/session.json` | `%APPDATA%\herdr\session.json` | Bố cục 7 space / tab / pane + session id của agent |
| `claude/settings.json` | `%USERPROFILE%\.claude\settings.json` | Đăng ký hook `SessionStart` cho Herdr, model, statusline |
| `claude/hooks/herdr-agent-state.ps1` | `%USERPROFILE%\.claude\hooks\herdr-agent-state.ps1` | Hook báo session-id của Claude về Herdr (do `herdr integration install claude` sinh ra) |
| `claude/skills/herdr/SKILL.md` | `%USERPROFILE%\.claude\skills\herdr\SKILL.md` | Skill dạy Claude dùng CLI `herdr` |
| `claude/statusline-usage.py` | `%USERPROFILE%\.claude\statusline-usage.py` | Statusline (không thuộc Herdr, nhưng `settings.json` tham chiếu tới) |
| `claude/CLAUDE.manager.md` | `E:\Kztek_Firmwave\CLAUDE.md` | Quy ước bố cục space/pane cho pane `manager` |
| `scripts/backup.ps1` | — | Hút config từ máy vào repo |
| `scripts/restore.ps1` | — | Đẩy config từ repo ra máy |

## Dùng nhanh

```powershell
# Cập nhật backup sau khi đổi config
.\scripts\backup.ps1
git add -A; git commit -m "backup: cap nhat config"; git push

# Khôi phục lên máy mới / sau khi cài lại Windows
.\scripts\restore.ps1
```

Hướng dẫn cài từ đầu trên máy trắng: [INSTALL.md](INSTALL.md).

## Lưu ý

- `config/session.json` là **trạng thái runtime**, không phải config thuần. Nó chứa
  đường dẫn tuyệt đối (`E:\Kztek_Firmwave\...`) và UUID phiên hội thoại Claude.
  Khôi phục file này sang máy khác chỉ có nghĩa khi máy đó có cùng cây thư mục dự án;
  các UUID phiên sẽ trỏ vào transcript không tồn tại và Herdr tự bỏ qua, pane vẫn mở
  đúng nhưng mở phiên Claude mới.
- Khôi phục `session.json` phải làm khi **Herdr server đang tắt**, nếu không server
  sẽ ghi đè lại khi thoát.
- Repo này **không** chứa `.credentials.json`, token, hay khoá SSH.
