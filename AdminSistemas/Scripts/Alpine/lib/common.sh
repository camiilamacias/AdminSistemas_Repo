#!/bin/sh

require_root() {
  if [ "$(id -u)" -ne 0 ]; then
    echo "ERROR: Ejecuta como root."
    return 1
  fi
  return 0
}

pause() {
  printf "Presiona ENTER para continuar..."
  read _x
}

# Validación IPv4 (POSIX sh)
validacion_ip() {
  mensaje="$1"
  opcional="$2" # "true" o "false"

  while true; do
    printf "%s" "$mensaje" >&2
    read ip

    if [ "$opcional" = "true" ] && [ -z "$ip" ]; then
      echo ""
      return 0
    fi

    echo "$ip" | grep -Eq '^((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$' || {
      echo "Formato IPv4 inválido. Reintente." >&2
      continue
    }

    # No ceros a la izquierda tipo 01
    echo "$ip" | grep -q '\.0[0-9]' && {
      echo "Error: no se permiten ceros a la izquierda." >&2
      continue
    }

    primerOcteto=$(echo "$ip" | cut -d. -f1)

    if [ "$ip" = "0.0.0.0" ]; then
      echo "Error: 0.0.0.0 reservada." >&2
    elif [ "$ip" = "255.255.255.255" ]; then
      echo "Error: Global Broadcast." >&2
    elif [ "$primerOcteto" -eq 127 ]; then
      echo "Error: Loopback." >&2
    elif [ "$primerOcteto" -ge 224 ]; then
      echo "Error: Multicast/Reservada." >&2
    else
      echo "$ip"
      return 0
    fi
  done
}