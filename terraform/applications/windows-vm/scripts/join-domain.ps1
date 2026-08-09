# Joins the machine to an Active Directory domain and restarts it.
#
# Runs on the machine through the Azure Run Command service. The join
# account's credentials are fetched here, at runtime, from the platform
# key vault using the machine's system-assigned managed identity - they
# never pass through Terraform, its state, or the run command
# parameters. The machine reaches the vault through its private
# endpoint and needs the Key Vault Secrets User role, which the
# deployment grants.
param(
    [Parameter(Mandatory = $true)][string]$DomainName,
    [string]$OUPath,
    [Parameter(Mandatory = $true)][string]$VaultName,
    [Parameter(Mandatory = $true)][string]$UsernameSecretName,
    [Parameter(Mandatory = $true)][string]$PasswordSecretName
)

$ErrorActionPreference = 'Stop'

$computer = Get-CimInstance -ClassName Win32_ComputerSystem
if ($computer.PartOfDomain -and $computer.Domain -eq $DomainName) {
    Write-Output "Already joined to $DomainName, nothing to do."
    exit 0
}

# Retries a request with linear backoff. On a first deployment the
# machine's Key Vault Secrets User role assignment can take a few
# minutes to propagate to the vault's data plane, so early reads may
# see transient 403s.
function Invoke-WithRetry {
    param(
        [Parameter(Mandatory = $true)][scriptblock]$Action,
        [int]$Attempts = 10,
        [int]$DelaySeconds = 30
    )

    for ($attempt = 1; $attempt -le $Attempts; $attempt++) {
        try {
            return & $Action
        }
        catch {
            if ($attempt -eq $Attempts) {
                throw
            }
            Write-Output "Attempt $attempt of $Attempts failed ($($_.Exception.Message)), retrying in $DelaySeconds seconds."
            Start-Sleep -Seconds $DelaySeconds
        }
    }
}

# Acquire a Key Vault token from the Instance Metadata Service with the
# machine's system-assigned managed identity.
$tokenResponse = Invoke-WithRetry {
    Invoke-RestMethod `
        -Headers @{ Metadata = 'true' } `
        -Uri 'http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=https%3A%2F%2Fvault.azure.net'
}

$authHeader = @{ Authorization = "Bearer $($tokenResponse.access_token)" }
$vaultUri = "https://$VaultName.vault.azure.net"

$username = (Invoke-WithRetry {
        Invoke-RestMethod -Headers $authHeader `
            -Uri "$vaultUri/secrets/$($UsernameSecretName)?api-version=7.4"
    }).value
$password = (Invoke-WithRetry {
        Invoke-RestMethod -Headers $authHeader `
            -Uri "$vaultUri/secrets/$($PasswordSecretName)?api-version=7.4"
    }).value

$securePassword = ConvertTo-SecureString -String $password -AsPlainText -Force
$credential = New-Object System.Management.Automation.PSCredential($username, $securePassword)

$joinParams = @{
    DomainName = $DomainName
    Credential = $credential
    Restart    = $true
    Force      = $true
}
if ($OUPath) {
    $joinParams.OUPath = $OUPath
}

Add-Computer @joinParams
Write-Output "Joined $DomainName, restarting."
