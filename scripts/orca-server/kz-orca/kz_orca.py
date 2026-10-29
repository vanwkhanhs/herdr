#!/usr/bin/env python3
"""
kz_orca - layout builder|reviewer|debug va vong review tu dong cho Orca SERVER
tren kztek-build (Ubuntu 18.04). Ban Linux cua scripts/orca/*.ps1 tren laptop.

Mot file, nhieu lenh con:

  watch                  daemon (systemd kz-orca-watcher): bam project -> dung layout,
                         client dong tab -> cho ngu han, Orca server khoi dong lai ->
                         cho moi project ngu
  layout <path>          dung layout cho mot project (bo qua neu da lanh)
  sleep  <path>          cho project ngu: dong het terminal bang --all
  register <role> <path> pane.sh goi luc pane khoi dong: ghi vai tro vao so dang ky
  claude-args <role> <path>  pane.sh goi: in tham so cho claude (resume dung phien)
  session-start          hook SessionStart: ghi ma phien theo vai tro
  relay                  hook Stop: builder xong -> reviewer; reviewer xong -> builder

KHAC LAPTOP - do that 29/10/2026:
  - 'orca terminal rename' tren Linux DE TEN MOI PANE trong tab thanh ten tab, nen
    KHONG nhan vai tro bang ten pane duoc. Moi pane tu ghi vai tro + ORCA_TERMINAL_HANDLE
    vao so dang ky (panes.json); moi thu tra so nay.
  - Khong co 'check-ignore' / 'sidebar_worktree_activate' trong trace cua server. Tin
    hieu "dang xem project" la 'git status' chay trong worktree do (client lam moi
    Source Control dinh ky ~15 s, CHI cho worktree dang xem).
  - Client dong tab -> 'runtime.session-tabs.close' kem deviceId. Lenh dong chay tai
    server (chinh watcher nay) KHONG ghi su kien nay -> khong tu hieu nham minh.
"""

import fcntl
import io
import json
import os
import re
import subprocess
import sys
import time
import uuid

HOME = os.path.expanduser('~')
ORCA = os.path.join(HOME, '.local', 'bin', 'orca')
BASE = os.path.dirname(os.path.abspath(__file__))
STATE = os.path.join(HOME, '.local', 'state', 'kz-orca')
PANES = os.path.join(STATE, 'panes.json')
SESSIONS = os.path.join(STATE, 'sessions.json')
WATCH_STATE = os.path.join(STATE, 'watch.json')
LOG = os.path.join(STATE, 'kz-orca.log')
TRACE = os.path.join(HOME, '.config', 'orca', 'logs', 'main.trace.ndjson')
PROJECTS_FILE = os.path.join(BASE, 'projects.json')
REVIEWER_PROMPT = os.path.join(BASE, 'reviewer-prompt.md')
ROLES = ('builder', 'reviewer', 'debug')

# Mot "lan xem" project ket thuc khi khong thay git status cua no trong chung nay giay.
# Client lam moi ~15 s mot lan khi dang xem -> 45 s la du chac nguoi dung da roi di.
VIEW_GAP = 45
MAX_ROUNDS = 3
MARKER = '[auto-review]'


# ---------------------------------------------------------------- tien ich chung
def log(msg):
    os.makedirs(STATE, exist_ok=True)
    with io.open(LOG, 'a', encoding='utf-8') as f:
        f.write('%s  %s\n' % (time.strftime('%Y-%m-%d %H:%M:%S'), msg))


def norm(p):
    return os.path.normpath(os.path.expanduser(p)).rstrip('/')


def load_json(path, default):
    try:
        with io.open(path, encoding='utf-8') as f:
            return json.load(f)
    except Exception:
        return default


def update_json(path, fn, default):
    """Doc-sua-ghi co khoa: ba pane khoi dong cung luc cung ghi panes.json."""
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with io.open(path + '.lock', 'w') as lk:
        fcntl.flock(lk, fcntl.LOCK_EX)
        data = load_json(path, default)
        new = fn(data)
        # KHONG viet 'fn(data) or data': loc het thi fn tra {} - rong la "falsy" nen
        # giu lai du lieu cu. Da gap: dong project xong so dang ky van con pane chet.
        if new is not None:
            data = new
        tmp = path + '.tmp'
        with io.open(tmp, 'w', encoding='utf-8') as f:
            f.write(json.dumps(data, ensure_ascii=False, indent=1))
        os.replace(tmp, path)
        return data


def run(argv, timeout=60):
    """Chay lenh, tra (returncode, stdout chuoi). Tu giai ma UTF-8: Python 3.6 tren
    18.04 voi locale C mac dinh giai ma ASCII -> vo ngay khi gap tieng Viet (do that:
    'terminal list' co tieu de tab tieng Viet). KHONG dung universal_newlines."""
    p = subprocess.run(argv, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                       stderr=subprocess.DEVNULL, timeout=timeout)
    return p.returncode, p.stdout.decode('utf-8', 'replace')


def orca(*args):
    """Goi orca CLI cua server, tra ve JSON (None neu loi). stdin dong: CLI khong doc."""
    try:
        return json.loads(run([ORCA] + list(args) + ['--json'])[1])
    except Exception:
        return None


def terminals():
    r = orca('terminal', 'list')
    if not r or not r.get('ok'):
        return None
    return [t for t in r['result']['terminals'] if not t.get('orphaned')]


def projects():
    return [dict(p, path=norm(p['path'])) for p in load_json(PROJECTS_FILE, [])]


def project_of(path):
    path = norm(path)
    for p in projects():
        if path == p['path'] or path.startswith(p['path'] + '/'):
            return p
    return None


def claude_dir(path):
    return os.path.join(HOME, '.claude', 'projects', re.sub(r'[^A-Za-z0-9]', '-', norm(path)))


def session_exists(path, sid):
    return bool(sid) and os.path.isfile(os.path.join(claude_dir(path), sid + '.jsonl'))


def live_roles(path, terms):
    """Vai tro dang song trong project = so dang ky giao voi terminal dang song."""
    live = {t['handle'] for t in terms if norm(t.get('worktreePath', '')) == path}
    reg = load_json(PANES, {})
    return {v['role']: h for h, v in reg.items() if h in live and v.get('path') == path}


# ---------------------------------------------------------------- layout / ngu
def handle_of(r):
    if not r or not r.get('ok'):
        return None
    res = r['result']
    # 'create' tra result.terminal.handle, 'split' tra result.split.handle (do 29/10)
    return (res.get('terminal') or res.get('split') or res).get('handle')


def build_layout(path, why=''):
    p = project_of(path)
    if not p:
        return False
    path = p['path']
    roles = p.get('roles') or list(ROLES)
    terms = terminals()
    if terms is None:
        log('LOI: khong doc duoc terminal list')
        return False
    alive = {t['handle'] for t in terms}
    update_json(PANES, lambda d: {h: v for h, v in d.items() if h in alive}, {})   # bo pane da chet
    have = live_roles(path, terms)
    if all(r in have for r in roles):
        return False                                   # da lanh

    mine = [t for t in terms if norm(t.get('worktreePath', '')) == path]
    if mine:
        # --all: xoa luon tab, layout va resume record (PITFALLS #4)
        orca('terminal', 'close', '--worktree', 'path:' + path, '--all')
        forget_panes(path)

    cmd = lambda role: '. %s %s' % (os.path.join(BASE, 'pane.sh'), role)
    # KHONG dat --title luc tao: co --title thi pane khong nhan ten OSC cua tien trinh
    first = handle_of(orca('terminal', 'create', '--worktree', 'path:' + path, '--command', cmd(roles[0])))
    if not first:
        log('LOI: tao pane %s cho %s that bai' % (roles[0], p['name']))
        return False
    # Dua tab len truoc ngay sau pane dau - nguoi dung thay som hon
    orca('terminal', 'switch', '--terminal', first)
    prev = first
    for i, role in enumerate(roles[1:], start=1):
        h = handle_of(orca('terminal', 'split', '--terminal', prev,
                           '--direction', 'vertical' if i == 1 else 'horizontal', '--command', cmd(role)))
        if not h:
            log('LOI: tao pane %s cho %s that bai' % (role, p['name']))
            break
        prev = h
    orca('terminal', 'rename', '--terminal', first, '--title', p['name'])
    log('dung layout %s%s' % (p['name'], ' (' + why + ')' if why else ''))
    return True


def sleep_project(path, why=''):
    p = project_of(path)
    if not p:
        return
    terms = terminals() or []
    if any(norm(t.get('worktreePath', '')) == p['path'] for t in terms):
        orca('terminal', 'close', '--worktree', 'path:' + p['path'], '--all')
    forget_panes(p['path'])
    log('cho ngu %s%s' % (p['name'], ' (' + why + ')' if why else ''))


def forget_panes(path):
    update_json(PANES, lambda d: {h: v for h, v in d.items() if v.get('path') != path}, {})


# ---------------------------------------------------------------- pane.sh goi
def cmd_register(role, path):
    h = os.environ.get('ORCA_TERMINAL_HANDLE')
    if not h:
        return
    p = project_of(path)
    entry = {'role': role, 'path': p['path'] if p else norm(path),
             'tab': os.environ.get('ORCA_TAB_ID', ''), 'ts': int(time.time())}
    update_json(PANES, lambda d: dict(d, **{h: entry}), {})


def cmd_claude_args(role, path):
    p = project_of(path)
    root = p['path'] if p else norm(path)
    sid = load_json(SESSIONS, {}).get(root, {}).get(role)
    args = ['--permission-mode', 'auto', '--model', "'opus[1m]'"]
    if role == 'reviewer' and os.path.isfile(REVIEWER_PROMPT):
        args += ['--append-system-prompt-file', "'%s'" % REVIEWER_PROMPT]
    cdir = claude_dir(root)
    has_history = os.path.isdir(cdir) and any(f.endswith('.jsonl') for f in os.listdir(cdir))
    if session_exists(root, sid):
        args += ['--resume', sid]
    elif role == 'builder' and has_history:
        # --continue o thu muc chua co phien nao thi Claude thoat (PITFALLS 10c)
        args += ['--continue']
    print(' '.join(args))


def cmd_session_start():
    role = os.environ.get('KZ_ROLE')
    root = os.environ.get('KZ_PROJECT_DIR')
    try:
        hook = json.load(io.TextIOWrapper(sys.stdin.buffer, encoding='utf-8'))
    except Exception:
        return
    if role not in ('builder', 'reviewer') or not root or not hook.get('session_id'):
        return
    root = norm(root)
    update_json(SESSIONS, lambda d: dict(d, **{root: dict(d.get(root, {}), **{role: hook['session_id']})}), {})


# ---------------------------------------------------------------- hook Stop: relay
def git(root, *args):
    rc, out = run(['git', '-C', root] + list(args))
    return out.strip() if rc == 0 else ''


def read_turn(hook):
    """(tin nhan cuoi cua Claude, cau lenh mo dau luot nay)."""
    last = hook.get('last_assistant_message') or ''
    prompt = ''
    tp = hook.get('transcript_path')
    if tp and os.path.isfile(tp):
        with io.open(tp, encoding='utf-8', errors='replace') as f:
            lines = f.readlines()[-600:]
        for line in reversed(lines):
            try:
                e = json.loads(line)
            except Exception:
                continue
            c = (e.get('message') or {}).get('content')
            if not last and e.get('type') == 'assistant' and isinstance(c, list):
                t = '\n'.join(b.get('text', '') for b in c if b.get('type') == 'text')
                if t.strip():
                    last = t
            if e.get('type') == 'user' and not e.get('isMeta'):
                if isinstance(c, str):
                    prompt = c
                    break
                if isinstance(c, list) and not any(b.get('type') == 'tool_result' for b in c):
                    prompt = '\n'.join(b.get('text', '') for b in c if b.get('type') == 'text')
                    break
    return last, prompt


def cmd_relay():
    role = os.environ.get('KZ_ROLE')
    if role not in ('builder', 'reviewer') or os.environ.get('ORCA_REVIEW_RELAY') == '0':
        return
    dry = os.environ.get('ORCA_REVIEW_RELAY_DRYRUN') == '1'
    try:
        hook = json.load(io.TextIOWrapper(sys.stdin.buffer, encoding='utf-8'))
    except Exception:
        hook = {}
    root = norm(os.environ.get('KZ_PROJECT_DIR') or hook.get('cwd') or os.getcwd())

    # Pane doi dien: cung tab, vai tro con lai, dang song (tra so dang ky, khong tra ten)
    other_role = 'reviewer' if role == 'builder' else 'builder'
    tab = os.environ.get('ORCA_TAB_ID', '')
    terms = terminals() or []
    live = {t['handle'] for t in terms}
    other = [h for h, v in load_json(PANES, {}).items()
             if h in live and v.get('role') == other_role and v.get('tab') == tab]
    if not other:
        return
    other = other[0]

    gitdir = git(root, 'rev-parse', '--absolute-git-dir')
    if not gitdir:
        return
    sdir = os.path.join(gitdir, 'orca-review')
    os.makedirs(sdir, exist_ok=True)
    if os.path.exists(os.path.join(sdir, 'off')):
        return
    sfile = os.path.join(sdir, 'state.json')
    state = load_json(sfile, {'fingerprint': '', 'head': '', 'rounds': 0})

    last, prompt = read_turn(hook)
    auto = prompt.lstrip().startswith(MARKER)

    def save():
        if not dry:
            with io.open(sfile, 'w', encoding='utf-8') as f:
                json.dump(state, f)

    def write(name, text):
        if not dry:
            with io.open(os.path.join(sdir, name), 'w', encoding='utf-8') as f:
                f.write(text)

    def send(text):
        if dry:
            print('[thu] %s -> %s: %s' % (role, other_role, text))
            return
        orca('terminal', 'send', '--terminal', other, '--text', text, '--enter')
        log('relay %s -> %s [%s] %s' % (role, other_role, os.path.basename(root), text[:90]))

    if role == 'builder':
        head = git(root, 'rev-parse', 'HEAD')
        status = git(root, 'status', '--porcelain')
        diff = git(root, 'diff', 'HEAD')
        import hashlib
        fp = hashlib.sha256(('%s\n%s\n%s' % (head, status, diff)).encode('utf-8')).hexdigest()
        if fp == state.get('fingerprint'):
            return                                     # khong doi gi tu lan gui truoc
        if not status and (not state.get('head') or head == state.get('head')):
            state.update(fingerprint=fp, head=head)   # cay sach, khong commit moi
            save()
            return
        rounds = int(state.get('rounds', 0)) + 1 if auto else 1
        if rounds > MAX_ROUNDS:
            log('relay builder [%s] da %d vong tu dong - dung' % (os.path.basename(root), MAX_ROUNDS))
            state['fingerprint'] = fp
            save()
            return
        write('builder-last.md', last)
        since = (' va cac commit moi tu %s den HEAD' % state['head'][:8]
                 if state.get('head') and state['head'] != head else '')
        send('%s Vong %d/%d. Builder vua sua code. Tom tat cua builder o file .git/orca-review/builder-last.md. '
             'Hay review cac thay doi chua commit (git status, git diff HEAD)%s theo chi dan reviewer: chi neu loi '
             'that, kem file:dong va kich ban hong. Khong sua code. Dong CUOI CUNG cua tra loi ghi dung mot trong '
             'hai: KET LUAN: OK  hoac  KET LUAN: CON LOI' % (MARKER, rounds, MAX_ROUNDS, since))
        state.update(fingerprint=fp, head=head, rounds=rounds)
        save()
    else:
        m = re.search(r'KET LUAN:\s*(OK|CON LOI)', last)
        if not m:
            return                                     # tra loi cau hoi thuong
        write('review-last.md', last)
        if m.group(1) == 'OK':
            send('%s Reviewer ket luan OK - khong con loi. Chi tiet o file .git/orca-review/review-last.md. '
                 'Khong can sua gi, chi xac nhan mot dong.' % MARKER)
        else:
            send('%s Reviewer bao CON LOI (vong %s/%d). Chi tiet o file .git/orca-review/review-last.md. Doc va '
                 'sua cac loi ban dong y; loi nao khong dong y thi neu ly do. Sua xong khong can goi reviewer - he '
                 'thong tu gui lai.' % (MARKER, state.get('rounds', 0), MAX_ROUNDS))


# ---------------------------------------------------------------- watcher
def runtime_id():
    r = orca('status')
    try:
        rt = r['result']['runtime']
        return rt['runtimeId'] if rt.get('state') == 'ready' else None
    except Exception:
        return None


def cmd_watch():
    log('watcher bat dau (%d project)' % len(projects()))
    # Doi runtime san sang
    rid = None
    while not rid:
        rid = runtime_id()
        if not rid:
            time.sleep(2)
    st = load_json(WATCH_STATE, {})
    if st.get('runtime') != rid:
        # Orca server vua khoi dong lai: PTY cu da chet, tab con lai la vo. Cho ngu het.
        # Watcher tu khoi dong lai voi CUNG runtime thi KHONG cho ngu - khong dong mat
        # project nguoi dung dang mo (bai hoc tu laptop, PITFALLS watcher).
        log('Orca server moi (runtime %s) - cho moi project ngu' % rid)
        for p in projects():
            sleep_project(p['path'], 'server khoi dong lai')
        st = {'runtime': rid}
        update_json(WATCH_STATE, lambda d: st, {})

    offset = os.path.getsize(TRACE) if os.path.exists(TRACE) else 0
    last_seen = {}          # path -> lan cuoi thay git status
    suppressed = set()      # client vua dong tab: khong dung lai trong lan xem nay
    last_view = None
    last_rid_check = time.time()
    paths = {p['path'] for p in projects()}

    while True:
        time.sleep(0.5)
        now = time.time()
        if now - last_rid_check > 15:
            last_rid_check = now
            r = runtime_id()
            if r and r != rid:
                log('runtime doi %s -> %s - khoi dong lai watcher' % (rid, r))
                sys.exit(1)                            # systemd chay lai, nhanh "server moi"
        try:
            size = os.path.getsize(TRACE)
        except OSError:
            continue
        if size < offset:
            offset = 0                                 # file vua xoay vong
        if size == offset:
            continue
        with io.open(TRACE, 'rb') as f:
            f.seek(offset)
            chunk = f.read()
        cut = chunk.rfind(b'\n')
        if cut < 0:
            continue
        offset += cut + 1
        for raw in chunk[:cut].split(b'\n'):
            line = raw.decode('utf-8', 'replace')
            if 'git.exec' in line and '"status"' in line:
                m = re.search(r'"cwd":"([^"]+)"', line)
                if not m:
                    continue
                path = norm(m.group(1))
                if path not in paths:
                    continue
                new_view = now - last_seen.get(path, 0) > VIEW_GAP
                last_seen[path] = now
                if new_view:
                    suppressed.discard(path)
                changed = path != last_view
                last_view = path
                if (new_view or changed) and path not in suppressed:
                    build_layout(path, 'nguoi dung mo')
            elif 'session-tabs.close' in line and '"deviceId"' in line:
                m = re.search(r'"worktree":"id:[^"]*?::([^"]+)"', line)
                if m and norm(m.group(1)) in paths:
                    path = norm(m.group(1))
                    suppressed.add(path)
                    last_view = path
                    sleep_project(path, 'client dong tab')


# ---------------------------------------------------------------- main
def main():
    a = sys.argv[1:]
    if not a:
        print(__doc__)
        return
    cmd = a[0]
    try:
        if cmd == 'watch':
            cmd_watch()
        elif cmd == 'layout':
            build_layout(a[1], 'chay tay')
        elif cmd == 'sleep':
            sleep_project(a[1], 'lenh ngu')
        elif cmd == 'register':
            cmd_register(a[1], a[2])
        elif cmd == 'claude-args':
            cmd_claude_args(a[1], a[2])
        elif cmd == 'session-start':
            cmd_session_start()
        elif cmd == 'relay':
            cmd_relay()
        else:
            print(__doc__)
    except SystemExit:
        raise
    except Exception as e:
        log('LOI %s: %r' % (cmd, e))
        if cmd in ('watch',):
            raise


if __name__ == '__main__':
    main()
