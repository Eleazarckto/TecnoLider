#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════════════
#  Publicar una versión de Tecno Líder en sistemasceccato.com
# ════════════════════════════════════════════════════════════════════
#  Uso (desde la raíz del proyecto, en Git Bash):
#     bash tool/publicar.sh            → compila APK + Windows y publica
#     bash tool/publicar.sh --sin-compilar
#                                      → publica lo que ya está en release/<versión>/
#
#  Antes de correrlo hay que subir la versión en TRES lugares del repo:
#     · kAppVersion en lib/main.dart
#     · version: X.Y.Z+N en pubspec.yaml (el +N tiene que subir)
#     · backend/version.json (versión, url y notas de android y windows)
#
#  Los datos de conexión viven en tool/.deploy.env (en .gitignore, no
#  sale de esta PC). Si no existe se usan los valores por defecto de abajo.
#
#  Orden de publicación (si se altera, los equipos intentan descargar un
#  archivo que todavía no está):
#     1. APK y zip  →  2. chmod 644 (scp los deja en 640 y la web no los
#     sirve)  →  3. respaldo del version.json viejo  →  4. version.json nuevo
#
#  El version.json publicado lleva además "sha256" y "tamano" de cada
#  paquete (los escribe este script en backend/version.json): el
#  actualizador nuevo (lib/actualizador.dart) comprueba con eso que la
#  descarga llegó entera. La 1.0.17 y anteriores ignoran esos campos.
# ════════════════════════════════════════════════════════════════════
set -euo pipefail

RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$RAIZ"

# Orden del dueño: mientras exista PUBLICACION_BLOQUEADA la versión espera la
# confirmación del cliente y no se anuncia. Solo el dueño borra ese archivo.
if [[ -f "$RAIZ/PUBLICACION_BLOQUEADA" ]]; then
  printf '\033[31mNO se publica: existe PUBLICACION_BLOQUEADA\033[0m\n'
  sed 's/^/  | /' "$RAIZ/PUBLICACION_BLOQUEADA"
  exit 1
fi

ENV_FILE="$RAIZ/tool/.deploy.env"
[[ -f "$ENV_FILE" ]] && { set -a; source "$ENV_FILE"; set +a; }
: "${DEPLOY_HOST:=204.48.24.185}"
: "${DEPLOY_USUARIO:=sistemasceccato}"
: "${DEPLOY_LLAVE:=$HOME/.ssh/id_ed25519}"
: "${DEPLOY_RUTA:=/home/sistemasceccato/htdocs/sistemasceccato.com/tecnolider/updates}"
BASE_URL="https://sistemasceccato.com/tecnolider/updates"

# Huella de la firma de los APK ya instalados en los teléfonos. Si un APK
# sale firmado con otra llave, Android lo rechaza como actualización.
FIRMA_FLOTA="40083ad5045afba3b1c5862dcbc3d77adc7e7d783d52124d33d82d44489de469"

FLUTTER="${FLUTTER:-/c/Users/eleaz/Downloads/src/flutter/bin/flutter}"
JAVA="${JAVA:-/c/Program Files/Android/Android Studio/jbr/bin/java.exe}"
O=(-o ConnectTimeout=20 -o BatchMode=yes -o IdentitiesOnly=yes -i "$DEPLOY_LLAVE")
DEST="$DEPLOY_USUARIO@$DEPLOY_HOST"

PY=""
for c in python3 python py; do "$c" -c 'import sys' >/dev/null 2>&1 && { PY="$c"; break; }; done
[[ -n "$PY" ]] || { printf 'Hace falta Python para escribir la huella en version.json.\n'; exit 1; }

rojo()  { printf '\033[31m%s\033[0m\n' "$*"; }
verde() { printf '\033[32m%s\033[0m\n' "$*"; }
paso()  { printf '\n── %s ──\n' "$*"; }

# ── 1. Versiones coherentes ─────────────────────────────────────────
paso "1/6  Comprobando versiones"
VERSION="$(grep -E '^version:' pubspec.yaml | sed -E 's/version:[[:space:]]*([0-9.]+)\+.*/\1/')"
grep -q "kAppVersion = \"$VERSION\"" lib/main.dart \
  || { rojo "kAppVersion en lib/main.dart no es $VERSION"; exit 1; }
for so in android windows; do
  grep -q "tecnolider-$( [[ $so == windows ]] && echo windows- )$VERSION" backend/version.json \
    || { rojo "backend/version.json no anuncia $VERSION para $so"; exit 1; }
done
[[ "$(grep -c "\"version\": \"$VERSION\"" backend/version.json)" -eq 2 ]] \
  || { rojo "backend/version.json no tiene \"version\": \"$VERSION\" en android y windows"; exit 1; }
verde "  versión $VERSION"

DIR="release/$VERSION"
APK="$DIR/tecnolider-$VERSION.apk"
ZIP="$DIR/tecnolider-windows-$VERSION.zip"
mkdir -p "$DIR"

# ── 2. Compilar ─────────────────────────────────────────────────────
if [[ "${1:-}" != "--sin-compilar" ]]; then
  paso "2/6  Compilando (APK y Windows, uno después del otro)"
  # Con poca RAM, dos compilaciones a la vez hacen fallar a Gradle.
  "$FLUTTER" build apk --release
  cp build/app/outputs/flutter-apk/app-release.apk "$APK"
  "$FLUTTER" build windows --release
  rm -f "$ZIP"
  powershell.exe -NoProfile -Command "Compress-Archive -Path 'build\\windows\\x64\\runner\\Release\\*' -DestinationPath '$(cygpath -w "$ZIP")' -Force"
else
  paso "2/6  Sin compilar: se usa lo que hay en $DIR"
fi
[[ -f "$APK" && -f "$ZIP" ]] || { rojo "Faltan $APK o $ZIP"; exit 1; }

# Huella SHA-256 y tamaño de cada paquete en version.json. Se escribe con
# indent=2 y ensure_ascii=False: queda "version": "X" (con espacio), que es
# lo que buscan los grep de arriba y de la verificación final.
"$PY" - backend/version.json "$(cygpath -w "$APK" 2>/dev/null || echo "$APK")" \
       "$(cygpath -w "$ZIP" 2>/dev/null || echo "$ZIP")" <<'PY' \
  || { rojo "No se pudo escribir la huella en backend/version.json"; exit 1; }
import hashlib, json, os, sys
ruta, apk, zip_ = sys.argv[1:4]
d = json.load(open(ruta, encoding='utf-8'))
for so, f in (('android', apk), ('windows', zip_)):
    h = hashlib.sha256()
    with open(f, 'rb') as a:
        for trozo in iter(lambda: a.read(1 << 20), b''):
            h.update(trozo)
    d[so]['sha256'] = h.hexdigest()
    d[so]['tamano'] = os.path.getsize(f)
with open(ruta, 'w', encoding='utf-8', newline='\n') as s:
    json.dump(d, s, ensure_ascii=False, indent=2)
    s.write('\n')
PY
cp backend/version.json "$DIR/version.json"

# ── 3. Firma del APK ────────────────────────────────────────────────
paso "3/6  Verificando la firma del APK"
SIGNER="$(ls -d "$LOCALAPPDATA"/Android/sdk/build-tools/*/lib/apksigner.jar 2>/dev/null | sort -V | tail -1)"
firma="$("$JAVA" -jar "$SIGNER" verify --print-certs "$APK" | grep -m1 'SHA-256' | awk '{print $NF}' | tr -d '\r')"
[[ "$firma" == "$FIRMA_FLOTA" ]] \
  || { rojo "Firma $firma distinta a la de los teléfonos. No se publica."; exit 1; }
verde "  firmado con la llave de la flota"

# ── 4. Subir instaladores ───────────────────────────────────────────
paso "4/6  Subiendo APK y zip"
scp "${O[@]}" "$APK" "$ZIP" "$DEST:$DEPLOY_RUTA/"
ssh "${O[@]}" "$DEST" "cd '$DEPLOY_RUTA' && chmod 644 'tecnolider-$VERSION.apk' 'tecnolider-windows-$VERSION.zip'"
for f in "$APK" "$ZIP"; do
  local_t=$(stat -c %s "$f")
  remoto_t=$(ssh "${O[@]}" "$DEST" "stat -c %s '$DEPLOY_RUTA/$(basename "$f")'" | tr -d '\r')
  [[ "$local_t" == "$remoto_t" ]] || { rojo "$(basename "$f"): subió $remoto_t de $local_t bytes"; exit 1; }
  code=$(curl -s -o /dev/null -w '%{http_code}' -I "$BASE_URL/$(basename "$f")")
  [[ "$code" == 200 ]] || { rojo "$(basename "$f") no descarga desde la web (HTTP $code)"; exit 1; }
done
verde "  instaladores completos y descargables"

# ── 5. Anunciar la versión ──────────────────────────────────────────
paso "5/6  Publicando version.json (respaldo del anterior)"
ssh "${O[@]}" "$DEST" "cd '$DEPLOY_RUTA' && cp version.json version.json.bak_$(date +%Y%m%d_%H%M%S)"
scp "${O[@]}" backend/version.json "$DEST:$DEPLOY_RUTA/version.json"

# ── 6. Verificación pública ─────────────────────────────────────────
paso "6/6  Verificando desde internet"
# Se lee como UTF-8: en Windows la entrada estándar de Python no lo es y
# una nota con tildes o «…» llegaba distinta de la local (falso error).
curl -s -H 'Cache-Control: no-cache' "$BASE_URL/version.json?nc=$RANDOM" | "$PY" -c "
import json, sys
d = json.loads(sys.stdin.buffer.read().decode('utf-8'))
local = json.load(open(sys.argv[1], encoding='utf-8'))
for so in ('android', 'windows'):
    assert d[so]['version'] == sys.argv[2], so + ' no anuncia ' + sys.argv[2]
    assert d[so].get('sha256') == local[so]['sha256'], so + ': falta la huella'
assert d == local, 'el version.json publicado no es igual al local'
" backend/version.json "$VERSION" \
  || { rojo "El version.json publicado no anuncia $VERSION (o no es igual al local)"; exit 1; }
verde "Tecno Líder $VERSION publicada en Android y Windows."
echo "Recuerda: git add release/$VERSION && git commit && git push"
