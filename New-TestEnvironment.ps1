configuration NewTestEnvironment
{        
    Import-DscResource -ModuleName xActiveDirectory
    
    Login-AzureRmAccount

    $credParams = @{
        ResourceGroupName = 'Group'
        AutomationAccountName = 'adamautomation'
    }
    $defaultAdUserCred = Get-AutomationPSCredential -Name 'Default AD User Password'
    $domainSafeModeCred = Get-AutomationPSCredential -Name 'Domain safe mode'
            
    Node $AllNodes.NodeName
    {

        @($ConfigurationData.NonNodeData.ADGroups).foreach( {
                xADGroup $_
                {
                    Ensure = 'Present'
                    GroupName = $_
                    DependsOn = '[xADDomain]ADDomain'
                }
            })

        @($ConfigurationData.NonNodeData.OrganizationalUnits).foreach( {
                xADOrganizationalUnit $_
                {
                    Ensure = 'Present'
                    Name = ($_ -replace '-')
                    Path = ('DC={0},DC={1}' -f ($ConfigurationData.NonNodeData.DomainName -split '\.')[0], ($ConfigurationData.NonNodeData.DomainName -split '\.')[1])
                    DependsOn = '[xADDomain]ADDomain'
                }
            })

        @($ConfigurationData.NonNodeData.ADUsers).foreach( {
                xADUser "$($_.FirstName) $($_.LastName)"
                {
                    Ensure = 'Present'
                    DomainName = $ConfigurationData.NonNodeData.DomainName
                    GivenName = $_.FirstName
                    SurName = $_.LastName
                    UserName = ('{0}{1}' -f $_.FirstName.SubString(0, 1), $_.LastName)
                    Department = $_.Department
                    Path = ("OU={0},DC={1},DC={2}" -f $_.Department, ($ConfigurationData.NonNodeData.DomainName -split '\.')[0], ($ConfigurationData.NonNodeData.DomainName -split '\.')[1])
                    JobTitle = $_.Title
                    Password = $defaultAdUserCred.Password
                    DependsOn = '[xADDomain]ADDomain'
                }
            })

        ($Node.WindowsFeatures).foreach( {
                WindowsFeature $_
                {
                    Ensure = 'Present'
                    Name = $_
                }
            })        
        
        xADDomain ADDomain          
        {             
            DomainName = $ConfigurationData.NonNodeData.DomainName
            DomainAdministratorCredential = $domainSafeModeCred
            SafemodeAdministratorPassword = $domainSafeModeCred
            DependsOn = '[WindowsFeature]AD-Domain-Services'
        }
    }         
} 

$configData = @{
	AllNodes = @(
		@{
			NodeName = '*'
			PsDscAllowDomainUser = $true
            PSDscAllowPlainTextPassword = $true
		}
        @{
			NodeName = 'LABDC'
		}
    )
    NonNodeData = @{
        DomainName = 'mytestlab.local'
        AdGroups = 'Accounting','Information Systems','Executive Office','Janitorial Services'
        OrganizationalUnits = 'Accounting','Information Systems','Executive Office','Janitorial Services'
        WindowsFatures = 'AD-Domain-Services'
        AdUsers = @(
            @{
                FirstName = 'Katie'
                LastName = 'Green'
                Department = 'Accounting'
                Title = 'Manager of Accounting'
            }
            @{
                FirstName = 'Joe'
                LastName = 'Blow'
                Department = 'Information Systems'
                Title = 'System Administrator'
            }
            @{
                FirstName = 'Joe'
                LastName = 'Schmoe'
                Department = 'Information Systems'
                Title = 'Software Developer'
            }
            @{
                FirstName = 'Barack'
                LastName = 'Obama'
                Department = 'Executive Office'
                Title = 'CEO'
            }
            @{
                FirstName = 'Donald'
                LastName = 'Trump'
                Department = 'Janitorial Services'
                Title = 'Custodian'
            }
        )
    }
}

NewTestEnvironment -ConfigurationData $configData -WarningAction SilentlyContinue