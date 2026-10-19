#!/usr/bin/env python3
"""Descarga reproducible de los assets CC0 usados por «Isla Salvaje».

Todos los archivos se obtienen desde repositorios públicos de GitHub mediante la
API (api.github.com), fijando el commit exacto para que la descarga sea
reproducible. Cada entrada indica el pack original, su licencia y su página
oficial. El resultado se escribe dentro de ``assets/`` (modelos, texturas,
iconos, fuentes) y en ``.asset_cache/raw`` (audio sin procesar, que luego
convierte ``tools/process_audio.py``).

Uso:
    python3 tools/fetch_assets.py            # descarga lo que falte
    python3 tools/fetch_assets.py --force    # vuelve a descargar todo

Requiere un token de GitHub (variable GITHUB_TOKEN o ``gh auth token``).
"""
from __future__ import annotations

import argparse
import concurrent.futures as cf
import json
import os
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RAW_AUDIO = os.path.join(ROOT, ".asset_cache", "raw")

# --------------------------------------------------------------------------
# Repositorios espejo (commit fijado) y origen oficial de cada pack.
# --------------------------------------------------------------------------
REPOS = {
    "tiddy": ("Tiddybub/3d-assets", "11ff7082e566a6278553bf7623980cb93dd41e27"),
    "shore": ("shorepine/kenney", "3694c6879e487c108f55677be7dd2ca75b07cc3b"),
    "token": ("DickyDicky7/TokenTale-The-Elemental-Saga", "8cf4a7001515d975e82ccc76018e2d908201eaad"),
    "omarchy": ("funcoder/omarchy-ambient", "2686c861bff26bc7da55dd8e4e858f6d66d39a41"),
    "stn": ("webdevcody/survive-the-night-fps", "9e32eb4514c27d6e418718b9ef3b7fe13297ac0e"),
    "rene": ("g0ddest/renethack", "723d1d1957b723ea9f7ce69709d3a840ca67943a"),
    "safari": ("SoundSafari/CC0-1.0-Music", "655388f987eacf6d08d73080fcc3e727f267bfde"),
    "gfonts": ("google/fonts", "47d54ca1ebb14fd864695f1d39dc734f39017c33"),
}

# --------------------------------------------------------------------------
# Modelos OBJ (+MTL y texturas). Formato: carpeta destino -> definición.
# --------------------------------------------------------------------------
MODEL_PACKS = {
    "nature": {
        "repo": "tiddy", "src": "nature/nature-kit", "textures": False,
        "names": """
            tree_palmTall tree_palmDetailedTall tree_palmBend tree_palmShort tree_palmDetailedShort tree_palm
            tree_default tree_oak tree_detailed tree_fat tree_tall tree_simple tree_thin tree_cone
            tree_default_dark tree_oak_dark tree_detailed_dark tree_tall_dark
            tree_pineRoundA tree_pineRoundC tree_pineTallA tree_pineDefaultA
            log log_large log_stack log_stackLarge stump_round stump_old stump_roundDetailed
            rock_largeA rock_largeB rock_largeC rock_largeD rock_tallA rock_tallB rock_tallC
            rock_smallA rock_smallB rock_smallC rock_smallD rock_smallFlatA rock_smallTopA
            stone_largeA stone_largeB stone_largeC stone_tallA stone_tallB stone_smallA stone_smallB stone_smallC stone_smallFlatA
            cliff_block_rock cliff_large_rock cliff_corner_rock cliff_cornerLarge_rock cliff_cave_rock cliff_blockCave_rock
            cliff_top_rock cliff_half_rock cliff_steps_rock cliff_rock cliff_blockHalf_rock cliff_waterfall_rock
            cliff_block_stone cliff_large_stone cliff_corner_stone cliff_cave_stone
            plant_bush plant_bushDetailed plant_bushLarge plant_bushSmall plant_bushTriangle plant_flatShort plant_flatTall
            grass grass_large grass_leafs grass_leafsLarge
            flower_redA flower_redB flower_yellowA flower_yellowB flower_purpleA flower_purpleB
            mushroom_red mushroom_tan mushroom_redGroup mushroom_tanGroup mushroom_redTall
            lily_large lily_small hanging_moss
            crop_carrot crop_melon crop_pumpkin crop_turnip
            crops_cornStageA crops_cornStageB crops_cornStageC crops_cornStageD crops_wheatStageA crops_wheatStageB
            crops_dirtRow crops_dirtSingle crops_dirtDoubleRow crops_leafsStageA crops_leafsStageB crops_bambooStageA crops_bambooStageB
            campfire_stones campfire_logs campfire_bricks tent_detailedOpen tent_detailedClosed tent_smallOpen tent_smallClosed
            bed canoe canoe_paddle sign pot_large pot_small
            statue_head statue_obelisk statue_column statue_columnDamaged statue_ring statue_block
            fence_simple fence_planks fence_gate fence_simpleHigh bridge_wood bridge_woodNarrow
            path_stone path_stoneCircle path_wood platform_beach platform_grass
        """,
    },
    "survival": {"repo": "tiddy", "src": "nature/survival-kit", "textures": True, "names": "*"},
    "town": {
        "repo": "tiddy", "src": "fantasy/fantasy-town-kit", "textures": True,
        "names": """
            watermill watermill-wide windmill wheel cart cart-high stall stall-red stall-green stall-bench stall-stool
            fountain-round fountain-round-detail lantern chimney chimney-base chimney-top
            wall-wood wall-wood-door wall-wood-window-shutters wall-wood-window-small wall-wood-corner wall-wood-half
            wall wall-door wall-window-shutters wall-corner wall-half
            roof roof-gable roof-gable-end roof-corner roof-high roof-high-gable roof-point roof-flat
            planks planks-half pillar-wood pillar-stone poles fence fence-gate hedge hedge-large
            banner-red banner-green blade overhang stairs-wood rock-large tree-crooked tree-high-round
        """,
    },
    "pirate": {
        "repo": "tiddy", "src": "fantasy/pirate-kit", "textures": True,
        "names": """
            ship-wreck boat-row-small boat-row-large barrel crate crate-bottles chest cannon cannon-ball
            palm-bend palm-straight palm-detailed-bend palm-detailed-straight
            structure-platform-dock structure-platform-dock-small structure-platform tower-watch flag-pirate flag
            rocks-sand-a rocks-sand-b rocks-sand-c rocks-a rocks-b patch-sand patch-sand-foliage patch-grass-foliage
            grass-plant hole bottle-large tool-shovel mast
        """,
    },
    "food": {
        "repo": "tiddy", "src": "misc/food-kit", "textures": True,
        "names": """
            apple banana coconut coconut-half meat-raw meat-cooked meat-ribs fish fish-bones mushroom carrot corn
            pineapple watermelon cherries strawberry grapes egg egg-cooked honey bowl-soup bowl-broth pot-stew
            skewer skewer-vegetables bottle-oil lemon orange pumpkin-basic bread loaf mussel bag can
        """,
    },
    "animals": {"repo": "tiddy", "src": "characters/cube-pets", "textures": True, "names": "*"},
    "characters": {
        "repo": "tiddy", "src": "characters/mini-characters", "textures": True,
        "names": """
            character-male-a character-male-b character-male-c character-male-d character-male-e character-male-f
            character-female-a character-female-b character-female-c character-female-d character-female-e character-female-f
        """,
    },
    "graveyard": {
        "repo": "tiddy", "src": "characters/graveyard-kit", "textures": True,
        "names": """
            character-skeleton character-zombie character-ghost character-vampire character-keeper
            lantern-candle lantern-glass fire-basket gravestone-round gravestone-cross gravestone-broken
            crypt-small crypt-small-roof crypt-door pumpkin pumpkin-carved hay-bale hay-bale-bundled
            debris debris-wood rocks rocks-tall pine-crooked trunk trunk-long altar-stone candle candle-multiple
            shovel shovel-dirt iron-fence iron-fence-damaged pillar-obelisk urn-round cross-wood
        """,
    },
    "factory": {
        "repo": "tiddy", "src": "modern-urban/factory-kit", "textures": True,
        "names": """
            machine machine-window machine-fortified machine-bed hopper-round hopper-high-round
            conveyor conveyor-long conveyor-corner robot-arm-a robot-arm-b cog-a cog-b cog-c
            pipe-large pipe-large-bend crane screen-small screen-wide piston-round box-small box-large
            lever-single top structure-short structure-medium scanner-low
        """,
    },
    "crystals": {
        "repo": "tiddy", "src": "fantasy/tower-defense-kit", "textures": True,
        "names": "detail-crystal detail-crystal-large tower-round-crystals detail-rocks detail-rocks-large",
    },
    "cave": {
        "repo": "tiddy", "src": "nature/modular-cave-kit", "textures": True,
        "names": "gate-rock gate gate-metal-bars ladder template-wall template-wall-corner template-floor-detail",
    },
    "weapons": {
        "repo": "tiddy", "src": "fantasy/mini-dungeon", "textures": True,
        "names": "weapon-spear weapon-sword shield-round chest barrel",
    },
    "station": {
        "repo": "tiddy", "src": "sci-fi/space-station-kit", "textures": True,
        "names": "computer-screen computer-system container container-tall table-display display-wall",
    },
}

# --------------------------------------------------------------------------
# Imágenes de UI y fuentes (destino relativo a assets/).
# --------------------------------------------------------------------------
UI_ADV = "ui/UI Pack - Adventure/Double/"
MOBILE = "ui/Mobile Controls/Sprites/"
LARGE = "Large (2\u00fb)/"  # nombre literal de la carpeta en el espejo
ICONS = "icons/Game Icons/White/2x/"

UI_FILES = []
for n in """panel_brown panel_brown_dark panel_border_brown panel_border_brown_detail panel_brown_corners_a
            panel_brown_damaged panel_grey panel_grey_dark panel_grid_paper button_brown button_grey button_red
            button_brown_close round_brown round_brown_dark round_grey round_grey_dark hexagon_brown hexagon_grey
            progress_green progress_green_border progress_red progress_red_border progress_blue progress_blue_border
            progress_white progress_white_border progress_transparent progress_green_small progress_red_small
            progress_blue_small progress_white_small progress_transparent_small
            checkbox_brown_checked checkbox_brown_empty scrollbar_brown scrollbar_brown_small banner_hanging banner_modern
            minimap_ring_brown minimap_arrow_a minimap_icon_star_yellow minimap_icon_exclamation_red minimap_icon_jewel_white
            minimap_icon_star_white minimap_icon_exclamation_yellow pattern_grid_paper""".split():
    UI_FILES.append(("shore", UI_ADV + n + ".png", "textures/ui/" + n + ".png"))
for n in """joystick_circle_pad_a joystick_circle_nub_a button_circle button_square button_hexagon""".split():
    UI_FILES.append(("shore", MOBILE + "Style B/" + LARGE + n + ".png", "textures/controls/" + n + ".png"))
for n in """joystick_circle_pad_highlight joystick_circle_nub_highlight button_circle_highlight
            button_square_highlight button_hexagon_highlight""".split():
    UI_FILES.append(("shore", MOBILE + "Highlights A/" + LARGE + n + ".png", "textures/controls/" + n + ".png"))
for n in """icon_hand icon_jump icon_sword icon_arrow_curved icon_wrench icon_menu icon_cog icon_pause icon_shield
            icon_target icon_fire icon_burst icon_checkmark icon_cross icon_arrow_rotate icon_lock icon_save
            icon_search icon_star icon_skull icon_key icon_money icon_arrow""".split():
    UI_FILES.append(("shore", MOBILE + "Icons/" + LARGE + n + ".png", "textures/controls/" + n + ".png"))
for n in """gear home menuGrid menuList wrench information trophy star save exit locked unlocked checkmark cross
            plus minus pause audioOn audioOff musicOn musicOff warning exclamation question target zoomIn zoomOut
            barsVertical leaderboardsSimple shoppingBasket open return arrowLeft arrowRight medal1 power
            fastForward next previous trashcan multiplayer singleplayer zoom larger""".split():
    UI_FILES.append(("shore", ICONS + n + ".png", "icons/ui/" + n + ".png"))
UI_FILES += [
    ("gfonts", "ofl/fredoka/Fredoka[wdth,wght].ttf", "fonts/Fredoka.ttf"),
    ("gfonts", "ofl/fredoka/OFL.txt", "fonts/Fredoka-OFL.txt"),
    ("gfonts", "ofl/nunito/Nunito[wght].ttf", "fonts/Nunito.ttf"),
    ("gfonts", "ofl/nunito/OFL.txt", "fonts/Nunito-OFL.txt"),
]

# --------------------------------------------------------------------------
# Audio bruto (se procesa después con tools/process_audio.py).
# --------------------------------------------------------------------------
K = "game_asset_s/Audio/"
AUDIO_FILES = []


def _k(pack: str, sub: str, names: str, ext: str = ".ogg") -> None:
    for n in names.split():
        AUDIO_FILES.append(("token", K + pack + "/" + sub + n + ext, "kenney/" + pack + "/" + n + ext))
    AUDIO_FILES.append(("token", K + pack + "/License.txt", "kenney/" + pack + "/License.txt"))


_k("Impact Sounds", "Audio/", """
    footstep_grass_000 footstep_grass_001 footstep_grass_002 footstep_grass_003 footstep_grass_004
    footstep_concrete_000 footstep_concrete_001 footstep_concrete_002 footstep_concrete_003 footstep_concrete_004
    footstep_wood_000 footstep_wood_001 footstep_wood_002 footstep_wood_003 footstep_wood_004
    footstep_snow_000 footstep_snow_001 footstep_snow_002 footstep_snow_003 footstep_snow_004
    impactWood_heavy_000 impactWood_heavy_001 impactWood_heavy_002 impactWood_medium_000 impactWood_medium_001
    impactMining_000 impactMining_001 impactMining_002 impactMining_003 impactMining_004
    impactPunch_heavy_000 impactPunch_heavy_001 impactPunch_medium_000 impactPunch_medium_001
    impactPlank_medium_000 impactPlank_medium_001 impactPlank_medium_002
    impactSoft_heavy_000 impactSoft_heavy_001 impactSoft_medium_000 impactSoft_medium_001
    impactMetal_light_000 impactMetal_light_001 impactMetal_medium_000 impactGeneric_light_000 impactGeneric_light_001
""")
_k("RPG Audio", "Audio/", """
    chop cloth1 cloth2 cloth3 bookFlip1 bookFlip2 bookOpen bookClose handleCoins handleCoins2 metalPot1 metalPot2
    drawKnife1 drawKnife2 creak1 creak2 dropLeather handleSmallLeather handleSmallLeather2 metalLatch metalClick
    knifeSlice knifeSlice2 beltHandle1 doorOpen_1 doorClose_1 footstep00 footstep01 footstep02 footstep03 footstep04
""")
for sub, names in (("Audio/Water/", "drip1 drip2 drip3 sinkWater1 sinkWater2"),
                   ("Audio/Woosh/", "woosh1 woosh2 woosh3 woosh4"),
                   ("Audio/Rocks/", "rockHit1 rockHit2 stoneHit1 stoneHit2 stoneHit3 stonesHit1"),
                   ("Audio/Swords/", "swordStone1 swordStone2 sword1 sword2")):
    for n in names.split():
        AUDIO_FILES.append(("token", K + "Foley Sounds/" + sub + n + ".ogg", "kenney/Foley Sounds/" + n + ".ogg"))
AUDIO_FILES.append(("token", K + "Foley Sounds/License.txt", "kenney/Foley Sounds/License.txt"))
_k("Interface Sounds", "Audio/", """
    click_001 click_002 click_003 confirmation_001 confirmation_002 confirmation_003 error_001 error_002 error_004
    open_001 open_002 close_001 close_002 select_001 select_002 switch_001 switch_002 toggle_001 drop_001 drop_002
    bong_001 glass_001 pluck_001 pluck_002 maximize_001 minimize_001 question_001 tick_001 back_001
""")
_k("Digital Audio", "Audio/", """
    powerUp2 powerUp5 powerUp7 powerUp11 threeTone1 threeTone2 lowDown phaserUp1 phaserUp3 zapThreeToneUp highUp twoTone1
""")
_k("Sci-Fi Sounds", "Audio/", "computerNoise_000 engineCircular_000 forceField_000 spaceEngineLow_000 spaceEngine_000 doorOpen_000")
_k("Music Jingles", "Audio (Steeldrum)/", " ".join("jingles-steel_%02d" % i for i in range(17)))
_k("Music Loops", "Loops/", "", ".ogg")
for n in ("Night at the Beach", "Farm Frolics", "Flowing Rocks", "Infinite Descent", "Mishief Stroll"):
    AUDIO_FILES.append(("token", K + "Music Loops/Loops/" + n + ".ogg", "kenney/Music Loops/" + n + ".ogg"))

# Grabaciones de campo CC0 (Freesound) ya preparadas como bucles.
for n in ("birds", "crickets", "waves", "stream", "wind", "storm"):
    AUDIO_FILES.append(("omarchy", "sounds/" + n + ".ogg", "omarchy/" + n + ".ogg"))
AUDIO_FILES.append(("omarchy", "CREDITS.md", "omarchy/CREDITS.md"))

# Grabaciones CC0 (Freesound) recortadas en «sprites» con varias tomas.
for n in ("fire_loop fire_ignite tree_fall branch_snap bush_rustle hammer swing hit_flesh imp_body imp_wood_break "
          "pv_hurt pv_death wolf_howl zv_growl zv_attack zv_death zv_pain dog_snarl owl_horned stg_night stg_dawn "
          "stg_victory stg_death fs_water sticks tree_creak cloth").split():
    AUDIO_FILES.append(("stn", "client/audio/samples/" + n + ".ogg", "stn/" + n + ".ogg"))
AUDIO_FILES.append(("stn", "client/audio/samples/CREDITS.md", "stn/CREDITS.md"))
AUDIO_FILES.append(("stn", "client/audio/samples.js", "stn/samples.js"))

# Efectos CC0 de OpenGameArt (comer, beber, agua, campana, fuego).
for p in ("starninjas/crunch/crunch_2.wav starninjas/crunch/crunch_3.wav starninjas/crunch/crunch_4.wav "
          "owlishmedia/drink/Drink_02.wav owlishmedia/drink/Drink_03.wav owlishmedia/drink/Drink_04.wav "
          "rubberduck/water/splash_02.wav rubberduck/water/splash_03.wav rubberduck/water/bubble_02.wav "
          "springspring/pleasing-bell.wav themightyglider/flame_0.wav").split():
    AUDIO_FILES.append(("rene", "client/godot/audio/cc0/" + p, "oga/" + p.replace("/", "__")))
AUDIO_FILES.append(("rene", "client/godot/audio/CREDITS.md", "oga/CREDITS.md"))

# Música CC0 de FreePD.com (Kevin MacLeod).
for n in ("Connecting Rainbows", "Midnight in the Green House"):
    AUDIO_FILES.append(("safari", "freepd.com/" + n + ".mp3", "freepd/" + n + ".mp3"))


# --------------------------------------------------------------------------
def github_token() -> str:
    tok = os.environ.get("GITHUB_TOKEN") or os.environ.get("GH_TOKEN")
    if tok:
        return tok
    try:
        return subprocess.run(["gh", "auth", "token"], capture_output=True, text=True, check=True).stdout.strip()
    except Exception:  # noqa: BLE001
        return ""


TOKEN = github_token()
_TREES: dict[str, dict] = {}


def tree(repo_key: str) -> dict:
    """Mapa ruta->tamaño del árbol del commit fijado (para validar y expandir '*')."""
    if repo_key not in _TREES:
        repo, sha = REPOS[repo_key]
        data = api_json(f"https://api.github.com/repos/{repo}/git/trees/{sha}?recursive=1")
        _TREES[repo_key] = {t["path"]: t.get("size", 0) for t in data["tree"] if t["type"] == "blob"}
    return _TREES[repo_key]


def api_json(url: str) -> dict:
    req = urllib.request.Request(url, headers={"Authorization": f"Bearer {TOKEN}", "Accept": "application/vnd.github+json"})
    with urllib.request.urlopen(req, timeout=120) as r:
        return json.loads(r.read())


def download(repo_key: str, path: str, dest: str, force: bool) -> tuple[str, int]:
    if os.path.exists(dest) and os.path.getsize(dest) > 0 and not force:
        return dest, -1
    repo, sha = REPOS[repo_key]
    url = f"https://api.github.com/repos/{repo}/contents/{urllib.parse.quote(path)}?ref={sha}"
    req = urllib.request.Request(url, headers={"Authorization": f"Bearer {TOKEN}", "Accept": "application/vnd.github.raw"})
    for attempt in range(5):
        try:
            with urllib.request.urlopen(req, timeout=300) as r:
                data = r.read()
            break
        except urllib.error.HTTPError as e:
            if e.code in (403, 429, 500, 502, 503) and attempt < 4:
                time.sleep(2 + attempt * 3)
                continue
            raise RuntimeError(f"HTTP {e.code} para {repo}:{path}") from e
        except urllib.error.URLError:
            if attempt < 4:
                time.sleep(2 + attempt * 3)
                continue
            raise
    if data.startswith(b"version https://git-lfs"):
        raise RuntimeError(f"{repo}:{path} es un puntero Git LFS, no el archivo real")
    os.makedirs(os.path.dirname(dest), exist_ok=True)
    tmp = dest + ".part"
    with open(tmp, "wb") as f:
        f.write(data)
    os.replace(tmp, dest)
    return dest, len(data)


def build_jobs() -> list[tuple[str, str, str]]:
    jobs: list[tuple[str, str, str]] = []
    for folder, pk in MODEL_PACKS.items():
        t = tree(pk["repo"])
        base = pk["src"] + "/Models/OBJ format/"
        if pk["names"].strip() == "*":
            names = sorted(p[len(base):-4] for p in t if p.startswith(base) and p.endswith(".obj") and "/" not in p[len(base):])
        else:
            names = pk["names"].split()
        dest_dir = os.path.join(ROOT, "assets", "models", folder)
        for n in names:
            for ext in (".obj", ".mtl"):
                src = base + n + ext
                if src not in t:
                    raise SystemExit(f"Falta {src} en {REPOS[pk['repo']][0]}")
                jobs.append((pk["repo"], src, os.path.join(dest_dir, n + ext)))
        if pk["textures"]:
            for p in t:
                if p.startswith(base + "Textures/"):
                    jobs.append((pk["repo"], p, os.path.join(dest_dir, p[len(base):])))
        for extra in ("License.txt", "SOURCE.md"):
            if pk["src"] + "/" + extra in t:
                jobs.append((pk["repo"], pk["src"] + "/" + extra, os.path.join(dest_dir, extra)))
    for repo_key, src, rel in UI_FILES:
        jobs.append((repo_key, src, os.path.join(ROOT, "assets", rel)))
    for repo_key, src, rel in AUDIO_FILES:
        jobs.append((repo_key, src, os.path.join(RAW_AUDIO, rel)))
    return jobs


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--force", action="store_true")
    args = ap.parse_args()
    if not TOKEN:
        sys.exit("No hay token de GitHub (GITHUB_TOKEN o gh auth token).")
    jobs = build_jobs()
    print(f"{len(jobs)} archivos en el manifiesto")
    total = 0
    errors = []
    with cf.ThreadPoolExecutor(max_workers=8) as ex:
        futs = {ex.submit(download, r, s, d, args.force): (r, s) for r, s, d in jobs}
        for i, fut in enumerate(cf.as_completed(futs), 1):
            try:
                _, n = fut.result()
                if n > 0:
                    total += n
            except Exception as e:  # noqa: BLE001
                errors.append(f"{futs[fut]}: {e}")
            if i % 100 == 0:
                print(f"  {i}/{len(jobs)}")
    print(f"Descargados {total / 1e6:.1f} MB")
    if errors:
        print("ERRORES:")
        for e in errors:
            print("  ", e)
        sys.exit(1)


if __name__ == "__main__":
    main()
