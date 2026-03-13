#!/bin/sh
# =============================================================================
# diagnostico_tomcat.sh - Diagnóstico automático de Tomcat en puerto 281
# =============================================================================

echo "╔════════════════════════════════════════════════════════════════════╗"
echo "║     DIAGNÓSTICO AUTOMÁTICO - TOMCAT PUERTO 281                     ║"
echo "╚════════════════════════════════════════════════════════════════════╝"
echo ""

# Colores
C_OK='\033[1;32m'
C_FAIL='\033[1;31m'
C_WARN='\033[1;33m'
C_INFO='\033[1;36m'
C_RESET='\033[0m'

PUERTO=281
PROBLEMAS=0

# =============================================================================
# 1. VERIFICAR QUE EL SCRIPT USA SYSCTL (NO SETCAP)
# =============================================================================
echo "${C_INFO}[1/10] Verificando tipo de script...${C_RESET}"
if [ -f "http_functions.sh" ]; then
    if grep -q "sysctl" http_functions.sh; then
        echo "  ${C_OK}✓ Script CORRECTO (usa sysctl)${C_RESET}"
    else
        echo "  ${C_FAIL}✗ Script VIEJO (usa setcap - NO funciona en Alpine)${C_RESET}"
        echo "  ${C_WARN}→ Necesitas copiar el script del compañero${C_RESET}"
        PROBLEMAS=$((PROBLEMAS + 1))
    fi
elif [ -f "lib/http_functions.sh" ]; then
    if grep -q "sysctl" lib/http_functions.sh; then
        echo "  ${C_OK}✓ Script CORRECTO (usa sysctl)${C_RESET}"
    else
        echo "  ${C_FAIL}✗ Script VIEJO (usa setcap - NO funciona en Alpine)${C_RESET}"
        echo "  ${C_WARN}→ Necesitas copiar el script del compañero${C_RESET}"
        PROBLEMAS=$((PROBLEMAS + 1))
    fi
else
    echo "  ${C_FAIL}✗ No se encuentra http_functions.sh${C_RESET}"
    PROBLEMAS=$((PROBLEMAS + 1))
fi
echo ""

# =============================================================================
# 2. VERIFICAR SYSCTL
# =============================================================================
echo "${C_INFO}[2/10] Verificando configuración del kernel (sysctl)...${C_RESET}"
SYSCTL_VALOR=$(sysctl -n net.ipv4.ip_unprivileged_port_start 2>/dev/null)
if [ -n "$SYSCTL_VALOR" ]; then
    if [ "$SYSCTL_VALOR" -le "$PUERTO" ]; then
        echo "  ${C_OK}✓ sysctl configurado correctamente ($SYSCTL_VALOR)${C_RESET}"
    else
        echo "  ${C_FAIL}✗ sysctl = $SYSCTL_VALOR (debería ser ≤ $PUERTO)${C_RESET}"
        echo "  ${C_WARN}→ Ejecutar: sysctl -w net.ipv4.ip_unprivileged_port_start=$PUERTO${C_RESET}"
        PROBLEMAS=$((PROBLEMAS + 1))
    fi
else
    echo "  ${C_FAIL}✗ sysctl no configurado${C_RESET}"
    PROBLEMAS=$((PROBLEMAS + 1))
fi

# Verificar persistencia
if grep -q "ip_unprivileged_port_start" /etc/sysctl.conf 2>/dev/null; then
    echo "  ${C_OK}✓ sysctl persistente en /etc/sysctl.conf${C_RESET}"
else
    echo "  ${C_WARN}⚠ sysctl NO persistente (se perderá al reiniciar)${C_RESET}"
fi
echo ""

# =============================================================================
# 3. VERIFICAR USUARIO TOMCAT
# =============================================================================
echo "${C_INFO}[3/10] Verificando usuario tomcat...${C_RESET}"
if id tomcat > /dev/null 2>&1; then
    echo "  ${C_OK}✓ Usuario 'tomcat' existe${C_RESET}"
else
    echo "  ${C_FAIL}✗ Usuario 'tomcat' NO existe${C_RESET}"
    PROBLEMAS=$((PROBLEMAS + 1))
fi
echo ""

# =============================================================================
# 4. VERIFICAR DIRECTORIO DE TOMCAT
# =============================================================================
echo "${C_INFO}[4/10] Verificando instalación de Tomcat...${C_RESET}"
if [ -d "/opt/tomcat" ]; then
    echo "  ${C_OK}✓ Directorio /opt/tomcat existe${C_RESET}"
    
    # Verificar binarios
    if [ -f "/opt/tomcat/bin/catalina.sh" ]; then
        echo "  ${C_OK}✓ catalina.sh encontrado${C_RESET}"
    else
        echo "  ${C_FAIL}✗ catalina.sh NO encontrado${C_RESET}"
        PROBLEMAS=$((PROBLEMAS + 1))
    fi
    
    # Verificar permisos
    OWNER=$(stat -c '%U' /opt/tomcat 2>/dev/null)
    if [ "$OWNER" = "tomcat" ]; then
        echo "  ${C_OK}✓ Permisos correctos (propietario: tomcat)${C_RESET}"
    else
        echo "  ${C_WARN}⚠ Propietario incorrecto: $OWNER (debería ser tomcat)${C_RESET}"
    fi
else
    echo "  ${C_FAIL}✗ Directorio /opt/tomcat NO existe${C_RESET}"
    echo "  ${C_WARN}→ Tomcat no está instalado${C_RESET}"
    PROBLEMAS=$((PROBLEMAS + 1))
fi
echo ""

# =============================================================================
# 5. VERIFICAR CONFIGURACIÓN DE PUERTO
# =============================================================================
echo "${C_INFO}[5/10] Verificando configuración del puerto...${C_RESET}"
if [ -f "/opt/tomcat/conf/server.xml" ]; then
    PUERTO_CONFIG=$(grep 'Connector.*port=' /opt/tomcat/conf/server.xml | grep -oE 'port="[0-9]+"' | head -1 | grep -oE '[0-9]+')
    if [ "$PUERTO_CONFIG" = "$PUERTO" ]; then
        echo "  ${C_OK}✓ Puerto configurado en server.xml: $PUERTO${C_RESET}"
    else
        echo "  ${C_FAIL}✗ Puerto en server.xml: $PUERTO_CONFIG (debería ser $PUERTO)${C_RESET}"
        PROBLEMAS=$((PROBLEMAS + 1))
    fi
else
    echo "  ${C_FAIL}✗ server.xml NO encontrado${C_RESET}"
    PROBLEMAS=$((PROBLEMAS + 1))
fi

if [ -f "/opt/tomcat/conf/tomcat_port" ]; then
    PUERTO_FILE=$(cat /opt/tomcat/conf/tomcat_port)
    if [ "$PUERTO_FILE" = "$PUERTO" ]; then
        echo "  ${C_OK}✓ Puerto en tomcat_port: $PUERTO${C_RESET}"
    else
        echo "  ${C_WARN}⚠ Puerto en tomcat_port: $PUERTO_FILE${C_RESET}"
    fi
fi
echo ""

# =============================================================================
# 6. VERIFICAR SERVICIO INIT
# =============================================================================
echo "${C_INFO}[6/10] Verificando servicio init...${C_RESET}"
if [ -f "/etc/init.d/tomcat" ]; then
    echo "  ${C_OK}✓ Script de servicio existe${C_RESET}"
    
    if [ -x "/etc/init.d/tomcat" ]; then
        echo "  ${C_OK}✓ Script tiene permisos de ejecución${C_RESET}"
    else
        echo "  ${C_FAIL}✗ Script NO ejecutable${C_RESET}"
        PROBLEMAS=$((PROBLEMAS + 1))
    fi
    
    # Verificar runlevel
    if rc-update show default | grep -q tomcat; then
        echo "  ${C_OK}✓ Tomcat en runlevel default${C_RESET}"
    else
        echo "  ${C_WARN}⚠ Tomcat NO en runlevel default${C_RESET}"
    fi
else
    echo "  ${C_FAIL}✗ Script de servicio NO existe${C_RESET}"
    PROBLEMAS=$((PROBLEMAS + 1))
fi
echo ""

# =============================================================================
# 7. VERIFICAR ESTADO DEL SERVICIO
# =============================================================================
echo "${C_INFO}[7/10] Verificando estado del servicio...${C_RESET}"
if rc-service tomcat status > /dev/null 2>&1; then
    echo "  ${C_OK}✓ Servicio Tomcat CORRIENDO${C_RESET}"
else
    echo "  ${C_FAIL}✗ Servicio Tomcat DETENIDO${C_RESET}"
    echo "  ${C_WARN}→ Ejecutar: rc-service tomcat start${C_RESET}"
    PROBLEMAS=$((PROBLEMAS + 1))
fi
echo ""

# =============================================================================
# 8. VERIFICAR PROCESOS JAVA
# =============================================================================
echo "${C_INFO}[8/10] Verificando procesos Java...${C_RESET}"
if pgrep -f "catalina" > /dev/null 2>&1; then
    PID=$(pgrep -f "catalina" | head -1)
    PROC_USER=$(ps -o user= -p "$PID" 2>/dev/null)
    echo "  ${C_OK}✓ Proceso Tomcat corriendo (PID: $PID, Usuario: $PROC_USER)${C_RESET}"
    
    if [ "$PROC_USER" != "tomcat" ]; then
        echo "  ${C_WARN}⚠ Proceso NO corre como usuario 'tomcat'${C_RESET}"
    fi
else
    echo "  ${C_FAIL}✗ NO hay procesos Tomcat corriendo${C_RESET}"
    PROBLEMAS=$((PROBLEMAS + 1))
fi
echo ""

# =============================================================================
# 9. VERIFICAR PUERTO ESCUCHANDO
# =============================================================================
echo "${C_INFO}[9/10] Verificando puerto $PUERTO...${C_RESET}"
if netstat -tuln 2>/dev/null | grep -q ":${PUERTO} " || ss -tuln 2>/dev/null | grep -q ":${PUERTO} "; then
    echo "  ${C_OK}✓ Puerto $PUERTO ESCUCHANDO${C_RESET}"
    
    # Mostrar en qué IP escucha
    LISTEN_IP=$(netstat -tuln 2>/dev/null | grep ":${PUERTO} " | awk '{print $4}' | head -1)
    if [ -n "$LISTEN_IP" ]; then
        echo "  ${C_INFO}  → Escuchando en: $LISTEN_IP${C_RESET}"
    fi
else
    echo "  ${C_FAIL}✗ Puerto $PUERTO NO ESCUCHANDO${C_RESET}"
    echo "  ${C_WARN}→ Revisar logs: tail -f /opt/tomcat/logs/catalina.out${C_RESET}"
    PROBLEMAS=$((PROBLEMAS + 1))
fi
echo ""

# =============================================================================
# 10. VERIFICAR RESPUESTA HTTP
# =============================================================================
echo "${C_INFO}[10/10] Verificando respuesta HTTP...${C_RESET}"
if command -v curl > /dev/null 2>&1; then
    RESPONSE=$(curl -I "http://localhost:$PUERTO" 2>/dev/null | head -1)
    if echo "$RESPONSE" | grep -qE "200|301|302"; then
        echo "  ${C_OK}✓ Servidor responde: $RESPONSE${C_RESET}"
    else
        echo "  ${C_FAIL}✗ Sin respuesta HTTP o error${C_RESET}"
        PROBLEMAS=$((PROBLEMAS + 1))
    fi
else
    echo "  ${C_WARN}⚠ curl no disponible, no se puede probar${C_RESET}"
fi
echo ""

# =============================================================================
# RESUMEN FINAL
# =============================================================================
echo "════════════════════════════════════════════════════════════════════"
echo ""
if [ $PROBLEMAS -eq 0 ]; then
    echo "${C_OK}✓✓✓ TODO CORRECTO - Tomcat funcionando perfectamente ✓✓✓${C_RESET}"
    echo ""
    echo "Accede desde: http://$(ip addr show | grep "inet " | grep -v "127.0.0.1" | awk '{print $2}' | cut -d/ -f1 | head -1):$PUERTO"
else
    echo "${C_FAIL}✗✗✗ SE ENCONTRARON $PROBLEMAS PROBLEMAS ✗✗✗${C_RESET}"
    echo ""
    echo "${C_WARN}SOLUCIONES RECOMENDADAS:${C_RESET}"
    echo ""
    echo "1. Si el script es VIEJO (usa setcap):"
    echo "   cp /mnt/compartida/http_functions.sh ."
    echo ""
    echo "2. Si sysctl no está configurado:"
    echo "   sysctl -w net.ipv4.ip_unprivileged_port_start=$PUERTO"
    echo "   echo 'net.ipv4.ip_unprivileged_port_start=$PUERTO' >> /etc/sysctl.conf"
    echo ""
    echo "3. Si Tomcat no está corriendo:"
    echo "   rc-service tomcat start"
    echo ""
    echo "4. Si el puerto no está configurado:"
    echo "   cd /opt/tomcat/conf"
    echo "   sed -i 's/port=\"[0-9]*\"/port=\"$PUERTO\"/' server.xml"
    echo "   echo '$PUERTO' > tomcat_port"
    echo "   rc-service tomcat restart"
    echo ""
    echo "5. Ver logs de errores:"
    echo "   tail -50 /opt/tomcat/logs/catalina.out"
fi
echo ""
echo "════════════════════════════════════════════════════════════════════"