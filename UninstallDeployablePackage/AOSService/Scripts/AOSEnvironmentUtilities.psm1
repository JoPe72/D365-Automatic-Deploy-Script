param
(
    [parameter(Position=0,Mandatory=$false)][boolean] $useServiceFabric=$false 
)

Import-Module "$PSScriptRoot\CommonRollbackUtilities.psm1"  -ArgumentList $useServiceFabric -DisableNameChecking

function Get-ApplicationEnvironment
{
    $ErrorActionPreference = 'Stop'
    $webroot = Get-AosWebSitePhysicalPath
    #need to load the Microsoft.Dynamics.ApplicationPlatform.Environment.dll and all the dll it referenced
    $dllPath = Join-Path $webroot 'bin\Microsoft.Dynamics.ApplicationPlatform.Environment.dll'
    Load-DllinMemory -dllPath $dllPath
    $dllPath = Join-Path $webroot 'bin\Microsoft.Dynamics.AX.Configuration.Base.dll'
    Load-DllinMemory -dllPath $dllPath
    $dllPath = Join-Path $webroot 'bin\Microsoft.Dynamics.AX.Framework.EncryptionEngine.dll'
    Load-DllinMemory -dllPath $dllPath
    $dllPath = Join-Path $webroot 'bin\Microsoft.Dynamics.BusinessPlatform.SharedTypes.dll'
    Load-DllinMemory -dllPath $dllPath

    $config = [Microsoft.Dynamics.ApplicationPlatform.Environment.EnvironmentFactory]::GetApplicationEnvironment()
    
    return $config
}

function Load-DllinMemory([string] $dllPath)
{
    #try catch as not all dll exist in RTM version, some dependency/dll are introduced at update 1 or later
    #powershell cannot unload dll once it's loaded, the trick is to create an in-memory copy of the dll than load it
    #after the loading of in-memory dll, the physical dll stay unlocked

    try
    {
        $bytes = [System.IO.File]::ReadAllBytes($dllPath)
        [System.Reflection.Assembly]::Load($bytes) >$null
    }
    catch
    {}
}

function GenerateMetadataModuleInstallationInfo
{
    try
    {
        $ErrorActionPreference = 'Stop'

        write-output "Creating Metadata Module Installation Info."
        
        $packagePath = Get-AOSPackageDirectory
        $CommonBin = $(Get-CommonBinDir)

        $dllPath = Join-Path $CommonBin 'bin\Microsoft.Dynamics.AX.AXInstallationInfo.dll'
        Load-DllinMemory -dllPath $dllPath
        $dllPath = Join-Path $CommonBin 'bin\Microsoft.Dynamics.AX.Metadata.Storage.dll'
        Load-DllinMemory -dllPath $dllPath
        $dllPath = Join-Path $CommonBin 'bin\Microsoft.Dynamics.AX.Metadata.dll'
        Load-DllinMemory -dllPath $dllPath
        $dllPath = Join-Path $CommonBin 'bin\Microsoft.Dynamics.AX.Metadata.Core.dll'
        Load-DllinMemory -dllPath $dllPath
        $dllPath = Join-Path $CommonBin 'bin\Microsoft.Dynamics.ApplicationPlatform.XppServices.Instrumentation.dll'
        Load-DllinMemory -dllPath $dllPath

        [Microsoft.Dynamics.AX.AXInstallationInfo.AXInstallationInfo]::ScanMetadataModelInRuntimePackage($packagePath)
    }
    catch
    {}
}

function Get-IsAppFallOrLater([Parameter(Mandatory=$false)] $webroot)
{
    $version = Get-ApplicationReleaseFromAOS -webroot:$webroot

    return $($version -ne "RTW")
}

function Get-ApplicationReleaseFromAOS([Parameter(Mandatory=$false)] $webroot)
{
    if ($webroot -eq $null) {
        $webroot = Get-AosWebSitePhysicalPath
    }


    #must use job or process to load the production information provider dll or it'll lock it self
    #in memory copy is not usable as this dll have some special hard coded reference dll which won't resolve when loaded in memory.
    $job = Start-Job -ScriptBlock  {
        param($webrootBlock)
        $VersionDLLPath = Join-Path $webrootBlock 'bin\Microsoft.Dynamics.BusinessPlatform.ProductInformation.Provider.dll'
        Add-Type -Path $VersionDLLPath
        $provider = [Microsoft.Dynamics.BusinessPlatform.ProductInformation.Provider.ProductInfoProvider]::get_Provider();
        $version = $provider.get_ApplicationVersion();
        $version
    } -ArgumentList $webroot
    Wait-Job -Job $job >>null
    $version = Receive-Job -Job $job

    if($((![string]::IsNullOrEmpty($version)) -and ($version -ne '7.0') -and ($version -ne '7.0.0.0')))
    {
        return $version
    }
    else
    {
        return "RTW"
    }
}

function Get-ApplicationReleaseFromPackage
{
    $packageRoot = split-Path -parent "$(split-Path -parent $PSScriptRoot)" 
    $PackageInstallationInfo = "$packageRoot\HotfixInstallationInfo.xml"
    $XPath = '/HotfixInstallationInfo/ServiceModelList/ComponentModel/Release[../ServiceModelGroup = "Application"]'
    $ApplicationRelease =  Select-Xml -Path $PackageInstallationInfo -XPath $Xpath 
    $MRXPath = '/HotfixInstallationInfo/ServiceModelList/ComponentModel[Name = "MRApplicationService"]'
    $MRApplicationServiceModel =  Select-Xml -Path $PackageInstallationInfo -XPath $MRXpath 

    if($ApplicationRelease.Count -ge 1)
    {
        return $ApplicationRelease[0].Node.InnerText
    }
    elseif ($MRApplicationServiceModel -eq $null)
    {
        return ""
    }
    else
    {
        return "RTW"
    }
}

function Get-IsModulePartOfPlatformAsBinary ([string] $packageNugetFile)
{
    [Void][Reflection.Assembly]::LoadWithPartialName('System.IO.Compression.FileSystem') 
    $PackFiles = [IO.Compression.ZipFile]::OpenRead($packageNugetFile).Entries
    $PackageSpec =  $PackFiles | where {($_.Name -like '*.nuspec')}

    if(!($PackageSpec))
    {
        Throw "Unable to get package information"
    }

    [System.Xml.XmlDocument] $xmlDoc = New-Object System.Xml.XmlDocument
    $XmlDoc.Load($PackageSpec.Open())

    $Description = $xmlDoc.GetElementsByTagName('description').Item(0).InnerText

    if($Description.Contains("[Platform Package]"))
    {
        return $true
    }
    else
    {
        return $false
    }
}

function Get-IsModulePartOfApplicationAsBinary ([string] $PackageNugetFilePath)
{
    [Void][Reflection.Assembly]::LoadWithPartialName('System.IO.Compression.FileSystem') 
    $PackFiles = [IO.Compression.ZipFile]::OpenRead($PackageNugetFilePath).Entries
    $PackageSpec =  $PackFiles | Where-Object {($_.Name -like '*.nuspec')}

    if(!($PackageSpec))
    {
        Throw "Unable to get package information"
    }

    [System.Xml.XmlDocument] $xmlDoc=new-object System.Xml.XmlDocument
    $XmlDoc.Load($PackageSpec.Open())

    $Description = $xmlDoc.GetElementsByTagName('description').Item(0).InnerText

    if($Description.Contains("[Application Package]"))
    {
        return $true
    }
    else
    {
        return $false
    }
}

function Get-IsPlatformUpdate3OrLater([Parameter(Mandatory=$false)] $webroot)
{
    if (!$webroot) {
    $webroot = Get-AosWebSitePhysicalPath
    }

    #must use job or process to load the production information provider dll or it'll lock it self
    #in memory copy is not usable as this dll have some special hard coded reference dll which won't resolve when loaded in memory.
    $job = Start-Job -ScriptBlock  {
        param($webrootBlock)
        $VersionDLLPath = Join-Path $webrootBlock 'bin\Microsoft.Dynamics.BusinessPlatform.ProductInformation.Provider.dll'
        Add-Type -Path $VersionDLLPath
        $provider = [Microsoft.Dynamics.BusinessPlatform.ProductInformation.Provider.ProductInfoProvider]::get_Provider();
        $version = $provider.get_PlatformVersion();
        $version
    } -ArgumentList $webroot
    Wait-Job -Job $job | Out-Null
    $version = Receive-Job -Job $job

    return $(($version -ne '7.0') -and ($version -ne '7.0.0.0') -and (![string]::IsNullOrEmpty($version)))
    
}

function Get-IsPackageContainUpgradeBinaryForUpdate3
{
    $sourcePath = [IO.Path]::Combine($(split-Path -parent $PSScriptRoot), "Packages")
    #using a framework package from platform which customer cannot generate to identify if it's from platform update 3
    $files=get-childitem -Path:$sourcePath dynamicsax-framework-bin.*.nupkg
    foreach ($packageFile in $files) 
    {
        if(Get-IsModulePartOfPlatformAsBinary -packageNugetFile $packageFile.FullName)
        {
            return $true
        }
    }

    return $false
}

function Get-ProductPlatformBuildVersion
{
    $webroot = Get-AosWebSitePhysicalPath

    #must use job or process to load the production information provider dll or it'll lock it self
    #in memory copy is not usable as this dll have some special hard coded reference dll which won't resolve when loaded in memory.
    $job = Start-Job -ScriptBlock  {
        param($webrootBlock)
        $VersionDLLPath = Join-Path $webrootBlock 'bin\Microsoft.Dynamics.BusinessPlatform.ProductInformation.Provider.dll'
        Add-Type -Path $VersionDLLPath
        $provider = [Microsoft.Dynamics.BusinessPlatform.ProductInformation.Provider.ProductInfoProvider]::get_Provider();
        $version = $provider.get_PlatformBuildVersion();
        $version
    } -ArgumentList $webroot
    Wait-Job -Job $job >>null
    $version = Receive-Job -Job $job
   
    $build = [System.Version]::new()
    $releaseBuild
    if([System.Version]::TryParse($Version, [ref]$build))
    {
        $releaseBuild = $build.Build
    }
    else
    {
        #default to 0 from 7.0.0.0 
        $releaseBuild = 0
    }   
    return  $releaseBuild
}

function Get-ProductApplicationVersion ([Parameter(Mandatory=$false)] $webroot)
{
    if($webroot -eq $null)
    {
        $webroot = Get-AosWebSitePhysicalPath
    }

    #must use job or process to load the production information provider dll or it'll lock it self
    #in memory copy is not usable as this dll have some special hard coded reference dll which won't resolve when loaded in memory.
    $job = Start-Job -ScriptBlock  {
        param($webrootBlock)
        $VersionDLLPath = Join-Path $webrootBlock 'bin\Microsoft.Dynamics.BusinessPlatform.ProductInformation.Provider.dll'
        Add-Type -Path $VersionDLLPath
        $provider = [Microsoft.Dynamics.BusinessPlatform.ProductInformation.Provider.ProductInfoProvider]::get_Provider();
        $version = $provider.get_ApplicationBuildVersion();
        $version
    } -ArgumentList $webroot
    Wait-Job -Job $job | Out-Null
    $version = Receive-Job -Job $job
    
    
    return  $version
}

function Get-DataAccessSqlPwd
{
    $Config = Get-ApplicationEnvironment
    return $Config.DataAccess.SqlPwd
}

function Get-DataAccessDatabase
{
    $Config = Get-ApplicationEnvironment
    return $Config.DataAccess.Database
}

function Get-DataAccessSqlUsr
{
    $Config = Get-ApplicationEnvironment
    return $Config.DataAccess.SqlUser
}

function Get-DataAccessDbServer
{
    $Config = Get-ApplicationEnvironment
    return $Config.DataAccess.DbServer
}


function Get-AOSPackageDirectory
{
    $Config = Get-ApplicationEnvironment
    return $Config.Aos.PackageDirectory
}

function Get-CommonBinDir
{
    $Config = Get-ApplicationEnvironment
    return $Config.Common.BinDir
}

function Get-BiReportingPersistentVirtualMachineIPAddressSSRS
{
    $Config = Get-ApplicationEnvironment
    return $Config.BiReporting.PersistentVirtualMachineIPAddressSSRS
}

function Get-BiReportingReportingServers
{
    $Config = Get-ApplicationEnvironment
    $reportingServers = $Config.BiReporting.ReportingServers
    if ([System.String]::IsNullOrWhiteSpace($reportingServers))
    {
        $reportingServers = $Config.BiReporting.PersistentVirtualMachineIPAddressSSRS
    }

    return $reportingServers
}

function Get-InfrastructureClickonceAppsDirectory
{
    $Config = Get-ApplicationEnvironment
    return $Config.Infrastructure.ClickonceAppsDirectory
}

function Get-DevToolsInstalled
{
    $webroot = Get-AosWebSitePhysicalPath
    $webconfig=join-path $webroot "web.config"
    $DevInstall=$false
    
    [System.Xml.XmlDocument] $xd=new-object System.Xml.XmlDocument
    $xd.Load($webconfig)
    $ns=New-Object System.Xml.XmlNamespaceManager($xd.NameTable)
    $ns.AddNamespace("ns",$xd.DocumentElement.NamespaceURI)

    $key="Infrastructure.VSToolsCount"

    $VScount = $xd.SelectSingleNode("//ns:add[@key='$key']",$ns)

    if($VScount -ne $null){
        
        if($VScount.GetAttribute("value") -gt 0)
        {
            $DevInstall=$true
        }
    }
    return $DevInstall 
}

function Get-ProductVersionMajorMinor
{
    [string]  $productVersionMajorMinorString = '7.0'
    return $productVersionMajorMinorString
}

function Get-IsRetailProductSku
{
    $productVersion = Get-ProductVersionMajorMinor    
    $retailHQConfigurationLocationRegistryPath = "HKLM:\SOFTWARE\Microsoft\Dynamics\$productVersion\Setup\Metadata"
    if(Test-Path $retailHQConfigurationLocationRegistryPath)
    {
        $retailProductSku = Get-ItemProperty -Path $retailHQConfigurationLocationRegistryPath -Name 'ProductSku' -ErrorAction SilentlyContinue
        
        if($retailProductSku -and $retailProductSku.ProductSku -and ($retailProductSku.ProductSku -eq 'Dynamics365ForRetail'))
        {
            return $true
        }
    }

    return $false
}

function Get-IsOverlayeringDisabled
{
    $productVersion = Get-ProductVersionMajorMinor    
    $retailHQConfigurationLocationRegistryPath = "HKLM:\SOFTWARE\Microsoft\Dynamics\$productVersion\Setup\Metadata"
    if(Test-Path $retailHQConfigurationLocationRegistryPath)
    {
        $isOverlayeringDisabled = Get-ItemProperty -Path $retailHQConfigurationLocationRegistryPath -Name 'DisableOverlayering' -ErrorAction SilentlyContinue
        
        if($isOverlayeringDisabled -and $isOverlayeringDisabled.DisableOverlayering -and ($isOverlayeringDisabled.DisableOverlayering -like 'true'))
        {
            return $true
        }
    }

    return $false
}

function Get-IsAppSealed ([Parameter(Mandatory=$false)] $webroot)
{

    if($webroot -eq $null)
    {
        $webroot = Get-AosWebSitePhysicalPath
    }

    $Version = (Get-ProductApplicationVersion -webroot:$webroot)
    $build = [System.Version]::new()
    
    if([System.Version]::TryParse($Version, [ref]$build))
    {
        if($build.Major -ge "8")
        {
            return $true
        }
        elseif($build.Minor -ge "2")
        {
            if($build.Build.ToString().StartsWith("2"))
            {
                return $true
            }
        }
    }
    
    return $false
    
}

function Get-DependencyAXModelList([string] $sourcePath, [string] $metaPackageName)
{
    $microsoftPackages = @()
    [Void][Reflection.Assembly]::LoadWithPartialName('System.IO.Compression.FileSystem')
    $zipFile = Get-Item $sourcePath\$metaPackageName*.nupkg
    if($zipFile -ne $null)
    {
        $PackFiles = [IO.Compression.ZipFile]::OpenRead($zipFile).Entries
        $PackageSpec =  $PackFiles | where {($_.Name -like "*.nuspec")}

        if(!($PackageSpec))
        {
            Throw "Unable to get package information for $metaPackageName"
        }

        [System.Xml.XmlDocument] $xmlDoc=new-object System.Xml.XmlDocument
        $XmlDoc.Load($PackageSpec.Open())

        $Dependencies = $xmlDoc.GetElementsByTagName('dependency').id
        
        foreach($d in $Dependencies)
        {
            $microsoftPackages += $d
        }
    }
    
    return $microsoftPackages
}

function Get-ALMPackageCopyPath
{
    [string]$ALMBackupPath = ""

    # Is the ALM Service registered (environment variable "DynamicsSDK" would be set)
    if ($env:DynamicsSDK)
    {
        $RegPath = "HKLM:\SOFTWARE\Microsoft\Dynamics\AX\7.0\SDK"

        [string]$ALMBackupPath = $null
        
        # Do not fail when registry key is not found
        try
        {
            # Get the Dynamics SDK (ALM Service) registry key (throws if not found).
            $RegKey = Get-ItemProperty -Path $RegPath
            if ($RegKey -ne $null)
            {
                # Check if backup path set in registry
                $ALMBackupPath = $RegKey.BackupPath
            }
        }
        catch
        {
        }
        
        # If path not found in registry, check default paths
        if (-not $ALMBackupPath)
        {
            if (Test-Path "I:\DynamicsBackup")
            {
                $ALMBackupPath = "I:\DynamicsBackup"
            }
            elseif (Test-Path "$($env:SystemDrive)\DynamicsBackup")
            {
                $ALMBackupPath = "$($env:SystemDrive)\DynamicsBackup"
            }
        }
    }

    return $ALMBackupPath
}

if(!$useServiceFabric)
{
    if (Test-Path "$($PSScriptRoot)\NonAdminDevToolsInterject.ps1")
    {
        & "$($PSScriptRoot)\NonAdminDevToolsInterject.ps1"
    }
}


Export-ModuleMember -Function Get-DataAccessSqlPwd
Export-ModuleMember -Function Get-DataAccessDatabase
Export-ModuleMember -Function Get-DataAccessSqlUsr
Export-ModuleMember -Function Get-DataAccessDbServer
Export-ModuleMember -Function Get-AOSPackageDirectory
Export-ModuleMember -Function Get-CommonBinDir
Export-ModuleMember -Function Get-BiReportingPersistentVirtualMachineIPAddressSSRS
Export-ModuleMember -Function Get-BiReportingReportingServers
Export-ModuleMember -Function Get-InfrastructureClickonceAppsDirectory
Export-ModuleMember -Function Get-DevToolsInstalled
Export-ModuleMember -Function Get-IsModulePartOfPlatformAsBinary
Export-ModuleMember -Function Get-IsAppFallOrLater
Export-ModuleMember -Function Get-IsPlatformUpdate3OrLater
Export-ModuleMember -Function Get-IsPackageContainUpgradeBinaryForUpdate3
Export-ModuleMember -Function Get-ProductPlatformBuildVersion
Export-ModuleMember -Function Get-ApplicationReleaseFromAOS
Export-ModuleMember -Function Get-ApplicationReleaseFromPackage
Export-ModuleMember -Function Get-ProductVersionMajorMinor
Export-ModuleMember -Function Get-IsRetailProductSku
Export-ModuleMember -Function Get-IsOverlayeringDisabled
Export-ModuleMember -Function Get-DependencyAXModelList
Export-ModuleMember -Function Get-IsAppSealed
Export-ModuleMember -Function Get-IsModulePartOfApplicationAsBinary
Export-ModuleMember -Function Get-ALMPackageCopyPath
Export-ModuleMember -Function GenerateMetadataModuleInstallationInfo

# SIG # Begin signature block
# MIIkDgYJKoZIhvcNAQcCoIIj/zCCI/sCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCC0tAl97Oj8ScHM
# n760lMpRaM6Bgdc/T2WHDqtHaSplxaCCDYIwggYAMIID6KADAgECAhMzAAAAww6b
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
# SEXAQsmbdlsKgEhr/Xmfwb1tbWrJUnMTDXpQzTGCFeIwghXeAgEBMIGVMH4xCzAJ
# BgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25k
# MR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xKDAmBgNVBAMTH01pY3Jv
# c29mdCBDb2RlIFNpZ25pbmcgUENBIDIwMTECEzMAAADDDpun2LLc9ywAAAAAAMMw
# DQYJYIZIAWUDBAIBBQCggdQwGQYJKoZIhvcNAQkDMQwGCisGAQQBgjcCAQQwHAYK
# KwYBBAGCNwIBCzEOMAwGCisGAQQBgjcCARUwLwYJKoZIhvcNAQkEMSIEIIKq0rqp
# h/GsfOHXIF3znppWswTIdzvoqDXCafcJ+48NMGgGCisGAQQBgjcCAQwxWjBYoDqA
# OABBAE8AUwBFAG4AdgBpAHIAbwBuAG0AZQBuAHQAVQB0AGkAbABpAHQAaQBlAHMA
# LgBwAHMAbQAxoRqAGGh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbTANBgkqhkiG9w0B
# AQEFAASCAQCJ4kw5OLOoqpm8pqWNdg5JtLIYa+NH7EUsXVTTujV6yYfdd7AyU90b
# Nn0pNuqbqWl7FIfC/2VVSTWId54YtKMVhE5Jsf+rKpXkFsdjCU9/TuWoGlwt8pdA
# Ayc8LNGIwXD8ImPbve94bE6XaVV9/31RfhojOxF7wZjQNAwRgb3OoCrJrfEnjaco
# uhgX6SVQFmpWKOnWjTd2R7SLkgnnYDnJ2Ub/V7hwfURHWP+6B4b5obbm6GnfCBPn
# Gs6SGOiTkSMA0+Gs/a8OeXmypeFM+Zr2e3qAzEIgdNQMj+Bcq5qrkcMI3N0MZsRo
# tLOmokeVb8U4fDg8Hcu6quBbeaE9z2QcoYITRjCCE0IGCisGAQQBgjcDAwExghMy
# MIITLgYJKoZIhvcNAQcCoIITHzCCExsCAQMxDzANBglghkgBZQMEAgEFADCCATwG
# CyqGSIb3DQEJEAEEoIIBKwSCAScwggEjAgEBBgorBgEEAYRZCgMBMDEwDQYJYIZI
# AWUDBAIBBQAEIGD4HX0hMslDENLR9a7xP2qs2FLn7q7hVTFzOovGTrENAgZasqW7
# zZUYEzIwMTgwMzI1MjEwNTUyLjEwOFowBwIBAYACAfSggbikgbUwgbIxCzAJBgNV
# BAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4w
# HAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xDDAKBgNVBAsTA0FPQzEnMCUG
# A1UECxMebkNpcGhlciBEU0UgRVNOOjEyRTctMzA2NC02MTEyMSUwIwYDVQQDExxN
# aWNyb3NvZnQgVGltZS1TdGFtcCBTZXJ2aWNloIIOyjCCBnEwggRZoAMCAQICCmEJ
# gSoAAAAAAAIwDQYJKoZIhvcNAQELBQAwgYgxCzAJBgNVBAYTAlVTMRMwEQYDVQQI
# EwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3Nv
# ZnQgQ29ycG9yYXRpb24xMjAwBgNVBAMTKU1pY3Jvc29mdCBSb290IENlcnRpZmlj
# YXRlIEF1dGhvcml0eSAyMDEwMB4XDTEwMDcwMTIxMzY1NVoXDTI1MDcwMTIxNDY1
# NVowfDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcT
# B1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEmMCQGA1UE
# AxMdTWljcm9zb2Z0IFRpbWUtU3RhbXAgUENBIDIwMTAwggEiMA0GCSqGSIb3DQEB
# AQUAA4IBDwAwggEKAoIBAQCpHQ28dxGKOiDs/BOX9fp/aZRrdFQQ1aUKAIKF++18
# aEssX8XD5WHCdrc+Zitb8BVTJwQxH0EbGpUdzgkTjnxhMFmxMEQP8WCIhFRDDNdN
# uDgIs0Ldk6zWczBXJoKjRQ3Q6vVHgc2/JGAyWGBG8lhHhjKEHnRhZ5FfgVSxz5NM
# ksHEpl3RYRNuKMYa+YaAu99h/EbBJx0kZxJyGiGKr0tkiVBisV39dx898Fd1rL2K
# Qk1AUdEPnAY+Z3/1ZsADlkR+79BL/W7lmsqxqPJ6Kgox8NpOBpG2iAg16HgcsOmZ
# zTznL0S6p/TcZL2kAcEgCZN4zfy8wMlEXV4WnAEFTyJNAgMBAAGjggHmMIIB4jAQ
# BgkrBgEEAYI3FQEEAwIBADAdBgNVHQ4EFgQU1WM6XIoxkPNDe3xGG8UzaFqFbVUw
# GQYJKwYBBAGCNxQCBAweCgBTAHUAYgBDAEEwCwYDVR0PBAQDAgGGMA8GA1UdEwEB
# /wQFMAMBAf8wHwYDVR0jBBgwFoAU1fZWy4/oolxiaNE9lJBb186aGMQwVgYDVR0f
# BE8wTTBLoEmgR4ZFaHR0cDovL2NybC5taWNyb3NvZnQuY29tL3BraS9jcmwvcHJv
# ZHVjdHMvTWljUm9vQ2VyQXV0XzIwMTAtMDYtMjMuY3JsMFoGCCsGAQUFBwEBBE4w
# TDBKBggrBgEFBQcwAoY+aHR0cDovL3d3dy5taWNyb3NvZnQuY29tL3BraS9jZXJ0
# cy9NaWNSb29DZXJBdXRfMjAxMC0wNi0yMy5jcnQwgaAGA1UdIAEB/wSBlTCBkjCB
# jwYJKwYBBAGCNy4DMIGBMD0GCCsGAQUFBwIBFjFodHRwOi8vd3d3Lm1pY3Jvc29m
# dC5jb20vUEtJL2RvY3MvQ1BTL2RlZmF1bHQuaHRtMEAGCCsGAQUFBwICMDQeMiAd
# AEwAZQBnAGEAbABfAFAAbwBsAGkAYwB5AF8AUwB0AGEAdABlAG0AZQBuAHQALiAd
# MA0GCSqGSIb3DQEBCwUAA4ICAQAH5ohRDeLG4Jg/gXEDPZ2joSFvs+umzPUxvs8F
# 4qn++ldtGTCzwsVmyWrf9efweL3HqJ4l4/m87WtUVwgrUYJEEvu5U4zM9GASinbM
# QEBBm9xcF/9c+V4XNZgkVkt070IQyK+/f8Z/8jd9Wj8c8pl5SpFSAK84Dxf1L3mB
# ZdmptWvkx872ynoAb0swRCQiPM/tA6WWj1kpvLb9BOFwnzJKJ/1Vry/+tuWOM7ti
# X5rbV0Dp8c6ZZpCM/2pif93FSguRJuI57BlKcWOdeyFtw5yjojz6f32WapB4pm3S
# 4Zz5Hfw42JT0xqUKloakvZ4argRCg7i1gJsiOCC1JeVk7Pf0v35jWSUPei45V3ai
# caoGig+JFrphpxHLmtgOR5qAxdDNp9DvfYPw4TtxCd9ddJgiCGHasFAeb73x4QDf
# 5zEHpJM692VHeOj4qEir995yfmFrb3epgcunCaw5u+zGy9iCtHLNHfS4hQEegPsb
# iSpUObJb2sgNVZl6h3M7COaYLeqN4DMuEin1wC9UJyH3yKxO2ii4sanblrKnQqLJ
# zxlBTeCG+SqaoxFmMNO7dDJL32N79ZmKLxvHIa9Zta7cRDyXUHHXodLFVeNp3lfB
# 0d4wwP3M5k37Db9dT+mdHhk4L7zPWAUu7w2gUDXa7wknHNWzfjUeCLraNtvTX4/e
# dIhJEjCCBNkwggPBoAMCAQICEzMAAACsiiG8etKbcvQAAAAAAKwwDQYJKoZIhvcN
# AQELBQAwfDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNV
# BAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEmMCQG
# A1UEAxMdTWljcm9zb2Z0IFRpbWUtU3RhbXAgUENBIDIwMTAwHhcNMTYwOTA3MTc1
# NjU0WhcNMTgwOTA3MTc1NjU0WjCBsjELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldh
# c2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBD
# b3Jwb3JhdGlvbjEMMAoGA1UECxMDQU9DMScwJQYDVQQLEx5uQ2lwaGVyIERTRSBF
# U046MTJFNy0zMDY0LTYxMTIxJTAjBgNVBAMTHE1pY3Jvc29mdCBUaW1lLVN0YW1w
# IFNlcnZpY2UwggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIBAQChxPQ8pY5z
# MaEXQVyrdwi3qdFDqrvf3HT5ujVWaoQJ2Km7+1T3GNnGpbND6PomAcw9NfV+C+RM
# mCrThpUlBVzeuzsNL2Lsj9mMdK83ixebazenSrA0rXLIifWBzKHVP6jzsQWo96cH
# ukHZqI8xRp3tYivgapt5LLrn9Rm2Jn+E0h2lKDOw5sIteZiriOMPH2Z7mtgYXmyB
# 8ThgdB46p6frNGpcXr11pa1Vkldl0iY6oBAKQQSxJ5Bn4N7ui5Wj5wDkDZzGAg6n
# 1ptMPTPJhL2uosW84YjnSp/2suNap3qOjKEYXmpGzvasq5qyqPyvfqfksOfNBaJn
# tfpC8dIDJKrnAgMBAAGjggEbMIIBFzAdBgNVHQ4EFgQU2EdwqIU1ixNhr4eQ6EUX
# JOCYpw0wHwYDVR0jBBgwFoAU1WM6XIoxkPNDe3xGG8UzaFqFbVUwVgYDVR0fBE8w
# TTBLoEmgR4ZFaHR0cDovL2NybC5taWNyb3NvZnQuY29tL3BraS9jcmwvcHJvZHVj
# dHMvTWljVGltU3RhUENBXzIwMTAtMDctMDEuY3JsMFoGCCsGAQUFBwEBBE4wTDBK
# BggrBgEFBQcwAoY+aHR0cDovL3d3dy5taWNyb3NvZnQuY29tL3BraS9jZXJ0cy9N
# aWNUaW1TdGFQQ0FfMjAxMC0wNy0wMS5jcnQwDAYDVR0TAQH/BAIwADATBgNVHSUE
# DDAKBggrBgEFBQcDCDANBgkqhkiG9w0BAQsFAAOCAQEASOzoXifDGxicXbTOdm43
# DB9dYxwNXaQj0hW0ztBACeWbX6zxee1w7TJeXQx1IfTz1BWJAfVla7HA1oxa0LiF
# /Uf6rfRvEEmGmHr9wWEbr3xiErllTFE2V/mdYBSEwdj74m8QLBeFY37Cjx4TFe+A
# B/FQly3kvfrJKDaYYTTXTAFYAKpi0AcDTcESXZcshJ/O8UZs9fr0BgrOm5h7qeQ1
# CJNmDMVEqElQt/cFO3dxqrAKv3Fu/nsT5GkABu+vIibgxX6tNmqccIIXKALgv7zD
# IaRAAWtXV9LwnmstDUbIp8dH/oSVm3tPnCPlrB3+C28vPnvJdbtJi/yOuETd+rLn
# +qGCA3QwggJcAgEBMIHioYG4pIG1MIGyMQswCQYDVQQGEwJVUzETMBEGA1UECBMK
# V2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0
# IENvcnBvcmF0aW9uMQwwCgYDVQQLEwNBT0MxJzAlBgNVBAsTHm5DaXBoZXIgRFNF
# IEVTTjoxMkU3LTMwNjQtNjExMjElMCMGA1UEAxMcTWljcm9zb2Z0IFRpbWUtU3Rh
# bXAgU2VydmljZaIlCgEBMAkGBSsOAwIaBQADFQA5cCWLFMh53V8MXemLnLOUmfcc
# t6CBwTCBvqSBuzCBuDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24x
# EDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlv
# bjEMMAoGA1UECxMDQU9DMScwJQYDVQQLEx5uQ2lwaGVyIE5UUyBFU046MjY2NS00
# QzNGLUM1REUxKzApBgNVBAMTIk1pY3Jvc29mdCBUaW1lIFNvdXJjZSBNYXN0ZXIg
# Q2xvY2swDQYJKoZIhvcNAQEFBQACBQDeYe00MCIYDzIwMTgwMzI1MDk0MTA4WhgP
# MjAxODAzMjYwOTQxMDhaMHQwOgYKKwYBBAGEWQoEATEsMCowCgIFAN5h7TQCAQAw
# BwIBAAICJxYwBwIBAAICGc4wCgIFAN5jPrQCAQAwNgYKKwYBBAGEWQoEAjEoMCYw
# DAYKKwYBBAGEWQoDAaAKMAgCAQACAxbjYKEKMAgCAQACAwehIDANBgkqhkiG9w0B
# AQUFAAOCAQEAY1fiWDfeHlvSVx8yPDkvRGLPGXP74+urvWYBzepnv6d8vXhWS5Ms
# C6LP8+bTWnSzMWsDvpjZOtxuTnFLwbzIoDL7mpSEYjEmtCigNNQST+ZpaEoX+H4l
# dOB6i9EQjZE6DBnljenG4eLAEIlFDiueHD2ls9aabcZl7mIqPCAWlggQClXekjJt
# Zj6qIq9LaVTZ9zgG57I3GbGccgfC6i8goZ3dEP0pNFMgJKADN1jZhajxnAPzu+nZ
# 4AtQVvSgcDoIf99Ue8zUlUQUgG0f7EO+Jqnb2SyPLWB0hVsuWYxIppDnWheLnbzX
# B+PV2Z/5bes0ABNS7D85m26OkIDIdS3OhTGCAvUwggLxAgEBMIGTMHwxCzAJBgNV
# BAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4w
# HAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xJjAkBgNVBAMTHU1pY3Jvc29m
# dCBUaW1lLVN0YW1wIFBDQSAyMDEwAhMzAAAArIohvHrSm3L0AAAAAACsMA0GCWCG
# SAFlAwQCAQUAoIIBMjAaBgkqhkiG9w0BCQMxDQYLKoZIhvcNAQkQAQQwLwYJKoZI
# hvcNAQkEMSIEIIAwJ2nqanIJ6hJGqHqd5yA5BkigZxQ5eOYkDAVh0TeqMIHiBgsq
# hkiG9w0BCRACDDGB0jCBzzCBzDCBsQQUOXAlixTIed1fDF3pi5yzlJn3HLcwgZgw
# gYCkfjB8MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UE
# BxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSYwJAYD
# VQQDEx1NaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0EgMjAxMAITMwAAAKyKIbx60pty
# 9AAAAAAArDAWBBTozm2OayPZf6jhy3FmMPY0BkOHODANBgkqhkiG9w0BAQsFAASC
# AQCK90d4v1UAgrzVzbUqfHbZEt61V6vDMWwJyPO+rKY/A9MLKG8tO8+jILuvnSHj
# 7QXdNLx/VbZJ20P+o+YZC9JEj4xQRHhtYCiY9IzE3E4w491ZU+56I0M0Hl1eCuf0
# CHnvUNLxm+Vrnx8ekdP+qOv2kr2J1l8xWhqW8aEDqf+KHbR0lPtvmxpd6p6hmfAi
# CBMoA2/i1aBUrylwGsNnNrVH8WZ/SFDhhwDeI8s5DqFcfGq72lWfyC1UvemmpEb1
# YBBgyXVhanCt4vQqjOqOcn2g/QOb3r4yHuVUh16PKnnu6gjw5c5rkkUNNAd0f9do
# DqJ1haKwDTq8DPbuxYcYVXFI
# SIG # End signature block
