# Clave de firma de Android

`isla_salvaje_publica.keystore` es la clave con la que se firman los APK que
publica GitHub Actions cuando el repositorio **no** tiene configurados secretos
de firma.

| Dato | Valor |
|---|---|
| Archivo | `tools/android/isla_salvaje_publica.keystore` (PKCS#12) |
| Alias (usuario) | `islasalvaje` |
| Contraseña | `islasalvaje-publica` |
| Huella SHA-256 | `BB:92:3C:34:05:63:97:7F:03:4A:FC:DA:C4:8F:CB:D6:0F:49:F5:8D:39:FB:50:5A:5B:40:1E:9D:6B:4D:FD:87` |

## ¿Por qué hay una clave pública en el repositorio?

Android sólo deja instalar una versión nueva **encima** de la anterior (sin
borrar la partida guardada) si las dos están firmadas con la misma clave. Con
una clave fija, cada release se puede instalar sobre la anterior. La alternativa,
una clave nueva en cada compilación, obligaría a desinstalar el juego (y perder
la partida) en cada actualización.

La clave es pública a propósito: sirve para instalar el APK directamente
(«sideload») y **no da ningún permiso especial**. El juego no pide permisos y
sólo guarda la partida. Lo único que permite es firmar un APK que Android
acepte como actualización de este juego.

## Usar una clave privada (recomendado si se publica en una tienda)

1. Crear la clave (no hace falta Java):
   ```bash
   pip install cryptography
   python3 tools/create_android_keystore.py --out ~/isla_privada.keystore \
       --alias islasalvaje --password "una-contraseña-larga"
   ```
   También sirve `keytool -genkeypair -v -keystore isla_privada.keystore -alias islasalvaje -keyalg RSA -keysize 2048 -validity 10000`.
2. En GitHub: *Settings → Secrets and variables → Actions → New repository secret*:
   - `ANDROID_KEYSTORE_BASE64`: salida de `base64 -w0 ~/isla_privada.keystore`
   - `ANDROID_KEYSTORE_PASSWORD`: la contraseña
   - `ANDROID_KEY_ALIAS`: el alias (`islasalvaje`)
3. El workflow `Exportar juego` usará esa clave automáticamente.

Al cambiar de clave hay que desinstalar **una vez** la versión firmada con la
clave pública antes de instalar la nueva.
