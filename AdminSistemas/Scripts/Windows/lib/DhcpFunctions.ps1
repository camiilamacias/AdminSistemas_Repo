# DhcpFunctions.ps1
# Funciones DHCP (Windows Server) - modularizadas
# Requiere Common.ps1 (Validar-IPv4)

function Dhcp-VerificarInstalacion {
    Write-Host "Verificando la instalacion DHCP..." -ForegroundColor Magenta
    $feature = Get-WindowsFeature -Name DHCP

    if ($feature.Installed) {
        Write-Host "SERVICIO DHCP INSTALADO" -ForegroundColor Magenta
    } else {
        Write-Host "SERVICIO DHCP NO INSTALADO" -ForegroundColor Magenta
        Write-Host "sugerencia!... use la opcion de instalar el servicio" -ForegroundColor Magenta
    }
}

function Dhcp-Instalar {
    Write-Host " INICIANDO INSTALACION..." -ForegroundColor Magenta
    $check = Get-WindowsFeature -Name DHCP

    if ($check.Installed) {
        Write-Host "SERVICIO DHCP INSTALADO, (no es necesario una instalacion)" -ForegroundColor Magenta
        return
    }

    try {
        $resul = Install-WindowsFeature -Name DHCP -IncludeManagementTools

        if ($resul.RestartNeeded -eq "Yes") {
            Write-Host "REINICIO REQUERIDO PARA COMPLETAR." -ForegroundColor Magenta
            $confirmar = Read-Host "desea reiniciar ahora? (si/no)"
            if ($confirmar -eq "si") { Restart-Computer }
        } else {
            Write-Host "SERVICIO DHCP INSTALADO CON EXITO!" -ForegroundColor Magenta
        }
    } catch {
        Write-Host "error al instalar: $($_.Exception.Message)" -ForegroundColor Magenta
    }
}

function Dhcp-Desinstalar {
    Write-Host "INICIANDO DESINSTALACION..." -ForegroundColor Magenta
    $check = Get-WindowsFeature -Name DHCP

    if (-not $check.Installed) {
        Write-Host "servicio no instalado, por lo tanto no se puede desinstalar" -ForegroundColor Magenta
        return
    }

    Write-Host "deteniendo proceso en memoria..." -ForegroundColor Magenta
    Stop-Service -Name DHCPServer -Force -ErrorAction SilentlyContinue

    $res = Uninstall-WindowsFeature -Name DHCP -IncludeManagementTools
    if ($res.Success) {
        Write-Host "desinstalacion exitosa!" -ForegroundColor Magenta
        if ($res.RestartNeeded -eq "Yes") {
            Write-Host "advertencia: se necesita un reinicio" -ForegroundColor Magenta
        }
    }
}

function Dhcp-Configurar {
    Import-Module DhcpServer -Force
    Write-Host "===CONFIGURACION DEL SERVICIO DHCP===" -ForegroundColor Magenta

    $nombreScope = Read-Host "Ingrese un nombre para el scope: "

    # IP Inicial del rango = IP fija del servidor (como tu script base)
    $rangoI = Validar-IPv4 "IP Inicial del rango (sera la IP del servidor): "
    $prefijoI = $rangoI.Split('.')[0..2] -join '.'
    $octetoI = $rangoI.Split('.')

    Write-Host "configurando la ip fija del servidor ($rangoI)..." -ForegroundColor Magenta
    try {
        # Mantengo tu enfoque: Ethernet 2 es la red interna del lab
        Remove-NetIPAddress -InterfaceAlias "Ethernet 2" -Confirm:$false -ErrorAction SilentlyContinue
        New-NetIPAddress -InterfaceAlias "Ethernet 2" -IPAddress $rangoI -PrefixLength 24 -ErrorAction SilentlyContinue
        Set-DhcpServerv4Binding -BindingState $true -InterfaceAlias "Ethernet 2"
        Write-Host "servidor ahora tiene la ip: $rangoI" -ForegroundColor Magenta
    } catch {
        Write-Host "no se puede cambiar la ip del servidor: $($_.Exception.Message)" -ForegroundColor Magenta
    }

    # Rango clientes inicia en +1
    $ipSplit = $rangoI.Split('.')
    $ultimoOcteto = [int]$ipSplit[3] + 1
    $rangoDhcpInicio = "$($ipSplit[0..2] -join '.').$ultimoOcteto"
    Write-Host "el rango de clientes empezara en: $rangoDhcpInicio" -ForegroundColor Magenta

    # Validación IP final y subred (tu lógica)
    do {
        $rangoF = Validar-IPv4 "IP final del rango: "
        $prefijoF = $rangoF.Split('.')[0..2] -join '.'
        $octetoF = $rangoF.Split('.')

        if ([version]$rangoI -ge [version]$rangoF) {
            Write-Host "error, la ip inicial ($rangoI) no puede ser mayor que el rango final ($rangoF)" -ForegroundColor Magenta
        }
        elseif ($prefijoI -ne $prefijoF) {
            Write-Host "error, la ip inicial debe ser del mismo rango que la ip final" -ForegroundColor Magenta
        }
        else {
            Write-Host "las IPs son validas" -ForegroundColor Magenta
            Write-Host "procediendo..." -ForegroundColor Magenta
            Write-Host "CALCULANDO ID DE RED..." -ForegroundColor Magenta
            $redId = $prefijoI + ".0"

            Write-Host "CALCULANDO MASCARA DE RED..." -ForegroundColor Magenta
            if (($octetoI[0..2] -join '.') -eq ($octetoF[0..2] -join '.')) {
                $mascara = "255.255.255.0"
            }
            elseif (($octetoI[0..1] -join '.') -eq ($octetoF[0..1] -join '.')) {
                $mascara = "255.255.0.0"
            }
            else {
                $mascara = "255.0.0.0"
            }
            Write-Host "mascara calculada: $mascara" -ForegroundColor Magenta
        }
    } while ([version]$rangoI -ge [version]$rangoF -or $prefijoI -ne $prefijoF)

    # ✅ CAMBIO PEDIDO: DNS PRIMARIO = IP DEL SERVIDOR
    $dnsPrimario = $rangoI
    Write-Host "DNS primario (servidor): $dnsPrimario" -ForegroundColor Magenta

    # DNS secundario opcional (se mantiene opcional)
    $dnsSecundario = Validar-IPv4 "DNS secundario (opcional, ENTER para omitir): " $true

    $gateway = Read-Host "ingrese la ip del gateway/puerta de enlace (deje en blanco para saltar)"
    if (-not [string]::IsNullOrWhiteSpace($gateway)) {
        Set-DhcpServerv4OptionValue -ScopeId $redId -OptionId 3 -Value $gateway
        Write-Host "gateway configurado: $gateway" -ForegroundColor Magenta
    }

    Write-Host "ejemplo de lease time: 08:00:00 (8 horas) 'dias.hrs.min.seg'" -ForegroundColor Magenta
    $tiempolease = Read-Host "ingrese tiempo de concesion: "
    if ([string]::IsNullOrWhiteSpace($tiempolease)) { $tiempolease = "08:00:00" }

    Write-Host "aplicando configuracion..." -ForegroundColor Magenta

    $params = @{
        Name          = $nombreScope
        StartRange    = $rangoDhcpInicio
        EndRange      = $rangoF
        SubnetMask    = $mascara
        LeaseDuration = [timespan]$tiempolease
        State         = "Active"
    }

    try {
        Add-DhcpServerv4Scope @params

        # Opción 006 DNS: primario = servidor, secundario opcional
        if ($dnsSecundario) {
            Set-DhcpServerv4OptionValue -ScopeId $redId -DnsServer $dnsPrimario, $dnsSecundario -Force
            Write-Host "DNS entregado por DHCP: $dnsPrimario (primario), $dnsSecundario (secundario)" -ForegroundColor Magenta
        } else {
            Set-DhcpServerv4OptionValue -ScopeId $redId -DnsServer $dnsPrimario -Force
            Write-Host "DNS entregado por DHCP (primario): $dnsPrimario" -ForegroundColor Magenta
        }

        Write-Host "configuracion exitosa!" -ForegroundColor Magenta
    } catch {
        Write-Host "error: $($_.Exception.Message)" -ForegroundColor Magenta
    }
}

function Dhcp-Monitoreo {
    Write-Host "==================MONITOREO Y ESTADO DEL SERVICIO==================" -ForegroundColor Magenta

    $servicio = Get-Service -Name DHCPServer -ErrorAction SilentlyContinue
    if ($servicio) {
        Write-Host "estado del servicio: $($servicio.Status)" -ForegroundColor Magenta
    } else {
        Write-Host "el servicio dhcp no esta instalado correctamente" -ForegroundColor Magenta
        return
    }

    Write-Host "--------------------------------------------------------------------------"
    Write-Host "equipos conectados (leases activos): " -ForegroundColor Magenta

    try {
        $ambitos = Get-DhcpServerv4Scope -ErrorAction SilentlyContinue
        if ($ambitos) {
            $hayleases = $false
            foreach ($ambito in $ambitos) {
                $leases = Get-DhcpServerv4Lease -ScopeId $ambito.ScopeId -ErrorAction SilentlyContinue
                if ($leases) {
                    $leases | Select-Object IPAddress, ClientId, Hostname, LeaseExpiryTime | Format-Table -AutoSize
                    $hayleases = $true
                }
            }
            if (-not $hayleases) {
                Write-Host "no hay equipos conectados actualmente" -ForegroundColor Magenta
            }
        } else {
            Write-Host "no hay ambitos (scopes) configurados" -ForegroundColor Magenta
        }
    } catch {
        Write-Host "no existe el servicio o no hay clientes disponibles" -ForegroundColor Magenta
    }
}