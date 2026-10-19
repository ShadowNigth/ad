#!/usr/bin/env python3
"""Dibuja los rectángulos exportados por tests/tools/hud_layout.tscn."""
import json, sys
from PIL import Image, ImageDraw
d = json.load(open(sys.argv[1] if len(sys.argv) > 1 else "/tmp/hud_layout.json"))
W, H = d["size"]
im = Image.new("RGB", (W, H), (60, 120, 80))
dr = ImageDraw.Draw(im)
colors = {"Button": (255, 230, 150), "TextureButton": (255, 200, 120), "Label": (255, 255, 255), "ProgressBar": (120, 220, 120),
          "TextureRect": (150, 200, 255), "PanelContainer": (200, 160, 110)}
for r in d["rects"]:
    c = colors.get(r["kind"], (180, 180, 180))
    dr.rectangle([r["x"], r["y"], r["x"] + r["w"], r["y"] + r["h"]], outline=c, width=1 if r["kind"] not in ("PanelContainer",) else 2)
    if r["text"] and r["kind"] in ("Label", "Button"):
        dr.text((r["x"] + 2, r["y"] + 1), r["text"][:40], fill=c)
im.save(sys.argv[2] if len(sys.argv) > 2 else "/tmp/hud_layout.png")
print("ok")
