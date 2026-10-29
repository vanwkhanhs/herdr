#!/bin/sh
# Ubuntu 18.04 co glibc 2.27, ma pty.node chinh cua Orca doi GLIBC_2.28 -> khong mo
# duoc terminal nao ("Failed to load native module: pty.node"). Orca co dong goi san
# ban glibc217 (cho orcad) - dat no vao build/orca-napi-linux-x64/, cho node-pty tim
# DAU TIEN. Khong ghi de file goc. Chay lai moi lan service khoi dong vi cap nhat Orca
# (giai nen lai app/) se xoa mat.
R="$HOME/.local/opt/orca/app/resources"
SRC="$R/orcad-template/targets/linux-x64-glibc217/node_modules/node-pty/build/Release/pty.node"
DST="$R/node_modules/node-pty/build/orca-napi-linux-x64"
[ -f "$SRC" ] || { echo "fix-glibc227: khong thay ban glibc217 - bo qua"; exit 0; }
if ! cmp -s "$SRC" "$DST/pty.node" 2>/dev/null; then
  mkdir -p "$DST" && cp "$SRC" "$DST/pty.node" && echo "fix-glibc227: da dat pty.node ban glibc217"
fi
