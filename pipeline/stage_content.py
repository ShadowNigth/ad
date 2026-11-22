"""Stage a clean Source content root per CS2 addon so the importer can resolve
models/materials/sounds without scanning the whole 3.9 GB dump.

The CS2 packs keep their compiled view/world models under a '#pak' folder (a
Decompiler artifact) while materials + sounds live next to it.  A Source content
root, however, wants 'models/...', 'materials/...', 'sound/...' side by side, so we
build exactly that with hard links (no copies, no duplication of 3.9 GB).

    python3 stage_content.py [--archi /tmp/archi] [--out build/content] [--only ak47]
"""
import argparse, json, os, shutil
from pathlib import Path

PACKS = [
    "CS2GO.Pack.Director.s.Cut.-.Rifles",
    "CS2GO.Pack.Director.s.Cut.-.Pistols",
    "CS2GO.Pack.Director.s.Cut.-.SubMachineGuns",
    "CS2GO.Pack.Director.s.Cut.-.Heavy.Weapons",
    "CS2GO.Pack.Director.s.Cut.-.Equipment",
]
# folders that belong to a Source content root
CONTENT_SUBDIRS = ["models", "materials", "sound", "particles", "scripts", "resource"]


def linktree(src: Path, dst: Path, stats: dict):
    """Mirror src -> dst with hard links (falls back to copy across filesystems)."""
    for p in sorted(src.rglob("*")):
        if p.is_dir():
            continue
        rel = p.relative_to(src)
        out = dst / rel
        out.parent.mkdir(parents=True, exist_ok=True)
        if out.exists() or out.is_symlink():
            stats["skipped"] += 1
            continue
        try:
            os.link(p, out)
            stats["linked"] += 1
        except OSError:
            shutil.copy2(p, out)
            stats["copied"] += 1


def stage_addon(addon_dir: Path, out_root: Path, stats: dict) -> dict | None:
    """Build <out_root>/<addon_name>/{models,materials,sound,...}."""
    name = addon_dir.name
    dst = out_root / name
    if dst.exists():
        shutil.rmtree(dst)
    found = {}
    # a pack keeps content both in '<addon>/<sub>' and '<addon>/#pak/<sub>'
    for base in (addon_dir, addon_dir / "#pak"):
        if not base.is_dir():
            continue
        for sub in CONTENT_SUBDIRS:
            src = base / sub
            if src.is_dir():
                linktree(src, dst / sub, stats)
                found[sub] = found.get(sub, 0) + sum(1 for p in (dst / sub).rglob("*") if p.is_file())
    if "models" not in found:
        shutil.rmtree(dst, ignore_errors=True)
        return None
    # inventory of the interesting files
    inv = {"models": sorted(str(p.relative_to(dst)) for p in dst.rglob("*.mdl")),
           "anims": sorted(str(p.relative_to(dst)) for p in dst.rglob("*.ani")),
           "vmt": sorted(str(p.relative_to(dst)) for p in dst.rglob("*.vmt")),
           "vtf": sorted(str(p.relative_to(dst)) for p in dst.rglob("*.vtf")),
           "wav": sorted(str(p.relative_to(dst)) for p in dst.rglob("*.wav")),
           "pcf": sorted(str(p.relative_to(dst)) for p in dst.rglob("*.pcf")),
           }
    (dst / "stage_manifest.json").write_text(json.dumps({"addon": name, "inventory": inv}, indent=1))
    return {"addon": name, "counts": {k: len(v) for k, v in inv.items()}}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--archi", default="/tmp/archi")
    ap.add_argument("--out", default="build/content")
    ap.add_argument("--only", default=None, help="substring filter on addon folder name")
    a = ap.parse_args()
    archi = Path(a.archi)
    out_root = Path(a.out)
    out_root.mkdir(parents=True, exist_ok=True)
    stats = {"linked": 0, "copied": 0, "skipped": 0}
    report = []
    for pack in PACKS:
        pack_dir = archi / pack
        if not pack_dir.is_dir():
            continue
        for addon in sorted(p for p in pack_dir.rglob("*") if p.is_dir() and p.name.startswith("m_cs2")):
            if a.only and a.only not in addon.name:
                continue
            r = stage_addon(addon, out_root / pack, stats)
            if r:
                r["pack"] = pack
                report.append(r)
    (out_root / "staging_report.json").write_text(json.dumps({"addons": report, "stats": stats}, indent=1))
    print(f"staged {len(report)} addons -> {out_root}")
    print("link stats:", stats)
    for r in report:
        print(f"  {r['addon']:26s} mdl={r['counts']['models']:2d} ani={r['counts']['anims']:2d} "
              f"vmt={r['counts']['vmt']:3d} vtf={r['counts']['vtf']:3d} wav={r['counts']['wav']:3d}")


if __name__ == "__main__":
    main()
