Write-Host 'Authenticating to Azure...'
Add-AzureRmAccount

$sharedParams = @{
	AutomationAccountName = 'adamautomation'
	ResourceGroupName = 'Group'
}

## Send the changed DSC configuration to Azure
Write-Host 'Sending DSC configuration to Azure Automation...'
#Import-AzureRmAutomationDscConfiguration @sharedParams -SourcePath .\NewTestEnvironment.ps1 -Published -Force
Import-AzureRmAutomationDscConfiguration @sharedParams -SourcePath C:\Dropbox\GitRepos\TestDomainCreator\NewTestEnvironment.ps1 -Published -Force

## Grab config data from source
Write-Host 'Getting ConfigData from source...'
$configDataFilePath = "$env:TEMP\ConfigData.psd1"
$iwrParams = @{
	Uri = 'https://raw.githubusercontent.com/adbertram/TestDomainCreator/master/ConfigurationData.psd1'
	UseBasicParsing = $true
	OutFile = $configDataFilePath
}
Invoke-WebRequest @iwrParams
$configData = Invoke-Expression (Get-Content -Path $configDataFilePath -Raw)

## Start the DSC compile in Azure
Write-Host 'Begin Azure Automation DSC compile...'
$compParams = $sharedParams + @{
	ConfigurationName = 'NewTestEnvironment'
	ConfigurationData = $configData
}
$CompilationJob = Start-AzureRmAutomationDscCompilationJob @compParams

## Wait for the DSC compile
Write-Host 'Waiting for Azure Automation DSC compile...'
while($CompilationJob.EndTime -eq $null -and $CompilationJob.Exception -eq $null)
{
    $CompilationJob = $CompilationJob | Get-AzureRmAutomationDscCompilationJob
    Start-Sleep -Seconds 3
}

## Ensure the compile was good
$CompilationJob | Get-AzureRmAutomationDscCompilationJobOutput -Stream Any

## Assign the configuration to the node?? This might not be necessary
Write-Host 'Assigning DSC configuraiton to node...'
$nodeId = (Get-AzureRmAutomationDscNode @sharedParams -Name LABDC).Id
$node = Set-AzureRmAutomationDscNode -NodeConfigurationName 'NewTestEnvironment.LABDC' -ResourceGroupName 'Group' -Id $nodeId

## Wait for the assignment (running???) to complete
while($node.Status -ne 'Done???')
{
    $node = $node | Get-AzureRmAutomationDscNode
    Start-Sleep -Seconds 3
}

## Apply the DSC configuration to our test VM. This might not be necessary if the assign part does it.


## Ensure the DSC configuration was good
Get-AzureRmAutomationDscNodeReport -NodeId $nodeId @sharedParams | sort endtime | select -last 1