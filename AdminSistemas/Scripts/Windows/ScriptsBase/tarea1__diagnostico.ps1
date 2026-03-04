Write-Host $env:COMPUTERNAME
Write-Host $env:COMPUTERNAME
Write-Host "IP actual:"
Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.IPAddress -notlike "169.*"}
Write-Host "Espacio en disco: "
Get-PSDrive C
