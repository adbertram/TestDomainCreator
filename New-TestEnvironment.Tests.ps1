<#
    .SYNOPSIS
        This is a set of Pester tests for for New-TestEnvironment script.

    .PARAMETER Full
         An optional switch parameter that is used if a full, from-scratch set of tests is to be executed. This accounts
         for dependencies, executes the code to be tested and tears down any changes made. Use this switch if you don't
         trust the current environment configuration and want to start from scratch.

    .PARAMETER DependencyFailureAction
         An optional string parameter representing the action to take if any test dependencies are not found. This can
         either be 'Exit' which if a dependency is not found, the tests will exit or 'Build' which indicates to dynamically
         build any dependencies required and tear them down after the tests are complete.

    .EXAMPLE
        PS> Invoke-Pester -Script @{ Parameter = @{ Path = 'New-TestEnvironment.Tests.ps1'}}

            This example executes this test suite assuming that the code that builds the components for these tests
            was already ran and the dependencies required for these tests to execute are already in place.

    .EXAMPLE
        PS> Invoke-Pester -Script @{ Parameter = @{ Path = 'New-TestEnvironment.Tests.ps1'; Parameter = @{ Full = $true }}}

            This example executes this test suite assuming nothing. It will start from scratch by first checking to see
            if all prerequiiste dependencies are in place. If not, it will dynamically build them. It will execute the 
            code to be tested, perform all necessary tests against the infrastructure and then tear down any dependencies
            and changes that the tests performed.

#>

param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [switch]$Full,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [ValidateSet('Exit','Build')]
    [string]$DependencyFailureAction = 'Exit'
)

try {
    $whParams = @{
        BackgroundColor = 'Black'
    }

    ## Read the expected attributes from ConfigurationData
    $configDataFilePath = "$env:TEMP\ConfigData.psd1"
    Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/adbertram/TestDomainCreator/master/ConfigurationData.psd1' -UseBasicParsing -OutFile $configDataFilePath
    $expectedAttributes = Invoke-Expression (Get-Content -Path $configDataFilePath -Raw)
        
    $expectedDomainControllerName = @($expectedAttributes.AllNodes).where({ $_.Purpose -eq 'Domain Controller' -and $_.NodeName -ne '*' }).Nodename
    $expectedVmName = $expectedDomainControllerName

    $domainDn = ('DC={0},DC={1}' -f ($expectedAttributes.NonNodeData.DomainName -split '\.')[0], ($expectedAttributes.NonNodeData.DomainName -split '\.')[1])

    describe 'New-TestEnvironment' {

        ## Run all tests
        $sharedSession = New-PSSession -ComputerName $expectedDomainControllerName

        ## Forest-wide
        $forest = Invoke-Command -Session $sharedSession -ScriptBlock { Get-AdForest }
        
        ## Groups
        $actualGroups = Invoke-Command -Session $sharedSession -ScriptBlock {  Get-AdGroup -Filter '*' } | Select -ExpandProperty Name
        $expectedGroups = $expectedAttributes.NonNodeData.AdGroups
        
        ## OUs
        $actualOuDns = Invoke-Command -Session $sharedSession -ScriptBlock { Get-AdOrganizationalUnit -Filter '*' } | Select -ExpandProperty DistinguishedName
        $expectedOus = $expectedAttributes.NonNodeData.OrganizationalUnits
        $expectedOuDns = $expectedOus | foreach { "OU=$_,$domainDn" }

        ## Users
        $actualUsers = Invoke-Command -Session $sharedSession -ScriptBlock { Get-AdUser -Filter "*" -Properties Department, Title }
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
            if (@($script:removeActions).Count -eq 0)
            {
                Write-Host @whParams -Object 'No dependencies built thus no teardown necessary' -ForegroundColor Yellow
            } else
            {
                Write-Host @whParams -Object "====Begin Teardown====" -ForegroundColor Magenta
                foreach ($removeAction in $script:removeActions)
                {
                    Write-Host @whParams -Object 'Starting remove action...' -ForegroundColor Yellow
                    & $removeAction
                }
                Write-Host @whParams -Object "====End Teardown====" -ForegroundColor Magenta    
            }
        }
    }
} catch {
    Write-Host @whParams -Object $_.Exception.Message -ForegroundColor Red
}