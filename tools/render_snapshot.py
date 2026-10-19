#!/usr/bin/env python3
"""Renderiza por software el JSON exportado por tests/tools/snapshot_export.tscn.

Permite revisar sin GPU la escala, orientación y materiales de los modelos
OBJ dentro del mundo real del juego (terreno, vegetación, edificios, jugador).

    python3 tools/render_snapshot.py --yaw 200 --pitch -22 --dist 14 --out /tmp/vista.png
"""
from __future__ import annotations

import argparse
import base64
import json
import math

import numpy as np
from PIL import Image

_TEX: dict = {}


def tex(path: str):
    if not path:
        return None
    if path not in _TEX:
        try:
            _TEX[path] = np.asarray(Image.open(path).convert("RGB"), dtype=np.float32) / 255.0
        except Exception:  # noqa: BLE001
            _TEX[path] = None
    return _TEX[path]


def f32(b64: str, n: int) -> np.ndarray:
    return np.frombuffer(base64.b64decode(b64), dtype=np.float32).reshape(-1, n)


def i32(b64: str) -> np.ndarray:
    return np.frombuffer(base64.b64decode(b64), dtype=np.int32)


def look_at(eye, target):
    f = target - eye
    f /= np.linalg.norm(f)
    up = np.array([0.0, 1.0, 0.0])
    r = np.cross(f, up)
    r /= np.linalg.norm(r)
    u = np.cross(r, f)
    return r, u, f


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--json", default="/tmp/snapshot.json")
    ap.add_argument("--out", default="/tmp/snapshot.png")
    ap.add_argument("--yaw", type=float, default=200.0, help="grados; 0 = la cámara mira hacia -Z (norte)")
    ap.add_argument("--pitch", type=float, default=-22.0)
    ap.add_argument("--dist", type=float, default=12.0)
    ap.add_argument("--fov", type=float, default=65.0)
    ap.add_argument("--width", type=int, default=960)
    ap.add_argument("--height", type=int, default=540)
    ap.add_argument("--sun", type=float, nargs=3, default=[-0.4, 0.8, -0.35])
    ap.add_argument("--center", choices=["player", "focus"], default="player")
    args = ap.parse_args()
    doc = json.load(open(args.json))
    focus = np.array(doc["camera"][args.center], dtype=np.float64) + np.array([0.0, 1.55, 0.0])
    yaw = math.radians(args.yaw)
    pitch = math.radians(args.pitch)
    # Igual que el rig de cámara del juego: la cámara está detrás (+Z local) del foco.
    back = np.array([math.sin(yaw) * math.cos(pitch), -math.sin(pitch), math.cos(yaw) * math.cos(pitch)])
    eye = focus + back * args.dist
    r, u, f = look_at(eye, focus)
    W, H = args.width, args.height
    fl = (H * 0.5) / math.tan(math.radians(args.fov) * 0.5)
    sun = np.array(args.sun, dtype=np.float64)
    sun /= np.linalg.norm(sun)
    color = np.zeros((H, W, 3), dtype=np.float32)
    # cielo degradado
    for y in range(H):
        t = y / H
        color[y, :, :] = np.array([0.45, 0.68, 0.88]) * (1 - t) + np.array([0.78, 0.88, 0.95]) * t
    zbuf = np.full((H, W), np.inf, dtype=np.float32)
    transparent = []
    tri_total = 0
    meshes = doc["meshes"]
    decoded: dict = {}
    for item in doc["items"]:
        mid = item["mesh"]
        if mid not in decoded:
            surfs = []
            for s in meshes[mid]:
                v = f32(s["v"], 3)
                idx = i32(s["i"]) if "i" in s else np.arange(len(v), dtype=np.int32)
                uv = f32(s["uv"], 2) if "uv" in s else None
                col = f32(s["c"], 3) if "c" in s else None
                surfs.append((v, idx.reshape(-1, 3), uv, col, s["info"]))
            decoded[mid] = surfs
        xf = np.array(item["xf"], dtype=np.float64)
        B = np.stack([xf[0:3], xf[3:6], xf[6:9]], axis=1)
        O = xf[9:12]
        for (v, tris, uv, col, info) in decoded[mid]:
            info = item.get("override", info)
            wv = v.astype(np.float64) @ B.T + O
            rel = wv - eye
            cx = rel @ r
            cy = rel @ u
            cz = rel @ f
            sx = W * 0.5 + cx / np.maximum(cz, 1e-3) * fl
            sy = H * 0.5 - cy / np.maximum(cz, 1e-3) * fl
            base_col = np.array(info.get("color", [1, 1, 1, 1])[:3], dtype=np.float32)
            alpha = float(info.get("color", [1, 1, 1, 1])[3]) if info.get("shader") else 1.0
            t_img = tex(info.get("tex", ""))
            for tri in tris:
                a, b, c = tri
                if cz[a] < 0.3 or cz[b] < 0.3 or cz[c] < 0.3:
                    continue
                x0, y0, x1, y1, x2, y2 = sx[a], sy[a], sx[b], sy[b], sx[c], sy[c]
                minx, maxx = int(max(0, math.floor(min(x0, x1, x2)))), int(min(W - 1, math.ceil(max(x0, x1, x2))))
                miny, maxy = int(max(0, math.floor(min(y0, y1, y2)))), int(min(H - 1, math.ceil(max(y0, y1, y2))))
                if minx > maxx or miny > maxy:
                    continue
                den = (y1 - y2) * (x0 - x2) + (x2 - x1) * (y0 - y2)
                if abs(den) < 1e-9:
                    continue
                n = np.cross(wv[b] - wv[a], wv[c] - wv[a])
                nl = np.linalg.norm(n)
                if nl < 1e-12:
                    continue
                n /= nl
                if np.dot(n, eye - wv[a]) < 0:
                    n = -n
                shade = 0.45 + 0.6 * max(0.0, float(np.dot(n, sun)))
                if col is not None and info.get("vcol", False):
                    cc = (col[a] + col[b] + col[c]) / 3.0
                elif t_img is not None and uv is not None:
                    uc = (uv[a] + uv[b] + uv[c]) / 3.0
                    th, tw = t_img.shape[:2]
                    tu = int(np.clip((uc[0] % 1.0) * tw, 0, tw - 1))
                    tv = int(np.clip((uc[1] % 1.0) * th, 0, th - 1))
                    cc = t_img[tv, tu] * base_col
                else:
                    cc = base_col
                rgb = np.clip(cc * shade, 0, 1)
                tri_total += 1
                if alpha < 1.0:
                    transparent.append((minx, maxx, miny, maxy, x0, y0, x1, y1, x2, y2, den, cz[a], cz[b], cz[c], rgb, alpha))
                    continue
                gx, gy = np.meshgrid(np.arange(minx, maxx + 1) + 0.5, np.arange(miny, maxy + 1) + 0.5)
                w0 = ((y1 - y2) * (gx - x2) + (x2 - x1) * (gy - y2)) / den
                w1 = ((y2 - y0) * (gx - x2) + (x0 - x2) * (gy - y2)) / den
                w2 = 1 - w0 - w1
                inside = (w0 >= -1e-4) & (w1 >= -1e-4) & (w2 >= -1e-4)
                if not inside.any():
                    continue
                z = 1.0 / (w0 / cz[a] + w1 / cz[b] + w2 / cz[c])
                sub = zbuf[miny:maxy + 1, minx:maxx + 1]
                vis = inside & (z < sub)
                if vis.any():
                    sub[vis] = z[vis]
                    color[miny:maxy + 1, minx:maxx + 1][vis] = rgb
    for (minx, maxx, miny, maxy, x0, y0, x1, y1, x2, y2, den, za, zb, zc, rgb, alpha) in transparent:
        gx, gy = np.meshgrid(np.arange(minx, maxx + 1) + 0.5, np.arange(miny, maxy + 1) + 0.5)
        w0 = ((y1 - y2) * (gx - x2) + (x2 - x1) * (gy - y2)) / den
        w1 = ((y2 - y0) * (gx - x2) + (x0 - x2) * (gy - y2)) / den
        w2 = 1 - w0 - w1
        inside = (w0 >= -1e-4) & (w1 >= -1e-4) & (w2 >= -1e-4)
        z = 1.0 / (w0 / za + w1 / zb + w2 / zc)
        sub = zbuf[miny:maxy + 1, minx:maxx + 1]
        vis = inside & (z < sub)
        if vis.any():
            blk = color[miny:maxy + 1, minx:maxx + 1]
            blk[vis] = blk[vis] * (1 - alpha) + rgb * alpha
    # niebla suave por distancia
    fog = np.clip((zbuf - 40.0) / 120.0, 0, 0.6)[..., None]
    fog[np.isinf(zbuf)] = 0
    color = color * (1 - fog) + np.array([0.75, 0.85, 0.93]) * fog
    Image.fromarray((np.clip(color, 0, 1) * 255).astype(np.uint8)).save(args.out)
    print(f"{tri_total} triángulos -> {args.out}")


if __name__ == "__main__":
    main()
