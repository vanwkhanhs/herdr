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
