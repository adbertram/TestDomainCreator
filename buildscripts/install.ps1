Write-Host 'Installing necessary PowerShell modules...'
Install-PackageProvider NuGet -MinimumVersion '2.8.5.201' -Force
Import-PackageProvider NuGet -MinimumVersion '2.8.5.201' -Force
Install-Module AzureRM -verbose -Force -Confirm:$false
Install-Module Pester -verbose -Force -Confirm:$false