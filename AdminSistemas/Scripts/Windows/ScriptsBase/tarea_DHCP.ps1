write-host "===================================================" -foregroundcolor magenta
write-host "=================PRUEBA DE SCRIPT==================" -foregroundcolor magenta
write-host "===================================================" -foregroundcolor magenta

function verificarInstalacion {
	write-host "Verificando la instalacion DHCP..." -foregroundcolor magenta
	$feature = get-windowsfeature -name DHCP

	if ($feature.installed) 
	{
		write-host "SERVICIO DHCP INSTALADO" -foregroundcolor magenta
	}
	else 
	{
		write-host "SERVICIO DHCP NO INSTALADO" -foregroundcolor magenta
		write-host "sugerencia!... use la opcion de instalar el servicio" -foregroundcolor magenta
	}
}

function instalacion {

	write-host " INICIANDO INSTALACION..." -foregroundcolor magenta
	$check = get-windowsfeature -name DHCP

	if ($check.installed) 
	{
		write-host "SERVICIO DHCP INSTALADO, (no es necesario una instalacion)" -foregroundcolor magenta
	}
	else 
	{
		try{
			$resul = install-windowsfeature -name DHCP -includemanagementtools
		
			if($resul.restartneeded -eq "Yes"){
				write-host "REINICIO REQUERIDO PARA COMPLETAR." -foregroundcolor magenta
				$confirmar = read-host "desea reiniciar ahora? (si/no)"
				if ($confirmar -eq "si") {restart-computer} 
			}else{
				write-host "SERVICIO DHCP INSTALADO CON EXITO!" -foregroundcolor magenta		
			}
		
		}catch{
			write-host "error al instalar" -foregroundcolor magenta
		}
	}
}

function desinstalacion{
	write-host "INICIANDO DESINSTALACION..." -foregroundcolor magenta
	$check = get-windowsfeature -name DHCP
	
	if ($check.installed) 
	{
		write-host "deteniendo proceso en memoria..." -foregroundcolor magenta
		stop-service -name DHCPServer -force -erroraction silentlycontinue
	
		$res = uninstall-windowsfeature -name DHCP -includemanagementtools
		if ($res.success){
			write-host "desinstalacion exitosa!" -foregroundcolor magenta
			if ($res.restartneeded -eq "Yes"){
				write-host "advertencia: se necesita un reinicio" -foregroundcolor magenta
			}
		}
	}
	else 
	{
		write-host "servicio no instalado, por lo tanto no se puede desinstalar" -foregroundcolor magenta
	}
}

function configuracionDhcp{
	import-module dhcpserver -force
	function validacionIp {
    	param([string]$mensaje, [bool]$opcional = $false)
    	do {
        	$ip = read-host $mensaje
        	if ($opcional -and [string]::IsNullOrWhiteSpace($ip)) { return $null }

        	if ($ip -match '^((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$') {
            
            	$octetos = $ip.Split('.')
            	$errorCero = $false

            	foreach ($octeto in $octetos) {
                	if ($octeto.Length -gt 1 -and $octeto.StartsWith("0")) {
                    	$errorCero = $true
                    	break
                	}
            	}

            	if ($errorCero) {
                	write-host "error: no se permiten ceros a la izquierda (ej. use '1' en lugar de '01')" -foregroundcolor magenta
                	continue
            	}

             	$primerOcteto = [int]$octetos[0]
            
            	if ($ip -eq "0.0.0.0") { write-host "error: 0.0.0.0 reservada" -foregroundcolor magenta }
            	elseif ($ip -eq "255.255.255.255") { write-host "error: Global Broadcast" -foregroundcolor magenta }
            	elseif ($primerOcteto -eq 127) { write-host "error: Rango Loopback" -foregroundcolor magenta }
            	elseif ($primerOcteto -ge 224) { write-host "error: IP Multicast o Reservada ($primerOcteto)" -foregroundcolor magenta }
            	else { return $ip }
        	}
        	else {
            	write-host "formato ipv4 invalido o fuera de rango (0-255). reintente" -foregroundcolor magenta
        	}
    	} while ($true)
	}

	write-host "===CONFIGURACION DEL SERVICIO DHCP===" -foregroundcolor magenta

	$nombreScope = read-host "Ingrese un nombre para el scope: " 

	$rangoI = validacionIp "IP Inicial del rango: "
	$prefijoI = $rangoI.split('.')[0..2] -join '.'
	$octetoI = $rangoI.split('.')

	write-host "configurando la ip fija del servidor ($rangoI)..." -foregroundcolor magenta
	try{
		$interfaz = (get-netadapter | where-object status -eq "Up" | select-object -first 1).name
		remove-netipaddress -interfacealias "Ethernet 2" -confirm:$false -erroraction silentlycontinue
		new-netipaddress -interfacealias "Ethernet 2" -ipaddress $rangoI -prefixlength 24 -erroraction silentlycontinue
		set-dhcpserverv4binding -bindingstate $true -interfacealias "Ethernet 2"
		write-host "servidor ahora tiene la ip: $rangoI" -foregroundcolor magenta
	} catch{
		write-host "no se puede cambiar la ip del servidor: $($_.exception.message)" -foregroundcolor magenta
	}

	$ipSplit = $rangoI.split('.')
	$ultimoOcteto = [int]$ipSplit[3] + 1
	$rangoDhcpInicio = "$($ipSplit[0..2] -join '.').$ultimoOcteto"
	write-host "el rango de clientes empezara en: $rangoDhcpInicio" -foregroundcolor magenta

	do{
		$rangoF = validacionIp "IP final del rango: "
		$prefijoF = $rangoF.split('.')[0..2] -join '.'
		$octetoF = $rangoF.split('.')

		if ([version]$rangoI -ge [version]$rangoF ){
			write-host "error, la ip inicial ($rangoI) no puede ser mayor que el rango final ($rangoF)" -foregroundcolor magenta	
		}
		elseif ($prefijoI -ne $prefijoF){
			write-host "error, la ip inicial debe ser del mismo rango que la ip final" -foregroundcolor magenta
		}
		else {
			write-host "las IPs son validas" -foregroundcolor magenta
			write-host "procediendo..." -foregroundcolor magenta
			write-host "CALCULANDO ID DE RED..." -foregroundcolor magenta
			$redId = $prefijoI + ".0"
			
			write-host "CALCULANDO MASCARA DE RED..." -foregroundcolor magenta
			if ($octetoI[0..2] -join '.' -eq $octetoF[0..2] -join '.'){
				$mascara = "255.255.255.0"
			}
			elseif ($octetoI[0..1] -join '.' -eq $octetoF[0..1] -join '.'){
				$mascara = "255.255.0.0"
			}
			else{
				$mascara = "255.0.0.0"
			}			
			write-host "mascara calculada: $mascara" -foregroundcolor magenta
		}
	} while([version]$rangoI -ge [version]$rangoF -or $prefijoI -ne $prefijoF)

	$dns = validacionIp "servidor DNS:	"
	if (-not [string]::isnullorwhitespace($dns)) {
		write-host "dns configurado: $dns" -foregroundcolor magenta
	}

	$gateway = read-host "ingrese la ip del gateway/puerta de enlace (deje en blanco para saltar"
	if (-not [string]::isnullorwhitespace($gateway)) {
		set-dhcpserverv4optionvalue -scopeid $redId -optionid 3 -value $gateway
		write-host "gateway configurado: $gateway" -foregroundcolor magenta
	}

	write-host "ejemplo de lease time: 08:00:00 (8 horas) 'dias.hrs.min.seg'"
	$tiempolease = read-host "ingrese tiempo de concesion: " 
	
	write-host "aplicando configuracion..." -foregroundcolor magenta

	$params = @{
		Name = $nombreScope
		StartRange = $rangoDhcpInicio
		EndRange = $rangoF
		SubnetMask = $mascara
		LeaseDuration = [timespan]$tiempolease
		State = "Active"
	}

	try{
		add-DhcpServerv4Scope @params
		set-dhcpserverv4optionvalue -scopeid $redId -dnsserver $dns -force
		write-host "configuracion exitosa!" -foregroundcolor magenta
	}
	catch{
		write-host "error: $($_.Exception.message)" -foregroundcolor magenta
	}
}

function monitoreo{
	write-host "==================MONITOREO Y ESTADO DEL SERVICIO==================" -foregroundcolor magenta
	$servicio = get-service -name DHCPServer -Erroraction silentlycontinue
	if ($servicio){
		$color = if ($servicio.status -eq "Running") {"magenta"} else {"magenta"}
		write-host "estado del servicio: " -nonewline
		write-host "$($servicio.Status)" -foregroundcolor $color
	} else{
		write-host "el servicio dhcp no esta instalado correctamente" -foregroundcolor magenta
		return
	}

	write-host "--------------------------------------------------------------------------"
	write-host "equipos conectados (leases activos): " -foregroundcolor magenta

	try{
		$ambitos = get-dhcpserverv4scope -erroraction silentlycontinue
		if ($ambitos) {
			$hayleases = $false
			foreach ($ambito in $ambitos){
				$leases = get-dhcpserverv4lease -scopeid $ambito.scopeid -erroraction silentlycontinue
				if ($leases) {
					$leases | select-object ipaddress, clientid, hostname, leaseexpirytime | format-table -autosize
					$hayleases = $true
				}
			}
			if (-not $hayleases){
				write-host "no hay equipos conectados actualmente" -foregroundcolor magenta
			}
		} else{
			write-host "no hay ambitos (scopes) configurados" -foregroundcolor magenta
		}
	}catch{
		write-host "no existe el servicio o no hay clientes disponibles" -foregroundcolor magenta
	}
}

function menu{
	write-host "==================MENU DE OPCIONES==================" -foregroundcolor magenta
	write-host "1. verificar instalacion dhcp" -foregroundcolor magenta
	write-host "2. instalar servicio" -foregroundcolor magenta
	write-host "3. desinstalar servicio (razon de practica)" -foregroundcolor magenta
	write-host "4. configuracion de servicio dhcp" -foregroundcolor magenta
	write-host "5. monitoreo de servicio " -foregroundcolor magenta
}

do {
	menu
	$opcion = read-host "ingrese una opcion: "

	switch ($opcion) {
		"1" {verificarInstalacion}
		"2" {instalacion}
		"3" {desinstalacion}
		"4" {configuracionDhcp}
		"5" {monitoreo}
		default {write-host "opcion invalida!" -foregroundcolor magenta}
	}
	$choice = read-host "escribe 'si' para continuar"
}while ($choice -eq "si")

write-host "procediendo..." -foregroundcolor magenta
