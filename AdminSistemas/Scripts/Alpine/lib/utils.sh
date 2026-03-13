#!/bin/sh
# =============================================================================
# utilidades.sh — Funciones utilitarias generales
# Proyecto : Aprovisionamiento Web Automatizado
# SO       : Alpine Linux 3.23
# Uso      : source ./lib/utilidades.sh  
# =============================================================================

# -----------------------------------------------------------------------------
# COLORES ROSITA
# -----------------------------------------------------------------------------
C_RESET='\033[0m'
C_PINK='\033[38;5;213m'
C_ROSE='\033[38;5;218m'
C_HOTPINK='\033[38;5;205m'
C_WHITE='\033[1;37m'
C_BOLD='\033[1m'

# -----------------------------------------------------------------------------
# FUNCIONES DE IMPRESIÓN
# -----------------------------------------------------------------------------
print_warning() { printf "${C_HOTPINK}[ERROR] %s${C_RESET}\n" "$1"; }
print_success() { printf "${C_ROSE}[OK]    %s${C_RESET}\n" "$1"; }
print_info()    { printf "${C_PINK}[INFO]  %s${C_RESET}\n" "$1"; }
print_menu()    { printf "${C_PINK}%s${C_RESET}\n" "$1"; }
print_title()   { printf "\n${C_BOLD}${C_HOTPINK}========================================${C_RESET}\n";
                  printf "${C_BOLD}${C_HOTPINK}  %s${C_RESET}\n" "$1";
                  printf "${C_BOLD}${C_HOTPINK}========================================${C_RESET}\n\n"; }

# -----------------------------------------------------------------------------
# VERIFICAR ROOT
# -----------------------------------------------------------------------------
verificar_root() {
    if [ "$(id -u)" -ne 0 ]; then
        print_warning "Este script debe ejecutarse como root"
        exit 1
    fi
}

# -----------------------------------------------------------------------------
# VERIFICAR QUE UN COMANDO EXISTE
# Uso: requiere_comando "apk"
# -----------------------------------------------------------------------------
requiere_comando() {
    if ! command -v "$1" > /dev/null 2>&1; then
        print_warning "Comando requerido no encontrado: $1"
        return 1
    fi
    return 0
}

# -----------------------------------------------------------------------------
# VALIDAR INPUT GENÉRICO
# Uso: validar_input "valor" "nombre_campo"
# Rechaza: vacíos y caracteres peligrosos
# -----------------------------------------------------------------------------
validar_input() {
    valor="$1"
    campo="$2"

    if [ -z "$valor" ]; then
        print_warning "El campo '$campo' no puede estar vacío."
        return 1
    fi

    if echo "$valor" | grep -qE '[;|&$<>(){}\\`!]'; then
        print_warning "El campo '$campo' contiene caracteres no permitidos."
        return 1
    fi

    return 0
}

# -----------------------------------------------------------------------------
# VALIDAR PUERTO
# Uso: validar_puerto "8080"
# Verifica: que sea número, rango 1-65535, no ocupado
# MODIFICADO: Ahora permite TODOS los puertos (80, 202, 443, 808, etc.)
# -----------------------------------------------------------------------------
validar_puerto() {
    puerto="$1"

    # Validar que sea número
    if ! echo "$puerto" | grep -qE '^[0-9]+$'; then
        print_warning "El puerto debe ser un número entero."
        return 1
    fi

    # Validar rango (MODIFICADO: permite 1-65535 en lugar de 1024-65535)
    if [ "$puerto" -lt 1 ] || [ "$puerto" -gt 65535 ]; then
        print_warning "Puerto $puerto fuera de rango permitido (1-65535)."
        return 1
    fi

    # Puertos reservados COMENTADOS (permite cualquier puerto)
    # Si necesitas bloquear puertos específicos, descomenta esta sección:
    # case "$puerto" in
    #     21|22|2122|23|25|53|110|143|443|3306|5432|6379|27017|40000|40001|40002|40003|40004|40005)
    #         print_warning "Puerto $puerto reservado para otro servicio del sistema."
    #         return 1
    #         ;;
    # esac

    # Verificar que no esté ocupado
    if netstat -tuln 2>/dev/null | grep -q ":${puerto} " || ss -tuln 2>/dev/null | grep -q ":${puerto} "; then
        # Intentar obtener el proceso
        proceso=$(netstat -tulnp 2>/dev/null | grep ":${puerto} " | awk '{print $7}' | head -1)
        if [ -z "$proceso" ]; then
            proceso=$(ss -tulnp 2>/dev/null | grep ":${puerto} " | grep -oP 'users:\(\(".*?",pid=\K[0-9]+' | head -1)
        fi
        
        print_warning "Puerto $puerto ya está en uso."
        if [ -n "$proceso" ]; then
            print_warning "        Proceso: $proceso"
        fi
        return 1
    fi

    print_success "Puerto $puerto disponible."
    return 0
}

# -----------------------------------------------------------------------------
# PEDIR PUERTO AL USUARIO (con reintentos)
# Exporta: PUERTO_ELEGIDO
# -----------------------------------------------------------------------------
pedir_puerto() {
    intentos=0
    max_intentos=3

    while [ "$intentos" -lt "$max_intentos" ]; do
        printf "${C_PINK}Ingresa el puerto de escucha (ej. 80, 8080, 8888): ${C_RESET}"
        read puerto_raw

        if validar_input "$puerto_raw" "puerto" && validar_puerto "$puerto_raw"; then
            PUERTO_ELEGIDO="$puerto_raw"
            export PUERTO_ELEGIDO
            return 0
        fi

        intentos=$((intentos + 1))
        print_info "Intento $intentos de $max_intentos."
    done

    print_warning "Demasiados intentos fallidos al ingresar el puerto."
    return 1
}

# -----------------------------------------------------------------------------
# ABRIR PUERTO EN FIREWALL (iptables — Alpine)
# Uso: abrir_puerto_firewall "8080"
# Cierra el puerto 80 por defecto si el usuario eligió otro
# -----------------------------------------------------------------------------
abrir_puerto_firewall() {
    puerto="$1"

    print_info "Configurando firewall para puerto $puerto..."

    # Instalar iptables si no existe
    if ! requiere_comando "iptables"; then
        apk add --no-cache iptables ip6tables > /dev/null 2>&1
    fi

    # Abrir puerto específico
    if ! iptables -C INPUT -p tcp --dport "$puerto" -j ACCEPT 2>/dev/null; then
        iptables -A INPUT -p tcp --dport "$puerto" -j ACCEPT
        print_success "Puerto $puerto abierto en firewall."
    else
        print_info "Puerto $puerto ya estaba abierto."
    fi

    # Cerrar puerto 80 si no se usa
    if [ "$puerto" -ne 80 ]; then
        if iptables -C INPUT -p tcp --dport 80 -j ACCEPT 2>/dev/null; then
            iptables -D INPUT -p tcp --dport 80 -j ACCEPT 2>/dev/null
            print_info "Puerto 80 cerrado (no utilizado)."
        fi
    fi

    # Cerrar puerto 443 si no se usa
    if [ "$puerto" -ne 443 ]; then
        if iptables -C INPUT -p tcp --dport 443 -j ACCEPT 2>/dev/null; then
            iptables -D INPUT -p tcp --dport 443 -j ACCEPT 2>/dev/null
            print_info "Puerto 443 cerrado (no utilizado)."
        fi
    fi

    # Guardar reglas
    if command -v rc-service > /dev/null 2>&1; then
        rc-service iptables save 2>/dev/null
        print_success "Reglas de firewall guardadas."
    fi
}

# -----------------------------------------------------------------------------
# CREAR USUARIO DEDICADO PARA UN SERVICIO
# Uso: crear_usuario_servicio "httpd-user" "/var/www/localhost/htdocs"
# -----------------------------------------------------------------------------
crear_usuario_servicio() {
    usuario="$1"
    directorio="$2"

    if id "$usuario" > /dev/null 2>&1; then
        print_info "Usuario '$usuario' ya existe."
    else
        print_info "Creando usuario dedicado '$usuario'..."
        adduser -D -H -s /sbin/nologin "$usuario" 2>/dev/null
        print_success "Usuario '$usuario' creado."
    fi

    if [ -d "$directorio" ]; then
        chown -R "${usuario}:${usuario}" "$directorio"
        chmod 750 "$directorio"
        print_success "Permisos aplicados en $directorio para '$usuario'."
    fi
}

# -----------------------------------------------------------------------------
# CREAR INDEX.HTML PERSONALIZADO
# Uso: crear_index "Apache2" "2.4.62" "8080" "/var/www/localhost/htdocs"
# -----------------------------------------------------------------------------
crear_index() {
    servicio="$1"
    version="$2"
    puerto="$3"
    ruta_web="$4"

    mkdir -p "$ruta_web"

    cat > "${ruta_web}/index.html" << EOF
<!DOCTYPE html>
<html lang="es">
<head>
  <meta charset="UTF-8">
  <title>Servidor Web - $servicio</title>
  <style>
    body { 
      font-family: Arial, sans-serif; 
      background: linear-gradient(135deg, #FFB6C1, #FFC0CB); 
      display: flex; 
      justify-content: center; 
      align-items: center; 
      height: 100vh; 
      margin: 0; 
    }
    .card { 
      background: white; 
      border: 2px solid #FF69B4; 
      padding: 3rem 4rem;
      border-radius: 15px; 
      text-align: center; 
      box-shadow: 0 8px 16px rgba(0,0,0,0.1);
    }
    h1 { color: #FF1493; margin: 0 0 1.5rem 0; }
    p { color: #666; font-size: 1.2rem; margin: 0.5rem 0; }
    span { color: #FF69B4; font-weight: bold; }
  </style>
</head>
<body>
  <div class="card">
    <h1>Servidor HTTP Activo</h1>
    <p>Servidor: <span>$servicio</span></p>
    <p>Versión: <span>$version</span></p>
    <p>Puerto: <span>$puerto</span></p>
    <p>Sistema: <span>Alpine Linux 3.23</span></p>
  </div>
</body>
</html>
EOF

    print_success "index.html creado en $ruta_web"
}

# -----------------------------------------------------------------------------
# PAUSAR HASTA QUE EL USUARIO PRESIONE ENTER
# -----------------------------------------------------------------------------
pausar() {
    printf "\n${C_PINK}Presiona Enter para continuar...${C_RESET}"
    read pausa
}