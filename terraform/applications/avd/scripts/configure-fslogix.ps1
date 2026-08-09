# Reconciles the session host's FSLogix configuration with the
# deployment's: points the agent at the profile share and enables
# Microsoft Entra Kerberos ticket retrieval, or - given an empty share
# path - turns profiles off in the guest.
#
# Runs on the machine through the Azure Run Command service. The share
# path is the only input and is not a secret. The FSLogix agent ships
# with the Windows multi-session marketplace images; profiles apply to
# users at their next sign-in, so no restart is needed.
param(
    [string]$ProfileShareUncPath = ''
)

$ErrorActionPreference = 'Stop'

$profilesKey = 'HKLM:\SOFTWARE\FSLogix\Profiles'

# An empty share path means the deployment has FSLogix disabled, so
# profiles are switched off here rather than left pointing at a share
# that is being destroyed in the same apply. Users fall back to local
# profiles at their next sign-in. A host that was never configured -
# or an image without the agent - has nothing to switch off.
if ([string]::IsNullOrWhiteSpace($ProfileShareUncPath)) {
    if (Test-Path $profilesKey) {
        Set-ItemProperty -Path $profilesKey -Name 'Enabled' -Value 0 -Type DWord
        Remove-ItemProperty -Path $profilesKey -Name 'VHDLocations' -ErrorAction SilentlyContinue
        Write-Output 'FSLogix profiles disabled; users fall back to local profiles at their next sign-in.'
    }
    else {
        Write-Output 'FSLogix profiles were never configured on this host, nothing to disable.'
    }

    exit 0
}

# These registry settings configure the FSLogix agent - they do not
# install it. The agent ships with the Windows multi-session
# marketplace images; custom images must have it baked in (e.g.
# through the golden-image stack). Failing here surfaces the gap at
# deployment instead of silently leaving users on local profiles.
if (-not (Get-Service -Name 'frxsvc' -ErrorAction SilentlyContinue)) {
    throw 'The FSLogix agent (frxsvc service) is not installed on this image. Bake FSLogix into the session host image, or deploy from a Windows multi-session marketplace image that ships with it.'
}

# Let the Entra joined machine request Kerberos service tickets from
# Microsoft Entra ID - Azure Files AADKERB authentication depends on
# it, and it is off by default.
$kerberosKey = 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa\Kerberos\Parameters'
New-Item -Path $kerberosKey -Force | Out-Null
Set-ItemProperty -Path $kerberosKey -Name 'CloudKerberosTicketRetrievalEnabled' -Value 1 -Type DWord

# Load the Microsoft Entra credential key from the roaming profile, so
# single sign-on keeps working when a user's FSLogix container attaches
# on a different pooled session host.
$entraAccountKey = 'HKLM:\SOFTWARE\Policies\Microsoft\AzureADAccount'
New-Item -Path $entraAccountKey -Force | Out-Null
Set-ItemProperty -Path $entraAccountKey -Name 'LoadCredKeyFromProfile' -Value 1 -Type DWord

# Store each user's profile as a container on the share. The local
# profile is removed when the container takes over, and the directory
# name leads with the username so administrators can browse the share.
New-Item -Path $profilesKey -Force | Out-Null
Set-ItemProperty -Path $profilesKey -Name 'Enabled' -Value 1 -Type DWord
Set-ItemProperty -Path $profilesKey -Name 'VHDLocations' -Value @($ProfileShareUncPath) -Type MultiString
Set-ItemProperty -Path $profilesKey -Name 'DeleteLocalProfileWhenVHDShouldApply' -Value 1 -Type DWord
Set-ItemProperty -Path $profilesKey -Name 'FlipFlopProfileDirectoryName' -Value 1 -Type DWord

Write-Output "FSLogix profiles configured against $ProfileShareUncPath"
