#!/usr/bin/env python3
"""Convierte el audio bruto descargado por fetch_assets.py en los archivos del juego.

* Copia los efectos de Kenney (ya en OGG) con nombres ordenados por categoría.
* Separa los «sprites» de varias tomas (survive-the-night) usando su tabla de cortes.
* Recorta las grabaciones de ambiente largas a bucles de ~45 s con fundido cíclico,
  las pasa a mono y las vuelve a codificar a menor calidad (pensado para Android).
* Convierte la música MP3 (FreePD) a OGG Vorbis.

Requiere: numpy, scipy, soundfile (libsndfile >= 1.1 con soporte MP3/Vorbis).
"""
from __future__ import annotations

import os
import re
import shutil

import numpy as np
import soundfile as sf
from scipy.signal import resample_poly

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SOURCES: list = []  # registro destino -> origen (lo usa tools/generate_credits.py)


def record(dst: str, src: str, note: str = "") -> None:
    SOURCES.append({"file": dst.replace(ROOT + os.sep, "").replace(os.sep, "/"), "src": src, "note": note})
RAW = os.path.join(ROOT, ".asset_cache", "raw")
SND = os.path.join(ROOT, "assets", "sounds")
MUS = os.path.join(ROOT, "assets", "music")


def out(path: str) -> str:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    return path


def copy(src_rel: str, dst_rel: str) -> None:
    shutil.copyfile(os.path.join(RAW, src_rel), out(os.path.join(SND, dst_rel)))
    record(os.path.join(SND, dst_rel), src_rel)


def to_mono(x: np.ndarray) -> np.ndarray:
    return x.mean(axis=1) if x.ndim == 2 else x


def resample(x: np.ndarray, sr: int, target: int) -> np.ndarray:
    if sr == target:
        return x
    g = np.gcd(sr, target)
    return resample_poly(x, target // g, sr // g, axis=0).astype(np.float32)


def peak_normalize(x: np.ndarray, peak: float = 0.89) -> np.ndarray:
    m = float(np.max(np.abs(x))) if x.size else 0.0
    return x * (peak / m) if m > 1e-6 else x


def rms_normalize(x: np.ndarray, rms: float) -> np.ndarray:
    r = float(np.sqrt(np.mean(np.square(x)))) if x.size else 0.0
    y = x * (rms / r) if r > 1e-7 else x
    m = float(np.max(np.abs(y)))
    return y * (0.95 / m) if m > 0.95 else y


def fade(x: np.ndarray, sr: int, fin: float = 0.004, fout: float = 0.03) -> np.ndarray:
    x = x.copy()
    n_in = min(len(x), int(sr * fin))
    n_out = min(len(x), int(sr * fout))
    if n_in > 0:
        x[:n_in] *= np.linspace(0.0, 1.0, n_in, dtype=np.float32)[:, None] if x.ndim == 2 else np.linspace(0.0, 1.0, n_in, dtype=np.float32)
    if n_out > 0:
        ramp = np.linspace(1.0, 0.0, n_out, dtype=np.float32)
        x[-n_out:] *= ramp[:, None] if x.ndim == 2 else ramp
    return x


def write_ogg(path: str, x: np.ndarray, sr: int, quality: float) -> None:
    """quality 0..1 (más alto = mejor). libsndfile usa compression_level = 1 - calidad."""
    x = np.ascontiguousarray(np.clip(x, -1.0, 1.0), dtype=np.float32)
    channels = 1 if x.ndim == 1 else x.shape[1]
    # libsndfile puede fallar con escrituras Vorbis muy grandes en una sola llamada: se escribe por bloques.
    with sf.SoundFile(out(path), "w", samplerate=sr, channels=channels, format="OGG", subtype="VORBIS",
                      compression_level=float(np.clip(1.0 - quality, 0.0, 1.0))) as f:
        for i in range(0, len(x), 8192):
            f.write(x[i:i + 8192])


def loop_crossfade(x: np.ndarray, sr: int, start: float, length: float, xfade: float) -> np.ndarray:
    """Bucle sin cortes: el final se funde (potencia constante) con el inicio."""
    s = int(start * sr)
    n = int(length * sr)
    xf = int(xfade * sr)
    seg = x[s:s + n + xf]
    if len(seg) < n + xf:
        raise ValueError("segmento demasiado corto para el bucle")
    t = np.linspace(0.0, np.pi / 2, xf, dtype=np.float32)
    head = seg[:xf] * np.sin(t) + seg[n:n + xf] * np.cos(t)
    return np.concatenate([head, seg[xf:n]]).astype(np.float32)


def parse_slices(js_text: str) -> dict[str, list[tuple[float, float]]]:
    res: dict[str, list[tuple[float, float]]] = {}
    for m in re.finditer(r"^\s+([a-z_0-9]+):\s*\{[^}]*slices:\s*\[([^\]]*)\]", js_text, re.M):
        nums = [float(v) for v in m.group(2).replace("\n", " ").split(",") if v.strip()]
        res[m.group(1)] = [(nums[i], nums[i + 1]) for i in range(0, len(nums) - 1, 2)]
    return res


def split_sprite(name: str, dst_prefix: str, slices: dict, pick: list[int] | None = None, quality: float = 0.45,
                 peak: float = 0.89) -> int:
    x, sr = sf.read(os.path.join(RAW, "stn", name + ".ogg"), dtype="float32")
    x = to_mono(x)
    cuts = slices.get(name) or [(0.0, len(x) / sr)]
    idx = pick if pick is not None else list(range(len(cuts)))
    for k, i in enumerate(idx):
        st, du = cuts[i]
        seg = x[int(st * sr):int((st + du) * sr)]
        seg = fade(peak_normalize(seg, peak), sr)
        write_ogg(os.path.join(SND, f"{dst_prefix}_{k}.ogg"), seg, sr, quality)
        record(os.path.join(SND, f"{dst_prefix}_{k}.ogg"), f"stn/{name}.ogg", f"toma {i + 1} de {len(cuts)}")
    return len(idx)


def wav_to_ogg(src_rel: str, dst_rel: str, peak: float = 0.89, quality: float = 0.5) -> None:
    x, sr = sf.read(os.path.join(RAW, src_rel), dtype="float32")
    x = fade(peak_normalize(to_mono(x), peak), sr)
    write_ogg(os.path.join(SND, dst_rel), x, sr, quality)
    record(os.path.join(SND, dst_rel), src_rel, "convertido de WAV a OGG")


def weather_audio() -> None:
    """Lluvia (bucle) y truenos (tomas sueltas) del registro CC0 «Rain and Thunder Ambience Tübingen»."""
    x, sr = sf.read(os.path.join(RAW, "omarchy", "storm.ogg"), dtype="float32")
    mono = resample(to_mono(x), sr, 32000)
    # Tramo inicial (8-72 s): lluvia constante sin truenos.
    rain = rms_normalize(loop_crossfade(mono, 32000, 8.0, 60.0, 4.0), 0.07)
    write_ogg(os.path.join(SND, "ambient/rain_loop.ogg"), rain, 32000, 0.25)
    record(os.path.join(SND, "ambient/rain_loop.ogg"), "omarchy/storm.ogg", "lluvia: recorte de 60 s en bucle, mono 32 kHz")
    # Truenos: picos de energía grave localizados en 196 s, 241 s y 280 s del original.
    for k, (st, du) in enumerate(((236.0, 14.5), (191.5, 12.0), (275.5, 15.0))):
        seg = mono[int(st * 32000):int((st + du) * 32000)]
        seg = fade(peak_normalize(seg, 0.9), 32000, 0.25, 3.0)
        write_ogg(os.path.join(SND, f"ambient/thunder_{k}.ogg"), seg, 32000, 0.3)
        record(os.path.join(SND, f"ambient/thunder_{k}.ogg"), "omarchy/storm.ogg", f"trueno: {st:.1f}-{st + du:.1f} s, mono 32 kHz")


def main() -> None:
    k = "kenney/"
    # ---------------- Pasos -----------------
    for i in range(5):
        copy(f"{k}Impact Sounds/footstep_grass_00{i}.ogg", f"footsteps/grass_{i}.ogg")
        copy(f"{k}Impact Sounds/footstep_concrete_00{i}.ogg", f"footsteps/stone_{i}.ogg")
        copy(f"{k}Impact Sounds/footstep_wood_00{i}.ogg", f"footsteps/wood_{i}.ogg")
        copy(f"{k}Impact Sounds/footstep_snow_00{i}.ogg", f"footsteps/sand_{i}.ogg")
        copy(f"{k}RPG Audio/footstep0{i}.ogg", f"footsteps/dirt_{i}.ogg")
    # ---------------- Recolección -----------------
    copy(f"{k}RPG Audio/chop.ogg", "gather/chop_0.ogg")
    for i in range(3):
        copy(f"{k}Impact Sounds/impactWood_heavy_00{i}.ogg", f"gather/wood_hit_{i}.ogg")
    for i in range(2):
        copy(f"{k}Impact Sounds/impactWood_medium_00{i}.ogg", f"gather/wood_light_{i}.ogg")
    for i in range(5):
        copy(f"{k}Impact Sounds/impactMining_00{i}.ogg", f"gather/mining_{i}.ogg")
    for i, n in enumerate(("stoneHit1", "stoneHit2", "stoneHit3")):
        copy(f"{k}Foley Sounds/{n}.ogg", f"gather/stone_hit_{i}.ogg")
    for i, n in enumerate(("rockHit1", "rockHit2", "stonesHit1")):
        copy(f"{k}Foley Sounds/{n}.ogg", f"gather/rock_break_{i}.ogg")
    for i, n in enumerate(("swordStone1", "swordStone2")):
        copy(f"{k}Foley Sounds/{n}.ogg", f"gather/ore_hit_{i}.ogg")
    for i, n in enumerate(("handleSmallLeather", "handleSmallLeather2")):
        copy(f"{k}RPG Audio/{n}.ogg", f"gather/pickup_{i}.ogg")
    slices = parse_slices(open(os.path.join(RAW, "stn", "samples.js"), encoding="utf-8").read())
    split_sprite("bush_rustle", "gather/bush_rustle", slices, [0, 2, 5])
    split_sprite("branch_snap", "gather/branch_snap", slices, [0, 1, 2, 4])
    split_sprite("tree_fall", "gather/tree_fall", slices, [1], quality=0.4)
    split_sprite("sticks", "gather/sticks", slices, [2, 3])
    # ---------------- Combate -----------------
    for i in range(2):
        copy(f"{k}Impact Sounds/impactPunch_heavy_00{i}.ogg", f"combat/punch_heavy_{i}.ogg")
        copy(f"{k}Impact Sounds/impactPunch_medium_00{i}.ogg", f"combat/punch_medium_{i}.ogg")
        copy(f"{k}Impact Sounds/impactSoft_heavy_00{i}.ogg", f"combat/soft_hit_{i}.ogg")
        copy(f"{k}RPG Audio/drawKnife{i + 1}.ogg", f"combat/draw_{i}.ogg")
    for i in range(4):
        copy(f"{k}Foley Sounds/woosh{i + 1}.ogg", f"combat/woosh_{i}.ogg")
    split_sprite("swing", "combat/swing", slices)
    split_sprite("hit_flesh", "combat/hit_flesh", slices, [1, 3])
    split_sprite("imp_body", "combat/body_fall", slices, [0])
    split_sprite("pv_hurt", "combat/player_hurt", slices, [0, 2, 4, 7, 9])
    split_sprite("pv_death", "combat/player_death", slices, [0])
    split_sprite("zv_growl", "combat/creature_growl", slices, [0, 2, 4], quality=0.4)
    split_sprite("zv_attack", "combat/creature_attack", slices, [0, 3, 6])
    split_sprite("zv_pain", "combat/creature_pain", slices, [1, 3])
    split_sprite("zv_death", "combat/creature_death", slices, [0, 1])
    split_sprite("dog_snarl", "combat/animal_snarl", slices, [0, 2, 4], quality=0.4)
    split_sprite("wolf_howl", "events/wolf_howl", slices, [1], quality=0.35, peak=0.7)
    # ---------------- Construcción -----------------
    split_sprite("hammer", "build/hammer", slices, [0, 1, 2, 4])
    for i in range(3):
        copy(f"{k}Impact Sounds/impactPlank_medium_00{i}.ogg", f"build/plank_{i}.ogg")
    for i, n in enumerate(("creak1", "creak2")):
        copy(f"{k}RPG Audio/{n}.ogg", f"build/creak_{i}.ogg")
    copy(f"{k}Impact Sounds/impactGeneric_light_000.ogg", "build/place_0.ogg")
    copy(f"{k}Impact Sounds/impactGeneric_light_001.ogg", "build/place_1.ogg")
    copy(f"{k}Impact Sounds/impactMetal_light_000.ogg", "build/metal_0.ogg")
    copy(f"{k}Impact Sounds/impactMetal_light_001.ogg", "build/metal_1.ogg")
    copy(f"{k}Impact Sounds/impactMetal_medium_000.ogg", "build/anvil_0.ogg")
    split_sprite("imp_wood_break", "build/wood_break", slices, [1, 2])
    # ---------------- Interfaz -----------------
    ui = {
        "click": ("click_001", "click_002", "click_003"), "confirm": ("confirmation_001", "confirmation_002", "confirmation_003"),
        "error": ("error_001", "error_002", "error_004"), "open": ("open_001", "open_002"), "close": ("close_001", "close_002"),
        "select": ("select_001", "select_002"), "switch": ("switch_001", "switch_002"), "toggle": ("toggle_001",),
        "drop": ("drop_001", "drop_002"), "bong": ("bong_001",), "glass": ("glass_001",), "pluck": ("pluck_001", "pluck_002"),
        "maximize": ("maximize_001",), "minimize": ("minimize_001",), "question": ("question_001",), "tick": ("tick_001",),
        "back": ("back_001",),
    }
    for dst, names in ui.items():
        for i, n in enumerate(names):
            copy(f"{k}Interface Sounds/{n}.ogg", f"ui/{dst}_{i}.ogg")
    for i, n in enumerate(("cloth1", "cloth2", "cloth3")):
        copy(f"{k}RPG Audio/{n}.ogg", f"ui/cloth_{i}.ogg")
    for i, n in enumerate(("bookFlip1", "bookFlip2")):
        copy(f"{k}RPG Audio/{n}.ogg", f"ui/book_flip_{i}.ogg")
    copy(f"{k}RPG Audio/bookOpen.ogg", "ui/book_open_0.ogg")
    copy(f"{k}RPG Audio/bookClose.ogg", "ui/book_close_0.ogg")
    for i, n in enumerate(("handleCoins", "handleCoins2")):
        copy(f"{k}RPG Audio/{n}.ogg", f"ui/coins_{i}.ogg")
    copy(f"{k}RPG Audio/metalLatch.ogg", "ui/latch_0.ogg")
    copy(f"{k}RPG Audio/metalClick.ogg", "ui/metal_click_0.ogg")
    copy(f"{k}RPG Audio/beltHandle1.ogg", "ui/equip_0.ogg")
    copy(f"{k}RPG Audio/dropLeather.ogg", "ui/drop_item_0.ogg")
    copy(f"{k}RPG Audio/doorOpen_1.ogg", "build/door_open_0.ogg")
    copy(f"{k}RPG Audio/doorClose_1.ogg", "build/door_close_0.ogg")
    # ---------------- Supervivencia -----------------
    for i, n in enumerate(("crunch_2", "crunch_3", "crunch_4")):
        wav_to_ogg(f"oga/starninjas__crunch__{n}.wav", f"survival/eat_{i}.ogg")
    for i, n in enumerate(("Drink_02", "Drink_03", "Drink_04")):
        wav_to_ogg(f"oga/owlishmedia__drink__{n}.wav", f"survival/drink_{i}.ogg")
    for i, n in enumerate(("splash_02", "splash_03")):
        wav_to_ogg(f"oga/rubberduck__water__{n}.wav", f"survival/splash_{i}.ogg")
    wav_to_ogg("oga/rubberduck__water__bubble_02.wav", "survival/bubble_0.ogg")
    wav_to_ogg("oga/springspring__pleasing-bell.wav", "events/bell_0.ogg", peak=0.7)
    wav_to_ogg("oga/themightyglider__flame_0.wav", "survival/flame_0.ogg")
    for i, n in enumerate(("sinkWater1", "sinkWater2")):
        copy(f"{k}Foley Sounds/{n}.ogg", f"survival/water_fill_{i}.ogg")
    for i, n in enumerate(("drip1", "drip2", "drip3")):
        copy(f"{k}Foley Sounds/{n}.ogg", f"survival/drip_{i}.ogg")
    for i, n in enumerate(("metalPot1", "metalPot2")):
        copy(f"{k}RPG Audio/{n}.ogg", f"survival/cook_{i}.ogg")
    for i, n in enumerate(("knifeSlice", "knifeSlice2")):
        copy(f"{k}RPG Audio/{n}.ogg", f"survival/slice_{i}.ogg")
    copy(f"{k}Digital Audio/highUp.ogg", "survival/heal_0.ogg")
    split_sprite("fire_ignite", "survival/fire_ignite", slices)
    split_sprite("fs_water", "footsteps/water", slices, [0, 2, 4, 8])
    # ---------------- Eventos / progresión -----------------
    ev = {"level_up": "powerUp7", "unlock": "zapThreeToneUp", "quest_complete": "threeTone1", "research": "phaserUp1",
          "death": "lowDown", "reward": "powerUp2", "upgrade": "powerUp5", "achievement": "threeTone2",
          "worker": "twoTone1", "power_on": "phaserUp3", "boost": "powerUp11"}
    for dst, n in ev.items():
        copy(f"{k}Digital Audio/{n}.ogg", f"events/{dst}_0.ogg")
    for i in range(17):
        copy(f"{k}Music Jingles/jingles-steel_{i:02d}.ogg", f"events/jingle_{i:02d}.ogg")
    for name, dst in (("stg_night", "stinger_night"), ("stg_dawn", "stinger_dawn"), ("stg_victory", "stinger_victory"),
                      ("stg_death", "stinger_death")):
        x, sr = sf.read(os.path.join(RAW, "stn", name + ".ogg"), dtype="float32")
        write_ogg(os.path.join(SND, f"events/{dst}.ogg"), fade(peak_normalize(to_mono(x), 0.8), sr, 0.005, 0.4), sr, 0.4)
        record(os.path.join(SND, f"events/{dst}.ogg"), f"stn/{name}.ogg", "mono, normalizado")
    # ---------------- Máquinas (bucles) -----------------
    for n, dst in (("computerNoise_000", "computer_loop"), ("engineCircular_000", "engine_loop"),
                   ("forceField_000", "force_field_loop"), ("spaceEngineLow_000", "factory_loop"),
                   ("spaceEngine_000", "generator_loop"), ("doorOpen_000", "machine_door")):
        copy(f"{k}Sci-Fi Sounds/{n}.ogg", f"machines/{dst}.ogg")
    # ---------------- Ambiente (bucles largos) -----------------
    x, sr = sf.read(os.path.join(RAW, "stn", "fire_loop.ogg"), dtype="float32")
    write_ogg(os.path.join(SND, "ambient/fire_loop.ogg"),
              rms_normalize(loop_crossfade(to_mono(x), sr, 0.0, 24.0, 2.0), 0.12), sr, 0.35)
    record(os.path.join(SND, "ambient/fire_loop.ogg"), "stn/fire_loop.ogg", "bucle de 24 s con fundido cíclico")
    split_sprite("owl_horned", "ambient/owl", slices, [0, 2], quality=0.35, peak=0.6)
    split_sprite("tree_creak", "ambient/tree_creak", slices, [6, 7], quality=0.35, peak=0.6)
    amb = {  # archivo: (inicio, duración, fundido, rms)
        "birds": (5.0, 46.0, 3.0, 0.06, "ambient/day_birds.ogg"),
        "crickets": (30.0, 46.0, 3.0, 0.05, "ambient/night_crickets.ogg"),
        "waves": (25.0, 40.0, 4.0, 0.07, "ambient/beach_waves.ogg"),
        "stream": (10.0, 30.0, 3.0, 0.06, "ambient/river_stream.ogg"),
        "wind": (20.0, 36.0, 4.0, 0.05, "ambient/wind.ogg"),
    }
    for name, (st, du, xf, rms, dst) in amb.items():
        x, sr = sf.read(os.path.join(RAW, "omarchy", name + ".ogg"), dtype="float32")
        y = resample(to_mono(x), sr, 32000)
        y = rms_normalize(loop_crossfade(y, 32000, st, du, xf), rms)
        write_ogg(os.path.join(SND, dst), y, 32000, 0.25)
        record(os.path.join(SND, dst), f"omarchy/{name}.ogg", f"recorte de {du:.0f} s en bucle, mono 32 kHz")
    weather_audio()
    # ---------------- Música -----------------
    for src, dst in (("freepd/Connecting Rainbows.mp3", "day_connecting_rainbows.ogg"),
                     ("freepd/Midnight in the Green House.mp3", "night_midnight_green_house.ogg")):
        x, sr = sf.read(os.path.join(RAW, src), dtype="float32")
        x = fade(rms_normalize(x, 0.12), sr, 0.01, 2.5)
        write_ogg(os.path.join(MUS, dst), x, sr, 0.3)
        record(os.path.join(MUS, dst), src, "convertido de MP3 a OGG")
    for src, dst in (("Night at the Beach", "night_at_the_beach.ogg"), ("Farm Frolics", "day_farm_frolics.ogg"),
                     ("Flowing Rocks", "day_flowing_rocks.ogg"), ("Infinite Descent", "danger_infinite_descent.ogg"),
                     ("Mishief Stroll", "day_mischief_stroll.ogg")):
        shutil.copyfile(os.path.join(RAW, "kenney/Music Loops", src + ".ogg"), out(os.path.join(MUS, dst)))
        record(os.path.join(MUS, dst), f"kenney/Music Loops/{src}.ogg")
    # Licencias de los packs de audio de Kenney
    for pack in ("Impact Sounds", "RPG Audio", "Foley Sounds", "Interface Sounds", "Digital Audio", "Sci-Fi Sounds",
                 "Music Jingles", "Music Loops"):
        shutil.copyfile(os.path.join(RAW, k + pack, "License.txt"),
                        out(os.path.join(SND, "licenses", "Kenney " + pack + " License.txt")))
    shutil.copyfile(os.path.join(RAW, "stn", "CREDITS.md"), out(os.path.join(SND, "licenses", "freesound_survive-the-night_CREDITS.md")))
    shutil.copyfile(os.path.join(RAW, "omarchy", "CREDITS.md"), out(os.path.join(SND, "licenses", "freesound_omarchy-ambient_CREDITS.md")))
    shutil.copyfile(os.path.join(RAW, "oga", "CREDITS.md"), out(os.path.join(SND, "licenses", "opengameart_renethack_CREDITS.md")))
    import json
    with open(out(os.path.join(SND, "licenses", "audio_sources.json")), "w", encoding="utf-8") as fh:
        json.dump(SOURCES, fh, ensure_ascii=False, indent=1)
    total = 0
    count = 0
    for base in (SND, MUS):
        for dp, _, fs in os.walk(base):
            for f in fs:
                if f.endswith(".ogg"):
                    total += os.path.getsize(os.path.join(dp, f))
                    count += 1
    print(f"{count} archivos OGG, {total / 1e6:.2f} MB")


def main_weather_only() -> None:
    """Regenera solo el audio del clima y lo fusiona en el registro de orígenes existente."""
    import json
    path = os.path.join(SND, "licenses", "audio_sources.json")
    entries = json.load(open(path, encoding="utf-8")) if os.path.exists(path) else []
    weather_audio()
    new_files = {e["file"] for e in SOURCES}
    entries = [e for e in entries if e["file"] not in new_files] + SOURCES
    with open(path, "w", encoding="utf-8") as fh:
        json.dump(entries, fh, ensure_ascii=False, indent=1)
    print("audio del clima:", ", ".join(sorted(new_files)))


if __name__ == "__main__":
    import sys
    if "--solo-clima" in sys.argv:
        main_weather_only()
    else:
        main()
