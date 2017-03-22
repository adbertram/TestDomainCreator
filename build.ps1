Add-AzureRmAccount

$sharedParams = @{
	AutomationAccountName = 'adamautomation'
	ResourceGroupName = 'Group'
}

## Send the changed DSC configuration to Azure
#Import-AzureRmAutomationDscConfiguration @sharedParams -SourcePath .\NewTestEnvironment.ps1 -Published -Force
Import-AzureRmAutomationDscConfiguration @sharedParams -SourcePath C:\Dropbox\GitRepos\TestDomainCreator\NewTestEnvironment.ps1 -Published -Force

## Grab config data from source
$configDataFilePath = "$env:TEMP\ConfigData.psd1"
$iwrParams = @{
	Uri = 'https://raw.githubusercontent.com/adbertram/TestDomainCreator/master/ConfigurationData.psd1'
	UseBasicParsing = $true
	OutFile = $configDataFilePath
}
Invoke-WebRequest @iwrParams
$configData = Invoke-Expression (Get-Content -Path $configDataFilePath -Raw)

## Start the DSC compile in Azure
$compParams = $sharedParams + @{
	ConfigurationName = 'NewTestEnvironment'
	ConfigurationData = $configData
}
$CompilationJob = Start-AzureRmAutomationDscCompilationJob @compParams

## Wait for the DSC compile
while($CompilationJob.EndTime –eq $null -and $CompilationJob.Exception –eq $null)
{
    $CompilationJob = $CompilationJob | Get-AzureRmAutomationDscCompilationJob
    Start-Sleep -Seconds 3
}

$CompilationJob | Get-AzureRmAutomationDscCompilationJobOutput –Stream Any

## Apply the DSC configuration to our test VM



## Ensure the DSC configuration was good
$Node  = Get-AzureAutomationDscNode -Name WEB02
Get-AzureAutomationDSCNodeReport  -NodeId $Node.ID | Sort EndTime | Select-Object -last 1