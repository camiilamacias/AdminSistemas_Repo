dhcp_configurar() {
  echo "=== CONFIGURACION DHCP KEA ==="

  printf "Ingrese un nombre para el scope: "
  read nombreScope

  rangoI=$(validacion_ip "IP Inicial del rango (IP fija para servidor eth1): " "false")
  prefijoI=$(echo "$rangoI" | cut -d. -f1-3)

  echo "Configurando IP fija en eth1: $rangoI/24"
  ip addr add "$rangoI/24" dev eth1 2>/dev/null || true
  ip link set eth1 up 2>/dev/null || true

  # DNS PRIMARIO = IP DEL SERVIDOR (eth1)
  dns_primario="$rangoI"

  ultimo=$(echo "$rangoI" | cut -d. -f4)
  rangoDhcpInicio="$prefijoI.$((ultimo + 1))"
  echo "Rango clientes inicia en: $rangoDhcpInicio"

  while true; do
    rangoF=$(validacion_ip "IP final del rango: " "false")
    prefijoF=$(echo "$rangoF" | cut -d. -f1-3)
    ultimoF=$(echo "$rangoF" | cut -d. -f4)

    if [ "$ultimo" -ge "$ultimoF" ]; then
      echo "ERROR: inicial no puede ser >= final."
    elif [ "$prefijoI" != "$prefijoF" ]; then
      echo "ERROR: deben estar en la misma subred ($prefijoI.x)."
    else
      redId="$prefijoI.0"
      break
    fi
  done

  # DNS secundario opcional
  dns_secundario=$(validacion_ip "DNS secundario (opcional, ENTER para omitir): " "true")

  # Kea acepta lista separada por comas en domain-name-servers
  dns_data="$dns_primario"
  if [ -n "$dns_secundario" ]; then
    dns_data="$dns_primario, $dns_secundario"
  fi

  printf "Gateway (opcional, ENTER para omitir): "
  read gateway

  printf "Lease (segundos, ej 28800): "
  read tiempolease
  [ -z "$tiempolease" ] && tiempolease="28800"

  OPT_GW=""
  if [ -n "$gateway" ]; then
    OPT_GW=", { \"name\": \"routers\", \"data\": \"$gateway\" }"
  fi

  cat > /etc/kea/kea-dhcp4.conf <<EOF
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
        { "name": "domain-name-servers", "data": "$dns_data" }$OPT_GW
      ]
    }
  ]
}
}
EOF

  rc-service kea-dhcp4 restart
  rc-update add kea-dhcp4 default

  echo "OK: DHCP configurado. Scope: $nombreScope"
  echo "DNS primario entregado por DHCP: $dns_primario"
  [ -n "$dns_secundario" ] && echo "DNS secundario entregado por DHCP: $dns_secundario"
}