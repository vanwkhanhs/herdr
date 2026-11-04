# Xep project vao nhom (project group) tren sidebar Orca theo PLAN, qua RPC cua runtime
# dang chay - khong can tat Orca. Chay lai bao nhieu lan cung duoc.
#   Laptop:  python scripts/orca/orca-groups.py [--dry]
#   Server:  python3 orca-groups.py [--dry]        (Python 3.6 tren kztek-build)
# Moi runtime (laptop, kztek-build) giu danh sach nhom RIENG -> chay o ca hai noi.
# Nhom ngoai PLAN ma rong sau khi xep thi bi xoa; nhom con cua nhom trong PLAN thi giu.
# Nhom o 2 may phai CUNG ID moi gop thanh 1 tieu de - script nay tao nhom thi ID ngau nhien.
# Nhom moi: xem README muc "Nhom project" truoc khi chay tren server.
import io, json, os, socket, sys, unicodedata, uuid

# (nhom, [ten project]) - thu tu trong list = thu tu tren sidebar
PLAN = [
    ('Kztek_Firmwave', ['KZ_E02.NET', 'kz_e16.net_firmware-dev1', 'kz_e32.net_firmware-dev1',
                        'smart_lock_control_12ch', 'EV_CS_10CH_V1.0', 'KZ_FP_MODULE']),
    ('Linux_SoC', ['SDK_RV1126B', 'SSC37X_CAM', 'BUILD_LUCKFOX3566']),
    ('Tools', ['KzFlashTool', 'herdr-backup']),
    ('Hardware', ['Cam báo trống']),
]
DRY = '--dry' in sys.argv


def nfc(s):
    return unicodedata.normalize('NFC', s or '')


def rpc(method, params=None):
    if os.name == 'nt':
        meta = json.load(io.open(os.path.expandvars(r'%APPDATA%\orca\orca-runtime.json'), encoding='utf-8'))
        end = next(t['endpoint'] for t in meta['transports'] if t['kind'] == 'named-pipe')
        f = open(end, 'r+b', buffering=0)
        send, recv = f.write, lambda: f.read(65536)
    else:
        meta = json.load(io.open(os.path.expanduser('~/.config/orca/orca-runtime.json'), encoding='utf-8'))
        end = next(t['endpoint'] for t in meta['transports'] if t['kind'] != 'websocket')
        s = socket.socket(socket.AF_UNIX)
        s.connect(end)
        send, recv = s.sendall, lambda: s.recv(65536)
    send((json.dumps({'id': str(uuid.uuid4()), 'authToken': meta['authToken'],
                      'method': method, 'params': params}) + '\n').encode('utf-8'))
    buf = b''
    while True:
        chunk = recv()
        if not chunk:
            raise SystemExit('%s: Orca dong ket noi' % method)
        buf += chunk
        while b'\n' in buf:
            line, buf = buf.split(b'\n', 1)
            if not line.strip():
                continue
            d = json.loads(line.decode('utf-8'))
            if '_keepalive' in d:
                continue
            if not d.get('ok'):
                raise SystemExit('%s loi: %s' % (method, json.dumps(d, ensure_ascii=False)[:400]))
            return d['result']


def act(msg, method, params):
    print(('[dry] ' if DRY else '') + msg)
    return None if DRY else rpc(method, params)


repos = rpc('repo.list')['repos']
groups = rpc('projectGroup.list')['groups']
by_name = {}
for r in repos:
    by_name.setdefault(nfc(r['displayName']), []).append(r)

wanted = set()
for order, (gname, names) in enumerate(PLAN):
    members = [r for n in names for r in by_name.get(nfc(n), [])]
    if not members:
        continue                                   # runtime nay khong co project nao cua nhom
    g = next((g for g in groups if g['name'] == gname), None)
    if g is None:
        res = act('tao nhom %s' % gname, 'projectGroup.create', {'name': gname, 'createdFrom': 'manual'})
        g = res['group'] if res else {'id': '<moi:%s>' % gname, 'name': gname, 'tabOrder': None,
                                       'parentGroupId': None}
    wanted.add(g['id'])
    if g.get('tabOrder') != order or g.get('parentGroupId'):
        act('nhom %s: thu tu %d' % (gname, order), 'projectGroup.update',
            {'groupId': g['id'], 'updates': {'tabOrder': order}})
    # Nhom con Orca tu dung theo thu muc (folder-scan, vd Elevator trong Kztek_Firmwave):
    # project nam trong do coi nhu da dung nhom - keo ra thi lan khoi dong sau Orca lai dung lai.
    subs = set(k['id'] for k in groups if k.get('parentGroupId') == g['id'])
    for i, r in enumerate(members):
        if r.get('projectGroupId') in subs:
            continue
        if r.get('projectGroupId') == g['id'] and r.get('projectGroupOrder') == i:
            continue
        act('  %s -> %s' % (r['displayName'], gname), 'projectGroup.moveProject',
            {'repo': 'id:' + r['id'], 'groupId': g['id'], 'order': i, 'connectionId': None})

# Nhom cu ngoai PLAN: xoa khi khong con project/nhom con (sau khi da don project ra)
repos = repos if DRY else rpc('repo.list')['repos']
for g in rpc('projectGroup.list')['groups']:
    if g['id'] in wanted or g['name'] in [p[0] for p in PLAN] or g.get('parentGroupId') in wanted:
        continue
    used = [r['displayName'] for r in repos if r.get('projectGroupId') == g['id']
            and not any(nfc(r['displayName']) in map(nfc, names) for _, names in PLAN)]
    kids = [k for k in groups if k.get('parentGroupId') == g['id']]
    if used or kids:
        print('giu nhom %s (con %s)' % (g['name'], ', '.join(used + [k['name'] for k in kids])))
    else:
        act('xoa nhom rong %s' % g['name'], 'projectGroup.delete', {'groupId': g['id']})
print('xong')
