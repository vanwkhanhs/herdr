# -*- coding: utf-8 -*-
"""Statusline: ten model + muc dung cua so ngu canh.

Claude Code day mot khoi JSON vao stdin moi lan trang thai doi; script in ra
DUNG MOT DONG, do la dong hien duoi o nhap lieu.

Cac truong dung o day:
  model.display_name
  context_window.{used_percentage, total_input_tokens, total_output_tokens,
                  context_window_size}

Co y KHONG hien rate_limits (han muc 5h/7d) va cost - xem statusline-usage.py
neu muon day du.
"""
import json
import sys

R = "\033[0m"
DIM = "\033[2m"
BAR = DIM + "|" + R


def paint(pct):
    """Xanh khi con thoai mai, vang khi qua nua, do khi sap het."""
    if pct is None:
        return "\033[37m"
    if pct >= 85:
        return "\033[1;31m"
    if pct >= 60:
        return "\033[33m"
    return "\033[32m"


def tokens(n):
    """84213 -> 84k ; 1250000 -> 1.2M"""
    if n is None:
        return "?"
    if n >= 1000000:
        return "%.1fM" % (n / 1000000.0)
    if n >= 1000:
        return "%dk" % (n // 1000)
    return str(n)


def main():
    try:
        data = json.load(sys.stdin)
    except Exception:
        return

    out = []

    name = (data.get("model") or {}).get("display_name")
    if name:
        out.append("\033[1;35m" + name + R)

    ctx = data.get("context_window") or {}
    pct = ctx.get("used_percentage")
    if pct is not None:
        used = (ctx.get("total_input_tokens") or 0) + (ctx.get("total_output_tokens") or 0)
        seg = "%sctx %.0f%%%s" % (paint(pct), pct, R)
        size = ctx.get("context_window_size")
        if size:
            seg += DIM + " " + tokens(used) + "/" + tokens(size) + R
        out.append(seg)

    sys.stdout.write((" " + BAR + " ").join(out))


main()
