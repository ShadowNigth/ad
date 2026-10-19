#!/usr/bin/env python3
"""Genera ASSET_CREDITS.md recorriendo assets/ y los registros de origen.

Cada archivo del juego aparece con su pack/autor, URL de origen, licencia y
atribución. Los datos de origen salen de los SOURCE.md/License.txt de cada
pack y de assets/sounds/licenses/audio_sources.json (process_audio.py).
"""
from __future__ import annotations

import json
import os
import re

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
A = os.path.join(ROOT, "assets")

MIRRORS = {
    "tiddy": "https://github.com/Tiddybub/3d-assets (commit 11ff708)",
    "shore": "https://github.com/shorepine/kenney (commit 3694c68)",
    "token": "https://github.com/DickyDicky7/TokenTale-The-Elemental-Saga (commit 8cf4a70), carpeta game_asset_s/Audio",
    "omarchy": "https://github.com/funcoder/omarchy-ambient (commit 2686c86)",
    "stn": "https://github.com/webdevcody/survive-the-night-fps (commit 9e32eb4), client/audio/samples",
    "rene": "https://github.com/g0ddest/renethack (commit 723d1d1), client/godot/audio/cc0",
    "safari": "https://github.com/SoundSafari/CC0-1.0-Music (commit 655388f), carpeta freepd.com",
    "gfonts": "https://github.com/google/fonts (commit 47d54ca)",
}

KENNEY_AUDIO = {
    "Impact Sounds": "https://kenney.nl/assets/impact-sounds",
    "RPG Audio": "https://kenney.nl/assets/rpg-audio",
    "Foley Sounds": "https://kenney.nl/assets/foley-sounds",
    "Interface Sounds": "https://kenney.nl/assets/interface-sounds",
    "Digital Audio": "https://kenney.nl/assets/digital-audio",
    "Sci-Fi Sounds": "https://kenney.nl/assets/sci-fi-sounds",
    "Music Jingles": "https://kenney.nl/assets/music-jingles",
    "Music Loops": "https://kenney.nl (pack «Music Loops» 1.1, incluido en Kenney Game Assets All-in-1)",
}

OGA = {
    "starninjas": ("7 Eating Crunches", "StarNinjas", "https://opengameart.org/content/7-eating-crunches"),
    "owlishmedia": ("202 More Sound Effects (drinking)", "OwlishMedia", "https://opengameart.org/content/202-more-sound-effects"),
    "rubberduck": ("40 CC0 water / splash / slime SFX", "rubberduck", "https://opengameart.org/content/40-cc0-water-splash-slime-sfx"),
    "springspring": ("Pleasing Bell Sound Effect", "Spring Spring", "https://opengameart.org/content/pleasing-bell-sound-effect"),
    "themightyglider": ("Catching fire", "themightyglider", "https://opengameart.org/content/catching-fire"),
}

OMARCHY_LABEL = {"birds": "Forest birds", "crickets": "Night crickets", "waves": "Ocean waves", "stream": "Stream", "wind": "Wind"}

FREEPD = {
    "Connecting Rainbows": "Kevin MacLeod",
    "Midnight in the Green House": "Kevin MacLeod",
}


def md_table_rows(path: str) -> dict:
    rows = {}
    if not os.path.exists(path):
        return rows
    for line in open(path, encoding="utf-8"):
        if line.startswith("|") and not line.startswith("|---") and not line.startswith("| ---"):
            cells = [c.strip() for c in line.strip().strip("|").split("|")]
            if cells:
                rows[cells[0].strip("`")] = cells
    return rows


def source_info(pack_dir: str) -> tuple[str, str]:
    src = os.path.join(pack_dir, "SOURCE.md")
    name = os.path.basename(pack_dir)
    url = ""
    if os.path.exists(src):
        txt = open(src, encoding="utf-8").read()
        m = re.search(r"^#\s*(.+)$", txt, re.M)
        if m:
            name = m.group(1).strip()
        m = re.search(r"\((https://kenney\.nl/assets/[^)]+)\)", txt)
        if m:
            url = m.group(1)
    return name, url


def main() -> None:
    out: list[str] = []
    w = out.append
    w("# Créditos de recursos (ASSET_CREDITS)")
    w("")
    w("Todos los recursos de terceros están **dentro del proyecto** (no se descarga nada en tiempo de ejecución).")
    w("Este archivo se genera con `python3 tools/generate_credits.py` a partir de los propios archivos de `assets/`,")
    w("los `License.txt`/`SOURCE.md` de cada pack y el registro `assets/sounds/licenses/audio_sources.json`.")
    w("Los recursos se descargaron con `tools/fetch_assets.py` desde espejos públicos en GitHub con commit fijado")
    w("(kenney.nl, opengameart.org y freesound.org no eran accesibles directamente desde el entorno de desarrollo);")
    w("se comprobó la licencia de cada pack en su página original y en el `License.txt` incluido.")
    w("")
    w("| Licencia | Significado |")
    w("|---|---|")
    w("| CC0 1.0 | Dominio público: uso libre, también comercial, sin atribución obligatoria (se acredita por cortesía). |")
    w("| SIL OFL 1.1 | Fuentes tipográficas: uso libre; el texto de la licencia se incluye junto a la fuente. |")
    w("")
    w("**Atribución obligatoria:** ninguna (todo es CC0 u OFL). Se agradece a Kenney (www.kenney.nl), Kevin MacLeod")
    w("(FreePD.com) y a los autores de Freesound y OpenGameArt listados abajo.")
    w("")
    # ------------------------------------------------------------ modelos
    w("## 1. Modelos 3D (OBJ + MTL + texturas)")
    w("")
    w("Formato original OBJ con sus `.mtl` y texturas (`Textures/colormap.png`). Autor: **Kenney**. Licencia: **CC0 1.0**.")
    w(f"Espejo de descarga: {MIRRORS['tiddy']} (los 3 modelos de `weapons/` vienen del pack Mini Dungeon del mismo espejo).")
    w("")
    models_root = os.path.join(A, "models")
    for pack in sorted(os.listdir(models_root)):
        pdir = os.path.join(models_root, pack)
        if not os.path.isdir(pdir):
            continue
        name, url = source_info(pdir)
        objs = sorted(f[:-4] for f in os.listdir(pdir) if f.endswith(".obj"))
        texs = []
        tdir = os.path.join(pdir, "Textures")
        if os.path.isdir(tdir):
            texs = sorted(os.listdir(tdir))
            texs = [t for t in texs if not t.endswith(".import")]
        w(f"### `assets/models/{pack}/` — {name}")
        w("")
        w(f"- Fuente: {url or 'https://kenney.nl'} · Licencia: CC0 1.0 (`assets/models/{pack}/License.txt`) · Autor: Kenney")
        w(f"- {len(objs)} modelos (cada uno con `.obj` + `.mtl`): " + ", ".join(f"`{o}`" for o in objs))
        if texs:
            w(f"- Texturas: " + ", ".join(f"`Textures/{t}`" for t in texs))
        w("")
    # ------------------------------------------------------------ 2D
    w("## 2. Interfaz, controles táctiles, iconos y fuentes")
    w("")
    groups = [
        ("textures/ui", "Kenney — UI Pack: Adventure", "https://kenney.nl/assets/ui-pack-adventure", "CC0 1.0", MIRRORS["shore"]),
        ("textures/controls", "Kenney — Mobile Controls", "https://kenney.nl/assets/mobile-controls", "CC0 1.0", MIRRORS["shore"]),
        ("icons/ui", "Kenney — Game Icons", "https://kenney.nl/assets/game-icons", "CC0 1.0", MIRRORS["shore"]),
    ]
    for rel, name, url, lic, mirror in groups:
        d = os.path.join(A, rel)
        files = sorted(f for f in os.listdir(d) if f.endswith(".png"))
        w(f"### `assets/{rel}/` — {name}")
        w("")
        w(f"- Fuente: {url} · Licencia: {lic} · Autor: Kenney · Espejo: {mirror}")
        w(f"- {len(files)} archivos: " + ", ".join(f"`{f}`" for f in files))
        w("")
    for rel, what in (("icons/items", "objetos del inventario"), ("icons/buildings", "edificios")):
        d = os.path.join(A, rel)
        files = sorted(f for f in os.listdir(d) if f.endswith(".png"))
        w(f"### `assets/{rel}/` — iconos de {what}")
        w("")
        w(f"- Renderizados para este proyecto con `tools/render_icons.py` a partir de los modelos OBJ de Kenney listados arriba")
        w(f"  (obra derivada de recursos CC0; se distribuyen también como CC0).")
        w(f"- {len(files)} archivos: " + ", ".join(f"`{f}`" for f in files))
        w("")
    w("### `assets/fonts/`")
    w("")
    w(f"- `Fredoka.ttf` — Fredoka, © The Fredoka Project Authors, SIL Open Font License 1.1 (`Fredoka-OFL.txt`). Fuente: https://fonts.google.com/specimen/Fredoka · Espejo: {MIRRORS['gfonts']} (`ofl/fredoka`).")
    w(f"- `Nunito.ttf` — Nunito, © The Nunito Project Authors, SIL Open Font License 1.1 (`Nunito-OFL.txt`). Fuente: https://fonts.google.com/specimen/Nunito · Espejo: {MIRRORS['gfonts']} (`ofl/nunito`).")
    w("")
    w("### Recursos propios del proyecto")
    w("")
    w("- `icon.svg` (icono de la aplicación), `assets/shaders/*.gdshader` (agua y barras), el terreno, el agua y la")
    w("  disposición de la isla se generan con el código de este proyecto (sin recursos de terceros).")
    app_dir = os.path.join(A, "icons", "app")
    if os.path.isdir(app_dir):
        app_files = sorted(f for f in os.listdir(app_dir) if f.endswith(".png"))
        w("- `assets/icons/app/` — iconos del lanzador (Android adaptable y Windows), rasterizados desde `icon.svg` con")
        w("  `Image.load_svg_from_string` de Godot: " + ", ".join(f"`{f}`" for f in app_files) + ".")
    w("- `tools/android/isla_salvaje_publica.keystore` — clave de firma generada con `tools/create_android_keystore.py`.")
    w("")
    # ------------------------------------------------------------ audio
    w("## 3. Efectos de sonido, ambiente y música")
    w("")
    w("Formato OGG Vorbis. Algunos archivos se recortaron, se pasaron a mono, se normalizaron o se separaron en")
    w("tomas individuales con `tools/process_audio.py` (permitido por CC0). Copias de las licencias y créditos de")
    w("origen en `assets/sounds/licenses/`.")
    w("")
    srcs = json.load(open(os.path.join(A, "sounds", "licenses", "audio_sources.json"), encoding="utf-8"))
    stn_rows = md_table_rows(os.path.join(A, "sounds", "licenses", "freesound_survive-the-night_CREDITS.md"))
    om_rows = md_table_rows(os.path.join(A, "sounds", "licenses", "freesound_omarchy-ambient_CREDITS.md"))
    w("| Archivo | Origen | Autor | Licencia | Notas |")
    w("|---|---|---|---|---|")
    for e in srcs:
        f = e["file"].replace("assets/", "")
        src = e["src"]
        note = e.get("note", "")
        if src.startswith("kenney/"):
            pack = src.split("/")[1]
            origin = f"Kenney — {pack}: `{os.path.basename(src)}` · {KENNEY_AUDIO.get(pack, 'https://kenney.nl')}"
            author, lic = "Kenney", "CC0 1.0"
        elif src.startswith("stn/"):
            key = os.path.basename(src)
            row = stn_rows.get(key, ["", ""])
            links = re.findall(r"\[(\d+)\]\((https://freesound\.org[^)]+)\) ([^<|]+?)(?: by ([^<|]+?))?(?:<br>|$)", row[1] if len(row) > 1 else "")
            parts = []
            authors = []
            for (sid, url, title, by) in links:
                parts.append(f"Freesound {sid} «{title.strip()}» {url}")
                if by:
                    authors.append(by.strip())
            origin = "; ".join(parts) if parts else f"Freesound (ver créditos) · {MIRRORS['stn']}"
            author = ", ".join(sorted(set(authors))) or "autores de Freesound"
            lic = "CC0 1.0"
        elif src.startswith("omarchy/"):
            key = os.path.basename(src)[:-4]
            row = om_rows.get(OMARCHY_LABEL.get(key, key), ["", "", ""])
            m = re.search(r"\[([^\]]+)\]\((https://freesound\.org/s/\d+/)\)", row[1] if len(row) > 1 else "")
            a = re.search(r"\[([^\]]+)\]", row[2] if len(row) > 2 else "")
            origin = f"Freesound «{m.group(1)}» {m.group(2)}" if m else "Freesound"
            author = a.group(1) if a else "autor de Freesound"
            lic = "CC0 1.0"
        elif src.startswith("oga/"):
            key = os.path.basename(src).split("__")[0]
            title, author, url = OGA.get(key, ("OpenGameArt", "autor de OpenGameArt", "https://opengameart.org"))
            origin = f"OpenGameArt «{title}» {url}"
            lic = "CC0 1.0"
        elif src.startswith("freepd/"):
            track = os.path.basename(src)[:-4]
            origin = f"FreePD.com «{track}» (https://freepd.com — sitio archivado; espejo {MIRRORS['safari']})"
            author = FREEPD.get(track, "FreePD")
            lic = "CC0 1.0"
        else:
            origin, author, lic = src, "?", "?"
        w(f"| `{f}` | {origin} | {author} | {lic} | {note} |")
    w("")
    w("## 4. Comprobación de licencias")
    w("")
    w("- Kenney: todas las páginas de los packs indican «Creative Commons CC0» y cada pack incluye su `License.txt` CC0")
    w("  (copiados en `assets/models/*/License.txt` y `assets/sounds/licenses/`).")
    w("- FreePD.com: «This music is all licensed CC0 1.0 Universal Public Domain Dedication» (copia archivada del sitio).")
    w("- Freesound: cada grabación usada figura como «Creative Commons 0» en su página (se verificaron, entre otras,")
    w("  414098, 588401 y 547203); los créditos completos de los recopiladores están en `assets/sounds/licenses/`.")
    w("- OpenGameArt: los packs usados están publicados bajo CC0 (p. ej. «7 Eating Crunches» de StarNinjas).")
    w("- Fuentes: SIL Open Font License 1.1, texto incluido en `assets/fonts/`.")
    w("")
    open(os.path.join(ROOT, "ASSET_CREDITS.md"), "w", encoding="utf-8").write("\n".join(out) + "\n")
    print("ASSET_CREDITS.md:", len(out), "líneas")


if __name__ == "__main__":
    main()
