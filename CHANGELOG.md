# Registro de cambios

## v1.1.0 — 2026-10-19

Actualización de **pulido visual y vida**: animaciones, efectos, clima, cielo nuevo y algo
más de contenido. Las partidas de la v1.0 se cargan sin cambios.

### Animación
- **Gestos por acción** en la animación procedural de los modelos OBJ:
  - Talar (golpe lateral con giro del tronco), picar (golpe por encima de la cabeza), recoger
    (agacharse y alcanzar), comer (llevarse la comida a la boca, que se ve en la mano),
    martillear al construir, mejorar o reparar, y celebrar al subir de nivel o cumplir objetivos.
  - El tronco se dobla por la cintura y las piernas compensan la inclinación.
  - Saltos con piernas recogidas, aterrizaje con aplastamiento según la caída, voltereta al
    esquivar y retroceso al recibir un golpe.
  - En reposo, los personajes miran alrededor o se estiran; los animales de la granja pastan.
- **Criaturas**:
  - Antes de atacar se echan atrás y parpadean en naranja (aviso de 0,45 s, en
    `data/balance.json`), y después embisten. Golpearlas durante el aviso interrumpe el ataque
    (salvo a los guardianes).
  - Un «!» aparece sobre su cabeza al detectarte y un «?» cuando te pierden de vista.
  - Aparecen creciendo (las nocturnas, con una nube violeta) y al morir caen de espaldas o de
    lado, levantan polvo y se encogen.
- Los trabajadores usan el gesto de su herramienta (hacha, pico, azada o martillo).

### Efectos
- Estela del arma al atacar, chispas y destello en los impactos y una breve pausa de impacto.
- Hojas que caen al golpear árboles y arbustos, chispas al picar roca y una nube de escombros
  al agotar un recurso.
- El botín sale despedido en arco, rebota y vuela hacia el jugador al acercarse (imán). Lo que
  sueltas tú no vuelve solo a la mochila.
- Polvo al esprintar, saltar y aterrizar; salpicaduras al entrar y caminar por el agua.
- Campo de visión un poco más abierto al esprintar y al esquivar.
- Fuego con llamas brillantes y brasas; humo suave.

### Mundo
- **Clima**: despejado, nublado, lluvia y tormenta, con duraciones y probabilidades en
  `data/balance.json`.
  - Lluvia con gotas y salpicaduras alrededor del jugador, sonido de lluvia y cielo gris.
  - Tormentas con relámpagos que iluminan la escena y truenos (grabación CC0 de Freesound).
  - Con lluvia **la sed baja un 40 % más despacio** y los **huertos crecen un 25 % más
    rápido**. El progreso sin conexión no usa esta bonificación.
  - Se puede desactivar en *Ajustes → Clima dinámico*.
- **Cielo nuevo**: degradado de día y noche, disco del sol, luna con halo, estrellas que
  parpadean y nubes que se desplazan (más densas con mal tiempo).
- **Viento**: palmeras, árboles, arbustos, hierba, flores y banderas se mecen (un único
  material con *shader*, sin coste extra de llamadas de dibujo).
- **Vida ambiental** cerca del jugador: luciérnagas de noche, mariposas y polen de día,
  gaviotas sobre la costa, hojas que caen en el bosque y peces que saltan en los bancos de pesca.
- **Tesoros en la playa**: el mar deja botellas y cofres con botín aleatorio (tabla en
  `data/balance.json`). Brillan para verse de lejos y se guardan con la partida.

### Construcción
- **7 decoraciones nuevas** (pestaña *Decoración*): valla, seto, macetas con flores, camino de
  losas, estandarte, estatua de piedra y fuente.
  - Cada una suma **belleza**: la base produce hasta un **10 % más** (0,5 % por punto).
  - Los caminos de losas no bloquean el paso, suenan a piedra y hacen caminar un **15 % más
    rápido**.
  - La fuente tiene un chorro de agua y su murmullo.
- Los edificios parados muestran un **icono flotante** con el material que les falta, «sin
  energía» o «almacén lleno».
- Los edificios muy dañados arden y echan humo; destruidos se ven ennegrecidos.
- Al construir: onda en el suelo y destellos. Al mejorar: anillo dorado, destellos que suben y
  el rótulo «¡Nivel N!».

### Interfaz
- **Rótulos grandes** para subir de nivel, cumplir objetivos, nueva era, nueva región,
  guardián derrotado, el amanecer y el anochecer.
- Las ventanas se cierran con una animación. Los botones se encogen al pulsarlos y rebotan al
  soltarlos.
- Las barras de supervivencia se deslizan hasta su valor y laten cuando un valor vital es bajo.
- Los avisos entran con un pequeño rebote. Los textos flotantes aparecen con un golpe de escala
  y los números de daño son más grandes.
- Los objetos recogidos **vuelan hasta su contador** del HUD (o hasta el botón de inventario).
- El reloj indica el clima cuando no está despejado.
- Nuevos ajustes: *Clima dinámico* y *Sacudidas de cámara*.

### Técnico
- Nuevos scripts: `scripts/world/weather.gd`, `ambient_life.gd` y `beach_treasures.gd`.
  Nuevos *shaders*: `assets/shaders/sky.gdshader` y `foliage.gdshader`.
- La capa de destello de los modelos animados solo se dibuja mientras se ve (menos llamadas de
  dibujo con muchas criaturas y trabajadores).
- Las pruebas automáticas pasan de 227 a 274: comprueban también que todos los *shaders*
  compilan, los gestos de animación, los avisos de las criaturas, el imán del botín, el clima y
  su efecto en la economía, el cielo de día y de noche, los tesoros, la belleza, los caminos,
  los iconos de edificios parados, los rótulos y el cierre animado de las ventanas.
- **Capturas con el renderizador real**: GitHub Actions puede renderizar escenas preparadas con
  OpenGL (Mesa) cuando el commit lleva `[capturas]` y las guarda en `docs/capturas/`.

## v1.0.0 — 2026-10-19

Primera versión completa y jugable de **Isla Salvaje: Supervivencia Incremental**.

### Juego
- **Isla tropical de 256 m**:
  - Playas, pradera, bosque viejo, tierras altas, río y laguna.
  - Caminos y lugares de interés: naufragio, campamento, ruinas, cementerio pirata, mirador,
    puente roto y cueva.
  - Ciclo de día y noche de 12 minutos.
- **Supervivencia**:
  - Salud, hambre, sed y estamina con drenaje suave.
  - El agua se trata en la fogata o en el purificador.
  - Te curas con comida, vendas, tónicos o durmiendo.
  - Al morir pierdes el 50 % de lo que llevas, que queda en una mochila recuperable.
- **Recolección y herramientas**: 47 objetos y herramientas con calidad y durabilidad (mano 1,
  hacha de piedra 3, hacha avanzada 8 de madera por golpe).
- **Fabricación**: 27 recetas con cola y barra de progreso. Las bloqueadas indican qué
  necesitan.
- **Construcción**: 21 edificios con niveles, límites y costes progresivos.
  - El modo construcción muestra una silueta válida o inválida y permite girar, confirmar y
    cancelar.
  - Cada edificio tiene un panel para mejorar, reparar y ver estadísticas.
- **Producción automática**: por intervalos con progreso visible, cadenas de procesado
  (aserradero, horno de carbón, fundición, taller, refinería y fábrica) y almacén con capacidad.
- **Trabajadores**: leñador, minero, granjero, recolector y artesano. Contratación, plazas,
  entrenamiento y presencia visual en la base.
- **Árbol tecnológico**: 44 tecnologías en 8 ramas y 6 edades.
- **Objetivos**: 29 misiones encadenadas.
- **Enemigos**:
  - Fauna, criaturas nocturnas y dos guardianes de zona.
  - Detección, persecución, invulnerabilidad tras golpe y esquiva.
  - Torres de defensa y antorchas.
- **Regiones desbloqueables**: jungla de las ruinas (reparar el puente) y cueva de cristal
  (despejar el derrumbe).
- **Progreso sin conexión**: hasta 8 h (12 h con *Logística*), sólo economía, con pantalla de
  bienvenida.
- **Guardado**: automático, atómico, con copia de seguridad y suma de verificación.
- **Controles**: táctiles (joystick, cámara por arrastre, pellizco y botones multitáctiles), y
  teclado y ratón.
- **Ajustes**: sensibilidad, volúmenes, calidad gráfica, límite de FPS y escala de interfaz.

### Técnico
- Godot 4.7.2 con renderizador *Compatibilidad* y física Jolt. Todo el equilibrio está en
  `data/*.json`.
- Optimizado para móviles:
  - Mallas con color de vértice horneado y un solo material.
  - MultiMesh y decoración fusionada por trozos.
  - Pocas luces y preajustes de calidad.
- Recursos 100 % libres (Kenney CC0, Freesound/OpenGameArt/FreePD CC0 y fuentes OFL),
  documentados en `ASSET_CREDITS.md`.
- 227 pruebas automáticas más una prueba del flujo completo, ejecutadas también sobre la build
  exportada.
- GitHub Actions exporta APK, Linux y Windows con el Godot oficial y los adjunta a cada
  release.
