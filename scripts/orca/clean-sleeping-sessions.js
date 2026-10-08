// Xoa cac ban ghi "sleeping agent session" cua cac project duoc quan ly khoi
// kho trang thai cua Orca.
//
// Vi sao can: moi lan dung lai layout, Orca ghi them mot cap ban ghi resume theo
// pane-key moi va giu lai cap cu. Ket qua la duoi moi project hien 4 agent trong
// khi chi co 2 dang chay - hai cai kia tro ve dung hai hoi thoai do, chi la ban
// ghi resume thua.
//
// Chi xoa ban ghi cua cac worktree duoc truyen vao (cac project co trong
// orca-layout.ps1). Worktree khac - vi du herdr-backup, pane nguoi dung ngoi lam
// viec - duoc giu nguyen de no van tu resume duoc.
//
// Phai chay khi Orca DA TAT. Script .ps1 goi file nay da kiem tra dieu do.

const { DatabaseSync } = require("node:sqlite");
const crypto = require("crypto");

const dbPath = process.argv[2];
const BS = String.fromCharCode(92);   // dau gach nguoc, viet kieu nay de khong bi
                                      // bien dang khi file duoc sinh qua shell

const norm = s => String(s).split(BS).join("/").replace(/\/+$/, "").toLowerCase();

const managed = process.argv.slice(3).map(norm);

if (!dbPath || managed.length === 0) {
    console.error("Thieu tham so: <duong-dan-db> <duong-dan-project...>");
    process.exit(2);
}

const db = new DatabaseSync(dbPath);
const row = db.prepare(
    "SELECT domain, payload, revision FROM profile_state_documents WHERE domain = 'workspaceSession'"
).get();

if (!row) {
    console.log("Khong tim thay document workspaceSession - khong lam gi.");
    process.exit(0);
}

const doc = JSON.parse(row.payload);
const sleeping = doc.sleepingAgentSessionsByPaneKey;

if (!sleeping || Object.keys(sleeping).length === 0) {
    console.log("Khong co ban ghi sleeping nao - khong lam gi.");
    process.exit(0);
}

const before = Object.keys(sleeping).length;
const removed = [];

for (const [key, val] of Object.entries(sleeping)) {
    const wt = norm(val.worktreeId || "");
    if (!managed.some(m => wt.endsWith(m))) continue;
    removed.push({ key, proj: String(val.worktreeId || "").split("/").pop() });
    delete sleeping[key];
}

if (removed.length === 0) {
    console.log("Khong co ban ghi nao thuoc cac project duoc quan ly - khong doi gi.");
    process.exit(0);
}

const payload = JSON.stringify(doc);
const hash = crypto.createHash("sha256").update(payload, "utf8").digest("hex");

db.prepare(
    "UPDATE profile_state_documents SET payload = ?, revision = ?, content_hash = ? WHERE domain = 'workspaceSession'"
).run(payload, row.revision + 1, hash);

const byProj = {};
for (const r of removed) byProj[r.proj] = (byProj[r.proj] || 0) + 1;

console.log("Da xoa " + removed.length + "/" + before + " ban ghi sleeping:");
for (const [p, n] of Object.entries(byProj)) console.log("   " + p.padEnd(30) + n);
console.log("Con lai: " + Object.keys(sleeping).length + " ban ghi (cua worktree khong duoc quan ly)");
console.log("revision " + row.revision + " -> " + (row.revision + 1) + ", content_hash da tinh lai");
