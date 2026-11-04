# Goi 1 RPC cua runtime Orca qua named pipe (giong CLI: 1 dong JSON {id, authToken, method, params}).
import json, os, sys, uuid
meta = json.load(open(os.path.expandvars(r'%APPDATA%\orca\orca-runtime.json')))
pipe = next(t['endpoint'] for t in meta['transports'] if t['kind'] == 'named-pipe')
method = sys.argv[1]
params = json.loads(sys.argv[2]) if len(sys.argv) > 2 else None
f = open(pipe, 'r+b', buffering=0)
f.write((json.dumps({'id': str(uuid.uuid4()), 'authToken': meta['authToken'], 'method': method, 'params': params}) + '\n').encode())
buf = b''
while True:
    ch = f.read(65536)
    if not ch: break
    buf += ch
    while b'\n' in buf:
        line, buf = buf.split(b'\n', 1)
        if not line.strip(): continue
        d = json.loads(line)
        if '_keepalive' in d: continue
        sys.stdout.write(json.dumps(d, ensure_ascii=False)); sys.exit(0)
