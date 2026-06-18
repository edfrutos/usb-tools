#!/usr/bin/env bash
# Stress test de integridad: múltiples escrituras/verificaciones seguidas.
#
# USO:
#   ./stress_integridad_extendido.sh /Volumes/USB_LIMPIO 4 5
#
# Parámetros:
#   1: ruta del volumen (ej: /Volumes/USB_LIMPIO)
#   2: tamaño GiB por archivo (por defecto 2)
#   3: número de archivos/ciclos (por defecto 5)

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
  echo "Uso: $0 /Volumes/Volumen [GiB] [ciclos]"
  exit 1
fi

VOLUME_PATH="$1"
SIZE_GIB="${2:-2}"
CYCLES="${3:-5}"

if [[ ! -d "$VOLUME_PATH" ]]; then
  echo "ERROR: El volumen '$VOLUME_PATH' no existe o no está montado."
  exit 1
fi

TOTAL_MB=$((SIZE_GIB * 1024))
SRC_FILE=$(mktemp /tmp/usblab_stress.XXXXXX)
trap 'rm -f "$SRC_FILE" 2>/dev/null || true' EXIT INT TERM

echo "=============================================="
echo " Stress de integridad"
echo "=============================================="
echo "Volumen:           $VOLUME_PATH"
echo "Tamaño por archivo: ${SIZE_GIB} GiB"
echo "Ciclos/archivos:   ${CYCLES}"
echo "Archivo origen:    $SRC_FILE"
echo "=============================================="
echo

read -r -p "Pulsa ENTER para generar el archivo origen y comenzar..." _

# Generar archivo aleatorio en /tmp
echo ">>> Generando ${SIZE_GIB} GiB de datos aleatorios en $SRC_FILE ..."
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

c=1
while (( c <= CYCLES )); do
  DST_FILE="${VOLUME_PATH}/stress_${SIZE_GIB}GiB_${c}.bin"
  echo "----------------------------------------------"
  echo " Ciclo $c / $CYCLES"
  echo " Archivo destino: $DST_FILE"
  echo "----------------------------------------------"

  echo ">>> Copiando archivo al volumen..."
  START_CP=$(date +%s)
  cp "$SRC_FILE" "$DST_FILE"
  sync
  END_CP=$(date +%s)
  CP_TIME=$((END_CP - START_CP))
  (( CP_TIME == 0 )) && CP_TIME=1
  CP_SPEED=$((TOTAL_MB / CP_TIME))

  echo "Copia completada en ${CP_TIME}s (~${CP_SPEED} MB/s)."
  echo

  echo ">>> Calculando SHA-256 destino..."
  SHA_DST=$(shasum -a 256 "$DST_FILE" | awk '{print $1}')
  echo "SHA destino: $SHA_DST"

  if [[ "$SHA_SRC" == "$SHA_DST" ]]; then
    echo "Ciclo $c: OK — integridad correcta."
  else
    echo "Ciclo $c: ERROR — corrupción detectada."
    echo "RESULTADO GLOBAL: NO FIABLE."
    exit 1
  fi

  echo
  c=$((c + 1))
done

echo "=============================================="
echo "RESULTADO GLOBAL: TODOS LOS CICLOS OK."
echo "La unidad ha pasado el stress test de integridad."
echo "=============================================="
echo
read -r -p "¿Borrar los archivos stress_*.bin del volumen? [yes/NO] " RESP
if [[ "$RESP" == "yes" ]]; then
  rm -f "${VOLUME_PATH}/stress_${SIZE_GIB}GiB_"*.bin 2>/dev/null || true
  echo "Archivos de prueba eliminados."
fi
