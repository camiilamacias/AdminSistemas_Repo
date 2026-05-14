#!/bin/sh
# T11_stack.sh — Gestion del stack Docker Compose (Alpine Linux)
# Equivalente al T11_stack.sh del compañero pero para Alpine/OpenRC

_require_compose() {
    if [ -z "$COMPOSE_CMD" ]; then
        print_error "[ERROR] Docker Compose no detectado."
        print_info "[INFO] Instala el stack primero con: sh practica11.sh -i"
        exit 1
    fi
}

levantar_stack() {
    local dir="$1"
    _require_compose

    print_titulo "Levantando stack de microservicios"

    if [ ! -f "$dir/docker-compose.yml" ]; then
        print_error "[ERROR] No se encontro docker-compose.yml en $dir"
        print_info "[INFO] Genera la infraestructura primero con: sh practica11.sh -i"
        exit 1
    fi

    if [ ! -f "$dir/.env" ]; then
        print_error "[ERROR] No se encontro .env en $dir"
        print_info "[INFO] Genera la infraestructura primero con: sh practica11.sh -i"
        exit 1
    fi

    print_info "[INFO] Descargando imagenes y levantando contenedores..."
    $COMPOSE_CMD -f "$dir/docker-compose.yml" --env-file "$dir/.env" up -d
    if [ $? -ne 0 ]; then
        print_error "[ERROR] Fallo al levantar el stack"
        exit 1
    fi
    print_completado "[OK] Stack levantado"

    # Esperar healthcheck de PostgreSQL
    print_info "[INFO] Esperando healthcheck de PostgreSQL..."
    intentos=0
    until docker inspect --format='{{.State.Health.Status}}' t11_db 2>/dev/null | grep -q "healthy"; do
        sleep 5
        intentos=$((intentos + 1))
        if [ "$intentos" -ge 12 ]; then
            print_error "[ERROR] PostgreSQL no alcanzo estado healthy en 60s"
            exit 1
        fi
        print_info "[INFO] Esperando... ($((intentos * 5))s)"
    done
    print_completado "[OK] PostgreSQL healthy — todos los servicios listos"
}

estado_stack() {
    local dir="$1"
    _require_compose

    print_titulo "Estado del stack"
    $COMPOSE_CMD -f "$dir/docker-compose.yml" ps
    printf "\n"

    print_info "[INFO] Redes activas:"
    docker network ls 2>/dev/null | grep t11
    printf "\n"

    print_info "[INFO] Volumen de datos:"
    docker volume ls 2>/dev/null | grep t11
    printf "\n"

    print_info "[INFO] Para acceder a pgAdmin via tunel SSH:"
    _ip=$(_obtener_ip)
    print_info "       ssh -L 8080:localhost:5050 root@${_ip:-<ip_servidor>}"
    print_info "       Luego abrir: http://localhost:8080"
}

detener_stack() {
    local dir="$1"
    _require_compose

    print_info "[INFO] Deteniendo stack (los datos se conservan)..."
    $COMPOSE_CMD -f "$dir/docker-compose.yml" down
    print_completado "[OK] Stack detenido"
}

resetear_stack() {
    local dir="$1"
    _require_compose

    print_info "[INFO] Eliminando contenedores y volumenes..."
    $COMPOSE_CMD -f "$dir/docker-compose.yml" down -v
    print_completado "[OK] Stack y volumenes eliminados"
}
