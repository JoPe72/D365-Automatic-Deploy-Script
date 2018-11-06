$module=Join-Path -Path $PSScriptRoot -ChildPath "CommonRollbackUtilities.psm1"
Import-Module $module -DisableNameChecking -force
Import-Module "$PSScriptRoot\AosEnvironmentUtilities.psm1" -Force -DisableNameChecking

$global:logfile=""
$AosWebsiteName = Get-AosWebSiteName
$BatchService = "DynamicsAxBatch"
$PrintService = "DynamicsAXPrintService"

$configEncryptor="Microsoft.Dynamics.AX.Framework.ConfigEncryptor.exe"

$ErrorActionPreference="Stop"

function Initialize-Log([string]$log)
{
    if(Test-Path -Path $log)
    {
        Write-Output "Removing the existing log file '$log'."
        Remove-Item -Path $log -Force|Out-Null
    }

    Write-Output "Creating the log file '$log'."
    New-Item -Path $log -ItemType File -Force|out-null
    $global:logfile=$log
}

function Write-Log([string]$message)
{
    $datetime=Get-Date -Format "MM-dd-yyyy:HH:mm:ss"
    Add-Content -Path $global:logfile -Value "$datetime`: $message"|out-null
    Write-Output "$datetime`: $message"
}

function Log-Error([string]$error,[switch]$throw)
{
    Write-Error $error
    if($throw)
    {
        throw $error
    }
}

function Create-Backup([string]$webroot,[string]$backupdir)
{
    $orig_webconfig= Join-Path -Path $webroot -ChildPath "web.config"
    $orig_wifconfig= Join-Path -Path $webroot -ChildPath "wif.config"
    $orig_wifservicesconfig=Join-Path -Path $webroot -ChildPath "wif.services.config"

    $backup_webconfig= Join-Path -Path $backupdir -ChildPath "web.config.backup"
    $backup_wifconfig= Join-Path -Path $backupdir -ChildPath "wif.config.backup"
    $backup_wifservicesconfig=Join-Path -Path $backupdir -ChildPath "wif.services.config.backup"

    Copy-Item -Path $orig_webconfig -Destination $backup_webconfig -Force|out-null
    Write-Log "Copied '$orig_webconfig' to '$backup_webconfig."

    Copy-item -Path $orig_wifconfig -Destination $backup_wifconfig -Force|out-null
    Write-Log "Copied '$orig_wifconfig' to '$backup_wifconfig'."

    Copy-item -Path $orig_wifservicesconfig -Destination $backup_wifservicesconfig -Force|out-null
    Write-Log "Copied '$orig_wifservicesconfig' to '$backup_wifservicesconfig'."
}

# This is the main entry point to control what is upgraded
function Upgrade-Web-Config([string]$webroot, [int]$platformVersion)
{
    $script:PlatformReleaseVersion = $platformVersion
    Decrypt-Config -webroot:$webroot
    $webconfig=Join-Path -Path $webroot -ChildPath "Web.config"
    $batchconfig=Join-Path -Path $webroot -ChildPath "bin\Batch.exe.config"
	Upgrade-HttpProtocol-NewNames -webconfig:$webconfig
    Upgrade-WebConfig-NewKeys -webconfig:$webconfig
    Upgrade-WebConfig-DeleteKeys -webconfig:$webconfig
    Upgrade-WebConfig-updateKeys -webconfig:$webconfig
    Upgrade-WebConfig-Add-DependentAssemblies -webconfig:$webconfig
    Upgrade-WebConfig-Update-DependentAssemblyBinding -webconfig:$webconfig
    Upgrade-WebConfig-AssemblyReferences -webconfig:$webconfig
    Upgrade-WebConfig-rootLocations -webconfig:$webconfig
    Upgrade-WebConfig-rootLocations-ReliableCommunicationManager -webconfig:$webconfig
    Upgrade-WebConfig-RemoveAssemblies -webConfig:$webconfig
    Upgrade-WebConfig-RemoveWcfActivityLog -webConfig:$webconfig
    Upgrade-WebConfig-Add-LcsEnvironmentId -webConfig:$webconfig
    if(Test-Path -Path $batchconfig)
    {
        Upgrade-BatchConfig-Add-DependentAssemblies -batchconfig:$batchconfig
    }
    Encrypt-Config -webroot:$webroot
}

function Add-DependencyAssembly([System.Xml.XmlDocument] $xmlDoc, [string] $assemblyName, [string] $publickey, [string] $oldVersion, [string] $newVersion, [string] $culture)
{
    $ns = New-Object System.Xml.XmlNamespaceManager($xmlDoc.NameTable)
    $ns.AddNamespace("ab", "urn:schemas-microsoft-com:asm.v1")

    $DependencyNode = $xmlDoc.SelectSingleNode("/configuration/runtime/ab:assemblyBinding",$ns)

    [System.Xml.XmlElement] $dependencyElement = $xmlDoc.CreateElement("dependentAssembly","urn:schemas-microsoft-com:asm.v1")
    [System.Xml.XmlElement] $assemblyElement = $xmlDoc.CreateElement("assemblyIdentity", "urn:schemas-microsoft-com:asm.v1")


    $nameAttribute = $xmlDoc.CreateAttribute('name')
    $nameAttribute.Value = $assemblyName

    $publicKeyAttribute = $xmlDoc.CreateAttribute('publicKeyToken')
    $publicKeyAttribute.Value = $publickey

    $assemblyElement.Attributes.Append($nameAttribute)
    $assemblyElement.Attributes.Append($publicKeyAttribute)

    #This attribute is optional so only add the attribute if a value is passed in for culture
    if(!([String]::IsNullOrWhiteSpace($culture)))
    {
        $cultureAttribute = $xmlDoc.CreateAttribute('culture')
        $cultureAttribute.Value = $culture
        $assemblyElement.Attributes.Append($cultureAttribute)
    }

    $dependencyElement.AppendChild($assemblyElement)

    #This element is optional so only add the node if a value is passed in for old
    if(!([String]::IsNullOrWhiteSpace($oldVersion)))
    {
        [System.Xml.XmlElement] $bindingElement = $xmlDoc.CreateElement("bindingRedirect", "urn:schemas-microsoft-com:asm.v1")
        $oldVersionAttribute = $xmlDoc.CreateAttribute('oldVersion')
        $oldVersionAttribute.Value = $oldVersion

        $newVersionAttribute = $xmlDoc.CreateAttribute('newVersion')
        $newVersionAttribute.Value = $newVersion

        $bindingElement.Attributes.Append($oldVersionAttribute)
        $bindingElement.Attributes.Append($newVersionAttribute)
        $dependencyElement.AppendChild($bindingElement)
    }

    $DependencyNode.AppendChild($dependencyElement)
}

function Update-DependentAssemblyBinding([System.Xml.XmlDocument] $xmlDoc, [string] $assemblyName, [string] $oldVersion, [string] $newVersion)
{
    $ns = New-Object System.Xml.XmlNamespaceManager($xmlDoc.NameTable)
    $ns.AddNamespace("ab", "urn:schemas-microsoft-com:asm.v1")

    if(Get-DependentAssemblyExists -assemblyName:$assemblyName -xmlDoc:$xmlDoc)
    {
        $bindingNode = $xmlDoc.SelectSingleNode("/configuration/runtime/ab:assemblyBinding/ab:dependentAssembly/ab:bindingRedirect[../ab:assemblyIdentity[@name='$assemblyName']]", $ns)
        $bindingNode.oldVersion = $oldVersion
        $bindingNode.newVersion = $newVersion
    }
}

function Upgrade-WebConfig-Update-DependentAssemblyBinding([string] $webConfig)
{
    [System.Xml.XmlDocument] $xmlDoc = new-object System.Xml.XmlDocument
    $xmlDoc.Load($webconfig)

    Update-DependentAssemblyBinding -xmlDoc:$xmlDoc -assemblyName:'Microsoft.Owin' -oldVersion:'0.0.0.0-3.0.1.0' -newVersion:'3.0.1.0'

    $xmlDoc.Save($webconfig)
}

function Get-DependentAssemblyExists([string] $assemblyName, [System.Xml.XmlDocument] $xmlDoc)
{
    $dependentAssemblyExists=$false
    $ns = New-Object System.Xml.XmlNamespaceManager($xmlDoc.NameTable)
    $ns.AddNamespace("ab", "urn:schemas-microsoft-com:asm.v1")
    $assemblyNode = $xmlDoc.SelectSingleNode("/configuration/runtime/ab:assemblyBinding/ab:dependentAssembly/ab:assemblyIdentity[@name='$assemblyName']", $ns)
    if($assemblyNode -ne $null)
    {
        $dependentAssemblyExists=$true
    }
    return $dependentAssemblyExists
}

function Upgrade-WebConfig-Add-DependentAssemblies([string] $webConfig)
{
    [System.Xml.XmlDocument] $xmlDoc = new-object System.Xml.XmlDocument
    $xmlDoc.Load($webconfig)

    $assemblyName='System.Web.http'
    if(!(Get-DependentAssemblyExists -assemblyName:$assemblyName -xmlDoc:$xmlDoc))
    {
        Add-DependencyAssembly -xmlDoc:$xmlDoc -assemblyName:$assemblyName -publickey:'31bf3856ad364e35' -oldVersion:'0.0.0.0-5.0.0.0' -newVersion:'5.2.2.0'
    }
    $assemblyName='System.Web.Http.WebHost'
    if(!(Get-DependentAssemblyExists -assemblyName:$assemblyName  -xmlDoc:$xmlDoc))
    {
        Add-DependencyAssembly -xmlDoc:$xmlDoc -assemblyName:$assemblyName -publickey:'31bf3856ad364e35' -oldVersion:'0.0.0.0-5.0.0.0' -newVersion:'5.2.2.0'
    }
    $assemblyName='System.Net.Http'
    if(!(Get-DependentAssemblyExists -assemblyName:$assemblyName -xmlDoc:$xmlDoc))
    {
        Add-DependencyAssembly -xmlDoc:$xmlDoc -assemblyName:$assemblyName -publickey:'31bf3856ad364e35'
    }
    if ($PlatformReleaseVersion -gt 4641)
    {
        $assemblyName = 'System.Net.Http.Formatting'
        if (!(Get-DependentAssemblyExists -assemblyName:$assemblyName  -xmlDoc:$xmlDoc))
        {
            Add-DependencyAssembly -xmlDoc:$xmlDoc -assemblyName:$assemblyName -publickey:'31bf3856ad364e35' -oldVersion:'0.0.0.0-5.2.2.0' -newVersion:'5.2.3.0'
        }
    }
    $assemblyName='Microsoft.Dynamics.Client.InteractionService'
    if(!(Get-DependentAssemblyExists -assemblyName:$assemblyName -xmlDoc:$xmlDoc))
    {
        Add-DependencyAssembly -xmlDoc:$xmlDoc -assemblyName:$assemblyName -publickey:'31bf3856ad364e35' -oldVersion:'6.0.0.0' -newVersion:'7.0.0.0' -culture:'neutral'
    }
    $assemblyName='Microsoft.Owin.Security'
    if(!(Get-DependentAssemblyExists -assemblyName:$assemblyName -xmlDoc:$xmlDoc))
    {
        Add-DependencyAssembly -xmlDoc:$xmlDoc -assemblyName:$assemblyName -publickey:'31bf3856ad364e35' -oldVersion:'0.0.0.0-3.0.1.0' -newVersion:'3.0.1.0' -culture:'neutral'
    }
    $assemblyName='Microsoft.Diagnostics.Tracing.EventSource'
    if(!(Get-DependentAssemblyExists -assemblyName:$assemblyName -xmlDoc:$xmlDoc))
    {
        Add-DependencyAssembly -xmlDoc:$xmlDoc -assemblyName:$assemblyName -publickey:'b03f5f7f11d50a3a' -oldVersion:'1.1.17.0' -newVersion:'1.1.28.0' -culture:'neutral'
    }

    #Add check forupdate 4
    if ($PlatformReleaseVersion -ge 4425)
    {
        $assemblyName='Newtonsoft.Json'
        if(!(Get-DependentAssemblyExists -assemblyName:$assemblyName -xmlDoc:$xmlDoc))
        {
            Add-DependencyAssembly -xmlDoc:$xmlDoc -assemblyName:$assemblyName -publickey:'30ad4fe6b2a6aeed' -oldVersion:'0.0.0.0-9.0.0.0' -newVersion:'9.0.0.0' -culture:'neutral'
        }
        $assemblyName='Microsoft.IdentityModel.Clients.ActiveDirectory'
        if(!(Get-DependentAssemblyExists -assemblyName:$assemblyName -xmlDoc:$xmlDoc))
        {
            Add-DependencyAssembly -xmlDoc:$xmlDoc -assemblyName:$assemblyName -publickey:'31bf3856ad364e35' -oldVersion:'0.0.0.0-2.14.0.0' -newVersion:'2.14.0.0' -culture:'neutral'
        }
        $assemblyName='Microsoft.Azure.ActiveDirectory.GraphClient'
        if(!(Get-DependentAssemblyExists -assemblyName:$assemblyName -xmlDoc:$xmlDoc))
        {
            Add-DependencyAssembly -xmlDoc:$xmlDoc -assemblyName:$assemblyName -publickey:'31bf3856ad364e35' -oldVersion:'0.0.0.0-2.1.1.0' -newVersion:'2.1.1.0' -culture:'neutral'
        }
    }
    $xmlDoc.Save($webconfig);
}

function Upgrade-BatchConfig-Add-DependentAssemblies([string] $batchConfig)
{
    [System.Xml.XmlDocument] $xmlDoc = new-object System.Xml.XmlDocument
    $xmlDoc.Load($batchConfig)

    $assemblyName='Microsoft.Diagnostics.Tracing.EventSource'
    if(!(Get-DependentAssemblyExists -assemblyName:$assemblyName -xmlDoc:$xmlDoc))
    {
        Add-DependencyAssembly -xmlDoc:$xmlDoc -assemblyName:$assemblyName -publickey:'b03f5f7f11d50a3a' -oldVersion:'1.1.17.0' -newVersion:'1.1.28.0' -culture:'neutral'
    }

    $xmlDoc.Save($batchConfig);
}

function Upgrade-WebConfig-AssemblyReferences([string] $webConfig)
{
    [System.Xml.XmlDocument] $xmlDoc = new-object System.Xml.XmlDocument
    $xmlDoc.Load($webconfig)

    $assembliesNode = $xmlDoc.SelectSingleNode("/configuration/location/system.web/compilation/assemblies")

    $assemblyName = 'Microsoft.Dynamics.AX.Configuration.Base'
    if(!(Get-AssemblyExists -assemblyName:$assemblyName -xmlDoc:$xmlDoc))
    {
        Add-NewAssembly -assemblyName:$assemblyName -parentNode:$assembliesNode -xmlDoc:$xmlDoc
    }
    $assemblyName = 'System.Web.Http'
    if(!(Get-AssemblyExists -assemblyName:$assemblyName -xmlDoc:$xmlDoc))
    {
        Add-NewAssembly -assemblyName:$assemblyName -parentNode:$assembliesNode -xmlDoc:$xmlDoc
    }
    $assemblyName = 'System.Web.Http.WebHost'
    if(!(Get-AssemblyExists -assemblyName:$assemblyName -xmlDoc:$xmlDoc))
    {
        Add-NewAssembly -assemblyName:$assemblyName -parentNode:$assembliesNode -xmlDoc:$xmlDoc
    }
    $assemblyName = 'System.Net.Http'
    if(!(Get-AssemblyExists -assemblyName:$assemblyName -xmlDoc:$xmlDoc))
    {
        Add-NewAssembly -assemblyName:$assemblyName -parentNode:$assembliesNode -xmlDoc:$xmlDoc
    }
    if ($PlatformReleaseVersion -gt 4641)
    {
        $assemblyName = 'System.Net.Http.Formatting'
        if(!(Get-AssemblyExists -assemblyName:$assemblyName -xmlDoc:$xmlDoc))
        {
            Add-NewAssembly -assemblyName:$assemblyName -parentNode:$assembliesNode -xmlDoc:$xmlDoc
        }
    }
    $assemblyName = 'Microsoft.Dynamics.Client.InteractionService'
    if(!(Get-AssemblyExists -assemblyName:$assemblyName -xmlDoc:$xmlDoc))
    {
        Add-NewAssembly -assemblyName:$assemblyName -parentNode:$assembliesNode -xmlDoc:$xmlDoc
    }
    $xmlDoc.Save($webconfig);
}

function Add-NewAssembly([string] $assemblyName, [System.Xml.XmlNode] $parentNode, [System.Xml.XmlDocument] $xmlDoc)
{
    [System.Xml.XmlElement] $element = $xmlDoc.CreateElement("add")
    $newAttribute = $xmlDoc.CreateAttribute('assembly')
    $newAttribute.Value = $assemblyName

    $element.Attributes.Append($newAttribute)

    $parentNode.AppendChild($element)
}

function Upgrade-WebConfig-NewKeys([string]$webconfig)
{
    [System.Xml.XmlDocument] $xmlDoc = new-object System.Xml.XmlDocument
    $xmlDoc.Load($webconfig)

    $appsettings=$xmlDoc.SelectSingleNode("/configuration/appSettings")

    $key = 'Aad.AADValidAudience'
    $value = 'microsoft.erp'
    if(!(Get-KeyExists -key:$key -xmlDoc:$xmlDoc))
    {
        Add-NewKey -key $key -value $value -parentNode $appsettings -xmlDoc $xmlDoc
    }

    $key = 'Aad.MSAIdentityProvider'
    $value = 'live.com'
    if(!(Get-KeyExists -key:$key -xmlDoc:$xmlDoc))
    {
        Add-NewKey -key $key -value $value -parentNode $appsettings -xmlDoc $xmlDoc
    }

    $key = 'Aad.MSAOutlook'
    $value = 'outlook.com'
    if(!(Get-KeyExists -key:$key -xmlDoc:$xmlDoc))
    {
        Add-NewKey -key $key -value $value -parentNode $appsettings -xmlDoc $xmlDoc
    }

    $key = 'BiReporting.IsSSRSEnabled'
    $value = 'true'
    if(!(Get-KeyExists -key:$key -xmlDoc:$xmlDoc))
    {
        Add-NewKey -key $key -value $value -parentNode $appsettings -xmlDoc $xmlDoc
    }

    $key = 'CertificateHandler.HandlerType'
    $value = 'Microsoft.Dynamics.AX.Configuration.CertificateHandler.LocalStoreCertificateHandler'
    if(!(Get-KeyExists -key:$key -xmlDoc:$xmlDoc))
    {
        Add-NewKey -key $key -value $value -parentNode $appsettings -xmlDoc $xmlDoc
    }

    $key = 'LCS.BpmAuthClient'
    $value = 'SysBpmCertClient'
    if(!(Get-KeyExists -key:$key -xmlDoc:$xmlDoc))
    {
        Add-NewKey -key $key -value $value -parentNode $appsettings -xmlDoc $xmlDoc
    }

    $key = 'LCS.ProjectId'
    $value = ''
    if(!(Get-KeyExists -key:$key -xmlDoc:$xmlDoc))
    {
        Add-NewKey -key $key -value $value -parentNode $appsettings -xmlDoc $xmlDoc
    }

    $key = 'DataAccess.FlightingEnvironment'
    $value = ''
    if(!(Get-KeyExists -key:$key -xmlDoc:$xmlDoc))
    {
        Add-NewKey -key $key -value $value -parentNode $appsettings -xmlDoc $xmlDoc
    }

    $key = 'DataAccess.FlightingCertificateThumbprint'
    $value = ''
    if(!(Get-KeyExists -key:$key -xmlDoc:$xmlDoc))
    {
        Add-NewKey -key $key -value $value -parentNode $appsettings -xmlDoc $xmlDoc
    }

    $key = 'DataAccess.FlightingServiceCatalogID'
    $value = ''
    if(!(Get-KeyExists -key:$key -xmlDoc:$xmlDoc))
    {
        Add-NewKey -key $key -value $value -parentNode $appsettings -xmlDoc $xmlDoc
    }

    $key = 'DataAccess.FlightingServiceCacheFolder'
    $value = 'CarbonRuntimeBackup'
    if(!(Get-KeyExists -key:$key -xmlDoc:$xmlDoc))
    {
        Add-NewKey -key $key -value $value -parentNode $appsettings -xmlDoc $xmlDoc
    }
    
    #Check if update 7 or later
    if ($PlatformReleaseVersion -ge 4542)
    {
        $key = 'PowerBIEmbedded.AccessKey'
        $value = ''
        if(!(Get-KeyExists -key:$key -xmlDoc:$xmlDoc))
        {
            Add-NewKey -key $key -value $value -parentNode $appsettings -xmlDoc $xmlDoc
        }

        $key = 'PowerBIEmbedded.AccessKey2'
        $value = ''
        if(!(Get-KeyExists -key:$key -xmlDoc:$xmlDoc))
        {
            Add-NewKey -key $key -value $value -parentNode $appsettings -xmlDoc $xmlDoc
        }

        $key = 'PowerBIEmbedded.ApiUrl'
        $value = 'https://api.powerbi.com'
        if(!(Get-KeyExists -key:$key -xmlDoc:$xmlDoc))
        {
            Add-NewKey -key $key -value $value -parentNode $appsettings -xmlDoc $xmlDoc
        }

        $key = 'PowerBIEmbedded.IsPowerBIEmbeddedEnabled'
        $value = 'false'
        if(!(Get-KeyExists -key:$key -xmlDoc:$xmlDoc))
        {
            Add-NewKey -key $key -value $value -parentNode $appsettings -xmlDoc $xmlDoc
        }

        $key = 'PowerBIEmbedded.WorkspaceCollectionName'
        $value = ''
        if(!(Get-KeyExists -key:$key -xmlDoc:$xmlDoc))
        {
            Add-NewKey -key $key -value $value -parentNode $appsettings -xmlDoc $xmlDoc
        }
    }

    #Check if update 4
    if ($PlatformReleaseVersion -ge 4425)
    {
        $key = 'License.LicenseEnforced'
        $value = '1'
        if(!(Get-KeyExists -key:$key -xmlDoc:$xmlDoc))
        {
            Add-NewKey -key $key -value $value -parentNode $appsettings -xmlDoc $xmlDoc
        }
        $key = 'License.D365EnterprisePlanId'
        $value = '95d2cd7b-1007-484b-8595-5e97e63fe189;112847d2-abbb-4b47-8b62-37af73d536c1'
        if(!(Get-KeyExists -key:$key -xmlDoc:$xmlDoc))
        {
            Add-NewKey -key $key -value $value -parentNode $appsettings -xmlDoc $xmlDoc
        }
        $key = 'License.D365UniversalPlanId'
        $value = 'f5aa7b45-8a36-4cd1-bc37-5d06dea98645'
        if(!(Get-KeyExists -key:$key -xmlDoc:$xmlDoc))
        {
            Add-NewKey -key $key -value $value -parentNode $appsettings -xmlDoc $xmlDoc
        }
        $key = 'Infrastructure.AzureKeyVaultName'
        $value = "[Topology/Configuration/Setting[@Name='AzureKeyVaultName']/@Value]"
        if(!(Get-KeyExists -key:$key -xmlDoc:$xmlDoc))
        {
            Add-NewKey -key $key -value $value -parentNode $appsettings -xmlDoc $xmlDoc
        }
    }

    #Check if update 11 or later
    if ($PlatformReleaseVersion -ge 4647)
    {
        $key = 'Aos.DeploymentName'
        $value = "initial"
        if(!(Get-KeyExists -key:$key -xmlDoc:$xmlDoc))
        {
            Add-NewKey -key $key -value $value -parentNode $appsettings -xmlDoc $xmlDoc
        }
        $key = 'Infrastructure.SDSAzureSubscriptionId'
        $value = ""
        if(!(Get-KeyExists -key:$key -xmlDoc:$xmlDoc))
        {
            Add-NewKey -key $key -value $value -parentNode $appsettings -xmlDoc $xmlDoc
        }
        $key = 'Infrastructure.SDSAzureResourceGroup'
        $value = ""
        if(!(Get-KeyExists -key:$key -xmlDoc:$xmlDoc))
        {
            Add-NewKey -key $key -value $value -parentNode $appsettings -xmlDoc $xmlDoc
        }
        $key = 'Infrastructure.SDSAzureDirectoryId'
        $value = ""
        if(!(Get-KeyExists -key:$key -xmlDoc:$xmlDoc))
        {
            Add-NewKey -key $key -value $value -parentNode $appsettings -xmlDoc $xmlDoc
        }
        $key = 'Infrastructure.SDSApplicationID'
        $value = ""
        if(!(Get-KeyExists -key:$key -xmlDoc:$xmlDoc))
        {
            Add-NewKey -key $key -value $value -parentNode $appsettings -xmlDoc $xmlDoc
        }
        $key = 'Infrastructure.SDSApplicationKey'
        $value = ""
        if(!(Get-KeyExists -key:$key -xmlDoc:$xmlDoc))
        {
            Add-NewKey -key $key -value $value -parentNode $appsettings -xmlDoc $xmlDoc
        }
    }

    $xmlDoc.Save($webconfig);
}

function Upgrade-HttpProtocol-NewNames([string]$webconfig)
{
    [System.Xml.XmlDocument] $xmlDoc = new-object System.Xml.XmlDocument
    $xmlDoc.Load($webconfig)

    $appsettings = $xmlDoc.SelectSingleNode("/configuration/system.webServer/httpProtocol/customHeaders")
    
    #Check if update 11 or later
    if ($PlatformReleaseVersion -ge 4647)
    {
        $name = 'Strict-Transport-Security'
        $value = "max-age=31536000; includeSubDomains"
        if(!(Get-NameExists -name:$name -xmlDoc:$xmlDoc))
        {
            Add-NewName -name $name -value $value -parentNode $appsettings -xmlDoc $xmlDoc
        }
    }

    $xmlDoc.Save($webconfig);
}

function Upgrade-WebConfig-DeleteKeys([string]$webconfig)
{
    [System.Xml.XmlDocument] $xmlDoc=new-object System.Xml.XmlDocument
    $xmlDoc.Load($webconfig)

    $key = 'HelpWiki.AuthorizationKey'
    if(Get-KeyExists -key:$key -xmlDoc:$xmlDoc)
    {
        Remove-Key -key $key -xmlDoc $xmlDoc
    }

    $key = 'HelpWiki.AuthorizationKeyValue'

    if(Get-KeyExists -key:$key -xmlDoc:$xmlDoc)
    {
        Remove-Key -key $key -xmlDoc $xmlDoc
    }

    $xmlDoc.Save($webconfig);
}

function Upgrade-WebConfig-updateKeys([string]$webconfig)
{
    [System.Xml.XmlDocument] $xmlDoc=new-object System.Xml.XmlDocument
    $xmlDoc.Load($webconfig)

    # Update the AppInsightsKey if it was the old production key to the new production key. Test keys are unchanged.
    $key = "OfficeApps.AppInsightsKey"
    if(Get-KeyExists -key:$key -xmlDoc:$xmlDoc)
    {
        $oldValue = Get-KeyValue -key $key -xmlDoc $xmlDoc
        if ($oldValue -eq "a8640c62-56a5-49c5-8d37-adcc48ac1523")
        {
            Write-Log "Updating OfficeApps.AppInsightsKey"
            Update-KeyValue -key $key -value "0e9ff251-74c0-4b3f-8466-c5345e5d4933" -xmlDoc $xmlDoc
        }
        else
        {
            Write-Log "Not updating OfficeApps.AppInsightsKey"
        }
    }

	# Update the HelpWiki.APIEndPoint key to the new production or test endpoint
    $key = "HelpWiki.APIEndPoint"
    if(Get-KeyExists -key:$key -xmlDoc:$xmlDoc)
    {
		$oldValue = Get-KeyValue -key $key -xmlDoc $xmlDoc
        if ($oldValue -eq "http://ax.help.dynamics.com")
        {
            Write-Log "Updating HelpWiki.APIEndPoint to production endpoint"
            Update-KeyValue -key $key -value "https://lcsapi.lcs.dynamics.com" -xmlDoc $xmlDoc
        }
        elseif ($oldValue -eq "http://ax.help.int.dynamics.com")
        {
            Write-Log "Updating HelpWiki.APIEndPoint to test endpoint"
            Update-KeyValue -key $key -value "https://lcsapi.lcs.tie.dynamics.com" -xmlDoc $xmlDoc
        }
		else
        {
            Write-Log "Not updating HelpWiki.APIEndPoint endpoint"
        }
    }

    $xmlDoc.Save($webconfig);
}

function Get-AssemblyExists([string] $assemblyName, [System.Xml.XmlDocument] $xmlDoc)
{
    [System.Xml.XmlNode] $nodeToRead = $xmlDoc.SelectSingleNode("//add[@assembly='$assemblyName']")
    $keyExists=$false

    if($nodeToRead -eq $null)
    {
       $keyExists=$false
    }
    else
    {
       $keyExists=$true
    }
    return $keyExists
}

function Get-KeyExists([string] $key, [System.Xml.XmlDocument] $xmlDoc)
{
    [System.Xml.XmlNode] $nodeToRead = $xmlDoc.SelectSingleNode("//add[@key='$key']")
    $keyExists=$false

    if($nodeToRead -ne $null)
    {
       $keyExists=$true
    }

    return $keyExists
}

function Get-NameExists([string] $name, [System.Xml.XmlDocument] $xmlDoc)
{
    [System.Xml.XmlNode] $nodeToRead = $xmlDoc.SelectSingleNode("//add[@name='$name']")
    $nameExists=$false

    if ($nodeToRead -ne $null)
	{
		$nameExists=$true
	}

    return $nameExists
}

function Remove-Key([string] $key, [System.Xml.XmlDocument] $xmlDoc)
{
    [System.Xml.XmlNode] $nodeForDeletion = $xmlDoc.SelectSingleNode("//add[@key='$key']")

    if($nodeForDeletion -eq $null)
    {
        Log-Error  "Failed to find key node '$key' for deletion"
    }

    Write-log "selected node '$key' for deletion"

    $nodeForDeletion.ParentNode.RemoveChild($nodeForDeletion);
}

function Remove-Assembly([string] $assemblyName, [System.Xml.XmlDocument] $xmlDoc)
{
    [System.Xml.XmlNode] $nodeForDeletion = $xmlDoc.SelectSingleNode("//add[@assembly='$assemblyName']")

    if($nodeForDeletion -eq $null)
    {
        Log-Error  "Failed to find assembly node '$assemblyName' for deletion"
    }

    Write-log "selected node ''$assemblyName' for deletion"

    $nodeForDeletion.ParentNode.RemoveChild($nodeForDeletion);
}

function Get-KeyValue([string] $key, [System.Xml.XmlDocument] $xmlDoc)
{
    [System.Xml.XmlNode] $nodeToRead = $xmlDoc.SelectSingleNode("//add[@key='$key']")

    if($nodeToRead -eq $null)
    {
        Log-Error  "Failed to find key node '$key' for read"
    }

    Write-log "selected node '$key' for read"

    return $nodeToRead.Value
}

function Update-KeyValue([string] $key, [string] $value, [System.Xml.XmlDocument] $xmlDoc)
{
    [System.Xml.XmlNode] $nodeForDeletion = $xmlDoc.SelectSingleNode("//add[@key='$key']")

    if($nodeForDeletion -eq $null)
    {
        Log-Error  "Failed to find key node '$key' for update"
    }

    Write-log "selected node '$key' for update"

    $nodeForDeletion.Value = $value
}

function Add-NewKey([string] $key, [string] $value, [System.Xml.XmlNode] $parentNode, [System.Xml.XmlDocument] $xmlDoc)
{
    [System.Xml.XmlElement] $element = $xmlDoc.CreateElement("add")
    $newAttribute = $xmlDoc.CreateAttribute('key')
    $newAttribute.Value = $key

    $element.Attributes.Append($newAttribute)

    $newAttribute = $xmlDoc.CreateAttribute('value')
    $newAttribute.Value = $value
    $element.Attributes.Append($newAttribute)

    $parentNode.AppendChild($element)
}

function Add-NewName([string] $name, [string] $value, [System.Xml.XmlNode] $parentNode, [System.Xml.XmlDocument] $xmlDoc)
{
    [System.Xml.XmlElement] $element = $xmlDoc.CreateElement("add")
    $newAttribute = $xmlDoc.CreateAttribute('name')
    $newAttribute.Value = $name

    $element.Attributes.Append($newAttribute)

    $newAttribute = $xmlDoc.CreateAttribute('value')
    $newAttribute.Value = $value
    $element.Attributes.Append($newAttribute)

    $parentNode.AppendChild($element)
}

function Rename-File([string]$from,[string]$to)
{
    Move-Item -Path $from -Destination $to -Force|out-null
    Write-Log "Renamed file '$from' to '$to'."
}

function Decrypt-Config([string]$webroot)
{
    $command = Join-Path -Path "$webroot\bin" -ChildPath $configEncryptor
    if(!(Test-Path -Path $command))
    {
        Log-Error "Cannot find the Microsoft.Dynamics.AX.Framework.ConfigEncryptor.exe at '$webroot\bin\'." -throw
    }

    $webconfig=Join-Path -Path $webroot -ChildPath "Web.config"
    $commandParameter = " -decrypt `"$webconfig`""
    $logdir=[System.IO.Path]::GetDirectoryName($global:logfile)
    $stdOut=Join-Path -Path $logdir -ChildPath "config_decrypt.log"
    $stdErr= Join-Path -Path $logdir -ChildPath "config_decrypt.error.log"
    Start-Process $command $commandParameter -PassThru -Wait -RedirectStandardOutput $stdOut -RedirectStandardError $stdErr

    $decryptError = Get-Content $stdErr
    if ($decryptError -ne $null) {
        Log-Error $decryptError -throw
    }

    Write-Log "Finished decrypting the web.config."
}

function Encrypt-Config([string]$webroot)
{
    $command = Join-Path -Path "$webroot\bin" -ChildPath $configEncryptor
    if(!(Test-Path -Path $command))
    {
        Log-Error "Cannot find the Microsoft.Dynamics.AX.Framework.ConfigEncryptor.exe at '$webroot\bin\'." -throw
    }

    $webconfig=Join-Path -Path $webroot -ChildPath "Web.config"
    $commandParameter = " -encrypt `"$webconfig`""
    $logdir=[System.IO.Path]::GetDirectoryName($global:logfile)
    $stdOut=Join-Path -Path $logdir -ChildPath "config_encrypt.log"
    $stdErr= Join-Path -Path $logdir -ChildPath "config_encrypt.error.log"
    Start-Process $command $commandParameter -PassThru -Wait -RedirectStandardOutput $stdOut -RedirectStandardError $stdErr

    $encryptError = Get-Content $stdErr
    if ($encryptError -ne $null) {
        Log-Error $encryptError -throw
    }

    Write-Log "Finished encrypting the web.config."
}

function Upgrade-WebConfig-rootLocations-ReliableCommunicationManager([string]$webconfig)
{
    [System.Xml.XmlDocument] $xmlDoc = new-object System.Xml.XmlDocument
    $xmlDoc.Load($webconfig)

    $rcmLocationNode = $xmlDoc.SelectSingleNode("/configuration/location[@path='Services/ReliableCommunicationManager.svc']")
    if($rcmLocationNode -eq $null)
    {
        Write-Log "Start adding Services/ReliableCommunicationManager.svc location node"
        $configurationNode = $xmlDoc.SelectSingleNode("/configuration")

        [System.Xml.XmlElement] $locationElement = $xmlDoc.CreateElement("location")
        $pathAttribute = $xmlDoc.CreateAttribute('path')
        $pathAttribute.Value = 'Services/ReliableCommunicationManager.svc'
        $locationElement.Attributes.Append($pathAttribute)

        $configurationNode.AppendChild($locationElement)

        $xmlDoc.Save($webconfig)
    }

    $webServerNode = $xmlDoc.SelectSingleNode("/configuration/location[@path='Services/ReliableCommunicationManager.svc']/system.webServer")
    if($webServerNode -eq $null)
    {
        Write-Log "Start adding system.webServer node to Services/ReliableCommunicationManager.svc location"
        $locationNode = $xmlDoc.SelectSingleNode("/configuration/location[@path='Services/ReliableCommunicationManager.svc']")

        [System.Xml.XmlElement] $webServerElement = $xmlDoc.CreateElement("system.webServer")

        [System.Xml.XmlElement] $httpErrorsElement = $xmlDoc.CreateElement("httpErrors")
        $errorModeAttribute = $xmlDoc.CreateAttribute('errorMode')
        $errorModeAttribute.Value = 'Custom'
        $existingResponseAttribute = $xmlDoc.CreateAttribute('existingResponse')
        $existingResponseAttribute.Value = 'PassThrough'
        $httpErrorsElement.Attributes.Append($errorModeAttribute)
        $httpErrorsElement.Attributes.Append($existingResponseAttribute)

        $webServerElement.AppendChild($httpErrorsElement)

        $locationNode.AppendChild($webServerElement)

        $xmlDoc.Save($webconfig)
    }

    $httpProtocolNode = $xmlDoc.SelectSingleNode("/configuration/location[@path='Services/ReliableCommunicationManager.svc']/system.webServer/httpProtocol")
    if($httpProtocolNode -eq $null)
    {
        Write-Log "Start adding system.webServer/httpProtocol node to Services/ReliableCommunicationManager.svc location"
        $webServerNode = $xmlDoc.SelectSingleNode("/configuration/location[@path='Services/ReliableCommunicationManager.svc']/system.webServer")

        [System.Xml.XmlElement] $httpProtocolElement = $xmlDoc.CreateElement("httpProtocol")

        $webServerNode.AppendChild($httpProtocolElement)

        $xmlDoc.Save($webconfig)
    }

    $customHeadersNode = $xmlDoc.SelectSingleNode("/configuration/location[@path='Services/ReliableCommunicationManager.svc']/system.webServer/httpProtocol/customHeaders")
    if($customHeadersNode -eq $null)
    {
        Write-Log "Start adding system.webServer/httpProtocol/customHeaders node to Services/ReliableCommunicationManager.svc location"
        $httpProtocolNode = $xmlDoc.SelectSingleNode("/configuration/location[@path='Services/ReliableCommunicationManager.svc']/system.webServer/httpProtocol")

        [System.Xml.XmlElement] $customHeadersElement = $xmlDoc.CreateElement("customHeaders")

        $httpProtocolNode.AppendChild($customHeadersElement)

        $xmlDoc.Save($webconfig)
    }

    $removeNode = $xmlDoc.SelectSingleNode("/configuration/location[@path='Services/ReliableCommunicationManager.svc']/system.webServer/httpProtocol/customHeaders/remove[@name='Cache-Control']")
    if($removeNode -eq $null)
    {
        Write-Log "Start adding system.webServer/httpProtocol/customHeaders/remove node to Services/ReliableCommunicationManager.svc location"
        $customHeadersNode = $xmlDoc.SelectSingleNode("/configuration/location[@path='Services/ReliableCommunicationManager.svc']/system.webServer/httpProtocol/customHeaders")

        $addNode = $xmlDoc.SelectSingleNode("/configuration/location[@path='Services/ReliableCommunicationManager.svc']/system.webServer/httpProtocol/customHeaders/add[@name='Cache-Control']")
        if($addNode -ne $null)
        {
            $customHeadersNode.RemoveChild($addNode)
        }

        [System.Xml.XmlElement] $removeElement = $xmlDoc.CreateElement("remove")
        $removeNameAttribute = $xmlDoc.CreateAttribute('name')
        $removeNameAttribute.Value = 'Cache-Control'
        $removeElement.Attributes.Append($removeNameAttribute)

        $customHeadersNode.AppendChild($removeElement)

        $xmlDoc.Save($webconfig)
    }

    $addNode = $xmlDoc.SelectSingleNode("/configuration/location[@path='Services/ReliableCommunicationManager.svc']/system.webServer/httpProtocol/customHeaders/add[@name='Cache-Control']")
    if($addNode -eq $null)
    {
        Write-Log "Start adding system.webServer/httpProtocol/customHeaders/add node to Services/ReliableCommunicationManager.svc location"
        $customHeadersNode = $xmlDoc.SelectSingleNode("/configuration/location[@path='Services/ReliableCommunicationManager.svc']/system.webServer/httpProtocol/customHeaders")

        [System.Xml.XmlElement] $addElement = $xmlDoc.CreateElement("add")
        $addNameAttribute = $xmlDoc.CreateAttribute('name')
        $addNameAttribute.Value = 'Cache-Control'
        $addValueAttribute = $xmlDoc.CreateAttribute('value')
        $addValueAttribute.Value = 'no-cache,no-store'
        $addElement.Attributes.Append($addNameAttribute)
        $addElement.Attributes.Append($addValueAttribute)

        $customHeadersNode.AppendChild($addElement)

        $xmlDoc.Save($webconfig)
    }
}

function Upgrade-WebConfig-rootLocations([string]$webconfig)
{
    if ($PlatformReleaseVersion -ge 4425)
    {
        [System.Xml.XmlDocument] $xmlDoc = new-object System.Xml.XmlDocument
        $xmlDoc.Load($webconfig)
        $newNodeAttribute = 'punchout'
        $nodetoAdd = $xmlDoc.SelectSingleNode("/configuration/location[@path='$newNodeAttribute']")
        if($nodetoAdd -eq $null)
        {
            Write-Log "Start adding punchout node"
            $configurationNode = $xmlDoc.SelectSingleNode("/configuration")

            [System.Xml.XmlElement] $locationElement = $xmlDoc.CreateElement("location")
            $pathAttribute = $xmlDoc.CreateAttribute('path')
            $pathAttribute.Value = $newNodeAttribute
            $locationElement.Attributes.Append($pathAttribute)

            [System.Xml.XmlElement] $webElement = $xmlDoc.CreateElement("system.web")
            [System.Xml.XmlElement] $httpRuntimeElement = $xmlDoc.CreateElement("httpRuntime")
            $requestValidationModeAttribute = $xmlDoc.CreateAttribute('requestValidationMode')
            $requestValidationModeAttribute.Value = '2.0'
            $httpRuntimeElement.Attributes.Append($requestValidationModeAttribute)

            $webElement.AppendChild($httpRuntimeElement)
            $locationElement.AppendChild($webElement)
            $configurationNode.AppendChild($locationElement)

            $xmlDoc.Save($webconfig)
        }
    }
}

function Upgrade-WebConfig-RemoveAssemblies([string]$webConfig)
{
   if ($PlatformReleaseVersion -ge 4425)
   {
        [System.Xml.XmlDocument] $xmlDoc = new-object System.Xml.XmlDocument
        $xmlDoc.Load($webconfig)
        $assemblyName = 'Microsoft.Dynamics.IntegrationFramework.WebService.Process'
        if (Get-AssemblyExists -assemblyName:$assemblyName -xmlDoc:$xmlDoc)
        {
            Remove-Assembly -assemblyName:$assemblyName -xmlDoc:$xmlDoc
        }
   }
}

function Upgrade-WebConfig-RemoveWcfActivityLog([string]$webConfig)
{
    if ($PlatformReleaseVersion -ge 4425)
    {
        Write-Log "Start removing wcf activityLog."
        [System.Xml.XmlDocument] $xmlDoc = new-object System.Xml.XmlDocument
        $xmlDoc.Load($webconfig)

        $Web = $xmlDoc.SelectNodes("//*[@name='WcfActivityLog']")
        foreach($webitem in $Web)
        {
            $webItemParent = $webitem.ParentNode
            $webItemParent.RemoveChild($webitem)
        }

        $xmlDoc.Save($webconfig)
    }
 }

function Upgrade-WebConfig-Add-LcsEnvironmentId([string]$webconfig)
{
    [System.Xml.XmlDocument] $xmlDoc = new-object System.Xml.XmlDocument
    $xmlDoc.Load($webconfig)
    $appsettings=$xmlDoc.SelectSingleNode("/configuration/appSettings")

    $key = 'LCS.EnvironmentId'
    Try
    {
	    $value = Get-ItemProperty -Path hklm:SOFTWARE\Microsoft\Dynamics\AX\Diagnostics\MonitoringInstall -Name "LCSEnvironmentID"
        $value = $value.LCSEnvironmentId
    }
    Catch
    {
        $value = ''
    }
    if(!(Get-KeyExists -key:$key -xmlDoc:$xmlDoc) -and $value -ne '')
    {
        Add-NewKey -key $key -value $value -parentNode $appsettings -xmlDoc $xmlDoc
    }

     $xmlDoc.Save($webconfig);
}

Export-ModuleMember -Function Initialize-Log,Write-Log,Write-Error,Create-Backup,Upgrade-Web-Config -Variable $logfile
# SIG # Begin signature block
# MIIkFAYJKoZIhvcNAQcCoIIkBTCCJAECAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCBIaVqsTjs6FE9B
# z8Ck1oWhLFKwpVPwrt/orXQGtn8OdKCCDYIwggYAMIID6KADAgECAhMzAAAAww6b
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
# SEXAQsmbdlsKgEhr/Xmfwb1tbWrJUnMTDXpQzTGCFegwghXkAgEBMIGVMH4xCzAJ
# BgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25k
# MR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xKDAmBgNVBAMTH01pY3Jv
# c29mdCBDb2RlIFNpZ25pbmcgUENBIDIwMTECEzMAAADDDpun2LLc9ywAAAAAAMMw
# DQYJYIZIAWUDBAIBBQCggdowGQYJKoZIhvcNAQkDMQwGCisGAQQBgjcCAQQwHAYK
# KwYBBAGCNwIBCzEOMAwGCisGAQQBgjcCARUwLwYJKoZIhvcNAQkEMSIEIFxNkoEU
# fsiJfMXSWzmvHsmfQPuH9ScnVJ0G9RTolVQoMG4GCisGAQQBgjcCAQwxYDBeoECA
# PgBVAHAAZwByAGEAZABlAEMAbwBuAGYAaQBnAEgAZQBsAHAAZQByAFUAcABkAGEA
# dABlADMALgBwAHMAbQAxoRqAGGh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbTANBgkq
# hkiG9w0BAQEFAASCAQAn0NgqH+ZjSNJxz2nvufH4GHazNLqPJTlLduMQ3D7cOEMF
# 0MR/CUz6XeCRH13uRGoprNyFsACAaEWTk99Dr58Dm+k6kDYQi/e+G/1bvG9Iq/D3
# qTzGl512XlS9d7xP3yEUjP0Nalhzh5FNyBvR/KnCZNEE6rrvKofe+0IKFqsOOz5K
# l7ufmZYp/EYWzUekSx/53XU/ZEchR7Yq4qeTZ37tQBrImelTIIXP2ySV57fYx7on
# meqvG79pDgwrqurjGVm0vFddayQ6K6nuz4WJiR6Apbk90pOnGrE1Pyu+B65gueW7
# hAqMXg5b0DGMIYt4nc1tY5SRW0UKdXf3sLY3+5FpoYITRjCCE0IGCisGAQQBgjcD
# AwExghMyMIITLgYJKoZIhvcNAQcCoIITHzCCExsCAQMxDzANBglghkgBZQMEAgEF
# ADCCATwGCyqGSIb3DQEJEAEEoIIBKwSCAScwggEjAgEBBgorBgEEAYRZCgMBMDEw
# DQYJYIZIAWUDBAIBBQAEIEgeOZP0FjH+7Lsk09lP8SZSobre5iV2Jb0IY0hq/gAy
# AgZaspvFNZcYEzIwMTgwMzI1MjEwNTU3LjA5NFowBwIBAYACAfSggbikgbUwgbIx
# CzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRt
# b25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xDDAKBgNVBAsTA0FP
# QzEnMCUGA1UECxMebkNpcGhlciBEU0UgRVNOOjU3QzgtMkQxNS0xQzhCMSUwIwYD
# VQQDExxNaWNyb3NvZnQgVGltZS1TdGFtcCBTZXJ2aWNloIIOyjCCBnEwggRZoAMC
# AQICCmEJgSoAAAAAAAIwDQYJKoZIhvcNAQELBQAwgYgxCzAJBgNVBAYTAlVTMRMw
# EQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVN
# aWNyb3NvZnQgQ29ycG9yYXRpb24xMjAwBgNVBAMTKU1pY3Jvc29mdCBSb290IENl
# cnRpZmljYXRlIEF1dGhvcml0eSAyMDEwMB4XDTEwMDcwMTIxMzY1NVoXDTI1MDcw
# MTIxNDY1NVowfDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAO
# BgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEm
# MCQGA1UEAxMdTWljcm9zb2Z0IFRpbWUtU3RhbXAgUENBIDIwMTAwggEiMA0GCSqG
# SIb3DQEBAQUAA4IBDwAwggEKAoIBAQCpHQ28dxGKOiDs/BOX9fp/aZRrdFQQ1aUK
# AIKF++18aEssX8XD5WHCdrc+Zitb8BVTJwQxH0EbGpUdzgkTjnxhMFmxMEQP8WCI
# hFRDDNdNuDgIs0Ldk6zWczBXJoKjRQ3Q6vVHgc2/JGAyWGBG8lhHhjKEHnRhZ5Ff
# gVSxz5NMksHEpl3RYRNuKMYa+YaAu99h/EbBJx0kZxJyGiGKr0tkiVBisV39dx89
# 8Fd1rL2KQk1AUdEPnAY+Z3/1ZsADlkR+79BL/W7lmsqxqPJ6Kgox8NpOBpG2iAg1
# 6HgcsOmZzTznL0S6p/TcZL2kAcEgCZN4zfy8wMlEXV4WnAEFTyJNAgMBAAGjggHm
# MIIB4jAQBgkrBgEEAYI3FQEEAwIBADAdBgNVHQ4EFgQU1WM6XIoxkPNDe3xGG8Uz
# aFqFbVUwGQYJKwYBBAGCNxQCBAweCgBTAHUAYgBDAEEwCwYDVR0PBAQDAgGGMA8G
# A1UdEwEB/wQFMAMBAf8wHwYDVR0jBBgwFoAU1fZWy4/oolxiaNE9lJBb186aGMQw
# VgYDVR0fBE8wTTBLoEmgR4ZFaHR0cDovL2NybC5taWNyb3NvZnQuY29tL3BraS9j
# cmwvcHJvZHVjdHMvTWljUm9vQ2VyQXV0XzIwMTAtMDYtMjMuY3JsMFoGCCsGAQUF
# BwEBBE4wTDBKBggrBgEFBQcwAoY+aHR0cDovL3d3dy5taWNyb3NvZnQuY29tL3Br
# aS9jZXJ0cy9NaWNSb29DZXJBdXRfMjAxMC0wNi0yMy5jcnQwgaAGA1UdIAEB/wSB
# lTCBkjCBjwYJKwYBBAGCNy4DMIGBMD0GCCsGAQUFBwIBFjFodHRwOi8vd3d3Lm1p
# Y3Jvc29mdC5jb20vUEtJL2RvY3MvQ1BTL2RlZmF1bHQuaHRtMEAGCCsGAQUFBwIC
# MDQeMiAdAEwAZQBnAGEAbABfAFAAbwBsAGkAYwB5AF8AUwB0AGEAdABlAG0AZQBu
# AHQALiAdMA0GCSqGSIb3DQEBCwUAA4ICAQAH5ohRDeLG4Jg/gXEDPZ2joSFvs+um
# zPUxvs8F4qn++ldtGTCzwsVmyWrf9efweL3HqJ4l4/m87WtUVwgrUYJEEvu5U4zM
# 9GASinbMQEBBm9xcF/9c+V4XNZgkVkt070IQyK+/f8Z/8jd9Wj8c8pl5SpFSAK84
# Dxf1L3mBZdmptWvkx872ynoAb0swRCQiPM/tA6WWj1kpvLb9BOFwnzJKJ/1Vry/+
# tuWOM7tiX5rbV0Dp8c6ZZpCM/2pif93FSguRJuI57BlKcWOdeyFtw5yjojz6f32W
# apB4pm3S4Zz5Hfw42JT0xqUKloakvZ4argRCg7i1gJsiOCC1JeVk7Pf0v35jWSUP
# ei45V3aicaoGig+JFrphpxHLmtgOR5qAxdDNp9DvfYPw4TtxCd9ddJgiCGHasFAe
# b73x4QDf5zEHpJM692VHeOj4qEir995yfmFrb3epgcunCaw5u+zGy9iCtHLNHfS4
# hQEegPsbiSpUObJb2sgNVZl6h3M7COaYLeqN4DMuEin1wC9UJyH3yKxO2ii4sanb
# lrKnQqLJzxlBTeCG+SqaoxFmMNO7dDJL32N79ZmKLxvHIa9Zta7cRDyXUHHXodLF
# VeNp3lfB0d4wwP3M5k37Db9dT+mdHhk4L7zPWAUu7w2gUDXa7wknHNWzfjUeCLra
# NtvTX4/edIhJEjCCBNkwggPBoAMCAQICEzMAAACqt6mI/+pXwwoAAAAAAKowDQYJ
# KoZIhvcNAQELBQAwfDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24x
# EDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlv
# bjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRpbWUtU3RhbXAgUENBIDIwMTAwHhcNMTYw
# OTA3MTc1NjUzWhcNMTgwOTA3MTc1NjUzWjCBsjELMAkGA1UEBhMCVVMxEzARBgNV
# BAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jv
# c29mdCBDb3Jwb3JhdGlvbjEMMAoGA1UECxMDQU9DMScwJQYDVQQLEx5uQ2lwaGVy
# IERTRSBFU046NTdDOC0yRDE1LTFDOEIxJTAjBgNVBAMTHE1pY3Jvc29mdCBUaW1l
# LVN0YW1wIFNlcnZpY2UwggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIBAQCe
# 2H97V3j6BfqjmreQr5q51bZ0dpHLuM67Ks4rKe9ftGt1mHUogK2Yj7mq8J3StptH
# ZJjGpVmqkXj5Hot59yR0Ruok/mkErr7rf1NTE1nVD/z7zd32B0GbGzc32Vx2md2u
# x8Pb061owlCcdA5Edy4unW/BHe8sxzt0rtuXLY+BxUcFQMBKN0iTvAOaS/CNBMtD
# cPvoWLGdrFDnubWE8cebB+z3mmnbr0h/rFkxhmIWcJVe8cvMOkfz6j8CjBC7vSOM
# qQNzTw64DFzxL6p/+mSbjC6YFMBGzyZPPAYjxk8it5IPGgIZ/JwpzYTega/w/a2Y
# rKWIg4aVVIa0m3FAxi83AgMBAAGjggEbMIIBFzAdBgNVHQ4EFgQUCLhyHRUk9ZMC
# 4Z/SHEzTq8xZybAwHwYDVR0jBBgwFoAU1WM6XIoxkPNDe3xGG8UzaFqFbVUwVgYD
# VR0fBE8wTTBLoEmgR4ZFaHR0cDovL2NybC5taWNyb3NvZnQuY29tL3BraS9jcmwv
# cHJvZHVjdHMvTWljVGltU3RhUENBXzIwMTAtMDctMDEuY3JsMFoGCCsGAQUFBwEB
# BE4wTDBKBggrBgEFBQcwAoY+aHR0cDovL3d3dy5taWNyb3NvZnQuY29tL3BraS9j
# ZXJ0cy9NaWNUaW1TdGFQQ0FfMjAxMC0wNy0wMS5jcnQwDAYDVR0TAQH/BAIwADAT
# BgNVHSUEDDAKBggrBgEFBQcDCDANBgkqhkiG9w0BAQsFAAOCAQEAYI8O7gfOGuF9
# n3nGeA6dzkykAZ1qZ0eXERuKcsrkwXznLeOPkWe86HR6P8rpRiQAP6HO8H5P0vQa
# ffR2OB0UNh2l2YlvysVTFO8TLCACldEKecXS7m08P5FG6blS3t9c4pykTVFqHcLp
# k01GchYm+YT/k3fd6AM9VPzCBKBfj4e9VXSa6WSssOQaylw7IB8LVVgIsMPLp7xZ
# LE1Cke1bszAukqeTjk6ADK6peTHsUpF8lRCvf8HOI9sPmcxqw8T0LB91ZIIsoNgO
# B/eaDmWoXJWBnH5Y7nnzkSGt280sv7WIcv4GG51fdg92MoiuUjxtOS7MBk4kSS0v
# qWYA1vxoJqGCA3QwggJcAgEBMIHioYG4pIG1MIGyMQswCQYDVQQGEwJVUzETMBEG
# A1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWlj
# cm9zb2Z0IENvcnBvcmF0aW9uMQwwCgYDVQQLEwNBT0MxJzAlBgNVBAsTHm5DaXBo
# ZXIgRFNFIEVTTjo1N0M4LTJEMTUtMUM4QjElMCMGA1UEAxMcTWljcm9zb2Z0IFRp
# bWUtU3RhbXAgU2VydmljZaIlCgEBMAkGBSsOAwIaBQADFQCcnMVrmMynwa1HIOzT
# RPzObdDqA6CBwTCBvqSBuzCBuDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hp
# bmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jw
# b3JhdGlvbjEMMAoGA1UECxMDQU9DMScwJQYDVQQLEx5uQ2lwaGVyIE5UUyBFU046
# MjY2NS00QzNGLUM1REUxKzApBgNVBAMTIk1pY3Jvc29mdCBUaW1lIFNvdXJjZSBN
# YXN0ZXIgQ2xvY2swDQYJKoZIhvcNAQEFBQACBQDeYem0MCIYDzIwMTgwMzI1MDky
# NjEyWhgPMjAxODAzMjYwOTI2MTJaMHQwOgYKKwYBBAGEWQoEATEsMCowCgIFAN5h
# 6bQCAQAwBwIBAAICJp4wBwIBAAICGgswCgIFAN5jOzQCAQAwNgYKKwYBBAGEWQoE
# AjEoMCYwDAYKKwYBBAGEWQoDAaAKMAgCAQACAxbjYKEKMAgCAQACAx6EgDANBgkq
# hkiG9w0BAQUFAAOCAQEASz033EpW84nZpGQKE/bTByOuDdqNUFl3448hNVLTcWSY
# PUnqnrq3Ig17AzC9zTkzlQJIfuCHRyqYabBRaIDxwJU2ZJpQMHpqOylWwTLFn/Uw
# yieLX/qWMwxApoDRwmFRGbC7jLiS67X9IL4waE93CQQoXVtjue+UsJxdV6qLqIs4
# QPVxazegiyO9JzwhLVgUW8xHvbS5432I7ouRGCgYYdynLLFQxJAZQk6Jqwk4JzIr
# qLRtGNFjxTBtZYfF1mswPMWa5+tq0MbU8KMFkUOWySKeFPAf6Kazsk4taJ75HcBy
# 0u99o+F9G/d3s6jINcULbm1gGIuvPlZm7gvPB384IDGCAvUwggLxAgEBMIGTMHwx
# CzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRt
# b25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xJjAkBgNVBAMTHU1p
# Y3Jvc29mdCBUaW1lLVN0YW1wIFBDQSAyMDEwAhMzAAAAqrepiP/qV8MKAAAAAACq
# MA0GCWCGSAFlAwQCAQUAoIIBMjAaBgkqhkiG9w0BCQMxDQYLKoZIhvcNAQkQAQQw
# LwYJKoZIhvcNAQkEMSIEIEpDjBaBDhMTWpAJKPjrzqE3wJGYfmyMCZBI1JZBz6wm
# MIHiBgsqhkiG9w0BCRACDDGB0jCBzzCBzDCBsQQUnJzFa5jMp8GtRyDs00T8zm3Q
# 6gMwgZgwgYCkfjB8MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQ
# MA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9u
# MSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0EgMjAxMAITMwAAAKq3
# qYj/6lfDCgAAAAAAqjAWBBQoMyUfR5+52q9gS8+7I/DRhE38aDANBgkqhkiG9w0B
# AQsFAASCAQBAquFCIJyi+rcTQH6O0/M/3WMRhtt71D06J3Pnq3NSiI/qVrl3d1BS
# TgcjIqOn5xxSSqDFP1+je2nGuxX3EMSm+FS99f/DSDLb+ve6Cyp6c09hD3cRl+pi
# Mb0PQFzNi/YzJiesTOaVW5oYV/yecWJQ1+PS2pN4way1GzKlkkUZmuNHo8IrzzFG
# QRf2TnEO5XHrqqNeH7HDTMeOhLu4iV3U6eVezpTr09BsLMPOx/+rovnvf2ZmF0M9
# Z13tZVJE2XjebrAXJ5g9Nh3XTGHqyq29ekqs9uL7i2EGF3MOjd9btH9andnPgw21
# LSsMsmq9RQCN7N531QbuI7RxxaP+7iZQ
# SIG # End signature block
