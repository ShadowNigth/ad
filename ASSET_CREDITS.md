# Créditos de recursos (ASSET_CREDITS)

Todos los recursos de terceros están **dentro del proyecto** (no se descarga nada en tiempo de ejecución).
Este archivo se genera con `python3 tools/generate_credits.py` a partir de los propios archivos de `assets/`,
los `License.txt`/`SOURCE.md` de cada pack y el registro `assets/sounds/licenses/audio_sources.json`.
Los recursos se descargaron con `tools/fetch_assets.py` desde espejos públicos en GitHub con commit fijado
(kenney.nl, opengameart.org y freesound.org no eran accesibles directamente desde el entorno de desarrollo);
se comprobó la licencia de cada pack en su página original y en el `License.txt` incluido.

| Licencia | Significado |
|---|---|
| CC0 1.0 | Dominio público: uso libre, también comercial, sin atribución obligatoria (se acredita por cortesía). |
| SIL OFL 1.1 | Fuentes tipográficas: uso libre; el texto de la licencia se incluye junto a la fuente. |

**Atribución obligatoria:** ninguna (todo es CC0 u OFL). Se agradece a Kenney (www.kenney.nl), Kevin MacLeod
(FreePD.com) y a los autores de Freesound y OpenGameArt listados abajo.

## 1. Modelos 3D (OBJ + MTL + texturas)

Formato original OBJ con sus `.mtl` y texturas (`Textures/colormap.png`). Autor: **Kenney**. Licencia: **CC0 1.0**.
Espejo de descarga: https://github.com/Tiddybub/3d-assets (commit 11ff708) (los 3 modelos de `weapons/` vienen del pack Mini Dungeon del mismo espejo).

### `assets/models/animals/` — Cube Pets

- Fuente: https://kenney.nl/assets/cube-pets · Licencia: CC0 1.0 (`assets/models/animals/License.txt`) · Autor: Kenney
- 24 modelos (cada uno con `.obj` + `.mtl`): `animal-beaver`, `animal-bee`, `animal-bunny`, `animal-cat`, `animal-caterpillar`, `animal-chick`, `animal-cow`, `animal-crab`, `animal-deer`, `animal-dog`, `animal-elephant`, `animal-fish`, `animal-fox`, `animal-giraffe`, `animal-hog`, `animal-koala`, `animal-lion`, `animal-monkey`, `animal-panda`, `animal-parrot`, `animal-penguin`, `animal-pig`, `animal-polar`, `animal-tiger`
- Texturas: `Textures/colormap.png`

### `assets/models/cave/` — Modular Cave Kit

- Fuente: https://kenney.nl/assets/modular-cave-kit · Licencia: CC0 1.0 (`assets/models/cave/License.txt`) · Autor: Kenney
- 7 modelos (cada uno con `.obj` + `.mtl`): `gate`, `gate-metal-bars`, `gate-rock`, `ladder`, `template-floor-detail`, `template-wall`, `template-wall-corner`
- Texturas: `Textures/colormap.png`

### `assets/models/characters/` — Mini Characters

- Fuente: https://kenney.nl/assets/mini-characters · Licencia: CC0 1.0 (`assets/models/characters/License.txt`) · Autor: Kenney
- 12 modelos (cada uno con `.obj` + `.mtl`): `character-female-a`, `character-female-b`, `character-female-c`, `character-female-d`, `character-female-e`, `character-female-f`, `character-male-a`, `character-male-b`, `character-male-c`, `character-male-d`, `character-male-e`, `character-male-f`
- Texturas: `Textures/colormap.png`

### `assets/models/crystals/` — Tower Defense Kit

- Fuente: https://kenney.nl/assets/tower-defense-kit · Licencia: CC0 1.0 (`assets/models/crystals/License.txt`) · Autor: Kenney
- 5 modelos (cada uno con `.obj` + `.mtl`): `detail-crystal`, `detail-crystal-large`, `detail-rocks`, `detail-rocks-large`, `tower-round-crystals`
- Texturas: `Textures/colormap.png`

### `assets/models/factory/` — Factory Kit

- Fuente: https://kenney.nl/assets/factory-kit · Licencia: CC0 1.0 (`assets/models/factory/License.txt`) · Autor: Kenney
- 27 modelos (cada uno con `.obj` + `.mtl`): `box-large`, `box-small`, `cog-a`, `cog-b`, `cog-c`, `conveyor`, `conveyor-corner`, `conveyor-long`, `crane`, `hopper-high-round`, `hopper-round`, `lever-single`, `machine`, `machine-bed`, `machine-fortified`, `machine-window`, `pipe-large`, `pipe-large-bend`, `piston-round`, `robot-arm-a`, `robot-arm-b`, `scanner-low`, `screen-small`, `screen-wide`, `structure-medium`, `structure-short`, `top`
- Texturas: `Textures/colormap.png`

### `assets/models/food/` — Food Kit

- Fuente: https://kenney.nl/assets/food-kit · Licencia: CC0 1.0 (`assets/models/food/License.txt`) · Autor: Kenney
- 34 modelos (cada uno con `.obj` + `.mtl`): `apple`, `bag`, `banana`, `bottle-oil`, `bowl-broth`, `bowl-soup`, `bread`, `can`, `carrot`, `cherries`, `coconut`, `coconut-half`, `corn`, `egg`, `egg-cooked`, `fish`, `fish-bones`, `grapes`, `honey`, `lemon`, `loaf`, `meat-cooked`, `meat-raw`, `meat-ribs`, `mushroom`, `mussel`, `orange`, `pineapple`, `pot-stew`, `pumpkin-basic`, `skewer`, `skewer-vegetables`, `strawberry`, `watermelon`
- Texturas: `Textures/colormap.png`

### `assets/models/graveyard/` — Graveyard Kit

- Fuente: https://kenney.nl/assets/graveyard-kit · Licencia: CC0 1.0 (`assets/models/graveyard/License.txt`) · Autor: Kenney
- 35 modelos (cada uno con `.obj` + `.mtl`): `altar-stone`, `candle`, `candle-multiple`, `character-ghost`, `character-keeper`, `character-skeleton`, `character-vampire`, `character-zombie`, `cross-wood`, `crypt-door`, `crypt-small`, `crypt-small-roof`, `debris`, `debris-wood`, `fire-basket`, `gravestone-broken`, `gravestone-cross`, `gravestone-round`, `hay-bale`, `hay-bale-bundled`, `iron-fence`, `iron-fence-damaged`, `lantern-candle`, `lantern-glass`, `pillar-obelisk`, `pine-crooked`, `pumpkin`, `pumpkin-carved`, `rocks`, `rocks-tall`, `shovel`, `shovel-dirt`, `trunk`, `trunk-long`, `urn-round`
- Texturas: `Textures/colormap.png`

### `assets/models/nature/` — Nature Kit

- Fuente: https://kenney.nl/assets/nature-kit · Licencia: CC0 1.0 (`assets/models/nature/License.txt`) · Autor: Kenney
- 139 modelos (cada uno con `.obj` + `.mtl`): `bed`, `bridge_wood`, `bridge_woodNarrow`, `campfire_bricks`, `campfire_logs`, `campfire_stones`, `canoe`, `canoe_paddle`, `cliff_blockCave_rock`, `cliff_blockHalf_rock`, `cliff_block_rock`, `cliff_block_stone`, `cliff_cave_rock`, `cliff_cave_stone`, `cliff_cornerLarge_rock`, `cliff_corner_rock`, `cliff_corner_stone`, `cliff_half_rock`, `cliff_large_rock`, `cliff_large_stone`, `cliff_rock`, `cliff_steps_rock`, `cliff_top_rock`, `cliff_waterfall_rock`, `crop_carrot`, `crop_melon`, `crop_pumpkin`, `crop_turnip`, `crops_bambooStageA`, `crops_bambooStageB`, `crops_cornStageA`, `crops_cornStageB`, `crops_cornStageC`, `crops_cornStageD`, `crops_dirtDoubleRow`, `crops_dirtRow`, `crops_dirtSingle`, `crops_leafsStageA`, `crops_leafsStageB`, `crops_wheatStageA`, `crops_wheatStageB`, `fence_gate`, `fence_planks`, `fence_simple`, `fence_simpleHigh`, `flower_purpleA`, `flower_purpleB`, `flower_redA`, `flower_redB`, `flower_yellowA`, `flower_yellowB`, `grass`, `grass_large`, `grass_leafs`, `grass_leafsLarge`, `hanging_moss`, `lily_large`, `lily_small`, `log`, `log_large`, `log_stack`, `log_stackLarge`, `mushroom_red`, `mushroom_redGroup`, `mushroom_redTall`, `mushroom_tan`, `mushroom_tanGroup`, `path_stone`, `path_stoneCircle`, `path_wood`, `plant_bush`, `plant_bushDetailed`, `plant_bushLarge`, `plant_bushSmall`, `plant_bushTriangle`, `plant_flatShort`, `plant_flatTall`, `platform_beach`, `platform_grass`, `pot_large`, `pot_small`, `rock_largeA`, `rock_largeB`, `rock_largeC`, `rock_largeD`, `rock_smallA`, `rock_smallB`, `rock_smallC`, `rock_smallD`, `rock_smallFlatA`, `rock_smallTopA`, `rock_tallA`, `rock_tallB`, `rock_tallC`, `sign`, `statue_block`, `statue_column`, `statue_columnDamaged`, `statue_head`, `statue_obelisk`, `statue_ring`, `stone_largeA`, `stone_largeB`, `stone_largeC`, `stone_smallA`, `stone_smallB`, `stone_smallC`, `stone_smallFlatA`, `stone_tallA`, `stone_tallB`, `stump_old`, `stump_round`, `stump_roundDetailed`, `tent_detailedClosed`, `tent_detailedOpen`, `tent_smallClosed`, `tent_smallOpen`, `tree_cone`, `tree_default`, `tree_default_dark`, `tree_detailed`, `tree_detailed_dark`, `tree_fat`, `tree_oak`, `tree_oak_dark`, `tree_palm`, `tree_palmBend`, `tree_palmDetailedShort`, `tree_palmDetailedTall`, `tree_palmShort`, `tree_palmTall`, `tree_pineDefaultA`, `tree_pineRoundA`, `tree_pineRoundC`, `tree_pineTallA`, `tree_simple`, `tree_tall`, `tree_tall_dark`, `tree_thin`

### `assets/models/pirate/` — Pirate Kit

- Fuente: https://kenney.nl/assets/pirate-kit · Licencia: CC0 1.0 (`assets/models/pirate/License.txt`) · Autor: Kenney
- 32 modelos (cada uno con `.obj` + `.mtl`): `barrel`, `boat-row-large`, `boat-row-small`, `bottle-large`, `cannon`, `cannon-ball`, `chest`, `crate`, `crate-bottles`, `flag`, `flag-pirate`, `grass-plant`, `hole`, `mast`, `palm-bend`, `palm-detailed-bend`, `palm-detailed-straight`, `palm-straight`, `patch-grass-foliage`, `patch-sand`, `patch-sand-foliage`, `rocks-a`, `rocks-b`, `rocks-sand-a`, `rocks-sand-b`, `rocks-sand-c`, `ship-wreck`, `structure-platform`, `structure-platform-dock`, `structure-platform-dock-small`, `tool-shovel`, `tower-watch`
- Texturas: `Textures/colormap.png`

### `assets/models/station/` — Space Station Kit

- Fuente: https://kenney.nl/assets/space-station-kit · Licencia: CC0 1.0 (`assets/models/station/License.txt`) · Autor: Kenney
- 6 modelos (cada uno con `.obj` + `.mtl`): `computer-screen`, `computer-system`, `container`, `container-tall`, `display-wall`, `table-display`
- Texturas: `Textures/colormap.png`

### `assets/models/survival/` — Survival Kit

- Fuente: https://kenney.nl/assets/survival-kit · Licencia: CC0 1.0 (`assets/models/survival/License.txt`) · Autor: Kenney
- 80 modelos (cada uno con `.obj` + `.mtl`): `barrel`, `barrel-open`, `bedroll`, `bedroll-frame`, `bedroll-packed`, `bottle`, `bottle-large`, `box`, `box-large`, `box-large-open`, `box-open`, `bucket`, `campfire-fishing-stand`, `campfire-pit`, `campfire-stand`, `chest`, `fence`, `fence-doorway`, `fence-fortified`, `fish`, `fish-large`, `floor`, `floor-hole`, `floor-old`, `grass`, `grass-large`, `metal-panel`, `metal-panel-narrow`, `metal-panel-screws`, `metal-panel-screws-half`, `metal-panel-screws-narrow`, `patch-grass`, `patch-grass-large`, `resource-planks`, `resource-stone`, `resource-stone-large`, `resource-wood`, `rock-a`, `rock-b`, `rock-c`, `rock-flat`, `rock-flat-grass`, `rock-sand-a`, `rock-sand-b`, `rock-sand-c`, `signpost`, `signpost-single`, `structure`, `structure-canvas`, `structure-floor`, `structure-metal`, `structure-metal-doorway`, `structure-metal-floor`, `structure-metal-roof`, `structure-metal-wall`, `structure-roof`, `tent`, `tent-canvas`, `tent-canvas-half`, `tool-axe`, `tool-axe-upgraded`, `tool-hammer`, `tool-hammer-upgraded`, `tool-hoe`, `tool-hoe-upgraded`, `tool-pickaxe`, `tool-pickaxe-upgraded`, `tool-shovel`, `tool-shovel-upgraded`, `tree`, `tree-autumn`, `tree-autumn-tall`, `tree-autumn-trunk`, `tree-log`, `tree-log-small`, `tree-tall`, `tree-trunk`, `workbench`, `workbench-anvil`, `workbench-grind`
- Texturas: `Textures/colormap.png`

### `assets/models/town/` — Fantasy Town Kit

- Fuente: https://kenney.nl/assets/fantasy-town-kit · Licencia: CC0 1.0 (`assets/models/town/License.txt`) · Autor: Kenney
- 53 modelos (cada uno con `.obj` + `.mtl`): `banner-green`, `banner-red`, `blade`, `cart`, `cart-high`, `chimney`, `chimney-base`, `chimney-top`, `fence`, `fence-gate`, `fountain-round`, `fountain-round-detail`, `hedge`, `hedge-large`, `lantern`, `overhang`, `pillar-stone`, `pillar-wood`, `planks`, `planks-half`, `poles`, `rock-large`, `roof`, `roof-corner`, `roof-flat`, `roof-gable`, `roof-gable-end`, `roof-high`, `roof-high-gable`, `roof-point`, `stairs-wood`, `stall`, `stall-bench`, `stall-green`, `stall-red`, `stall-stool`, `tree-crooked`, `tree-high-round`, `wall`, `wall-corner`, `wall-door`, `wall-half`, `wall-window-shutters`, `wall-wood`, `wall-wood-corner`, `wall-wood-door`, `wall-wood-half`, `wall-wood-window-shutters`, `wall-wood-window-small`, `watermill`, `watermill-wide`, `wheel`, `windmill`
- Texturas: `Textures/colormap.png`

### `assets/models/weapons/` — Mini Dungeon

- Fuente: https://kenney.nl/assets/mini-dungeon · Licencia: CC0 1.0 (`assets/models/weapons/License.txt`) · Autor: Kenney
- 5 modelos (cada uno con `.obj` + `.mtl`): `barrel`, `chest`, `shield-round`, `weapon-spear`, `weapon-sword`
- Texturas: `Textures/colormap.png`

## 2. Interfaz, controles táctiles, iconos y fuentes

### `assets/textures/ui/` — Kenney — UI Pack: Adventure

- Fuente: https://kenney.nl/assets/ui-pack-adventure · Licencia: CC0 1.0 · Autor: Kenney · Espejo: https://github.com/shorepine/kenney (commit 3694c68)
- 47 archivos: `banner_hanging.png`, `banner_modern.png`, `button_brown.png`, `button_brown_close.png`, `button_grey.png`, `button_red.png`, `checkbox_brown_checked.png`, `checkbox_brown_empty.png`, `hexagon_brown.png`, `hexagon_grey.png`, `minimap_arrow_a.png`, `minimap_icon_exclamation_red.png`, `minimap_icon_exclamation_yellow.png`, `minimap_icon_jewel_white.png`, `minimap_icon_star_white.png`, `minimap_icon_star_yellow.png`, `minimap_ring_brown.png`, `panel_border_brown.png`, `panel_border_brown_detail.png`, `panel_brown.png`, `panel_brown_corners_a.png`, `panel_brown_damaged.png`, `panel_brown_dark.png`, `panel_grey.png`, `panel_grey_dark.png`, `panel_grid_paper.png`, `pattern_grid_paper.png`, `progress_blue.png`, `progress_blue_border.png`, `progress_blue_small.png`, `progress_green.png`, `progress_green_border.png`, `progress_green_small.png`, `progress_red.png`, `progress_red_border.png`, `progress_red_small.png`, `progress_transparent.png`, `progress_transparent_small.png`, `progress_white.png`, `progress_white_border.png`, `progress_white_small.png`, `round_brown.png`, `round_brown_dark.png`, `round_grey.png`, `round_grey_dark.png`, `scrollbar_brown.png`, `scrollbar_brown_small.png`

### `assets/textures/controls/` — Kenney — Mobile Controls

- Fuente: https://kenney.nl/assets/mobile-controls · Licencia: CC0 1.0 · Autor: Kenney · Espejo: https://github.com/shorepine/kenney (commit 3694c68)
- 33 archivos: `button_circle.png`, `button_circle_highlight.png`, `button_hexagon.png`, `button_hexagon_highlight.png`, `button_square.png`, `button_square_highlight.png`, `icon_arrow.png`, `icon_arrow_curved.png`, `icon_arrow_rotate.png`, `icon_burst.png`, `icon_checkmark.png`, `icon_cog.png`, `icon_cross.png`, `icon_fire.png`, `icon_hand.png`, `icon_jump.png`, `icon_key.png`, `icon_lock.png`, `icon_menu.png`, `icon_money.png`, `icon_pause.png`, `icon_save.png`, `icon_search.png`, `icon_shield.png`, `icon_skull.png`, `icon_star.png`, `icon_sword.png`, `icon_target.png`, `icon_wrench.png`, `joystick_circle_nub_a.png`, `joystick_circle_nub_highlight.png`, `joystick_circle_pad_a.png`, `joystick_circle_pad_highlight.png`

### `assets/icons/ui/` — Kenney — Game Icons

- Fuente: https://kenney.nl/assets/game-icons · Licencia: CC0 1.0 · Autor: Kenney · Espejo: https://github.com/shorepine/kenney (commit 3694c68)
- 44 archivos: `arrowLeft.png`, `arrowRight.png`, `audioOff.png`, `audioOn.png`, `barsVertical.png`, `checkmark.png`, `cross.png`, `exclamation.png`, `exit.png`, `fastForward.png`, `gear.png`, `home.png`, `information.png`, `larger.png`, `leaderboardsSimple.png`, `locked.png`, `medal1.png`, `menuGrid.png`, `menuList.png`, `minus.png`, `multiplayer.png`, `musicOff.png`, `musicOn.png`, `next.png`, `open.png`, `pause.png`, `plus.png`, `power.png`, `previous.png`, `question.png`, `return.png`, `save.png`, `shoppingBasket.png`, `singleplayer.png`, `star.png`, `target.png`, `trashcan.png`, `trophy.png`, `unlocked.png`, `warning.png`, `wrench.png`, `zoom.png`, `zoomIn.png`, `zoomOut.png`

### `assets/icons/items/` — iconos de objetos del inventario

- Renderizados para este proyecto con `tools/render_icons.py` a partir de los modelos OBJ de Kenney listados arriba
  (obra derivada de recursos CC0; se distribuyen también como CC0).
- 47 archivos: `acero.png`, `agua.png`, `agua_sucia.png`, `azada.png`, `bayas.png`, `calabaza.png`, `carbon.png`, `carne_cocida.png`, `carne_cruda.png`, `coco.png`, `combustible.png`, `cristal.png`, `cubo.png`, `cuenco_coco.png`, `cuerda.png`, `cuero.png`, `electronica.png`, `esencia.png`, `fibra.png`, `guiso.png`, `hacha_acero.png`, `hacha_hierro.png`, `hacha_piedra.png`, `hierbas.png`, `hongo.png`, `hueso.png`, `huevo.png`, `lanza.png`, `lanza_hierro.png`, `lingote_hierro.png`, `machete.png`, `madera.png`, `maiz.png`, `martillo.png`, `medicina.png`, `mineral_hierro.png`, `pescado.png`, `pescado_asado.png`, `pico_acero.png`, `pico_hierro.png`, `pico_piedra.png`, `piedra.png`, `piezas.png`, `reliquia.png`, `tablas.png`, `venda.png`, `zanahoria.png`

### `assets/icons/buildings/` — iconos de edificios

- Renderizados para este proyecto con `tools/render_icons.py` a partir de los modelos OBJ de Kenney listados arriba
  (obra derivada de recursos CC0; se distribuyen también como CC0).
- 21 archivos: `almacen.png`, `antorcha.png`, `aserradero.png`, `cabana.png`, `cantera.png`, `carbonera.png`, `choza.png`, `fabrica.png`, `fogata.png`, `fundicion.png`, `generador.png`, `granja.png`, `huerto.png`, `laboratorio.png`, `lenador.png`, `mina.png`, `purificador.png`, `refineria.png`, `refugio.png`, `taller.png`, `torre.png`

### `assets/fonts/`

- `Fredoka.ttf` — Fredoka, © The Fredoka Project Authors, SIL Open Font License 1.1 (`Fredoka-OFL.txt`). Fuente: https://fonts.google.com/specimen/Fredoka · Espejo: https://github.com/google/fonts (commit 47d54ca) (`ofl/fredoka`).
- `Nunito.ttf` — Nunito, © The Nunito Project Authors, SIL Open Font License 1.1 (`Nunito-OFL.txt`). Fuente: https://fonts.google.com/specimen/Nunito · Espejo: https://github.com/google/fonts (commit 47d54ca) (`ofl/nunito`).

### Recursos propios del proyecto

- `icon.svg` (icono de la aplicación), `assets/shaders/*.gdshader` (agua y barras), el terreno, el agua y la
  disposición de la isla se generan con el código de este proyecto (sin recursos de terceros).
- `assets/icons/app/` — iconos del lanzador (Android adaptable y Windows), rasterizados desde `icon.svg` con
  `Image.load_svg_from_string` de Godot: `adaptive_background_432.png`, `adaptive_foreground_432.png`, `icon_192.png`, `icon_512.png`.
- `tools/android/isla_salvaje_publica.keystore` — clave de firma generada con `tools/create_android_keystore.py`.

## 3. Efectos de sonido, ambiente y música

Formato OGG Vorbis. Algunos archivos se recortaron, se pasaron a mono, se normalizaron o se separaron en
tomas individuales con `tools/process_audio.py` (permitido por CC0). Copias de las licencias y créditos de
origen en `assets/sounds/licenses/`.

| Archivo | Origen | Autor | Licencia | Notas |
|---|---|---|---|---|
| `sounds/footsteps/grass_0.ogg` | Kenney — Impact Sounds: `footstep_grass_000.ogg` · https://kenney.nl/assets/impact-sounds | Kenney | CC0 1.0 |  |
| `sounds/footsteps/stone_0.ogg` | Kenney — Impact Sounds: `footstep_concrete_000.ogg` · https://kenney.nl/assets/impact-sounds | Kenney | CC0 1.0 |  |
| `sounds/footsteps/wood_0.ogg` | Kenney — Impact Sounds: `footstep_wood_000.ogg` · https://kenney.nl/assets/impact-sounds | Kenney | CC0 1.0 |  |
| `sounds/footsteps/sand_0.ogg` | Kenney — Impact Sounds: `footstep_snow_000.ogg` · https://kenney.nl/assets/impact-sounds | Kenney | CC0 1.0 |  |
| `sounds/footsteps/dirt_0.ogg` | Kenney — RPG Audio: `footstep00.ogg` · https://kenney.nl/assets/rpg-audio | Kenney | CC0 1.0 |  |
| `sounds/footsteps/grass_1.ogg` | Kenney — Impact Sounds: `footstep_grass_001.ogg` · https://kenney.nl/assets/impact-sounds | Kenney | CC0 1.0 |  |
| `sounds/footsteps/stone_1.ogg` | Kenney — Impact Sounds: `footstep_concrete_001.ogg` · https://kenney.nl/assets/impact-sounds | Kenney | CC0 1.0 |  |
| `sounds/footsteps/wood_1.ogg` | Kenney — Impact Sounds: `footstep_wood_001.ogg` · https://kenney.nl/assets/impact-sounds | Kenney | CC0 1.0 |  |
| `sounds/footsteps/sand_1.ogg` | Kenney — Impact Sounds: `footstep_snow_001.ogg` · https://kenney.nl/assets/impact-sounds | Kenney | CC0 1.0 |  |
| `sounds/footsteps/dirt_1.ogg` | Kenney — RPG Audio: `footstep01.ogg` · https://kenney.nl/assets/rpg-audio | Kenney | CC0 1.0 |  |
| `sounds/footsteps/grass_2.ogg` | Kenney — Impact Sounds: `footstep_grass_002.ogg` · https://kenney.nl/assets/impact-sounds | Kenney | CC0 1.0 |  |
| `sounds/footsteps/stone_2.ogg` | Kenney — Impact Sounds: `footstep_concrete_002.ogg` · https://kenney.nl/assets/impact-sounds | Kenney | CC0 1.0 |  |
| `sounds/footsteps/wood_2.ogg` | Kenney — Impact Sounds: `footstep_wood_002.ogg` · https://kenney.nl/assets/impact-sounds | Kenney | CC0 1.0 |  |
| `sounds/footsteps/sand_2.ogg` | Kenney — Impact Sounds: `footstep_snow_002.ogg` · https://kenney.nl/assets/impact-sounds | Kenney | CC0 1.0 |  |
| `sounds/footsteps/dirt_2.ogg` | Kenney — RPG Audio: `footstep02.ogg` · https://kenney.nl/assets/rpg-audio | Kenney | CC0 1.0 |  |
| `sounds/footsteps/grass_3.ogg` | Kenney — Impact Sounds: `footstep_grass_003.ogg` · https://kenney.nl/assets/impact-sounds | Kenney | CC0 1.0 |  |
| `sounds/footsteps/stone_3.ogg` | Kenney — Impact Sounds: `footstep_concrete_003.ogg` · https://kenney.nl/assets/impact-sounds | Kenney | CC0 1.0 |  |
| `sounds/footsteps/wood_3.ogg` | Kenney — Impact Sounds: `footstep_wood_003.ogg` · https://kenney.nl/assets/impact-sounds | Kenney | CC0 1.0 |  |
| `sounds/footsteps/sand_3.ogg` | Kenney — Impact Sounds: `footstep_snow_003.ogg` · https://kenney.nl/assets/impact-sounds | Kenney | CC0 1.0 |  |
| `sounds/footsteps/dirt_3.ogg` | Kenney — RPG Audio: `footstep03.ogg` · https://kenney.nl/assets/rpg-audio | Kenney | CC0 1.0 |  |
| `sounds/footsteps/grass_4.ogg` | Kenney — Impact Sounds: `footstep_grass_004.ogg` · https://kenney.nl/assets/impact-sounds | Kenney | CC0 1.0 |  |
| `sounds/footsteps/stone_4.ogg` | Kenney — Impact Sounds: `footstep_concrete_004.ogg` · https://kenney.nl/assets/impact-sounds | Kenney | CC0 1.0 |  |
| `sounds/footsteps/wood_4.ogg` | Kenney — Impact Sounds: `footstep_wood_004.ogg` · https://kenney.nl/assets/impact-sounds | Kenney | CC0 1.0 |  |
| `sounds/footsteps/sand_4.ogg` | Kenney — Impact Sounds: `footstep_snow_004.ogg` · https://kenney.nl/assets/impact-sounds | Kenney | CC0 1.0 |  |
| `sounds/footsteps/dirt_4.ogg` | Kenney — RPG Audio: `footstep04.ogg` · https://kenney.nl/assets/rpg-audio | Kenney | CC0 1.0 |  |
| `sounds/gather/chop_0.ogg` | Kenney — RPG Audio: `chop.ogg` · https://kenney.nl/assets/rpg-audio | Kenney | CC0 1.0 |  |
| `sounds/gather/wood_hit_0.ogg` | Kenney — Impact Sounds: `impactWood_heavy_000.ogg` · https://kenney.nl/assets/impact-sounds | Kenney | CC0 1.0 |  |
| `sounds/gather/wood_hit_1.ogg` | Kenney — Impact Sounds: `impactWood_heavy_001.ogg` · https://kenney.nl/assets/impact-sounds | Kenney | CC0 1.0 |  |
| `sounds/gather/wood_hit_2.ogg` | Kenney — Impact Sounds: `impactWood_heavy_002.ogg` · https://kenney.nl/assets/impact-sounds | Kenney | CC0 1.0 |  |
| `sounds/gather/wood_light_0.ogg` | Kenney — Impact Sounds: `impactWood_medium_000.ogg` · https://kenney.nl/assets/impact-sounds | Kenney | CC0 1.0 |  |
| `sounds/gather/wood_light_1.ogg` | Kenney — Impact Sounds: `impactWood_medium_001.ogg` · https://kenney.nl/assets/impact-sounds | Kenney | CC0 1.0 |  |
| `sounds/gather/mining_0.ogg` | Kenney — Impact Sounds: `impactMining_000.ogg` · https://kenney.nl/assets/impact-sounds | Kenney | CC0 1.0 |  |
| `sounds/gather/mining_1.ogg` | Kenney — Impact Sounds: `impactMining_001.ogg` · https://kenney.nl/assets/impact-sounds | Kenney | CC0 1.0 |  |
| `sounds/gather/mining_2.ogg` | Kenney — Impact Sounds: `impactMining_002.ogg` · https://kenney.nl/assets/impact-sounds | Kenney | CC0 1.0 |  |
| `sounds/gather/mining_3.ogg` | Kenney — Impact Sounds: `impactMining_003.ogg` · https://kenney.nl/assets/impact-sounds | Kenney | CC0 1.0 |  |
| `sounds/gather/mining_4.ogg` | Kenney — Impact Sounds: `impactMining_004.ogg` · https://kenney.nl/assets/impact-sounds | Kenney | CC0 1.0 |  |
| `sounds/gather/stone_hit_0.ogg` | Kenney — Foley Sounds: `stoneHit1.ogg` · https://kenney.nl/assets/foley-sounds | Kenney | CC0 1.0 |  |
| `sounds/gather/stone_hit_1.ogg` | Kenney — Foley Sounds: `stoneHit2.ogg` · https://kenney.nl/assets/foley-sounds | Kenney | CC0 1.0 |  |
| `sounds/gather/stone_hit_2.ogg` | Kenney — Foley Sounds: `stoneHit3.ogg` · https://kenney.nl/assets/foley-sounds | Kenney | CC0 1.0 |  |
| `sounds/gather/rock_break_0.ogg` | Kenney — Foley Sounds: `rockHit1.ogg` · https://kenney.nl/assets/foley-sounds | Kenney | CC0 1.0 |  |
| `sounds/gather/rock_break_1.ogg` | Kenney — Foley Sounds: `rockHit2.ogg` · https://kenney.nl/assets/foley-sounds | Kenney | CC0 1.0 |  |
| `sounds/gather/rock_break_2.ogg` | Kenney — Foley Sounds: `stonesHit1.ogg` · https://kenney.nl/assets/foley-sounds | Kenney | CC0 1.0 |  |
| `sounds/gather/ore_hit_0.ogg` | Kenney — Foley Sounds: `swordStone1.ogg` · https://kenney.nl/assets/foley-sounds | Kenney | CC0 1.0 |  |
| `sounds/gather/ore_hit_1.ogg` | Kenney — Foley Sounds: `swordStone2.ogg` · https://kenney.nl/assets/foley-sounds | Kenney | CC0 1.0 |  |
| `sounds/gather/pickup_0.ogg` | Kenney — RPG Audio: `handleSmallLeather.ogg` · https://kenney.nl/assets/rpg-audio | Kenney | CC0 1.0 |  |
| `sounds/gather/pickup_1.ogg` | Kenney — RPG Audio: `handleSmallLeather2.ogg` · https://kenney.nl/assets/rpg-audio | Kenney | CC0 1.0 |  |
| `sounds/gather/bush_rustle_0.ogg` | Freesound 106114 «bushmovement.wav» https://freesound.org/people/j1987/sounds/106114/; Freesound 445788 «Rustling foliage.WAV» https://freesound.org/people/DDT197/sounds/445788/; Freesound 59315 «looking_in_bushes.wav» https://freesound.org/people/vibe_crc/sounds/59315/; Freesound 635053 «Rustling Foliage in Forest» https://freesound.org/people/sillygrizzlies/sounds/635053/ | DDT197, j1987, sillygrizzlies, vibe_crc | CC0 1.0 | toma 1 de 8 |
| `sounds/gather/bush_rustle_1.ogg` | Freesound 106114 «bushmovement.wav» https://freesound.org/people/j1987/sounds/106114/; Freesound 445788 «Rustling foliage.WAV» https://freesound.org/people/DDT197/sounds/445788/; Freesound 59315 «looking_in_bushes.wav» https://freesound.org/people/vibe_crc/sounds/59315/; Freesound 635053 «Rustling Foliage in Forest» https://freesound.org/people/sillygrizzlies/sounds/635053/ | DDT197, j1987, sillygrizzlies, vibe_crc | CC0 1.0 | toma 3 de 8 |
| `sounds/gather/bush_rustle_2.ogg` | Freesound 106114 «bushmovement.wav» https://freesound.org/people/j1987/sounds/106114/; Freesound 445788 «Rustling foliage.WAV» https://freesound.org/people/DDT197/sounds/445788/; Freesound 59315 «looking_in_bushes.wav» https://freesound.org/people/vibe_crc/sounds/59315/; Freesound 635053 «Rustling Foliage in Forest» https://freesound.org/people/sillygrizzlies/sounds/635053/ | DDT197, j1987, sillygrizzlies, vibe_crc | CC0 1.0 | toma 6 de 8 |
| `sounds/gather/branch_snap_0.ogg` | Freesound 152413 «Stick_Snap1.wav» https://freesound.org/people/burnsie289/sounds/152413/; Freesound 369986 «Branches snapping_northern87» https://freesound.org/people/northern87/sounds/369986/; Freesound 392009 «SNAP SMALL BRANCHES AND STICKS.wav» https://freesound.org/people/burbujafilms/sounds/392009/; Freesound 452570 «branch breaking forest twig snap crunch.wav» https://freesound.org/people/kyles/sounds/452570/ | burbujafilms, burnsie289, kyles, northern87 | CC0 1.0 | toma 1 de 14 |
| `sounds/gather/branch_snap_1.ogg` | Freesound 152413 «Stick_Snap1.wav» https://freesound.org/people/burnsie289/sounds/152413/; Freesound 369986 «Branches snapping_northern87» https://freesound.org/people/northern87/sounds/369986/; Freesound 392009 «SNAP SMALL BRANCHES AND STICKS.wav» https://freesound.org/people/burbujafilms/sounds/392009/; Freesound 452570 «branch breaking forest twig snap crunch.wav» https://freesound.org/people/kyles/sounds/452570/ | burbujafilms, burnsie289, kyles, northern87 | CC0 1.0 | toma 2 de 14 |
| `sounds/gather/branch_snap_2.ogg` | Freesound 152413 «Stick_Snap1.wav» https://freesound.org/people/burnsie289/sounds/152413/; Freesound 369986 «Branches snapping_northern87» https://freesound.org/people/northern87/sounds/369986/; Freesound 392009 «SNAP SMALL BRANCHES AND STICKS.wav» https://freesound.org/people/burbujafilms/sounds/392009/; Freesound 452570 «branch breaking forest twig snap crunch.wav» https://freesound.org/people/kyles/sounds/452570/ | burbujafilms, burnsie289, kyles, northern87 | CC0 1.0 | toma 3 de 14 |
| `sounds/gather/branch_snap_3.ogg` | Freesound 152413 «Stick_Snap1.wav» https://freesound.org/people/burnsie289/sounds/152413/; Freesound 369986 «Branches snapping_northern87» https://freesound.org/people/northern87/sounds/369986/; Freesound 392009 «SNAP SMALL BRANCHES AND STICKS.wav» https://freesound.org/people/burbujafilms/sounds/392009/; Freesound 452570 «branch breaking forest twig snap crunch.wav» https://freesound.org/people/kyles/sounds/452570/ | burbujafilms, burnsie289, kyles, northern87 | CC0 1.0 | toma 5 de 14 |
| `sounds/gather/tree_fall_0.ogg` | Freesound 494071 «Big Tree Fall in Forest» https://freesound.org/people/Kinoton/sounds/494071/; Freesound 798282 «The fall of a small ten-meter pine tree» https://freesound.org/people/Walking.With.Microphones/sounds/798282/ | Kinoton, Walking.With.Microphones | CC0 1.0 | toma 2 de 2 |
| `sounds/gather/sticks_0.ogg` | Freesound 457263 «Sticks Dropping.WAV» https://freesound.org/people/kylecutsfilms/sounds/457263/ | kylecutsfilms | CC0 1.0 | toma 3 de 8 |
| `sounds/gather/sticks_1.ogg` | Freesound 457263 «Sticks Dropping.WAV» https://freesound.org/people/kylecutsfilms/sounds/457263/ | kylecutsfilms | CC0 1.0 | toma 4 de 8 |
| `sounds/combat/punch_heavy_0.ogg` | Kenney — Impact Sounds: `impactPunch_heavy_000.ogg` · https://kenney.nl/assets/impact-sounds | Kenney | CC0 1.0 |  |
| `sounds/combat/punch_medium_0.ogg` | Kenney — Impact Sounds: `impactPunch_medium_000.ogg` · https://kenney.nl/assets/impact-sounds | Kenney | CC0 1.0 |  |
| `sounds/combat/soft_hit_0.ogg` | Kenney — Impact Sounds: `impactSoft_heavy_000.ogg` · https://kenney.nl/assets/impact-sounds | Kenney | CC0 1.0 |  |
| `sounds/combat/draw_0.ogg` | Kenney — RPG Audio: `drawKnife1.ogg` · https://kenney.nl/assets/rpg-audio | Kenney | CC0 1.0 |  |
| `sounds/combat/punch_heavy_1.ogg` | Kenney — Impact Sounds: `impactPunch_heavy_001.ogg` · https://kenney.nl/assets/impact-sounds | Kenney | CC0 1.0 |  |
| `sounds/combat/punch_medium_1.ogg` | Kenney — Impact Sounds: `impactPunch_medium_001.ogg` · https://kenney.nl/assets/impact-sounds | Kenney | CC0 1.0 |  |
| `sounds/combat/soft_hit_1.ogg` | Kenney — Impact Sounds: `impactSoft_heavy_001.ogg` · https://kenney.nl/assets/impact-sounds | Kenney | CC0 1.0 |  |
| `sounds/combat/draw_1.ogg` | Kenney — RPG Audio: `drawKnife2.ogg` · https://kenney.nl/assets/rpg-audio | Kenney | CC0 1.0 |  |
| `sounds/combat/woosh_0.ogg` | Kenney — Foley Sounds: `woosh1.ogg` · https://kenney.nl/assets/foley-sounds | Kenney | CC0 1.0 |  |
| `sounds/combat/woosh_1.ogg` | Kenney — Foley Sounds: `woosh2.ogg` · https://kenney.nl/assets/foley-sounds | Kenney | CC0 1.0 |  |
| `sounds/combat/woosh_2.ogg` | Kenney — Foley Sounds: `woosh3.ogg` · https://kenney.nl/assets/foley-sounds | Kenney | CC0 1.0 |  |
| `sounds/combat/woosh_3.ogg` | Kenney — Foley Sounds: `woosh4.ogg` · https://kenney.nl/assets/foley-sounds | Kenney | CC0 1.0 |  |
| `sounds/combat/swing_0.ogg` | Freesound 422513 «Swinging staff whoosh (strong) 04.wav» https://freesound.org/people/Nightflame/sounds/422513/; Freesound 719636 «Fast whoosh, bamboo swoosh through air, version 1» https://freesound.org/people/zapsplat.com/sounds/719636/; Freesound 719637 «Fast whoosh, bamboo swoosh through air, version 2» https://freesound.org/people/zapsplat.com/sounds/719637/; Freesound 855844 «Whoosh - Long Bamboo stick - OS ST 13» https://freesound.org/people/Sadiquecat/sounds/855844/ | Nightflame, Sadiquecat, zapsplat.com | CC0 1.0 | toma 1 de 4 |
| `sounds/combat/swing_1.ogg` | Freesound 422513 «Swinging staff whoosh (strong) 04.wav» https://freesound.org/people/Nightflame/sounds/422513/; Freesound 719636 «Fast whoosh, bamboo swoosh through air, version 1» https://freesound.org/people/zapsplat.com/sounds/719636/; Freesound 719637 «Fast whoosh, bamboo swoosh through air, version 2» https://freesound.org/people/zapsplat.com/sounds/719637/; Freesound 855844 «Whoosh - Long Bamboo stick - OS ST 13» https://freesound.org/people/Sadiquecat/sounds/855844/ | Nightflame, Sadiquecat, zapsplat.com | CC0 1.0 | toma 2 de 4 |
| `sounds/combat/swing_2.ogg` | Freesound 422513 «Swinging staff whoosh (strong) 04.wav» https://freesound.org/people/Nightflame/sounds/422513/; Freesound 719636 «Fast whoosh, bamboo swoosh through air, version 1» https://freesound.org/people/zapsplat.com/sounds/719636/; Freesound 719637 «Fast whoosh, bamboo swoosh through air, version 2» https://freesound.org/people/zapsplat.com/sounds/719637/; Freesound 855844 «Whoosh - Long Bamboo stick - OS ST 13» https://freesound.org/people/Sadiquecat/sounds/855844/ | Nightflame, Sadiquecat, zapsplat.com | CC0 1.0 | toma 3 de 4 |
| `sounds/combat/swing_3.ogg` | Freesound 422513 «Swinging staff whoosh (strong) 04.wav» https://freesound.org/people/Nightflame/sounds/422513/; Freesound 719636 «Fast whoosh, bamboo swoosh through air, version 1» https://freesound.org/people/zapsplat.com/sounds/719636/; Freesound 719637 «Fast whoosh, bamboo swoosh through air, version 2» https://freesound.org/people/zapsplat.com/sounds/719637/; Freesound 855844 «Whoosh - Long Bamboo stick - OS ST 13» https://freesound.org/people/Sadiquecat/sounds/855844/ | Nightflame, Sadiquecat, zapsplat.com | CC0 1.0 | toma 4 de 4 |
| `sounds/combat/hit_flesh_0.ogg` | Freesound 264062 «Melee Weapon hit with male moan & body fall» https://freesound.org/people/Paul368/sounds/264062/; Freesound 460509 «Hitting in a Face» https://freesound.org/people/florianreichelt/sounds/460509/ | Paul368, florianreichelt | CC0 1.0 | toma 2 de 5 |
| `sounds/combat/hit_flesh_1.ogg` | Freesound 264062 «Melee Weapon hit with male moan & body fall» https://freesound.org/people/Paul368/sounds/264062/; Freesound 460509 «Hitting in a Face» https://freesound.org/people/florianreichelt/sounds/460509/ | Paul368, florianreichelt | CC0 1.0 | toma 4 de 5 |
| `sounds/combat/body_fall_0.ogg` | Freesound 504626 «BODY FALL - V HVY - DIRT» https://freesound.org/people/leonelmail/sounds/504626/; Freesound 346694 «Body fall_02.wav» https://freesound.org/people/deleted_user_2104797/sounds/346694/ | deleted_user_2104797, leonelmail | CC0 1.0 | toma 1 de 2 |
| `sounds/combat/player_hurt_0.ogg` | Freesound 547203 «Voice_AdultMale_PainGrunts_01.wav» https://freesound.org/people/MrFossy/sounds/547203/; Freesound 547202 «Voice_AdultMale_PainGrunts_02.wav» https://freesound.org/people/MrFossy/sounds/547202/; Freesound 547201 «Voice_AdultMale_PainGrunts_03.wav» https://freesound.org/people/MrFossy/sounds/547201/; Freesound 547200 «Voice_AdultMale_PainGrunts_04.wav» https://freesound.org/people/MrFossy/sounds/547200/; Freesound 547207 «Voice_AdultMale_PainGrunts_05.wav» https://freesound.org/people/MrFossy/sounds/547207/; Freesound 547206 «Voice_AdultMale_PainGrunts_06.wav» https://freesound.org/people/MrFossy/sounds/547206/; Freesound 547205 «Voice_AdultMale_PainGrunts_07.wav» https://freesound.org/people/MrFossy/sounds/547205/; Freesound 547204 «Voice_AdultMale_PainGrunts_08.wav» https://freesound.org/people/MrFossy/sounds/547204/; Freesound 547209 «Voice_AdultMale_PainGrunts_09.wav» https://freesound.org/people/MrFossy/sounds/547209/; Freesound 547208 «Voice_AdultMale_PainGrunts_10.wav» https://freesound.org/people/MrFossy/sounds/547208/; Freesound 547194 «Voice_AdultMale_PainGrunts_11.wav» https://freesound.org/people/MrFossy/sounds/547194/; Freesound 547195 «Voice_AdultMale_PainGrunts_12.wav» https://freesound.org/people/MrFossy/sounds/547195/; Freesound 547193 «Voice_AdultMale_PainGrunts_14.wav» https://freesound.org/people/MrFossy/sounds/547193/; Freesound 547198 «Voice_AdultMale_PainGrunts_15.wav» https://freesound.org/people/MrFossy/sounds/547198/ | MrFossy | CC0 1.0 | toma 1 de 14 |
| `sounds/combat/player_hurt_1.ogg` | Freesound 547203 «Voice_AdultMale_PainGrunts_01.wav» https://freesound.org/people/MrFossy/sounds/547203/; Freesound 547202 «Voice_AdultMale_PainGrunts_02.wav» https://freesound.org/people/MrFossy/sounds/547202/; Freesound 547201 «Voice_AdultMale_PainGrunts_03.wav» https://freesound.org/people/MrFossy/sounds/547201/; Freesound 547200 «Voice_AdultMale_PainGrunts_04.wav» https://freesound.org/people/MrFossy/sounds/547200/; Freesound 547207 «Voice_AdultMale_PainGrunts_05.wav» https://freesound.org/people/MrFossy/sounds/547207/; Freesound 547206 «Voice_AdultMale_PainGrunts_06.wav» https://freesound.org/people/MrFossy/sounds/547206/; Freesound 547205 «Voice_AdultMale_PainGrunts_07.wav» https://freesound.org/people/MrFossy/sounds/547205/; Freesound 547204 «Voice_AdultMale_PainGrunts_08.wav» https://freesound.org/people/MrFossy/sounds/547204/; Freesound 547209 «Voice_AdultMale_PainGrunts_09.wav» https://freesound.org/people/MrFossy/sounds/547209/; Freesound 547208 «Voice_AdultMale_PainGrunts_10.wav» https://freesound.org/people/MrFossy/sounds/547208/; Freesound 547194 «Voice_AdultMale_PainGrunts_11.wav» https://freesound.org/people/MrFossy/sounds/547194/; Freesound 547195 «Voice_AdultMale_PainGrunts_12.wav» https://freesound.org/people/MrFossy/sounds/547195/; Freesound 547193 «Voice_AdultMale_PainGrunts_14.wav» https://freesound.org/people/MrFossy/sounds/547193/; Freesound 547198 «Voice_AdultMale_PainGrunts_15.wav» https://freesound.org/people/MrFossy/sounds/547198/ | MrFossy | CC0 1.0 | toma 3 de 14 |
| `sounds/combat/player_hurt_2.ogg` | Freesound 547203 «Voice_AdultMale_PainGrunts_01.wav» https://freesound.org/people/MrFossy/sounds/547203/; Freesound 547202 «Voice_AdultMale_PainGrunts_02.wav» https://freesound.org/people/MrFossy/sounds/547202/; Freesound 547201 «Voice_AdultMale_PainGrunts_03.wav» https://freesound.org/people/MrFossy/sounds/547201/; Freesound 547200 «Voice_AdultMale_PainGrunts_04.wav» https://freesound.org/people/MrFossy/sounds/547200/; Freesound 547207 «Voice_AdultMale_PainGrunts_05.wav» https://freesound.org/people/MrFossy/sounds/547207/; Freesound 547206 «Voice_AdultMale_PainGrunts_06.wav» https://freesound.org/people/MrFossy/sounds/547206/; Freesound 547205 «Voice_AdultMale_PainGrunts_07.wav» https://freesound.org/people/MrFossy/sounds/547205/; Freesound 547204 «Voice_AdultMale_PainGrunts_08.wav» https://freesound.org/people/MrFossy/sounds/547204/; Freesound 547209 «Voice_AdultMale_PainGrunts_09.wav» https://freesound.org/people/MrFossy/sounds/547209/; Freesound 547208 «Voice_AdultMale_PainGrunts_10.wav» https://freesound.org/people/MrFossy/sounds/547208/; Freesound 547194 «Voice_AdultMale_PainGrunts_11.wav» https://freesound.org/people/MrFossy/sounds/547194/; Freesound 547195 «Voice_AdultMale_PainGrunts_12.wav» https://freesound.org/people/MrFossy/sounds/547195/; Freesound 547193 «Voice_AdultMale_PainGrunts_14.wav» https://freesound.org/people/MrFossy/sounds/547193/; Freesound 547198 «Voice_AdultMale_PainGrunts_15.wav» https://freesound.org/people/MrFossy/sounds/547198/ | MrFossy | CC0 1.0 | toma 5 de 14 |
| `sounds/combat/player_hurt_3.ogg` | Freesound 547203 «Voice_AdultMale_PainGrunts_01.wav» https://freesound.org/people/MrFossy/sounds/547203/; Freesound 547202 «Voice_AdultMale_PainGrunts_02.wav» https://freesound.org/people/MrFossy/sounds/547202/; Freesound 547201 «Voice_AdultMale_PainGrunts_03.wav» https://freesound.org/people/MrFossy/sounds/547201/; Freesound 547200 «Voice_AdultMale_PainGrunts_04.wav» https://freesound.org/people/MrFossy/sounds/547200/; Freesound 547207 «Voice_AdultMale_PainGrunts_05.wav» https://freesound.org/people/MrFossy/sounds/547207/; Freesound 547206 «Voice_AdultMale_PainGrunts_06.wav» https://freesound.org/people/MrFossy/sounds/547206/; Freesound 547205 «Voice_AdultMale_PainGrunts_07.wav» https://freesound.org/people/MrFossy/sounds/547205/; Freesound 547204 «Voice_AdultMale_PainGrunts_08.wav» https://freesound.org/people/MrFossy/sounds/547204/; Freesound 547209 «Voice_AdultMale_PainGrunts_09.wav» https://freesound.org/people/MrFossy/sounds/547209/; Freesound 547208 «Voice_AdultMale_PainGrunts_10.wav» https://freesound.org/people/MrFossy/sounds/547208/; Freesound 547194 «Voice_AdultMale_PainGrunts_11.wav» https://freesound.org/people/MrFossy/sounds/547194/; Freesound 547195 «Voice_AdultMale_PainGrunts_12.wav» https://freesound.org/people/MrFossy/sounds/547195/; Freesound 547193 «Voice_AdultMale_PainGrunts_14.wav» https://freesound.org/people/MrFossy/sounds/547193/; Freesound 547198 «Voice_AdultMale_PainGrunts_15.wav» https://freesound.org/people/MrFossy/sounds/547198/ | MrFossy | CC0 1.0 | toma 8 de 14 |
| `sounds/combat/player_hurt_4.ogg` | Freesound 547203 «Voice_AdultMale_PainGrunts_01.wav» https://freesound.org/people/MrFossy/sounds/547203/; Freesound 547202 «Voice_AdultMale_PainGrunts_02.wav» https://freesound.org/people/MrFossy/sounds/547202/; Freesound 547201 «Voice_AdultMale_PainGrunts_03.wav» https://freesound.org/people/MrFossy/sounds/547201/; Freesound 547200 «Voice_AdultMale_PainGrunts_04.wav» https://freesound.org/people/MrFossy/sounds/547200/; Freesound 547207 «Voice_AdultMale_PainGrunts_05.wav» https://freesound.org/people/MrFossy/sounds/547207/; Freesound 547206 «Voice_AdultMale_PainGrunts_06.wav» https://freesound.org/people/MrFossy/sounds/547206/; Freesound 547205 «Voice_AdultMale_PainGrunts_07.wav» https://freesound.org/people/MrFossy/sounds/547205/; Freesound 547204 «Voice_AdultMale_PainGrunts_08.wav» https://freesound.org/people/MrFossy/sounds/547204/; Freesound 547209 «Voice_AdultMale_PainGrunts_09.wav» https://freesound.org/people/MrFossy/sounds/547209/; Freesound 547208 «Voice_AdultMale_PainGrunts_10.wav» https://freesound.org/people/MrFossy/sounds/547208/; Freesound 547194 «Voice_AdultMale_PainGrunts_11.wav» https://freesound.org/people/MrFossy/sounds/547194/; Freesound 547195 «Voice_AdultMale_PainGrunts_12.wav» https://freesound.org/people/MrFossy/sounds/547195/; Freesound 547193 «Voice_AdultMale_PainGrunts_14.wav» https://freesound.org/people/MrFossy/sounds/547193/; Freesound 547198 «Voice_AdultMale_PainGrunts_15.wav» https://freesound.org/people/MrFossy/sounds/547198/ | MrFossy | CC0 1.0 | toma 10 de 14 |
| `sounds/combat/player_death_0.ogg` | Freesound 547182 «Voice_AdultMale_DeathScream_03.wav» https://freesound.org/people/MrFossy/sounds/547182/; Freesound 547185 «Voice_AdultMale_DeathScream_08.wav» https://freesound.org/people/MrFossy/sounds/547185/; Freesound 547190 «Voice_AdultMale_DeathScream_09.wav» https://freesound.org/people/MrFossy/sounds/547190/; Freesound 547186 «Voice_AdultMale_DeathScream_07.wav» https://freesound.org/people/MrFossy/sounds/547186/; Freesound 547183 «Voice_AdultMale_DeathScream_02.wav» https://freesound.org/people/MrFossy/sounds/547183/; Freesound 547189 «Voice_AdultMale_DeathScream_10.wav» https://freesound.org/people/MrFossy/sounds/547189/ | MrFossy | CC0 1.0 | toma 1 de 6 |
| `sounds/combat/creature_growl_0.ogg` | Freesound 555416 «Zombie Growl 1.wav» https://freesound.org/people/tonsil5/sounds/555416/; Freesound 555415 «Zombie Growl 2.wav» https://freesound.org/people/tonsil5/sounds/555415/; Freesound 555413 «Zombie Growl 4.wav» https://freesound.org/people/tonsil5/sounds/555413/; Freesound 555417 «Zombie Growl 5.wav» https://freesound.org/people/tonsil5/sounds/555417/; Freesound 133974 «Horrific Zombie Growl» https://freesound.org/people/MrPokephile/sounds/133974/; Freesound 323819 «zombie growl» https://freesound.org/people/adharca/sounds/323819/; Freesound 426628 «Zombie Moan.wav» https://freesound.org/people/mrh4hn/sounds/426628/; Freesound 426627 «Zombie Grunt.wav» https://freesound.org/people/mrh4hn/sounds/426627/; Freesound 754441 «Zombie Groan 3» https://freesound.org/people/OwNathan/sounds/754441/; Freesound 393749 «Zombie Pack(Clean Record)» https://freesound.org/people/haratman/sounds/393749/ | MrPokephile, OwNathan, adharca, haratman, mrh4hn, tonsil5 | CC0 1.0 | toma 1 de 12 |
| `sounds/combat/creature_growl_1.ogg` | Freesound 555416 «Zombie Growl 1.wav» https://freesound.org/people/tonsil5/sounds/555416/; Freesound 555415 «Zombie Growl 2.wav» https://freesound.org/people/tonsil5/sounds/555415/; Freesound 555413 «Zombie Growl 4.wav» https://freesound.org/people/tonsil5/sounds/555413/; Freesound 555417 «Zombie Growl 5.wav» https://freesound.org/people/tonsil5/sounds/555417/; Freesound 133974 «Horrific Zombie Growl» https://freesound.org/people/MrPokephile/sounds/133974/; Freesound 323819 «zombie growl» https://freesound.org/people/adharca/sounds/323819/; Freesound 426628 «Zombie Moan.wav» https://freesound.org/people/mrh4hn/sounds/426628/; Freesound 426627 «Zombie Grunt.wav» https://freesound.org/people/mrh4hn/sounds/426627/; Freesound 754441 «Zombie Groan 3» https://freesound.org/people/OwNathan/sounds/754441/; Freesound 393749 «Zombie Pack(Clean Record)» https://freesound.org/people/haratman/sounds/393749/ | MrPokephile, OwNathan, adharca, haratman, mrh4hn, tonsil5 | CC0 1.0 | toma 3 de 12 |
| `sounds/combat/creature_growl_2.ogg` | Freesound 555416 «Zombie Growl 1.wav» https://freesound.org/people/tonsil5/sounds/555416/; Freesound 555415 «Zombie Growl 2.wav» https://freesound.org/people/tonsil5/sounds/555415/; Freesound 555413 «Zombie Growl 4.wav» https://freesound.org/people/tonsil5/sounds/555413/; Freesound 555417 «Zombie Growl 5.wav» https://freesound.org/people/tonsil5/sounds/555417/; Freesound 133974 «Horrific Zombie Growl» https://freesound.org/people/MrPokephile/sounds/133974/; Freesound 323819 «zombie growl» https://freesound.org/people/adharca/sounds/323819/; Freesound 426628 «Zombie Moan.wav» https://freesound.org/people/mrh4hn/sounds/426628/; Freesound 426627 «Zombie Grunt.wav» https://freesound.org/people/mrh4hn/sounds/426627/; Freesound 754441 «Zombie Groan 3» https://freesound.org/people/OwNathan/sounds/754441/; Freesound 393749 «Zombie Pack(Clean Record)» https://freesound.org/people/haratman/sounds/393749/ | MrPokephile, OwNathan, adharca, haratman, mrh4hn, tonsil5 | CC0 1.0 | toma 5 de 12 |
| `sounds/combat/creature_attack_0.ogg` | Freesound 393749 «Zombie Pack(Clean Record)» https://freesound.org/people/haratman/sounds/393749/; Freesound 143998 «Zombie Roar 4» https://freesound.org/people/ArriGD/sounds/143998/; Freesound 144005 «Zombie Roar 5» https://freesound.org/people/ArriGD/sounds/144005/ | ArriGD, haratman | CC0 1.0 | toma 1 de 15 |
| `sounds/combat/creature_attack_1.ogg` | Freesound 393749 «Zombie Pack(Clean Record)» https://freesound.org/people/haratman/sounds/393749/; Freesound 143998 «Zombie Roar 4» https://freesound.org/people/ArriGD/sounds/143998/; Freesound 144005 «Zombie Roar 5» https://freesound.org/people/ArriGD/sounds/144005/ | ArriGD, haratman | CC0 1.0 | toma 4 de 15 |
| `sounds/combat/creature_attack_2.ogg` | Freesound 393749 «Zombie Pack(Clean Record)» https://freesound.org/people/haratman/sounds/393749/; Freesound 143998 «Zombie Roar 4» https://freesound.org/people/ArriGD/sounds/143998/; Freesound 144005 «Zombie Roar 5» https://freesound.org/people/ArriGD/sounds/144005/ | ArriGD, haratman | CC0 1.0 | toma 7 de 15 |
| `sounds/combat/creature_pain_0.ogg` | Freesound 555423 «Zombie Pain 2.wav» https://freesound.org/people/tonsil5/sounds/555423/; Freesound 555421 «Zombie Pain 4.wav» https://freesound.org/people/tonsil5/sounds/555421/; Freesound 555425 «Zombie Pain 6.wav» https://freesound.org/people/tonsil5/sounds/555425/; Freesound 555420 «Zombie Hit 1.wav» https://freesound.org/people/tonsil5/sounds/555420/; Freesound 555419 «Zombie Hit 2.wav» https://freesound.org/people/tonsil5/sounds/555419/; Freesound 754438 «Zombie Groan 0» https://freesound.org/people/OwNathan/sounds/754438/; Freesound 163447 «Zombie Hit» https://freesound.org/people/Under7dude/sounds/163447/ | OwNathan, Under7dude, tonsil5 | CC0 1.0 | toma 2 de 7 |
| `sounds/combat/creature_pain_1.ogg` | Freesound 555423 «Zombie Pain 2.wav» https://freesound.org/people/tonsil5/sounds/555423/; Freesound 555421 «Zombie Pain 4.wav» https://freesound.org/people/tonsil5/sounds/555421/; Freesound 555425 «Zombie Pain 6.wav» https://freesound.org/people/tonsil5/sounds/555425/; Freesound 555420 «Zombie Hit 1.wav» https://freesound.org/people/tonsil5/sounds/555420/; Freesound 555419 «Zombie Hit 2.wav» https://freesound.org/people/tonsil5/sounds/555419/; Freesound 754438 «Zombie Groan 0» https://freesound.org/people/OwNathan/sounds/754438/; Freesound 163447 «Zombie Hit» https://freesound.org/people/Under7dude/sounds/163447/ | OwNathan, Under7dude, tonsil5 | CC0 1.0 | toma 4 de 7 |
| `sounds/combat/creature_death_0.ogg` | Freesound 555412 «Zombie Death 1.wav» https://freesound.org/people/tonsil5/sounds/555412/; Freesound 555411 «Zombie Death 2.wav» https://freesound.org/people/tonsil5/sounds/555411/; Freesound 555424 «Zombie Pain 1.wav» https://freesound.org/people/tonsil5/sounds/555424/; Freesound 396797 «Mutant Scream» https://freesound.org/people/scorpion67890/sounds/396797/; Freesound 163445 «Zombie 4» https://freesound.org/people/Under7dude/sounds/163445/ | Under7dude, scorpion67890, tonsil5 | CC0 1.0 | toma 1 de 5 |
| `sounds/combat/creature_death_1.ogg` | Freesound 555412 «Zombie Death 1.wav» https://freesound.org/people/tonsil5/sounds/555412/; Freesound 555411 «Zombie Death 2.wav» https://freesound.org/people/tonsil5/sounds/555411/; Freesound 555424 «Zombie Pain 1.wav» https://freesound.org/people/tonsil5/sounds/555424/; Freesound 396797 «Mutant Scream» https://freesound.org/people/scorpion67890/sounds/396797/; Freesound 163445 «Zombie 4» https://freesound.org/people/Under7dude/sounds/163445/ | Under7dude, scorpion67890, tonsil5 | CC0 1.0 | toma 2 de 5 |
| `sounds/combat/animal_snarl_0.ogg` | Freesound 341090 «Dog snarl.mp3» https://freesound.org/people/strongbot/sounds/341090/; Freesound 439535 «Angry Dog» https://freesound.org/people/CmdRobot/sounds/439535/ | CmdRobot, strongbot | CC0 1.0 | toma 1 de 7 |
| `sounds/combat/animal_snarl_1.ogg` | Freesound 341090 «Dog snarl.mp3» https://freesound.org/people/strongbot/sounds/341090/; Freesound 439535 «Angry Dog» https://freesound.org/people/CmdRobot/sounds/439535/ | CmdRobot, strongbot | CC0 1.0 | toma 3 de 7 |
| `sounds/combat/animal_snarl_2.ogg` | Freesound 341090 «Dog snarl.mp3» https://freesound.org/people/strongbot/sounds/341090/; Freesound 439535 «Angry Dog» https://freesound.org/people/CmdRobot/sounds/439535/ | CmdRobot, strongbot | CC0 1.0 | toma 5 de 7 |
| `sounds/events/wolf_howl_0.ogg` | Freesound 398430 «Wolf howl» https://freesound.org/people/NaturesTemper/sounds/398430/; Freesound 500646 «Cooper Creek 20160313_014852 solitary wolf howl very clear.wav» https://freesound.org/people/betchkal/sounds/500646/ | NaturesTemper, betchkal | CC0 1.0 | toma 2 de 4 |
| `sounds/build/hammer_0.ogg` | Freesound 342542 «Outside Hammer» https://freesound.org/people/sgrowe/sounds/342542/; Freesound 707864 «Hammer on Wood» https://freesound.org/people/L.i.Z.e.L.l.E_+/sounds/707864/; Freesound 850175 «nailing.wav» https://freesound.org/people/Mihacappy/sounds/850175/ | L.i.Z.e.L.l.E_+, Mihacappy, sgrowe | CC0 1.0 | toma 1 de 9 |
| `sounds/build/hammer_1.ogg` | Freesound 342542 «Outside Hammer» https://freesound.org/people/sgrowe/sounds/342542/; Freesound 707864 «Hammer on Wood» https://freesound.org/people/L.i.Z.e.L.l.E_+/sounds/707864/; Freesound 850175 «nailing.wav» https://freesound.org/people/Mihacappy/sounds/850175/ | L.i.Z.e.L.l.E_+, Mihacappy, sgrowe | CC0 1.0 | toma 2 de 9 |
| `sounds/build/hammer_2.ogg` | Freesound 342542 «Outside Hammer» https://freesound.org/people/sgrowe/sounds/342542/; Freesound 707864 «Hammer on Wood» https://freesound.org/people/L.i.Z.e.L.l.E_+/sounds/707864/; Freesound 850175 «nailing.wav» https://freesound.org/people/Mihacappy/sounds/850175/ | L.i.Z.e.L.l.E_+, Mihacappy, sgrowe | CC0 1.0 | toma 3 de 9 |
| `sounds/build/hammer_3.ogg` | Freesound 342542 «Outside Hammer» https://freesound.org/people/sgrowe/sounds/342542/; Freesound 707864 «Hammer on Wood» https://freesound.org/people/L.i.Z.e.L.l.E_+/sounds/707864/; Freesound 850175 «nailing.wav» https://freesound.org/people/Mihacappy/sounds/850175/ | L.i.Z.e.L.l.E_+, Mihacappy, sgrowe | CC0 1.0 | toma 5 de 9 |
| `sounds/build/plank_0.ogg` | Kenney — Impact Sounds: `impactPlank_medium_000.ogg` · https://kenney.nl/assets/impact-sounds | Kenney | CC0 1.0 |  |
| `sounds/build/plank_1.ogg` | Kenney — Impact Sounds: `impactPlank_medium_001.ogg` · https://kenney.nl/assets/impact-sounds | Kenney | CC0 1.0 |  |
| `sounds/build/plank_2.ogg` | Kenney — Impact Sounds: `impactPlank_medium_002.ogg` · https://kenney.nl/assets/impact-sounds | Kenney | CC0 1.0 |  |
| `sounds/build/creak_0.ogg` | Kenney — RPG Audio: `creak1.ogg` · https://kenney.nl/assets/rpg-audio | Kenney | CC0 1.0 |  |
| `sounds/build/creak_1.ogg` | Kenney — RPG Audio: `creak2.ogg` · https://kenney.nl/assets/rpg-audio | Kenney | CC0 1.0 |  |
| `sounds/build/place_0.ogg` | Kenney — Impact Sounds: `impactGeneric_light_000.ogg` · https://kenney.nl/assets/impact-sounds | Kenney | CC0 1.0 |  |
| `sounds/build/place_1.ogg` | Kenney — Impact Sounds: `impactGeneric_light_001.ogg` · https://kenney.nl/assets/impact-sounds | Kenney | CC0 1.0 |  |
| `sounds/build/metal_0.ogg` | Kenney — Impact Sounds: `impactMetal_light_000.ogg` · https://kenney.nl/assets/impact-sounds | Kenney | CC0 1.0 |  |
| `sounds/build/metal_1.ogg` | Kenney — Impact Sounds: `impactMetal_light_001.ogg` · https://kenney.nl/assets/impact-sounds | Kenney | CC0 1.0 |  |
| `sounds/build/anvil_0.ogg` | Kenney — Impact Sounds: `impactMetal_medium_000.ogg` · https://kenney.nl/assets/impact-sounds | Kenney | CC0 1.0 |  |
| `sounds/build/wood_break_0.ogg` | Freesound 262538 «Locked door being forced open.wav» https://freesound.org/people/Talitha5/sounds/262538/; Freesound 536777 «Smash.ogg» https://freesound.org/people/egomassive/sounds/536777/; Freesound 343164 «Wood Crash.mp3» https://freesound.org/people/benjaminpotter/sounds/343164/; Freesound 537459 «wood crackling-31.wav» https://freesound.org/people/wavecal22/sounds/537459/ | Talitha5, benjaminpotter, egomassive, wavecal22 | CC0 1.0 | toma 2 de 4 |
| `sounds/build/wood_break_1.ogg` | Freesound 262538 «Locked door being forced open.wav» https://freesound.org/people/Talitha5/sounds/262538/; Freesound 536777 «Smash.ogg» https://freesound.org/people/egomassive/sounds/536777/; Freesound 343164 «Wood Crash.mp3» https://freesound.org/people/benjaminpotter/sounds/343164/; Freesound 537459 «wood crackling-31.wav» https://freesound.org/people/wavecal22/sounds/537459/ | Talitha5, benjaminpotter, egomassive, wavecal22 | CC0 1.0 | toma 3 de 4 |
| `sounds/ui/click_0.ogg` | Kenney — Interface Sounds: `click_001.ogg` · https://kenney.nl/assets/interface-sounds | Kenney | CC0 1.0 |  |
| `sounds/ui/click_1.ogg` | Kenney — Interface Sounds: `click_002.ogg` · https://kenney.nl/assets/interface-sounds | Kenney | CC0 1.0 |  |
| `sounds/ui/click_2.ogg` | Kenney — Interface Sounds: `click_003.ogg` · https://kenney.nl/assets/interface-sounds | Kenney | CC0 1.0 |  |
| `sounds/ui/confirm_0.ogg` | Kenney — Interface Sounds: `confirmation_001.ogg` · https://kenney.nl/assets/interface-sounds | Kenney | CC0 1.0 |  |
| `sounds/ui/confirm_1.ogg` | Kenney — Interface Sounds: `confirmation_002.ogg` · https://kenney.nl/assets/interface-sounds | Kenney | CC0 1.0 |  |
| `sounds/ui/confirm_2.ogg` | Kenney — Interface Sounds: `confirmation_003.ogg` · https://kenney.nl/assets/interface-sounds | Kenney | CC0 1.0 |  |
| `sounds/ui/error_0.ogg` | Kenney — Interface Sounds: `error_001.ogg` · https://kenney.nl/assets/interface-sounds | Kenney | CC0 1.0 |  |
| `sounds/ui/error_1.ogg` | Kenney — Interface Sounds: `error_002.ogg` · https://kenney.nl/assets/interface-sounds | Kenney | CC0 1.0 |  |
| `sounds/ui/error_2.ogg` | Kenney — Interface Sounds: `error_004.ogg` · https://kenney.nl/assets/interface-sounds | Kenney | CC0 1.0 |  |
| `sounds/ui/open_0.ogg` | Kenney — Interface Sounds: `open_001.ogg` · https://kenney.nl/assets/interface-sounds | Kenney | CC0 1.0 |  |
| `sounds/ui/open_1.ogg` | Kenney — Interface Sounds: `open_002.ogg` · https://kenney.nl/assets/interface-sounds | Kenney | CC0 1.0 |  |
| `sounds/ui/close_0.ogg` | Kenney — Interface Sounds: `close_001.ogg` · https://kenney.nl/assets/interface-sounds | Kenney | CC0 1.0 |  |
| `sounds/ui/close_1.ogg` | Kenney — Interface Sounds: `close_002.ogg` · https://kenney.nl/assets/interface-sounds | Kenney | CC0 1.0 |  |
| `sounds/ui/select_0.ogg` | Kenney — Interface Sounds: `select_001.ogg` · https://kenney.nl/assets/interface-sounds | Kenney | CC0 1.0 |  |
| `sounds/ui/select_1.ogg` | Kenney — Interface Sounds: `select_002.ogg` · https://kenney.nl/assets/interface-sounds | Kenney | CC0 1.0 |  |
| `sounds/ui/switch_0.ogg` | Kenney — Interface Sounds: `switch_001.ogg` · https://kenney.nl/assets/interface-sounds | Kenney | CC0 1.0 |  |
| `sounds/ui/switch_1.ogg` | Kenney — Interface Sounds: `switch_002.ogg` · https://kenney.nl/assets/interface-sounds | Kenney | CC0 1.0 |  |
| `sounds/ui/toggle_0.ogg` | Kenney — Interface Sounds: `toggle_001.ogg` · https://kenney.nl/assets/interface-sounds | Kenney | CC0 1.0 |  |
| `sounds/ui/drop_0.ogg` | Kenney — Interface Sounds: `drop_001.ogg` · https://kenney.nl/assets/interface-sounds | Kenney | CC0 1.0 |  |
| `sounds/ui/drop_1.ogg` | Kenney — Interface Sounds: `drop_002.ogg` · https://kenney.nl/assets/interface-sounds | Kenney | CC0 1.0 |  |
| `sounds/ui/bong_0.ogg` | Kenney — Interface Sounds: `bong_001.ogg` · https://kenney.nl/assets/interface-sounds | Kenney | CC0 1.0 |  |
| `sounds/ui/glass_0.ogg` | Kenney — Interface Sounds: `glass_001.ogg` · https://kenney.nl/assets/interface-sounds | Kenney | CC0 1.0 |  |
| `sounds/ui/pluck_0.ogg` | Kenney — Interface Sounds: `pluck_001.ogg` · https://kenney.nl/assets/interface-sounds | Kenney | CC0 1.0 |  |
| `sounds/ui/pluck_1.ogg` | Kenney — Interface Sounds: `pluck_002.ogg` · https://kenney.nl/assets/interface-sounds | Kenney | CC0 1.0 |  |
| `sounds/ui/maximize_0.ogg` | Kenney — Interface Sounds: `maximize_001.ogg` · https://kenney.nl/assets/interface-sounds | Kenney | CC0 1.0 |  |
| `sounds/ui/minimize_0.ogg` | Kenney — Interface Sounds: `minimize_001.ogg` · https://kenney.nl/assets/interface-sounds | Kenney | CC0 1.0 |  |
| `sounds/ui/question_0.ogg` | Kenney — Interface Sounds: `question_001.ogg` · https://kenney.nl/assets/interface-sounds | Kenney | CC0 1.0 |  |
| `sounds/ui/tick_0.ogg` | Kenney — Interface Sounds: `tick_001.ogg` · https://kenney.nl/assets/interface-sounds | Kenney | CC0 1.0 |  |
| `sounds/ui/back_0.ogg` | Kenney — Interface Sounds: `back_001.ogg` · https://kenney.nl/assets/interface-sounds | Kenney | CC0 1.0 |  |
| `sounds/ui/cloth_0.ogg` | Kenney — RPG Audio: `cloth1.ogg` · https://kenney.nl/assets/rpg-audio | Kenney | CC0 1.0 |  |
| `sounds/ui/cloth_1.ogg` | Kenney — RPG Audio: `cloth2.ogg` · https://kenney.nl/assets/rpg-audio | Kenney | CC0 1.0 |  |
| `sounds/ui/cloth_2.ogg` | Kenney — RPG Audio: `cloth3.ogg` · https://kenney.nl/assets/rpg-audio | Kenney | CC0 1.0 |  |
| `sounds/ui/book_flip_0.ogg` | Kenney — RPG Audio: `bookFlip1.ogg` · https://kenney.nl/assets/rpg-audio | Kenney | CC0 1.0 |  |
| `sounds/ui/book_flip_1.ogg` | Kenney — RPG Audio: `bookFlip2.ogg` · https://kenney.nl/assets/rpg-audio | Kenney | CC0 1.0 |  |
| `sounds/ui/book_open_0.ogg` | Kenney — RPG Audio: `bookOpen.ogg` · https://kenney.nl/assets/rpg-audio | Kenney | CC0 1.0 |  |
| `sounds/ui/book_close_0.ogg` | Kenney — RPG Audio: `bookClose.ogg` · https://kenney.nl/assets/rpg-audio | Kenney | CC0 1.0 |  |
| `sounds/ui/coins_0.ogg` | Kenney — RPG Audio: `handleCoins.ogg` · https://kenney.nl/assets/rpg-audio | Kenney | CC0 1.0 |  |
| `sounds/ui/coins_1.ogg` | Kenney — RPG Audio: `handleCoins2.ogg` · https://kenney.nl/assets/rpg-audio | Kenney | CC0 1.0 |  |
| `sounds/ui/latch_0.ogg` | Kenney — RPG Audio: `metalLatch.ogg` · https://kenney.nl/assets/rpg-audio | Kenney | CC0 1.0 |  |
| `sounds/ui/metal_click_0.ogg` | Kenney — RPG Audio: `metalClick.ogg` · https://kenney.nl/assets/rpg-audio | Kenney | CC0 1.0 |  |
| `sounds/ui/equip_0.ogg` | Kenney — RPG Audio: `beltHandle1.ogg` · https://kenney.nl/assets/rpg-audio | Kenney | CC0 1.0 |  |
| `sounds/ui/drop_item_0.ogg` | Kenney — RPG Audio: `dropLeather.ogg` · https://kenney.nl/assets/rpg-audio | Kenney | CC0 1.0 |  |
| `sounds/build/door_open_0.ogg` | Kenney — RPG Audio: `doorOpen_1.ogg` · https://kenney.nl/assets/rpg-audio | Kenney | CC0 1.0 |  |
| `sounds/build/door_close_0.ogg` | Kenney — RPG Audio: `doorClose_1.ogg` · https://kenney.nl/assets/rpg-audio | Kenney | CC0 1.0 |  |
| `sounds/survival/eat_0.ogg` | OpenGameArt «7 Eating Crunches» https://opengameart.org/content/7-eating-crunches | StarNinjas | CC0 1.0 | convertido de WAV a OGG |
| `sounds/survival/eat_1.ogg` | OpenGameArt «7 Eating Crunches» https://opengameart.org/content/7-eating-crunches | StarNinjas | CC0 1.0 | convertido de WAV a OGG |
| `sounds/survival/eat_2.ogg` | OpenGameArt «7 Eating Crunches» https://opengameart.org/content/7-eating-crunches | StarNinjas | CC0 1.0 | convertido de WAV a OGG |
| `sounds/survival/drink_0.ogg` | OpenGameArt «202 More Sound Effects (drinking)» https://opengameart.org/content/202-more-sound-effects | OwlishMedia | CC0 1.0 | convertido de WAV a OGG |
| `sounds/survival/drink_1.ogg` | OpenGameArt «202 More Sound Effects (drinking)» https://opengameart.org/content/202-more-sound-effects | OwlishMedia | CC0 1.0 | convertido de WAV a OGG |
| `sounds/survival/drink_2.ogg` | OpenGameArt «202 More Sound Effects (drinking)» https://opengameart.org/content/202-more-sound-effects | OwlishMedia | CC0 1.0 | convertido de WAV a OGG |
| `sounds/survival/splash_0.ogg` | OpenGameArt «40 CC0 water / splash / slime SFX» https://opengameart.org/content/40-cc0-water-splash-slime-sfx | rubberduck | CC0 1.0 | convertido de WAV a OGG |
| `sounds/survival/splash_1.ogg` | OpenGameArt «40 CC0 water / splash / slime SFX» https://opengameart.org/content/40-cc0-water-splash-slime-sfx | rubberduck | CC0 1.0 | convertido de WAV a OGG |
| `sounds/survival/bubble_0.ogg` | OpenGameArt «40 CC0 water / splash / slime SFX» https://opengameart.org/content/40-cc0-water-splash-slime-sfx | rubberduck | CC0 1.0 | convertido de WAV a OGG |
| `sounds/events/bell_0.ogg` | OpenGameArt «Pleasing Bell Sound Effect» https://opengameart.org/content/pleasing-bell-sound-effect | Spring Spring | CC0 1.0 | convertido de WAV a OGG |
| `sounds/survival/flame_0.ogg` | OpenGameArt «Catching fire» https://opengameart.org/content/catching-fire | themightyglider | CC0 1.0 | convertido de WAV a OGG |
| `sounds/survival/water_fill_0.ogg` | Kenney — Foley Sounds: `sinkWater1.ogg` · https://kenney.nl/assets/foley-sounds | Kenney | CC0 1.0 |  |
| `sounds/survival/water_fill_1.ogg` | Kenney — Foley Sounds: `sinkWater2.ogg` · https://kenney.nl/assets/foley-sounds | Kenney | CC0 1.0 |  |
| `sounds/survival/drip_0.ogg` | Kenney — Foley Sounds: `drip1.ogg` · https://kenney.nl/assets/foley-sounds | Kenney | CC0 1.0 |  |
| `sounds/survival/drip_1.ogg` | Kenney — Foley Sounds: `drip2.ogg` · https://kenney.nl/assets/foley-sounds | Kenney | CC0 1.0 |  |
| `sounds/survival/drip_2.ogg` | Kenney — Foley Sounds: `drip3.ogg` · https://kenney.nl/assets/foley-sounds | Kenney | CC0 1.0 |  |
| `sounds/survival/cook_0.ogg` | Kenney — RPG Audio: `metalPot1.ogg` · https://kenney.nl/assets/rpg-audio | Kenney | CC0 1.0 |  |
| `sounds/survival/cook_1.ogg` | Kenney — RPG Audio: `metalPot2.ogg` · https://kenney.nl/assets/rpg-audio | Kenney | CC0 1.0 |  |
| `sounds/survival/slice_0.ogg` | Kenney — RPG Audio: `knifeSlice.ogg` · https://kenney.nl/assets/rpg-audio | Kenney | CC0 1.0 |  |
| `sounds/survival/slice_1.ogg` | Kenney — RPG Audio: `knifeSlice2.ogg` · https://kenney.nl/assets/rpg-audio | Kenney | CC0 1.0 |  |
| `sounds/survival/heal_0.ogg` | Kenney — Digital Audio: `highUp.ogg` · https://kenney.nl/assets/digital-audio | Kenney | CC0 1.0 |  |
| `sounds/survival/fire_ignite_0.ogg` | Freesound 386385 «Torch - Ignite flame on soft» https://freesound.org/people/ldezem/sounds/386385/; Freesound 687010 «Fire Ignite.wav» https://freesound.org/people/Jo000/sounds/687010/ | Jo000, ldezem | CC0 1.0 | toma 1 de 2 |
| `sounds/survival/fire_ignite_1.ogg` | Freesound 386385 «Torch - Ignite flame on soft» https://freesound.org/people/ldezem/sounds/386385/; Freesound 687010 «Fire Ignite.wav» https://freesound.org/people/Jo000/sounds/687010/ | Jo000, ldezem | CC0 1.0 | toma 2 de 2 |
| `sounds/footsteps/water_0.ogg` | Freesound 321594 «Wading in a shallow river» https://freesound.org/people/macdaddyno1/sounds/321594/; Freesound 342932 «Wading in Shallow Water.wav» https://freesound.org/people/ryansitz/sounds/342932/; Freesound 627004 «Walking through water» https://freesound.org/people/rosenberg3/sounds/627004/ | macdaddyno1, rosenberg3, ryansitz | CC0 1.0 | toma 1 de 14 |
| `sounds/footsteps/water_1.ogg` | Freesound 321594 «Wading in a shallow river» https://freesound.org/people/macdaddyno1/sounds/321594/; Freesound 342932 «Wading in Shallow Water.wav» https://freesound.org/people/ryansitz/sounds/342932/; Freesound 627004 «Walking through water» https://freesound.org/people/rosenberg3/sounds/627004/ | macdaddyno1, rosenberg3, ryansitz | CC0 1.0 | toma 3 de 14 |
| `sounds/footsteps/water_2.ogg` | Freesound 321594 «Wading in a shallow river» https://freesound.org/people/macdaddyno1/sounds/321594/; Freesound 342932 «Wading in Shallow Water.wav» https://freesound.org/people/ryansitz/sounds/342932/; Freesound 627004 «Walking through water» https://freesound.org/people/rosenberg3/sounds/627004/ | macdaddyno1, rosenberg3, ryansitz | CC0 1.0 | toma 5 de 14 |
| `sounds/footsteps/water_3.ogg` | Freesound 321594 «Wading in a shallow river» https://freesound.org/people/macdaddyno1/sounds/321594/; Freesound 342932 «Wading in Shallow Water.wav» https://freesound.org/people/ryansitz/sounds/342932/; Freesound 627004 «Walking through water» https://freesound.org/people/rosenberg3/sounds/627004/ | macdaddyno1, rosenberg3, ryansitz | CC0 1.0 | toma 9 de 14 |
| `sounds/events/level_up_0.ogg` | Kenney — Digital Audio: `powerUp7.ogg` · https://kenney.nl/assets/digital-audio | Kenney | CC0 1.0 |  |
| `sounds/events/unlock_0.ogg` | Kenney — Digital Audio: `zapThreeToneUp.ogg` · https://kenney.nl/assets/digital-audio | Kenney | CC0 1.0 |  |
| `sounds/events/quest_complete_0.ogg` | Kenney — Digital Audio: `threeTone1.ogg` · https://kenney.nl/assets/digital-audio | Kenney | CC0 1.0 |  |
| `sounds/events/research_0.ogg` | Kenney — Digital Audio: `phaserUp1.ogg` · https://kenney.nl/assets/digital-audio | Kenney | CC0 1.0 |  |
| `sounds/events/death_0.ogg` | Kenney — Digital Audio: `lowDown.ogg` · https://kenney.nl/assets/digital-audio | Kenney | CC0 1.0 |  |
| `sounds/events/reward_0.ogg` | Kenney — Digital Audio: `powerUp2.ogg` · https://kenney.nl/assets/digital-audio | Kenney | CC0 1.0 |  |
| `sounds/events/upgrade_0.ogg` | Kenney — Digital Audio: `powerUp5.ogg` · https://kenney.nl/assets/digital-audio | Kenney | CC0 1.0 |  |
| `sounds/events/achievement_0.ogg` | Kenney — Digital Audio: `threeTone2.ogg` · https://kenney.nl/assets/digital-audio | Kenney | CC0 1.0 |  |
| `sounds/events/worker_0.ogg` | Kenney — Digital Audio: `twoTone1.ogg` · https://kenney.nl/assets/digital-audio | Kenney | CC0 1.0 |  |
| `sounds/events/power_on_0.ogg` | Kenney — Digital Audio: `phaserUp3.ogg` · https://kenney.nl/assets/digital-audio | Kenney | CC0 1.0 |  |
| `sounds/events/boost_0.ogg` | Kenney — Digital Audio: `powerUp11.ogg` · https://kenney.nl/assets/digital-audio | Kenney | CC0 1.0 |  |
| `sounds/events/jingle_00.ogg` | Kenney — Music Jingles: `jingles-steel_00.ogg` · https://kenney.nl/assets/music-jingles | Kenney | CC0 1.0 |  |
| `sounds/events/jingle_01.ogg` | Kenney — Music Jingles: `jingles-steel_01.ogg` · https://kenney.nl/assets/music-jingles | Kenney | CC0 1.0 |  |
| `sounds/events/jingle_02.ogg` | Kenney — Music Jingles: `jingles-steel_02.ogg` · https://kenney.nl/assets/music-jingles | Kenney | CC0 1.0 |  |
| `sounds/events/jingle_03.ogg` | Kenney — Music Jingles: `jingles-steel_03.ogg` · https://kenney.nl/assets/music-jingles | Kenney | CC0 1.0 |  |
| `sounds/events/jingle_04.ogg` | Kenney — Music Jingles: `jingles-steel_04.ogg` · https://kenney.nl/assets/music-jingles | Kenney | CC0 1.0 |  |
| `sounds/events/jingle_05.ogg` | Kenney — Music Jingles: `jingles-steel_05.ogg` · https://kenney.nl/assets/music-jingles | Kenney | CC0 1.0 |  |
| `sounds/events/jingle_06.ogg` | Kenney — Music Jingles: `jingles-steel_06.ogg` · https://kenney.nl/assets/music-jingles | Kenney | CC0 1.0 |  |
| `sounds/events/jingle_07.ogg` | Kenney — Music Jingles: `jingles-steel_07.ogg` · https://kenney.nl/assets/music-jingles | Kenney | CC0 1.0 |  |
| `sounds/events/jingle_08.ogg` | Kenney — Music Jingles: `jingles-steel_08.ogg` · https://kenney.nl/assets/music-jingles | Kenney | CC0 1.0 |  |
| `sounds/events/jingle_09.ogg` | Kenney — Music Jingles: `jingles-steel_09.ogg` · https://kenney.nl/assets/music-jingles | Kenney | CC0 1.0 |  |
| `sounds/events/jingle_10.ogg` | Kenney — Music Jingles: `jingles-steel_10.ogg` · https://kenney.nl/assets/music-jingles | Kenney | CC0 1.0 |  |
| `sounds/events/jingle_11.ogg` | Kenney — Music Jingles: `jingles-steel_11.ogg` · https://kenney.nl/assets/music-jingles | Kenney | CC0 1.0 |  |
| `sounds/events/jingle_12.ogg` | Kenney — Music Jingles: `jingles-steel_12.ogg` · https://kenney.nl/assets/music-jingles | Kenney | CC0 1.0 |  |
| `sounds/events/jingle_13.ogg` | Kenney — Music Jingles: `jingles-steel_13.ogg` · https://kenney.nl/assets/music-jingles | Kenney | CC0 1.0 |  |
| `sounds/events/jingle_14.ogg` | Kenney — Music Jingles: `jingles-steel_14.ogg` · https://kenney.nl/assets/music-jingles | Kenney | CC0 1.0 |  |
| `sounds/events/jingle_15.ogg` | Kenney — Music Jingles: `jingles-steel_15.ogg` · https://kenney.nl/assets/music-jingles | Kenney | CC0 1.0 |  |
| `sounds/events/jingle_16.ogg` | Kenney — Music Jingles: `jingles-steel_16.ogg` · https://kenney.nl/assets/music-jingles | Kenney | CC0 1.0 |  |
| `sounds/events/stinger_night.ogg` | Freesound 647712 «Braam» https://freesound.org/people/unfa/sounds/647712/ | unfa | CC0 1.0 | mono, normalizado |
| `sounds/events/stinger_dawn.ogg` | Freesound 218524 «Movie Swell 2» https://freesound.org/people/jordivburgel/sounds/218524/ | jordivburgel | CC0 1.0 | mono, normalizado |
| `sounds/events/stinger_victory.ogg` | Freesound 812468 «Angelic Fanfare 2» https://freesound.org/people/qubodup/sounds/812468/ | qubodup | CC0 1.0 | mono, normalizado |
| `sounds/events/stinger_death.ogg` | Freesound 408141 «Cinematic Low Pitch Impact» https://freesound.org/people/Jofae/sounds/408141/ | Jofae | CC0 1.0 | mono, normalizado |
| `sounds/machines/computer_loop.ogg` | Kenney — Sci-Fi Sounds: `computerNoise_000.ogg` · https://kenney.nl/assets/sci-fi-sounds | Kenney | CC0 1.0 |  |
| `sounds/machines/engine_loop.ogg` | Kenney — Sci-Fi Sounds: `engineCircular_000.ogg` · https://kenney.nl/assets/sci-fi-sounds | Kenney | CC0 1.0 |  |
| `sounds/machines/force_field_loop.ogg` | Kenney — Sci-Fi Sounds: `forceField_000.ogg` · https://kenney.nl/assets/sci-fi-sounds | Kenney | CC0 1.0 |  |
| `sounds/machines/factory_loop.ogg` | Kenney — Sci-Fi Sounds: `spaceEngineLow_000.ogg` · https://kenney.nl/assets/sci-fi-sounds | Kenney | CC0 1.0 |  |
| `sounds/machines/generator_loop.ogg` | Kenney — Sci-Fi Sounds: `spaceEngine_000.ogg` · https://kenney.nl/assets/sci-fi-sounds | Kenney | CC0 1.0 |  |
| `sounds/machines/machine_door.ogg` | Kenney — Sci-Fi Sounds: `doorOpen_000.ogg` · https://kenney.nl/assets/sci-fi-sounds | Kenney | CC0 1.0 |  |
| `sounds/ambient/fire_loop.ogg` | Freesound 588401 «Campfire Close Crackling Sticks.mp3» https://freesound.org/people/FunWithSound/sounds/588401/ | FunWithSound | CC0 1.0 | bucle de 24 s con fundido cíclico |
| `sounds/ambient/owl_0.ogg` | Freesound 479588 «R01-27-Great Horned Owl Hoot.wav» https://freesound.org/people/craigsmith/sounds/479588/; Freesound 612651 «Great Horned Owl Duet at Canaveral Seashore» https://freesound.org/people/felix.blume/sounds/612651/ | craigsmith, felix.blume | CC0 1.0 | toma 1 de 8 |
| `sounds/ambient/owl_1.ogg` | Freesound 479588 «R01-27-Great Horned Owl Hoot.wav» https://freesound.org/people/craigsmith/sounds/479588/; Freesound 612651 «Great Horned Owl Duet at Canaveral Seashore» https://freesound.org/people/felix.blume/sounds/612651/ | craigsmith, felix.blume | CC0 1.0 | toma 3 de 8 |
| `sounds/ambient/tree_creak_0.ogg` | Freesound 140047 «A tree is creaking in the patagonian forest of Argentina in a deep creaky sound. (Argentina, Tierra del Fuego).» https://freesound.org/people/felix.blume/sounds/140047/; Freesound 726217 «Tree creaks» https://freesound.org/people/Sacha.Julien/sounds/726217/ | Sacha.Julien, felix.blume | CC0 1.0 | toma 7 de 9 |
| `sounds/ambient/tree_creak_1.ogg` | Freesound 140047 «A tree is creaking in the patagonian forest of Argentina in a deep creaky sound. (Argentina, Tierra del Fuego).» https://freesound.org/people/felix.blume/sounds/140047/; Freesound 726217 «Tree creaks» https://freesound.org/people/Sacha.Julien/sounds/726217/ | Sacha.Julien, felix.blume | CC0 1.0 | toma 8 de 9 |
| `sounds/ambient/day_birds.ogg` | Freesound «Forest quiet atmosphere with some birds» https://freesound.org/s/414098/ | felix.blume | CC0 1.0 | recorte de 46 s en bucle, mono 32 kHz |
| `sounds/ambient/night_crickets.ogg` | Freesound «Crickets (close recording)» https://freesound.org/s/476672/ | felix.blume | CC0 1.0 | recorte de 46 s en bucle, mono 32 kHz |
| `sounds/ambient/beach_waves.ogg` | Freesound «Crashing Waves - Pacific Ocean» https://freesound.org/s/817075/ | SecureSubset | CC0 1.0 | recorte de 40 s en bucle, mono 32 kHz |
| `sounds/ambient/river_stream.ogg` | Freesound «Relaxing River Sound» https://freesound.org/s/722875/ | IceVFX | CC0 1.0 | recorte de 30 s en bucle, mono 32 kHz |
| `sounds/ambient/wind.ogg` | Freesound «Wind on bushes with muffled gust of wind, twig branch, close to desert ground» https://freesound.org/s/711106/ | felix.blume | CC0 1.0 | recorte de 36 s en bucle, mono 32 kHz |
| `music/day_connecting_rainbows.ogg` | FreePD.com «Connecting Rainbows» (https://freepd.com — sitio archivado; espejo https://github.com/SoundSafari/CC0-1.0-Music (commit 655388f), carpeta freepd.com) | Kevin MacLeod | CC0 1.0 | convertido de MP3 a OGG |
| `music/night_midnight_green_house.ogg` | FreePD.com «Midnight in the Green House» (https://freepd.com — sitio archivado; espejo https://github.com/SoundSafari/CC0-1.0-Music (commit 655388f), carpeta freepd.com) | Kevin MacLeod | CC0 1.0 | convertido de MP3 a OGG |
| `music/night_at_the_beach.ogg` | Kenney — Music Loops: `Night at the Beach.ogg` · https://kenney.nl (pack «Music Loops» 1.1, incluido en Kenney Game Assets All-in-1) | Kenney | CC0 1.0 |  |
| `music/day_farm_frolics.ogg` | Kenney — Music Loops: `Farm Frolics.ogg` · https://kenney.nl (pack «Music Loops» 1.1, incluido en Kenney Game Assets All-in-1) | Kenney | CC0 1.0 |  |
| `music/day_flowing_rocks.ogg` | Kenney — Music Loops: `Flowing Rocks.ogg` · https://kenney.nl (pack «Music Loops» 1.1, incluido en Kenney Game Assets All-in-1) | Kenney | CC0 1.0 |  |
| `music/danger_infinite_descent.ogg` | Kenney — Music Loops: `Infinite Descent.ogg` · https://kenney.nl (pack «Music Loops» 1.1, incluido en Kenney Game Assets All-in-1) | Kenney | CC0 1.0 |  |
| `music/day_mischief_stroll.ogg` | Kenney — Music Loops: `Mishief Stroll.ogg` · https://kenney.nl (pack «Music Loops» 1.1, incluido en Kenney Game Assets All-in-1) | Kenney | CC0 1.0 |  |

## 4. Comprobación de licencias

- Kenney: todas las páginas de los packs indican «Creative Commons CC0» y cada pack incluye su `License.txt` CC0
  (copiados en `assets/models/*/License.txt` y `assets/sounds/licenses/`).
- FreePD.com: «This music is all licensed CC0 1.0 Universal Public Domain Dedication» (copia archivada del sitio).
- Freesound: cada grabación usada figura como «Creative Commons 0» en su página (se verificaron, entre otras,
  414098, 588401 y 547203); los créditos completos de los recopiladores están en `assets/sounds/licenses/`.
- OpenGameArt: los packs usados están publicados bajo CC0 (p. ej. «7 Eating Crunches» de StarNinjas).
- Fuentes: SIL Open Font License 1.1, texto incluido en `assets/fonts/`.

