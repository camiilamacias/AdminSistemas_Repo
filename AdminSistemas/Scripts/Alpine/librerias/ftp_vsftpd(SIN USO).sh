#!/bin/sh
# FTP (vsftpd) - Alpine (OpenRC) | Compatible con Alpine 3.x / BusyBox ash

# Usa tus colores (vienen de lib/colors.sh)
# Usa pause() y require_root() (vienen de lib/common.sh)

FTP_ROOT="/ftp"
FTP_GENERAL="$FTP_ROOT/general"
FTP_GROUPS="$FTP_ROOT/grupos"
FTP_USERS="$FTP_ROOT/usuarios"

FTPWRITE_GROUP="ftpwrite"

# Rango PASV que ya configuraste en Port Forwarding
PASV_MIN="50000"
PASV_MAX="50010"
PASV_ADDR="127.0.0.1"  # como te conectas desde el host con 127.0.0.1

ftp_verificar() {
  echo -e "${HOT_PINK}================== VERIFICAR FTP (vsftpd) ==================${NC}"

  if apk info -e vsftpd >/dev/null 2>&1; then
    echo -e "${ROSE}[OK] vsftpd instalado${NC}"
  else
    echo -e "${DARK_PINK}[WARN] vsftpd NO instalado${NC}"
  fi

  rc-service vsftpd status 2>/dev/null || echo -e "${DARK_PINK}[WARN] vsftpd no iniciado${NC}"

  if command -v netstat >/dev/null 2>&1; then
    netstat -lntp 2>/dev/null | grep ":21" >/dev/null 2>&1 \
      && echo -e "${ROSE}[OK] Puerto 21 LISTEN${NC}" \
      || echo -e "${DARK_PINK}[WARN] No veo LISTEN en 21${NC}"
  else
    echo -e "${DARK_PINK}[INFO] netstat no existe (opcional: apk add net-tools)${NC}"
  fi

  [ -f /etc/vsftpd/vsftpd.conf ] \
    && echo -e "${ROSE}[OK] /etc/vsftpd/vsftpd.conf existe${NC}" \
    || echo -e "${DARK_PINK}[WARN] Falta /etc/vsftpd/vsftpd.conf${NC}"

  echo -e "${LIGHT_PINK}Rutas esperadas:${NC} $FTP_ROOT (general/grupos/usuarios)"
  echo -e "${LIGHT_PINK}PASV esperado:${NC} $PASV_MIN-$PASV_MAX (addr $PASV_ADDR)"
}

ftp_preparar_idempotente() {
  echo -e "${HOT_PINK}================== PREPARAR FTP (IDEMPOTENTE) ==================${NC}"

  # 1) Instalar vsftpd si falta + arrancar en boot
  apk add --no-cache vsftpd >/dev/null 2>&1 || true
  rc-update add vsftpd default >/dev/null 2>&1 || true

  # 2) Grupos requeridos
  addgroup -S reprobados 2>/dev/null || true
  addgroup -S recursadores 2>/dev/null || true
  addgroup -S "$FTPWRITE_GROUP" 2>/dev/null || true

  # 3) Estructura base
  mkdir -p "$FTP_GENERAL"
  mkdir -p "$FTP_GROUPS/reprobados" "$FTP_GROUPS/recursadores"
  mkdir -p "$FTP_USERS"

  # 4) Permisos base
  # /general: lectura para todos + escritura para autenticados (grupo ftpwrite)
  chown root:"$FTPWRITE_GROUP" "$FTP_GENERAL"
  chmod 2775 "$FTP_GENERAL"

  # carpetas grupo: escritura para el grupo + herencia de grupo (setgid)
  chown -R root:reprobados "$FTP_GROUPS/reprobados"
  chmod 2775 "$FTP_GROUPS/reprobados"

  chown -R root:recursadores "$FTP_GROUPS/recursadores"
  chmod 2775 "$FTP_GROUPS/recursadores"

  # 5) Escribir config vsftpd reproducible (respeta lo que ya hiciste, pero lo normaliza)
  cp /etc/vsftpd/vsftpd.conf /etc/vsftpd/vsftpd.conf.bak 2>/dev/null || true

  cat > /etc/vsftpd/vsftpd.conf <<CONF
listen=YES
listen_ipv6=NO

local_enable=YES
write_enable=YES

chroot_local_user=YES
allow_writeable_chroot=YES

# Cada usuario entra a /ftp/usuarios/\$USER
user_sub_token=\$USER
local_root=/ftp/usuarios/\$USER

# PASV (NAT + Port Forwarding)
pasv_enable=YES
pasv_min_port=$PASV_MIN
pasv_max_port=$PASV_MAX
pasv_address=$PASV_ADDR
pasv_addr_resolve=NO

# Anónimo: SOLO lectura a /ftp/general
anonymous_enable=YES
anon_root=/ftp/general
anon_upload_enable=NO
anon_mkdir_write_enable=NO
anon_other_write_enable=NO

xferlog_enable=YES
log_ftp_protocol=YES
ssl_enable=NO
CONF

  # 6) Reiniciar servicio
  rc-service vsftpd restart >/dev/null 2>&1 || rc-service vsftpd start >/dev/null 2>&1

  echo -e "${ROSE}[OK] FTP listo (vsftpd + /ftp + permisos + config)${NC}"
}

ftp_crear_usuarios() {
  echo -e "${HOT_PINK}================== CREAR USUARIOS (MASIVO) ==================${NC}"
  printf "${SOFT_PINK}¿Cuántos usuarios crear (n)?: ${NC}"
  read n

  i=1
  while [ "$i" -le "${n:-0}" ]; do
    echo -e "${LIGHT_PINK}--- Usuario $i de $n ---${NC}"

    printf "${SOFT_PINK}Usuario: ${NC}"
    read user

    printf "${SOFT_PINK}Contraseña para $user: ${NC}"
    stty -echo
    read pass
    stty echo
    echo ""

    printf "${SOFT_PINK}Grupo (reprobados/recursadores): ${NC}"
    read grupo

    if [ "$grupo" != "reprobados" ] && [ "$grupo" != "recursadores" ]; then
      echo -e "${DARK_PINK}[ERROR] Grupo inválido.${NC}"
      continue
    fi

    # Crear usuario si no existe
    adduser -D "$user" 2>/dev/null || true
    echo "$user:$pass" | chpasswd

    # Asegurar pertenencia: grupo + ftpwrite
    addgroup "$user" "$grupo" 2>/dev/null || true
    addgroup "$user" "$FTPWRITE_GROUP" 2>/dev/null || true

    # Construir "raíz" que verá en FileZilla:
    # /general  /<grupo>  /<usuario>
    mkdir -p "$FTP_USERS/$user/$user"
    ln -sfn "$FTP_GENERAL" "$FTP_USERS/$user/general"
    ln -sfn "$FTP_GROUPS/$grupo" "$FTP_USERS/$user/$grupo"

    # Permisos carpeta personal
    chown -R "$user:$grupo" "$FTP_USERS/$user/$user"
    chmod 775 "$FTP_USERS/$user/$user"
    chmod 755 "$FTP_USERS/$user"

    echo -e "${ROSE}[OK] $user creado en $grupo${NC}"
    i=$((i+1))
  done
}

ftp_cambiar_grupo_usuario() {
  echo -e "${HOT_PINK}================== CAMBIAR GRUPO DE USUARIO ==================${NC}"
  printf "${SOFT_PINK}Usuario a cambiar: ${NC}"
  read user

  if id "$user" 2>/dev/null | grep -q "(reprobados)"; then
    old="reprobados"; new="recursadores"
  elif id "$user" 2>/dev/null | grep -q "(recursadores)"; then
    old="recursadores"; new="reprobados"
  else
    echo -e "${DARK_PINK}[ERROR] $user no está en reprobados/recursadores.${NC}"
    return 1
  fi

  delgroup "$user" "$old" 2>/dev/null || true
  addgroup "$user" "$new" 2>/dev/null || true

  # Actualiza carpeta visible del grupo (symlink)
  rm -f "$FTP_USERS/$user/$old"
  ln -sfn "$FTP_GROUPS/$new" "$FTP_USERS/$user/$new"

  echo -e "${ROSE}[OK] $user: $old -> $new${NC}"
}

ftp_menu() {
  while true; do
    echo -e "${HOT_PINK}====================================================${NC}"
    echo -e "${LIGHT_PINK}                 FTP (vsftpd) - ALPINE              ${NC}"
    echo -e "${HOT_PINK}====================================================${NC}"
    echo -e "${LIGHT_PINK}[1] Verificar FTP${NC}"
    echo -e "${LIGHT_PINK}[2] Preparar/Instalar (idempotente)${NC}"
    echo -e "${LIGHT_PINK}[3] Crear usuarios (n)${NC}"
    echo -e "${LIGHT_PINK}[4] Cambiar grupo de usuario${NC}"
    echo -e "${LIGHT_PINK}[0] Volver${NC}"
    printf "${SOFT_PINK}Opción: ${NC}"
    read op

    case "$op" in
      1) ftp_verificar ;;
      2) ftp_preparar_idempotente ;;
      3) ftp_crear_usuarios ;;
      4) ftp_cambiar_grupo_usuario ;;
      0) return 0 ;;
      *) echo -e "${DARK_PINK}Opción inválida.${NC}" ;;
    esac

    pause
  done
}
