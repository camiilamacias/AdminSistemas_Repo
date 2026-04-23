#Requires -RunAsAdministrator
# ============================================================
# join_domain_win.ps1
# Prepara la VM clonada de Windows y la une al dominio
# Practica 8 - Administracion de Sistemas
#
# PROBLEMA DEL CLON: Al clonar la VM del servidor, el cliente
# hereda el mismo SID (Security Identifier). Dos maquinas con
# el mismo SID en el mismo dominio causan conflictos de identidad.
# Este script resuelve eso con Sysprep antes de unirse al dominio.
#
# Uso: powershell -ExecutionPolicy RemoteSigned -File .\join_domain_win.ps1
# ============================================================

Set-StrictMode -Version Latest

# -----------------------------------------------
# VARIABLES GLOBALES
# -----------------------------------------------
$DOMINIO    = "empresa.local"
$DC_IP      = "220.1.1.234"       # IP del servidor Windows DC
$ADMIN_AD   = "Administrador"     # Usuario administrador del dominio


# -----------------------------------------------
# MENSAJES (paleta rosita)
# -----------------------------------------------
function Write-Ok    { param($msg) Write-Host "  [+] $msg" -ForegroundColor Magenta    }
function Write-Info  { param($msg) Write-Host "  [i] $msg" -ForegroundColor DarkMagenta }
function Write-Warn  { param($msg) Write-Host "  [!] $msg" -ForegroundColor Yellow      }
function Write-Err   { param($msg) Write-Host "  [x] $msg" -ForegroundColor Red         }

function Write-Banner {
    param([string]$titulo)
    Write-Host ""
    Write-Host "  ================================================" -ForegroundColor Magenta
    Write-Host "    $titulo" -ForegroundColor White
    Write-Host "  ================================================" -ForegroundColor Magenta
    Write-Host ""
}

function Write-Linea { Write-Host "  ------------------------------------------------" -ForegroundColor Magenta }


# -----------------------------------------------
# 1. DIAGNOSTICO DEL CLON
#    Muestra informacion clave antes de proceder:
#    SID actual, nombre del equipo, dominio/workgroup.
#    Util para confirmar que la VM es un clon.
# -----------------------------------------------
function diagnosticoClon {
    Write-Banner "DIAGNOSTICO DE LA VM CLONADA"

    $sid    = (Get-WmiObject Win32_UserAccount -Filter "Name='Administrator'" `
               -ErrorAction SilentlyContinue).SID
    $cs     = Get-WmiObject Win32_ComputerSystem
    $nombre = $env:COMPUTERNAME

    Write-Info "Nombre actual del equipo : $nombre"
    Write-Info "Dominio / Workgroup       : $($cs.Domain)"
    Write-Info "SID del Administrador     : $sid"
    Write-Linea
    Write-Warn "Si el SID termina en -500 y coincide con el servidor,"
    Write-Warn "es necesario ejecutar Sysprep (opcion 2) antes de unirse al dominio."
    Write-Linea

    # Verificar si ya esta en el dominio
    if ($cs.PartOfDomain) {
        Write-Ok "Este equipo YA pertenece al dominio: $($cs.Domain)"
    } else {
        Write-Info "Este equipo esta en WORKGROUP. Aun no esta en el dominio."
    }
}


# -----------------------------------------------
# 2. SYSPREP - REGENERAR SID
#    Sysprep /generalize borra el SID actual y
#    genera uno nuevo al reiniciar.
#    El equipo se reiniciara automaticamente.
#
#    IMPORTANTE: Despues del reinicio vuelve a
#    ejecutar este script y usa la opcion 3
#    para unirte al dominio.
# -----------------------------------------------
function ejecutarSysprep {
    Write-Banner "SYSPREP - REGENERAR SID DEL CLON"

    Write-Warn "Sysprep borrara el SID duplicado del servidor y generara uno nuevo."
    Write-Warn "El equipo se REINICIARA automaticamente al terminar."
    Write-Warn "Despues del reinicio, ejecuta este script de nuevo y usa la opcion 3."
    Write-Host ""

    $confirm = Read-Host "  Escribir 'SI' para continuar con Sysprep"
    if ($confirm -ne "SI") {
        Write-Info "Sysprep cancelado."
        return
    }

    # Cambiar nombre del equipo ANTES del sysprep
    # El nombre del servidor y del cliente no pueden ser el mismo en el dominio
    $nuevoNombre = Read-Host "  Nombre para este equipo cliente (ej: ClienteWin1)"
    if ([string]::IsNullOrWhiteSpace($nuevoNombre)) {
        $nuevoNombre = "ClienteWin-$(Get-Random -Maximum 999)"
        Write-Info "Nombre generado automaticamente: $nuevoNombre"
    }

    Write-Info "Cambiando nombre del equipo a '$nuevoNombre'..."
    Rename-Computer -NewName $nuevoNombre -Force -ErrorAction SilentlyContinue
    Write-Ok "Nombre cambiado a: $nuevoNombre"

    Write-Info "Iniciando Sysprep /generalize /oobe /shutdown..."
    Write-Warn "El equipo se apagara. Encienalo de nuevo para continuar."

    $sysprepPath = "$env:SystemRoot\System32\Sysprep\sysprep.exe"
    if (-not (Test-Path $sysprepPath)) {
        Write-Err "No se encontro sysprep.exe en $sysprepPath"
        return
    }

    # /generalize: elimina SID especifico del equipo
    # /oobe:       muestra pantalla de configuracion inicial al reiniciar
    # /shutdown:   apaga el equipo al terminar (no reinicia directamente)
    Start-Process -FilePath $sysprepPath -ArgumentList "/generalize /oobe /shutdown" -Wait
}


# -----------------------------------------------
# 3. CAMBIAR NOMBRE DEL EQUIPO
#    Si el clon ya tiene un nombre diferente al
#    servidor pero quieres cambiarlo antes de unirte.
#    Requiere reinicio.
# -----------------------------------------------
function cambiarNombreEquipo {
    Write-Banner "CAMBIAR NOMBRE DEL EQUIPO"

    Write-Info "Nombre actual: $env:COMPUTERNAME"
    $nuevoNombre = Read-Host "  Nuevo nombre para este cliente (ej: ClienteWin1)"

    if ([string]::IsNullOrWhiteSpace($nuevoNombre)) {
        Write-Warn "Nombre no puede estar vacio."
        return
    }

    try {
        Rename-Computer -NewName $nuevoNombre -Force -ErrorAction Stop
        Write-Ok "Nombre cambiado a '$nuevoNombre'. Reinicia para aplicar."
        Write-Warn "Ejecuta: Restart-Computer"
    } catch {
        Write-Err "Error al cambiar nombre: $($_.Exception.Message)"
    }
}


# -----------------------------------------------
# 4. CONFIGURAR RED - APUNTAR AL DC
#    El cliente necesita al DC como servidor DNS
#    para resolver el nombre del dominio.
# -----------------------------------------------
function configurarRed {
    Write-Banner "CONFIGURAR RED Y DNS"

    # Obtener el adaptador de red activo
    $adapter = Get-NetAdapter | Where-Object { $_.Status -eq "Up" } | Select-Object -First 1

    if (-not $adapter) {
        Write-Err "No se encontro adaptador de red activo."
        return
    }

    Write-Info "Adaptador activo: $($adapter.Name)"
    Write-Info "Configurando DNS primario: $DC_IP"

    Set-DnsClientServerAddress -InterfaceIndex $adapter.InterfaceIndex `
        -ServerAddresses $DC_IP

    Write-Ok "DNS configurado: $DC_IP apunta al servidor DC."

    # Verificar conectividad con el DC
    Write-Info "Probando conectividad con el DC ($DC_IP)..."
    if (Test-Connection -ComputerName $DC_IP -Count 2 -Quiet) {
        Write-Ok "DC alcanzable en $DC_IP"
    } else {
        Write-Warn "Sin respuesta del DC. Verifica que las VMs esten en la misma red."
    }

    # Probar resolucion DNS del dominio
    Write-Info "Probando resolucion DNS de '$DOMINIO'..."
    try {
        $resolved = Resolve-DnsName -Name $DOMINIO -Server $DC_IP -ErrorAction Stop
        Write-Ok "DNS OK: $DOMINIO resuelto -> $($resolved[0].IPAddress)"
    } catch {
        Write-Warn "No se pudo resolver '$DOMINIO'. Verifica que el servidor DNS este activo."
    }
}


# -----------------------------------------------
# 5. UNIRSE AL DOMINIO
#    Add-Computer une este cliente al dominio.
#    Solicita la contrasena del administrador AD.
#    Requiere reinicio para aplicar.
# -----------------------------------------------
function unirseAlDominio {
    Write-Banner "UNIRSE AL DOMINIO"

    $cs = Get-WmiObject Win32_ComputerSystem
    if ($cs.PartOfDomain) {
        Write-Ok "Este equipo ya esta en el dominio: $($cs.Domain)"
        return
    }

    Write-Info "Uniendo '$env:COMPUTERNAME' al dominio '$DOMINIO'..."
    Write-Info "Se solicitara la contrasena del usuario: $ADMIN_AD"

    $pass = Read-Host "  Contrasena de $ADMIN_AD@$DOMINIO" -AsSecureString
    $cred = New-Object System.Management.Automation.PSCredential(
        "$ADMIN_AD@$DOMINIO", $pass
    )

    try {
        Add-Computer -DomainName $DOMINIO -Credential $cred -Force -ErrorAction Stop
        Write-Ok "Equipo unido exitosamente al dominio '$DOMINIO'."
        Write-Warn "Reinicia el equipo para que los cambios surtan efecto."
        Write-Warn "Comando: Restart-Computer"
    } catch {
        Write-Err "Error al unirse al dominio: $($_.Exception.Message)"
        Write-Info "Verifica:"
        Write-Info "  - Que el DNS apunta al DC (opcion 4)"
        Write-Info "  - Que el SID fue regenerado con Sysprep (opcion 2)"
        Write-Info "  - Que el nombre del equipo no coincide con el servidor"
    }
}


# -----------------------------------------------
# 6. VERIFICACION COMPLETA
# -----------------------------------------------
function verificar {
    Write-Banner "VERIFICACION"

    $cs = Get-WmiObject Win32_ComputerSystem

    Write-Info "Nombre del equipo : $env:COMPUTERNAME"
    Write-Info "Dominio/Workgroup  : $($cs.Domain)"

    if ($cs.PartOfDomain) {
        Write-Ok "Estado: UNIDO al dominio $($cs.Domain)"
    } else {
        Write-Warn "Estado: NO esta en el dominio (solo en workgroup)"
    }

    Write-Linea

    # DNS
    Write-Info "Servidores DNS configurados:"
    Get-DnsClientServerAddress -AddressFamily IPv4 |
        Where-Object { $_.ServerAddresses.Count -gt 0 } |
        ForEach-Object {
            Write-Info "  $($_.InterfaceAlias) -> $($_.ServerAddresses -join ', ')"
        }

    Write-Linea

    # Conectividad con el DC
    if (Test-Connection -ComputerName $DC_IP -Count 1 -Quiet) {
        Write-Ok "DC alcanzable: $DC_IP"
    } else {
        Write-Warn "DC NO alcanzable: $DC_IP"
    }

    # Resolucion DNS del dominio
    try {
        $r = Resolve-DnsName -Name $DOMINIO -Server $DC_IP -ErrorAction Stop
        Write-Ok "DNS OK: $DOMINIO -> $($r[0].IPAddress)"
    } catch {
        Write-Warn "DNS: No se pudo resolver '$DOMINIO'"
    }

    Write-Linea

    # Polticas GPO recibidas
    Write-Info "Politicas GPO aplicadas en este equipo:"
    $gpResult = gpresult /scope computer /r 2>$null
    if ($gpResult) {
        $gpResult | Select-String "GPO aplicado|Applied GPO" |
            ForEach-Object { Write-Info "  $($_.Line.Trim())" }
    } else {
        Write-Warn "No se pudo obtener resultado de GPO (gpresult)."
    }

    Write-Linea
    Write-Ok "Verificacion completa."
}


# -----------------------------------------------
# MENU PRINCIPAL
# -----------------------------------------------
function menuPrincipal {
    do {
        Clear-Host
        Write-Host ""
        Write-Host "  ================================================" -ForegroundColor Magenta
        Write-Host "    CLIENTE WINDOWS - UNION AL DOMINIO AD          " -ForegroundColor White
        Write-Host "    Practica 8 - Administracion de Sistemas        " -ForegroundColor DarkMagenta
        Write-Host "  ================================================" -ForegroundColor Magenta
        Write-Host ""
        Write-Host "  Dominio  : $DOMINIO" -ForegroundColor DarkMagenta
        Write-Host "  IP DC    : $DC_IP"   -ForegroundColor DarkMagenta
        Write-Host ""
        Write-Host "    1.  Diagnostico del clon  (ver SID y nombre)"     -ForegroundColor White
        Write-Host "    2.  Sysprep  (regenerar SID - VM clonada)"        -ForegroundColor Yellow
        Write-Host "    3.  Cambiar nombre del equipo"                    -ForegroundColor White
        Write-Host "    4.  Configurar red y DNS  (apuntar al DC)"        -ForegroundColor White
        Write-Host "    5.  Unirse al dominio '$DOMINIO'"                 -ForegroundColor White
        Write-Host "    6.  Verificar estado"                             -ForegroundColor White
        Write-Host "    7.  Cambiar variables (dominio, IP del DC)"       -ForegroundColor White
        Write-Host "    8.  Salir"                                        -ForegroundColor DarkMagenta
        Write-Host ""
        Write-Host "  ------------------------------------------------" -ForegroundColor Magenta
        Write-Host "  Orden recomendado: 1 -> 2 -> reiniciar -> 4 -> 5" -ForegroundColor DarkMagenta
        Write-Host ""

        $op = Read-Host "  Selecciona una opcion"

        switch ($op) {
            "1" { diagnosticoClon;     Read-Host "`n  Enter para continuar" }
            "2" { ejecutarSysprep;     Read-Host "`n  Enter para continuar" }
            "3" { cambiarNombreEquipo; Read-Host "`n  Enter para continuar" }
            "4" { configurarRed;       Read-Host "`n  Enter para continuar" }
            "5" { unirseAlDominio;     Read-Host "`n  Enter para continuar" }
            "6" { verificar;           Read-Host "`n  Enter para continuar" }
            "7" {
                Write-Host ""
                $d = Read-Host "  Nuevo dominio (actual: $DOMINIO, Enter para mantener)"
                if (-not [string]::IsNullOrWhiteSpace($d)) { $script:DOMINIO = $d }
                $i = Read-Host "  Nueva IP del DC (actual: $DC_IP, Enter para mantener)"
                if (-not [string]::IsNullOrWhiteSpace($i)) { $script:DC_IP = $i }
                Write-Ok "Variables actualizadas."
                Read-Host "`n  Enter para continuar"
            }
            "8" { Write-Host "`n  Saliendo..." -ForegroundColor Magenta; return }
            default {
                Write-Warn "Opcion no valida."
                Start-Sleep -Seconds 1
            }
        }
    } while ($true)
}


# -----------------------------------------------
# ENTRY POINT
# -----------------------------------------------
menuPrincipal