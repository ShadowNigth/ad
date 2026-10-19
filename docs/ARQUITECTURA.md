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
     ├─ DayNight          sol, cielo, niebla y horas
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
- **Sin simulación lejana**: los enemigos sólo se procesan cerca del jugador. Los edificios
  lejanos siguen produciendo en `Economy`, pero sin efectos visuales fuera de
  `visual_production_radius`.

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
- **Luces**: un sol direccional con sombras (desactivadas en calidad baja) y luces puntuales
  sin sombras sólo en fogatas, antorchas, el laboratorio y algunos lugares de interés. En la
  partida de prueba hay 7.
- **Física sencilla**: terreno `HeightMapShape3D`, cilindros y cajas para árboles, rocas y
  edificios, y capas separadas (terreno, jugador, enemigos, edificios, recursos, obstáculos).
- **Calidad** baja, media o alta: sombras, distancia de visión, densidad de vegetación, escala
  de renderizado y MSAA. Hay límite de FPS de 30, 60 o sin límite.

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

- `tests/test_runner.tscn` hace 227 comprobaciones de toda la sección 19. `tests/main_flow.tscn`
  prueba el flujo del menú.
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
