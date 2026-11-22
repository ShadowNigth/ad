"""Headless-bpy enabler.

The bpy (Blender-as-a-python-module) wheel links against X11/GL libraries that are
absent from this sandbox image. Blender in background (-b) mode never calls into
them, so we synthesize no-op shared objects that only have to satisfy the dynamic
loader: right soname, right exported symbol names and, where a consumer demands
them, the right symbol-version nodes.

    python3 build_stubs.py            ->  /tmp/stubs/*.so
    LD_LIBRARY_PATH=/tmp/stubs python -c "import bpy"
"""
import subprocess, re, pathlib, collections

SP = "/tmp/venv/lib/python3.11/site-packages"
STUB = pathlib.Path("/tmp/stubs")
GEN = pathlib.Path("/tmp/gen")
STUB.mkdir(parents=True, exist_ok=True)
GEN.mkdir(parents=True, exist_ok=True)

REAL_DIRS = [pathlib.Path(d) for d in ("/usr/lib/x86_64-linux-gnu", "/lib/x86_64-linux-gnu", "/usr/lib")]
REAL_DIRS += [pathlib.Path(f"{SP}/bpy/lib"), pathlib.Path(f"{SP}/bpy")]
present = lambda n: any((d / n).exists() for d in REAL_DIRS)

# Candidate libraries that may be missing, and the symbol families they own.
PREFIX = {
    "libXrender.so.1":   ("XRender",),
    "libXi.so.6":        ("_Xi", "Xi", "XGetExtensionVersion", "XListInputDevices", "XOpenDevice", "XCloseDevice",
                          "XFreeDevice", "XSelectExtensionEvent", "XQueryDeviceState"),
    "libXfixes.so.3":    ("XFixes",),
    "libXt.so.6":        ("Xt",),
    "libSM.so.6":        ("Sm",),
    "libICE.so.6":       ("Ice",),
    "libxkbcommon.so.0": ("xkb", "_evdev"),
    "libGL.so.1":        ("glX", "gl"),
    "libGLX.so.0":       ("glX",),
    "libOpenGL.so.0":    ("OpenGL", "glOpenGL"),
    "libEGL.so.1":       ("egl",),
    "libXxf86vm.so.1":   ("XF86VidMode",),
    "libXcursor.so.1":   ("Xcursor",),
    "libXinerama.so.1":  ("Xinerama",),
    "libXrandr.so.2":    ("XRR",),
    "libcuda.so.1":      ("cu",),
    "libze_loader.so.1": ("ze",),
    "libamdhip64.so.6":  ("hip",),
    "libXfixes.so":      (),
}

OBJS = []
for d in (f"{SP}/bpy/lib", f"{SP}/bpy"):
    p = pathlib.Path(d)
    if p.exists():
        OBJS += [f for f in sorted(p.iterdir()) if ".so" in f.name and f.is_file()]

NEEDED = set()
for c in OBJS:
    out = subprocess.run(["readelf", "-d", str(c)], capture_output=True, text=True).stdout
    NEEDED |= set(re.findall(r"Shared library: \[([^\]]+)\]", out))

missing = sorted(n for n in (NEEDED | set(PREFIX))
                 if ".so" in n and not present(n) and not n.startswith(("libpython", "ld-linux")))

file2vers = collections.defaultdict(set)   # soname -> version names demanded
ver2file = collections.defaultdict(set)    # version name -> sonames
for c in OBJS:
    out = subprocess.run(["readelf", "-W", "-V", str(c)], capture_output=True, text=True).stdout
    if "Version needs section" not in out:
        continue
    cur = None
    for line in out.split("Version needs section", 1)[1].splitlines():
        m = re.search(r"File: +(\S+)", line)
        if m:
            cur = m.group(1)
            continue
        m = re.search(r"Name: +(\S+)", line)
        if m and cur:
            file2vers[cur].add(m.group(1))
            ver2file[m.group(1)].add(cur)

sym2vers = collections.defaultdict(set)    # symbol -> versions it is referenced with
unversioned = set()                        # symbols referenced with no version
for c in OBJS:
    for line in subprocess.run(["objdump", "-T", str(c)], capture_output=True, text=True).stdout.splitlines():
        if "*UND*" not in line:
            continue
        tail = line.split("*UND*", 1)[1]
        m = re.search(r"\(([^()]+)\)\s+(\S+)$", tail)
        if m:
            sym2vers[m.group(2)].add(m.group(1))
        elif tail.split():
            unversioned.add(tail.split()[-1])

SYM_RE = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*$")
by_file = collections.defaultdict(set)
# 1) symbols whose referenced version belongs to a missing library
for sym, vers in sym2vers.items():
    if not SYM_RE.match(sym):
        continue
    for v in vers:
        for f in ver2file.get(v, ()):
            if f in missing:
                by_file[f].add(sym)
# 2) unversioned symbols, routed by name prefix
placed = set().union(*by_file.values()) if by_file else set()
for f in missing:
    for sym in sorted(unversioned - placed):
        if not SYM_RE.match(sym):
            continue
        if sym.startswith(PREFIX.get(f, ("\0",))):
            by_file[f].add(sym)
            placed.add(sym)

# 3) symbols that are genuinely unresolved anywhere (not Python/glibc/C++ runtime) get
#    routed into the X11/GL stubs so the loader stops complaining.
GPU = {"libcuda.so.1", "libze_loader.so.1", "libamdhip64.so.6"}
havedef = set()
for d in [x for x in REAL_DIRS if x.exists()]:
    for f in d.glob("*.so*"):
        havedef |= set(re.findall(r"^\s*[0-9a-f]+\s+g\s+DF\s+\*ABS\*.*\s(\S+)$",
                        subprocess.run(["nm","-D","--defined-only",str(f)],capture_output=True,text=True).stdout, re.M))
        havedef |= set(subprocess.run(["bash","-c",f"nm -D --defined-only '{f}' 2>/dev/null | awk '{{print $NF}}'"],
                        capture_output=True,text=True).stdout.split())
BAD = re.compile(r"^(_|Py|py|glXChooseVisual$|XInitThreads$|XCloseDisplay$|XOpenDisplay$|XPending$|XNextEvent$)")
all_unplaced = sorted(s for s in (set(sym2vers) | unversioned)
                      if SYM_RE.match(s) and s not in placed and s not in havedef and not BAD.match(s)
                      and s.startswith(("X", "x", "gl", "ep0", "Xi", "Ice", "Sm", "Xt")))
for f in missing:
    if f not in GPU:
        by_file[f].update(all_unplaced)

summary = {}
for soname in missing:
    syms = sorted(by_file.get(soname, set()))
    vers = sorted(v for v in file2vers.get(soname, set()) if SYM_RE.match(v) or re.fullmatch(r"[\w.\-]+", v))
    if not syms:
        syms = ["_bpy_stub_dummy"]
        vers = vers or []
    stem = re.sub(r"[^A-Za-z0-9_]", "_", soname.split(".so")[0])
    nodes = collections.OrderedDict((v, []) for v in vers)
    for s in syms:
        want = [v for v in vers if v in sym2vers.get(s, ())]
        (nodes[want[0]] if want else nodes.setdefault("_EXTRA", [])).append(s)
    lines = []
    for v, vsyms in nodes.items():
        body = f"global: {'; '.join(sorted(vsyms))}; local: *;" if vsyms else "local: *;"
        lines.append(f"{v} {{ {body} }};")
    if not lines:
        lines = ["BASE { global: *; local: *; };"]
    (GEN / f"{stem}.map").write_text("\n".join(lines) + "\n")
    (GEN / f"{stem}.c").write_text("#include <stddef.h>\n" +
                                   "\n".join(f"void {s}(void) {{ (void)0; }}" for s in syms) + "\n")
    cmd = ["gcc", "-O0", "-fPIC", "-shared", f"-Wl,-soname,{soname}",
           f"-Wl,--version-script={GEN}/{stem}.map", "-o", str(STUB / soname), str(GEN / f"{stem}.c")]
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode:
        (GEN / f"{stem}.map").write_text("BASE { global: *; local: *; };\n")
        r = subprocess.run(cmd, capture_output=True, text=True)
        if r.returncode:
            print("BUILD FAIL", soname, r.stderr[:200])
            continue
    summary[soname] = {"symbols": len(syms), "versions": vers}
print("missing:", missing)
for k, v in summary.items():
    print(f"  {k:24s} {v['symbols']:3d} syms  versions={v['versions']}")
