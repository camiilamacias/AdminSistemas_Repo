function Ssh-Install {
    $cap = Get-WindowsCapability -Online | Where-Object Name -like 'OpenSSH.Server*'
    if ($cap.State -ne "Installed") {
        Add-WindowsCapability -Online -Name $cap.Name
    }
    Set-Service -Name sshd -StartupType Automatic
    Start-Service -Name sshd

    $rule = Get-NetFirewallRule -DisplayName "OpenSSH-Server-In-TCP" -ErrorAction SilentlyContinue
    if ($rule) {
        Set-NetFirewallRule -DisplayName "OpenSSH-Server-In-TCP" -Enabled True
    } else {
        New-NetFirewallRule -Name "OpenSSH-Server-In-TCP-22" -DisplayName "OpenSSH-Server-In-TCP-22" `
          -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22
    }

    Write-Host "SSH listo en Windows." -ForegroundColor Green
}

function Ssh-Status {
    Get-Service sshd | Format-List Status,StartType,Name
    Get-NetFirewallRule -DisplayName "OpenSSH-Server-In-TCP" -ErrorAction SilentlyContinue | Format-List DisplayName,Enabled
}