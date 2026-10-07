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
# ════════════════════════════════════════════════════════════════════
set -euo pipefail

RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$RAIZ"

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
cp backend/version.json "$DIR/version.json"
[[ -f "$APK" && -f "$ZIP" ]] || { rojo "Faltan $APK o $ZIP"; exit 1; }

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
publicado=$(curl -s "$BASE_URL/version.json?nc=$RANDOM" | grep -c "\"version\": \"$VERSION\"" || true)
[[ "$publicado" -eq 2 ]] || { rojo "El version.json publicado no anuncia $VERSION"; exit 1; }
verde "Tecno Líder $VERSION publicada en Android y Windows."
echo "Recuerda: git add release/$VERSION && git commit && git push"
