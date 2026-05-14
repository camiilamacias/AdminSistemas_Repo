#!/bin/sh
# docker_install.sh — Instalacion de Docker para Alpine Linux
# Habilita el repositorio 'community' antes de instalar (Docker vive ahi)

_habilitar_repo_community() {
    _repos="/etc/apk/repositories"

    if grep -qE '^[^#].*community' "$_repos" 2>/dev/null; then
        print_completado "[OK] Repositorio community ya habilitado"
        return
    fi

    print_info "[INFO] Habilitando repositorio community en $_repos..."

    if grep -qE '^#.*community' "$_repos" 2>/dev/null; then
        sed -i 's|^#\(.*community\)|\1|' "$_repos"
        print_completado "[OK] Repositorio community habilitado (descomenado)"
        return
    fi

    _ver=$(cat /etc/alpine-release 2>/dev/null | cut -d. -f1-2)
    [ -z "$_ver" ] && _ver="edge" || _ver="v${_ver}"

    _mirror=$(grep -E '^https?://' "$_repos" 2>/dev/null | head -1 \
              | sed 's|/v[0-9][^/]*/.*||; s|/edge/.*||')
    [ -z "$_mirror" ] && _mirror="https://dl-cdn.alpinelinux.org/alpine"

    printf "%s/%s/community\n" "$_mirror" "$_ver" >> "$_repos"
    print_completado "[OK] Repositorio community agregado: $_mirror/$_ver/community"
}

verificar_docker() {
    print_info "[INFO] Verificando instalacion de Docker..."

    if command -v docker >/dev/null 2>&1; then
        print_completado "[OK] Docker ya instalado: $(docker --version)"
        return
    fi

    print_info "[INFO] Docker no encontrado — preparando instalacion..."
    _habilitar_repo_community

    print_info "[INFO] Actualizando indices apk..."
    apk update

    print_info "[INFO] Instalando docker..."
    if apk add --no-cache docker; then
        print_completado "[OK] Docker instalado correctamente"
    else
        print_error "[ERROR] Fallo la instalacion de Docker"
        print_info "[INFO] Contenido de /etc/apk/repositories:"
        cat /etc/apk/repositories 2>/dev/null | while IFS= read -r _l; do
            printf "       %s\n" "$_l"
        done
        print_info "[INFO] Prueba manualmente: apk add docker"
        exit 1
    fi
}

verificar_servicio_docker() {
    print_info "[INFO] Verificando servicio Docker..."

    if rc-service docker status >/dev/null 2>&1; then
        print_completado "[OK] Servicio Docker activo"
        return
    fi

    print_info "[INFO] Iniciando servicio Docker..."
    rc-update add docker default >/dev/null 2>&1
    rc-service docker start
    sleep 3

    if rc-service docker status >/dev/null 2>&1; then
        print_completado "[OK] Servicio Docker iniciado"
    else
        print_error "[ERROR] No se pudo iniciar Docker"
        print_info "[INFO] Intenta manualmente: rc-service docker start"
        exit 1
    fi
}

verificar_grupo_docker() {
    print_info "[INFO] Verificando acceso a Docker..."
    if docker ps >/dev/null 2>&1; then
        print_completado "[OK] Acceso a Docker correcto"
    else
        print_error "[ERROR] No se puede conectar al daemon de Docker"
        print_info "[INFO] Verifica: rc-service docker status"
        exit 1
    fi
}