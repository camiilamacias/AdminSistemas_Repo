#!/bin/sh

diag_mostrar() {
  echo "Equipo: $(hostname)"
  echo "IPs:"
  ip addr show | grep inet | grep -v 127
  echo "Espacio en disco (/):"
  df -h /
}