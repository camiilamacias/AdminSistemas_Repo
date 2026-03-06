#!/bin/sh
set -eu

BASE_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

# Cargar librerias
. "$BASE_DIR/lib/colors.sh"
. "$BASE_DIR/lib/common.sh"
. "$BASE_DIR/lib/diagnostico.sh"
. "$BASE_DIR/lib/dhcp_kea.sh"
. "$BASE_DIR/lib/dns_bind.sh"
. "$BASE_DIR/lib/ssh.sh"
. "$BASE_DIR/lib/ftp_vsftpd.sh"

require_root || exit 1

while true; do
  echo -e "${HOT_PINK}====================================================${NC}"
  echo -e "${LIGHT_PINK}          MAIN - ADMIN SISTEMAS (ALPINE)            ${NC}"
  echo -e "${HOT_PINK}====================================================${NC}"
  echo -e "${LIGHT_PINK}[1] Diagnóstico${NC}"
  echo -e "${LIGHT_PINK}[2] DHCP (Kea) - Verificar${NC}"
  echo -e "${LIGHT_PINK}[3] DHCP (Kea) - Instalar${NC}"
  echo -e "${LIGHT_PINK}[4] DHCP (Kea) - Configurar${NC}"
  echo -e "${LIGHT_PINK}[5] DHCP (Kea) - Monitoreo${NC}"
  echo -e "${LIGHT_PINK}[6] DNS (BIND) - Estado${NC}"
  echo -e "${LIGHT_PINK}[7] DNS (BIND) - Alta dominio${NC}"
  echo -e "${LIGHT_PINK}[8] DNS (BIND) - Baja dominio${NC}"
  echo -e "${LIGHT_PINK}[9] SSH - Gestion${NC}"
  echo -e "${LIGHT_PINK}[10] FTP (vsftpd)${NC}"
  echo -e "${LIGHT_PINK}[0] Salir${NC}"
  printf "${SOFT_PINK}Opción: ${NC}"
  read op

  case "$op" in
    1) diag_mostrar ;;
    2) dhcp_verificar ;;
    3) dhcp_instalar ;;
    4) dhcp_configurar ;;
    5) dhcp_monitoreo ;;
    6) dns_estado ;;
    7) dns_alta ;;
    8) dns_baja ;;
    9) ssh_menu ;;
    10) ftp_menu ;;
    0) exit 0 ;;
    *) echo -e "${HOT_PINK}Opción inválida.${NC}" ;;
  esac

  pause
done
