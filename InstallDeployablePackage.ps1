# Manage Deployable Packages

param([switch]$Elevated,
      [string]$Filename,
      [ValidateSet('Dev', 'Default')]
      [string]$ServiceModel)


      # 

#Check if we are running elevated
Function Check-Admin() 
{
    $currentUser = New-Object Security.Principal.WindowsPrincipal $([Security.Principal.WindowsIdentity]::GetCurrent())
    $currentUser.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)
}

# Check if Visual Studio is started
Function Check-VisualStudio() 
{
    $ProcessActive = Get-Process devenv -ErrorAction SilentlyContinue
    if($ProcessActive -eq $null)
    {
        return $false
    }
    else
    {
        return $true
    }
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

if ((Check-VisualStudio) -eq $true)  
{
    write-error "Exit all instances of Visual Studio and rerun the script" -ErrorAction Stop
}


$ErrorActionPreference = 'Stop'

Function Get-FileName()
{
    # write-host $filename

    # start-sleep -Seconds 30
    
    if (!$filename)
    {
      [System.Reflection.Assembly]::LoadWithPartialName('System.windows.forms') | Out-Null
    
      $OpenFileDialog = New-Object System.Windows.Forms.OpenFileDialog
      $OpenFileDialog.initialDirectory = $PSScriptRoot 
      $OpenFileDialog.filter = 'zip (*.zip)| *.zip'
      $OpenFileDialog.ShowDialog() | Out-Null
      $OpenFileDialog.filename
    }
    else
    {
      return (get-childItem -Path $filename).FullName
    }
    
}

$filePath = Get-FileName #Hardcode full path for deployable-package-zip  

if (![System.IO.File]::Exists($filePath))
{
    Write-Error 'No file selected or the file does not exists.'
}

if (!$ServiceModel)
{
    $serviceModel = Read-Host -Prompt 'Input service model (Dev or Default)'
}


if (!(($serviceModel.Equals('Dev')) -or ($serviceModel.Equals('Default'))))
{
   Write-Error 'Enter Dev or Default.' -ErrorAction Stop
}


$newRunbookId = $false

$folder = [System.IO.Path]::GetDirectoryName($filePath);
$archiveFileName = [System.IO.Path]::GetFileName($filePath);
$extracted = Join-Path $folder ([System.IO.Path]::GetFileNameWithoutExtension($archiveFileName))
$runbookPath = Join-Path $extracted "Runbooks"

if ((Test-Path $runbookPath -PathType Container) -and (!$newRunbookId))
{
    $latest = Get-ChildItem -Path $runbookPath | Sort-Object LastAccessTime -Descending | Select-Object -First 1
    $runbookId = [System.IO.Path]::GetFileNameWithoutExtension($latest)
}
else
{
    $runbookId = [Guid]::NewGuid()
}

Write-Information -MessageData "Trying to install the runbook: $runbookId" -InformationAction Continue

$file = Join-Path $folder $archiveFileName
$runbookFile = Join-Path $extracted "Runbooks\$runbookId.xml"
$topologyFile = Join-Path $extracted 'DefaultTopologyData.xml'
$updateInstaller = Join-Path $extracted 'AXUpdateInstaller.exe'

 
Function ExtractFiles
{
    Write-Information "Extracting $file" -InformationAction Continue
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
 
    $instalInfoDll = Join-Path $extracted 'Microsoft.Dynamics.AX.AXInstallationInfo.dll'
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
    if ($serviceModel.Equals('Dev'))
    {
        $serviceModelFile = Join-Path $extracted 'DevInstallServiceModelData.xml'
    }
    
    if ($serviceModel.Equals('Default'))
    {
        $serviceModelFile = Join-Path $extracted 'DefaultServiceModelData.xml'
    }
    
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

Function AutoInstall
{
    Set-MpPreference -DisableRealtimeMonitoring $true

    ExtractFiles
    SetTopologyData
    GenerateRunbook
    ImportRunbook
    ExecuteRunbook

    Set-MpPreference -DisableRealtimeMonitoring $false
}

AutoInstall