#!/bin/sh
# =============================================================================
# Main_HTTP.sh - Script Principal para Servidores HTTP
# Proyecto : Aprovisionamiento Web Automatizado
# SO       : Alpine Linux 3.23
# Uso      : sudo ./Main_HTTP.sh
# =============================================================================

# Cargar librerías
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

if [ -f "$SCRIPT_DIR/lib/utils.sh" ]; then
    . "$SCRIPT_DIR/lib/utils.sh"
elif [ -f "$SCRIPT_DIR/utils.sh" ]; then
    . "$SCRIPT_DIR/utils.sh"
else
    echo "ERROR: No se encontró utils.sh"
    exit 1
fi

if [ -f "$SCRIPT_DIR/lib/http_functions.sh" ]; then
    . "$SCRIPT_DIR/lib/http_functions.sh"
elif [ -f "$SCRIPT_DIR/http_functions.sh" ]; then
    . "$SCRIPT_DIR/http_functions.sh"
else
    echo "ERROR: No se encontró http_functions.sh"
    exit 1
fi

# Verificar root
verificar_root

# =============================================================================
# MENÚ PRINCIPAL
# =============================================================================
menu_principal() {
    while true; do
        clear
        print_title "SERVIDORES HTTP - ALPINE LINUX"
        
        printf "${C_PINK}1)${C_RESET} Instalar Apache2\n"
        printf "${C_PINK}2)${C_RESET} Instalar Nginx\n"
        printf "${C_PINK}3)${C_RESET} Instalar Tomcat\n"
        printf "${C_PINK}4)${C_RESET} Verificar servicios\n"
        printf "${C_PINK}5)${C_RESET} Revisar HTTP (curl)\n"
        printf "${C_PINK}0)${C_RESET} Salir\n\n"
        
        printf "${C_PINK}Seleccione [0-5]:${C_RESET} "
        read OPCION
        
        case "$OPCION" in
            1) setup_apache ;;
            2) setup_nginx ;;
            3) setup_tomcat ;;
            4) verificar_HTTP ;;
            5) revisar_HTTP ;;
            0) print_info "Saliendo..."; exit 0 ;;
            *) print_warning "Opción inválida" ;;
        esac
        
        pausar
    done
}

# Ejecutar menú principal
menu_principal