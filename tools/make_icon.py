"""Draws the StreamBridge icon with the standard library only (no packages).

Writes assets/icon/icon.png (full) and assets/icon/icon_fg.png (transparent,
for the Android adaptive icon). Idea: two pillars with three stream waves
between them, like a bridge over flowing water.
"""
import math
import os
import struct
import zlib

N = 512
SS = 2  # supersampling per axis


def seg_dist(px, py, ax, ay, bx, by):
    vx, vy = bx - ax, by - ay
    t = ((px - ax) * vx + (py - ay) * vy) / (vx * vx + vy * vy)
    t = max(0.0, min(1.0, t))
    dx, dy = px - (ax + t * vx), py - (ay + t * vy)
    return math.hypot(dx, dy)


def arc_dist(px, py, cx, cy, r, a0, a1):
    dx, dy = px - cx, py - cy
    ang = math.atan2(dy, dx)
    if a0 <= ang <= a1:
        return abs(math.hypot(dx, dy) - r)
    e0 = (cx + r * math.cos(a0), cy + r * math.sin(a0))
    e1 = (cx + r * math.cos(a1), cy + r * math.sin(a1))
    return min(math.hypot(px - e0[0], py - e0[1]), math.hypot(px - e1[0], py - e1[1]))


def mix(c0, c1, t):
    return tuple(c0[i] + (c1[i] - c0[i]) * t for i in range(3))


def build(scale, with_bg):
    """scale: how much of the canvas the artwork uses (1 = full)."""
    s = N * scale
    o = (N - s) / 2
    f = lambda v: o + v * s
    w = 0.07 * s
    pillars = [
        (f(0.20), f(0.22), f(0.20), f(0.78)),
        (f(0.80), f(0.22), f(0.80), f(0.78)),
    ]
    arcs = []
    for k, r in enumerate((0.13, 0.22, 0.31)):
        arcs.append((f(0.30), f(0.50), r * s, -1.05, 1.05))
    blue0, blue1 = (45, 107, 255), (34, 211, 238)
    bg0, bg1 = (11, 11, 18), (22, 24, 48)
    rows = []
    for y in range(N):
        row = bytearray()
        for x in range(N):
            acc = [0.0, 0.0, 0.0, 0.0]
            for sy in range(SS):
                for sx in range(SS):
                    px = x + (sx + 0.5) / SS
                    py = y + (sy + 0.5) / SS
                    r_, g_, b_, a_ = 0.0, 0.0, 0.0, 0.0
                    if with_bg:
                        m = 0.18 * N
                        qx = abs(px - N / 2) - (N / 2 - m)
                        qy = abs(py - N / 2) - (N / 2 - m)
                        d = math.hypot(max(qx, 0), max(qy, 0)) + min(max(qx, qy), 0) - m
                        if d <= 0:
                            c = mix(bg0, bg1, py / N)
                            r_, g_, b_, a_ = c[0], c[1], c[2], 1.0
                    dmin = 1e9
                    for (ax, ay, bx, by) in pillars:
                        dmin = min(dmin, seg_dist(px, py, ax, ay, bx, by))
                    for (cx, cy, rr, a0, a1) in arcs:
                        dmin = min(dmin, arc_dist(px, py, cx, cy, rr, a0, a1))
                    if dmin <= w / 2:
                        c = mix(blue0, blue1, (px - o) / s)
                        r_, g_, b_, a_ = c[0], c[1], c[2], 1.0
                    acc[0] += r_ * a_
                    acc[1] += g_ * a_
                    acc[2] += b_ * a_
                    acc[3] += a_
            n = SS * SS
            a = acc[3] / n
            if a > 0:
                row += bytes((int(acc[0] / acc[3]), int(acc[1] / acc[3]), int(acc[2] / acc[3]), int(a * 255)))
            else:
                row += bytes((0, 0, 0, 0))
        rows.append(bytes(row))
    return rows


def write_png(path, rows):
    raw = b''.join(b'\x00' + r for r in rows)

    def chunk(tag, data):
        c = struct.pack('>I', len(data)) + tag + data
        return c + struct.pack('>I', zlib.crc32(tag + data) & 0xFFFFFFFF)

    png = b'\x89PNG\r\n\x1a\n'
    png += chunk(b'IHDR', struct.pack('>IIBBBBB', N, N, 8, 6, 0, 0, 0))
    png += chunk(b'IDAT', zlib.compress(raw, 9))
    png += chunk(b'IEND', b'')
    with open(path, 'wb') as fh:
        fh.write(png)


if __name__ == '__main__':
    out = os.path.join('assets', 'icon')
    os.makedirs(out, exist_ok=True)
    write_png(os.path.join(out, 'icon.png'), build(0.78, True))
    write_png(os.path.join(out, 'icon_fg.png'), build(0.56, False))
    print('icons written to', out)
