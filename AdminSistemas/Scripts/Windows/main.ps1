Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$BaseDir = Split-Path -Parent $MyInvocation.MyCommand.Path

. "$BaseDir\lib\Common.ps1"
. "$BaseDir\lib\SshFunctions.ps1"
. "$BaseDir\lib\DhcpFunctions.ps1"
. "$BaseDir\lib\DnsFunctions.ps1"

# FTP: un solo script (no librería)
$FtpScript = Join-Path $BaseDir "ScriptsBase\ftp_main.ps1"

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
    Write-Host "[10] FTP - Menu" -ForegroundColor Magenta
    Write-Host "[0] Salir" -ForegroundColor Magenta
}

do {
    Menu
    $op = Read-Host "Opcion"
    switch ($op) {
        "1"  { Dhcp-VerificarInstalacion }
        "2"  { Dhcp-Instalar }
        "3"  { Dhcp-Configurar }
        "4"  { Dhcp-Monitoreo }
        "5"  { Dns-ConfigurarZona }
        "6"  { Dns-BorrarZona }
        "7"  { Dns-Monitoreo }
        "8"  { Ssh-Install }
        "9"  { Ssh-Status }
        "10" {
            if (-not (Test-Path $FtpScript)) {
                Write-Host "No existe: $FtpScript" -ForegroundColor Red
            } else {
                & powershell -ExecutionPolicy Bypass -File $FtpScript
            }
        }
        "0"  { break }
        default { Write-Host "Opcion invalida" -ForegroundColor Magenta }
    }

    if ($op -ne "0") { Read-Host "Enter para continuar" | Out-Null }
} while ($true)