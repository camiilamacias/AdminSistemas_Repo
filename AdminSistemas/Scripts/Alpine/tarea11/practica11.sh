#!/bin/sh
# =============================================================================
# practica11.sh — Tarea 11 — Alpine Linux
# Orquestación de microservicios con Docker Compose
#
# Uso: sh practica11.sh [-i|-v|-s|-u|-r|-p|-h]
#   -i  Instalar dependencias, generar archivos y levantar el stack
#   -v  Verificar estado de contenedores y redes
#   -s  Detener el stack (conserva datos)
#   -u  Iniciar stack previamente detenido
#   -r  Resetear todo (elimina contenedores y volumenes)
#   -p  Ejecutar protocolo de pruebas (4 pruebas)
#   -h  Mostrar ayuda
# =============================================================================

MAIN_DIR="$(cd "$(dirname "$0")" && pwd)"
LIB="$MAIN_DIR/lib"
COMPOSE_DIR="$MAIN_DIR"

# Cargar librerías
. "$LIB/colores.sh"
. "$LIB/docker_install.sh"
. "$LIB/T11_verificaciones.sh"
. "$LIB/T11_infraestructura.sh"
. "$LIB/T11_firewall.sh"
. "$LIB/T11_stack.sh"
. "$LIB/T11_pruebas.sh"

# Verificar root
if [ "$(id -u)" -ne 0 ]; then
    printf "${rojo}[ERROR] Este script debe ejecutarse como root${nc}\n"
    exit 1
fi

# Detectar docker compose al arrancar (para que -v/-s/-u/-r funcionen sin -i)
_detectar_compose_cmd() {
    if docker compose version >/dev/null 2>&1; then
        COMPOSE_CMD="docker compose"
    elif command -v docker-compose >/dev/null 2>&1; then
        COMPOSE_CMD="docker-compose"
    else
        COMPOSE_CMD=""
    fi
}
_detectar_compose_cmd

# =============================================================================
# ACCIONES
# =============================================================================

instalar() {
    print_titulo "Tarea 11 — Instalacion completa"
    verificar_dependencias
    crear_infraestructura "$COMPOSE_DIR"
    configurar_firewall_t11
    levantar_stack "$COMPOSE_DIR"
    print_titulo "Instalacion finalizada"
    estado_stack "$COMPOSE_DIR"
}

verificar() {
    estado_stack "$COMPOSE_DIR"
}

detener() {
    print_titulo "Deteniendo stack"
    detener_stack "$COMPOSE_DIR"
}

iniciar() {
    print_titulo "Iniciando stack"
    levantar_stack "$COMPOSE_DIR"
}

resetear() {
    print_titulo "Reseteo completo"
    print_info "[INFO] Esto eliminara contenedores, redes y volumenes de datos"
    printf "  Estas seguro? (s/N): "
    read confirm
    case "$confirm" in
        [sS]) resetear_stack "$COMPOSE_DIR" ;;
        *) print_info "[INFO] Operacion cancelada" ;;
    esac
}

pruebas() {
    ejecutar_pruebas
}

ayuda() {
    print_titulo "Tarea 11 — Orquestacion de Microservicios"
    printf "  ${verde}-i${nc}   Instalar dependencias, generar archivos y levantar el stack\n"
    printf "  ${verde}-v${nc}   Verificar estado de contenedores y redes\n"
    printf "  ${verde}-s${nc}   Detener el stack (conserva datos)\n"
    printf "  ${verde}-u${nc}   Iniciar stack previamente detenido\n"
    printf "  ${verde}-r${nc}   Resetear todo (elimina contenedores y volumenes)\n"
    printf "  ${verde}-p${nc}   Ejecutar protocolo de pruebas de aceptacion (4 pruebas)\n"
    printf "  ${verde}-h${nc}   Mostrar esta ayuda\n"
    printf "\n"
    printf "  ${azul}Servicios desplegados:${nc}\n"
    printf "    nginx        Puerto 80          Balanceador / punto de entrada publico\n"
    printf "    app_interna  (sin puertos)       Apache httpd, solo via nginx\n"
    printf "    postgresql   (sin puertos)       Base de datos, red interna red_datos\n"
    printf "    pgadmin      127.0.0.1:5050      Panel admin, solo via tunel SSH\n"
    printf "\n"
    printf "  ${azul}Redes internas:${nc}\n"
    printf "    red_publica  nginx + app_interna\n"
    printf "    red_datos    postgresql + pgadmin  (aislada del exterior)\n"
    printf "\n"
    printf "  ${azul}Acceso a pgAdmin via tunel SSH:${nc}\n"
    _ip=$(_obtener_ip)
    printf "    ssh -L 8080:localhost:5050 root@${_ip:-<ip_servidor>}\n"
    printf "    Luego abrir http://localhost:8080 en el navegador\n"
    printf "\n"
}

# =============================================================================
# PARSING DE ARGUMENTOS
# =============================================================================

if [ $# -eq 0 ]; then
    ayuda
    exit 0
fi

while getopts "ivsurhp" opt; do
    case $opt in
        i) instalar   ;;
        v) verificar  ;;
        s) detener    ;;
        u) iniciar    ;;
        r) resetear   ;;
        p) pruebas    ;;
        h) ayuda      ;;
        *) print_error "[ERROR] Opcion invalida. Usa -h para ver la ayuda"; exit 1 ;;
    esac
done
