<#
    .SYNOPSIS
        This is a set of Pester tests for for New-TestEnvironment script.

    .EXAMPLE
        PS> Invoke-Pester -Script @{ Parameter = @{ Path = 'New-TestEnvironment.Tests.ps1'}}

            This example executes this test suite assuming that the code that builds the components for these tests
            was already ran and the dependencies required for these tests to execute are already in place.
#>

try {
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

        $vm = Get-AzureRmVm -Name $expectedDomainControllerName -ResourceGroupName 'Group'
        $ipAddress = (Get-AzureRmPublicIpAddress -ResourceGroupName 'Group' -Name labdc-ip).IpAddress
        Set-Item -Path wsman:\localhost\Client\TrustedHosts -Value $ipAddress -Force
        $adminUsername = $vm.osProfile.AdminUsername
        $adminPwd = ConvertTo-SecureString $env:vm_admin_password -AsPlainText -Force
        $cred = New-Object System.Management.Automation.PSCredential ($adminUsername, $adminPwd)

        ## Run all tests
        $script:sharedSession = New-PSSession -ComputerName $ipAddress -Credential $cred

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

        AfterAll {
            $script:sharedSession | Remove-PSSession
        }
    }
} catch {
    Write-Host @whParams -Object $_.Exception.Message -ForegroundColor Red
}