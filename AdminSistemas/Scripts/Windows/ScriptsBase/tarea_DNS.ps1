# =======================
# PRACTICA 3 - DNS 
# =======================
function validacionIp {
    param([string]$mensaje, [bool]$opcional = $false)
    do {
        $ip = Read-Host $mensaje
        if ($opcional -and [string]::IsNullOrWhiteSpace($ip)) { return $null }
        if ($ip -match '^((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$') {
            return $ip
        }
        Write-Host "Formato IPv4 invalido. Reintente." -ForegroundColor Magenta
    } while ($true)
}

function GestionarIpFija {
    Write-Host "`n[Verificando Configuracion de Red]" -ForegroundColor Magenta
    $interfaz = Get-NetIPInterface -AddressFamily IPv4 | Where-Object { $_.InterfaceAlias -notmatch "Loopback" } | Select-Object -First 1
    
    if ($interfaz.Dhcp -eq "Enabled") {
        Write-Host "ADVERTENCIA: El servidor tiene DHCP habilitado. Se requiere IP fija para DNS." -ForegroundColor Yellow
        $nuevaIp = validacionIp "Ingrese la IP estatica para este servidor: "
        $mascara = Read-Host "Ingrese la mascara (ej. 24 para 255.255.255.0): "
        $gw = validacionIp "Ingrese el Gateway (Puerta de enlace): "
        
        Write-Host "Configurando IP estatica..." -ForegroundColor Yellow
        New-NetIPAddress -InterfaceAlias $interfaz.InterfaceAlias -IPAddress $nuevaIp -PrefixLength $mascara -DefaultGateway $gw
        Write-Host "IP configurada con exito." -ForegroundColor Green
    } else {
        $actual = (Get-NetIPAddress -InterfaceIndex $interfaz.InterfaceIndex -AddressFamily IPv4).IPAddress
        Write-Host "El servidor ya tiene una IP fija configurada: $actual" -ForegroundColor Green
    }
}

function ConfigurarDns {
    Write-Host "`n=== CONFIGURACION DE ZONA Y REGISTROS ===" -ForegroundColor DarkMagenta
    
    $dominio = Read-Host "Ingrese el nombre de la zona (ej: reprobados.com)"
    if ([string]::IsNullOrWhiteSpace($dominio)) { $dominio = "reprobados.com" }

    $hostname = Read-Host "Ingrese el hostname (ej: www)"
    if ([string]::IsNullOrWhiteSpace($hostname)) { $hostname = "www" }

    $ipDestino = validacionIp "Ingrese la IP a la que apuntara ${hostname}.${dominio} : "

    try {
        if (-not (Get-DnsServerZone -Name $dominio -ErrorAction SilentlyContinue)) {
            Add-DnsServerPrimaryZone -Name $dominio -ZoneFile "$dominio.dns"
            Write-Host "Zona $dominio creada." -ForegroundColor Green
        }
        
        Add-DnsServerResourceRecordA -Name $hostname -ZoneName $dominio -IPv4Address $ipDestino -AllowUpdateAny
        Write-Host "Registro configurado con exito." -ForegroundColor Green
    } catch {
        Write-Host "Error en la configuracion: $($_.Exception.Message)" -ForegroundColor Magenta
    }
} 

function borrarDominio{
    $borrar = read-host "ingrese el dominio que desea borrar (ej: reprobados.com)"
    if (get-DnsServerZone -name $borrar -erroraction silentlycontinue){
        try{
            remove-DnsServerZone -name $borrar -force
            write-host "el dominio $borrar a sido borrado correctamente" -foregroundcolor Green
        } catch{
            write-host "error al eliminar el dominio: $($_.exception.message)" -foregroundcolor Magenta
        }
    }else{
        write-host "error: el dominio $borrar no existe en el servidor" -ForegroundColor Magenta
    }
}

function MonitoreoDns {
    Write-Host "`n=== MODULO DE MONITOREO Y VALIDACION ===" -ForegroundColor Magenta
    
    # 1. Verificacion de Estado del Servicio
    $servicio = Get-Service -Name DNS -ErrorAction SilentlyContinue
    if ($servicio.Status -eq "Running") {
        Write-Host "[OK] El servicio DNS esta operando correctamente." -ForegroundColor Green
    } else {
        Write-Host "[ERROR] El servicio DNS no esta iniciado." -ForegroundColor Magenta
        return
    }

    # 2. Entrada de datos para la prueba
    $dominioTest = Read-Host "Ingrese el dominio a validar (ej: reprobados.com)"
    if ([string]::IsNullOrWhiteSpace($dominioTest)) { $dominioTest = "reprobados.com" }
    
    $hostTest = Read-Host "Ingrese el host a validar (ej: www)"
    if ([string]::IsNullOrWhiteSpace($hostTest)) { $hostTest = "www" }
    
    $nombreCompleto = "${hostTest}.${dominioTest}"

    # 3. Prueba de Resolucion (nslookup)
    Write-Host "`nEjecutando nslookup para $nombreCompleto..." -ForegroundColor Yellow
    $lookup = Resolve-DnsName -Name $nombreCompleto -Server 127.0.0.1 -ErrorAction SilentlyContinue
    
    if ($lookup) {
        $ipDevuelta = $lookup.IPAddress
        Write-Host "[EXITO] nslookup resolvio $nombreCompleto en la IP: $ipDevuelta" -ForegroundColor Green
        
        # 4. Prueba de Ping y Verificacion de IP
        Write-Host "Ejecutando ping para verificar respuesta..." -ForegroundColor Yellow
        $ping = Test-Connection -ComputerName $nombreCompleto -Count 1 -ErrorAction SilentlyContinue
        
        if ($ping) {
            $ipPing = $ping.IPV4Address.IPAddressToString
            Write-Host "[EXITO] Ping respondio desde $ipPing" -ForegroundColor Green
            
            if ($ipDevuelta -eq $ipPing) {
                Write-Host "EVIDENCIA: La IP devuelta coincide con la maquina referenciada ($ipDevuelta)." -ForegroundColor Cyan -BackgroundColor DarkMagenta
            }
        } else {
            Write-Host "[AVISO] El nombre resuelve pero el host no responde al ping (verifique Firewall)." -ForegroundColor Yellow
        }
    } else {
        Write-Host "[FALLO] No se pudo resolver el nombre $nombreCompleto en el DNS local." -ForegroundColor Magenta
    }
}

do {
    Write-Host "======================================================================" -ForegroundColor DarkMagenta
    Write-Host "                           SERVIDOR DNS                               " -ForegroundColor Magenta
    Write-Host "======================================================================" -ForegroundColor DarkMagenta
    Write-Host "[1] - VERIFICAR INSTALACION DNS" -ForegroundColor Magenta
    Write-Host "[2] - INSTALAR SERVICIO DNS" -ForegroundColor Magenta
    Write-Host "[3] - REMOVER SERVICIO DNS" -ForegroundColor Magenta
    Write-Host "[4] - CONFIGURAR ZONA Y REGISTROS (reprobados.com)" -ForegroundColor Magenta
    Write-Host "[5] - BORRAR DOMINIO" -ForegroundColor Magenta
    Write-Host "[6] - MONITOREO Y PRUEBAS" -ForegroundColor Magenta
    Write-Host "[7] - SALIR" -ForegroundColor Magenta

    $opc = Read-Host "`nIngrese una opcion"

    switch($opc) {
        "1" { 
            $v = Get-WindowsFeature DNS
            if ($v.Installed) { Write-Host "DNS Instalado" -ForegroundColor Green } else { Write-Host "No instalado" -ForegroundColor Magenta }
        }
        "2" { Install-WindowsFeature DNS -IncludeManagementTools }
        "3" { Uninstall-WindowsFeature DNS -Remove }
        "4" { ConfigurarDns }
        "5" { borrarDominio }
        "6" { MonitoreoDns }
        "7" { $opc = "salir" }
    }
} while ($opc -ne "salir")