# ============================================================
# windows-funciones_http.ps1
# Funciones para gestion de servidores HTTP en Windows Server 2022 Core
# Paleta rosita | Reinstalacion recursiva | Pagina estilo Alpine
# ============================================================

# =============== MENSAJES (PALETA ROSITA) ===============
function Write-Ok    { param($msg) Write-Host "  [+] $msg" -ForegroundColor Magenta    }
function Write-Info  { param($msg) Write-Host "  [i] $msg" -ForegroundColor DarkMagenta }
function Write-Err   { param($msg) Write-Host "  [x] $msg" -ForegroundColor Red         }
function Write-Warn  { param($msg) Write-Host "  [!] $msg" -ForegroundColor Yellow      }
function Write-Title {
    param($msg)
    Write-Host ""
    Write-Host "  $msg" -ForegroundColor White -BackgroundColor DarkMagenta
    Write-Host ""
}
function Write-Banner {
    param([string]$titulo)
    Write-Host ""
    Write-Host "  ================================================" -ForegroundColor Magenta
    Write-Host "    $titulo" -ForegroundColor White
    Write-Host "  ================================================" -ForegroundColor Magenta
    Write-Host ""
}
function Write-Linea { Write-Host "  ------------------------------------------------" -ForegroundColor Magenta }

# =============== RECARGAR PATH ===============
function Refrescar-Path {
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" +
                [System.Environment]::GetEnvironmentVariable("Path","User")
}

# =============== CHOCOLATEY ===============
function Asegurar-Chocolatey {
    Refrescar-Path
    if (Get-Command choco -ErrorAction SilentlyContinue) {
        Write-Info "Chocolatey disponible."
        return
    }
    Write-Info "Instalando Chocolatey..."
    try {
        Set-ExecutionPolicy Bypass -Scope Process -Force
        [System.Net.ServicePointManager]::SecurityProtocol =
            [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
        Invoke-Expression (
            (New-Object System.Net.WebClient).DownloadString(
                'https://community.chocolatey.org/install.ps1'
            )
        ) 2>&1 | Out-Null
        Refrescar-Path
        if (Get-Command choco -ErrorAction SilentlyContinue) {
            Write-Ok "Chocolatey instalado correctamente."
            return
        }
        $chocoDir = "$env:ALLUSERSPROFILE\chocolatey\bin"
        if (Test-Path "$chocoDir\choco.exe") {
            $env:Path += ";$chocoDir"
            Write-Ok "Chocolatey instalado (PATH actualizado manualmente)."
        } else {
            Write-Err "No se pudo instalar Chocolatey. Verifica la conexion a internet."
            return
        }
    } catch {
        Write-Err "Error instalando Chocolatey: $_"
        return
    }
}

# =============== VALIDAR PUERTO ===============
function validarPuerto {
    param([int]$puerto)
    $reservados = @(21, 22, 23, 25, 53, 443, 3306, 3389, 5432, 6379, 27017)
    if ($reservados -contains $puerto) {
        Write-Warn "Puerto $puerto reservado para otro servicio."
        return $false
    }
    $enUso = Get-NetTCPConnection -LocalPort $puerto -ErrorAction SilentlyContinue
    if ($enUso) {
        $proc = Get-Process -Id $enUso[0].OwningProcess -ErrorAction SilentlyContinue
        Write-Warn "Puerto $puerto ocupado por: $($proc.ProcessName) (PID: $($enUso[0].OwningProcess))"
        return $false
    }
    return $true
}

# =============== PEDIR PUERTO ===============
function pedirPuerto {
    param([int]$default = 80)
    Write-Host ""
    Write-Host "  === Configuracion de Puerto ===" -ForegroundColor Magenta
    Write-Info "Puerto por defecto : $default"
    Write-Info "Otros comunes      : 8080, 8888, 9090"
    Write-Info "Bloqueados         : 21 22 23 25 53 443 3306 3389 5432 6379 27017"
    Write-Host ""
    while ($true) {
        $inp = Read-Host "  Puerto de escucha (Enter = $default)"
        if ([string]::IsNullOrWhiteSpace($inp)) { $inp = "$default" }
        if ($inp -notmatch '^\d+$') { Write-Warn "Ingresa solo numeros."; continue }
        $puerto = [int]$inp
        if ($puerto -ne 80 -and ($puerto -lt 100 -or $puerto -gt 65535)) {
            Write-Warn "Puerto fuera de rango. Usa 80 o entre 100 y 65535."
            continue
        }
        if (validarPuerto -puerto $puerto) {
            Write-Ok "Puerto $puerto aceptado."
            return $puerto
        } else {
            Write-Warn "Intenta con otro puerto."
        }
    }
}

# =============== FIREWALL ===============
function configurarFirewall {
    param([int]$puertoNuevo, [string]$nombreServicio = "HTTP")
    Write-Info "Configurando firewall..."
    # Limpiar reglas anteriores del mismo servicio
    Get-NetFirewallRule -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName -like "HTTP-$nombreServicio-*" } |
        Remove-NetFirewallRule -ErrorAction SilentlyContinue
    New-NetFirewallRule `
        -DisplayName "HTTP-$nombreServicio-$puertoNuevo" `
        -Direction Inbound -Protocol TCP -LocalPort $puertoNuevo `
        -Action Allow -Profile Any | Out-Null
    Write-Ok "Firewall: puerto $puertoNuevo abierto para $nombreServicio."
}

# =============== OBTENER NOMBRE DEL SO ===============
function Obtener-SistemaOS {
    $sistemaOS = "Windows Server 2022"
    try {
        $osInfo = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
        if ($osInfo) { $sistemaOS = $osInfo.Caption -replace 'Microsoft\s+', '' }
    } catch {
        try {
            $osInfo = Get-WmiObject Win32_OperatingSystem -ErrorAction SilentlyContinue
            if ($osInfo) { $sistemaOS = $osInfo.Caption -replace 'Microsoft\s+', '' }
        } catch { }
    }
    return $sistemaOS
}

# =============== CREAR INDEX.HTML (ESTILO ALPINE ROSITA) ===============
function crearHTML {
    param([string]$rutaWeb, [string]$servicio, [string]$version, [int]$puerto)
    if (-not (Test-Path $rutaWeb)) {
        New-Item -ItemType Directory -Path $rutaWeb -Force | Out-Null
    }
    $utf8NoBom = New-Object System.Text.UTF8Encoding $false
    $sistemaOS = Obtener-SistemaOS

    $contenido = @"
<!DOCTYPE html>
<html lang="es">
<head>
  <meta charset="UTF-8">
  <title>Servidor Web - $servicio</title>
  <style>
    body { 
      font-family: Arial, sans-serif; 
      background: linear-gradient(135deg, #FFB6C1, #FFC0CB); 
      display: flex; 
      justify-content: center; 
      align-items: center; 
      height: 100vh; 
      margin: 0; 
    }
    .card { 
      background: white; 
      border: 2px solid #FF69B4; 
      padding: 3rem 4rem;
      border-radius: 15px; 
      text-align: center; 
      box-shadow: 0 8px 16px rgba(0,0,0,0.1);
    }
    h1 { color: #FF1493; margin: 0 0 1.5rem 0; }
    p { color: #666; font-size: 1.2rem; margin: 0.5rem 0; }
    span { color: #FF69B4; font-weight: bold; }
  </style>
</head>
<body>
  <div class="card">
    <h1>Servidor HTTP Activo</h1>
    <p>Servidor: <span>$servicio</span></p>
    <p>Version: <span>$version</span></p>
    <p>Puerto: <span>$puerto</span></p>
    <p>Sistema: <span>$sistemaOS</span></p>
  </div>
</body>
</html>
"@
    [System.IO.File]::WriteAllText("$rutaWeb\index.html", $contenido, $utf8NoBom)
    Write-Ok "index.html creado en $rutaWeb"
}

# =============== BUSCAR RUTA NGINX ===============
function Obtener-Ruta-Nginx {
    $libPath = "C:\ProgramData\chocolatey\lib\nginx\tools"
    if (Test-Path $libPath) {
        $exe = Get-ChildItem $libPath -Filter "nginx.exe" -Recurse `
            -ErrorAction SilentlyContinue -Depth 3 | Select-Object -First 1
        if ($exe) { return $exe.DirectoryName }
    }
    if (Test-Path "C:\tools") {
        $exe = Get-ChildItem "C:\tools" -Filter "nginx.exe" -Recurse `
            -ErrorAction SilentlyContinue -Depth 5 | Select-Object -First 1
        if ($exe) { return $exe.DirectoryName }
    }
    foreach ($r in @("C:\nginx", "C:\nginx\nginx")) {
        if (Test-Path "$r\nginx.exe") { return $r }
    }
    $exe = Get-ChildItem "C:\" -Filter "nginx.exe" -Recurse `
        -ErrorAction SilentlyContinue -Depth 7 |
        Where-Object { $_.FullName -notlike "*\bin\*" } |
        Select-Object -First 1
    if ($exe) { return $exe.DirectoryName }
    return $null
}

# =============== DETENER SERVICIO PREVIO (RECURSIVIDAD) ===============
function Detener-Servicio-Previo {
    param([string]$patron, [string]$nombre)
    $servicios = Get-Service -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match $patron }
    foreach ($svc in $servicios) {
        if ($svc.Status -eq "Running") {
            Write-Info "Deteniendo servicio anterior: $($svc.Name)..."
            Stop-Service $svc.Name -Force -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 1
        }
    }
    # Matar procesos residuales
    $procs = Get-Process -Name $nombre -ErrorAction SilentlyContinue
    foreach ($p in $procs) {
        Write-Info "Matando proceso residual: $nombre (PID: $($p.Id))..."
        Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
    }
    Start-Sleep -Seconds 1
}

# =============== INSTALAR IIS ===============
function instalarIIS {
    param([int]$puerto)
    Write-Title "INSTALANDO / RECONFIGURANDO IIS"

    $winVer = Obtener-SistemaOS
    $iisVersion = switch -Wildcard ($winVer) {
        "*Server 2022*" { "10.0" } "*Server 2019*" { "10.0" }
        "*Server 2016*" { "10.0" } "*Server 2012*" { "8.5"  }
        "*Windows 1*"   { "10.0" } default          { "10.0" }
    }
    Write-Info "Sistema: $winVer"
    Write-Info "Version IIS disponible: $iisVersion"
    Write-Host ""
    $confirmar = Read-Host "  Instalar/reconfigurar IIS $iisVersion en puerto $puerto? (s/n)"
    if ($confirmar -ne 's') { Write-Warn "Instalacion cancelada."; return }

    # Detener IIS si ya esta corriendo (reinstalacion recursiva)
    $iisExistente = Get-Service W3SVC -ErrorAction SilentlyContinue
    if ($iisExistente) {
        if ($iisExistente.Status -eq "Running") {
            Write-Info "IIS ya activo, reconfigurando con puerto $puerto..."
            Stop-Service W3SVC -Force -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 2
        } else {
            Write-Info "IIS instalado pero detenido, reconfigurando..."
        }
    }

    # Instalar features si no estan
    $features = @("Web-Server","Web-Common-Http","Web-Static-Content",
                  "Web-Default-Doc","Web-Http-Errors","Web-Security",
                  "Web-Filtering","Web-Http-Logging","Web-Stat-Compression")
    foreach ($f in $features) {
        $estado = Get-WindowsFeature -Name $f -ErrorAction SilentlyContinue
        if ($estado -and -not $estado.Installed) {
            Install-WindowsFeature -Name $f -ErrorAction SilentlyContinue | Out-Null
        }
    }
    Write-Ok "Features IIS verificadas/instaladas."

    $appcmd = "$env:SystemRoot\system32\inetsrv\appcmd.exe"
    if (Test-Path $appcmd) {
        & $appcmd set site "Default Web Site" /bindings:"http/*:${puerto}:" 2>&1 | Out-Null
        Write-Ok "Puerto configurado: $puerto"
    } else {
        Write-Err "appcmd.exe no encontrado. Verifica la instalacion de IIS."
        return
    }

    $webroot = "$env:SystemDrive\inetpub\wwwroot"
    if (-not (Test-Path $webroot)) {
        New-Item -ItemType Directory -Path $webroot -Force | Out-Null
    }

    # web.config de seguridad
    $webConfig = "$webroot\web.config"
    $utf8NoBom = New-Object System.Text.UTF8Encoding $false
    $webConfigContent = @"
<?xml version="1.0" encoding="UTF-8"?>
<configuration>
  <system.webServer>
    <security>
      <requestFiltering removeServerHeader="true">
        <verbs>
          <add verb="TRACE" allowed="false" />
          <add verb="TRACK" allowed="false" />
        </verbs>
      </requestFiltering>
    </security>
    <httpProtocol>
      <customHeaders>
        <remove name="X-Powered-By" />
        <add name="X-Frame-Options"        value="SAMEORIGIN" />
        <add name="X-Content-Type-Options" value="nosniff"    />
      </customHeaders>
    </httpProtocol>
  </system.webServer>
</configuration>
"@
    [System.IO.File]::WriteAllText($webConfig, $webConfigContent, $utf8NoBom)
    Write-Ok "Seguridad configurada (web.config)."

    # Permisos
    $acl  = Get-Acl $webroot
    $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
        "IIS_IUSRS","ReadAndExecute","ContainerInherit,ObjectInherit","None","Allow")
    $acl.SetAccessRule($rule)
    Set-Acl $webroot $acl
    Write-Ok "Permisos aplicados: IIS_IUSRS -> ReadAndExecute."

    crearHTML -rutaWeb $webroot -servicio "IIS" -version $iisVersion -puerto $puerto
    configurarFirewall -puertoNuevo $puerto -nombreServicio "IIS"

    Start-Service W3SVC -ErrorAction SilentlyContinue
    Set-Service   W3SVC -StartupType Automatic -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 3

    $svc = Get-Service W3SVC -ErrorAction SilentlyContinue
    if ($svc -and $svc.Status -eq "Running") {
        Write-Ok "IIS activo en puerto $puerto"
    } else {
        Write-Err "IIS no arranco. Revisa el Visor de Eventos."
    }
}

# =============== INSTALAR APACHE ===============
function instalarApache {
    param([int]$puerto)
    Write-Title "INSTALANDO / RECONFIGURANDO APACHE HTTP SERVER"
    Asegurar-Chocolatey

    Write-Info "Consultando versiones disponibles de apache-httpd..."
    $rawVersiones = @()
    try {
        $rawVersiones = @(choco search apache-httpd --exact --all-versions --limit-output 2>$null)
    } catch { }
    $versiones = @()
    if ($rawVersiones -and $rawVersiones.Count -gt 0) {
        foreach ($linea in $rawVersiones) {
            if ($linea -and $linea -match '\|') {
                $ver = ($linea -split '\|')[1].Trim()
                if ($ver -match '^\d+\.\d+' -and $versiones -notcontains $ver) { $versiones += $ver }
            }
        }
    }
    if ($versiones.Count -eq 0) {
        Write-Err "No se encontraron versiones. Verifica internet."
        return
    }

    Write-Host ""
    Write-Host "  Versiones disponibles:" -ForegroundColor Magenta
    $limite = [Math]::Min($versiones.Count, 3)
    for ($i = 0; $i -lt $limite; $i++) {
        $etiqueta = switch ($i) {
            0 { "[Latest - Desarrollo]" } 1 { "[Estable anterior]" } 2 { "[LTS]" }
        }
        Write-Host "    $($i+1). $($versiones[$i])  $etiqueta" -ForegroundColor White
    }
    Write-Host ""
    do { $selVer = Read-Host "  Selecciona version (1-$limite)" } while ($selVer -notmatch "^[1-$limite]$")
    $versionElegida = $versiones[[int]$selVer - 1]

    # Detener Apache previo si existe (reinstalacion recursiva)
    Detener-Servicio-Previo -patron "^Apache" -nombre "httpd"

    Write-Info "Instalando Apache $versionElegida en puerto $puerto..."
    choco install apache-httpd `
        --version="$versionElegida" `
        --params="`"/port:$puerto /installLocation:C:\Apache24`"" `
        --yes --no-progress --force 2>&1 | Out-Null

    Refrescar-Path

    # Buscar donde quedo instalado (incluye ruta anidada Apache24\Apache24)
    $posibles = @("C:\Apache24\Apache24","C:\Apache24",
                  "$env:APPDATA\Apache24","$env:LOCALAPPDATA\Apache24",
                  "C:\ProgramData\chocolatey\lib\apache-httpd\tools\Apache24")
    $apacheRoot = $posibles | Where-Object { Test-Path "$_\bin\httpd.exe" } | Select-Object -First 1
    if (-not $apacheRoot) {
        $httpd = Get-ChildItem "C:\" -Filter "httpd.exe" -Recurse `
            -ErrorAction SilentlyContinue -Depth 6 | Select-Object -First 1
        if ($httpd) { $apacheRoot = $httpd.DirectoryName -replace '\\bin$','' }
    }
    if (-not $apacheRoot) {
        Write-Err "No se encontro la instalacion de Apache."
        return
    }
    Write-Ok "Apache instalado en: $apacheRoot"

    # Convertir ruta a formato Apache (barras normales)
    $apacheRootSlash = $apacheRoot -replace '\\','/'

    $httpdConf = "$apacheRoot\conf\httpd.conf"
    if (Test-Path $httpdConf) {
        $conf = Get-Content $httpdConf -Raw -Encoding UTF8
        # Corregir SRVROOT para que apunte a la ruta real de instalacion
        $conf = $conf -replace '(?m)^Define\s+SRVROOT\s+"[^"]+"', "Define SRVROOT `"$apacheRootSlash`""
        # Siempre reemplazar el puerto Listen
        $conf = $conf -replace 'Listen\s+\d+', "Listen $puerto"
        # Habilitar mod_headers si esta comentado (necesario para Header directives)
        $conf = $conf -replace '(?m)^#(LoadModule headers_module\s)', '$1'
        # Limpiar bloque de seguridad anterior si existe para evitar duplicados
        $conf = $conf -replace '(?s)\r?\n?# TAREA6-SECURITY-START.*?# TAREA6-SECURITY-END\r?\n?', ''
        # Escribir config limpia sin BOM
        $utf8NoBom = New-Object System.Text.UTF8Encoding $false
        [System.IO.File]::WriteAllText($httpdConf, $conf.TrimEnd(), $utf8NoBom)
        # Agregar bloque de seguridad fresco
        $secBlock = @"

# TAREA6-SECURITY-START
ServerTokens Prod
ServerSignature Off

<Directory "$apacheRootSlash/htdocs">
    <LimitExcept GET POST HEAD>
        Require all denied
    </LimitExcept>
</Directory>

Header always set X-Frame-Options "SAMEORIGIN"
Header always set X-Content-Type-Options "nosniff"
# TAREA6-SECURITY-END
"@
        [System.IO.File]::AppendAllText($httpdConf, $secBlock, $utf8NoBom)
        Write-Ok "Puerto $puerto y seguridad configurados en httpd.conf."
    } else {
        Write-Warn "httpd.conf no encontrado en $httpdConf"
    }

    crearHTML -rutaWeb "$apacheRoot\htdocs" -servicio "Apache HTTP Server" -version $versionElegida -puerto $puerto
    configurarFirewall -puertoNuevo $puerto -nombreServicio "Apache"

    # Registrar o reiniciar servicio
    $svc = Get-Service -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match "^Apache" } | Select-Object -First 1
    if (-not $svc) {
        $httpdExe = "$apacheRoot\bin\httpd.exe"
        if (Test-Path $httpdExe) {
            Write-Info "Registrando servicio Apache..."
            & $httpdExe -k install 2>&1 | Out-Null
            Start-Sleep -Seconds 2
            $svc = Get-Service -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -match "^Apache" } | Select-Object -First 1
        }
    }
    if ($svc) {
        # Verificar config antes de arrancar
        $httpdExeCheck = "$apacheRoot\bin\httpd.exe"
        if (Test-Path $httpdExeCheck) {
            $testResult = & $httpdExeCheck -t 2>&1
            if ($LASTEXITCODE -ne 0) {
                Write-Err "Error en httpd.conf: $testResult"
                Write-Info "Corrige la configuracion y vuelve a intentar."
                return
            }
            Write-Ok "Configuracion httpd.conf validada."
        }
        Start-Service $svc.Name -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 3
        $svc = Get-Service $svc.Name -ErrorAction SilentlyContinue
        if ($svc.Status -eq "Running") {
            Write-Ok "Apache activo en puerto $puerto"
        } else {
            Write-Err "Apache no arranco. Revisa: $apacheRoot\logs\error.log"
        }
    } else {
        Write-Err "No se pudo registrar el servicio Apache."
    }
}

# =============== INSTALAR NGINX ===============
function instalarNginx {
    param([int]$puerto)
    Write-Title "INSTALANDO / RECONFIGURANDO NGINX"
    Asegurar-Chocolatey

    Write-Info "Consultando versiones disponibles de Nginx..."
    $rawVersiones = @()
    try {
        $rawVersiones = @(choco search nginx --exact --all-versions --limit-output 2>$null)
    } catch { }
    $versiones = @()
    if ($rawVersiones -and $rawVersiones.Count -gt 0) {
        foreach ($linea in $rawVersiones) {
            if ($linea -and $linea -match '\|') {
                $ver = ($linea -split '\|')[1].Trim()
                if ($ver -match '^\d+\.\d+' -and $versiones -notcontains $ver) { $versiones += $ver }
            }
        }
    }
    if ($versiones.Count -eq 0) {
        Write-Err "No se encontraron versiones de Nginx."
        return
    }

    $mainline = $versiones | Where-Object {
        $p = $_ -split '\.'; $p.Count -ge 2 -and ([int]$p[1] % 2 -ne 0)
    } | Select-Object -First 1
    $stable = $versiones | Where-Object {
        $p = $_ -split '\.'; $p.Count -ge 2 -and ([int]$p[1] % 2 -eq 0)
    } | Select-Object -First 1
    if (-not $mainline) { $mainline = $versiones[0] }
    if (-not $stable)   { $stable   = if ($versiones.Count -ge 2) { $versiones[1] } else { $versiones[0] } }

    Write-Host ""
    Write-Host "  Versiones disponibles:" -ForegroundColor Magenta
    Write-Host "    1. $mainline  [Mainline - Desarrollo]" -ForegroundColor White
    Write-Host "    2. $stable    [Stable - LTS]" -ForegroundColor White
    Write-Host ""
    do { $selVer = Read-Host "  Selecciona version (1/2)" } while ($selVer -notmatch '^[12]$')
    $versionElegida = if ($selVer -eq "1") { $mainline } else { $stable }

    # Detener Nginx previo (reinstalacion recursiva)
    Detener-Servicio-Previo -patron "^nginx" -nombre "nginx"

    # Eliminar servicios NSSM previos de nginx
    if (Get-Command nssm -ErrorAction SilentlyContinue) {
        $svcsNginx = Get-Service -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match "^nginx" }
        foreach ($s in $svcsNginx) {
            Write-Info "Eliminando servicio anterior: $($s.Name)..."
            & nssm remove $s.Name confirm 2>&1 | Out-Null
        }
        Start-Sleep -Seconds 1
    }

    Write-Info "Instalando Nginx $versionElegida..."
    choco install nginx --version="$versionElegida" --yes --no-progress --force 2>&1 | Out-Null
    Refrescar-Path

    $nginxRootCheck = Obtener-Ruta-Nginx
    if (-not $nginxRootCheck) {
        Write-Err "No se encontro nginx.exe. Verifica la instalacion de Chocolatey."
        Write-Info "Intenta manualmente: choco install nginx --version=$versionElegida --force"
        return
    }
    Write-Ok "Nginx $versionElegida disponible en: $nginxRootCheck"

    if (-not (Get-Command nssm -ErrorAction SilentlyContinue)) {
        Write-Info "Instalando NSSM..."
        choco install nssm --yes --no-progress 2>&1 | Out-Null
        Refrescar-Path
    }

    $nginxRoot = Obtener-Ruta-Nginx
    if (-not $nginxRoot) { Write-Err "No se encontro nginx.exe tras la instalacion."; return }
    Write-Info "Nginx encontrado en: $nginxRoot"

    # Asegurar directorio de logs
    $logsDir = "$nginxRoot\logs"
    if (-not (Test-Path $logsDir)) {
        New-Item -ItemType Directory -Path $logsDir -Force | Out-Null
    }

    $nginxConf = "$nginxRoot\conf\nginx.conf"
    $utf8NoBom = New-Object System.Text.UTF8Encoding $false
    $nginxConfContent = @"
worker_processes  1;

events {
    worker_connections  1024;
}

http {
    include       mime.types;
    default_type  application/octet-stream;

    server_tokens off;

    sendfile        on;
    keepalive_timeout  65;

    server {
        listen       $puerto;
        server_name  localhost;

        add_header X-Frame-Options SAMEORIGIN always;
        add_header X-Content-Type-Options nosniff always;

        location / {
            root   html;
            index  index.html index.htm;
            autoindex off;
        }

        error_page   500 502 503 504  /50x.html;
        location = /50x.html {
            root   html;
        }
    }
}
"@
    [System.IO.File]::WriteAllText($nginxConf, $nginxConfContent, $utf8NoBom)
    Write-Ok "nginx.conf escrito sin BOM, puerto $puerto configurado."

    crearHTML -rutaWeb "$nginxRoot\html" -servicio "Nginx" -version $versionElegida -puerto $puerto
    configurarFirewall -puertoNuevo $puerto -nombreServicio "Nginx"

    $serviceName = "nginx-$puerto"
    $nginxExe    = "$nginxRoot\nginx.exe"

    # Limpiar servicio anterior con mismo nombre si existe
    $svcAnterior = Get-Service $serviceName -ErrorAction SilentlyContinue
    if ($svcAnterior) {
        Stop-Service $serviceName -Force -ErrorAction SilentlyContinue
        & nssm remove $serviceName confirm 2>&1 | Out-Null
        Start-Sleep -Seconds 1
    }

    & nssm install $serviceName $nginxExe 2>&1 | Out-Null
    & nssm set     $serviceName AppDirectory $nginxRoot 2>&1 | Out-Null
    & nssm set     $serviceName DisplayName "Nginx HTTP Server (puerto $puerto)" 2>&1 | Out-Null
    & nssm set     $serviceName Start SERVICE_AUTO_START 2>&1 | Out-Null
    & nssm set     $serviceName AppStdout "$logsDir\service.log" 2>&1 | Out-Null
    & nssm set     $serviceName AppStderr "$logsDir\service-error.log" 2>&1 | Out-Null

    Start-Service $serviceName -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 3
    $svc = Get-Service $serviceName -ErrorAction SilentlyContinue
    if ($svc -and $svc.Status -eq "Running") {
        Write-Ok "Nginx activo en puerto $puerto (servicio: $serviceName)"
    } else {
        Write-Err "Nginx no arranco. Revisa: $logsDir\error.log"
        Write-Info "O inicia manualmente: nssm start $serviceName"
    }
}

# =============== INSTALAR HTTP (MENU INTERNO - RECURSIVO) ===============
function InstalarHTTP {
    Clear-Host
    Write-Banner "INSTALACION DE SERVIDOR HTTP"
    Write-Host "    1. IIS  (nativo Windows)" -ForegroundColor White
    Write-Host "    2. Apache HTTP Server" -ForegroundColor White
    Write-Host "    3. Nginx" -ForegroundColor White
    Write-Host "    0. Volver" -ForegroundColor DarkMagenta
    Write-Linea
    Write-Host ""
    $s = Read-Host "  Servidor"
    if ($s -eq "0") { return }
    if ($s -notin @("1","2","3")) { Write-Warn "Opcion no valida."; return }
    $puerto = pedirPuerto -default 80
    switch ($s) {
        "1" { instalarIIS    -puerto $puerto }
        "2" { instalarApache -puerto $puerto }
        "3" { instalarNginx  -puerto $puerto }
    }
}

# =============== VERIFICAR ESTADO ===============
function VerificarHTTP {
    Clear-Host
    Write-Banner "ESTADO DE SERVIDORES HTTP"

    # --- IIS ---
    Write-Host -NoNewline "    IIS     : " -ForegroundColor Magenta
    $iis = Get-Service W3SVC -ErrorAction SilentlyContinue
    if ($iis) {
        $ver = $null
        try { $ver = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\InetStp" -ErrorAction SilentlyContinue).VersionString } catch {}
        if (-not $ver) { $ver = "N/A" }
        $appcmd = "$env:SystemRoot\system32\inetsrv\appcmd.exe"
        $puerto = 80
        if (Test-Path $appcmd) {
            $raw = & $appcmd list site "Default Web Site" 2>$null
            if ($raw -and $raw -match ':(\d+):') { $puerto = $Matches[1] }
        }
        if ($iis.Status -eq "Running") {
            Write-Host "Activo -- version: $ver -- puerto: $puerto" -ForegroundColor Green
        } else { Write-Host "Detenido -- version: $ver -- puerto: $puerto" -ForegroundColor Yellow }
    } else { Write-Host "No instalado" -ForegroundColor Red }

    # --- Apache ---
    Write-Host -NoNewline "    Apache  : " -ForegroundColor Magenta
    $apache = Get-Service -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match "^Apache" } | Select-Object -First 1
    if ($apache) {
        $apacheRoot = @("C:\Apache24\Apache24","C:\Apache24","$env:APPDATA\Apache24",
                        "C:\ProgramData\chocolatey\lib\apache-httpd\tools\Apache24") |
            Where-Object { Test-Path "$_\conf\httpd.conf" } | Select-Object -First 1
        $puerto = "?"
        if ($apacheRoot) {
            $match = Get-Content "$apacheRoot\conf\httpd.conf" -ErrorAction SilentlyContinue |
                Select-String '^Listen\s+(\d+)' | Select-Object -First 1
            if ($match) { $puerto = $match.Matches[0].Groups[1].Value }
        }
        if ($apache.Status -eq "Running") {
            Write-Host "Activo -- puerto: $puerto" -ForegroundColor Green
        } else { Write-Host "Detenido -- puerto: $puerto" -ForegroundColor Yellow }
    } else { Write-Host "No instalado" -ForegroundColor Red }

    # --- Nginx ---
    Write-Host -NoNewline "    Nginx   : " -ForegroundColor Magenta
    $nginx = Get-Service -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match "^nginx" } | Select-Object -First 1
    if ($nginx) {
        $nginxRoot = Obtener-Ruta-Nginx
        $puerto = "?"
        if ($nginxRoot -and (Test-Path "$nginxRoot\conf\nginx.conf")) {
            $match = Get-Content "$nginxRoot\conf\nginx.conf" -ErrorAction SilentlyContinue |
                Select-String 'listen\s+(\d+)' | Select-Object -First 1
            if ($match) { $puerto = $match.Matches[0].Groups[1].Value }
        }
        if ($nginx.Status -eq "Running") {
            Write-Host "Activo -- puerto: $puerto (servicio: $($nginx.Name))" -ForegroundColor Green
        } else { Write-Host "Detenido -- puerto: $puerto" -ForegroundColor Yellow }
    } else { Write-Host "No instalado" -ForegroundColor Red }

    Write-Host ""
}

# =============== REVISAR HTTP ===============
function RevisarHTTP {
    Clear-Host
    Write-Banner "REVISION DE SERVIDORES HTTP"
    Write-Host "    [1] IIS" -ForegroundColor White
    Write-Host "    [2] Apache" -ForegroundColor White
    Write-Host "    [3] Nginx" -ForegroundColor White
    Write-Host "    [4] Todos" -ForegroundColor White
    Write-Host ""
    $opcion = Read-Host "  Selecciona [1-4]"
    if ($opcion -notmatch '^[1234]$') { Write-Warn "Opcion invalida."; return }

    function Curl-Servidor {
        param([string]$nombre, [int]$puerto)
        Write-Host ""
        Write-Host "  --- $nombre (puerto $puerto) ---" -ForegroundColor Magenta
        Write-Host "  Headers:" -ForegroundColor DarkMagenta
        try {
            $resp = Invoke-WebRequest -Uri "http://localhost:$puerto" -Method Head `
                -UseBasicParsing -TimeoutSec 5 -ErrorAction Stop
            $resp.Headers.GetEnumerator() | ForEach-Object {
                Write-Host "    $($_.Key): $($_.Value)" -ForegroundColor White
            }
        } catch { Write-Err "Sin respuesta en puerto $puerto" }
        Write-Host "  Index:" -ForegroundColor DarkMagenta
        try {
            $resp = Invoke-WebRequest -Uri "http://localhost:$puerto" `
                -UseBasicParsing -TimeoutSec 5 -ErrorAction Stop
            Write-Host $resp.Content
        } catch { Write-Err "No se pudo obtener index de puerto $puerto" }
    }

    # Obtener puertos actuales
    $appcmd = "$env:SystemRoot\system32\inetsrv\appcmd.exe"
    $puertoIIS = 80
    if (Test-Path $appcmd) {
        $raw = & $appcmd list site "Default Web Site" 2>$null
        if ($raw -and $raw -match ':(\d+):') { $puertoIIS = [int]$Matches[1] }
    }

    $apacheRoot = @("C:\Apache24\Apache24","C:\Apache24","$env:APPDATA\Apache24",
                    "C:\ProgramData\chocolatey\lib\apache-httpd\tools\Apache24") |
        Where-Object { Test-Path "$_\conf\httpd.conf" } | Select-Object -First 1
    $puertoApache = 80
    if ($apacheRoot) {
        $match = Get-Content "$apacheRoot\conf\httpd.conf" -ErrorAction SilentlyContinue |
            Select-String '^Listen\s+(\d+)' | Select-Object -First 1
        if ($match) { $puertoApache = [int]$match.Matches[0].Groups[1].Value }
    }

    $nginxRoot = Obtener-Ruta-Nginx
    $puertoNginx = 80
    if ($nginxRoot -and (Test-Path "$nginxRoot\conf\nginx.conf")) {
        $match = Get-Content "$nginxRoot\conf\nginx.conf" -ErrorAction SilentlyContinue |
            Select-String 'listen\s+(\d+)' | Select-Object -First 1
        if ($match) { $puertoNginx = [int]$match.Matches[0].Groups[1].Value }
    }

    switch ($opcion) {
        "1" { Curl-Servidor "IIS"    $puertoIIS    }
        "2" { Curl-Servidor "Apache" $puertoApache }
        "3" { Curl-Servidor "Nginx"  $puertoNginx  }
        "4" {
            Curl-Servidor "IIS"    $puertoIIS
            Curl-Servidor "Apache" $puertoApache
            Curl-Servidor "Nginx"  $puertoNginx
        }
    }
}