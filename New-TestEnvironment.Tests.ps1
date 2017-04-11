<#
    .SYNOPSIS
        This is a set of Pester tests for for New-TestEnvironment script.

    .EXAMPLE
        PS> Invoke-Pester -Script @{ Parameter = @{ Path = 'New-TestEnvironment.Tests.ps1'}}

            This example executes this test suite assuming that the code that builds the components for these tests
            was already ran and the dependencies required for these tests to execute are already in place.
#>

try {

    Write-Host 'Authenticating to Azure...'
	Disable-AzureRmDataCollection

	$azrPwd = ConvertTo-SecureString $env:azure_pass -AsPlainText -Force
	$azrCred = New-Object System.Management.Automation.PSCredential ($env:azure_appId, $azrPwd)

	## Use a SPN for easy authentication
	$connParams = @{
		ServicePrincipal = $true
		TenantId = $env:azure_tenantId
		Credential = $azrCred
		SubscriptionId = $env:azure_subscriptionid
	}
	$null = Add-AzureRmAccount @connParams
    
    $whParams = @{
        BackgroundColor = 'Black'
    }

    ## Read the expected attributes from ConfigurationData
    $configDataFilePath = "$env:TEMP\ConfigData.psd1"
    Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/adbertram/TestDomainCreator/master/ConfigurationData.psd1' -UseBasicParsing -OutFile $configDataFilePath
    $expectedAttributes = Invoke-Expression (Get-Content -Path $configDataFilePath -Raw)
        
    $expectedDomainControllerName = @($expectedAttributes.AllNodes).where({ $_.Purpose -eq 'Domain Controller' -and $_.NodeName -ne '*' }).Nodename

    $domainDn = ('DC={0},DC={1}' -f ($expectedAttributes.NonNodeData.DomainName -split '\.')[0], ($expectedAttributes.NonNodeData.DomainName -split '\.')[1])

    describe 'New-TestEnvironment' {

        ## Do all the stuff we need to up front here so we can then assert expected states later
            $vm = Get-AzureRmVm -Name $expectedDomainControllerName -ResourceGroupName 'Group'
            $ipAddress = $vm.NetworkProfile.NetworkInterfaces.Id | Split-Path -Leaf
            Set-Item -Path wsman:\localhost\Client\TrustedHosts -Value $ipAddress -Force
            $adminUsername = $vm.osProfile.AdminUsername
            $adminPwd = ConvertTo-SecureString $env:vm_admin_pass -AsPlainText -Force
            $cred = New-Object System.Management.Automation.PSCredential ($adminUsername, $adminPwd)

            ## Create a shared session for all of the calls we need to make.
            BeforeAll {
                $script:sharedSession = New-PSSession -ComputerName $ipAddress -Credential $cred
            }

            AfterAll {
                $script:sharedSession | Remove-PSSession
            }

            ## Forest-wide
            $forest = Invoke-Command -Session $script:sharedSession -ScriptBlock { Get-AdForest }
            
            ## Groups
            $actualGroups = Invoke-Command -Session $script:sharedSession -ScriptBlock {  Get-AdGroup -Filter '*' } | Select -ExpandProperty Name
            $expectedGroups = $expectedAttributes.NonNodeData.AdGroups
            
            ## OUs
            $actualOuDns = Invoke-Command -Session $script:sharedSession -ScriptBlock { Get-AdOrganizationalUnit -Filter '*' } | Select -ExpandProperty DistinguishedName
            $expectedOus = $expectedAttributes.NonNodeData.OrganizationalUnits
            $expectedOuDns = $expectedOus | foreach { "OU=$_,$domainDn" }

            ## Users
            $actualUsers = Invoke-Command -Session $script:sharedSession -ScriptBlock { Get-AdUser -Filter "*" -Properties Department, Title }
            $expectedUsers = $expectedAttributes.NonNodeData.AdUsers

        it "creates the expected forest" {
            $forest.Name | should be $expectedAttributes.NonNodeData.DomainName
        }

        it 'creates all expected AD Groups' {

            @($actualGroups | where { $_ -in $expectedGroups }).Count | should be @($expectedGroups).Count

        }

        it 'creates all expected AD OUs' {

            @($actualOuDns | where { $_ -in $expectedOuDns }).Count | should be @($expectedOuDns).Count
            
        }

        it 'creates all expected AD users' {
            
            foreach ($user in $expectedUsers)
            {
                $expectedUserName = ('{0}{1}' -f $user.FirstName.SubString(0, 1), $user.LastName)
                $actualUserMatch = $actualUsers | where {$_.SamAccountName -eq $expectedUserName}
                $actualUserMatch | should not benullorempty     
                $actualUserMatch.givenName | should be $user.FirstName
                $actualUserMatch.surName | should be $user.LastName
                $actualUserMatch.Department | should be $user.Department
                $actualUserMatch.DistinguishedName | should be "CN=$expectedUserName,OU=$($user.Department),$domainDn"
            }
        }
    }
} catch {
    Write-Host @whParams -Object $_.Exception.Message -ForegroundColor Red
}