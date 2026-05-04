<#
    Sovereign-cloud fallback installer for the SHIR shim.

    Only used when var.shir_install_method = "CustomScript" because DSC pull
    from `wpr.azure.com` is unreliable for some Azure Government egress
    profiles. The DSC path is preferred: it self-heals when the SHIR auth
    key is rotated and survives reboots without manual intervention.

    Invoked by the Custom Script extension defined in main.tf with the
    SHIR primary auth key passed via -AuthorizationKey.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string] $AuthorizationKey,

    [string] $InstallerUrl = 'https://download.microsoft.com/download/E/4/7/E4771905-1079-445B-8BF9-8A1A075D8A10/IntegrationRuntime_5.x.msi'
)

$ErrorActionPreference = 'Stop'
$msi = 'C:\Windows\Temp\IntegrationRuntime.msi'

Write-Host "Downloading SHIR installer from $InstallerUrl ..."
Invoke-WebRequest -Uri $InstallerUrl -OutFile $msi -UseBasicParsing

Write-Host 'Installing SHIR (silent) ...'
$proc = Start-Process -FilePath 'msiexec.exe' -ArgumentList @('/i', $msi, '/quiet', '/norestart') -Wait -PassThru
if ($proc.ExitCode -ne 0) {
    throw "msiexec exited with $($proc.ExitCode)"
}

$dmgcmd = 'C:\Program Files\Microsoft Integration Runtime\5.0\Shared\dmgcmd.exe'
if (-not (Test-Path $dmgcmd)) {
    throw "dmgcmd.exe not found at $dmgcmd; SHIR install failed."
}

Write-Host 'Registering node with the supplied auth key ...'
& $dmgcmd -RegisterNewNode $AuthorizationKey
if ($LASTEXITCODE -ne 0) {
    throw "dmgcmd -RegisterNewNode failed with exit code $LASTEXITCODE."
}

Write-Host 'SHIR registered. Done.'
