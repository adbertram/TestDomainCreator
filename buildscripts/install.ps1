Write-Host 'Installing necessary PowerShell modules...'
Install-Module AzureRM -verbose -Force -Confirm:$false
Install-Module Pester -verbose -Force -Confirm:$false