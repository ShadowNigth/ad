"""Run the per-pack gates over every built pack at once -- the driver behind the sweep table.

This is not a gate itself; it is how the two Blender gates are run over a whole `dist/` without
naming a single weapon, which is what makes the "Measured on the whole batch" table in
[`README.md`](README.md) reproducible instead of a transcription of one session's terminal:

    blender -b -P pipeline/qa/sweep_gates.py --            # every pack under dist/
    blender -b -P pipeline/qa/sweep_gates.py -- --out /tmp/dist --contact-fails

For each pack it runs `pose_residual.py` on the longest decoded clip at its middle frame and
`arms_contact.py --min-in 3`, then prints one row per pack plus the grip-fit result recorded in the
manifest.  `pose_residual` is the gate (its exit code decides the row, and `--contact-fails` folds the
contact misses in too); `arms_contact` only reports by default, because "how far are the gloves" is a
distribution worth reading before it is a verdict, and the knife packs legitimately sit further away.

Two things to know before trusting a clean sweep:

* It reads `.blend` files, so it has to run inside headless Blender like the gates it calls (see
  `../headless_blender_stubs.py` for the stub libs).  `--stubs` points `LD_LIBRARY_PATH` at them; when
  `bpy` imports without help, pass `--stubs ""` and the variable is left alone.
* A pack with no decoded animations is *reported*, not failed -- that is the legacy-RLE case
  (`docs/legacy-rle-anim.md`), where the geometry is fine and the clip data is what is missing.
  Counting rows against `ls dist` is how a build with 41 packs and 4 refusals gets misread as 45.
"""
from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
from pathlib import Path

sys.argv[0] = "blender"
HERE = Path(__file__).resolve().parent
ROOT = HERE.parent.parent
# Clips worth checking: a static or 1-frame clip cannot over-determine the bake, and the interesting
# failures (the 178 deg parent-space bug, the sleeve tear) only show up where bones actually move.
PREFERRED = ("reload", "fire", "draw", "lookat", "inspect")


def pick_clip(animations: dict) -> tuple:
    """`(name, frames)` for the clip to check: a moving one with a name that says so, else the longest."""
    best = None
    for name, rec in animations.items():
        if not isinstance(rec, dict):
            continue
        frames = rec.get("frames")
        if not isinstance(frames, int) or frames < 2 or "_empty" in name:
            continue
        low = name.lower()
        score = (any(p in low for p in PREFERRED), frames)
        if best is None or score > best[0]:
            best = (score, name, frames)
    if best is None:
        return None, 0
    return best[1], best[2]


IN_BLENDER = "bpy" in sys.modules          # driven as `blender -b -P sweep_gates.py -- ...`


def run(script: str, args: list, env: dict, timeout: int) -> subprocess.CompletedProcess:
    """Launch a gate the way *this* process was launched.

    Under Blender, `sys.executable` is the blender binary, so the gates have to be re-spawned as
    `blender -b -P gate.py -- args`; spawning them as plain scripts would hand `-u gate.py` to the
    binary and produce an exit code that means nothing.
    """
    cmd = ([sys.executable, "-b", "-P", str(HERE / script), "--", *args] if IN_BLENDER
           else [sys.executable, "-u", str(HERE / script), *args])
    return subprocess.run(cmd, env=env, capture_output=True, text=True, timeout=timeout)


def numbers(text: str, needle: str, pattern: str, verdict: bool = False) -> str:
    """Pull the measured value -- and the gate's own verdict -- out of the line that carries them.

    Matching on a number rather than on the whole sentence is deliberate: the gates' prose has changed
    several times, and a sweep that prints `?` because a sentence was reworded is worse than one that
    keeps reporting the figure.

    The contact verdict has to be read from the *line*, not inferred from the sweep's own PASS column:
    `arms_contact` fails at `--min-in 3` (the gloves never got that close) while the row's last column
    stays PASS, because that column reports whether the sweep treats this gate as binding.  Printing
    the number next to the gate's word is what keeps those two from being confused.
    """
    for line in text.splitlines():
        if needle in line:
            m = re.search(pattern, line)
            val = m.group(1) if m else line.split("] ", 1)[-1].strip()[:44]
            if verdict:
                v = re.search(r"->\s*(PASS|FAIL)", line)
                if v:
                    val += " " + v.group(1)
            return val
    return "?"


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=str(ROOT / "dist"), help="build output root to sweep")
    ap.add_argument("--stubs", default="/tmp/stubs",
                    help="LD_LIBRARY_PATH for the headless-Blender stubs ('' to leave it unset)")
    ap.add_argument("--min-in", type=float, default=3.0, help="arms_contact --min-in")
    ap.add_argument("--contact-fails", action="store_true",
                    help="treat an arms_contact miss as a sweep failure too")
    ap.add_argument("--timeout", type=int, default=900, help="seconds per gate invocation")
    ap.add_argument("--only", default="", help="substring filter on the pack directory name")
    args = ap.parse_args()

    env = dict(os.environ, PYTHONUNBUFFERED="1")
    if args.stubs and Path(args.stubs).is_dir():
        env["LD_LIBRARY_PATH"] = args.stubs
    elif args.stubs:
        print(f"[sweep] note: --stubs {args.stubs} does not exist; relying on bpy importing on its own")

    manifests = sorted(Path(args.out).glob("*/manifest.json"))
    if args.only:
        manifests = [m for m in manifests if args.only in m.parent.name]
    if not manifests:
        print(f"[sweep] no pack manifests under {args.out} -- build something first "
              f"(pipeline/build_pack.py --out {args.out})")
        return 2

    rows, fails = [], []
    for mf in manifests:
        try:
            doc = json.loads(mf.read_text())
        except Exception as e:
            fails.append((mf.parent.name, f"unreadable manifest: {type(e).__name__}: {e}"))
            continue
        build = doc.get("build") or {}
        weapon = doc.get("weapon") or mf.parent.name
        anims = build.get("animations") or {}
        name, frames = pick_clip(anims)
        fit = build.get("arms_grip_fit") or {}
        fit_txt = ("refused" if fit.get("skipped")
                   else f"{fit.get('gap_before')} -> {fit.get('gap_after')} in" if fit else "off")
        blend = mf.parent / Path(str(build.get("blend") or "?")).name
        if not name:
            rows.append((weapon, "-", "no decoded clips (legacy RLE)", fit_txt, "-", "-"))
            continue
        if not blend.is_file():
            fails.append((weapon, f"{blend.name} missing -- the pack was not finished"))
            rows.append((weapon, f"{name} f{max(1, frames // 2)}", "no .blend", fit_txt, "-", "FAIL"))
            continue
        frame = max(1, frames // 2)
        r1 = run("pose_residual.py", ["--blend", str(blend), "--anim", name, "--frame", str(frame)],
                 env, args.timeout)
        residual = numbers(r1.stdout, "worst as-baked", r"([\d.]+ deg / [\d.]+ in)")
        r2 = run("arms_contact.py", ["--blend", str(blend), "--min-in", str(args.min_in)],
                 env, args.timeout)
        contact = numbers(r2.stdout, "closest arms-to-weapon", r"([\d.]+ in)", verdict=True)
        ok = r1.returncode == 0 and (r2.returncode == 0 or not args.contact_fails)
        # `OK`/`FAIL` is the *sweep's* verdict -- whether the gates it treats as binding passed.  The
        # gate's own PASS/FAIL rides in the contact column, and the two legitimately differ: an
        # arms_contact miss is a report unless --contact-fails was asked for.
        rows.append((weapon, f"{name} f{frame}", residual, fit_txt, contact, "OK" if ok else "FAIL"))
        if not ok:
            tail = (r1.stdout + r1.stderr if r1.returncode else r2.stdout + r2.stderr)
            fails.append((weapon, tail[-400:]))

    print(f"\n{'pack':28s} {'clip checked':22s} {'worst as-baked':28s} {'grip fit':24s} "
          f"contact (arms_contact's own verdict)      sweep")
    for r in sorted(rows):
        print(f"{r[0]:28s} {r[1]:22s} {r[2][:28]:28s} {r[3][:24]:24s} {r[4]} {r[5]}")
    misses = [r for r in rows if r[4].endswith("FAIL")]
    print(f"\n[sweep] {len(rows)} pack(s) under {args.out}: {len(fails)} failing "
          f"({sum(1 for r in rows if r[5] == '-')} with nothing to check)")
    if misses:
        print(f"[sweep] arms_contact reported {len(misses)} contact miss(es): "
              + ", ".join(f"{r[0]} {r[4].replace(' FAIL', '')}" for r in misses)
              + ("   <- failing the sweep" if args.contact_fails else "   <- reported only; --contact-fails gates them"))
    for who, detail in fails:
        print(f"  {who}: {detail}")
    if fails:
        print("[sweep] FAIL")
        return 1
    print("[sweep] PASS")
    return 0


if __name__ == "__main__":
    sys.path.insert(0, str(ROOT / "pipeline"))
    try:
        from blender_exit import run_and_exit
        run_and_exit(main)
    except ImportError:                                    # plain python: no os._exit dance needed
        raise SystemExit(main())
