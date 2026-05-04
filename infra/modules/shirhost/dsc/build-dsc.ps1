<#
    Build script for the InstallShir DSC configuration.

    Compiles InstallShir.ps1 into a MOF, packages the MOF + xPSDesiredStateConfiguration
    module dependency into InstallShir.zip, and prints the SHA256 hash.

    Run locally before `terraform apply` whenever InstallShir.ps1 changes:
        pwsh ./build-dsc.ps1

    CI runs this same script in the `terraform-validate` job and verifies the
    SHA256 matches the committed InstallShir.zip to catch drift between the
    source and the compiled artifact.
#>

#requires -Version 7.0

[CmdletBinding()]
param(
    [string] $OutputDirectory = $PSScriptRoot
)

$ErrorActionPreference = 'Stop'

$workDir = Join-Path -Path $OutputDirectory -ChildPath '_build'
if (Test-Path $workDir) { Remove-Item -Recurse -Force $workDir }
New-Item -ItemType Directory -Force -Path $workDir | Out-Null

# Install required DSC module dependency into the work directory.
Save-Module -Name 'xPSDesiredStateConfiguration' -Path $workDir -Force

# Dot-source the configuration and compile the MOF.
. (Join-Path $PSScriptRoot 'InstallShir.ps1')
$mofRoot = Join-Path $workDir 'mof'
InstallShir `
    -InstallerUrl 'https://placeholder/' `
    -ShirAuthorizationKey 'placeholder' `
    -OutputPath $mofRoot | Out-Null

# Package: the MOF plus the module folder into a single zip the DSC
# extension can consume via ModulesUrl.
$zipPath = Join-Path $OutputDirectory 'InstallShir.zip'
if (Test-Path $zipPath) { Remove-Item -Force $zipPath }

Compress-Archive -Path "$mofRoot\*", "$workDir\xPSDesiredStateConfiguration" -DestinationPath $zipPath -Force

$hash = (Get-FileHash -Path $zipPath -Algorithm SHA256).Hash
Write-Host "Built: $zipPath"
Write-Host "SHA256: $hash"

# Emit a sidecar hash file so CI can compare without re-running the build.
$hash | Out-File -FilePath "$zipPath.sha256" -Encoding ascii
