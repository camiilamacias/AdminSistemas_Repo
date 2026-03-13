# =============================================================================
# Main.ps1 - Script principal de aprovisionamiento web
# SO: Windows Server 2022
# Uso: .\Main.ps1 [-Install] [-Verify] [-Review]
# =============================================================================

param([switch]$Install, [switch]$Verify, [switch]$Review, [switch]$Help)

. .\lib\Utils.ps1
. .\lib\HttpFunctions.ps1

function Menu-Principal {
    while ($true) {
        Clear-Host
        Print-Title "Aprovisionamiento Web Automatizado"
        Print-Menu "  [1] Instalar servidor HTTP"
        Print-Menu "  [2] Ver estado de servidores"
        Print-Menu "  [3] Revisar respuesta HTTP (curl)"
        Print-Menu "  [0] Salir"
        Write-Host ""
        Write-Host "Selecciona una opcion: " -ForegroundColor Magenta -NoNewline
        $opcion = Read-Host
        switch ($opcion) {
            "1" { Menu-Instalacion }
            "2" { Verificar-HTTP; Pausar }
            "3" { Revisar-HTTP; Pausar }
            "0" { Print-Success "Saliendo..."; exit 0 }
            default { Print-Warning "Opcion invalida." }
        }
    }
}

function Menu-Instalacion {
    Clear-Host
    Print-Title "Instalar Servidor HTTP"
    Print-Menu "  [1] IIS (Obligatorio)"
    Print-Menu "  [2] Apache2"
    Print-Menu "  [3] Nginx"
    Print-Menu "  [0] Volver"
    Write-Host ""
    Write-Host "Selecciona un servidor: " -ForegroundColor Magenta -NoNewline
    $opcion = Read-Host
    switch ($opcion) {
        "1" { Setup-IIS; Pausar }
        "2" { Setup-Apache; Pausar }
        "3" { Setup-Nginx; Pausar }
        "0" { return }
        default { Print-Warning "Opcion invalida."; Pausar }
    }
}

Verificar-Admin

if ($Install) {
    Menu-Instalacion
} elseif ($Verify) {
    Verificar-HTTP; Pausar
} elseif ($Review) {
    Revisar-HTTP; Pausar
} elseif ($Help) {
    Write-Host ""; Write-Host "USO:" -ForegroundColor Magenta
    Print-Menu "  .\Main.ps1           Menu interactivo"
    Print-Menu "  .\Main.ps1 -Install  Instalar servidor HTTP"
    Print-Menu "  .\Main.ps1 -Verify   Ver estado de servidores"
    Print-Menu "  .\Main.ps1 -Review   Revisar respuesta HTTP"
    Print-Menu "  .\Main.ps1 -Help     Mostrar esta ayuda"
    Write-Host ""
} else {
    Menu-Principal
}