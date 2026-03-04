#!/bin/sh

# --- COLORES ROSITA ---
PINK='\033[0;35m'
LIGHT_PINK='\033[1;95m'
ROSE='\033[38;5;213m'
HOT_PINK='\033[38;5;205m'
SOFT_PINK='\033[38;5;218m'
DARK_PINK='\033[38;5;169m'
WHITE='\033[1;37m'
NC='\033[0m' # Sin color

echo -e "${HOT_PINK}===================================================${NC}"
echo -e "${LIGHT_PINK}=================PRUEBA DE SCRIPT (ALPINE)=========${NC}"
echo -e "${HOT_PINK}===================================================${NC}"

# --- FUNCIONES DE APOYO ---

validacionIp() {
    local mensaje=$1
    local opcional=$2
    while true; do
        # IMPORTANTE: Enviamos el mensaje a >&2 para que sea visible durante la captura
        printf "${SOFT_PINK}%s${NC}" "$mensaje" >&2
        read ip
        if [ "$opcional" = "true" ] && [ -z "$ip" ]; then echo ""; return 0; fi

        # Validar formato con Regex
        if echo "$ip" | grep -E -q '^((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$'; then
            
            # Validar ceros a la izquierda
            if echo "$ip" | grep -q '\.0[0-9]'; then
                echo -e "${HOT_PINK}error: no se permiten ceros a la izquierda${NC}" >&2
                continue
            fi

            # Validaciones especiales
            primerOcteto=$(echo $ip | cut -d. -f1)
            if [ "$ip" = "0.0.0.0" ]; then echo -e "${HOT_PINK}error: 0.0.0.0 reservada${NC}" >&2
            elif [ "$ip" = "255.255.255.255" ]; then echo -e "${HOT_PINK}error: Global Broadcast${NC}" >&2
            elif [ "$primerOcteto" -eq 127 ]; then echo -e "${HOT_PINK}error: Rango Loopback${NC}" >&2
            elif [ "$primerOcteto" -ge 224 ]; then echo -e "${HOT_PINK}error: IP Multicast o Reservada${NC}" >&2
            else
                # Solo el valor final se envía al canal normal (stdout) para ser capturado por la variable
                echo "$ip"
                return 0
            fi
        else
            echo -e "${HOT_PINK}formato ipv4 invalido. reintente${NC}" >&2
        fi
    done
}

# --- FUNCIONES PRINCIPALES ---

verificarInstalacion() {
    echo -e "${LIGHT_PINK}Verificando la instalacion DHCP...${NC}"
    if [ -f "/usr/sbin/kea-dhcp4" ]; then
        echo -e "${ROSE}SERVICIO KEA-DHCP4 INSTALADO${NC}"
    else
        echo -e "${HOT_PINK}SERVICIO KEA-DHCP4 NO INSTALADO${NC}"
        echo -e "${LIGHT_PINK}sugerencia!... use la opcion de instalar el servicio${NC}"
    fi
}

instalacion() {
    echo -e "${SOFT_PINK} INICIANDO INSTALACION...${NC}"
    if [ -f "/usr/sbin/kea-dhcp4" ]; then
        echo -e "${ROSE}SERVICIO KEA-DHCP4 INSTALADO, (no es necesario una instalacion)${NC}"
    else
        apk add kea-dhcp4
        if [ $? -eq 0 ]; then
            mkdir -p /var/lib/kea
            echo -e "${ROSE}SERVICIO KEA-DHCP4 INSTALADO CON EXITO!${NC}"
        else
            echo -e "${HOT_PINK}error al instalar${NC}"
        fi
    fi
}

desinstalacion() {
    echo -e "${DARK_PINK}INICIANDO DESINSTALACION...${NC}"
    if [ -f "/usr/sbin/kea-dhcp4" ]; then
        echo -e "${LIGHT_PINK}deteniendo proceso en memoria...${NC}"
        rc-service kea-dhcp4 stop 2>/dev/null
        apk del kea-dhcp4
        echo -e "${ROSE}desinstalacion exitosa!${NC}"
    else
        echo -e "${HOT_PINK}servicio no instalado, por lo tanto no se puede desinstalar${NC}"
    fi
}

configuracionDhcp() {
    echo -e "${HOT_PINK}===CONFIGURACION DEL SERVICIO KEA DHCP===${NC}"

    printf "Ingrese un nombre para el scope: "
    read nombreScope

    # Ahora esto SI mostrará el mensaje en pantalla
    rangoI=$(validacionIp "IP Inicial del rango (Fija para Servidor eth1): ")
    prefijoI=$(echo $rangoI | cut -d. -f1-3)
    
    echo -e "${LIGHT_PINK}configurando la ip fija del servidor ($rangoI)...${NC}"
    ip addr add $rangoI/24 dev eth1 2>/dev/null
    ip link set eth1 up 2>/dev/null

    ultimo=$(echo $rangoI | cut -d. -f4)
    rangoDhcpInicio="$prefijoI.$((ultimo + 1))"
    echo -e "${WHITE}el rango de clientes empezara en: $rangoDhcpInicio${NC}"

    while true; do
        rangoF=$(validacionIp "IP final del rango: ")
        prefijoF=$(echo $rangoF | cut -d. -f1-3)
        
        ultimoF=$(echo $rangoF | cut -d. -f4)
        if [ $ultimo -ge $ultimoF ]; then
            echo -e "${HOT_PINK}error, la inicial ($rangoI) no puede ser mayor a la final ($rangoF)${NC}"
        elif [ "$prefijoI" != "$prefijoF" ]; then
            echo -e "${HOT_PINK}error, deben pertenecer a la misma subred ($prefijoI.x)${NC}"
        else
            echo -e "${ROSE}las IPs son validas${NC}"
            redId="$prefijoI.0"
            break
        fi
    done

    dns=$(validacionIp "servidor DNS (ej: 8.8.8.8): ")
    [ -z "$dns" ] && dns="8.8.8.8"

    printf "${SOFT_PINK}ingrese la ip del gateway (deje en blanco para saltar): ${NC}"
    read gateway

    printf "${SOFT_PINK}ingrese tiempo de concesion (segundos, ej: 28800): ${NC}"
    read tiempolease
    [ -z "$tiempolease" ] && tiempolease="28800"

    echo -e "${SOFT_PINK}generando configuracion JSON...${NC}"

    # Generamos el JSON. Usamos una técnica para que si gateway está vacío, no rompa el JSON.
    OPT_GW=""
    if [ -n "$gateway" ]; then
        OPT_GW=", { \"name\": \"routers\", \"data\": \"$gateway\" }"
    fi

    cat <<EOF > /etc/kea/kea-dhcp4.conf
{
"Dhcp4": {
    "interfaces-config": { "interfaces": [ "eth1" ] },
    "lease-database": {
        "type": "memfile",
        "persist": true,
        "name": "/var/lib/kea/kea-leases4.csv"
    },
    "valid-lifetime": $tiempolease,
    "subnet4": [
        {
            "id": 1,
            "subnet": "$redId/24",
            "pools": [ { "pool": "$rangoDhcpInicio - $rangoF" } ],
            "option-data": [
                { "name": "domain-name-servers", "data": "$dns" }$OPT_GW
            ]
        }
    ]
}
}
EOF

    rc-service kea-dhcp4 restart
    rc-update add kea-dhcp4 default
    echo -e "${ROSE}¡Configuración exitosa para el scope: $nombreScope!${NC}"
}

monitoreo() {
    echo -e "${HOT_PINK}==================MONITOREO Y ESTADO DEL SERVICIO==================${NC}"
    if rc-service kea-dhcp4 status | grep -q "started"; then
        echo -e "estado del servicio: ${ROSE}Running${NC}"
    else
        echo -e "${HOT_PINK}el servicio dhcp no esta iniciado${NC}"
        return
    fi

    echo "--------------------------------------------------------------------------"
    echo -e "${LIGHT_PINK}Equipos conectados (Leases):${NC}"
    if [ -f /var/lib/kea/kea-leases4.csv ]; then
        cat /var/lib/kea/kea-leases4.csv | column -t -s ','
    else
        echo -e "${WHITE}no hay equipos conectados actualmente${NC}"
    fi
}

menu() {
    echo -e "${HOT_PINK}==================MENU DE OPCIONES==================${NC}"
    echo -e "${LIGHT_PINK}1. verificar instalacion${NC}"
    echo -e "${LIGHT_PINK}2. instalar servicio${NC}"
    echo -e "${LIGHT_PINK}3. desinstalar servicio${NC}"
    echo -e "${LIGHT_PINK}4. configuracion dhcp${NC}"
    echo -e "${LIGHT_PINK}5. monitoreo de servicio${NC}"
    echo -e "6. Salir${NC}"
}

# --- LOOP PRINCIPAL ---
while true; do
    menu
    printf "ingrese una opcion: "
    read opcion

    case $opcion in
        1) verificarInstalacion ;;
        2) instalacion ;;
        3) desinstalacion ;;
        4) configuracionDhcp ;;
        5) monitoreo ;;
        6) exit 0 ;;
        *) echo -e "${HOT_PINK}opcion invalida!${NC}" ;;
    esac

    printf "\n${LIGHT_PINK}¿Desea volver al menú? (si/no): ${NC}"
    read choice
    if [ "$choice" != "si" ]; then break; fi
done