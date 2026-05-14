#!/bin/sh
# colores.sh — Esquema de colores para Alpine
# Mismos nombres de variable que el script del compañero para compatibilidad

rojo='\033[38;5;205m'       # hotpink  — errores
verde='\033[38;5;218m'      # rose     — completado / OK
amarillo='\033[38;5;213m'   # pink     — informacion
azul='\033[38;5;99m'        # lavender — titulos
cyan='\033[38;5;183m'       # lilac    — separadores
nc='\033[0m'                # reset

print_error() {
    printf "${rojo}$1${nc}\n"
}

print_completado() {
    printf "${verde}$1${nc}\n"
}

print_info() {
    printf "${amarillo}$1${nc}\n"
}

print_titulo() {
    printf "\n${azul}==== $1 ====${nc}\n\n"
}
