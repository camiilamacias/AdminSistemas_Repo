Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ========= CONFIG =========
$FTP_ROOT = "C:\ftp"
$FTP_GENERAL = Join-Path $FTP_ROOT "general"
$FTP_GROUPS  = Join-Path $FTP_ROOT "grupos"
$FTP_USERS   = Join-Path $FTP_ROOT "usuarios"

$GRP_REP = "reprobados"
$GRP_REC = "recursadores"

$SITE = "ServidorFTP"
$FTP_PORT = 21

# PASV debe coincidir con tu Port Forwarding de VirtualBox
$PASV_LOW  = 50020
$PASV_HIGH = 50030

# ========= Helpers (SIDs para evitar errores de idioma) =========
function Resolve-SID([string]$sid) {
    (New-Object System.Security.Principal.SecurityIdentifier($sid)).Translate([System.Security.Principal.NTAccount]).Value
}

$ID_ADMINS = Resolve-SID "S-1-5-32-544"  # Administrators
$ID_SYSTEM = Resolve-SID "S-1-5-18"      # SYSTEM
$ID_AUTH   = Resolve-SID "S-1-5-11"      # Authenticated Users
# Para anónimo IIS: suele ser IUSR, pero no siempre existe como nombre -> lo resolvemos si existe
function Try-GetIUSR {
    try { return (Get-LocalUser -Name "IUSR" -ErrorAction Stop).Name } catch { return $null }
}

function Pause { Read-Host "Enter para continuar" | Out-Null }

function Ensure-Admin {
    $p = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
    if (-not $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw "Ejecuta como Administrador."
    }
}

function Set-AclClean {
    param(
        [Parameter(Mandatory=$true)][string]$Path,
        [Parameter(Mandatory=$true)][System.Security.AccessControl.FileSystemAccessRule[]]$Rules
    )
    $acl = Get-Acl $Path
    $acl.SetAccessRuleProtection($true,$false)
    foreach ($r in $acl.Access) { $acl.RemoveAccessRule($r) | Out-Null }
    foreach ($r in $Rules) { $acl.AddAccessRule($r) | Out-Null }
    Set-Acl -Path $Path -AclObject $acl
}

function Rule($Identity, $Rights="FullControl") {
    New-Object System.Security.AccessControl.FileSystemAccessRule(
        $Identity, $Rights, "ContainerInherit,ObjectInherit", "None", "Allow"
    )
}

function RuleNoInherit($Identity, $Rights="FullControl") {
    New-Object System.Security.AccessControl.FileSystemAccessRule(
        $Identity, $Rights, "None", "None", "Allow"
    )
}

# ========= FTP Functions =========
function Ftp-Verify {
    Write-Host "=== FTP VERIFY (Windows IIS) ===" -ForegroundColor Magenta
    $iis = Get-WindowsFeature -Name Web-Server -ErrorAction SilentlyContinue
    $ftp = Get-WindowsFeature -Name Web-Ftp-Server -ErrorAction SilentlyContinue
    Write-Host ("IIS:  " + ($iis.Installed)) -ForegroundColor Magenta
    Write-Host ("FTP:  " + ($ftp.Installed)) -ForegroundColor Magenta

    $svc = Get-Service ftpsvc -ErrorAction SilentlyContinue
    if ($svc) { Write-Host ("ftpsvc: " + $svc.Status) -ForegroundColor Magenta }

    Write-Host ("Ruta FTP: " + $FTP_ROOT) -ForegroundColor Magenta
    Write-Host ("PASV: {0}-{1}" -f $PASV_LOW, $PASV_HIGH) -ForegroundColor Magenta
}

function Ftp-InstallPrepare {
    Write-Host "=== FTP PREPARAR/INSTALAR (IDEMPOTENTE) ===" -ForegroundColor Magenta

    Install-WindowsFeature -Name Web-Server, Web-Ftp-Server, Web-Ftp-Service, Web-Mgmt-Console -IncludeManagementTools | Out-Null
    Import-Module WebAdministration -ErrorAction Stop

    # Grupos
    if (-not (Get-LocalGroup -Name $GRP_REP -ErrorAction SilentlyContinue)) { New-LocalGroup -Name $GRP_REP | Out-Null }
    if (-not (Get-LocalGroup -Name $GRP_REC -ErrorAction SilentlyContinue)) { New-LocalGroup -Name $GRP_REC | Out-Null }

    # Estructura base
    New-Item -ItemType Directory -Force -Path $FTP_GENERAL | Out-Null
    New-Item -ItemType Directory -Force -Path (Join-Path $FTP_GROUPS $GRP_REP) | Out-Null
    New-Item -ItemType Directory -Force -Path (Join-Path $FTP_GROUPS $GRP_REC) | Out-Null
    New-Item -ItemType Directory -Force -Path $FTP_USERS | Out-Null

    # ACLs base:
    # general: Authenticated Users Modify, anónimo Read (si existe IUSR)
    $rulesGeneral = @(
        (Rule $ID_ADMINS "FullControl"),
        (Rule $ID_SYSTEM "FullControl"),
        (Rule $ID_AUTH   "Modify")
    )
    $iusr = Try-GetIUSR
    if ($iusr) { $rulesGeneral += (Rule $iusr "ReadAndExecute") }
    Set-AclClean -Path $FTP_GENERAL -Rules $rulesGeneral

    # carpetas de grupo: Modify SOLO para el grupo
    foreach ($g in @($GRP_REP,$GRP_REC)) {
        $p = Join-Path $FTP_GROUPS $g
        Set-AclClean -Path $p -Rules @(
            (Rule $ID_ADMINS "FullControl"),
            (Rule $ID_SYSTEM "FullControl"),
            (Rule $g         "Modify")
        )
    }

    # PASV
    Set-WebConfigurationProperty -PSPath "IIS:\" -Filter "system.ftpServer/firewallSupport" -Name "lowDataChannelPort"  -Value $PASV_LOW
    Set-WebConfigurationProperty -PSPath "IIS:\" -Filter "system.ftpServer/firewallSupport" -Name "highDataChannelPort" -Value $PASV_HIGH

    # Sitio FTP
    if (Get-WebSite -Name $SITE -ErrorAction SilentlyContinue) { Remove-WebSite -Name $SITE }
    New-WebFtpSite -Name $SITE -Port $FTP_PORT -PhysicalPath $FTP_ROOT -Force | Out-Null

    # Auth basic + anonymous
    Set-ItemProperty "IIS:\Sites\$SITE" -Name "ftpServer.security.authentication.basicAuthentication.enabled" -Value $true
    Set-ItemProperty "IIS:\Sites\$SITE" -Name "ftpServer.security.authentication.anonymousAuthentication.enabled" -Value $true

    # SSL: permitir texto plano (laboratorio)
    Set-ItemProperty "IIS:\Sites\$SITE" -Name "ftpServer.security.ssl.controlChannelPolicy" -Value "SslAllow"
    Set-ItemProperty "IIS:\Sites\$SITE" -Name "ftpServer.security.ssl.dataChannelPolicy"    -Value "SslAllow"

    # Reglas de autorización IIS: anónimo lectura / autenticados lectura+escritura
    Clear-WebConfiguration "/system.ftpServer/security/authorization" -PSPath "IIS:\" -Location $SITE -ErrorAction SilentlyContinue | Out-Null
    Add-WebConfiguration "/system.ftpServer/security/authorization" -PSPath "IIS:\" -Location $SITE -Value @{ accessType="Allow"; users="?"; roles=""; permissions=1 } | Out-Null
    Add-WebConfiguration "/system.ftpServer/security/authorization" -PSPath "IIS:\" -Location $SITE -Value @{ accessType="Allow"; users="*"; roles=""; permissions=3 } | Out-Null

    # Firewall
    if (-not (Get-NetFirewallRule -DisplayName "FTP Puerto 21" -ErrorAction SilentlyContinue)) {
        New-NetFirewallRule -DisplayName "FTP Puerto 21" -Direction Inbound -Protocol TCP -LocalPort 21 -Action Allow | Out-Null
    }
    $ruleName = "FTP Pasivo $PASV_LOW-$PASV_HIGH"
    if (-not (Get-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue)) {
        New-NetFirewallRule -DisplayName $ruleName -Direction Inbound -Protocol TCP -LocalPort "$PASV_LOW-$PASV_HIGH" -Action Allow | Out-Null
    }

    Restart-Service ftpsvc -Force
    Write-Host "[OK] FTP preparado." -ForegroundColor Green
}

function Ensure-Jail {
    param(
        [Parameter(Mandatory=$true)][string]$User,
        [Parameter(Mandatory=$true)][ValidateSet("reprobados","recursadores")][string]$Group
    )

    $UserHome = Join-Path $FTP_USERS $User
    $Personal = Join-Path $UserHome $User

    New-Item -ItemType Directory -Force -Path $UserHome  | Out-Null
    New-Item -ItemType Directory -Force -Path $Personal  | Out-Null

    # junction general
    $jGen = Join-Path $UserHome "general"
    if (-not (Test-Path $jGen)) { cmd /c "mklink /J `"$jGen`" `"$FTP_GENERAL`"" | Out-Null }

    # junction group
    $jGrp = Join-Path $UserHome $Group
    if (-not (Test-Path $jGrp)) { cmd /c "mklink /J `"$jGrp`" `"$FTP_GROUPS\$Group`"" | Out-Null }

    # quitar el otro grupo si existe
    $other = if ($Group -eq $GRP_REP) { $GRP_REC } else { $GRP_REP }
    $jOther = Join-Path $UserHome $other
    if (Test-Path $jOther) { cmd /c "rmdir `"$jOther`"" | Out-Null }

    # ACL home: user RX
    Set-AclClean -Path $UserHome -Rules @(
        (Rule $ID_ADMINS "FullControl"),
        (Rule $ID_SYSTEM "FullControl"),
        (Rule $User      "ReadAndExecute")
    )

    # ACL personal: user Modify
    Set-AclClean -Path $Personal -Rules @(
        (Rule $ID_ADMINS "FullControl"),
        (Rule $ID_SYSTEM "FullControl"),
        (Rule $User      "Modify")
    )
}

function Ftp-CreateUsers {
    Write-Host "=== CREAR USUARIOS FTP (n) ===" -ForegroundColor Magenta
    $n = Read-Host "¿Cuántos usuarios crear?"
    if (-not ($n -match '^\d+$') -or [int]$n -lt 1) { Write-Host "Número inválido" -ForegroundColor Yellow; return }

    for ($i=1; $i -le [int]$n; $i++) {
        Write-Host "`n--- Usuario $i de $n ---" -ForegroundColor Magenta
        $user = Read-Host "Usuario"
        $pass = Read-Host "Contraseña"
        Write-Host "Grupo: 1) reprobados  2) recursadores" -ForegroundColor Magenta
        $gop = Read-Host "Elige 1 o 2"
        $grp = if ($gop -eq "2") { $GRP_REC } else { $GRP_REP }

        $sec = ConvertTo-SecureString $pass -AsPlainText -Force
        if (-not (Get-LocalUser -Name $user -ErrorAction SilentlyContinue)) {
            New-LocalUser -Name $user -Password $sec -PasswordNeverExpires -UserMayNotChangePassword | Out-Null
        } else {
            Set-LocalUser -Name $user -Password $sec
        }

        # dejarlo en solo un grupo
        Remove-LocalGroupMember -Group $GRP_REP -Member $user -ErrorAction SilentlyContinue
        Remove-LocalGroupMember -Group $GRP_REC -Member $user -ErrorAction SilentlyContinue
        Add-LocalGroupMember -Group $grp -Member $user -ErrorAction SilentlyContinue

        Ensure-Jail -User $user -Group $grp
        Write-Host ("[OK] {0} creado en {1}" -f $user, $grp) -ForegroundColor Green
    }
}

function Ftp-ChangeGroup {
    Write-Host "=== CAMBIAR GRUPO ===" -ForegroundColor Magenta
    $user = Read-Host "Usuario"
    if (-not (Get-LocalUser -Name $user -ErrorAction SilentlyContinue)) { Write-Host "No existe" -ForegroundColor Yellow; return }

    $inRep = Get-LocalGroupMember -Group $GRP_REP -ErrorAction SilentlyContinue | Where-Object { $_.Name -match "\\$user$" }
    $old = if ($inRep) { $GRP_REP } else { $GRP_REC }
    $new = if ($old -eq $GRP_REP) { $GRP_REC } else { $GRP_REP }

    Remove-LocalGroupMember -Group $old -Member $user -ErrorAction SilentlyContinue
    Add-LocalGroupMember -Group $new -Member $user -ErrorAction SilentlyContinue

    Ensure-Jail -User $user -Group $new
    Write-Host ("[OK] {0}: {1} -> {2}" -f $user, $old, $new) -ForegroundColor Green
}

function Ftp-Menu {
    Ensure-Admin

    while ($true) {
        Write-Host ""
        Write-Host "===================================" -ForegroundColor Magenta
        Write-Host "      FTP (IIS) - WINDOWS MENU      " -ForegroundColor Magenta
        Write-Host "===================================" -ForegroundColor Magenta
        Write-Host "[1] Verificar" -ForegroundColor Magenta
        Write-Host "[2] Preparar/Instalar (idempotente)" -ForegroundColor Magenta
        Write-Host "[3] Crear usuarios (n)" -ForegroundColor Magenta
        Write-Host "[4] Cambiar grupo usuario" -ForegroundColor Magenta
        Write-Host "[0] Volver" -ForegroundColor Magenta
        $op = Read-Host "Opción"

        switch ($op) {
            "1" { Ftp-Verify; Pause }
            "2" { Ftp-InstallPrepare; Pause }
            "3" { Ftp-CreateUsers; Pause }
            "4" { Ftp-ChangeGroup; Pause }
            "0" { return }
            default { Write-Host "Opción inválida" -ForegroundColor Yellow }
        }
    }
}

# ENTRY
Ftp-Menu