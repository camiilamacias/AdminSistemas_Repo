#!/bin/sh
# T11_firewall.sh — Configuracion de firewall con iptables (Alpine Linux)
# El compañero usa firewalld (systemd). Alpine usa iptables directamente.

configurar_firewall_t11() {
    print_titulo "Configurando firewall (iptables)"

    # Verificar que iptables esta disponible
    if ! command -v iptables >/dev/null 2>&1; then
        print_info "[INFO] Instalando iptables..."
        apk add --no-cache iptables >/dev/null 2>&1
        if ! command -v iptables >/dev/null 2>&1; then
            print_info "[INFO] iptables no disponible, omitiendo configuracion de firewall"
            return
        fi
    fi

    # Detectar interfaz externa (adaptador puente, la que tiene la IP accesible)
    _ext_if=$(ip route show default 2>/dev/null | awk '/default/{print $5}' | head -1)
    if [ -z "$_ext_if" ]; then
        _ext_if="eth0"
        print_info "[INFO] Interfaz no detectada automaticamente, usando: $_ext_if"
    fi
    print_info "[INFO] Interfaz externa detectada: $_ext_if"

    # SSH siempre permitido (unico vector de acceso a servicios internos)
    if ! iptables -C INPUT -p tcp --dport 22 -j ACCEPT 2>/dev/null; then
        iptables -A INPUT -p tcp --dport 22 -j ACCEPT
    fi
    print_completado "[OK] Puerto 22 (SSH) abierto"

    # Puerto 80 abierto para nginx (unico punto de entrada publico)
    if ! iptables -C INPUT -p tcp --dport 80 -j ACCEPT 2>/dev/null; then
        iptables -A INPUT -p tcp --dport 80 -j ACCEPT
    fi
    print_completado "[OK] Puerto 80 (nginx) abierto"

    # Bloquear pgAdmin en la interfaz externa
    # pgAdmin ya esta vinculado a 127.0.0.1 en compose, pero se bloquea
    # explicitamente en el firewall para demostrar defensa en profundidad
    iptables -D INPUT -i "$_ext_if" -p tcp --dport 5050 -j DROP 2>/dev/null || true
    iptables -A INPUT -i "$_ext_if" -p tcp --dport 5050 -j DROP
    print_completado "[OK] Puerto 5050 (pgAdmin) bloqueado externamente"

    # Bloquear PostgreSQL en la interfaz externa
    # postgresql no tiene mapeo de puertos al host, pero se cierra 5432
    # por si otra instancia estuviera expuesta
    iptables -D INPUT -i "$_ext_if" -p tcp --dport 5432 -j DROP 2>/dev/null || true
    iptables -A INPUT -i "$_ext_if" -p tcp --dport 5432 -j DROP
    print_completado "[OK] Puerto 5432 (PostgreSQL) bloqueado externamente"

    # Guardar reglas para que persistan tras reinicios
    if command -v iptables-save >/dev/null 2>&1; then
        mkdir -p /etc/iptables
        iptables-save > /etc/iptables/rules.v4 2>/dev/null \
            && print_completado "[OK] Reglas de firewall guardadas en /etc/iptables/rules.v4" \
            || print_info "[INFO] No se pudieron persistir las reglas (no critico)"
    fi

    printf "\n"
    print_info "[INFO] Acceso a pgAdmin SOLO via tunel SSH:"
    _ip=$(_obtener_ip)
    print_info "       ssh -L 8080:localhost:5050 root@${_ip:-<ip_servidor>}"
    print_info "       Luego abrir: http://localhost:8080"
}
