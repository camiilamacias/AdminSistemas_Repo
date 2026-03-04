function Dns-ConfigurarZona {
    Write-Host "=== CONFIGURACION DNS ===" -ForegroundColor Magenta

    $dominio = Read-Host "Zona (ej: vamonosalauaneg.com)"
    if ([string]::IsNullOrWhiteSpace($dominio)) { $dominio = "vamonosalauaneg.com" }

    $hostname = Read-Host "Host (ej: www)"
    if ([string]::IsNullOrWhiteSpace($hostname)) { $hostname = "www" }

 $ipDestino = Validar-IPv4 "IP destino para ${hostname}.${dominio}: "

    if (-not (Get-DnsServerZone -Name $dominio -ErrorAction SilentlyContinue)) {
        Add-DnsServerPrimaryZone -Name $dominio -ZoneFile "$dominio.dns"
        Write-Host "Zona creada: $dominio" -ForegroundColor Green
    }

    Add-DnsServerResourceRecordA -Name $hostname -ZoneName $dominio -IPv4Address $ipDestino -AllowUpdateAny
    Write-Host "Registro A creado." -ForegroundColor Green
}

function Dns-BorrarZona {
    $borrar = Read-Host "Dominio a borrar"
    if (Get-DnsServerZone -Name $borrar -ErrorAction SilentlyContinue) {
        Remove-DnsServerZone -Name $borrar -Force
        Write-Host "Zona eliminada: $borrar" -ForegroundColor Green
    } else {
        Write-Host "No existe: $borrar" -ForegroundColor Magenta
    }
}

function Dns-Monitoreo {
    Write-Host "=== MONITOREO DNS ===" -ForegroundColor Magenta
    $servicio = Get-Service -Name DNS -ErrorAction SilentlyContinue
    if ($servicio.Status -ne "Running") { Write-Host "DNS no iniciado." -ForegroundColor Magenta; return }

    $dominioTest = Read-Host "Dominio a validar"
    $hostTest = Read-Host "Host a validar"
    $nombre = "$hostTest.$dominioTest"

    $lookup = Resolve-DnsName -Name $nombre -Server 127.0.0.1 -ErrorAction SilentlyContinue
    if ($lookup) {
        Write-Host "Resuelve: $($lookup.IPAddress)" -ForegroundColor Green
    } else {
        Write-Host "No resuelve." -ForegroundColor Magenta
    }
}