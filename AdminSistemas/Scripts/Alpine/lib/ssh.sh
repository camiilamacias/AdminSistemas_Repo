#!/bin/sh

ssh_verificar() {
  echo "=== SSH (OpenSSH Server) ==="
  if rc-service sshd status >/dev/null 2>&1; then
    echo "OK: sshd activo"
  else
    echo "NO: sshd inactivo/no instalado"
  fi

  if rc-update show default 2>/dev/null | grep -q "sshd"; then
    echo "OK: sshd en arranque (boot)"
  else
    echo "NO: sshd NO en arranque"
  fi
}

ssh_instalar() {
  echo "Instalando OpenSSH Server..."
  apk add --no-cache openssh openssh-server openssh-server-common >/dev/null 2>&1 || true

  if [ ! -f /etc/ssh/ssh_host_rsa_key ]; then
    ssh-keygen -A
  fi

  rc-update add sshd default >/dev/null 2>&1 || true
  rc-service sshd restart || rc-service sshd start

  echo "OK: SSH listo."
  echo "TIP: prueba desde tu host con PuTTY a la IP del adaptador puente (si lo usas) o la IP alcanzable."
}

ssh_menu() {
  echo "1) Verificar SSH"
  echo "2) Instalar/configurar SSH"
  echo "0) Volver"
  printf "Opción: "
  read op
  case "$op" in
    1) ssh_verificar ;;
    2) ssh_instalar ;;
    0) return ;;
    *) echo "Opción inválida" ;;
  esac
}