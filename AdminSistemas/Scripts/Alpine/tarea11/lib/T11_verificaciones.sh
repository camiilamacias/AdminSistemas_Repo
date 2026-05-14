#!/bin/sh
# T11_verificaciones.sh — Verificacion de dependencias para Alpine Linux
# Equivalente al T11_verificaciones.sh del compañero pero con apk + OpenRC

verificar_docker_compose() {
    print_info "[INFO] Verificando Docker Compose..."

    # Opcion 1: plugin v2 (docker compose)
    if docker compose version >/dev/null 2>&1; then
        print_completado "[OK] Docker Compose plugin: $(docker compose version 2>/dev/null | head -1)"
        COMPOSE_CMD="docker compose"
        return
    fi

    # Opcion 2: binario independiente v1 (docker-compose)
    if command -v docker-compose >/dev/null 2>&1; then
        print_completado "[OK] docker-compose: $(docker-compose --version 2>/dev/null)"
        COMPOSE_CMD="docker-compose"
        return
    fi

    # Instalar via apk (Alpine)
    print_info "[INFO] Intentando instalar docker-cli-compose via apk..."
    apk add --no-cache docker-cli-compose >/dev/null 2>&1
    if docker compose version >/dev/null 2>&1; then
        print_completado "[OK] Docker Compose v2 instalado via apk"
        COMPOSE_CMD="docker compose"
        return
    fi

    # Fallback: docker-compose clasico via apk
    print_info "[INFO] Intentando instalar docker-compose via apk..."
    apk add --no-cache docker-compose >/dev/null 2>&1
    if command -v docker-compose >/dev/null 2>&1; then
        print_completado "[OK] docker-compose instalado via apk"
        COMPOSE_CMD="docker-compose"
        return
    fi

    print_error "[ERROR] No se pudo instalar Docker Compose"
    print_info "[INFO] Instala manualmente: apk add docker-cli-compose"
    exit 1
}

verificar_dependencias() {
    print_titulo "Verificando dependencias"
    verificar_docker
    verificar_servicio_docker
    verificar_grupo_docker
    verificar_docker_compose
}

# Utilidad: obtener IP del adaptador puente (sin hardcodear interfaz)
# En Alpine el adaptador puente suele ser eth1 o eth2 segun la config de VirtualBox
_obtener_ip() {
    ip -4 addr show 2>/dev/null \
        | awk '/inet / && !/127\./ && !/10\.0\.2\./{print $2}' \
        | cut -d/ -f1 | head -1
}
