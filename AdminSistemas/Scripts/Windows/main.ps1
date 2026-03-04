Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# BaseDir = carpeta donde vive este main.ps1 (Z:\)
$BaseDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# Cargar librerías SIEMPRE desde la ruta del script (no depende del directorio actual)
. "$BaseDir\lib\Common.ps1"
. "$BaseDir\lib\SshFunctions.ps1"
. "$BaseDir\lib\DhcpFunctions.ps1"
. "$BaseDir\lib\DnsFunctions.ps1"

function Assert-FunctionExists {
    param([string]$Name)
    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "FALTA la función '$Name'. Revisa lib\*.ps1 (no se cargó o no existe)."
    }
}

# Validar que existen las funciones que el menú llama (evita errores raros)
$required = @(
    "Dhcp-VerificarInstalacion","Dhcp-Instalar","Dhcp-Configurar","Dhcp-Monitoreo",
    "Dns-ConfigurarZona","Dns-BorrarZona","Dns-Monitoreo",
    "Ssh-Install","Ssh-Status"
)
$required | ForEach-Object { Assert-FunctionExists $_ }

function Menu {
    Write-Host "============================================" -ForegroundColor Magenta
    Write-Host "      MAIN - ADMIN SISTEMAS (WINDOWS)       " -ForegroundColor Magenta
    Write-Host "============================================" -ForegroundColor Magenta
    Write-Host "[1] DHCP - Verificar" -ForegroundColor Magenta
    Write-Host "[2] DHCP - Instalar" -ForegroundColor Magenta
    Write-Host "[3] DHCP - Configurar" -ForegroundColor Magenta
    Write-Host "[4] DHCP - Monitoreo" -ForegroundColor Magenta
    Write-Host "[5] DNS  - Configurar Zona/Registro" -ForegroundColor Magenta
    Write-Host "[6] DNS  - Borrar Zona" -ForegroundColor Magenta
    Write-Host "[7] DNS  - Monitoreo" -ForegroundColor Magenta
    Write-Host "[8] SSH  - Instalar/Configurar" -ForegroundColor Magenta
    Write-Host "[9] SSH  - Estado" -ForegroundColor Magenta
    Write-Host "[0] Salir" -ForegroundColor Magenta
}

do {
    Menu
    $op = Read-Host "Opción"
    switch ($op) {
        "1" { Dhcp-VerificarInstalacion }
        "2" { Dhcp-Instalar }
        "3" { Dhcp-Configurar }
        "4" { Dhcp-Monitoreo }
        "5" { Dns-ConfigurarZona }
        "6" { Dns-BorrarZona }
        "7" { Dns-Monitoreo }
        "8" { Ssh-Install }
        "9" { Ssh-Status }
        "0" { break }
        default { Write-Host "Opción inválida" -ForegroundColor Magenta }
    }
    if ($op -ne "0") { Read-Host "Enter para continuar" | Out-Null }
} while ($true)