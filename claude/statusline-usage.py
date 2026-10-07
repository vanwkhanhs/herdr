# -*- coding: utf-8 -*-
"""Status line cho Claude Code: hien thong so su dung (usage).

Claude Code do mot khoi JSON vao stdin moi khi trang thai doi. Script in ra
DUNG MOT DONG, do la dong hien duoi o nhap lieu.

Cac truong dung o day (xac nhan tu ban 2.1.290):
  model.display_name
  context_window.{used_percentage, total_input_tokens, total_output_tokens,
                  context_window_size}
  rate_limits.five_hour.{used_percentage, resets_at}     <- han muc 5 gio
  rate_limits.seven_day.{used_percentage, resets_at}     <- han muc 7 ngay
  cost.total_cost_usd                                     <- tien phien nay

rate_limits CHI co khi tai khoan dung han muc theo cua so thoi gian
(Pro/Max). Tai khoan tra theo API thi khong co, nen moi muc deu phai
kiem tra truoc khi dung.
"""
import json
import sys
import time

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


def reset_at(epoch):
    """Doi moc epoch (giay) thanh gio dia phuong, vd 14:20."""
    try:
        return time.strftime("%H:%M", time.localtime(float(epoch)))
    except Exception:
        return None


def window(data, key, label, out):
    """Mot han muc (5h hoac 7d). Bo qua neu tai khoan khong co han muc do."""
    w = (data.get("rate_limits") or {}).get(key)
    if not isinstance(w, dict):
        return
    pct = w.get("used_percentage")
    if pct is None:
        return
    seg = "%s%s %.0f%%%s" % (paint(pct), label, pct, R)
    t = reset_at(w.get("resets_at"))
    if t:
        seg += DIM + "->" + t + R
    out.append(seg)


def main():
    try:
        data = json.load(sys.stdin)
    except Exception:
        return

    out = []

    # --- Model ---
    name = (data.get("model") or {}).get("display_name")
    if name:
        out.append("\033[1;35m" + name + R)

    # --- Cua so ngu canh: phan tram va so token da nap ---
    ctx = data.get("context_window") or {}
    pct = ctx.get("used_percentage")
    if pct is not None:
        used = (ctx.get("total_input_tokens") or 0) + (ctx.get("total_output_tokens") or 0)
        seg = "%sctx %.0f%%%s" % (paint(pct), pct, R)
        size = ctx.get("context_window_size")
        if size:
            seg += DIM + " " + tokens(used) + "/" + tokens(size) + R
        out.append(seg)

    # --- Han muc su dung theo cua so thoi gian ---
    window(data, "five_hour", "5h", out)
    window(data, "seven_day", "7d", out)

    # --- Chi phi phien hien tai ---
    usd = (data.get("cost") or {}).get("total_cost_usd")
    if isinstance(usd, (int, float)) and usd > 0:
        out.append("\033[36m$%.2f%s" % (usd, R))

    sys.stdout.write((" " + BAR + " ").join(out))


main()
