#!/usr/bin/env bash
# Test de superficie "full-ish": usa casi todo el espacio libre para probar
# escritura y lectura de un archivo enorme con verificación de SHA-256.
#
# USO:
#   ./test_surface_full.sh /Volumes/USB_LIMPIO
#
# Opcional: segundo parámetro para porcentaje del espacio libre a usar (por defecto 80)
#   ./test_surface_full.sh /Volumes/USB_LIMPIO 70

set -euo pipefail

# ── Validación de dependencias ─────────────────────────────────
check_deps() {
    local missing=()
    for cmd in shasum dd df sync; do
        command -v "$cmd" &>/dev/null || missing+=("$cmd")
    done
    if (( ${#missing[@]} > 0 )); then
        echo "ERROR: Faltan dependencias requeridas: ${missing[*]}" >&2
        echo "Instálalas antes de continuar (Homebrew: brew install coreutils)." >&2
        exit 1
    fi
}
check_deps

if [[ $# -lt 1 ]]; then
  echo "Uso: $0 /Volumes/Volumen [porcentaje_libre]"
  exit 1
fi

VOLUME_PATH="$1"
PCT="${2:-80}"

if [[ ! -d "$VOLUME_PATH" ]]; then
  echo "ERROR: El volumen '$VOLUME_PATH' no existe o no está montado."
  exit 1
fi

if (( PCT <= 0 || PCT > 95 )); then
  echo "Porcentaje inválido. Usa algo entre 10 y 95."
  exit 1
fi

# Espacio libre en GiB
FREE_GIB=$(df -g "$VOLUME_PATH" | awk 'NR==2 {print $4}' || echo 0)
if (( FREE_GIB < 2 )); then
  echo "Muy poco espacio libre (${FREE_GIB} GiB). No merece la pena el test."
  exit 1
fi

# Usamos PCT% del espacio libre, pero nunca menos de 1 GiB
TEST_GIB=$((FREE_GIB * PCT / 100))
if (( TEST_GIB < 1 )); then
  TEST_GIB=1
fi

TOTAL_MB=$((TEST_GIB * 1024))
SRC_FILE=$(mktemp /tmp/usblab_surface.XXXXXX)
trap 'rm -f "$SRC_FILE" 2>/dev/null || true' EXIT INT TERM
DST_FILE="${VOLUME_PATH}/surface_${TEST_GIB}GiB.bin"

echo "=============================================="
echo " Test de superficie (gran archivo)"
echo "=============================================="
echo "Volumen:         $VOLUME_PATH"
echo "Espacio libre:   ${FREE_GIB} GiB"
echo "Porcentaje a usar: ${PCT}%"
echo "Tamaño de prueba:  ${TEST_GIB} GiB (${TOTAL_MB} MB)"
echo "Archivo origen:  $SRC_FILE"
echo "Archivo destino: $DST_FILE"
echo "=============================================="
echo
echo "ADVERTENCIA: Este test puede tardar MUCHO (horas) en discos grandes."
echo

read -r -p "Pulsa ENTER para comenzar o Ctrl+C para cancelar..." _

# Generar archivo enorme en /tmp (puede ser costoso)
echo ">>> Generando ${TEST_GIB} GiB de datos aleatorios en $SRC_FILE ..."
START_GEN=$(date +%s)
dd if=/dev/urandom of="$SRC_FILE" bs=1m count="$TOTAL_MB" status=progress
END_GEN=$(date +%s)
GEN_TIME=$((END_GEN - START_GEN))
(( GEN_TIME == 0 )) && GEN_TIME=1
GEN_SPEED=$((TOTAL_MB / GEN_TIME))
echo "Generación completada en ${GEN_TIME}s (~${GEN_SPEED} MB/s)."
echo

echo ">>> SHA-256 origen..."
SHA_SRC=$(shasum -a 256 "$SRC_FILE" | awk '{print $1}')
echo "SHA origen: $SHA_SRC"
echo

echo ">>> Copiando enorme archivo al volumen..."
START_CP=$(date +%s)
cp "$SRC_FILE" "$DST_FILE"
sync
END_CP=$(date +%s)
CP_TIME=$((END_CP - START_CP))
(( CP_TIME == 0 )) && CP_TIME=1
CP_SPEED=$((TOTAL_MB / CP_TIME))

echo "Copia completada en ${CP_TIME}s (~${CP_SPEED} MB/s)."
echo

echo ">>> SHA-256 destino (lectura completa del archivo de superficie)..."
SHA_DST=$(shasum -a 256 "$DST_FILE" | awk '{print $1}')
echo "SHA destino: $SHA_DST"
echo

if [[ "$SHA_SRC" == "$SHA_DST" ]]; then
  echo "RESULTADO: OK — El disco ha pasado el test de superficie para ${TEST_GIB} GiB."
  echo "USBLAB_RESULT: {\"result\":\"ok\",\"test\":\"surface\",\"cycles_ok\":1,\"speed_gen_mb_s\":${GEN_SPEED},\"speed_copy_mb_s\":${CP_SPEED}}"
else
  echo "RESULTADO: ERROR — Corrupción detectada en el test de superficie."
fi

echo
read -r -p "¿Borrar archivo de prueba en volumen y en /tmp? [yes/NO] " RESP
if [[ "$RESP" == "yes" ]]; then
  rm -f "$DST_FILE"
  echo "Archivos de prueba eliminados."
fi

echo
echo "Test de superficie finalizado."
echo "=============================================="
