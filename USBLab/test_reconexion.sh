#!/usr/bin/env bash
# Test de reconexión: comprueba si un archivo sigue intacto tras varias
# desconexiones/reconexiones de la unidad.
#
# USO:
#   ./test_reconexion.sh /Volumes/USB_LIMPIO 4 5
#
# Parámetros:
#   1: ruta del volumen (ej: /Volumes/USB_LIMPIO)
#   2: tamaño en GiB del archivo de prueba (por defecto 2)
#   3: número de ciclos de reconexión (por defecto 5)

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
SRC_FILE=$(mktemp /tmp/usblab_reconexion.XXXXXX)
trap 'rm -f "$SRC_FILE" 2>/dev/null || true' EXIT INT TERM
DST_FILE="${VOLUME_PATH}/reconexion_${SIZE_GIB}GiB.bin"

echo "=============================================="
echo " Test de reconexión"
echo "=============================================="
echo "Volumen:           $VOLUME_PATH"
echo "Tamaño de prueba:  ${SIZE_GIB} GiB"
echo "Ciclos:            ${CYCLES}"
echo "Archivo origen:    $SRC_FILE"
echo "Archivo destino:   $DST_FILE"
echo "=============================================="
echo

read -r -p "Pulsa ENTER para generar el archivo y empezar el test..." _

# Generar archivo aleatorio en /tmp por bloques de 512 MiB
echo ">>> Generando ${SIZE_GIB} GiB de datos aleatorios en $SRC_FILE ..."
START_GEN=$(date +%s)
dd if=/dev/urandom of="$SRC_FILE" bs=1m count="$TOTAL_MB" status=progress
END_GEN=$(date +%s)
GEN_TIME=$((END_GEN - START_GEN))
(( GEN_TIME == 0 )) && GEN_TIME=1
GEN_SPEED=$((TOTAL_MB / GEN_TIME))
echo "Generación completada en ${GEN_TIME}s (~${GEN_SPEED} MB/s)."
echo

echo ">>> Calculando SHA-256 origen..."
SHA_SRC=$(shasum -a 256 "$SRC_FILE" | awk '{print $1}')
echo "SHA-256 origen: $SHA_SRC"
echo

echo ">>> Copiando al volumen..."
START_CP=$(date +%s)
cp "$SRC_FILE" "$DST_FILE"
sync
END_CP=$(date +%s)
CP_TIME=$((END_CP - START_CP))
(( CP_TIME == 0 )) && CP_TIME=1
CP_SPEED=$((TOTAL_MB / CP_TIME))

echo "Copia completada en ${CP_TIME}s (~${CP_SPEED} MB/s)."
echo

echo ">>> Verificando integridad inicial..."
SHA_DST_INITIAL=$(shasum -a 256 "$DST_FILE" | awk '{print $1}')
echo "SHA-256 destino inicial: $SHA_DST_INITIAL"
echo

if [[ "$SHA_SRC" != "$SHA_DST_INITIAL" ]]; then
  echo "RESULTADO: ERROR ya en la copia inicial. No tiene sentido seguir con reconexiones."
  exit 1
fi

echo "Integridad inicial OK."
echo

# Ciclos de reconexión
i=1
while (( i <= CYCLES )); do
  echo "=============================================="
  echo " Ciclo de reconexión $i / $CYCLES"
  echo "=============================================="
  echo
  echo "1) Desmonta el volumen desde Finder o con:"
  echo "   diskutil unmount \"$VOLUME_PATH\""
  echo "2) Desconecta físicamente el USB."
  echo "3) Vuelve a conectarlo."
  echo
  read -r -p "Cuando lo hayas vuelto a conectar y veas el volumen montado, pulsa ENTER..." _

  # Esperar a que el volumen exista de nuevo
  echo "Esperando a que se monte $VOLUME_PATH ..."
  while [[ ! -d "$VOLUME_PATH" ]]; do
    sleep 1
  done

  if [[ ! -f "$DST_FILE" ]]; then
    echo "AVISO: El archivo $DST_FILE no existe tras la reconexión."
    echo "RESULTADO: ERROR (archivo desaparecido)."
    exit 1
  fi

  echo ">>> Recalculando SHA-256 destino tras reconexión..."
  SHA_DST_CYCLE=$(shasum -a 256 "$DST_FILE" | awk '{print $1}')
  echo "SHA-256 destino ciclo $i: $SHA_DST_CYCLE"

  if [[ "$SHA_SRC" == "$SHA_DST_CYCLE" ]]; then
    echo "Ciclo $i: OK — archivo intacto tras reconexión."
  else
    echo "Ciclo $i: ERROR — el archivo ha cambiado, hay corrupción."
    echo "RESULTADO GLOBAL: NO FIABLE."
    exit 1
  fi

  echo
  i=$((i + 1))
done

echo "=============================================="
echo "RESULTADO GLOBAL: TODAS LAS RECONEXIONES OK."
echo "La unidad ha mantenido la integridad del archivo en todos los ciclos."
echo "=============================================="
