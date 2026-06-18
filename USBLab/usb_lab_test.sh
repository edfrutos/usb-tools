#!/usr/bin/env bash
#
# usb_lab_test.sh
#
# Uso:
#   usb_lab_test.sh <VOLUMEN> <TAM_PEQUEÑO_GiB> <CICLOS> <SUPERFICIE_%>
#
# Ejemplo:
#   usb_lab_test.sh /Volumes/USB_Limpio 4 5 20
#
# Hace:
#   1) Genera un archivo "pequeño" en ~/USBLabTmp y lo copia al volumen.
#      - Verifica integridad (SHA-256) tras la copia.
#   2) Hace N ciclos de:
#      - Te pide desmontar / desconectar / reconectar.
#      - Espera a que pulses ENTER.
#      - Recalcula SHA-256 en el volumen y comprueba que no se ha corrompido.
#   3) Test de superficie:
#      - Calcula X% del espacio libre del volumen.
#      - Genera un gran archivo de superficie, lo copia y verifica el hash.
#
# NOTA:
#   Este script está pensado para ser llamado desde tu app USBLab,
#   donde el botón "Enviar ENTER" escribe "\n" en el stdin del proceso.

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

########################################
# Funciones auxiliares
########################################

error() {
    echo "ERROR: $*" >&2
    exit 1
}

bytes_human() {
    # Convierte bytes a una cadena en MiB/GiB aprox.
    local bytes=$1
    local kib=$((bytes / 1024))
    local mib=$((kib / 1024))
    local gib=$((mib / 1024))
    if (( gib > 0 )); then
        echo "${gib} GiB"
    elif (( mib > 0 )); then
        echo "${mib} MiB"
    else
        echo "${bytes} bytes"
    fi
}

calc_speed_mb_s() {
    local mb=$1
    local secs=$2
    if (( secs <= 0 )); then
        echo "∞"
        return
    fi
    echo $(( mb / secs ))
}

########################################
# Parámetros
########################################

if (( $# != 4 )); then
    echo "Uso: $0 <VOLUMEN> <TAM_PEQUEÑO_GiB> <CICLOS> <SUPERFICIE_%>"
    echo "Ejemplo: $0 /Volumes/USB_Limpio 4 5 20"
    exit 1
fi

VOLUMEN="$1"
SIZE_GIB_SMALL="$2"
CYCLES="$3"
SURFACE_PERCENT="$4"

# Validaciones básicas
[[ -d "$VOLUMEN" ]] || error "El volumen $VOLUMEN no existe o no está montado."
[[ "$SIZE_GIB_SMALL" =~ ^[0-9]+$ ]] || error "Tamaño pequeño debe ser un entero."
[[ "$CYCLES" =~ ^[0-9]+$ ]] || error "Ciclos debe ser un entero."
[[ "$SURFACE_PERCENT" =~ ^[0-9]+$ ]] || error "Superficie % debe ser un entero."
(( SURFACE_PERCENT > 0 && SURFACE_PERCENT <= 90 )) || error "Superficie % debe estar entre 1 y 90."

########################################
# Preparar directorio temporal
########################################

TMP_BASE="${USBLAB_TMP:-$HOME/USBLabTmp}"
mkdir -p "$TMP_BASE" || error "No puedo crear $TMP_BASE"

SRC_SMALL="$TMP_BASE/usbtest_small_${SIZE_GIB_SMALL}GiB.bin"
DST_SMALL="$VOLUMEN/usbtest_small_${SIZE_GIB_SMALL}GiB.bin"

SRC_SURF="$TMP_BASE/usbtest_surface.bin"
DST_SURF="$VOLUMEN/usbtest_surface.bin"

trap 'rm -f "$SRC_SMALL" "$SRC_SURF" 2>/dev/null || true' EXIT

########################################
# Cabecera
########################################

echo "=================================================="
echo " Laboratorio USB para volumen:"
echo "   $VOLUMEN"
echo "--------------------------------------------------"
echo " Archivo pequeño:   ${SIZE_GIB_SMALL} GiB"
echo " Ciclos:            $CYCLES"
echo " Superficie:        ${SURFACE_PERCENT}% del espacio libre"
echo "=================================================="
echo
echo "Pulsa ENTER para iniciar todas las pruebas (Ctrl+C para cancelar)..."
read -r _

########################################
# 1) Test base con archivo pequeño
########################################

echo
echo "=============================================="
echo " 1) Test base con archivo pequeño"
echo "=============================================="
echo

# Generar archivo pequeño con datos pseudoaleatorios
MB_SMALL=$(( SIZE_GIB_SMALL * 1024 ))
echo ">>> Generando archivo pequeño de ${SIZE_GIB_SMALL} GiB en $SRC_SMALL ..."
START_TS=$(date +%s)
# Puedes cambiar /dev/urandom por /dev/zero si prefieres velocidad
dd if=/dev/urandom of="$SRC_SMALL" bs=1m count="$MB_SMALL" status=progress
END_TS=$(date +%s)
GEN_SECS=$(( END_TS - START_TS ))
SPEED_GEN=$(calc_speed_mb_s "$MB_SMALL" "$GEN_SECS")

echo "Generación completada en ${GEN_SECS}s (~${SPEED_GEN} MB/s)."
echo

echo ">>> Calculando SHA-256 origen (pequeño)..."
SHA_ORIG_SMALL=$(shasum -a 256 "$SRC_SMALL" | awk '{print $1}')
echo "SHA origen pequeño: $SHA_ORIG_SMALL"
echo

echo ">>> Copiando archivo pequeño al volumen..."
START_TS=$(date +%s)
cp "$SRC_SMALL" "$DST_SMALL"
sync
END_TS=$(date +%s)
COPY_SECS=$(( END_TS - START_TS ))
SPEED_COPY=$(calc_speed_mb_s "$MB_SMALL" "$COPY_SECS")
echo "Copia completada en ${COPY_SECS}s (~${SPEED_COPY} MB/s)."
echo

echo ">>> Verificando integridad inicial (pequeño)..."
SHA_DST_SMALL=$(shasum -a 256 "$DST_SMALL" | awk '{print $1}')
echo "SHA destino inicial: $SHA_DST_SMALL"
echo

if [[ "$SHA_ORIG_SMALL" == "$SHA_DST_SMALL" ]]; then
    echo "Integridad inicial del archivo pequeño: OK."
else
    echo "ERROR: El archivo pequeño se ha corrompido ya en la primera copia." >&2
    exit 1
fi

########################################
# 2) Ciclos de reconexión
########################################

echo
echo "=============================================="
echo " 2) Ciclos de reconexión"
echo "=============================================="
echo

for (( i=1; i<=CYCLES; i++ )); do
    echo "----------------------------------------------"
    echo " Ciclo de reconexión $i / $CYCLES"
    echo "----------------------------------------------"
    echo
    echo "1) Desmonta el volumen desde Finder o con:"
    echo "   diskutil unmount \"$VOLUMEN\""
    echo "2) Desconecta físicamente el USB."
    echo "3) Vuelve a conectarlo."
    echo
    echo "Cuando hayas reconectado el USB y veas el volumen montado,"
    echo "pulsa ENTER para continuar..."
    read -r _

    # Esperar a que el volumen aparezca de nuevo
    echo
    echo "Esperando a que se monte $VOLUMEN ..."
    while [[ ! -d "$VOLUMEN" ]]; do
        sleep 1
    done

    echo ">>> Recalculando SHA-256 destino tras reconexión..."
    if [[ ! -f "$DST_SMALL" ]]; then
        echo "ERROR: El archivo $DST_SMALL no existe tras la reconexión." >&2
        exit 1
    fi

    SHA_DST_CYCLE=$(shasum -a 256 "$DST_SMALL" | awk '{print $1}')
    echo "SHA destino ciclo $i: $SHA_DST_CYCLE"

    if [[ "$SHA_DST_CYCLE" == "$SHA_ORIG_SMALL" ]]; then
        echo "Ciclo $i: OK — archivo intacto tras reconexión."
    else
        echo "Ciclo $i: ERROR — archivo corrompido tras reconexión." >&2
        exit 1
    fi

    echo
done

echo
echo "Todos los ciclos de reconexión han mantenido la integridad del archivo pequeño."
echo

########################################
# 3) Test de superficie (archivo grande)
########################################

echo "=============================================="
echo " 3) Test de superficie (${SURFACE_PERCENT}% del espacio libre)"
echo "=============================================="
echo

# Calcular espacio libre en el volumen (en KiB) con df
# df -k => columnas: Filesystem, 1024-blocks, Used, Available, Capacity, iused, ifree, %iused, Mounted on
FREE_KB=$(df -k "$VOLUMEN" | awk 'NR==2 {print $4}')
FREE_BYTES=$(( FREE_KB * 1024 ))
TARGET_BYTES=$(( FREE_BYTES * SURFACE_PERCENT / 100 ))

if (( TARGET_BYTES <= 0 )); then
    echo "No hay espacio libre suficiente para el test de superficie." >&2
    exit 1
fi

TARGET_GIB=$(( TARGET_BYTES / 1024 / 1024 / 1024 ))
if (( TARGET_GIB == 0 )); then
    # al menos 1 GiB
    TARGET_GIB=1
fi

TARGET_MB=$(( TARGET_GIB * 1024 ))

echo "Espacio libre aproximado: $(bytes_human "$FREE_BYTES")"
echo "Se usará aproximadamente: ${TARGET_GIB} GiB para el archivo de superficie."
echo

echo ">>> Generando archivo de superficie (${TARGET_GIB} GiB) en $SRC_SURF ..."
START_TS=$(date +%s)
dd if=/dev/urandom of="$SRC_SURF" bs=1m count="$TARGET_MB" status=progress
END_TS=$(date +%s)
GEN_SURF_SECS=$(( END_TS - START_TS ))
SPEED_SURF_GEN=$(calc_speed_mb_s "$TARGET_MB" "$GEN_SURF_SECS")
echo "Generación completada en ${GEN_SURF_SECS}s (~${SPEED_SURF_GEN} MB/s)."
echo

echo ">>> Calculando SHA-256 origen (superficie)..."
SHA_ORIG_SURF=$(shasum -a 256 "$SRC_SURF" | awk '{print $1}')
echo "SHA origen superficie: $SHA_ORIG_SURF"
echo

echo ">>> Copiando archivo de superficie al volumen..."
START_TS=$(date +%s)
cp "$SRC_SURF" "$DST_SURF"
sync
END_TS=$(date +%s)
COPY_SURF_SECS=$(( END_TS - START_TS ))
SPEED_SURF_COPY=$(calc_speed_mb_s "$TARGET_MB" "$COPY_SURF_SECS")
echo "Copia completada en ${COPY_SURF_SECS}s (~${SPEED_SURF_COPY} MB/s)."
echo

echo ">>> Verificando SHA-256 destino (superficie)..."
SHA_DST_SURF=$(shasum -a 256 "$DST_SURF" | awk '{print $1}')
echo "SHA destino superficie: $SHA_DST_SURF"
echo

if [[ "$SHA_ORIG_SURF" == "$SHA_DST_SURF" ]]; then
    echo "RESULTADO: OK — El archivo de superficie coincide bit a bit con el origen."
else
    echo "RESULTADO: ERROR — El archivo de superficie NO coincide con el origen." >&2
    exit 1
fi

echo
echo "¿Quieres borrar los archivos de prueba del volumen? [yes/NO]"
read -r RESP
if [[ "$RESP" == "yes" || "$RESP" == "y" ]]; then
    echo "Borrando $DST_SMALL y $DST_SURF..."
    rm -f "$DST_SMALL" "$DST_SURF" 2>/dev/null || true
fi

echo
echo "Test completo finalizado."
echo "=============================================="
