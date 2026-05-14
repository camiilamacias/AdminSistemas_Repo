#!/bin/sh
# utils.sh - Funciones de utilidad compartidas

# Colores
verde='\033[1;37m'
amarillo='\033[0;35m'
rojo='\033[1;35m'
cyan='\033[1;35m'
nc='\033[0m'

print_titulo() {
    echo ""
    echo -e "${cyan}========== $1 ==========${nc}"
    echo ""
}

print_info() {
    echo -e "${amarillo}$1${nc}"
}

print_completado() {
    echo -e "${verde}$1${nc}"
}

print_error() {
    echo -e "${rojo}$1${nc}"
}
