Set-StrictMode -Version Latest

function Validar-IPv4 {
    param([string]$Mensaje, [bool]$Opcional = $false)

    do {
        $ip = Read-Host $Mensaje
        if ($Opcional -and [string]::IsNullOrWhiteSpace($ip)) { return $null }

        if ($ip -match '^((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$') {
            $oct = $ip.Split('.')
            foreach ($o in $oct) {
                if ($o.Length -gt 1 -and $o.StartsWith("0")) {
                    Write-Host "error: no ceros a la izquierda" -ForegroundColor Magenta
                    $ip = $null
                    break
                }
            }
            if ($ip) { return $ip }
        }
        Write-Host "Formato IPv4 inválido. Reintente." -ForegroundColor Magenta
    } while ($true)
}