"""Exit a Blender-spawning script without hanging in Blender's at-exit machinery.

A script that has initialised Blender's window manager and then hits `raise SystemExit` prints
`Error: Not freed memory blocks: ...` followed by an endless stream of
`Freeing memory after the leak detector has run.` and *never returns* -- so a mistyped `--only`
pattern, which should be a one-line error, became a 15-minute timeout.  This is the same machinery
that makes every success path in these scripts end in `os._exit()` (Blender 4.5's at-exit handlers
abort under the headless stub libs); it just was not applied to the failure paths.

`run_and_exit` gives both one behaviour: message to the right stream, flush, hard exit, non-zero on
error.
"""
from __future__ import annotations

import os
import sys
import traceback


def run_and_exit(main_fn):
    code = 0
    try:
        code = main_fn() or 0
    except SystemExit as e:                         # the scripts' own `raise SystemExit("why")`
        if isinstance(e.code, str):
            print(e.code, file=sys.stderr)
            code = 1
        elif isinstance(e.code, int):
            code = e.code
        else:
            code = 0 if e.code is None else 1
    except BaseException:                           # noqa: BLE001 - a traceback beats a silent hang
        traceback.print_exc()
        code = 1
    for s in (sys.stdout, sys.stderr):
        try:
            s.flush()
        except Exception:                           # noqa: BLE001 - already dying
            pass
    os._exit(int(code))
