# Arquitectura técnica

Godot 4.7.2, GDScript con tipos, renderizador **Compatibilidad** (OpenGL ES 3 / OpenGL 3.3) y
física **Jolt**. Son unas 11 000 líneas de GDScript repartidas en scripts pequeños por
sistema, sin plugins.

## Principios

1. **Datos fuera del código.** Costes, recetas, tiempos, producciones, niveles, enemigos,
   misiones, tecnologías, zonas de la isla y densidades están en `data/**.json`. `GameData`
   los carga una vez y `GameData.validate()` comprueba las referencias cruzadas: objetos,
   tecnologías, modelos e iconos.
2. **Sin dependencias circulares.** Los sistemas se comunican por señales de `EventBus`
   (`item_gathered`, `building_built`, `night_started`…) o consultan autoloads de nivel
   inferior. Ningún autoload conoce la escena del mundo.
3. **Economía independiente de la escena.** `Economy` simula edificios y almacén sin nodos
   3D. Por eso el progreso sin conexión es la misma simulación avanzada en pasos, y las pruebas
   pueden ejecutarla sin isla.
4. **Todo cambio de número tiene respuesta visual.** Barras de progreso sobre los edificios,
   pilas de recursos que crecen, trabajadores animados, avisos y sonidos.

## Autoloads (orden de carga)

| Autoload | Archivo | Responsabilidad |
|---|---|---|
| `EventBus` | `scripts/core/event_bus.gd` | Señales globales y avisos (`notify`). |
| `GameData` | `scripts/core/game_data.gd` | Carga y validación de `data/`, y acceso a objetos, recetas, edificios y equilibrio (`bf("player.walk_speed")`). |
| `Settings` | `scripts/core/settings.gd` | Ajustes del jugador (`user://settings.cfg`), preajustes de calidad y mapa de entradas. |
| `ModelLibrary` | `scripts/core/model_library.gd` | Caché de mallas OBJ, materiales canónicos, remapeo de paleta y **mallas horneadas** (ver Rendimiento). |
| `AudioManager` | `scripts/core/audio_manager.gd` | Efectos con variaciones, ambiente por zona y hora, y música de día, noche y peligro con fundidos. |
| `GameState` | `scripts/core/game_state.gd` | Inventario del jugador, nivel, experiencia, estadísticas y supervivencia persistente. |
| `TechTree` | `scripts/technology/tech_tree.gd` | Puntos, investigación, edades y modificadores acumulados (`mod("gather_mult")`). |
| `Economy` | `scripts/incremental/economy.gd` | Almacén con capacidad, edificios (registro, niveles, daño), *tick* de producción cada 0,25 s, ritmos por minuto y simulación sin conexión. |
| `Workers` | `scripts/incremental/worker_manager.gd` | Contratación, alojamiento, asignación automática, entrenamiento y bonificaciones. |
| `Quests` | `scripts/technology/quest_manager.gd` | Cadena de objetivos basada en estadísticas (no en eventos sueltos, para no perder progreso). |
| `SaveManager` | `scripts/save_system/save_manager.gd` | Guardado atómico, copia de seguridad, suma de verificación, autoguardado y progreso sin conexión. |

## Flujo de escenas

```
scenes/main/main.tscn (main.gd)
 ├─ MainMenu (main_menu.gd): Continuar / Nueva partida / Ajustes / Créditos / Salir
 └─ World (scenes/world/world.tscn, world.gd), creada al empezar o continuar
     ├─ IslandGenerator   alturas, zonas, río, laguna, cráter y caminos (desde world.json)
     ├─ Terreno           mallas por trozos de 64 m con color de vértice + colisión HeightMapShape3D
     ├─ Agua              plano con shader (water.gdshader)
     ├─ DecorScatter      decoración fusionada en una malla por trozo de 64 m
     ├─ POIManager        naufragio, campamento, ruinas, cementerio, puente, cueva…
     ├─ ResourceNodeManager  árboles, rocas, vetas y plantas (MultiMesh + rejilla espacial)
     ├─ BuildingManager + BuildMode   edificios y colocación con silueta
     ├─ EnemySpawner      fauna de día, criaturas de noche y guardianes
     ├─ DayNight          sol, luna, cielo (sky.gdshader), niebla y horas
     ├─ Weather           despejado, nublado, lluvia y tormenta (weather.gd)
     ├─ AmbientLife       luciérnagas, mariposas, polen, gaviotas, hojas y peces (ambient_life.gd)
     ├─ BeachTreasures    botellas y cofres que deja el mar (beach_treasures.gd)
     ├─ WorldEffects      partículas y efectos breves (effects.gd)
     ├─ Player (scenes/player/player.tscn)  CharacterBody3D + ProceduralRig + cámara
     └─ HUD (scenes/ui/hud.tscn)  barras, menú, joystick, botones táctiles y paneles
```

## Mundo

- La isla mide 256 m, con 129×129 alturas cada 2 m. La generación es determinista con la
  semilla de `balance.json`:
  - Ruido para el relieve, más montes definidos en `world.json`.
  - Cráter para la cueva, cauce del río y laguna.
  - Caminos de tierra entre los lugares de interés.
- Las zonas se calculan por altura, distancia a la costa y regiones dibujadas. De ellas
  dependen el color del terreno, los recursos (`resources` en `world.json`), la decoración, el
  sonido de los pasos y los enemigos.
- Las regiones bloqueadas (jungla y cueva) son zonas no transitables hasta que se repara el
  puente o se despeja el derrumbe. El estado se guarda.
- **Clima** (`Weather`): máquina de estados con duraciones y probabilidades de
  `balance.json → weather`. Escribe el estado en `GameState.weather` (se guarda); `SurvivalStats`
  y `Economy` lo leen para reducir la sed y acelerar los edificios con `rain_bonus` (nunca en la
  simulación sin conexión). `DayNight` mezcla la nubosidad, la lluvia y los relámpagos en la luz,
  el cielo y la niebla.
- **Sin simulación lejana**: los enemigos sólo se procesan cerca del jugador. Los edificios
  lejanos siguen produciendo en `Economy`, pero sin efectos visuales fuera de
  `visual_production_radius`.

## Animación procedural (`ProceduralRig`)

- Los modelos OBJ de Kenney no tienen esqueleto. `ProceduralRig` separa la malla en piernas,
  brazos y tronco (por superficies o por la posición de los triángulos) y cuelga cada pieza de
  un pivote en su articulación.
- Cada fotograma se calcula una **pose base** (andar, respirar, en el aire) y encima se mezcla
  la **acción** en curso (`play_action`): `attack`, `chop`, `mine`, `gather`, `eat`, `hammer`,
  `cheer`, `windup`, `lunge` y `flinch`, con curvas de anticipación, golpe y recuperación.
- El tronco se dobla por la cintura (el modelo gira alrededor de la cadera y las piernas
  compensan). La voltereta gira un nodo intermedio alrededor del centro del cuerpo.
- Extras: aplastamiento al aterrizar, aparición con rebote, pausa de impacto (`freeze`), aviso
  naranja (`telegraph`), caídas al morir y animaciones de reposo.
- La capa de destello solo se asigna mientras se ve, para no añadir una pasada de dibujo por
  pieza a cada personaje.

## Renderizado

- **Compatibilidad** en todas las plataformas (OpenGL ES 3 en Android).
- **Sin sombras en tiempo real.** En Compatibilidad, una luz direccional con sombras se dibuja
  en una pasada aditiva que se tonemapea y se pasa a sRGB por separado y se suma sobre la
  pasada base (`scene.glsl`, `USE_ADDITIVE_LIGHTING`). Esa suma en espacio sRGB lava las zonas
  iluminadas al mediodía y, además, duplica las llamadas de dibujo. Se comprobó con capturas
  del renderizador real. En su lugar:
  - `BlobShadow`: un cuadro con degradado radial bajo personajes, criaturas, animales,
    trabajadores y objetos, apoyado en el terreno y orientado con la pendiente.
  - Sombras fijas bajo los edificios y un MultiMesh de sombras por trozo para árboles, rocas y
    arbustos (calidad media y alta).
- **Cielo** (`assets/shaders/sky.gdshader`): degradado, sol, luna con halo, estrellas y nubes
  con ruido (menos octavas en calidad baja y en el mapa de radiancia).
- **Viento** (`assets/shaders/foliage.gdshader`): el peso del balanceo se hornea en el alfa del
  color de vértice (0 en la base, 1 en la copa) y el *shader* desplaza los vértices en
  coordenadas de mundo. Lo usan los MultiMesh de vegetación, la decoración fusionada y las
  decoraciones con `"sway": true`. Respeta `OUTPUT_IS_SRGB` como el material estándar.
- **Efectos** (`WorldEffects`): partículas por CPU con un tope de 40 simultáneas y cantidades
  reducidas en calidad baja; estelas, anillos y destellos son mallas sencillas que se animan con
  *tweens*.

## Rendimiento (objetivo: 30 FPS en Android modesto)

- **Mallas horneadas**: `ModelLibrary.baked_*` lee el color de la textura de paleta de Kenney
  (`colormap.png`) en cada vértice y lo guarda como color de vértice.
  - Todas las piezas comparten **un único material**.
  - Un edificio de varias piezas, o un MultiMesh de 100 árboles, se dibuja con 1 llamada.
  - Las texturas de paleta se importan sin compresión VRAM (`detect_3d/compress_to=0`), para
    poder leerlas en la CPU en cualquier plataforma.
- **MultiMesh** por tipo de recurso. Al agotar un nodo se oculta su instancia, sin crear ni
  destruir nodos.
- **Decoración** fusionada por trozos de 64 m con distancia de visibilidad. La densidad
  depende de la calidad gráfica.
- **Luces**: un sol direccional sin sombras (ver Renderizado) y luces puntuales sin sombras
  sólo en fogatas, antorchas, el laboratorio y algunos lugares de interés. En la partida de
  prueba hay 7.
- **Física sencilla**: terreno `HeightMapShape3D`, cilindros y cajas para árboles, rocas y
  edificios, y capas separadas (terreno, jugador, enemigos, edificios, recursos, obstáculos).
- **Calidad** baja, media o alta: sombras suaves (solo personajes o todo), distancia de visión,
  densidad de vegetación, escala de renderizado, MSAA, cantidad de partículas, gotas de lluvia y
  detalle de las nubes. Hay límite de FPS de 30, 60 o sin límite.

## Guardado (`user://savegame.json`)

- **Contenido**:
  - Datos del jugador: posición, supervivencia, inventario, nivel y estadísticas.
  - Base: almacén, edificios (tipo, posición, giro, nivel, salud y progreso de producción) y
    trabajadores.
  - Progreso: tecnologías, misiones y nodos agotados con su tiempo de reaparición.
  - Mundo: regiones, día y hora, y mochila de muerte.
  - Fecha (`saved_at`) y `version`.
- **Escritura**: primero en `savegame.tmp`. La versión anterior pasa a `savegame.bak` y después
  se renombra el temporal. Se calcula una suma SHA-256 sobre el JSON canónico. Al cargar, si el
  principal falla (no se puede leer, JSON roto o suma incorrecta), se usa la copia.
- **Sin conexión**: `now - saved_at` se limita a 8 h (más 4 h con *Logística*) y se simula en
  hasta 1800 pasos. Sólo cuenta la economía. Si el reloj se ha atrasado, no se genera nada.

## Interfaz

- Todo se construye por código con `UITheme`: estilos, botones redondos, paneles e iconos de
  Kenney. Los textos usan Fredoka y Nunito.
- El escalado es `canvas_items` + `expand`, con la escala de interfaz configurable.
- Los controles táctiles son `TouchJoystick`, `TouchLook` y `TouchButton` (multitáctil, que
  ignora los eventos de ratón emulados). También funcionan con ratón gracias a
  `emulate_touch_from_mouse`.
- Paneles: inventario, fabricación, construir, edificio, tecnologías, trabajadores, mapa,
  producción, ajustes, bienvenida sin conexión y muerte. Todos heredan de `UIPanel`.

## Pruebas y CI

- `tests/test_runner.tscn` hace 273 comprobaciones de toda la sección 19 y de los sistemas de la
  v1.1 (animación, efectos, clima, cielo, decoración, interfaz). Incluye la compilación de todos
  los *shaders*: el renderizador de prueba sin GPU también los analiza y avisa de errores.
  `tests/main_flow.tscn` prueba el flujo del menú.
- `tests/tools/capturas.tscn` hace capturas con el **renderizador real**. En GitHub Actions se
  ejecuta con Xvfb y OpenGL de Mesa (llvmpipe) cuando el mensaje del commit contiene
  `[capturas]`, y las imágenes se guardan en `docs/capturas/`.
- `tests/ci_entry.tscn` es la escena principal **sólo** en el preset *Linux (pruebas CI)*, por
  la característica `pruebas_ci`. Permite ejecutar las mismas pruebas sobre el juego exportado.
- `.github/workflows/exportar.yml` usa Godot oficial y hace, por orden:
  1. Importar el proyecto.
  2. Ejecutar las pruebas en el editor.
  3. Exportar y probar la build de pruebas.
  4. Exportar APK, Linux y Windows.
  5. Verificar la firma y el manifiesto del APK.
  6. Arrancar la build de Linux.
  7. Empaquetar con sumas SHA-256 y adjuntar a la release.
