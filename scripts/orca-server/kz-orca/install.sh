#!/bin/bash
# Cai kz-orca len kztek-build. Chay lai bao nhieu lan cung duoc.
#   bash install.sh            (tu thu muc chua file nay)
set -e
SRC="$(cd "$(dirname "$0")" && pwd)"
DST="$HOME/.local/opt/kz-orca"
STATE="$HOME/.local/state/kz-orca"
mkdir -p "$DST" "$STATE" "$HOME/.config/systemd/user"

# File soan tren Windows co the mang CRLF - bash/python tren Linux se hong vi '\r'
for f in kz_orca.py pane.sh projects.json reviewer-prompt.md; do
    tr -d '\r' < "$SRC/$f" > "$DST/$f"
done
chmod +x "$DST/kz_orca.py"
echo "file: da chep vao $DST"

# Hat giong session-id: CHI them project chua co, khong de cai hook da ghi
python3 - "$SRC/sessions.seed.json" "$STATE/sessions.json" <<'PY'
import io, json, os, sys
seed = json.load(io.open(sys.argv[1], encoding='utf-8-sig'))
cur = json.load(io.open(sys.argv[2], encoding='utf-8')) if os.path.exists(sys.argv[2]) else {}
n = 0
for k, v in seed.items():
    if k not in cur:
        cur[k] = v; n += 1
io.open(sys.argv[2], 'w', encoding='utf-8').write(json.dumps(cur, indent=1))
print('session-id: them %d project (da co %d)' % (n, len(cur) - n))
PY

# Hook Claude: GOP vao settings.json, khong dung toi hook Orca server tu ghi
python3 - "$DST/kz_orca.py" <<'PY'
import io, json, os, sys, time, shutil
p = os.path.expanduser('~/.claude/settings.json')
shutil.copy(p, p + '.bak-' + time.strftime('%Y%m%d-%H%M%S'))
s = json.load(io.open(p, encoding='utf-8'))
hooks = s.setdefault('hooks', {})
for event, sub in (('SessionStart', 'session-start'), ('Stop', 'relay')):
    cmd = 'python3 %s %s' % (sys.argv[1], sub)
    groups = hooks.setdefault(event, [])
    if any(h.get('command') == cmd for g in groups for h in g.get('hooks', [])):
        continue
    groups.append({'hooks': [{'type': 'command', 'command': cmd, 'timeout': 30}]})
    print('hook: them %s -> %s' % (event, sub))
io.open(p, 'w', encoding='utf-8').write(json.dumps(s, ensure_ascii=False, indent=2))
PY

cat > "$HOME/.config/systemd/user/kz-orca-watcher.service" <<'UNIT'
# Watcher kz-orca: bam project -> dung builder|reviewer|debug; client dong tab -> ngu.
# Gan voi orca-server: server khoi dong lai thi watcher cung chay lai.
[Unit]
Description=kz-orca watcher (layout tu dong cho Orca server)
After=orca-server.service
PartOf=orca-server.service

[Service]
Environment=PATH=%h/.local/bin:/usr/local/bin:/usr/bin:/bin
Environment=LANG=C.UTF-8 PYTHONIOENCODING=utf-8
ExecStart=/usr/bin/python3 %h/.local/opt/kz-orca/kz_orca.py watch
Restart=always
RestartSec=5

[Install]
WantedBy=default.target orca-server.service
UNIT
export XDG_RUNTIME_DIR="/run/user/$(id -u)"
systemctl --user daemon-reload
systemctl --user enable kz-orca-watcher.service >/dev/null 2>&1
systemctl --user restart kz-orca-watcher.service
sleep 3
echo "watcher: $(systemctl --user is-active kz-orca-watcher.service)"
tail -3 "$STATE/kz-orca.log" 2>/dev/null || true
