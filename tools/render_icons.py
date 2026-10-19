#!/usr/bin/env python3
"""Rasterizador por software (numpy + Pillow) para los modelos OBJ del juego.

Usos:
  * Genera los iconos de objetos del inventario (assets/icons/items/*.png) a partir
    de los propios modelos OBJ/MTL/texturas (derivados CC0 de los packs de Kenney).
  * Genera vistas previas para revisar escala y orientación de los modelos sin GPU:
        python3 tools/render_icons.py --preview nature/tree_palmTall characters/character-male-a

Las definiciones de icono (modelo, tinte, ángulo) se leen de data/items/items.json
(campo "icon_model" / "icon_tint" / "icon_yaw").
"""
from __future__ import annotations

import argparse
import json
import math
import os

import numpy as np
from PIL import Image, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MODELS = os.path.join(ROOT, "assets", "models")


# Misma paleta tropical que scripts/core/model_library.gd (Nature Kit sin textura).
PALETTE = {
    "grass": (0.38, 0.72, 0.30),
    "leafsGreen": (0.27, 0.64, 0.27),
    "leafsDark": (0.17, 0.46, 0.25),
    "stone": (0.68, 0.68, 0.66),
    "stoneDark": (0.54, 0.54, 0.53),
}


def load_mtl(path: str) -> dict:
    mats: dict = {}
    cur = None
    if not os.path.exists(path):
        return mats
    for line in open(path, encoding="utf-8", errors="ignore"):
        p = line.strip().split()
        if not p:
            continue
        if p[0] == "newmtl":
            cur = p[1]
            mats[cur] = {"kd": (1.0, 1.0, 1.0), "tex": None}
        elif cur and p[0] == "Kd":
            mats[cur]["kd"] = PALETTE.get(cur, tuple(float(v) for v in p[1:4]))
        elif cur and p[0] == "map_Kd":
            tex_path = os.path.join(os.path.dirname(path), " ".join(p[1:]))
            if os.path.exists(tex_path):
                mats[cur]["tex"] = np.asarray(Image.open(tex_path).convert("RGBA"), dtype=np.float32) / 255.0
    return mats


def load_obj(path: str):
    vs, vts = [], []
    tris = []  # (i0,i1,i2), (t0,t1,t2), mat
    mats = {}
    mat = None
    for line in open(path, encoding="utf-8", errors="ignore"):
        if line.startswith("v "):
            vs.append([float(v) for v in line.split()[1:4]])
        elif line.startswith("vt "):
            vts.append([float(v) for v in line.split()[1:3]])
        elif line.startswith("usemtl"):
            mat = line.split()[1]
        elif line.startswith("mtllib"):
            mats = load_mtl(os.path.join(os.path.dirname(path), line.split(None, 1)[1].strip()))
        elif line.startswith("f "):
            idx = []
            for tok in line.split()[1:]:
                parts = tok.split("/")
                vi = int(parts[0]) - 1
                ti = int(parts[1]) - 1 if len(parts) > 1 and parts[1] else -1
                idx.append((vi, ti))
            for k in range(1, len(idx) - 1):
                tris.append((idx[0], idx[k], idx[k + 1], mat))
    return np.array(vs, dtype=np.float32), np.array(vts or [[0, 0]], dtype=np.float32), tris, mats


def rot_y(a: float) -> np.ndarray:
    c, s = math.cos(a), math.sin(a)
    return np.array([[c, 0, s], [0, 1, 0], [-s, 0, c]], dtype=np.float32)


def rot_x(a: float) -> np.ndarray:
    c, s = math.cos(a), math.sin(a)
    return np.array([[1, 0, 0], [0, c, -s], [0, s, c]], dtype=np.float32)


def rot_z(a: float) -> np.ndarray:
    c, s = math.cos(a), math.sin(a)
    return np.array([[c, -s, 0], [s, c, 0], [0, 0, 1]], dtype=np.float32)


_OBJ_CACHE: dict = {}


def _load_cached(model: str):
    if model not in _OBJ_CACHE:
        _OBJ_CACHE[model] = load_obj(os.path.join(MODELS, model + ".obj"))
    return _OBJ_CACHE[model]


def load_parts(parts: list):
    """Combina piezas {model, scale, pos, rot} como hace ModelLibrary.merged()."""
    all_v, all_vt, all_tris, all_mats = [], [], [], {}
    voff = 0
    toff = 0
    for k, part in enumerate(parts):
        vs, vts, tris, mats = _load_cached(part["model"])
        sc = float(part.get("scale", 1.0))
        th = math.radians(float(part.get("rot", 0.0)))
        c, s_ = math.cos(th), math.sin(th)
        pos = np.array(part.get("pos", [0, 0, 0]), dtype=np.float32)
        v = vs * sc
        x = v[:, 0] * c + v[:, 2] * s_
        z = -v[:, 0] * s_ + v[:, 2] * c
        v = np.stack([x, v[:, 1], z], axis=1) + pos
        all_v.append(v)
        all_vt.append(vts)
        for name, m in mats.items():
            all_mats[f"{k}:{name}"] = m
        for (a, b, cc, mname) in tris:
            all_tris.append(((a[0] + voff, a[1] + toff if a[1] >= 0 else -1), (b[0] + voff, b[1] + toff if b[1] >= 0 else -1),
                             (cc[0] + voff, cc[1] + toff if cc[1] >= 0 else -1), f"{k}:{mname}"))
        voff += len(vs)
        toff += len(vts)
    return np.concatenate(all_v), np.concatenate(all_vt), all_tris, all_mats


def render(model, size: int = 128, yaw: float = 35.0, pitch: float = 28.0, tint=(1, 1, 1),
           supersample: int = 3, outline: bool = True, margin: float = 0.1, roll: float = 0.0,
           whiten: float = 0.0) -> Image.Image:
    if isinstance(model, list):
        vs, vts, tris, mats = load_parts(model)
    else:
        vs, vts, tris, mats = _load_cached(model)
    # Cámara: rotar el modelo (yaw) y luego inclinar (pitch). Vista ortográfica.
    r = rot_z(math.radians(roll)) @ rot_x(math.radians(pitch)) @ rot_y(math.radians(yaw))
    pv = vs @ r.T
    S = size * supersample
    lo, hi = pv.min(axis=0), pv.max(axis=0)
    span = max(hi[0] - lo[0], hi[1] - lo[1]) or 1.0
    scale = S * (1 - 2 * margin) / span
    cx, cy = (lo[0] + hi[0]) / 2, (lo[1] + hi[1]) / 2
    sx = (pv[:, 0] - cx) * scale + S / 2
    sy = S / 2 - (pv[:, 1] - cy) * scale
    sz = pv[:, 2]
    color = np.zeros((S, S, 3), dtype=np.float32)
    alpha = np.zeros((S, S), dtype=np.float32)
    zbuf = np.full((S, S), -1e9, dtype=np.float32)
    light = np.array([0.45, 0.8, 0.55], dtype=np.float32)
    light /= np.linalg.norm(light)
    light = light @ r.T if False else light
    tint = np.array(tint, dtype=np.float32)
    for (a, b, c, mname) in tris:
        ia, ib, ic = a[0], b[0], c[0]
        x0, y0, x1, y1, x2, y2 = sx[ia], sy[ia], sx[ib], sy[ib], sx[ic], sy[ic]
        den = (y1 - y2) * (x0 - x2) + (x2 - x1) * (y0 - y2)
        if abs(den) < 1e-9:
            continue
        # Normal de cara en espacio de vista (para sombreado plano).
        n = np.cross(pv[ib] - pv[ia], pv[ic] - pv[ia])
        nl = np.linalg.norm(n)
        if nl < 1e-12:
            continue
        n /= nl
        if n[2] < 0:  # cara trasera (z hacia la cámara positivo)
            n = -n
        shade = 0.42 + 0.58 * max(0.0, float(n @ light))
        minx, maxx = int(max(0, math.floor(min(x0, x1, x2)))), int(min(S - 1, math.ceil(max(x0, x1, x2))))
        miny, maxy = int(max(0, math.floor(min(y0, y1, y2)))), int(min(S - 1, math.ceil(max(y0, y1, y2))))
        if minx > maxx or miny > maxy:
            continue
        gx, gy = np.meshgrid(np.arange(minx, maxx + 1) + 0.5, np.arange(miny, maxy + 1) + 0.5)
        w0 = ((y1 - y2) * (gx - x2) + (x2 - x1) * (gy - y2)) / den
        w1 = ((y2 - y0) * (gx - x2) + (x0 - x2) * (gy - y2)) / den
        w2 = 1 - w0 - w1
        inside = (w0 >= -1e-4) & (w1 >= -1e-4) & (w2 >= -1e-4)
        if not inside.any():
            continue
        z = w0 * sz[ia] + w1 * sz[ib] + w2 * sz[ic]
        sub_z = zbuf[miny:maxy + 1, minx:maxx + 1]
        vis = inside & (z > sub_z)
        if not vis.any():
            continue
        m = mats.get(mname, {"kd": (0.8, 0.8, 0.8), "tex": None})
        if m["tex"] is not None and a[1] >= 0:
            uv = (w0[..., None] * vts[a[1]] + w1[..., None] * vts[b[1]] + w2[..., None] * vts[c[1]])
            tex = m["tex"]
            th, tw = tex.shape[:2]
            u = np.clip((uv[..., 0] % 1.0) * tw, 0, tw - 1).astype(int)
            v = np.clip((1 - (uv[..., 1] % 1.0)) * th, 0, th - 1).astype(int)
            base = tex[v, u, :3] * np.array(m["kd"], dtype=np.float32)
        else:
            base = np.broadcast_to(np.array(m["kd"], dtype=np.float32), gx.shape + (3,))
        if whiten > 0:
            base = base * (1 - whiten) + whiten
        col = np.clip(base * tint * shade, 0, 1)
        sub_c = color[miny:maxy + 1, minx:maxx + 1]
        sub_c[vis] = col[vis]
        sub_z[vis] = z[vis]
        alpha[miny:maxy + 1, minx:maxx + 1][vis] = 1.0
    img = np.dstack([color, alpha])
    im = Image.fromarray((img * 255).astype(np.uint8), "RGBA").resize((size, size), Image.LANCZOS)
    if outline:
        a = im.split()[3]
        grown = a.filter(ImageFilter.MaxFilter(5))
        bg = Image.new("RGBA", im.size, (24, 18, 12, 0))
        bg.putalpha(grown.point(lambda v: 200 if v > 40 else 0))
        bg.alpha_composite(im)
        im = bg
    return im


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--preview", nargs="*", help="modelos a previsualizar (carpeta/nombre)")
    ap.add_argument("--yaw", type=float, default=35.0)
    ap.add_argument("--pitch", type=float, default=28.0)
    ap.add_argument("--out", default="/tmp/previews")
    ap.add_argument("--buildings", action="store_true", help="genera miniaturas de edificios")
    args = ap.parse_args()
    if args.buildings:
        data = json.load(open(os.path.join(ROOT, "data", "buildings", "buildings.json"), encoding="utf-8"))["buildings"]
        out_dir = os.path.join(ROOT, "assets", "icons", "buildings")
        os.makedirs(out_dir, exist_ok=True)
        for b in data:
            levels = b["levels"]
            parts = levels[-1]["models"] if b["id"] in ("refugio",) else levels[0]["models"]
            parts = list(parts)
            if "spinner" in levels[0]:
                parts.append(levels[0]["spinner"])
            im = render(parts, 192, 35.0, 30.0, outline=True, margin=0.06)
            im.save(os.path.join(out_dir, b["id"] + ".png"), optimize=True)
        print(f"{len(data)} miniaturas en {out_dir}")
        return
    if args.preview:
        os.makedirs(args.out, exist_ok=True)
        for m in args.preview:
            im = render(m, 256, args.yaw, args.pitch, outline=False)
            dst = os.path.join(args.out, m.replace("/", "__") + ".png")
            im.save(dst)
            print(dst)
        return
    items = json.load(open(os.path.join(ROOT, "data", "items", "items.json"), encoding="utf-8"))["items"]
    out_dir = os.path.join(ROOT, "assets", "icons", "items")
    os.makedirs(out_dir, exist_ok=True)
    for it in items:
        model = it.get("icon_model")
        if not model:
            continue
        im = render(model, 128, it.get("icon_yaw", 35.0), it.get("icon_pitch", 28.0), tuple(it.get("icon_tint", (1, 1, 1))),
                    roll=it.get("icon_roll", 0.0), whiten=it.get("icon_whiten", 0.0))
        im.save(os.path.join(out_dir, it["id"] + ".png"), optimize=True)
    print(f"{len(items)} iconos generados en {out_dir}")


if __name__ == "__main__":
    main()
