#!/bin/sh
LAB_IFACE="eth1"
ZONEDIR="/var/bind"
NAMED_CONF="/etc/bind/named.conf"
NAMED_LOCAL="/etc/bind/named.conf.local"

dns_server_ip_eth1() {
  ip -4 addr show "$LAB_IFACE" 2>/dev/null | awk '/inet /{print $2}' | head -n1 | cut -d/ -f1
}

dns_verificar_ip_lab() {
  ip link show "$LAB_IFACE" >/dev/null 2>&1 || { echo "ERROR: No existe $LAB_IFACE"; return 1; }
  ip link set "$LAB_IFACE" up 2>/dev/null || true

  SIP="$(dns_server_ip_eth1)"
  [ -z "$SIP" ] && { echo "ERROR: eth1 sin IP. Ejecuta DHCP primero."; return 1; }

  echo "OK: eth1 tiene IP: $SIP"
  return 0
}

dns_instalar() {
  if command -v named >/dev/null 2>&1; then
    echo "OK: BIND ya instalado."
    return 0
  fi
  apk add --no-cache bind bind-tools bind-openrc || { echo "ERROR: apk add falló"; return 1; }
  echo "OK: BIND instalado."
}

dns_asegurar_base() {
  mkdir -p /etc/bind "$ZONEDIR"

  if [ ! -f "$NAMED_LOCAL" ]; then
    echo "// Zonas locales" > "$NAMED_LOCAL"
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

dns_zona_existe() {
  DOM="$1"
  grep -Eq "zone[[:space:]]+\"$DOM\"" "$NAMED_LOCAL" 2>/dev/null
}

dns_listar() {
  echo "DOMINIOS:"
  if [ ! -f "$NAMED_LOCAL" ]; then
    echo "(sin zonas)"
    return 0
  fi
  awk -F\" '/zone "/{print " - " $2}' "$NAMED_LOCAL" | sort -u
}

dns_alta() {
  dns_verificar_ip_lab || return 1
  dns_instalar || return 1
  dns_asegurar_base

  printf "Dominio (ej: vamonosalauaneg.com): "
  read DOM
  [ -z "$DOM" ] && { echo "ERROR: dominio vacío"; return 1; }

  IPDEST="$(validacion_ip "IP destino para @ y www: " "false")"
  ZFILE="$ZONEDIR/db.$DOM"

  if ! dns_zona_existe "$DOM"; then
    cat >> "$NAMED_LOCAL" <<EOF

zone "$DOM" {
  type master;
  file "$ZFILE";
  allow-update { none; };
};
EOF
  fi

  if [ ! -f "$ZFILE" ]; then
    SIP="$(dns_server_ip_eth1)"
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
  fi

  named-checkconf "$NAMED_CONF" || { echo "ERROR: named-checkconf falló"; return 1; }
  named-checkzone "$DOM" "$ZFILE" || { echo "ERROR: named-checkzone falló"; return 1; }

  rc-update add named default >/dev/null 2>&1 || true
  rc-service named restart || { echo "ERROR: no reinició named"; return 1; }

  echo "OK: $DOM -> $IPDEST"
}

dns_baja() {
  dns_asegurar_base
  dns_listar

  printf "Dominio a borrar: "
  read DOM
  [ -z "$DOM" ] && { echo "ERROR: dominio vacío"; return 1; }

  if ! dns_zona_existe "$DOM"; then
    echo "INFO: no existe."
    return 0
  fi

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

  echo "OK: dominio eliminado."
}

dns_estado() {
  dns_verificar_ip_lab || true
  rc-service named status 2>/dev/null || echo "(named no iniciado)"
  dns_listar
}