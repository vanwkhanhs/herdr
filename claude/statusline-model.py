"""Statusline toi gian: chi in ten model dang dung.

Claude Code day mot khoi JSON vao stdin moi lan cap nhat statusline;
truong can lay la model.display_name. In ra stdout la noi dung hien thi.
"""
import json
import sys

try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(0)

name = (data.get("model") or {}).get("display_name")
if name:
    print(name)
