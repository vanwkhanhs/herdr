// In ra duong dan worktree ma nguoi dung DANG MO tren giao dien Orca.
//
// Vi sao can: watcher phai phan biet "nguoi dung bam vao project" voi "Orca tu
// khoi phuc tab cu". Nhin vao terminal thi khong phan biet duoc - ca hai deu chi
// la terminal xuat hien trong worktree. Da thu phan biet bang thoi gian va bang
// so pane, deu sai: project tu bat len du khong ai bam.
//
// Bam vao project o sidebar thi Orca doi activeWorktreeId; tu khoi phuc tab thi
// khong. Do la tin hieu dung.
//
// CLI khong doc duoc cai nay: 'orca worktree show --worktree active' phan giai
// theo THU MUC HIEN TAI chu khong theo focus tren UI. Nen phai doc kho trang thai.
//
// Kho that la profiles/local-default/profile-state.db (SQLite). Du lieu nam trong
// WAL nen phai chep ca .db + -wal + -shm ra cho tam roi moi doc. File
// orca-data.json la ban xuat va dung yen hang chuc phut - dung doc no.

const { DatabaseSync } = require("node:sqlite");
const fs = require("fs");
const path = require("path");
const os = require("os");

const src = path.join(process.env.APPDATA, "orca", "profiles", "local-default", "profile-state.db");
if (!fs.existsSync(src)) process.exit(0);

let tmp;
try {
    tmp = fs.mkdtempSync(path.join(os.tmpdir(), "orca-active-"));
    for (const ext of ["", "-wal", "-shm"]) {
        try { fs.copyFileSync(src + ext, path.join(tmp, "db" + ext)); } catch { }
    }

    const db = new DatabaseSync(path.join(tmp, "db"));
    const row = db.prepare("SELECT payload FROM profile_state_documents WHERE domain='workspaceSession'").get();
    db.close();
    if (!row) process.exit(0);

    const id = JSON.parse(row.payload).activeWorktreeId;
    if (!id) process.exit(0);

    // worktreeId co dang "<repoId>::<duong dan>" - lay phan duong dan
    const i = id.indexOf("::");
    process.stdout.write(i >= 0 ? id.slice(i + 2) : id);
} catch {
    // Doc khong duoc thi im lang - watcher se coi nhu khong xac dinh duoc
    // va khong dung gi, an toan hon la doan bua.
} finally {
    if (tmp) { try { fs.rmSync(tmp, { recursive: true, force: true }); } catch { } }
}
