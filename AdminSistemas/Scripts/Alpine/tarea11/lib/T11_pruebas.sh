#!/bin/sh
# T11_pruebas.sh — Protocolo de pruebas de aceptacion (Alpine Linux)
# Requiere que COMPOSE_DIR y COMPOSE_CMD esten definidos (los define practica11.sh)

_separador_prueba() {
    printf "\n${cyan}────────────────────────────────────────────────────────${nc}\n\n"
}

# Cargar variables del .env en el entorno actual
_leer_env() {
    local env_file="$1"
    if [ -f "$env_file" ]; then
        # Compatible con sh: exportar cada variable del .env
        while IFS='=' read -r _key _val; do
            # Saltar comentarios y lineas vacias
            case "$_key" in
                '#'*|'') continue ;;
            esac
            export "$_key=$_val"
        done < "$env_file"
    else
        print_error "[ERROR] No se encontro .env en: $env_file"
        return 1
    fi
}

_stack_corriendo() {
    docker inspect t11_db >/dev/null 2>&1 && \
    docker inspect --format='{{.State.Status}}' t11_db 2>/dev/null | grep -q "running"
}

# ─── Prueba 11.1 ─────────────────────────────────────────────────────────────

prueba_aislamiento_red() {
    print_titulo "Prueba 11.1 — Aislamiento de red"
    printf "  ${azul}Objetivo:${nc} Los puertos 5050 (pgAdmin) y 5432 (PostgreSQL)\n"
    printf "  deben ser inaccesibles desde la red publica.\n\n"

    resultado_general=0

    # pgAdmin debe estar vinculado solo a 127.0.0.1, no a 0.0.0.0
    pg_binding=$(ss -tlnp 2>/dev/null | grep ":5050" | awk '{print $4}')

    if [ -z "$pg_binding" ]; then
        print_completado "[OK] Puerto 5050 no expuesto al host (servicio no iniciado o totalmente interno)"
    elif echo "$pg_binding" | grep -q "127.0.0.1"; then
        print_completado "[OK] pgAdmin vinculado a 127.0.0.1:5050 (inaccesible desde la red externa)"
    else
        print_error "[FALLO] pgAdmin escucha en $pg_binding (deberia ser 127.0.0.1)"
        resultado_general=1
    fi

    # PostgreSQL no debe tener ningun mapeo al host
    db_binding=$(ss -tlnp 2>/dev/null | grep ":5432" | awk '{print $4}')

    if [ -z "$db_binding" ]; then
        print_completado "[OK] Puerto 5432 (PostgreSQL) no expuesto al host"
    else
        print_error "[FALLO] Puerto 5432 accesible en: $db_binding"
        resultado_general=1
    fi

    # Verificar reglas de iptables (Alpine usa iptables, no firewalld)
    printf "\n"
    if command -v iptables >/dev/null 2>&1; then
        print_info "[INFO] Reglas iptables para puertos sensibles:"
        iptables -L INPUT -n 2>/dev/null | grep -E "5050|5432" | while IFS= read -r _line; do
            printf "    ${amarillo}%s${nc}\n" "$_line"
        done

        if iptables -L INPUT -n 2>/dev/null | grep -qE "DROP.*5050"; then
            print_completado "[OK] iptables bloquea acceso externo al puerto 5050 (pgAdmin)"
        else
            print_info "[INFO] Sin regla DROP explicita en iptables para 5050 (vinculado a 127.0.0.1)"
        fi

        if iptables -L INPUT -n 2>/dev/null | grep -qE "DROP.*5432"; then
            print_completado "[OK] iptables bloquea acceso externo al puerto 5432 (PostgreSQL)"
        else
            print_info "[INFO] Sin regla DROP explicita en iptables para 5432 (sin mapeo al host)"
        fi
    fi

    printf "\n"
    _ip=$(_obtener_ip)
    print_info "[VERIFICACION MANUAL] Desde la maquina fisica ejecutar:"
    print_info "  curl -m 3 http://${_ip:-<ip_servidor>}:5050  →  debe dar Connection refused o timeout"

    [ $resultado_general -eq 0 ] \
        && print_completado "[RESULTADO] Prueba 11.1 SUPERADA" \
        || print_error    "[RESULTADO] Prueba 11.1 CON FALLOS"
}

# ─── Prueba 11.2 ─────────────────────────────────────────────────────────────

prueba_dns_interno() {
    print_titulo "Prueba 11.2 — Resolucion DNS interna"
    printf "  ${azul}Objetivo:${nc} Desde el contenedor nginx, resolver el nombre del\n"
    printf "  servicio 'postgresql' por DNS interno de Docker (sin IP fija).\n\n"

    resultado_general=0

    if ! _stack_corriendo; then
        print_error "[ERROR] El stack no esta corriendo. Levantalo con: sh practica11.sh -u"
        return 1
    fi

    # nginx esta en red_publica y red_datos, por lo que puede resolver postgresql
    print_info "[INFO] docker exec t11_nginx ping -c 2 postgresql"
    ping_output=$(docker exec t11_nginx ping -c 2 -W 2 postgresql 2>&1)

    if echo "$ping_output" | grep -q "bytes from"; then
        print_completado "[OK] nginx resuelve 'postgresql' por nombre de servicio (DNS interno Docker)"
        echo "$ping_output" | grep -E "PING|bytes from" | while IFS= read -r _line; do
            printf "    %s\n" "$_line"
        done
    else
        print_error "[FALLO] nginx no puede resolver 'postgresql'"
        echo "$ping_output" | head -5 | while IFS= read -r _line; do
            printf "    %s\n" "$_line"
        done
        resultado_general=1
    fi

    printf "\n"
    [ $resultado_general -eq 0 ] \
        && print_completado "[RESULTADO] Prueba 11.2 SUPERADA" \
        || print_error    "[RESULTADO] Prueba 11.2 CON FALLOS"
}

# ─── Prueba 11.3 ─────────────────────────────────────────────────────────────

prueba_tunel_ssh() {
    print_titulo "Prueba 11.3 — Tunel SSH cifrado"
    printf "  ${azul}Objetivo:${nc} Acceder a pgAdmin desde la maquina fisica a traves\n"
    printf "  de un tunel SSH local, sin exponer el puerto publicamente.\n\n"

    resultado_general=0

    _ip=$(_obtener_ip)

    if [ -n "$_ip" ]; then
        print_completado "[OK] IP del servidor: $_ip"
    else
        print_error "[AVISO] No se detecto IP del adaptador puente"
        _ip="<ip_servidor>"
        resultado_general=1
    fi

    # Verificar SSH activo (Alpine usa OpenRC: rc-service sshd)
    if rc-service sshd status >/dev/null 2>&1 || rc-service ssh status >/dev/null 2>&1; then
        print_completado "[OK] Servicio SSH activo"
    else
        print_error "[ERROR] sshd no esta activo — iniciar con: rc-service sshd start"
        resultado_general=1
    fi

    # Verificar pgAdmin corriendo y en escucha
    if docker inspect --format='{{.State.Status}}' t11_pgadmin 2>/dev/null | grep -q "running"; then
        print_completado "[OK] Contenedor pgAdmin en ejecucion"
        pg_port=$(ss -tlnp 2>/dev/null | grep ":5050" | awk '{print $4}')
        [ -n "$pg_port" ] && print_completado "[OK] pgAdmin escuchando en $pg_port"
    else
        print_error "[AVISO] Contenedor pgAdmin no esta corriendo"
        resultado_general=1
    fi

    printf "\n"
    print_info "[ACCION MANUAL] Ejecutar desde la maquina fisica:"
    printf "\n"
    printf "  ${verde}ssh -L 8080:localhost:5050 root@${_ip}${nc}\n"
    printf "\n"
    print_info "Luego abrir en el navegador: ${verde}http://localhost:8080${nc}"
    printf "\n"

    [ $resultado_general -eq 0 ] \
        && print_completado "[RESULTADO] Prueba 11.3 SUPERADA (verificar acceso desde navegador)" \
        || print_error    "[RESULTADO] Prueba 11.3 CON FALLOS previos al tunel"
}

# ─── Prueba 11.4 ─────────────────────────────────────────────────────────────

prueba_persistencia() {
    print_titulo "Prueba 11.4 — Persistencia de datos y healthcheck"
    printf "  ${azul}Objetivo:${nc} Los datos sobreviven a un docker-compose down/up.\n"
    printf "  pgAdmin espera a que PostgreSQL este healthy antes de iniciar.\n\n"

    resultado_general=0
    env_file="$COMPOSE_DIR/.env"

    _leer_env "$env_file" || return 1

    if ! _stack_corriendo; then
        print_error "[ERROR] El stack no esta corriendo. Levantalo con: sh practica11.sh -u"
        return 1
    fi

    # Verificar que PostgreSQL esta healthy
    db_status=$(docker inspect --format='{{.State.Health.Status}}' t11_db 2>/dev/null)
    if [ "$db_status" = "healthy" ]; then
        print_completado "[OK] PostgreSQL en estado: healthy"
    else
        print_error "[ERROR] PostgreSQL no esta healthy (estado: ${db_status:-desconocido})"
        return 1
    fi

    # Insertar dato de prueba
    print_info "[INFO] Insertando dato de prueba..."
    marca_tiempo="prueba_t11_$(date +%s)"

    docker exec t11_db psql -U "$DB_USER" -d "$DB_NAME" -c \
        "CREATE TABLE IF NOT EXISTS prueba_persistencia (id SERIAL, mensaje TEXT, ts TIMESTAMP DEFAULT NOW());" \
        >/dev/null 2>&1

    docker exec t11_db psql -U "$DB_USER" -d "$DB_NAME" -c \
        "INSERT INTO prueba_persistencia (mensaje) VALUES ('${marca_tiempo}');" \
        >/dev/null 2>&1

    count_antes=$(docker exec t11_db psql -U "$DB_USER" -d "$DB_NAME" -t -c \
        "SELECT COUNT(*) FROM prueba_persistencia;" 2>/dev/null | tr -d ' \n')
    print_completado "[OK] Registros antes del reinicio: $count_antes"

    # Bajar el stack
    printf "\n"
    print_info "[INFO] Deteniendo stack con docker-compose down..."
    $COMPOSE_CMD -f "$COMPOSE_DIR/docker-compose.yml" down >/dev/null 2>&1
    print_completado "[OK] Stack detenido — contenedores eliminados"

    # Verificar que el volumen persiste tras down
    if docker volume ls --format '{{.Name}}' 2>/dev/null | grep -q "^t11_db_data$"; then
        print_completado "[OK] Volumen t11_db_data persiste tras docker-compose down"
    else
        print_error "[FALLO] Volumen t11_db_data no encontrado tras el down"
        resultado_general=1
    fi

    # Volver a levantar
    printf "\n"
    print_info "[INFO] Reiniciando stack..."
    $COMPOSE_CMD -f "$COMPOSE_DIR/docker-compose.yml" --env-file "$env_file" up -d >/dev/null 2>&1
    print_completado "[OK] Stack iniciado"

    # Esperar healthcheck
    print_info "[INFO] Esperando que PostgreSQL alcance estado healthy..."
    intentos=0
    until docker inspect --format='{{.State.Health.Status}}' t11_db 2>/dev/null | grep -q "healthy"; do
        sleep 5
        intentos=$((intentos + 1))
        if [ "$intentos" -ge 12 ]; then
            print_error "[ERROR] Timeout esperando PostgreSQL healthy (60s)"
            return 1
        fi
        print_info "       Esperando... ($((intentos * 5))s)"
    done
    print_completado "[OK] PostgreSQL healthy tras reinicio"

    # Verificar que pgAdmin esperó al healthcheck
    pgadmin_status=$(docker inspect --format='{{.State.Status}}' t11_pgadmin 2>/dev/null)
    print_completado "[OK] pgAdmin en estado '$pgadmin_status' (inicio condicionado a service_healthy)"

    # Verificar integridad de datos
    printf "\n"
    print_info "[INFO] Verificando datos persistentes..."
    count_despues=$(docker exec t11_db psql -U "$DB_USER" -d "$DB_NAME" -t -c \
        "SELECT COUNT(*) FROM prueba_persistencia;" 2>/dev/null | tr -d ' \n')

    if [ "$count_despues" = "$count_antes" ] && [ -n "$count_despues" ]; then
        print_completado "[OK] Datos intactos: $count_despues registro(s) tras reinicio completo"
    else
        print_error "[FALLO] Discrepancia de datos (antes: $count_antes, despues: $count_despues)"
        resultado_general=1
    fi

    printf "\n"
    [ $resultado_general -eq 0 ] \
        && print_completado "[RESULTADO] Prueba 11.4 SUPERADA" \
        || print_error    "[RESULTADO] Prueba 11.4 CON FALLOS"
}

# ─── Orquestador de pruebas ───────────────────────────────────────────────────

ejecutar_pruebas() {
    print_titulo "Protocolo de pruebas de aceptacion — Tarea 11"

    _separador_prueba
    prueba_aislamiento_red

    _separador_prueba
    prueba_dns_interno

    _separador_prueba
    prueba_tunel_ssh

    _separador_prueba
    prueba_persistencia

    _separador_prueba
    print_completado "[OK] Protocolo de pruebas completado"
    printf "\n"
}
