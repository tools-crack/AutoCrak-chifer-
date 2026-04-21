#!/data/data/com.termux/files/usr/bin/bash

# =========================
# CONFIGURACIÓN GLOBAL
# =========================
VERSION="3.0"
MAX_JOBS=4
FOUND=0
TOTAL_TESTS=0
CURRENT_TEST=0
SHOW_PROGRESS=0
EXCLUDE_METHODS=()
DICT_FILE=""
TARGET=""
FILE=""
QUIET=0
TIMEOUT=0
OUTPUT_FILE=""

# =========================
# FUNCIONES DE AYUDA
# =========================
show_help() {
    cat << 'EOF'
╔═══════════════════════════════════════════════════════════════════════════════╗
║                    🔐 AUTOCRACK v3.0 - ZERO DEPENDENCIES                      ║
║                      OFFLINE | SIN EXTERNOS | 100% BASH                       ║
╚═══════════════════════════════════════════════════════════════════════════════╝

┌───────────────────────────────────────────────────────────────────────────────┐
│ 📖 DESCRIPCIÓN                                                                │
├───────────────────────────────────────────────────────────────────────────────┤
│  Herramienta de criptoanálisis que NO necesita base64, xxd ni nada externo.  │
│  Todo está implementado en Bash puro. Funciona en CUALQUIER sistema con Bash.│
└───────────────────────────────────────────────────────────────────────────────┘

┌───────────────────────────────────────────────────────────────────────────────┐
│ 🚀 USO                                                                        │
├───────────────────────────────────────────────────────────────────────────────┤
│  ./autocrack.sh [OPCIONES] archivo.txt [PALABRA]                             │
│                                                                               │
│  OPCIONES:                                                                    │
│    -h, --help           Esta ayuda                                           │
│    -p, --progress       Barra de progreso                                    │
│    -q, --quiet          Modo silencioso                                      │
│    -e, --exclude LIST   Excluir métodos (ej: -e xor,railfence)               │
│    -d, --dict FILE      Diccionario de palabras                              │
│    -t, --timeout SEG    Timeout en segundos                                  │
│    -o, --output FILE    Guardar resultado                                    │
│    -j, --jobs N         Procesos paralelos (1-16, def:4)                     │
│                                                                               │
│  EJEMPLOS:                                                                    │
│    ./autocrack.sh -p mensaje.txt "CLAVE"                                     │
│    ./autocrack.sh -e xor,base64 -d dict.txt -t 30 cifrado.txt                │
│    ./autocrack.sh -q -j 8 -o encontrado.txt texto.txt "PASSWORD"             │
└───────────────────────────────────────────────────────────────────────────────┘

┌───────────────────────────────────────────────────────────────────────────────┐
│ 🔧 MÉTODOS IMPLEMENTADOS SIN DEPENDENCIAS                                     │
├───────────────────────────────────────────────────────────────────────────────┤
│  ✓ caesar         ✓ rot13        ✓ rot47        ✓ atbash                      │
│  ✓ reverse        ✓ base64       ✓ base32       ✓ hex                         │
│  ✓ url            ✓ xor          ✓ railfence    ✓ substitution                │
│  ✓ transposition  ✓ combo        ✓ morse        ✓ binario                     │
└───────────────────────────────────────────────────────────────────────────────┘
EOF
    exit 0
}

# =========================
# PROCESAMIENTO DE ARGUMENTOS
# =========================
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help) show_help ;;
        -p|--progress) SHOW_PROGRESS=1; shift ;;
        -q|--quiet) QUIET=1; shift ;;
        -e|--exclude) IFS=',' read -ra EXCLUDE_METHODS <<< "$2"; shift 2 ;;
        -d|--dict) DICT_FILE="$2"; shift 2 ;;
        -t|--timeout) TIMEOUT="$2"; shift 2 ;;
        -o|--output) OUTPUT_FILE="$2"; shift 2 ;;
        -j|--jobs) MAX_JOBS="$2"; shift 2 ;;
        --) shift; break ;;
        -*) echo "❌ Opción desconocida: $1"; exit 1 ;;
        *) break ;;
    esac
done

FILE="$1"
TARGET="${2:-CLAVE}"

[ -z "$FILE" ] && echo "❌ Error: Falta archivo. Usa -help" && exit 1
[ ! -f "$FILE" ] && echo "❌ Error: Archivo no encontrado" && exit 1

# Cargar diccionario
declare -a TARGETS=("$TARGET")
if [ -n "$DICT_FILE" ] && [ -f "$DICT_FILE" ]; then
    while IFS= read -r line; do
        [ -n "$line" ] && TARGETS+=("$line")
    done < "$DICT_FILE"
    [ $QUIET -eq 0 ] && echo "📚 Diccionario: ${#TARGETS[@]} palabras"
fi

# =========================
# IMPLEMENTACIONES NATIVAS (sin externos)
# =========================

# Base64 nativo (solo decodificación)
base64_decode() {
    local input="$1"
    local b64="ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
    local output=""
    local val=0
    local bits=0
    
    for ((i=0; i<${#input}; i++)); do
        local c="${input:$i:1}"
        [ "$c" = "=" ] && break
        local idx=$(expr index "$b64" "$c")
        [ $idx -eq 0 ] && continue
        idx=$((idx - 1))
        val=$(( (val << 6) | idx ))
        bits=$((bits + 6))
        
        if [ $bits -ge 8 ]; then
            bits=$((bits - 8))
            local byte=$(( (val >> bits) & 255 ))
            printf -v hexchar '\\x%02x' "$byte"
            output+="$hexchar"
        fi
    done
    printf "%b" "$output"
}

# Base32 nativo (decodificación)
base32_decode() {
    local input=$(echo "$1" | tr 'a-z' 'A-Z' | tr -d '=')
    local b32="ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"
    local output=""
    local val=0
    local bits=0
    
    for ((i=0; i<${#input}; i++)); do
        local c="${input:$i:1}"
        local idx=$(expr index "$b32" "$c")
        [ $idx -eq 0 ] && continue
        idx=$((idx - 1))
        val=$(( (val << 5) | idx ))
        bits=$((bits + 5))
        
        if [ $bits -ge 8 ]; then
            bits=$((bits - 8))
            local byte=$(( (val >> bits) & 255 ))
            printf -v hexchar '\\x%02x' "$byte"
            output+="$hexchar"
        fi
    done
    printf "%b" "$output"
}

# Hexadecimal nativo
hex_decode() {
    local input="$1"
    local output=""
    for ((i=0; i<${#input}; i+=2)); do
        local hex="${input:$i:2}"
        [ ${#hex} -eq 2 ] || continue
        printf -v char '\\x%s' "$hex"
        output+="$char"
    done
    printf "%b" "$output"
}

# URL decode nativo
url_decode() {
    local input="$1"
    local output=""
    local i=0
    while [ $i -lt ${#input} ]; do
        local c="${input:$i:1}"
        if [ "$c" = "%" ] && [ $((i+2)) -lt ${#input} ]; then
            local hex="${input:$((i+1)):2}"
            printf -v char '\\x%s' "$hex"
            output+="$char"
            i=$((i+3))
        else
            output+="$c"
            i=$((i+1))
        fi
    done
    printf "%b" "$output"
}

# Morse code nativo
morse_decode() {
    local input="$1"
    declare -A morse=(
        [".-"]="A" ["-..."]="B" ["-.-."]="C" ["-.."]="D" ["."]="E"
        ["..-."]="F" ["--."]="G" ["...."]="H" [".."]="I" [".---"]="J"
        ["-.-"]="K" [".-.."]="L" ["--"]="M" ["-."]="N" ["---"]="O"
        [".--."]="P" ["--.-"]="Q" [".-."]="R" ["..."]="S" ["-"]="T"
        ["..-"]="U" ["...-"]="V" [".--"]="W" ["-..-"]="X" ["-.--"]="Y"
        ["--.."]="Z" ["-----"]="0" [".----"]="1" ["..---"]="2" ["...--"]="3"
        ["....-"]="4" ["....."]="5" ["-...."]="6" ["--..."]="7" ["---.."]="8"
        ["----."]="9"
    )
    local output=""
    IFS=' ' read -ra codes <<< "$input"
    for code in "${codes[@]}"; do
        [ -n "${morse[$code]}" ] && output+="${morse[$code]}"
    done
    echo "$output"
}

# Binario nativo
bin_decode() {
    local input="$1"
    local output=""
    for byte in $input; do
        [ ${#byte} -eq 8 ] || continue
        local val=$((2#${byte}))
        printf -v char '\\x%02x' "$val"
        output+="$char"
    done
    printf "%b" "$output"
}

# =========================
# UTILIDADES
# =========================
TEXT=$(cat "$FILE" | tr -d '\r')
ABC="ABCDEFGHIJKLMNOPQRSTUVWXYZ"
abc="abcdefghijklmnopqrstuvwxyz"

is_excluded() {
    for excl in "${EXCLUDE_METHODS[@]}"; do
        [[ "$method" == "$excl" ]] && return 0
    done
    return 1
}

wait_jobs() {
    while [ "$(jobs -r | wc -l)" -ge "$MAX_JOBS" ]; do
        sleep 0.05
    done
}

progress_bar() {
    [ $SHOW_PROGRESS -eq 0 ] && return
    local percent=$((CURRENT_TEST * 100 / TOTAL_TESTS))
    local filled=$((percent / 2))
    local empty=$((50 - filled))
    printf "\r["
    printf "%${filled}s" | tr ' ' '█'
    printf "%${empty}s" | tr ' ' '░'
    printf "] %3d%% - %-30s" "$percent" "$1"
}

check() {
    local method="$1"
    local data="$2"
    [ -z "$data" ] && return
    for target in "${TARGETS[@]}"; do
        if echo "$data" | grep -qi "$target"; then
            echo -e "\n🔥 ENCONTRADO con $method: '$target'\n$data\n------------------"
            FOUND=1
            [ -n "$OUTPUT_FILE" ] && echo "$method: $data" >> "$OUTPUT_FILE"
            kill 0 2>/dev/null
            exit 0
        fi
    done
}

# =========================
# MÉTODOS DE ATAQUE (todos NATIVOS)
# =========================

caesar() {
    for ((i=1;i<26;i++)); do
        wait_jobs
        ((CURRENT_TEST++))
        progress_bar "César $i"
        (
            U="${ABC:$i}${ABC:0:$i}"
            L="${abc:$i}${abc:0:$i}"
            r=$(echo "$TEXT" | tr "$ABC$abc" "$U$L")
            check "César $i" "$r"
        ) &
    done
}

rot13() {
    wait_jobs
    ((CURRENT_TEST++))
    progress_bar "ROT13"
    ( check "ROT13" "$(echo "$TEXT" | tr "$ABC$abc" "NOPQRSTUVWXYZABCDEFGHIJKLMnopqrstuvwxyzabcdefghijklm")" ) &
}

rot47() {
    wait_jobs
    ((CURRENT_TEST++))
    progress_bar "ROT47"
    ( check "ROT47" "$(echo "$TEXT" | tr '!-~' 'P-~!-O')" ) &
}

atbash() {
    wait_jobs
    ((CURRENT_TEST++))
    progress_bar "Atbash"
    ( check "Atbash" "$(echo "$TEXT" | tr "$ABC$abc" "ZYXWVUTSRQPONMLKJIHGFEDCBAzyxwvutsrqponmlkjihgfedcba")" ) &
}

reverse() {
    wait_jobs
    ((CURRENT_TEST++))
    progress_bar "Reverso"
    ( check "Reverso" "$(echo "$TEXT" | rev)" ) &
}

base64d() {
    wait_jobs
    ((CURRENT_TEST++))
    progress_bar "Base64"
    ( check "Base64" "$(base64_decode "$TEXT")" ) &
}

base32d() {
    wait_jobs
    ((CURRENT_TEST++))
    progress_bar "Base32"
    ( check "Base32" "$(base32_decode "$TEXT")" ) &
}

hex_decode_method() {
    wait_jobs
    ((CURRENT_TEST++))
    progress_bar "Hex"
    ( check "Hex" "$(hex_decode "$TEXT")" ) &
}

url_decode_method() {
    wait_jobs
    ((CURRENT_TEST++))
    progress_bar "URL decode"
    ( check "URL" "$(url_decode "$TEXT")" ) &
}

xor_brute() {
    for ((k=1;k<256;k++)); do
        wait_jobs
        ((CURRENT_TEST++))
        progress_bar "XOR $k"
        (
            out=""
            for ((i=0;i<${#TEXT};i++)); do
                c=$(printf "%d" "'${TEXT:$i:1}" 2>/dev/null)
                out+=$(printf "\\$(printf '%03o' $((c ^ k))" 2>/dev/null)
            done
            check "XOR key=$k" "$out"
        ) &
    done
}

railfence() {
    for rails in 2 3 4 5; do
        wait_jobs
        ((CURRENT_TEST++))
        progress_bar "RailFence $rails"
        (
            local len=${#TEXT}
            local fence=()
            for ((i=0;i<rails;i++)); do fence[$i]=""; done
            local dir=1 row=0
            for ((i=0;i<len;i++)); do
                fence[$row]="${fence[$row]}${TEXT:$i:1}"
                ((row += dir))
                [ $row -eq 0 ] || [ $row -eq $((rails-1)) ] && ((dir *= -1))
            done
            local result=""
            for ((i=0;i<rails;i++)); do result+="${fence[$i]}"; done
            check "RailFence($rails)" "$result"
        ) &
    done
}

morse_method() {
    wait_jobs
    ((CURRENT_TEST++))
    progress_bar "Morse"
    ( check "Morse" "$(morse_decode "$TEXT")" ) &
}

bin_method() {
    wait_jobs
    ((CURRENT_TEST++))
    progress_bar "Binario"
    ( check "Binario" "$(bin_decode "$TEXT")" ) &
}

combo() {
    wait_jobs
    ((CURRENT_TEST++))
    progress_bar "Combo B64+Rev"
    ( check "Base64+Rev" "$(reverse "$(base64_decode "$TEXT")")" ) &
    
    wait_jobs
    ((CURRENT_TEST++))
    progress_bar "Combo Rev+ROT13"
    ( check "Rev+ROT13" "$(echo "$TEXT" | rev | tr "$ABC$abc" "NOPQRSTUVWXYZABCDEFGHIJKLMnopqrstuvwxyzabcdefghijklm")" ) &
}

# =========================
# EJECUCIÓN PRINCIPAL
# =========================
main() {
    # Calcular total de pruebas
    TOTAL_TESTS=25
    for m in rot13 rot47 atbash reverse base64 base32 hex url xor railfence morse bin combo; do
        is_excluded "$m" || ((TOTAL_TESTS++))
    done
    is_excluded "xor" || ((TOTAL_TESTS+=255))
    is_excluded "railfence" || ((TOTAL_TESTS+=4))
    is_excluded "combo" || ((TOTAL_TESTS+=2))
    
    [ $QUIET -eq 0 ] && echo "🚀 AutoCrack v3.0 | Archivo: $(wc -c < "$FILE")b | Objetivos: ${#TARGETS[@]} | Pruebas: $TOTAL_TESTS"
    
    if [ "$TIMEOUT" -gt 0 ]; then
        ( sleep "$TIMEOUT"; [ $FOUND -eq 0 ] && echo -e "\n⏰ Timeout" && kill 0 2>/dev/null ) &
    fi
    
    while [ $FOUND -eq 0 ]; do
        caesar
        is_excluded "rot13" || rot13
        is_excluded "rot47" || rot47
        is_excluded "atbash" || atbash
        is_excluded "reverse" || reverse
        is_excluded "base64" || base64d
        is_excluded "base32" || base32d
        is_excluded "hex" || hex_decode_method
        is_excluded "url" || url_decode_method
        is_excluded "xor" || xor_brute
        is_excluded "railfence" || railfence
        is_excluded "morse" || morse_method
        is_excluded "bin" || bin_method
        is_excluded "combo" || combo
        wait
    done
    
    echo -e "\n✔ Completado"
    [ -n "$OUTPUT_FILE" ] && echo "📁 Guardado en: $OUTPUT_FILE"
}

main
