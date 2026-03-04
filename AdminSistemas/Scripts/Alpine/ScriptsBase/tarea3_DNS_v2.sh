#!/bin/sh
#PRUEBAAAAAAA
set -eu

# ================== COLORES ROSAS ==================
LIGHT_PINK='\033[1;95m'
ROSE='\033[38;5;213m'
HOT_PINK='\033[38;5;205m'
SOFT_PINK='\033[38;5;218m'
DARK_PINK='\033[38;5;169m'
WHITE='\033[1;37m'
NC='\033[0m'

# ================== CONFIG BÁSICA ==================
LAB_IFACE="eth1"                 # Tu red interna (DHCP/DNS)
ZONEDIR="/var/bind"              # Directorio de zonas en Alpine (bind)
NAMED_CONF="/etc/bind/named.conf"
NAMED_LOCAL="/etc/bind/named.conf.local"

log(){ echo -e "${ROSE}[INFO]${NC} $*"; }
warn(){ echo -e "${HOT_PINK}[WARN]${NC} $*"; }
die(){ echo -e "${DARK_PINK}[ERROR]${NC} $*"; exit 1; }

require_root(){ [ "$(id -u)" -eq 0 ] || die "Ejecuta como root."; }

# ============ Validación simple IPv4 ============
validacionIp() {
  while true; do
    printf "${SOFT_PINK}%s${NC}" "$1" >&2
    read -r ip || true
    if echo "$ip" | grep -Eq '^((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$'; then
      echo "$ip"; return 0
    fi
    echo -e "${HOT_PINK}Formato IPv4 inválido. Reintente.${NC}" >&2
  done
}

# ============ IP del servidor en eth1 (solo validar, NO configurar) ============
server_ip_eth1() {
  ip -4 addr show "$LAB_IFACE" 2>/dev/null | awk '/inet /{print $2}' | head -n1 | cut -d/ -f1 || true
}

verificar_ip_lab() {
  echo -e "${HOT_PINK}================== VALIDACIÓN DE LAB ==================${NC}"
  ip link show "$LAB_IFACE" >/dev/null 2>&1 || die "No existe $LAB_IFACE. Revisa VirtualBox adaptador 2."
  ip link set "$LAB_IFACE" up 2>/dev/null || true

  SIP="$(server_ip_eth1)"
  if [ -z "${SIP:-}" ]; then
    warn "eth1 NO tiene IP. Primero ejecuta tu script DHCP (Práctica 2) y asigna la IP del servidor en eth1."
    return 1
  fi

  echo -e "${ROSE}Servidor (eth1) tiene IP: ${WHITE}${SIP}${NC}"
  echo -e "${ROSE}Recuerda: en tu DHCP debes entregar DNS = ${WHITE}${SIP}${NC} (DNS1)."
  return 0
}

# ============ Instalación / Desinstalación BIND ============
verificar_instalacion() {
  echo -e "${LIGHT_PINK}Verificando instalación DNS (BIND)...${NC}"
  if command -v named >/dev/null 2>&1; then
    echo -e "${ROSE}BIND instalado.${NC}"
  else
    echo -e "${HOT_PINK}BIND NO instalado.${NC}"
  fi
}

instalar_dns() {
  echo -e "${HOT_PINK}================== INSTALAR DNS ==================${NC}"
  if command -v named >/dev/null 2>&1; then
    echo -e "${ROSE}BIND ya está instalado.${NC}"
    return 0
  fi
  apk add --no-cache bind bind-tools bind-openrc || die "Falló apk add. Verifica internet (eth0 NAT)."
  echo -e "${ROSE}Instalación exitosa.${NC}"
}

desinstalar_dns() {
  echo -e "${DARK_PINK}================== DESINSTALAR DNS ==================${NC}"
  if ! command -v named >/dev/null 2>&1; then
    echo -e "${HOT_PINK}BIND no está instalado.${NC}"
    return 0
  fi
  rc-service named stop 2>/dev/null || true
  rc-update del named default 2>/dev/null || true
  apk del bind bind-tools bind-openrc || die "Falló la desinstalación."
  echo -e "${ROSE}BIND desinstalado.${NC}"
}

# ============ Base de configuración BIND (simple) ============
asegurar_base_bind() {
  mkdir -p /etc/bind "$ZONEDIR"

  if [ ! -f "$NAMED_LOCAL" ]; then
    cat > "$NAMED_LOCAL" <<EOF
// Zonas locales - Practica 3 DNS (Alpine)
EOF
  fi

  if [ ! -f "$NAMED_CONF" ]; then
    cat > "$NAMED_CONF" <<EOF
options {
  directory "$ZONEDIR";
  listen-on { any; };
  listen-on-v6 { none; };
  allow-query { any; };
  recursion no;
  dnssec-validation no;
};
include "$NAMED_LOCAL";
EOF
  fi
}

zona_existe() {
  DOM="$1"
  grep -Eq "zone[[:space:]]+\"$DOM\"" "$NAMED_LOCAL" 2>/dev/null
}

# ============ Listar dominios ============
listar_dominios() {
  echo -e "${HOT_PINK}================== DOMINIOS (ZONAS) ==================${NC}"
  if [ ! -f "$NAMED_LOCAL" ]; then
    echo -e "${WHITE}(sin zonas)${NC}"
    return 0
  fi
  awk -F\" '/zone "/{print " - " $2}' "$NAMED_LOCAL" | sort -u || echo -e "${WHITE}(sin zonas)${NC}"
}

# ============ Alta dominio (crear zona + A para @ y www) ============
alta_dominio() {
  echo -e "${HOT_PINK}================== ALTA DE DOMINIO ==================${NC}"

  verificar_ip_lab || return 1
  instalar_dns
  asegurar_base_bind

  printf "${SOFT_PINK}Nombre del dominio (ej: pepsi.com): ${NC}"
  read -r DOM
  [ -n "${DOM:-}" ] || die "Dominio vacío."

  IPDEST="$(validacionIp "IP a la que apuntará ${DOM} (A para @ y www): ")"

  ZFILE="$ZONEDIR/db.$DOM"

  # Idempotencia: no duplicar zona
  if ! zona_existe "$DOM"; then
    cat >> "$NAMED_LOCAL" <<EOF

zone "$DOM" {
  type master;
  file "$ZFILE";
  allow-update { none; };
};
EOF
    log "Zona agregada en named.conf.local"
  else
    warn "La zona $DOM ya existe (no se duplica)."
  fi

  # Crear archivo de zona si no existe (no sobreescribe)
  if [ ! -f "$ZFILE" ]; then
    SIP="$(server_ip_eth1)"
    SERIAL="$(date +%Y%m%d)01"
    cat > "$ZFILE" <<EOF
\$TTL 3600
@ IN SOA ns1.$DOM. admin.$DOM. (
  $SERIAL 3600 900 1209600 3600
)
@   IN NS ns1.$DOM.
ns1 IN A  $SIP

@   IN A  $IPDEST
www IN A  $IPDEST
EOF
    log "Archivo de zona creado: $ZFILE"
  else
    warn "El archivo $ZFILE ya existe (no se sobreescribe)."
  fi

  # Validaciones mínimas
  named-checkconf "$NAMED_CONF" || die "named-checkconf falló."
  named-checkzone "$DOM" "$ZFILE" || die "named-checkzone falló."

  rc-update add named default >/dev/null 2>&1 || true
  rc-service named restart || die "No pude reiniciar el servicio named."

  echo -e "${ROSE}OK: ${WHITE}$DOM${NC} -> ${WHITE}$IPDEST${NC} (incluye www)"
}

# ============ Baja dominio ============
baja_dominio() {
  echo -e "${HOT_PINK}================== BAJA DE DOMINIO ==================${NC}"
  asegurar_base_bind
  listar_dominios

  printf "${SOFT_PINK}Dominio a borrar (ej: pepsi.com): ${NC}"
  read -r DOM
  [ -n "${DOM:-}" ] || die "Dominio vacío."

  if ! zona_existe "$DOM"; then
    warn "El dominio $DOM no existe."
    return 0
  fi

  # Eliminar bloque zone { ... } sin romper el archivo
  TMP="/tmp/named.local.$$"
  awk -v dom="$DOM" '
    BEGIN{skip=0}
    $0 ~ "zone \""dom"\"" {skip=1; next}
    skip==1 && $0 ~ "};" {skip=0; next}
    skip==0 {print}
  ' "$NAMED_LOCAL" > "$TMP"
  mv "$TMP" "$NAMED_LOCAL"

  rm -f "$ZONEDIR/db.$DOM" 2>/dev/null || true
  rc-service named restart 2>/dev/null || true

  echo -e "${ROSE}Dominio eliminado: ${WHITE}$DOM${NC}"
}

# ============ Estado ============
estado_dns() {
  echo -e "${HOT_PINK}================== ESTADO DNS ==================${NC}"
  verificar_ip_lab || true
  rc-service named status 2>/dev/null || echo -e "${WHITE}(named no iniciado)${NC}"
  listar_dominios
}

# ============ Menú ============
menu() {
  echo -e "${HOT_PINK}====================================================${NC}"
  echo -e "${LIGHT_PINK}                SERVIDOR DNS - ALPINE               ${NC}"
  echo -e "${HOT_PINK}====================================================${NC}"
  echo -e "${LIGHT_PINK}[1] Verificar IP del lab (eth1)${NC}"
  echo -e "${LIGHT_PINK}[2] Verificar instalación DNS${NC}"
  echo -e "${LIGHT_PINK}[3] Instalar DNS (BIND)${NC}"
  echo -e "${LIGHT_PINK}[4] Desinstalar DNS (académico)${NC}"
  echo -e "${LIGHT_PINK}[5] Listar dominios${NC}"
  echo -e "${LIGHT_PINK}[6] Alta de dominio (zona + @ + www)${NC}"
  echo -e "${LIGHT_PINK}[7] Baja de dominio${NC}"
  echo -e "${LIGHT_PINK}[8] Estado DNS${NC}"
  echo -e "${LIGHT_PINK}[9] Salir${NC}"
}

# ============ Loop ============
require_root
while true; do
  menu
  printf "${SOFT_PINK}Ingrese una opción: ${NC}"
  read -r op

  case "$op" in
    1) verificar_ip_lab ;;
    2) verificar_instalacion ;;
    3) instalar_dns ;;
    4) desinstalar_dns ;;
    5) listar_dominios ;;
    6) alta_dominio ;;
    7) baja_dominio ;;
    8) estado_dns ;;
    9) exit 0 ;;
    *) echo -e "${HOT_PINK}Opción inválida.${NC}" ;;
  esac

  printf "\n${LIGHT_PINK}¿Desea volver al menú? (si/no): ${NC}"
  read -r ch
  [ "$ch" = "si" ] || break
done