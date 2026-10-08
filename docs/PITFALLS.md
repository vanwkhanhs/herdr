# Cạm bẫy đã gặp thật — đừng dẫm lại

Mỗi mục: **triệu chứng → nguyên nhân → cách đúng**. Tất cả đều đã xảy ra và đo được,
không phải suy đoán.

---

## Orca

### 1. `terminal rename` đổi tên TAB, không phải pane

Gọi `orca terminal rename --title builder` trả `ok` nhưng tên pane không đổi — Orca
hiển thị **title sống của tiến trình**. Một tab chỉ có một tên dù chứa 3 pane; đặt lần
lượt builder → reviewer → debug thì cả tab thành "debug".

**Đúng:** tên pane do chính tiến trình đặt — `WindowTitle` kèm
`CLAUDE_CODE_DISABLE_TERMINAL_TITLE=1` để Claude không ghi đè bằng chủ đề hội thoại.
Dùng `rename` cho tên tab (= tên project).

### 2. Orca gõ lại lệnh khởi động vào shell, chuỗi dài bị cắt cụt

Khi khởi động lại, Orca **gõ lại** lệnh khởi động chứ không chạy sạch. Chuỗi dài bị cắt
giữa chừng — đã gặp: `$env:CLAUDE_CODE_DISABLE_TERMINAL_TITL` cụt ở đó, kéo theo mất tên
pane và chạy nhầm lệnh.

**Đúng:** để lệnh Orca lưu thật ngắn. Mọi logic nằm trong `pane.ps1`.

### 3. Đừng ghim `claude --resume <id>` cứng vào lệnh khởi động

Session-id đổi theo thời gian. Lần sau Orca gõ lại sẽ báo
`No conversation found with session ID: ...` và mở phiên trống.

**Đúng:** lấy id mới từ Herdr **tại thời điểm dựng layout**, không ghim vào lệnh.

### 4. Đóng terminal phải dùng `--worktree <path> --all`

Đóng từng pane bằng `--terminal` để lại một **resume record** cho mỗi pane có agent.
Mỗi lần dựng lại layout cộng thêm một cặp → dưới project hiện **4 agent** trong khi chỉ
có 2 đang chạy. Đây là lỗi tốn nhiều thời gian nhất.

Tài liệu của `--all` ghi rõ: *"durably removes its terminal tabs, layouts, and
**resume records**"*.

**Đo được:** KzFlashTool 4 → 2 ngay sau khi đóng kiểu này, dựng lại vẫn giữ 2.

### 5. Orca khôi phục tab cũ thành NHIỀU ĐỢT rải ra vài phút

Không phải một lần. Đã gặp: lượt dọn `11:24:53` báo sạch, đến `11:26` KZ_E02 lại mọc
thêm một tab cũ ba pane.

**Đúng:** dọn lặp, nhịp thưa dần — `10,10,15,15,30,30,60,60,120,120` giây, phủ ~8 phút.
Dày ở phút đầu vì đó là lúc Orca khôi phục nhiều nhất.

### 6. Terminal mồ côi sống sót qua khởi động lại

Sau khi Orca restart, PTY cũ còn sống nhưng mất tab: `orphaned=true`, `title=null`, mà
Orca **vẫn gắn `agentIdentity=claude`**. Người dùng thấy chúng như agent thừa. Đã gặp
18 cái, riêng smart_lock 6 (4 mang agent).

**Đúng:** đóng chúng ở đầu mỗi lần chạy layout, chỉ trong worktree được quản lý.

### 7. Xét "layout lành" sai hai lần

- Theo **số pane** → sai: sau reset Orca khôi phục đủ tab nhưng chỉ là shell trống,
  script bỏ qua, không project nào có Claude.
- Theo **có agent** → vẫn sai: Orca gắn `agentIdentity=claude` cho cả pane khôi phục
  hỏng, script bỏ qua và để nguyên trạng thái hỏng.

**Đúng:** đủ pane **đúng tên** `builder`/`reviewer`/`debug` **VÀ** có agent. Tên pane là
bằng chứng tin cậy vì chỉ `pane.ps1` đặt được.

### 8. Thư mục lịch sử terminal hiện ra như agent

Mỗi terminal bị đóng để lại `%APPDATA%\orca\terminal-history\<ptyId mã hoá URL>`.
Đã gặp 42 thư mục cho 16 terminal sống.

**Đúng:** xoá thư mục không gắn ptyId nào đang sống, chỉ trong worktree được quản lý.

### 9. `orca-data.json` là bản xuất, KHÔNG phải kho thật

Nó đứng yên hàng chục phút trong khi trạng thái đổi liên tục. Đọc nó rồi kết luận là
sai nhiều lần.

**Đúng:** kho thật là `profiles\local-default\profile-state.db` (SQLite). Dữ liệu nằm
trong WAL nên phải chép cả `.db` + `-wal` + `-shm` rồi mới đọc. Bảng
`profile_state_documents`: cột `payload` là JSON, `content_hash` = **sha256 hex của
payload**, kèm cột `revision`.

### 10. Hai thứ Orca KHÔNG làm được

- **Không có tuỳ chọn tắt khôi phục tab.** Đã rà hết 207 setting; chỉ có
  `nativeChatResumeWorkOnRestart` dành cho chat nội bộ.
- **`Setup Script` chỉ chạy khi tạo worktree mới**, không chạy lúc mở app — không dùng
  được để dựng layout.

---

## Watcher

### 11. Nhận diện lần mở mới bằng `runtimeId`, không bằng "thấy Orca tắt"

Watcher poll 5 giây/lần; đóng mở Orca nhanh hơn thế thì nó **không bao giờ thấy khoảng
trống**, tưởng vẫn là phiên cũ và không dựng lại. Đã hỏng thật: 4/5 project mất sạch
pane, log watcher đứng im.

**Đúng:** so `runtimeId` từ `orca status --json`; khác lần trước nghĩa là runtime mới.

### 12. `-WindowStyle Hidden` vô dụng khi Windows Terminal là terminal mặc định

Scheduled Task gọi thẳng `powershell.exe -WindowStyle Hidden` vẫn bật một cửa sổ console
mỗi lần đăng nhập và không bao giờ tự tắt.

**Đúng:** gọi qua `wscript.exe watcher-hidden.vbs`, dùng `WScript.Shell.Run` với tham số
cửa sổ `0`.

### 13. Scheduled Task phải có cơ chế tự khởi động lại

Watcher đã chết một lần (`LastTaskResult 0xC000013A`), và vì nó chết nên sau khi bật máy
không có layout nào được dựng.

**Đúng:** `-RestartInterval` 1 phút, `-RestartCount 999`.

---

## Claude Code

### 14. Chế độ quyền đi theo PHIÊN được resume, không theo `settings.json`

Phiên cũ tạo ở `bypassPermissions` thì resume lại vẫn là bypass, dù `settings.json`
không hề có `defaultMode`. Bấm `shift+tab` đổi tay **không được lưu** — lần dựng lại
sẽ quay về như cũ.

**Đúng:** ép tường minh `--permission-mode auto` khi khởi động pane.

### 15. `--session-id <uuid>` không dùng lại được id cũ

Lần hai báo `Session ID ... is already in use.`

**Đúng:** muốn nối tiếp thì `--resume <id>`.

### 16. Nguồn session-id cho từng pane là Herdr

`herdr pane list` trả `label` (builder/reviewer) + `agent_session.value` + `cwd`.
Đó là thứ Orca mượn để resume đúng phiên.

**Bẫy:** watcher chạy ngay khi Orca mở, **sớm hơn** lúc người dùng gõ `herdr`. Lúc đó
Herdr chưa chạy → không lấy được id → reviewer mất sạch lịch sử (đã gặp 5/5).

**Đúng:** lưu đệm ra `herdr-sessions.json` mỗi khi Herdr chạy được, đọc đệm khi chưa.

---

## Công cụ và môi trường

### 17. Git Bash nuốt tham số bắt đầu bằng `/`

`--text "/exit"` biến thành `C:/Program Files/Git/exit` — Claude trả lời nhầm một lượt.

**Đúng:** `MSYS_NO_PATHCONV=1` trước lệnh.

### 18. PowerShell 5.1 làm hỏng nháy kép khi truyền sang file exe

**Đúng:** chuỗi gửi cho `orca.exe` chỉ dùng nháy đơn, lồng nhau bằng cách nhân đôi.

### 19. Backslash bị nuốt trong `node -e` qua shell

Đường dẫn mất dấu phân cách, regex thành biểu thức khác và lỗi cú pháp.

**Đúng:** viết script ra file rồi `node file.js`, hoặc dùng `String.fromCharCode(92)`.
Đừng nhúng backslash vào `node -e`.

### 20. Lọc tiến trình theo CommandLine khớp luôn chính mình

`Where-Object { $_.CommandLine -like '*orca-layout-watcher*' }` khớp cả tiến trình
PowerShell đang chạy lệnh đó → `Stop-Process` tự giết mình, exit 255. Dẫm hai lần.

**Đúng:** luôn thêm điều kiện loại trừ `$PID`.

### 21. `HOME` bị OrCAD chiếm ở mức User

`E:\APP\ORCAD\DATA`. Hệ quả: git global config thật nằm ở đó, và ssh không thấy
`C:\Users\vanwk\.ssh\config` nên alias `gitlab-kztek` chết.

**Đã vá, đừng gỡ:** `core.sshCommand = ssh -F C:/Users/vanwk/.ssh/config` và junction
`E:\APP\ORCAD\DATA\.ssh` trỏ về `C:\Users\vanwk\.ssh`.

---

## Về cách làm việc

### 22. Đo từ ảnh chụp cũ rồi kết luận

Đọc `orca-data.json` (bản xuất, đứng yên) và báo sai số liệu nhiều lần. Trạng thái Orca
đổi liên tục — **đo lại ngay trước khi kết luận**, và đo đúng kho dữ liệu.

### 23. Đoán chỗ hiển thị thay vì xin ảnh

Chuyện "4 agents" đoán sai bốn lần liên tiếp: pane thừa → tiến trình mồ côi → phiên cũ
→ subagent. Chỉ khi người dùng gửi ảnh chụp mới tìm đúng.
Không nhìn thấy giao diện thì **xin ảnh**, đừng đoán.

### 24. Dựng lại layout để test chính là thứ sinh ra rác

Mỗi lần dựng lại đẻ thêm một cặp resume record vào danh sách của người dùng — khoảng
mười lăm lần trong một buổi. **Test trên một project**, đừng chạy toàn bộ.

### 25. Tuyên bố xong khi chưa có bằng chứng đầu-cuối

Đã nói "reset là có hết" rồi lần reset thật hỏng ở ba chỗ. Logic đúng, script đúng,
cấu hình đúng — **không bằng** một lần chạy thật từ đầu đến cuối.
