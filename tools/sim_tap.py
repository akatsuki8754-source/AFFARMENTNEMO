#!/usr/bin/env python3
"""
Simulator window 内の指定座標 (window-relative) にマウスクリックを送る。
"""
import subprocess
import sys
import time

try:
    import Quartz
except ImportError:
    print("pyobjc-framework-Quartz が必要: pip3 install pyobjc-framework-Quartz")
    sys.exit(1)


def get_sim_window():
    """Simulator window の (x, y, w, h) を返す"""
    out = subprocess.check_output([
        "osascript", "-e",
        'tell application "System Events" to tell process "Simulator" to '
        'return position of window 1 & size of window 1'
    ]).decode().strip()
    parts = [int(x.strip()) for x in out.split(",")]
    return parts[0], parts[1], parts[2], parts[3]


def click_at(abs_x, abs_y):
    pos = (abs_x, abs_y)
    # まずマウスを移動 (一部アプリが必要とする)
    move = Quartz.CGEventCreateMouseEvent(None, Quartz.kCGEventMouseMoved, pos, Quartz.kCGMouseButtonLeft)
    Quartz.CGEventPost(Quartz.kCGHIDEventTap, move)
    time.sleep(0.1)
    down = Quartz.CGEventCreateMouseEvent(None, Quartz.kCGEventLeftMouseDown, pos, Quartz.kCGMouseButtonLeft)
    up = Quartz.CGEventCreateMouseEvent(None, Quartz.kCGEventLeftMouseUp, pos, Quartz.kCGMouseButtonLeft)
    Quartz.CGEventPost(Quartz.kCGHIDEventTap, down)
    time.sleep(0.15)  # 押下時間を長く
    Quartz.CGEventPost(Quartz.kCGHIDEventTap, up)
    time.sleep(0.05)


def tap(rel_x_pct, rel_y_pct):
    """window 内の相対座標 (0-1) でタップ"""
    wx, wy, ww, wh = get_sim_window()
    title_bar = 28
    abs_x = wx + int(ww * rel_x_pct)
    abs_y = wy + title_bar + int((wh - title_bar) * rel_y_pct)
    click_at(abs_x, abs_y)
    print(f"tapped at ({abs_x}, {abs_y})  rel=({rel_x_pct:.2f}, {rel_y_pct:.2f})")


if __name__ == "__main__":
    if len(sys.argv) >= 3:
        x_pct = float(sys.argv[1])
        y_pct = float(sys.argv[2])
        tap(x_pct, y_pct)
    else:
        print("Usage: sim_tap.py <x_pct 0-1> <y_pct 0-1>")
