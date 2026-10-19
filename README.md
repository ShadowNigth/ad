# Isla Salvaje: Supervivencia Incremental

Juego 3D *low poly* de **supervivencia, progresión incremental y automatización** en una isla
tropical. Hecho con **Godot 4.7.2** (GDScript, renderizador *Compatibilidad*, física Jolt).
La plataforma principal es **Android** (controles táctiles). También funciona en **Linux** y
**Windows** con teclado y ratón.

Empiezas como náufrago en la playa. Recoges madera, piedra y fibra a mano. Fabricas tus
primeras herramientas, levantas un refugio y sobrevives a las noches. Después vas construyendo
una base que produce sola: leñadores, canteras, aserraderos, fundiciones y fábricas, con
trabajadores, árbol tecnológico y progreso mientras no juegas.

---

## Descargar y jugar

Los archivos están en **[Releases](https://github.com/ShadowNigth/ad/releases/latest)**.

| Plataforma | Archivo | Instalación |
|---|---|---|
| **Android 7.0 o superior** (ARM 64 y 32 bits) | `IslaSalvaje-vX.Y.Z-android.apk` | Ver abajo |
| **Linux** x86_64 | `IslaSalvaje-vX.Y.Z-linux-x86_64.zip` | Descomprimir y ejecutar `./IslaSalvaje.x86_64` |
| **Windows** 10/11 de 64 bits | `IslaSalvaje-vX.Y.Z-windows-x86_64.zip` | Descomprimir y ejecutar `IslaSalvaje.exe` |

`SHA256SUMS.txt` sirve para comprobar las descargas (`sha256sum -c SHA256SUMS.txt`).

### Android

1. Descarga el `.apk` en el teléfono, desde la página de Releases.
2. Ábrelo. Si Android lo pide, permite **«Instalar apps desconocidas»** para el navegador o el
   gestor de archivos.
3. Pulsa **Instalar** y abre **Isla Salvaje**. El juego se pone en horizontal y en pantalla completa.

Desde un ordenador, con depuración USB activada: `adb install -r IslaSalvaje-vX.Y.Z-android.apk`.

- El APK no pide ningún permiso.
- Las versiones nuevas se instalan **encima** de la anterior y conservan la partida.
- Al desinstalar la app se borra la partida, porque se guarda en el almacenamiento interno de la app.
- La primera vez, en móviles de 4 núcleos o menos, se elige calidad *baja* y 30 FPS. En los
  demás, calidad *media* y 60 FPS. Se puede cambiar en **Ajustes**.

### Linux

```bash
unzip IslaSalvaje-vX.Y.Z-linux-x86_64.zip -d IslaSalvaje
cd IslaSalvaje && chmod +x IslaSalvaje.x86_64 && ./IslaSalvaje.x86_64
```

Requisitos:
- OpenGL 3.3 o superior (cualquier GPU de los últimos ~12 años, o Mesa).
- X11 o Wayland (XWayland).

Las partidas se guardan en `~/.local/share/IslaSalvaje/`.

### Windows

1. Descomprime el `.zip` y ejecuta `IslaSalvaje.exe`.
2. El ejecutable no está firmado. Si SmartScreen avisa, pulsa *Más información →
   Ejecutar de todas formas*.

Las partidas se guardan en `%APPDATA%\IslaSalvaje\`.

---

## Controles

### Táctil (Android)

| Control | Acción |
|---|---|
| Joystick virtual (abajo a la izquierda) | Moverse. Si lo empujas hasta el borde, corres (gasta estamina). |
| Arrastrar en la mitad derecha de la pantalla | Girar la cámara en tercera persona |
| Pellizcar con dos dedos | Acercar o alejar la cámara |
| Botón grande de la **mano** | Acción contextual: talar, picar, recoger, beber, abrir cofres o el panel de un edificio. Si lo mantienes, repite la acción. |
| Botón de la **espada** | Atacar o usar la herramienta equipada |
| Botón de **salto** | Saltar |
| Botón de la **flecha curva** | Esquivar, con invulnerabilidad breve |
| Botón de las **bayas** | Comer o beber lo mejor que tengas |
| Menú superior derecho | Inventario, Fabricación, Construir, Tecnologías, Trabajadores, Mapa, Producción y Ajustes |
| Modo construcción | La silueta aparece delante del personaje: verde si se puede colocar, roja si no (con el motivo). Tienes botones para **girar**, **confirmar** y **cancelar**. |

Todos los botones admiten **multitáctil**: puedes moverte, girar la cámara y atacar a la vez.

### Teclado y ratón (Linux / Windows)

| Tecla | Acción | Tecla | Acción |
|---|---|---|---|
| `W A S D` / flechas | Moverse | `Mayús` | Correr |
| `Espacio` | Saltar | `Q` / `Ctrl` | Esquivar |
| `E` | Interactuar / recolectar | `F` / `J` | Atacar |
| `H` | Comer o beber lo mejor | `I` / `Tab` | Inventario |
| `C` | Fabricación | `B` | Construir |
| `T` | Tecnologías | `M` | Mapa |
| `P` | Producción y estadísticas | `Esc` | Ajustes / cerrar panel / cancelar construcción |
| `R` | Girar edificio | `Intro` | Confirmar construcción |
| Arrastrar con clic izquierdo en la mitad derecha | Girar la cámara | Rueda del ratón | Zoom |

---

## Mecánicas

- **Isla compacta de 256 m.**
  - Zonas: playas, pradera central, bosque viejo, tierras altas rocosas, río y laguna.
  - Caminos de tierra reconocibles y lugares de interés: naufragio con cofre, claro del
    campamento, ruinas antiguas, cementerio pirata, mirador, puente roto y derrumbe de la cueva.
  - Ciclo de día y noche: 12 minutos reales por día completo. Las noches son más peligrosas.
- **Regiones que se desbloquean.**
  - **Jungla de las ruinas**: reparar el puente roto con la tecnología *Puentes* y 20 tablas,
    10 cuerdas y 20 maderas.
  - **Cueva de cristal**: despejar el derrumbe con *Explosivos* y 12 de carbón, 12 de fibra y
    4 cuerdas.
  - Cada una tiene recursos especiales y un **guardián**.
- **Supervivencia.**
  - Cuatro barras: salud, hambre, sed y estamina. Bajan poco a poco (de noche un 15 % más
    rápido) y están equilibradas para no frenar la progresión.
  - El agua sin tratar puede enfermarte: se recoge con cuenco o cubo y se purifica en la
    fogata o en el purificador.
  - Te curas comiendo, con vendas y tónicos, o durmiendo en el refugio hasta el amanecer.
  - **Muerte**: pierdes el 50 % de lo que llevas encima, que queda en una mochila recuperable
    durante 30 minutos. La base no se toca.
- **Recursos (47 objetos).**
  - Iniciales: madera, piedra, fibra, bayas, agua, comida y carbón.
  - Intermedios: mineral y lingotes de hierro, cuerda, tablas, hierbas medicinales y piezas
    mecánicas.
  - Avanzados: acero, componentes electrónicos, combustible, cristales de energía y reliquias.
  - Todos se pueden conseguir a mano y de forma automática.
  - Herramientas con calidad y durabilidad. Ejemplo con la madera por golpe: mano 1,
    hacha de piedra 3, hacha avanzada 8.
- **Fabricación (27 recetas).**
  - Cola de fabricación con barra de progreso.
  - Las recetas bloqueadas muestran qué tecnología o estación necesitan.
- **Construcción (21 edificios).**
  - Refugio, fogata, almacén, huerto, purificador, puesto de leñador, cantera, choza de
    recolección, aserradero, horno de carbón, mina, fundición, taller, granja de animales,
    laboratorio, generador, refinería, fábrica avanzada, antorchas, torre de defensa y cabaña
    de trabajadores.
  - Cada edificio tiene **niveles** (más producción, más velocidad o menos consumo), un límite
    de unidades y costes progresivos.
  - Su panel permite ver estadísticas (producción por minuto, nivel, coste de mejora), mejorar,
    reparar y demoler.
  - La producción es por intervalos, con barra de progreso visible sobre cada edificio.
- **Trabajadores**: leñador, minero, granjero, recolector y artesano.
  - Cada uno tiene coste de contratación creciente y acelera de verdad los edificios a los que
    se asigna.
  - Suben de nivel de habilidad y se ven trabajando en la base.
  - La cabaña de trabajadores añade plazas.
- **Árbol tecnológico (44 tecnologías en 8 ramas).**
  - Ramas: Supervivencia, Recolección, Construcción, Agricultura, Minería, Fabricación,
    Automatización y Exploración.
  - Los puntos se ganan al subir de nivel con la experiencia, al completar objetivos y en el
    laboratorio.
  - Seis edades: primitiva → herramientas de piedra → agricultura → metalurgia → máquinas →
    automatización.
- **Objetivos (29 misiones encadenadas)**: primeros pasos, primera herramienta, un techo
  propio, la primera noche, primera automatización… hasta «Señor de la isla».
- **Enemigos (10 tipos)**: cangrejos y jabalíes; tigres en la jungla; esqueletos, náufragos
  malditos y espíritus de noche; y dos guardianes de zona con barra de salud propia.
  - Usan detección, persecución y enfriamiento entre ataques. Tienen distintas vidas,
    velocidades y daños, y no atraviesan edificios.
  - Los ciervos y conejos son pacíficos y se cazan para conseguir carne y cuero.
- **Progreso sin conexión.**
  - Al volver se calcula lo que produjeron los edificios y trabajadores, con un máximo de 8 h
    (ampliable a 12 h con *Logística*).
  - Sólo cuenta la economía: no baja el hambre ni la sed y no hay pérdidas.
  - Una pantalla de bienvenida resume lo ganado.
- **Guardado.**
  - Contenido: posición, inventario, almacén de la base, edificios con su nivel, trabajadores,
    tecnologías, misiones, estado de supervivencia, progreso de producción y fecha.
  - Autoguardado cada 60 s y al salir o pasar a segundo plano.
  - Escritura atómica con copia de seguridad y suma de comprobación: un archivo dañado no
    borra la partida.
- **Ajustes**: sensibilidad, distancia e inversión vertical de la cámara, volúmenes (general,
  música, efectos y ambiente), calidad gráfica (baja, media o alta), límite de FPS (30, 60 o sin
  límite), mostrar FPS y escala de la interfaz (85–130 %).

Todos los números del juego están en `data/` (JSON): costes, recetas, tiempos, producciones,
niveles, enemigos, misiones y equilibrio.

---

## Abrir el proyecto en Godot

1. Instala **Godot 4.7.2 estándar** (no hace falta la versión .NET) desde
   https://godotengine.org/download/archive/4.7.2-stable/ o desde
   [GitHub](https://github.com/godotengine/godot/releases/tag/4.7.2-stable).
2. Clona el repositorio:
   ```bash
   git clone https://github.com/ShadowNigth/ad.git IslaSalvaje
   ```
3. En el Gestor de proyectos, pulsa *Importar*, elige `IslaSalvaje/project.godot` y ábrelo.
   La primera importación tarda uno o dos minutos.
4. Pulsa **F5** para jugar.

Desde la terminal (Linux):

```bash
godot --path IslaSalvaje                  # abre el juego directamente
godot --path IslaSalvaje --editor         # abre el editor
```

No hay plugins, servicios externos ni descargas en tiempo de ejecución. Todos los recursos
están dentro del proyecto.

## Exportar

Los presets ya están en `export_presets.cfg`: **Android**, **Linux**, **Windows** y uno
interno, *Linux (pruebas CI)*.

### Automático con GitHub Actions (recomendado)

El workflow `.github/workflows/exportar.yml` usa el Godot oficial y sus plantillas:

- **En cada push**: importa el proyecto, ejecuta todas las pruebas (en el editor y sobre una
  build exportada), exporta APK, Linux y Windows, y los deja como artefactos de la ejecución.
- **Al publicar una release**: repite todo y **adjunta los archivos a la release**.

Para publicar una versión nueva:

1. Sube `config/version` en `project.godot` (opcional: el workflow toma la versión de la
   etiqueta).
2. En GitHub, ve a *Releases → Draft a new release*, crea la etiqueta `vX.Y.Z` y pulsa
   **Publish**. También puedes usar `gh release create vX.Y.Z --target <rama> --notes "…"`.
3. En unos 10 minutos aparecen el APK, los zip y `SHA256SUMS.txt` en la release.

El *version code* de Android se calcula a partir de la etiqueta (`v1.2.3` → `10203`), así que
cada versión se instala sobre la anterior. La firma del APK se explica en
[`tools/android/LEEME.md`](tools/android/LEEME.md).

### Manual desde el editor: Android

1. Instala lo siguiente:
   - **JDK 17**, por ejemplo Temurin.
   - **Android SDK** con *platform-tools* y *build-tools* 34 o superior. Lo más fácil es
     instalar Android Studio, o *commandline-tools* y luego
     `sdkmanager "platform-tools" "build-tools;35.0.0"`.
2. En Godot, ve a *Editor → Configuración del editor → Exportar → Android* y rellena
   *Java SDK Path* y *Android SDK Path*.
3. Ve a *Editor → Gestionar plantillas de exportación → Descargar e instalar*.
4. Ve a *Proyecto → Exportar…*, elige **Android** y pulsa *Exportar proyecto*. Se genera
   `build/android/IslaSalvaje.apk`.
   - El preset ya apunta a la clave de `tools/android/`.
   - Si prefieres tu propia clave, cambia *Keystore → Release*, *User* y *Password*, o usa las
     variables `GODOT_ANDROID_KEYSTORE_RELEASE_PATH`, `GODOT_ANDROID_KEYSTORE_RELEASE_USER` y
     `GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD`.
5. Instala en el móvil con `adb install -r build/android/IslaSalvaje.apk`, o con el botón de
   *Despliegue con un clic* del editor si el móvil está conectado.

Línea de comandos equivalente:

```bash
godot --headless --path . --import
godot --headless --path . --export-release "Android" build/android/IslaSalvaje.apk
```

### Manual: Linux y Windows

Con las plantillas instaladas:

```bash
godot --headless --path . --export-release "Linux" build/linux/IslaSalvaje.x86_64
godot --headless --path . --export-release "Windows" build/windows/IslaSalvaje.exe
```

El `.pck` va incrustado en el ejecutable, así que el resultado es un solo archivo, más las DLL
de ANGLE en Windows si las plantillas las incluyen.

---

## Pruebas

### Automáticas

Se ejecutan sin ventana y devuelven código de salida distinto de 0 si algo falla:

```bash
godot --headless --path . tests/test_runner.tscn   # 227 comprobaciones (sección 19 completa)
godot --headless --path . tests/main_flow.tscn     # menú → nueva partida → guardar → menú → continuar → resumen sin conexión
```

`tests/test_runner.tscn` cubre lo siguiente (informe también en `user://test_report.txt`):

| Área | Qué se comprueba |
|---|---|
| Proyecto y datos | Los JSON cargan sin referencias rotas: objetos, tecnologías, modelos e iconos. Hay 8 ramas tecnológicas. |
| Modelos y texturas | Los OBJ se importan como `Mesh`, conservan su textura (`colormap.png`) y sus superficies con varios materiales. El personaje tiene el origen en los pies. |
| Inventario | Pilas y huecos, quitar sin alterar cantidades, mover sin duplicar, durabilidad y serialización sin pérdidas. |
| Mundo | Mapa de alturas, todas las zonas y generación determinista. La colisión del terreno coincide con la malla. Apareces en tierra firme y hay lugares de interés. |
| Bucle principal | Cofre del naufragio → talar 30 de madera y recoger piedra y fibra → fabricar herramientas → fogata, refugio y puesto de leñador con el modo construcción → agua de la laguna hervida en la fogata → el leñador produce solo. Los objetivos avanzan con el bucle. |
| Movimiento táctil | El joystick mueve al jugador y se detiene al soltarlo. Funciona el multitáctil (joystick y botón a la vez). Arrastrar en la zona derecha gira la cámara. |
| Recolección | Cada golpe resta vida al nodo, que se agota, se guarda y reaparece. Con hacha se obtiene más madera. La veta de hierro exige pico. El botón de acción recoge. |
| Fabricación | Sin materiales no se fabrica. Consume exactamente los ingredientes, exige estación y tecnología, y al cancelar la cola se devuelve lo de la unidad en curso. |
| Construcción | Colocación válida y martillo obligatorio. Descuenta el coste exacto, con costes progresivos. Se entra y se sale del modo construcción. |
| Producción | Producción en vivo y mejoras que cambian tiempo de ciclo y producción por minuto. Sin entrada se detiene (sin producción infinita). Almacén con límite, sin negativos, y los edificios dañados producen más lento. |
| Trabajadores y tecnologías | Requisitos, alojamiento, asignación, aceleración real, coste creciente, entrenamiento, puntos, desbloqueos y edades. |
| Misiones | Progreso, finalización y registro. |
| Combate | Los enemigos persiguen, hacen y reciben daño. Hay invulnerabilidad tras un golpe. Mueren y sueltan botín. Las fogatas iluminan y la torre de defensa dispara. |
| Muerte | Pierdes la mitad de lo que llevas, conservas las herramientas y la mochila se recupera sin duplicar. |
| Día, noche y regiones | Anochece a las 20:30 y se puede dormir hasta la mañana. Hambre y sed bajan suavemente. El puente roto se repara con tecnología y la jungla queda accesible. |
| Guardado | Ida y vuelta completa (inventario, edificios, tecnologías, trabajadores, almacén, supervivencia y posición). Cargar dos veces no duplica. Si el archivo principal está dañado se usa la copia de seguridad. La suma de verificación detecta manipulaciones. |
| Sin conexión | No baja el hambre. Límite de 8 h. Respeta la capacidad del almacén. Las ausencias cortas no generan informe y un reloj atrasado no genera recursos. |
| Interfaz | Controles dentro de pantalla a 854×480, 1280×720, 2400×1080 y 1024×768. Se abren todos los paneles. **Ningún botón sin función** (324 revisados). |
| Rendimiento | Vegetación en MultiMesh y pocas luces. La isla se genera en menos de 6 s. Se mide el coste del *tick* de producción y de la simulación sin conexión. |

### Resultados

- **Godot 4.7.2 oficial (GitHub Actions)**:
  - `test_runner`: 227 correctas, 0 fallidas. `main_flow`: OK.
  - Lo mismo **sobre la build exportada** de Linux: se ejecuta el `.pck` real, con scripts
    compilados y recursos importados.
- **Escritorio sin GPU (servidor de pruebas)**: 227/0.
  - La isla se genera en ~1,3 s, con 604 nodos de recursos y ~2500 piezas de decoración.
  - 131 MultiMesh con 663 instancias, ~150 mallas sueltas y 7 luces.
  - *Tick* de producción: ~65 µs. Simular 8 h sin conexión: ~110–130 ms.
- **APK**: GitHub Actions comprueba en cada compilación su firma (`apksigner verify`), el
  manifiesto (`aapt2 dump badging`) y las librerías ARM incluidas.

### Pendiente de verificar en hardware real

- **FPS en un Android modesto.** El objetivo es 30 FPS en gama baja y 60 en gama media, y el
  juego trae preajustes de calidad para eso. Todavía no se ha medido en un dispositivo físico:
  todas las pruebas se hicieron sin GPU.
- El aspecto visual sólo se revisó con un renderizador por software (`tools/render_snapshot.py`)
  y con capturas de las disposiciones de la interfaz. Puede haber pequeñas diferencias de color
  o de sombreado con una GPU real.
- La build de **Windows** se genera con las plantillas oficiales, pero no se ha ejecutado en un
  PC con Windows.

## Errores conocidos

| # | Error | Cómo reproducirlo | Impacto |
|---|---|---|---|
| 1 | Al cerrar el juego desde las pruebas aparecen avisos `ObjectDB instances were leaked` y `resources still in use at exit`. | Ejecutar `godot --headless --path . tests/test_runner.tscn` y mirar las últimas líneas. | Ninguno para el jugador: las pruebas salen con `quit()` sin liberar la escena del mundo. |
| 2 | La prueba de archivo dañado imprime `ERROR: Parse JSON failed`. | Igual que el anterior: se corrompe el guardado a propósito para comprobar que se recupera la copia. | Ninguno: es el comportamiento esperado. |
| 3 | En Windows, SmartScreen avisa al abrir `IslaSalvaje.exe`. | Descargar el zip de la release y ejecutar el `.exe`. | El ejecutable no está firmado con un certificado de código. Se abre con *Más información → Ejecutar de todas formas*. |

Si encuentras otro, abre un *issue* con el dispositivo, los pasos y, si puedes, el registro.
En PC está en `~/.local/share/IslaSalvaje/logs/`. En Android, usa `adb logcat -s godot`.

---

## Estructura del proyecto

```
project.godot, export_presets.cfg     configuración del motor y de exportación
data/                                 TODO el equilibrio en JSON
  balance.json, items/, recipes/, buildings/, technologies/, workers/,
  enemies/, quests/, world/ (zonas, relieve, río, caminos, lugares, densidades)
scenes/{main,world,player,ui}/        escenas principales
scripts/
  core/          autoloads: EventBus, GameData, Settings, ModelLibrary, AudioManager, GameState
  inventory/ crafting/ incremental/ (economía, trabajadores) technology/ (árbol, misiones)
  world/         generador de la isla, decoración agrupada, lugares de interés, efectos
  resources/ player/ survival/ buildings/ enemies/ save_system/ ui/ main/
assets/
  models/<pack>/   OBJ + MTL + Textures/colormap.png + License.txt + SOURCE.md
  sounds/<tipo>/ music/   OGG (licencias en sounds/licenses/)
  textures/ icons/ fonts/ shaders/
tests/           pruebas automáticas y herramientas de captura
tools/           scripts de Python del flujo de recursos y la firma de Android
docs/ARQUITECTURA.md   descripción técnica
ASSET_CREDITS.md       procedencia y licencia de cada recurso
```

Más detalles en [`docs/ARQUITECTURA.md`](docs/ARQUITECTURA.md).

## Flujo de recursos (assets)

Todos los recursos son de fuentes legales, la mayoría **CC0**, y están dentro del repositorio.
[`ASSET_CREDITS.md`](ASSET_CREDITS.md) lista cada archivo con su fuente, licencia y autor. Se
genera con `tools/generate_credits.py`.

| Herramienta | Qué hace |
|---|---|
| `tools/fetch_assets.py` | Descarga los paquetes (Kenney, Google Fonts, sonidos de Freesound, OpenGameArt y FreePD) desde espejos de GitHub con *commits* fijados. Así se puede reproducir y verificar. |
| `tools/process_audio.py` | Recorta, normaliza, separa tomas y convierte a OGG. Escribe `assets/sounds/licenses/audio_sources.json`. |
| `tools/render_icons.py` | Renderiza los iconos de objetos y edificios a partir de los OBJ. Renderizador propio en NumPy, sin GPU. |
| `tools/render_snapshot.py` / `render_layout.py` | Capturas de la escena y de la interfaz para revisarlas sin GPU (junto con `tests/tools/*.tscn`). |
| `tools/generate_credits.py` | Regenera `ASSET_CREDITS.md`. |
| `tools/create_android_keystore.py` | Crea una clave de firma PKCS#12 para Android sin necesitar Java. |

Dependencias de Python de las herramientas: `numpy pillow soundfile scipy cryptography`.
**No hacen falta para jugar ni para exportar.**

## Créditos

- Modelos 3D, interfaz, iconos y gran parte de los efectos: **Kenney** (kenney.nl, CC0).
- Música: **Kevin MacLeod** vía FreePD (CC0) y Kenney Music Loops (CC0).
- Grabaciones de campo y efectos: autores de **Freesound** y **OpenGameArt** (CC0).
- Fuentes: **Fredoka** y **Nunito** (SIL Open Font License 1.1). Las licencias van dentro de
  cada build y en la carpeta `licencias/` de los zip.

La lista completa está en [`ASSET_CREDITS.md`](ASSET_CREDITS.md).
