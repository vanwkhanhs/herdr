# Orca server tren kztek-build (Ubuntu 18.04, chay 24/7)

Dung 29/10/2026. May build `kztek-build` (LAN 192.168.21.105, Tailscale 100.121.167.64)
chay `orca serve` lam server chinh; laptop va may khac ket noi vao.

## Da cai gi

| Thu | Cho | Ghi chu |
|---|---|---|
| Claude Code 2.1.312 | `~/.local/bin/claude` | cai native, chay duoc tren 18.04 (glibc 2.27) |
| Orca 1.4.243 | `~/.local/opt/orca/app` | AppImage da GIAI NEN - khong phu thuoc FUSE |
| CLI | `~/.local/bin/orca-ide`, `~/.local/bin/orca` | `orca serve` tu cai. `/usr/bin/orca` la trinh doc man hinh GNOME, KHONG phai Orca |
| Goi apt | `libxss1 xvfb xdotool xclip xdg-utils` | `xvfb` bat buoc: serve can man hinh X ao |
| Service | `~/.config/systemd/user/orca-server.service` | ban sao o day; `loginctl enable-linger kztek` da bat |

## Lenh hay dung (tren kztek-build)

```bash
systemctl --user status orca-server       # trang thai
systemctl --user restart orca-server      # khoi dong lai
sudo journalctl _SYSTEMD_USER_UNIT=orca-server.service -f   # log (can sudo tren 18.04)
```

## Ghep cap may moi

Ma ghep cap nam trong log service (dong `Pairing URL:`). Lay va them tu Git Bash:

```bash
ssh kztek-build 'sudo journalctl _SYSTEMD_USER_UNIT=orca-server.service -o cat | grep "^Pairing URL:" | tail -1 | sed "s/^Pairing URL: *//"' > pair.txt
orca environment add --name kztek-build --pairing-code "$(cat pair.txt)"; rm pair.txt
```

Dung Git Bash, KHONG dung PowerShell 5.1: no lam hong nhay kep (PITFALLS #18).
Ma ghep cap la bi mat - dung in ra, dung commit.

## Cap nhat Orca

Ban giai nen khong tu cap nhat. Lam tay:

```bash
V=v1.4.xxx; cd ~/.local/opt/orca
curl -sSL -o o.AppImage https://github.com/stablyai/orca/releases/download/$V/orca-linux.AppImage
chmod +x o.AppImage && ./o.AppImage --appimage-extract >/dev/null && rm -rf app && mv squashfs-root app && rm o.AppImage
systemctl --user restart orca-server
```

## Can do khi dung

- `orca serve` bao `needs an X display` -> thieu `xvfb`.
- Chay thu bang `timeout N orca-ide serve` se ket thuc bang loat loi GPU/zygote va
  `SIGILL` - do `timeout` giet tien trinh, KHONG phai loi that. Service chay on dinh.
- Secret luu khong ma hoa (khong co keyring tren may headless) - Orca tu canh bao.

## Project da chuyen len (29/10/2026)

Chep NGUYEN thu muc lam viec (ke ca thay doi chua commit) tu laptop qua LAN
(`tar | ssh kztek@192.168.21.105`), giu cau truc:

| Laptop | kztek-build |
|---|---|
| `E:\Kztek_Firmwave\...` | `~/Kztek_Firmwave/...` |
| `E:\project_kztek\...` | `~/project_kztek/...` |

11 project: KZ_E02.NET, kz_e32, kz_e16, smart_lock_control_12ch, KzFlashTool,
EV_CS_10CH_V1.0, SDK_RV1126B, SSC37X_CAM, BUILD_LUCKFOX3566, KZ_FP_MODULE, herdr-backup.
Da `orca repo add --environment kztek-build` ca 11.

Sau khi chep phai sua 2 thu, khong thi `git status` bao sai:
- `git config core.autocrlf true` trong tung repo (laptop dung true; file tren dia la CRLF).
- Quyen chay: tar cua Git Bash tu danh `+x` cho file `.sh` -> go `+x` cho file git ghi
  `100644`, them `+x` cho file git ghi `100755`.
Doi chieu: so file chua commit tren server = tren laptop, 11/11 khop.

Lich su Claude: 22 phien chep vao `~/.claude/projects/-home-kztek-<duong dan>/`
(khoa = duong dan, ky tu khong phai chu/so doi thanh `-`). Kiem tra JSON: 22/22 hop le.

SDK_RV1126B: zip `rwa023...sdk` 30,6 GB da co san o `~/Downloads/RV1126B` -> hard link,
khong chep lai. Zip `rv1126b-v1-0` 39,6 GB chep qua LAN.

Kem theo: `~/.claude/agents` (fw-*), skill arm-cortex-expert / embedded-systems /
harness-creator, statusline, `~/Kztek_Firmwave/CLAUDE.md` + `_harness_chuan`.
`settings.json` tren server GOP them model/effort/tui/statusLine - hook do Orca server
tu ghi (15 su kien) giu nguyen. Hook Windows (review-relay.ps1, herdr) KHONG chep.
- **Ten thu muc phien dinh `\r`**: danh sach anh xa tao bang PowerShell (CRLF) roi doc
  bang `while read` trong Bash -> 11 thu muc phien tren server co `\r` cuoi ten, nhin
  giong het nhung Claude KHONG tim thay. Kiem tra: `ls ~/.claude/projects | cat -A`
  (thay `^M`). Da doi ten lai. Doc file tu Windows trong Bash: `tr -d '\r'` truoc.
- **`claude -p` an stdin**: chay trong `ssh host 'bash -s' <<EOF` thi no doc ca phan con
  lai cua script lam cau hoi, cac dong sau khong chay. Luon them `</dev/null`.
- Da do: Claude tren server dat khoa thu muc phien = duong dan, ky tu khong phai
  chu/so doi thanh `-` (vd `/tmp/kz_key.test` -> `-tmp-kz-key-test`).

## Loi "Failed to load native module: pty.node" (da sua 29/10/2026)

Trieu chung: tu laptop mo terminal tren kztek-build bao `Cannot find module
'./prebuilds/linux-x64//pty.node'`. Ten loi danh lac huong - file CO, nhung
`build/Release/pty.node` doi **GLIBC_2.28**, Ubuntu 18.04 chi co 2.27. node-pty thu
het cac cho roi chi in loi cua cho cuoi cung.

Orca dong goi san ban `orcad-template/targets/linux-x64-glibc217/.../pty.node` (chi can
glibc 2.14) cho tien trinh nen orcad, nhung orcad hong preflight nen Orca roi ve ban
chinh. Sua: `fix-glibc227.sh` chep ban glibc217 vao `build/orca-napi-linux-x64/` - cho
node-pty tim DAU TIEN - khong ghi de file goc. Chay lam `ExecStartPre` nen cap nhat
Orca (giai nen lai app/) van tu sua lai.

Da do: mo terminal that tu laptop -> chay dung thu muc, co `claude`.

Con mot module native khong chay tren 18.04: `sherpa-onnx` (nhan dang giong noi) doi
GLIBCXX_3.4.29, may co 3.4.25. Khong anh huong terminal / Claude.

## kz-orca: layout builder|reviewer|debug + vong review tren server (29/10/2026)

Ban Linux cua `scripts/orca/*.ps1`. Ma nguon `kz-orca/`, cai bang
`bash kz-orca/install.sh` (chay lai bao nhieu lan cung duoc) vao `~/.local/opt/kz-orca`.

| Thanh phan | Viec |
|---|---|
| `kz-orca-watcher.service` | client xem project dang ngu -> dung 3 pane; client dong tab -> ngu han; Orca server khoi dong lai -> cho moi project ngu |
| `pane.sh` | lenh khoi dong pane (source): ghi vai tro vao so dang ky, chon phien, `ngu` trong debug |
| hook `SessionStart` | ghi ma phien theo vai tro -> lan sau builder/reviewer mo dung phien cua minh |
| hook `Stop` | builder sua code xong -> reviewer; reviewer co `KET LUAN:` -> builder (toi da 3 vong) |
| `projects.json` | 10 project quan ly (herdr-backup CO Y khong) |

Trang thai: `~/.local/state/kz-orca/` (`panes.json`, `sessions.json`, `watch.json`, `kz-orca.log`).

**Khac laptop - do that:**
- `orca terminal rename` tren Linux DE TEN MOI PANE thanh ten tab -> khong nhan vai tro
  bang ten pane. Moi pane tu ghi `ORCA_TERMINAL_HANDLE` + vai tro vao `panes.json`.
- `terminal create` co `--title` thi pane khong nhan ten OSC -> tao khong `--title`, doi ten tab sau.
- Trace server khong co `check-ignore`/`sidebar_worktree_activate`. Tin hieu "dang xem" la
  `git status` trong worktree (client lam moi ~15 s, CHI worktree dang xem). Mot lan xem moi
  = >45 s khong thay status cua project do.
- `terminal split` tra `result.split.handle`, `create` tra `result.terminal.handle`.
- Python 3.6 + locale C giai ma ASCII -> vo voi tieng Viet. Moi lenh con giai ma UTF-8
  bang tay; unit dat `LANG=C.UTF-8`.
- `update_json`: KHONG `fn(d) or d` - loc het thi `{}` la falsy, giu nguyen du lieu cu.
- Lan dau mo moi thu muc, Claude hoi "trust this folder?" o ca builder va reviewer.
