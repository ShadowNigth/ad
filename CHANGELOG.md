# Registro de cambios

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
