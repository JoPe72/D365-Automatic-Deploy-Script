####################################################################################
####################################################################################
## ValidateAOS.ps1
## Validate AOS deployment
## Date: 09/29/2015
##
####################################################################################
####################################################################################
[CmdletBinding()]
Param(
   [Parameter(Mandatory = $true)]
   [string]$InputXml,
   [Parameter(Mandatory = $false)]
   [string]$CredentialsXml,
   [Parameter(Mandatory = $true)]
   [string]$Log
)

Import-Module "$PSScriptRoot\AosCommon.psm1" -Force -DisableNameChecking
Initialize-Log $Log

####################################################################################
## Helper Functions
####################################################################################

## Append XML Rows to Template
function Append-RowToXML
{
    [CmdletBinding()]
    Param(
       [Parameter(Mandatory = $false)]
       [string]$TestName,
       [Parameter(Mandatory = $false)]
       [string]$TestType,
       [Parameter(Mandatory = $false)]
       [string]$TestResult,
       [Parameter(Mandatory = $false)]
       [string]$RawResult,
       [Parameter(Mandatory = $false)]
       [string]$TimeStamp,
       [Parameter(Mandatory = $true)]
       [xml]$xmlTemplate
    )

    Write-Log "Getting existing rows from XML Template"
    $rows = $xmlTemplate.SelectSingleNode('CollectionResult/TabularResults/TabularData/Rows')
    Write-Log "Creating new row"
    $row = $xmlTemplate.CreateElement('ArrayOfStrings')
    $column = $xmlTemplate.CreateElement('string')#TestName
    $column.InnerText = $TestName
    $row.AppendChild($column)
    Write-Log "Adding column value: $TestName"
    $column = $xmlTemplate.CreateElement('string')#TestType
    $column.InnerText = $TestType
    $row.AppendChild($column)
    Write-Log "Adding column value: $TestType"
    $column = $xmlTemplate.CreateElement('string')#TestResult
    $column.InnerText = $TestResult
    $row.AppendChild($column)
    Write-Log "Adding column value: $TestResult"
    $column = $xmlTemplate.CreateElement('string')#RawResult
    $column.InnerText = $RawResult
    $row.AppendChild($column)
    
    $column = $xmlTemplate.CreateElement('string')#TimeStamp
    $column.InnerText = $TimeStamp
    $row.AppendChild($column)
    $rows.AppendChild($row)
    Write-Log "Adding column value: $TimeStamp"
    $xmlTemplate.CollectionResult.TabularResults.TabularData.AppendChild($rows)
    $xmlTemplate.Save($xmlTemplate)
    Write-Log "Saved rows to XML Template"
}

####################################################################################
## Validation Functions
####################################################################################

## Validate that all dependencies for AOS can be resolved
function Validate-AosDependencies($AosWebrootPath, $OutputPath, $Log, [ref]$TestResult)
{        
    $LoadErrorLog = join-path $OutputPath -ChildPath "AssemblyResolveErrors_$([System.DateTime]::Now.ToString("yyyy-MM-dd-HH_mm_ss")).csv"

    Write-Log "Dependency resolution error details will be written to $LoadErrorLog"
    
    Write-Log "Loading AOS web.config from $AosWebrootPath"
    [xml]$WebConfig = Get-Content "$(join-path $AosWebrootPath "web.config")"    
    $PackagesPathKey = $WebConfig.configuration.appSettings.add | where { $_.key -eq 'Aos.PackageDirectory' }

    Write-Log "Scanning for *.dll in $AosWebrootPath"
    $Assemblies = Get-ChildItem $AosWebrootPath -Recurse -Include "*.dll"

    if ($PackagesPathKey -ne $null)
    {
        Write-Log "Scanning for *.dll in $($PackagesPathKey.Value)"
        $Assemblies += Get-ChildItem $PackagesPathKey.Value -Recurse -Include "*.dll"
    }

    Write-Log "Creating a hash set of all found assembly names"
    $AssemblyNameHash = @{}
    foreach ($Assembly in $Assemblies)
    {
        if (!$AssemblyNameHash.ContainsKey($Assembly.Name))
        {
            $AssemblyNameHash[$Assembly.Name] = @($Assembly.FullName)
        }
        else
        {
            $AssemblyNameHash[$Assembly.Name] += $Assembly.FullName
        }
    }

    $ExclusionList = @("MS.Dynamics.Commerce.Client.Pos.FunctionalTests.dll",
"MS.Dynamics.Commerce.RetailProxy.Employee.CRT.Sqlite.FunctionalTests.dll",
"MS.Dynamics.Commerce.RetailProxy.Employee.CRT.SqlServer.FunctionalTests.dll",
"MS.Dynamics.Commerce.RetailProxy.Employee.DemoMode.SqlServer.FunctionalTests.dll",
"Microsoft.Dynamics.Retail.RetailServer.dll",
"Microsoft.Dynamics.Commerce.Runtime.Client.dll",
"Microsoft.Dynamics.Commerce.Runtime.Services.dll",
"Microsoft.Dynamics.Commerce.Runtime.TransactionService.dll",
"Microsoft.Dynamics.Commerce.Runtime.Workflow.dll"
"Cfx.CloudStorage.dll",
"Cfx.CommunicationFramework.dll",
"Cfx.Contracts.dll",
"Cfx.RuntimeWrapper.dll",
"DataContracts.NSD.dll",
"Microsoft.Dynamics.AX.ExchangeIntegration.dll",
"Microsoft.Dynamics.AX.Framework.Xlnt.XppParser.Tests.dll",
"Microsoft.Dynamics.AX.Metadata.Upgrade.Rules.dll",
"Microsoft.Dynamics.AX.Services.Tracing.Data.dll",
"Microsoft.Dynamics.AX.Services.Tracing.TraceParser.dll",
"Microsoft.Dynamics.AX.Servicing.SCDP.dll",
"Microsoft.Dynamics.AX.Servicing.SCDPBundling.dll",
"Microsoft.Dynamics.Clx.DbRestorePlugin.dll",
"Microsoft.Dynamics.Clx.DbSyncPlugin.dll",
"Microsoft.Dynamics.Clx.DbSyncPluginContext.dll",
"Microsoft.Dynamics.Clx.DummyPlugin.dll",
"Microsoft.Dynamics.Clx.DummyPluginContext.dll",
"Microsoft.Dynamics.Framework.Tools.ApplicationExplorer.dll",
"Microsoft.Dynamics.Framework.Tools.AutomationObjects.dll",
"Microsoft.Dynamics.Framework.Tools.BuildTasks.dll",
"Microsoft.Dynamics.Framework.Tools.Core.dll",
"Microsoft.Dynamics.Framework.Tools.Designers.dll",
"Microsoft.Dynamics.Framework.Tools.FormControlExtension.dll",
"Microsoft.Dynamics.Framework.Tools.Installer.dll",
"Microsoft.Dynamics.Framework.Tools.LabelEditor.dll",
"Microsoft.Dynamics.Framework.Tools.LanguageService.dll",
"Microsoft.Dynamics.Framework.Tools.LanguageService.Parser.dll",
"Microsoft.Dynamics.Framework.Tools.MetaModel.Core.dll",
"Microsoft.Dynamics.Framework.Tools.MetaModel.dll",
"Microsoft.Dynamics.Framework.Tools.ProjectSupport.dll",
"Microsoft.Dynamics.Framework.Tools.ProjectSystem.dll",
"Microsoft.Dynamics.Framework.Tools.Reports.DesignTime.dll",
"Microsoft.DynamicsOnline.Deployment.dll",
"Microsoft.DynamicsOnline.Infrastructure.dll",
"Microsoft.DynamicsOnline.Infrastructure.Providers.dll",
"Microsoft.ServiceHosting.Tools.DevelopmentFabric.dll",
"Microsoft.ServiceHosting.Tools.DevelopmentFabric.Service.dll",
"Microsoft.TeamFoundation.Client.dll",
"Microsoft.TeamFoundation.VersionControl.Client.dll",
"Microsoft.VisualStudio.ExtensionManager.dll",
"Microsoft.VisualStudio.Services.Client.dll",
"Microsoft.VisualStudio.TestPlatform.Extensions.VSTestIntegration.dll",
"Ms.Dynamics.Performance.Framework.dll",
"MS.Dynamics.Test.BIAndReporting.PowerBI.UnitTests.dll"
"MS.Dynamics.TestTools.CloudCommonTestUtilities.dll",
"MS.Dynamics.TestTools.TaskRecording.XppCodeGenerator.dll",
"MS.Dynamics.TestTools.TestLog.dll",
"MS.Dynamics.TestTools.UIHelpers.Core.dll",
"RoleCommon.dll",
"MS.Dynamics.TestTools.ApplicationFoundationUIHelpers.dll",
"Microsoft.Dynamics.AX.Framework.BestPracticeFixerIntegration.dll",
"Microsoft.Dynamics.Framework.Tools.Configuration.dll",
"MS.Dynamics.Platform.Integration.SharePoint.Tests.dll",
"MS.Dynamics.TestTools.ApplicationSuiteUIHelpers.dll",
"Microsoft.SqlServer.Management.SmoMetadataProvider.dll",
"Microsoft.SqlServer.Management.Utility.dll",
"Microsoft.SqlServer.OlapEnum.dll",
"Microsoft.Dynamics.Retail.DynamicsOnlineConnector.portable.dll",
"DataAccess.dll",
"SystemSettings.dll",
"BusinessLogic.dll",
"ButtonGrid.dll",
"POSProcesses.dll"
)

$ReferenceExclusionList = @(
"Microsoft.Dynamics.AX.Framework.Analytics.Deploy.dll#Microsoft.SqlServer.DTSPipelineWrap",
"Microsoft.Dynamics.AX.Framework.Analytics.Deploy.dll#Microsoft.SqlServer.DTSRuntimeWrap",
"Microsoft.Dynamics.AX.Framework.Analytics.Deploy.dll#Microsoft.SqlServer.ManagedDTS"
)


    $CurrentAssemblyWithErrors = ""

    $RawErrors = @()
    $RawWarnings = @()

    Add-Content -Path $LoadErrorLog -Value "Assembly;FullPath;FQ name;Unresolved reference FQ name;Error type"

    foreach ($Assembly in $Assemblies)
    {
        try
        {    
            $LoadedAssembly = [System.Reflection.Assembly]::LoadFile($Assembly.FullName)
            $ReferenceList = $LoadedAssembly.GetReferencedAssemblies()
        }
        catch
        {            
            Add-Content -Path $LoadErrorLog -Value "$($Assembly.Name);$($Assembly.FullName);Loading failed;Loading failed;LoadFailure"                
            $RawWarnings += "$($Assembly.Name) -> Loading failed;"
            continue
        }

        foreach ($Reference in $ReferenceList)
        {    
            if (!$AssemblyNameHash.ContainsKey("$($Reference.Name).dll"))
            {
                try
                {
                    [System.Reflection.Assembly]::Load($Reference.FullName) | Out-Null
                }
                catch
                {
                    $ErrorType = "ResolveFailure"
                    if (($Reference.Name -like "System.*" -or $Reference.Name -like "System") -and $Reference.Version -eq "2.0.5.0")
                    {
                        continue
                    }
                    elseif ($ExclusionList.Contains($Assembly.Name))
                    {
                        $ErrorType = "ResolveWarning - Exclusion"
                        Write-Log "Warning: Failed to resolve reference $($Reference.FullName) for assembly $($Assembly.FullName). The assembly was found in exclusion list."                                                    
                        $RawWarnings += "$($Assembly.Name) -> $($Reference.FullName);"                        
                    }
                    elseif ($ReferenceExclusionList.Contains($Assembly.Name + "#" + $Reference.Name))
                    {
                        $ErrorType = "ResolveWarning - Exclusion"
                        Write-Log "Warning: Failed to resolve reference $($Reference.FullName) for assembly $($Assembly.FullName). The referenced assembly was found in exclusion list."                        
                        $RawWarnings += "$($Assembly.Name) -> $($Reference.FullName);"
                    }
                    else
                    {
                        Write-Log "Error: Failed to resolve reference $($Reference.FullName) for assembly $($Assembly.FullName)"
                        $RawErrors += "$($Assembly.Name) -> $($Reference.FullName);"
                    }

                    $CurrentAssemblyWithErrors = $Assembly.Name
                    Add-Content -Path $LoadErrorLog -Value "$($Assembly.Name);$($Assembly.FullName);$($LoadedAssembly.FullName);$($Reference.FullName);$ErrorType"                                        
                }
            }
        }
    }
    
    Write-Log "Dependency scan finished."
    if($RawErrors.Length -gt 0)
    {
        Write-Log "Dependency resolution failed for some assemblies. Check test results or csv file.."
        $returnProperties = @{Result=0;RawResults=(($RawErrors + $RawWarnings) | Out-String);TimeStamp=(Get-Date).ToString()}
    }
    else
    {
        Write-Log "Dependency resolution passed."

        if ($RawWarnings.Length -gt 0)
        {
            Write-Log "There were warnings: dependency resolution failed for some assemblist from exclusion list"
        }

        $returnProperties = @{Result=1;RawResults=($RawWarnings | Out-String);TimeStamp=(Get-Date).ToString()}
    }

    $resultObject = New-Object PsObject -Property $returnProperties
    $TestResult.Value = $resultObject
}


## Validate endpoint sending HTTP request to configured endpoint 
function Validate-Endpoint{ 
     [CmdletBinding()] 
    Param( 
     [Parameter(Mandatory = $true)] 
     [string]$EndPointUrl 
     ) 
 
     [bool]$result = $false 
     [string]$rawResult 
     [string]$timestamp 
 
     try{ 
         Write-Log "Connecting to '$EndPointUrl'"
         $CurrentTime = (Get-Date).ToUniversalTime() 
         $webRequest = Invoke-WebRequest -Uri $EndPointUrl -UseBasicParsing 
         if($webRequest.StatusCode -eq 200){ 
             $result = $true 
             $UrlTime = [DateTime]::Parse($webRequest.Headers.Date).ToUniversalTime() 
             $rawResult = ('HttpResult: ' + $webRequest.StatusCode.ToString() + '; PingTime(ms): ' + ($CurrentTime - $UrlTime).TotalMilliseconds).ToString() 
             $timestamp = (Get-Date).ToString() 
             Write-Log "Web request returned - $rawResult"
         } 
     } 
     catch{ 
         $rawResult = $_.Exception 
         $timestamp = (Get-Date).ToString() 
         Write-Log "ERROR: $($_.Exception) CALLSTACK: $_"
     } 
 
     if($result){ 
         $returnProperties = @{ 
             Result=1; 
            RawResults=$rawResult; 
            TimeStamp=$timestamp 
         } 
     } 
     else{ 
         $returnProperties = @{ 
             Result=0; 
            RawResults=$rawResult; 
            TimeStamp=$timestamp 
         } 
     } 
     $resultObject = New-Object PsObject -Property $returnProperties 
     return $resultObject 
} 
 
## Validate install Files from a manifest file 
function Validate-Install{ 
     [CmdletBinding()] 
    Param( 
     [Parameter(Mandatory = $true)] 
     [string]$InstallPath, 
     [Parameter(Mandatory = $false)] 
     [string]$ManifestPath 
     ) 
 
     [bool]$result = $false 
     [string]$rawResult 
     [string]$timestamp 
 
     try{ 
         Write-Log "Validating Install at '$InstallPath'"
         if(Test-Path -Path $InstallPath) 
         { 
             Write-Log "Comparing '$InstallPath' to manifest"
             [System.Array]$installedfiles = @() 
             $installedFilesRaw = Get-ChildItem -Path $InstallPath -Recurse | Where {$_.PSIsContainer -eq $false} | Select-Object -Property Name 
            foreach($file in $installedFilesRaw){ 
                $installedfiles += $file.Name 
             } 
 
             if(Test-Path -Path $ManifestPath){ 
                 $manifestFiles = Get-Content -Path $ManifestPath 
                 $fileCompare = Compare-Object -ReferenceObject $manifestFiles -DifferenceObject $installedFiles -Property Name -PassThru 
                 $timestamp = (Get-Date).ToString() 
                 if($fileCompare -eq $null) 
                 { 
                     $rawResult = "Installed file ARE a match to the manifest" 
                     Write-Log "$rawResult"
                     $result = $true 
                 } 
                 else 
                 { 
                     $rawResult = ("{0} Files are missing." -f $fileCompare.Count ) 
                     Write-Log "$rawResult"
                 } 
             } 
             else{ 
                Throw "$ManifestPath does not exist." 
             } 
         } 
         else{ 
            Throw "$InstallPath does not exist." 
         } 
     } 
     catch{ 
         $rawResult = $_.Exception 
         $timestamp = (Get-Date).ToString() 
         Write-Log "ERROR: $($_.Exception) CALLSTACK: $_"
     } 
 
     if($result){ 
         $returnProperties = @{ 
             Result=1; 
            RawResults=$rawResult; 
            TimeStamp=$timestamp 
         } 
     } 
     else{ 
         $returnProperties = @{ 
             Result=0; 
            RawResults=$rawResult; 
            TimeStamp=$timestamp 
         } 
    } 
     $resultObject = New-Object PsObject -Property $returnProperties 
     return $resultObject 
} 
 
## Validate service is running 
function Validate-Service{ 
    [CmdletBinding()] 
    Param( 
     [Parameter(Mandatory = $true)] 
     [string]$ServiceName, 
     [Parameter(Mandatory = $true)] 
     [ValidateSet("Running","Stopped","Paused")] 
     [string]$CurrentState 
     ) 
 
     [bool]$result = $false 
     [string]$rawResult 
     [string]$timestamp 
 
     try{ 
         Write-Log "Validating Service: '$ServiceName' is $CurrentState"
         $thisService = Get-Service -Name $ServiceName 
         $timestamp = (Get-Date).ToString() 
         $rawResult = ("ServiceName: {0}; DisplayName: {1}; Status: {2}" -f $thisService.Name, $thisService.DisplayName, $thisService.Status) 
         if($thisService.Status.ToString() -eq $CurrentState) 
         { 
            $result = $true 
         } 
         Write-Log "Service: $ServiceName is $($thisService.Status)"
 
     } 
     catch{ 
         $rawResult = $_.Exception 
         $timestamp = (Get-Date).ToString() 
         Write-Log "ERROR: $($_.Exception) CALLSTACK: $_"
     } 
 
     if($result){ 
         $returnProperties = @{ 
             Result=1; 
            RawResults=$rawResult; 
            TimeStamp=$timestamp 
         } 
     } 
     else{ 
         $returnProperties = @{ 
             Result=0; 
            RawResults=$rawResult; 
            TimeStamp=$timestamp 
         } 
     } 
     $resultObject = New-Object PsObject -Property $returnProperties 
     return $resultObject 
} 
 
## Validate appPool is started 
function Validate-AppPool{ 
    [CmdletBinding()] 
    Param( 
     [Parameter(Mandatory = $true)] 
     [string]$AppPoolName, 
     [Parameter(Mandatory = $true)] 
     [ValidateSet("Started","Stopped")] 
     [string]$CurrentState 
     ) 
 
     [bool]$result = $false 
     [string]$rawResult 
     [string]$timestamp 
 
     try{ 
         Write-Log "Validating AppPool: '$AppPoolName' is $CurrentState"
         Get-WebAppPoolState 
         $appPoolStatus = Get-WebAppPoolState -Name $AppPoolName 
         $timestamp = (Get-Date).ToString() 
         $rawResult = ("AppPoolName: {0}; Status: {1}" -f $AppPoolName, $appPoolStatus) 
         if($appPoolStatus.Value -eq $CurrentState) 
         { 
            $result = $true 
         } 
         Write-Log "AppPool: $AppPoolName is $($appPoolStatus.Value)"
     } 
     catch{ 
         $rawResult = $_.Exception 
         $timestamp = (Get-Date).ToString() 
         Write-Log "ERROR: $($_.Exception) CALLSTACK: $_"
     } 
 
     if($result){ 
         $returnProperties = @{ 
             Result=1; 
            RawResults=$rawResult; 
            TimeStamp=$timestamp 
         } 
     } 
     else{ 
         $returnProperties = @{ 
             Result=0; 
            RawResults=$rawResult; 
            TimeStamp=$timestamp 
         } 
     } 
     $resultObject = New-Object PsObject -Property $returnProperties 
     return $resultObject 
} 




####################################################################################
## Parameter Setting
####################################################################################
Write-Log "Setting DVT execution parameters"

if(Test-Path -Path $InputXML)
{
    Write-Log "Parsing the xml for parameters/settings"
    [xml]$DVTParams = Get-Content -Path $InputXML
    [string]$ServiceName = $DVTParams.DVTParameters.ServiceName    
    [string]$AosWebrootPath = $DVTParams.DVTParameters.AosWebRootPath    
    [string]$XmlOutputPath = $DVTParams.DVTParameters.OutputPath    
	[string]$endPoint = $DVTParams.DVTParameters.EndPoint #Infrastructure.HostUrl
    [string]$installPath = $DVTParams.DVTParameters.InstallPath
	[string]$manifestFile = $DVTParams.DVTParameters.ManifestPath
	[string]$ServiceState = $DVTParams.DVTParameters.ServiceState
	[string]$AppPoolName = $DVTParams.DVTParameters.AppPoolName
	[string]$AppPoolState = $DVTParams.DVTParameters.AppPoolState
    [string]$BatchService = $DVTParams.DVTParameters.BatchService
}
else
{
    throw "Unable to parse settings from service model. Xml doesnt exist at: $InputXML"
}

if(-not ([string]::IsNullOrEmpty($CredentialsXml)))
{
    Write-Log "Parsing the CredentialsXml"
    if(Test-Path -Path $CredentialsXml)
    {
        Write-Log "Parsing the xml for local credentials"
        $localCredentials = Import-Clixml -Path $CredentialsXml
        [string]$UserName = $localCredentials.GetNetworkCredential().UserName
        [string]$UserPassword = $localCredentials.GetNetworkCredential().Password
    }
    else
    {
        throw "Unable to parse credentials from service model. Xml doesnt exist at: $CredentialsXML"
    }
}

Write-Log "Setting diagnostics-related parameters"
[string]$CollectorName = "$($ServiceName).DVT"
[string]$CollectorType = 'PowerShellCollector'
[string]$TargetName = (hostname)

if(-not (Test-Path -Path $XmlOutputPath))
{
    Write-Log "Creating diagnostics result directory at $XmlOutputPath"
    New-Item -Path $XmlOutputPath -Type Container | Out-Null
}

[string]$XMLFilePath = Join-Path -Path $XmlOutputPath -ChildPath "$([System.DateTime]::Now.ToFileTimeUtc())_$($ServiceName)DVTResults.xml"

####################################################################################
## Diagnostics Collector XML Template
####################################################################################
[xml]$xmlTemplate = @"
<?xml version="1.0"?>
<CollectionResult xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:xsd="http://www.w3.org/2001/XMLSchema">
  <CollectorName>$CollectorName</CollectorName>
  <CollectorType>$CollectorType</CollectorType>
  <ErrorMessages />
  <TabularResults>
    <TabularData>
      <TargetName>$TargetName</TargetName>
      <Columns>
        <string>TestName</string>
        <string>TestType</string>
        <string>PassResult</string>
        <string>RawResult</string>
        <string>TimeStamp</string>
      </Columns>
      <Rows>
      </Rows>
    </TabularData>
  </TabularResults>
</CollectionResult>
"@

####################################################################################
## Main Execution
####################################################################################

Write-Log "Running validations for $ServiceName"
try
{
    #Dependency validation
    Write-Log "Validate-AosDependencies -AosWebrootPath $AosWebrootPath -OutputPath $XmlOutputPath -Log $Log"
    $dependenciesResult = New-Object PsObject
    Validate-AosDependencies -AosWebrootPath $AosWebrootPath -OutputPath $XmlOutputPath -Log $Log ([ref]$dependenciesResult)
    
    Append-RowToXML -TestName 'AOSService.Validate-AosDependencies' -TestType 'DVT' -TestResult $dependenciesResult.Result -RawResult $dependenciesResult.RawResults -TimeStamp $dependenciesResult.TimeStamp -xmlTemplate $xmlTemplate | Out-Null
    
     #End point validation 
     Write-Log "Validate-Endpoint -EndPointUrl" 
     $endpointResult = Validate-Endpoint -EndPointUrl $endPoint
 
     Append-RowToXML -TestName 'AOS.Validate-Endpoint' -TestType 'DVT' -TestResult $endpointResult.Result -RawResult $endpointResult.RawResults -TimeStamp $endpointResult.TimeStamp -xmlTemplate $xmlTemplate | Out-Null 

    $ValidateBatch = (![System.String]::IsNullOrWhiteSpace($DVTParams.DVTParameters.ValidateBatch) -and [System.Convert]::ToBoolean($DVTParams.DVTParameters.ValidateBatch))
    if ($ValidateBatch)
    {
        #AXBatch Service 
        Write-Log "Validate-Service -ServiceName $BatchService -CurrentState $ServiceState" 
        $serviceResult = Validate-Service -ServiceName $BatchService -CurrentState $ServiceState 

        Append-RowToXML -TestName 'AOS.Validate-Service' -TestType 'DVT' -TestResult $serviceResult.Result -RawResult $serviceResult.RawResults -TimeStamp $serviceResult.TimeStamp -xmlTemplate $xmlTemplate | Out-Null 
    } 

     #IIS AppPool Validation 
     Write-Log "Validate-AppPool -AppPoolName $AppPoolName -CurrentState $AppPoolState"
     $apppoolResult = Validate-AppPool -AppPoolName $AppPoolName -CurrentState $AppPoolState 

     Append-RowToXML -TestName 'AOS.Validate-AppPool' -TestType 'DVT' -TestResult $apppoolResult.Result -RawResult $apppoolResult.RawResults -TimeStamp $apppoolResult.TimeStamp -xmlTemplate $xmlTemplate | Out-Null 

    #Writing XML results
    Write-Log "Writing DVT results to $XMLFilePath"
    $xmlTemplate.InnerXml | Out-File -FilePath $XMLFilePath -Force -Encoding utf8

    [bool]$dvtResult = $endpointResult.Result -and $apppoolResult.Result
    if ($ValidateBatch)
    {
        $dvtResult = $dvtResult -and $serviceResult.Result
    }

}
catch
{
    Write-Exception $_
}

if($dvtResult)
{
    $exitProperties = @{'ExitCode'= 0}
    $exitObject = New-Object PsObject -Property $exitProperties
    Write-Log "DVT Script Completed, ExitCode: $($exitObject.ExitCode)"
    return $exitObject
}
else
{
    $exitProperties = @{'ExitCode'= 1; 'Message'="DVT Validation failed, see log: '$Log' for further details, and '$XMLFilePath' for test results"}
    $exitObject = New-Object PsObject -Property $exitProperties
    Write-Log "DVT Script Completed, ExitCode: $($exitObject.ExitCode)"
    throw $exitObject
}


# SIG # Begin signature block
# MIIj9AYJKoZIhvcNAQcCoIIj5TCCI+ECAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCDs/PaFCEk7kQJj
# CroAsuy/nFdoMW3f3vLEi0U//6bA0KCCDYIwggYAMIID6KADAgECAhMzAAAAww6b
# p9iy3PcsAAAAAADDMA0GCSqGSIb3DQEBCwUAMH4xCzAJBgNVBAYTAlVTMRMwEQYD
# VQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNy
# b3NvZnQgQ29ycG9yYXRpb24xKDAmBgNVBAMTH01pY3Jvc29mdCBDb2RlIFNpZ25p
# bmcgUENBIDIwMTEwHhcNMTcwODExMjAyMDI0WhcNMTgwODExMjAyMDI0WjB0MQsw
# CQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9u
# ZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMR4wHAYDVQQDExVNaWNy
# b3NvZnQgQ29ycG9yYXRpb24wggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIB
# AQC7V9c40bEGf0ktqW2zY596urY6IVu0mK6N1KSBoMV1xSzvgkAqt4FTd/NjAQq8
# zjeEA0BDV4JLzu0ftv2AbcnCkV0Fx9xWWQDhDOtX3v3xuJAnv3VK/HWycli2xUib
# M2IF0ZWUpb85Iq2NEk1GYtoyGc6qIlxWSLFvRclndmJdMIijLyjFH1Aq2YbbGhEl
# gcL09Wcu53kd9eIcdfROzMf8578LgEcp/8/NabEMC2DrZ+aEG5tN/W1HOsfZwWFh
# 8pUSoQ0HrmMh2PSZHP94VYHupXnoIIJfCtq1UxlUAVcNh5GNwnzxVIaA4WLbgnM+
# Jl7wQBLSOdUmAw2FiDFfCguLAgMBAAGjggF/MIIBezAfBgNVHSUEGDAWBgorBgEE
# AYI3TAgBBggrBgEFBQcDAzAdBgNVHQ4EFgQUpxNdHyGJVegD7p4XNuryVIg1Ga8w
# UQYDVR0RBEowSKRGMEQxDDAKBgNVBAsTA0FPQzE0MDIGA1UEBRMrMjMwMDEyK2M4
# MDRiNWVhLTQ5YjQtNDIzOC04MzYyLWQ4NTFmYTIyNTRmYzAfBgNVHSMEGDAWgBRI
# bmTlUAXTgqoXNzcitW2oynUClTBUBgNVHR8ETTBLMEmgR6BFhkNodHRwOi8vd3d3
# Lm1pY3Jvc29mdC5jb20vcGtpb3BzL2NybC9NaWNDb2RTaWdQQ0EyMDExXzIwMTEt
# MDctMDguY3JsMGEGCCsGAQUFBwEBBFUwUzBRBggrBgEFBQcwAoZFaHR0cDovL3d3
# dy5taWNyb3NvZnQuY29tL3BraW9wcy9jZXJ0cy9NaWNDb2RTaWdQQ0EyMDExXzIw
# MTEtMDctMDguY3J0MAwGA1UdEwEB/wQCMAAwDQYJKoZIhvcNAQELBQADggIBAE2X
# TzR+8XCTnOPVGkucEX5rJsSlJPTfRNQkurNqCImZmssx53Cb/xQdsAc5f+QwOxMi
# 3g7IlWe7bn74fJWkkII3k6aD00kCwaytWe+Rt6dmAA6iTCXU3OddBwLKKDRlOzmD
# rZUqjsqg6Ag6HP4+e0BJlE2OVCUK5bHHCu5xN8abXjb1p0JE+7yHsA3ANdkmh1//
# Z+8odPeKMAQRimfMSzVgaiHnw40Hg16bq51xHykmCRHU9YLT0jYHKa7okm2QfwDJ
# qFvu0ARl+6EOV1PM8piJ858Vk8gGxGNSYQJPV0gc9ft1Esq1+fTCaV+7oZ0NaYMn
# 64M+HWsxw+4O8cSEQ4fuMZwGADJ8tyCKuQgj6lawGNSyvRXsN+1k02sVAiPGijOH
# OtGbtsCWWSygAVOEAV/ye8F6sOzU2FL2X3WBRFkWOCdTu1DzXnHf99dR3DHVGmM1
# Kpd+n2Y3X89VM++yyrwsI6pEHu77Z0i06ELDD4pRWKJGAmEmWhm/XJTpqEBw51sw
# THyA1FBnoqXuDus9tfHleR7h9VgZb7uJbXjiIFgl/+RIs+av8bJABBdGUNQMbJEU
# fe7K4vYm3hs7BGdRLg+kF/dC/z+RiTH4p7yz5TpS3Cozf0pkkWXYZRG222q3tGxS
# /L+LcRbELM5zmqDpXQjBRUWlKYbsATFtXnTGVjELMIIHejCCBWKgAwIBAgIKYQ6Q
# 0gAAAAAAAzANBgkqhkiG9w0BAQsFADCBiDELMAkGA1UEBhMCVVMxEzARBgNVBAgT
# Cldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29m
# dCBDb3Jwb3JhdGlvbjEyMDAGA1UEAxMpTWljcm9zb2Z0IFJvb3QgQ2VydGlmaWNh
# dGUgQXV0aG9yaXR5IDIwMTEwHhcNMTEwNzA4MjA1OTA5WhcNMjYwNzA4MjEwOTA5
# WjB+MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMH
# UmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSgwJgYDVQQD
# Ex9NaWNyb3NvZnQgQ29kZSBTaWduaW5nIFBDQSAyMDExMIICIjANBgkqhkiG9w0B
# AQEFAAOCAg8AMIICCgKCAgEAq/D6chAcLq3YbqqCEE00uvK2WCGfQhsqa+laUKq4
# BjgaBEm6f8MMHt03a8YS2AvwOMKZBrDIOdUBFDFC04kNeWSHfpRgJGyvnkmc6Whe
# 0t+bU7IKLMOv2akrrnoJr9eWWcpgGgXpZnboMlImEi/nqwhQz7NEt13YxC4Ddato
# 88tt8zpcoRb0RrrgOGSsbmQ1eKagYw8t00CT+OPeBw3VXHmlSSnnDb6gE3e+lD3v
# ++MrWhAfTVYoonpy4BI6t0le2O3tQ5GD2Xuye4Yb2T6xjF3oiU+EGvKhL1nkkDst
# rjNYxbc+/jLTswM9sbKvkjh+0p2ALPVOVpEhNSXDOW5kf1O6nA+tGSOEy/S6A4aN
# 91/w0FK/jJSHvMAhdCVfGCi2zCcoOCWYOUo2z3yxkq4cI6epZuxhH2rhKEmdX4ji
# JV3TIUs+UsS1Vz8kA/DRelsv1SPjcF0PUUZ3s/gA4bysAoJf28AVs70b1FVL5zmh
# D+kjSbwYuER8ReTBw3J64HLnJN+/RpnF78IcV9uDjexNSTCnq47f7Fufr/zdsGbi
# wZeBe+3W7UvnSSmnEyimp31ngOaKYnhfsi+E11ecXL93KCjx7W3DKI8sj0A3T8Hh
# hUSJxAlMxdSlQy90lfdu+HggWCwTXWCVmj5PM4TasIgX3p5O9JawvEagbJjS4NaI
# jAsCAwEAAaOCAe0wggHpMBAGCSsGAQQBgjcVAQQDAgEAMB0GA1UdDgQWBBRIbmTl
# UAXTgqoXNzcitW2oynUClTAZBgkrBgEEAYI3FAIEDB4KAFMAdQBiAEMAQTALBgNV
# HQ8EBAMCAYYwDwYDVR0TAQH/BAUwAwEB/zAfBgNVHSMEGDAWgBRyLToCMZBDuRQF
# TuHqp8cx0SOJNDBaBgNVHR8EUzBRME+gTaBLhklodHRwOi8vY3JsLm1pY3Jvc29m
# dC5jb20vcGtpL2NybC9wcm9kdWN0cy9NaWNSb29DZXJBdXQyMDExXzIwMTFfMDNf
# MjIuY3JsMF4GCCsGAQUFBwEBBFIwUDBOBggrBgEFBQcwAoZCaHR0cDovL3d3dy5t
# aWNyb3NvZnQuY29tL3BraS9jZXJ0cy9NaWNSb29DZXJBdXQyMDExXzIwMTFfMDNf
# MjIuY3J0MIGfBgNVHSAEgZcwgZQwgZEGCSsGAQQBgjcuAzCBgzA/BggrBgEFBQcC
# ARYzaHR0cDovL3d3dy5taWNyb3NvZnQuY29tL3BraW9wcy9kb2NzL3ByaW1hcnlj
# cHMuaHRtMEAGCCsGAQUFBwICMDQeMiAdAEwAZQBnAGEAbABfAHAAbwBsAGkAYwB5
# AF8AcwB0AGEAdABlAG0AZQBuAHQALiAdMA0GCSqGSIb3DQEBCwUAA4ICAQBn8oal
# mOBUeRou09h0ZyKbC5YR4WOSmUKWfdJ5DJDBZV8uLD74w3LRbYP+vj/oCso7v0ep
# o/Np22O/IjWll11lhJB9i0ZQVdgMknzSGksc8zxCi1LQsP1r4z4HLimb5j0bpdS1
# HXeUOeLpZMlEPXh6I/MTfaaQdION9MsmAkYqwooQu6SpBQyb7Wj6aC6VoCo/KmtY
# SWMfCWluWpiW5IP0wI/zRive/DvQvTXvbiWu5a8n7dDd8w6vmSiXmE0OPQvyCInW
# H8MyGOLwxS3OW560STkKxgrCxq2u5bLZ2xWIUUVYODJxJxp/sfQn+N4sOiBpmLJZ
# iWhub6e3dMNABQamASooPoI/E01mC8CzTfXhj38cbxV9Rad25UAqZaPDXVJihsMd
# YzaXht/a8/jyFqGaJ+HNpZfQ7l1jQeNbB5yHPgZ3BtEGsXUfFL5hYbXw3MYbBL7f
# QccOKO7eZS/sl/ahXJbYANahRr1Z85elCUtIEJmAH9AAKcWxm6U/RXceNcbSoqKf
# enoi+kiVH6v7RyOA9Z74v2u3S5fi63V4GuzqN5l5GEv/1rMjaHXmr/r8i+sLgOpp
# O6/8MO0ETI7f33VtY5E90Z1WTk+/gFcioXgRMiF670EKsT/7qMykXcGhiJtXcVZO
# SEXAQsmbdlsKgEhr/Xmfwb1tbWrJUnMTDXpQzTGCFcgwghXEAgEBMIGVMH4xCzAJ
# BgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25k
# MR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xKDAmBgNVBAMTH01pY3Jv
# c29mdCBDb2RlIFNpZ25pbmcgUENBIDIwMTECEzMAAADDDpun2LLc9ywAAAAAAMMw
# DQYJYIZIAWUDBAIBBQCggbowGQYJKoZIhvcNAQkDMQwGCisGAQQBgjcCAQQwHAYK
# KwYBBAGCNwIBCzEOMAwGCisGAQQBgjcCARUwLwYJKoZIhvcNAQkEMSIEIDrKFOux
# EK/XtqSrxndTF/HDXn0gvTlSKgbvdrfDoQJKME4GCisGAQQBgjcCAQwxQDA+oCCA
# HgBWAGEAbABpAGQAYQB0AGUAQQBPAFMALgBwAHMAMaEagBhodHRwOi8vd3d3Lm1p
# Y3Jvc29mdC5jb20wDQYJKoZIhvcNAQEBBQAEggEAYCwGgM8Jyg6Kfwrlu7kTdTSu
# YZX59Tvg7m3qtoozgaX4wFmykfDgmEdAtKnGi0wevEtIUMpN6iFa6R5tHr988OXz
# aKfjONmrwwtb0LocDE14GsYgQa9JKNk2XUkriMJbyt7QJozLdFOx7D6b8MqkC8Aa
# iEdcJtsR9uWBpvCIjwIgHHN8zPQOEj3Pxae3W0tJj7KoVCiWQQvJ7D8jDgiBWprb
# gTiH7+0PfCip5IHA5iGCgGVz+BijeedUTPaK5A8UCVsp5p6us/F+jwacrHMlsoS8
# +ECcy/CnqGzdYurHdo9x/bOIQp9Z04Ws2BWpepSNRydESfXKOWVKOvi5h11iGaGC
# E0YwghNCBgorBgEEAYI3AwMBMYITMjCCEy4GCSqGSIb3DQEHAqCCEx8wghMbAgED
# MQ8wDQYJYIZIAWUDBAIBBQAwggE7BgsqhkiG9w0BCRABBKCCASoEggEmMIIBIgIB
# AQYKKwYBBAGEWQoDATAxMA0GCWCGSAFlAwQCAQUABCDi/T8Hg1jhq4VfBSDTTxoP
# xUHJcsVwkOZMbWnIrLTYiAIGWrKvYLMzGBMyMDE4MDMyNTIxMDU1NC4wMjRaMAcC
# AQGAAgH0oIG3pIG0MIGxMQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3Rv
# bjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0
# aW9uMQwwCgYDVQQLEwNBT0MxJjAkBgNVBAsTHVRoYWxlcyBUU1MgRVNOOjk2RkYt
# NEJDNS1BN0RDMSUwIwYDVQQDExxNaWNyb3NvZnQgVGltZS1TdGFtcCBTZXJ2aWNl
# oIIOyzCCBnEwggRZoAMCAQICCmEJgSoAAAAAAAIwDQYJKoZIhvcNAQELBQAwgYgx
# CzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRt
# b25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xMjAwBgNVBAMTKU1p
# Y3Jvc29mdCBSb290IENlcnRpZmljYXRlIEF1dGhvcml0eSAyMDEwMB4XDTEwMDcw
# MTIxMzY1NVoXDTI1MDcwMTIxNDY1NVowfDELMAkGA1UEBhMCVVMxEzARBgNVBAgT
# Cldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29m
# dCBDb3Jwb3JhdGlvbjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRpbWUtU3RhbXAgUENB
# IDIwMTAwggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIBAQCpHQ28dxGKOiDs
# /BOX9fp/aZRrdFQQ1aUKAIKF++18aEssX8XD5WHCdrc+Zitb8BVTJwQxH0EbGpUd
# zgkTjnxhMFmxMEQP8WCIhFRDDNdNuDgIs0Ldk6zWczBXJoKjRQ3Q6vVHgc2/JGAy
# WGBG8lhHhjKEHnRhZ5FfgVSxz5NMksHEpl3RYRNuKMYa+YaAu99h/EbBJx0kZxJy
# GiGKr0tkiVBisV39dx898Fd1rL2KQk1AUdEPnAY+Z3/1ZsADlkR+79BL/W7lmsqx
# qPJ6Kgox8NpOBpG2iAg16HgcsOmZzTznL0S6p/TcZL2kAcEgCZN4zfy8wMlEXV4W
# nAEFTyJNAgMBAAGjggHmMIIB4jAQBgkrBgEEAYI3FQEEAwIBADAdBgNVHQ4EFgQU
# 1WM6XIoxkPNDe3xGG8UzaFqFbVUwGQYJKwYBBAGCNxQCBAweCgBTAHUAYgBDAEEw
# CwYDVR0PBAQDAgGGMA8GA1UdEwEB/wQFMAMBAf8wHwYDVR0jBBgwFoAU1fZWy4/o
# olxiaNE9lJBb186aGMQwVgYDVR0fBE8wTTBLoEmgR4ZFaHR0cDovL2NybC5taWNy
# b3NvZnQuY29tL3BraS9jcmwvcHJvZHVjdHMvTWljUm9vQ2VyQXV0XzIwMTAtMDYt
# MjMuY3JsMFoGCCsGAQUFBwEBBE4wTDBKBggrBgEFBQcwAoY+aHR0cDovL3d3dy5t
# aWNyb3NvZnQuY29tL3BraS9jZXJ0cy9NaWNSb29DZXJBdXRfMjAxMC0wNi0yMy5j
# cnQwgaAGA1UdIAEB/wSBlTCBkjCBjwYJKwYBBAGCNy4DMIGBMD0GCCsGAQUFBwIB
# FjFodHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20vUEtJL2RvY3MvQ1BTL2RlZmF1bHQu
# aHRtMEAGCCsGAQUFBwICMDQeMiAdAEwAZQBnAGEAbABfAFAAbwBsAGkAYwB5AF8A
# UwB0AGEAdABlAG0AZQBuAHQALiAdMA0GCSqGSIb3DQEBCwUAA4ICAQAH5ohRDeLG
# 4Jg/gXEDPZ2joSFvs+umzPUxvs8F4qn++ldtGTCzwsVmyWrf9efweL3HqJ4l4/m8
# 7WtUVwgrUYJEEvu5U4zM9GASinbMQEBBm9xcF/9c+V4XNZgkVkt070IQyK+/f8Z/
# 8jd9Wj8c8pl5SpFSAK84Dxf1L3mBZdmptWvkx872ynoAb0swRCQiPM/tA6WWj1kp
# vLb9BOFwnzJKJ/1Vry/+tuWOM7tiX5rbV0Dp8c6ZZpCM/2pif93FSguRJuI57BlK
# cWOdeyFtw5yjojz6f32WapB4pm3S4Zz5Hfw42JT0xqUKloakvZ4argRCg7i1gJsi
# OCC1JeVk7Pf0v35jWSUPei45V3aicaoGig+JFrphpxHLmtgOR5qAxdDNp9DvfYPw
# 4TtxCd9ddJgiCGHasFAeb73x4QDf5zEHpJM692VHeOj4qEir995yfmFrb3epgcun
# Caw5u+zGy9iCtHLNHfS4hQEegPsbiSpUObJb2sgNVZl6h3M7COaYLeqN4DMuEin1
# wC9UJyH3yKxO2ii4sanblrKnQqLJzxlBTeCG+SqaoxFmMNO7dDJL32N79ZmKLxvH
# Ia9Zta7cRDyXUHHXodLFVeNp3lfB0d4wwP3M5k37Db9dT+mdHhk4L7zPWAUu7w2g
# UDXa7wknHNWzfjUeCLraNtvTX4/edIhJEjCCBNgwggPAoAMCAQICEzMAAAC2i0dD
# ssytHwQAAAAAALYwDQYJKoZIhvcNAQELBQAwfDELMAkGA1UEBhMCVVMxEzARBgNV
# BAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jv
# c29mdCBDb3Jwb3JhdGlvbjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRpbWUtU3RhbXAg
# UENBIDIwMTAwHhcNMTcxMDAyMjMwMDUyWhcNMTkwMTAyMjMwMDUyWjCBsTELMAkG
# A1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQx
# HjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEMMAoGA1UECxMDQU9DMSYw
# JAYDVQQLEx1UaGFsZXMgVFNTIEVTTjo5NkZGLTRCQzUtQTdEQzElMCMGA1UEAxMc
# TWljcm9zb2Z0IFRpbWUtU3RhbXAgU2VydmljZTCCASIwDQYJKoZIhvcNAQEBBQAD
# ggEPADCCAQoCggEBANiJZxdISwi3RBuTEcM6z25BQKaoXGJjslsjRDM19Z7d/cBy
# y4tJbDB7IQBlkpYpRKcMe1M/WU4ge5ZuslgQ7649EYd8NWYqb7X8r9DCSnKtP84Q
# 49cQCcXlEuNfzmDo2/hqSW0/JaBpUaej1iz8Q+FCCUo0PVRISiS/fOHdpmcL3myx
# UrjHyNIRmyZ0/px3YBpmYywMP9gBBN++eTMKyeo/u6UUdjWHEtl3XTIW8e7y921g
# XSh9J2ZpHUkX5JXt+A7+uGeb/7y67R3XpPB7CbAoBGpKcxEk1fPKNRNsVsXGHHDW
# E7WzRga0LKpJROeYlQ8Vu9OlLXkIAYAfDaZMwTECAwEAAaOCARswggEXMB0GA1Ud
# DgQWBBTzbcKQAScg2o8zHMBfaGrfgQOF0DAfBgNVHSMEGDAWgBTVYzpcijGQ80N7
# fEYbxTNoWoVtVTBWBgNVHR8ETzBNMEugSaBHhkVodHRwOi8vY3JsLm1pY3Jvc29m
# dC5jb20vcGtpL2NybC9wcm9kdWN0cy9NaWNUaW1TdGFQQ0FfMjAxMC0wNy0wMS5j
# cmwwWgYIKwYBBQUHAQEETjBMMEoGCCsGAQUFBzAChj5odHRwOi8vd3d3Lm1pY3Jv
# c29mdC5jb20vcGtpL2NlcnRzL01pY1RpbVN0YVBDQV8yMDEwLTA3LTAxLmNydDAM
# BgNVHRMBAf8EAjAAMBMGA1UdJQQMMAoGCCsGAQUFBwMIMA0GCSqGSIb3DQEBCwUA
# A4IBAQAv19XqvpiOeBy6wypDpE1MzGUzKEcV5TqW3hbl1zq7PTwqQMYjIrhA2dj8
# UWRSETiDxu9K+cIIKZmBLpaFZTKcReDsqB2Gmmsp3bixBP+33/lKKNsQ8BIszJf5
# 2bSqKGLIsCqD66X10OgK4epSQs2sRAcpGe5eMZY/+HW35djuRHzMj9lHDNbA6OsQ
# jx/KjbBeH6iOanurNuT18zMMdd8pL2TInt3bfQbDGdY0k2kPB1pLoFSVwB55TZFq
# KJen1UZUdJu5afUeAzqcZjq3aOvMJ8IDixroQQWFYZJJkpIB+XNk+a0M/t3d0r8f
# Yr660odXElNAB4TbTMOuWre2rGRIoYIDdjCCAl4CAQEwgeGhgbekgbQwgbExCzAJ
# BgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25k
# MR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xDDAKBgNVBAsTA0FPQzEm
# MCQGA1UECxMdVGhhbGVzIFRTUyBFU046OTZGRi00QkM1LUE3REMxJTAjBgNVBAMT
# HE1pY3Jvc29mdCBUaW1lLVN0YW1wIFNlcnZpY2WiJQoBATAJBgUrDgMCGgUAAxUA
# /xYr7xVcs9W1liu+CEsh/E10AAGggcEwgb6kgbswgbgxCzAJBgNVBAYTAlVTMRMw
# EQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVN
# aWNyb3NvZnQgQ29ycG9yYXRpb24xDDAKBgNVBAsTA0FPQzEnMCUGA1UECxMebkNp
# cGhlciBOVFMgRVNOOjI2NjUtNEMzRi1DNURFMSswKQYDVQQDEyJNaWNyb3NvZnQg
# VGltZSBTb3VyY2UgTWFzdGVyIENsb2NrMA0GCSqGSIb3DQEBBQUAAgUA3mHSPTAi
# GA8yMDE4MDMyNTA3NDYwNVoYDzIwMTgwMzI2MDc0NjA1WjB3MD0GCisGAQQBhFkK
# BAExLzAtMAoCBQDeYdI9AgEAMAoCAQACAgg8AgH/MAcCAQACAhYYMAoCBQDeYyO9
# AgEAMDYGCisGAQQBhFkKBAIxKDAmMAwGCisGAQQBhFkKAwGgCjAIAgEAAgMW42Ch
# CjAIAgEAAgMehIAwDQYJKoZIhvcNAQEFBQADggEBAIe0VM1/1WGZ66wiWwoJdqnX
# sQLOwNkAZTOKqpGeLYOWoSHPolJ6HJJwf/kFJdy2PG8uDk3abUVcmB7QZRtaea9C
# pycEnFQeU+WsPSdydjUhBY9R274O+YUc5uUnY9y5DFTQTPrlYiIL2IS+gbbBeusO
# 1QSg1SUz6JmkwkVz0hwOtICmnDWMEBGwrRP663h++VWYEbSarMFdt816KZL2Ccmg
# AGFWqYadAXVXRoo4jF9TGn5983HflM6ASq+YgMW5BuZhjKR3KdPovLuB3Yht2ciW
# 80VsHJBkSGAgP7X4Qe8Tv4ccqdAOjB1OpeOfP2Ta6/kjFNSJ34ErsKuZcNtbm7Ex
# ggL1MIIC8QIBATCBkzB8MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3Rv
# bjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0
# aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0EgMjAxMAITMwAA
# ALaLR0OyzK0fBAAAAAAAtjANBglghkgBZQMEAgEFAKCCATIwGgYJKoZIhvcNAQkD
# MQ0GCyqGSIb3DQEJEAEEMC8GCSqGSIb3DQEJBDEiBCAuGY7q01dMvz1LNol2jm60
# KZZtovXxZgEwN5+ZX/6KwTCB4gYLKoZIhvcNAQkQAgwxgdIwgc8wgcwwgbEEFP8W
# K+8VXLPVtZYrvghLIfxNdAABMIGYMIGApH4wfDELMAkGA1UEBhMCVVMxEzARBgNV
# BAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jv
# c29mdCBDb3Jwb3JhdGlvbjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRpbWUtU3RhbXAg
# UENBIDIwMTACEzMAAAC2i0dDssytHwQAAAAAALYwFgQULhb4FpkwxJhZ0fMHreuA
# GLhiyHswDQYJKoZIhvcNAQELBQAEggEAeG6tk6o4/mLdNfg+QXFIh/kNOR6HjfxE
# 0mYm5PLlpvfpIz/YlrzbLE0HysezOoSTatzLNBCBSWASQq4pzn+ldUpOoK58F5Gw
# oseh608TQm6m9i/AN5j2PwomwJaTWP4NwuWn1sxVJ750cy/Wdi+GV9ct/4VCoWu7
# EXvIIwLO8wY21ubI6vWvnNQl9qItR9B8lg960ixFezmTB2cFpf7pQNBeoEZjX4y4
# ylTdCJtcr8U8aT9ceyaUBjZhWxLSXfi8llSGwdNXfL1QUm08gtNZu2UF87SsK8SB
# 2urRy/YiY6qCvowrvpDabtVSdPHOjCUhnLoGGcv3rb46AeP7e3DY6A==
# SIG # End signature block
