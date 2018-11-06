param([switch]$Elevated)

Function Check-Admin() 
{
    $currentUser = New-Object Security.Principal.WindowsPrincipal $([Security.Principal.WindowsIdentity]::GetCurrent())
    $currentUser.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)
}

if ((Check-Admin) -eq $false)  
{
    if ($elevated)
    {
        #could not elevate, quit
    }
    else 
    {
        Start-Process powershell.exe -Verb RunAs -ArgumentList ('-noprofile -noexit -file "{0}" -elevated' -f ($myinvocation.MyCommand.Definition))
    }
    
    exit
}


$moduleToRemove = "A_Entities`r`nA_EntityTrigger"
$moduleToRemove|Set-Content 'C:\DeployablePackage\UninstallDeployablePackage\AOSService\Scripts\ModuleToRemove.txt' -Force

$uninstallFolder = 'C:\DeployablePackage\UninstallDeployablePackage\'
$runbookId = [Guid]::NewGuid()
$runbookFile = Join-Path $uninstallFolder "Runbooks\$runbookId.xml"
$topologyFile = Join-Path $uninstallFolder 'DefaultTopologyData.xml'
$updateInstaller = Join-Path $uninstallFolder 'AXUpdateInstaller.exe'

 
Function ExtractFiles
{
    Unblock-File $file
    Expand-Archive -LiteralPath $file -Destination $extracted
}
 
Function SetTopologyData
{
    [xml]$xml = Get-Content $topologyFile
    $machine = $xml.TopologyData.MachineList.Machine
 
    # Set computer name
    $machine.Name = $env:computername
 
    #Set service models
    $serviceModelList = $machine.ServiceModelList
    $serviceModelList.RemoveAll()
 
    $instalInfoDll = Join-Path $uninstallFolder 'Microsoft.Dynamics.AX.AXInstallationInfo.dll'
    [void][System.Reflection.Assembly]::LoadFile($instalInfoDll)
 
    $models = [Microsoft.Dynamics.AX.AXInstallationInfo.AXInstallationInfo]::GetInstalledServiceModel()
    foreach ($name in $models.Name)
    {
        $element = $xml.CreateElement('string')
        $element.InnerText = $name
        $serviceModelList.AppendChild($element)
    }
 
    $xml.Save($topologyFile)
}
 
Function GenerateRunbook
{
    $serviceModelFile = Join-Path $uninstallFolder 'DevInstallServiceModelData.xml'
    & $updateInstaller generate "-runbookId=$runbookId" "-topologyFile=$topologyFile" "-serviceModelFile=$serviceModelFile" "-runbookFile=$runbookFile"
}
 
Function ImportRunbook
{
    & $updateInstaller import "-runbookfile=$runbookFile"
}
 
Function ExecuteRunbook
{
    & $updateInstaller execute "-runbookId=$runbookId"
}
 
Function RerunRunbook([int] $step)
{
    & $updateInstaller execute "-runbookId=$runbookId" "-rerunstep=$step"
}
 
Function SetStepComplete([int] $step)
{
    & $updateInstaller execute "-runbookId=$runbookId" "-setstepcomplete=$step"
}
 
Function ExportRunbook
{
    & $updateInstaller export "-runbookId=$runbookId" "-runbookfile=$runbookFile"
}

Set-MpPreference -DisableRealtimeMonitoring $true

SetTopologyData
GenerateRunbook
ImportRunbook
ExecuteRunbook

Set-MpPreference -DisableRealtimeMonitoring $false