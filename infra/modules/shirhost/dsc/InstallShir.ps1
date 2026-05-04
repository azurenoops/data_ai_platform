Configuration InstallShir
{
    param(
        [Parameter(Mandatory = $true)]
        [string] $InstallerUrl,

        [Parameter(Mandatory = $true)]
        [string] $ShirAuthorizationKey
    )

    Import-DscResource -ModuleName 'PSDesiredStateConfiguration' -ModuleVersion 1.1
    Import-DscResource -ModuleName 'xPSDesiredStateConfiguration'

    Node 'localhost'
    {
        # 1) Optional AD tooling so the operator can later domain-join.
        WindowsFeature 'RSAT-AD-Tools'
        {
            Ensure = 'Present'
            Name   = 'RSAT-AD-Tools'
        }

        # 2) Download the SHIR installer to a deterministic path.
        xRemoteFile 'DownloadShirMsi'
        {
            Uri             = $InstallerUrl
            DestinationPath = 'C:\Windows\Temp\IntegrationRuntime.msi'
            MatchSource     = $false
        }

        # 3) Install the MSI silently.
        Package 'InstallShirMsi'
        {
            Ensure    = 'Present'
            Name      = 'Microsoft Integration Runtime'
            Path      = 'C:\Windows\Temp\IntegrationRuntime.msi'
            ProductId = '' # Detected by Name / installation receipt.
            Arguments = '/quiet /norestart'
            DependsOn = '[xRemoteFile]DownloadShirMsi'
        }

        # 4) Register the SHIR with the supplied auth key. Idempotent: skip
        #    when DIAHostService already running and dmgcmd reports a node ID.
        Script 'RegisterShir'
        {
            GetScript  = {
                $svc = Get-Service -Name 'DIAHostService' -ErrorAction SilentlyContinue
                @{ Result = if ($svc) { $svc.Status.ToString() } else { 'NotInstalled' } }
            }
            TestScript = {
                $svc = Get-Service -Name 'DIAHostService' -ErrorAction SilentlyContinue
                if (-not $svc -or $svc.Status -ne 'Running') { return $false }
                $dmgcmd = 'C:\Program Files\Microsoft Integration Runtime\5.0\Shared\dmgcmd.exe'
                if (-not (Test-Path $dmgcmd)) { return $false }
                $status = & $dmgcmd -Status 2>&1
                return ($LASTEXITCODE -eq 0 -and $status -match 'Connected')
            }
            SetScript  = {
                $dmgcmd = 'C:\Program Files\Microsoft Integration Runtime\5.0\Shared\dmgcmd.exe'
                & $dmgcmd -RegisterNewNode $using:ShirAuthorizationKey
                if ($LASTEXITCODE -ne 0) {
                    throw "dmgcmd -RegisterNewNode failed with exit code $LASTEXITCODE."
                }
            }
            DependsOn  = '[Package]InstallShirMsi'
        }

        # 5) Make sure the service is running.
        Service 'DIAHostService'
        {
            Name      = 'DIAHostService'
            State     = 'Running'
            DependsOn = '[Script]RegisterShir'
        }
    }
}
