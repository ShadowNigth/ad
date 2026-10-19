#!/usr/bin/env python3
"""Crea un almacén de claves PKCS#12 para firmar el APK de Android.

No necesita Java ni keytool: usa la biblioteca `cryptography` de Python
(`pip install cryptography`). El archivo resultante es compatible con
`apksigner` (Android SDK) y con el exportador de Godot 4.

Uso:
    python3 tools/create_android_keystore.py --out mi_clave.keystore \
        --alias islasalvaje --password "una-contraseña-larga"

Para usarlo en GitHub Actions sin publicarlo, guárdalo como secreto:
    base64 -w0 mi_clave.keystore   # -> secreto ANDROID_KEYSTORE_BASE64
    (además: ANDROID_KEYSTORE_PASSWORD y ANDROID_KEY_ALIAS)

La clave incluida en tools/android/ es PÚBLICA a propósito (ver LEEME.md).
"""
from __future__ import annotations

import argparse
import datetime as dt
import sys
from pathlib import Path

try:
    from cryptography import x509
    from cryptography.hazmat.primitives import hashes, serialization
    from cryptography.hazmat.primitives.asymmetric import rsa
    from cryptography.hazmat.primitives.serialization import pkcs12
    from cryptography.x509.oid import NameOID
except ImportError:  # pragma: no cover - mensaje para el usuario
    sys.exit("Falta la biblioteca 'cryptography'. Instálala con: pip install cryptography")


def build_keystore(alias: str, password: str, common_name: str, org: str, country: str, years: int) -> bytes:
    key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    subject = x509.Name([
        x509.NameAttribute(NameOID.COMMON_NAME, common_name),
        x509.NameAttribute(NameOID.ORGANIZATION_NAME, org),
        x509.NameAttribute(NameOID.COUNTRY_NAME, country),
    ])
    now = dt.datetime.now(dt.timezone.utc) - dt.timedelta(days=1)
    cert = (
        x509.CertificateBuilder()
        .subject_name(subject)
        .issuer_name(subject)
        .public_key(key.public_key())
        .serial_number(x509.random_serial_number())
        .not_valid_before(now)
        .not_valid_after(now + dt.timedelta(days=365 * years))
        .add_extension(x509.BasicConstraints(ca=False, path_length=None), critical=True)
        .sign(key, hashes.SHA256())
    )
    # Cifrado "clásico" (PBE-SHA1-3DES + MAC SHA1): lo leen todas las versiones de Java.
    encryption = (
        serialization.PrivateFormat.PKCS12.encryption_builder()
        .kdf_rounds(50000)
        .key_cert_algorithm(pkcs12.PBES.PBESv1SHA1And3KeyTripleDESCBC)
        .hmac_hash(hashes.SHA1())
        .build(password.encode("utf-8"))
    )
    return pkcs12.serialize_key_and_certificates(alias.encode("utf-8"), key, cert, None, encryption)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--out", required=True, help="Ruta del archivo .keystore a crear")
    ap.add_argument("--alias", default="islasalvaje", help="Alias de la clave (usuario en Godot)")
    ap.add_argument("--password", required=True, help="Contraseña (mínimo 6 caracteres)")
    ap.add_argument("--cn", default="Isla Salvaje", help="Nombre común del certificado")
    ap.add_argument("--org", default="Isla Salvaje", help="Organización del certificado")
    ap.add_argument("--country", default="AR", help="Código de país (2 letras)")
    ap.add_argument("--years", type=int, default=30, help="Años de validez")
    ap.add_argument("--force", action="store_true", help="Sobrescribir si ya existe")
    args = ap.parse_args()

    if len(args.password) < 6:
        ap.error("La contraseña debe tener al menos 6 caracteres (requisito de keytool/apksigner).")
    out = Path(args.out)
    if out.exists() and not args.force:
        ap.error(f"{out} ya existe (usa --force para sobrescribirlo).")
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_bytes(build_keystore(args.alias, args.password, args.cn, args.org, args.country, args.years))

    # Comprobación: se vuelve a abrir con la misma contraseña.
    with out.open("rb") as fh:
        loaded = pkcs12.load_pkcs12(fh.read(), args.password.encode("utf-8"))
    cert = loaded.cert.certificate if loaded.cert else None
    if cert is None or loaded.key is None:
        print("ERROR: el almacén creado no contiene clave y certificado", file=sys.stderr)
        return 1
    fp = cert.fingerprint(hashes.SHA256()).hex(":").upper()
    print(f"Creado {out} (alias '{args.alias}')")
    print(f"Huella SHA-256 del certificado: {fp}")
    print(f"Válido hasta: {cert.not_valid_after_utc:%Y-%m-%d}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
