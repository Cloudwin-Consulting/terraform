# Mounts the deployment's Azure file share on the machine, so the
# application saves its files there instead of on the machine's own
# disks.
#
# Runs on the machine through the Azure Run Command service, as
# SYSTEM. The mapping is created with New-SmbGlobalMapping rather than
# New-PSDrive or `net use`: a global mapping belongs to the machine
# instead of to a signed-in user, so services, scheduled tasks and
# every user session see the drive, and -Persistent keeps it across
# restarts.
#
# Authentication follows the storage account's configuration, and the
# deployment passes whichever the account is set up for:
#
#   * With identity-based authentication (Active Directory or
#     Microsoft Entra Kerberos) no key is passed. The mapping is made
#     as the machine's own directory identity - the computer account,
#     because this runs as SYSTEM - which therefore needs share-level
#     access: grant it through the deployment's
#     share_contributor_principals, or by setting
#     default_share_level_permission on azure_files_authentication.
#
#   * Without it, the account key arrives as an encrypted protected
#     parameter that the Run Command service never returns in
#     instance view or logs. It is stored in the mapping's credential,
#     not written to disk by this script.
param(
    [Parameter(Mandatory = $true)][string]$StorageAccountName,
    [Parameter(Mandatory = $true)][string]$FileEndpointHost,
    [Parameter(Mandatory = $true)][string]$ShareName,
    [Parameter(Mandatory = $true)][string]$DriveLetter,
    [string]$StorageAccountKey = ''
)

$ErrorActionPreference = 'Stop'

$remotePath = "\\$FileEndpointHost\$ShareName"
$localPath = "${DriveLetter}:"

# The share is only reachable over the private endpoint, so the host
# name must resolve to a private address through the hub's
# privatelink.file.core.windows.net zone and answer on SMB. Both take
# a moment to settle after a first deployment - and the machine may
# still be restarting after a domain join - so this waits rather than
# failing the deployment on a race. A failure here is a real network
# problem: DNS pointing at the public endpoint, the private endpoint
# missing, or the subnet NSG blocking port 445.
function Wait-ForFileEndpoint {
    param(
        [Parameter(Mandatory = $true)][string]$HostName,
        [int]$Attempts = 20,
        [int]$DelaySeconds = 15
    )

    for ($attempt = 1; $attempt -le $Attempts; $attempt++) {
        $client = New-Object System.Net.Sockets.TcpClient
        try {
            if ($client.ConnectAsync($HostName, 445).Wait(5000) -and $client.Connected) {
                $address = (Resolve-DnsName -Name $HostName -Type A -ErrorAction SilentlyContinue |
                        Where-Object { $_.IPAddress } | Select-Object -First 1).IPAddress
                Write-Output "$HostName answers on port 445 (resolved to $address)."
                return
            }
        }
        catch {
            Write-Output "Attempt $attempt of ${Attempts}: $HostName not reachable on port 445 ($($_.Exception.Message))."
        }
        finally {
            $client.Dispose()
        }

        if ($attempt -eq $Attempts) {
            throw "$HostName did not answer on port 445 after $Attempts attempts. Check that the file share private endpoint exists, that the machine resolves the host through the hub's privatelink.file.core.windows.net zone, and that the subnet network security groups allow SMB."
        }

        Start-Sleep -Seconds $DelaySeconds
    }
}

Wait-ForFileEndpoint -HostName $FileEndpointHost

# SMB traffic to Azure Files is encrypted in transit and the account
# rejects unencrypted connections, so a client that has SMB signing or
# encryption disabled cannot mount the share. Nothing to configure on
# a current Windows Server, but report the setting so an image that
# ships with SMB 3 encryption off is visible in the run command's
# output rather than surfacing as an opaque access error.
$smbClient = Get-SmbClientConfiguration
Write-Output "SMB client: EncryptionCiphers=$($smbClient.EncryptionCiphers), RequireSecuritySignature=$($smbClient.RequireSecuritySignature)"

$credential = $null
if ($StorageAccountKey) {
    # The storage account key authenticates as the account itself. The
    # AZURE\<account> form is what Azure Files expects for key-based
    # SMB access.
    $securedKey = ConvertTo-SecureString -String $StorageAccountKey -AsPlainText -Force
    $credential = New-Object System.Management.Automation.PSCredential("AZURE\$StorageAccountName", $securedKey)
    Write-Output "Mounting $remotePath with the storage account key."
}
else {
    Write-Output "Mounting $remotePath as this machine's directory identity - no key is used."
}

# The mapping is always re-created rather than left in place when it
# looks healthy. A global mapping does not expose the credential it
# holds, and the Run Command service only re-runs this script when the
# deployment changed something - the share it points at, the account
# key, or the switch from key to identity-based authentication - which
# are exactly the cases where the stored credential or remote path has
# to be replaced. A healthy-looking mapping left alone through a switch
# to identity would keep a key the account has since disabled, and fail
# at its next reconnect or restart instead of here.
#
# Both the share's own mapping and anything else holding the drive
# letter go, so a deployment that renames the share - or moves it to
# another account - migrates the machines instead of stranding the old
# mapping on the letter the new one needs. Removing a mapping breaks
# whatever handles an application holds on the drive, which is why
# nothing re-runs this script unless the deployment changed.
$stale = @(
    Get-SmbGlobalMapping -ErrorAction SilentlyContinue |
    Where-Object { $_.RemotePath -eq $remotePath -or $_.LocalPath -eq $localPath }
)

foreach ($mapping in $stale) {
    Write-Output "Removing the existing mapping of $($mapping.RemotePath) at $($mapping.LocalPath) (status $($mapping.Status))."
    Remove-SmbGlobalMapping -RemotePath $mapping.RemotePath -Force
}

# With this machine's own mappings gone, anything still holding the
# drive letter is a real volume - the machine's disks, the Azure
# temporary disk (usually D:) or a DVD drive - and no mapping can be
# created over it. New-SmbGlobalMapping would only report that the
# local device is already in use, once per retry.
$occupant = Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DeviceID = '$localPath'" -ErrorAction SilentlyContinue
if ($occupant) {
    throw "$localPath is already in use on this machine (drive type $($occupant.DriveType), volume '$($occupant.VolumeName)'). Choose a free letter with the deployment's file_share_drive_letter."
}

$mappingParams = @{
    RemotePath  = $remotePath
    LocalPath   = $localPath
    Persistent  = $true
    ErrorAction = 'Stop'
}
if ($credential) {
    $mappingParams.Credential = $credential
}

# Share-level role assignments are granted moments earlier in the same
# deployment and take a short while to reach the storage account's
# data plane, so an identity-based mount can see a transient access
# denied. Retry before giving up.
for ($attempt = 1; $attempt -le 10; $attempt++) {
    try {
        New-SmbGlobalMapping @mappingParams | Out-Null
        break
    }
    catch {
        if ($attempt -eq 10) {
            throw
        }
        Write-Output "Attempt $attempt of 10 to map $remotePath failed ($($_.Exception.Message)), retrying in 30 seconds."
        Start-Sleep -Seconds 30
    }
}

if (-not (Test-Path -Path "$localPath\")) {
    throw "$remotePath was mapped to $localPath but the drive is not readable. With identity-based authentication, check this machine's identity holds a share-level role on the storage account."
}

Write-Output "$remotePath is mounted at $localPath and available to every user and service on this machine."
