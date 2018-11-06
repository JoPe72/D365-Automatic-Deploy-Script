[CmdletBinding()]
param
(
    [Parameter(Mandatory=$true)]
    [string]$servicemodelxml,

    [Parameter(Mandatory=$true)]
    [string]$log
)

#region configuration generators
function Write-LCM-Configuration($configdata)
{
    Write-Verbose "Creating the LCM configuration to set the encryption certificate thumbprint..."
    $thumbprint=$configdata.AllNodes[0].Thumbprint
    $script="`
    LocalConfigurationManager 
    {
        CertificateId=`"$thumbprint`"
        ConfigurationMode = `"ApplyOnly`"
        RefreshMode = `"Push`"
    }"
    
    write-content $script
}

function Write-Certificate-Configuration
{
    [System.Xml.XmlDocument] $xd = new-object System.Xml.XmlDocument
    $xd.LoadXml($global:decodedservicemodelxml)
    $certificates=$xd.SelectNodes("//ServiceModel/Certificates/Certificate")
    [string]$global:lastcertidentifier=[string]::Empty

    Write-Trace-Start "Certificate installation"
    foreach($certificate in $certificates){
        $identifier=$certificate.Name
        $rawdata=$certificate.RawData
        $pwd=$certificate.Password
        $storename=$certificate.StoreName
        $storelocation=$certificate.StoreLocation
        [string]$thumbprint=$certificate.Thumbprint

        if(-not [string]::IsNullOrEmpty($thumbprint) -and -not [string]::IsNullOrEmpty($rawdata) -and -not [string]::IsNullOrEmpty($pwd)){
            Write-Log "Creating the configuration for the certificate: '$identifier'"

            if(-not [string]::IsNullOrEmpty($global:lastcertidentifier)){
                $script="`
    DynamicsCertificate $identifier `
    { `
        Ensure=`"Present`" `
        Identifier=`"$identifier`" `
        RawData=`"$rawdata`" `
        StoreName=`"$storename`" `
        StoreLocation=`"$storelocation`" `
        Password=`"$pwd`" `
        Thumbprint=`"$thumbprint`" `
        DependsOn=@(`"$global:lastcertidentifier`") `
        MonitoringAssembly=`"$global:telemetrydll`" `
    }"
            }else{
                $script="`
    DynamicsCertificate $identifier `
    { `
        Ensure=`"Present`" `
        Identifier=`"$identifier`" `
        RawData=`"$rawdata`" `
        StoreName=`"$storename`" `
        StoreLocation=`"$storelocation`" `
        Password=`"$pwd`" `
        Thumbprint=`"$thumbprint`" `
        MonitoringAssembly=`"$global:telemetrydll`" `
    }"
            }

            Write-Content $script
            $global:lastcertidentifier="[DynamicsCertificate]$identifier"
        }else{
            Write-Log "Skipping the configuration for the certificate '$identifier' as a required value is missing in the service model."
        }
    }

    Write-Trace-End "Certificate installation"
}

function Write-Dependency-Configuration
{
    $parentdir=Split-Path -parent $PSCommandPath
    $parentdir=Split-Path -parent $parentdir
    [System.Xml.XmlDocument] $xd = new-object System.Xml.XmlDocument
    $xd.LoadXml($global:decodedservicemodelxml)
    $dependencies=$xd.SelectNodes("/ServiceModel/Dependencies/Dependency")
    $global:lastdependency=$global:lastcertidentifier
    Write-Trace-Start "Install dependencies"
    foreach($dependency in $dependencies){
      $type=$dependency.getAttribute("Type")
      switch($type){
        "WindowsFeature"
        {
            $name=$dependency.getAttribute("Name")
            $script="`
    WindowsFeature $name `
    { `
        Ensure=`"Present`"
        Name=`"$name`" `
        DependsOn=@(`"$global:lastdependency`") `
    }"
            write-content $script
            write-log "Creating the configuration for the WindowsFeature $name"
            $global:lastdependency="[WindowsFeature]$name"
        }

        "Msi" 
        {
            # not supported currently as some MSI installation requires reboot
        }

        "Exe" 
        {
            # not supported currently some exe installation requires reboot
        }

        Default {}
      }
    }

    Write-Trace-End "Install dependencies"
}

function Write-Firewall-Ports-Configuration
{
    [System.Xml.XmlDocument] $xd = new-object System.Xml.XmlDocument
    $xd.LoadXml($global:decodedservicemodelxml)
    $ns=New-Object System.Xml.XmlNamespaceManager($xd.NameTable)
    $ns.AddNamespace("ns",$xd.DocumentElement.NamespaceURI)

    $serviceName=$xd.SelectSingleNode("//ns:ServiceModel",$ns).getAttribute("Name")
    $inputendpoints=$xd.SelectNodes("/ServiceModel/Endpoints/InputEndpoint")
    Write-Trace-start "Open firewall ports"
    [string[]]$ports=$null
    foreach($inputendpoint in $inputendpoints){
        [string]$localport=$inputendpoint.getAttribute("LocalPort")
        if($ports -notcontains $localport){
            $ports += $localport
            Write-Log "Creating the configuration for the firewall port $name"
            $name="$serviceName-$localPort"
            $displayName="$ServiceName service on port $localPort"
            $access="Allow"
            $state="Enabled"
            [string[]]$profile=@("Any")
            $direction="Inbound"
            [string[]]$remoteport=@("Any")
            $description="$ServiceName service on port $localPort"
            $protocol="TCP"
        
            $script="`
            xFirewall OpenFirewallPort-$name `
            { `
                Ensure=`"Present`" `
                Name=`"$name`" `
                DisplayName=`"$displayName`" `
                Access=`"$access`" `
                State=`"$state`" `
                Profile=`"$profile`" `
                Direction=`"$direction`" `
                RemotePort=`"$remoteport`" `
                LocalPort=`"$localPort`" `
                Description=`"$description`" `
                Protocol=`"$protocol`" `
            }"
            Write-Content $script
        }
    }

    Write-Trace-End "Open firewall ports"
}

function Write-Perf-Counters-Configuration
{
    [System.Xml.XmlDocument] $xd = new-object System.Xml.XmlDocument
    $xd.LoadXml($global:decodedservicemodelxml)
    $ns=New-Object System.Xml.XmlNamespaceManager($xd.NameTable)
    $ns.AddNamespace("ns",$xd.DocumentElement.NamespaceURI)

    # retrieve parameters
    $webRoot=$xd.SelectSingleNode("//ns:WorkingFolder[@Name='WebRoot']",$ns).getAttribute("Directory")
    $codeFolder = Join-Path $webRoot "bin"

    Write-Trace-start "Perf counter initialization"
    $script="`
    DynamicsPerfCounter InitializePerfCounters `
    { `
        Ensure=`"Present`" `
        CodeFolder=`"$codeFolder`" `
        DependsOn=@(`"[DynamicsPackage]DeployPackages`") `
        MonitoringAssembly=`"$global:telemetrydll`" `
    }"

    Write-Content $script
    Write-Log "Creating the configuration for the Dynamics perf counters"
    Write-Trace-End "Perf counter initialization"
}

function Write-DynamicsTools-Configuration
{
    $targetPath = Join-Path $env:SystemDrive "DynamicsTools"
    $sourcePath = Join-Path $PSScriptRoot "Redist\DynamicsTools"

    Write-Trace-Start "Copy DynamicsTools"
    $script = 
@"
    File CopyDynamicsTools
    { 
        Ensure = 'Present'
        DestinationPath = '$targetPath'
        Recurse = `$true
        SourcePath = '$sourcePath'
        Type = 'Directory'
        MatchSource = `$true
        DependsOn=@("$global:lastdependency")
    }
"@

    Write-Content $script
    Write-Log "Copying supporting tools (ex. nuget and 7za) to the target machine."
    Write-Trace-End "Copy DynamicsTools"
}

function Write-AosWebsite-Configuration
{
    $parentdir=Split-Path -parent $PSCommandPath
    [System.Xml.XmlDocument] $xd = new-object System.Xml.XmlDocument
    $xd.LoadXml($global:decodedservicemodelxml)
    $ns=New-Object System.Xml.XmlNamespaceManager($xd.NameTable)
    $ns.AddNamespace("ns",$xd.DocumentElement.NamespaceURI)

    # retrieve parameters
    $webRoot=$xd.SelectSingleNode("//ns:WorkingFolder[@Name='WebRoot']",$ns).getAttribute("Directory")
    $source=join-path $parentdir "..\Code"

    Write-Trace-start "Copy AOS website code"

    $script="`
    File CopyAosWebsiteCode `
    { `
        Ensure=`"Present`" `
        DestinationPath=`"$webRoot`" `
        Recurse=`$true `
        SourcePath=`"$source`" `
        Type=`"Directory`" `
        MatchSource=`$true `
        DependsOn=@(`"$global:lastdependency`") `
    }"

    Write-Content $script
    Write-Log "Creating the configuration to copy the AOS website code to the target machine"
    Write-Trace-End "Copy AOS website code"
}

function Write-Packages-Configuration([string]$deploydb)
{
    $parentdir=Split-Path -parent $PSCommandPath
    $parentdir=Split-Path -parent $parentdir
    [System.Xml.XmlDocument] $xd = new-object System.Xml.XmlDocument
    $xd.LoadXml($global:decodedservicemodelxml)
    $ns=New-Object System.Xml.XmlNamespaceManager($xd.NameTable)
    $ns.AddNamespace("ns",$xd.DocumentElement.NamespaceURI)

    # retrieve parameters
    $packageDir=$xd.SelectSingleNode("//ns:WorkingFolder[@Name='PackagesLocalDirectory']",$ns).getAttribute("Directory")
    $clickOncePackageDir=$xd.SelectSingleNode("//ns:InstallParameter[@Name='clickOnceInstallPath']",$ns).getAttribute("Value")
    $metadataInstallPath=$xd.SelectSingleNode("//ns:InstallParameter[@Name='metadataInstallPath']",$ns).getAttribute("Value")
    $webRoot=$xd.SelectSingleNode("//ns:WorkingFolder[@Name='WebRoot']",$ns).getAttribute("Directory")
    $frameworkInstallPath=$xd.SelectSingleNode("//ns:InstallParameter[@Name='frameworkInstallPath']",$ns).getAttribute("Value")
    $dataset=$xd.SelectSingleNode("//ns:Setting[@Name='Deploy.Dataset']",$ns).getAttribute("Value")
    $packageName=$xd.SelectSingleNode("//ns:Setting[@Name='Aos.Packages']",$ns).getAttribute("Value")
    $packageSourceDir=join-path $parentdir "Packages"
	$dataStack=$xd.SelectSingleNode("//ns:Setting[@Name='DataAccess.UseManagedDatastack']",$ns).getAttribute("Value")

    Write-Trace-start "Deploy packages"

    $script = 
@"
    DynamicsPackage DeployPackages
    {
        PackageName="$packageName"
        TargetPackageDirectory="$packageDir"
        ClickOnceInstallDirectory="$clickOncePackageDir"
        PackageSourceDirectory="$packageSourceDir"
        Ensure="Present"
        MetadataDirectory="$metadataInstallPath"
        FrameworkDirectory="$frameworkInstallPath"
        DataSet="$dataset"
        WebRoot="$webRoot"
        DependsOn=@("[File]CopyAosWebsiteCode", "[File]CopyDynamicsTools")
        MonitoringAssembly="$global:telemetrydll"
        LogDir='$global:logdir'
        DeployDatabase='$deploydb'
        UseManagedDatastack='$dataStack'
    }
"@

    Write-Content $script
    Write-Log "Creating the configuration to deploy the packages"
    Write-Trace-End "Deploy packages"
}

function Write-Storage-Emulator-Configuration
{
    $emulatorinstallpath=Get-AzureStorageEmulatorInstallPath
    if(-not [string]::IsNullOrEmpty($emulatorinstallpath))
    {
        Write-Log "Creating the configuration to start the Azure Storage Emulator"
        $storageemulator=join-path $emulatorinstallpath "AzureStorageEmulator.exe"
        $initEmulatorStdOut=join-path $global:logdir "InitEmulator-output.log"
        $initEmulatorStdErr=join-path $global:logdir "InitEmulator-error.log"
        $startEmulatorStdOut=join-path $global:logdir "StartEmulator-output.log"
        $startEmulatorStdErr=join-path $global:logdir "StartEmulator-error.log"
        $clearEmulatorStdOut=join-path $global:logdir "ClearEmulator-output.log"
        $clearEmulatorStdErr=join-path $global:logdir "ClearEmulator-error.log"
        $script="`
        WindowsProcess StopEmulator
        {
            Path=`"$storageemulator`" `
            Arguments=`"start /inprocess`" `
            Ensure=`"Absent`" `
        }

        DynamicsProcess InitializeEmulator
        {
            Ensure=`"Present`" `
            Arguments=`"init -forcecreate -server $env:COMPUTERNAME`"
            File=`"$storageemulator`" `
            StandardErrorPath=`"$initEmulatorStdErr`" `
            StandardOutputPath=`"$initEmulatorStdOut`" `
            MonitoringAssembly=`"$global:telemetrydll`" `
            WaitForExit=`$true `
            DependsOn=@(`"[WindowsProcess]StopEmulator`")
        }

        DynamicsProcess StartEmulator
        {
            Ensure=`"Present`" `
            Arguments=`"start`"
            File=`"$storageemulator`" `
            StandardErrorPath=`"$startEmulatorStdErr`" `
            StandardOutputPath=`"$startEmulatorStdOut`" `
            MonitoringAssembly=`"$global:telemetrydll`" `
            WaitForExit=`$true `
            DependsOn=@(`"[DynamicsProcess]InitializeEmulator`")
        }
        
        DynamicsProcess ClearEmulator
        {
            Ensure=`"Present`" `
            Arguments=`"clear all`"
            File=`"$storageemulator`" `
            StandardErrorPath=`"$clearEmulatorStdErr`" `
            StandardOutputPath=`"$clearEmulatorStdOut`" `
            MonitoringAssembly=`"$global:telemetrydll`" `
            WaitForExit=`$true `
            DependsOn=@(`"[DynamicsProcess]InitializeEmulator`")
        }
        "
    
        Write-Content $script

        # Generate script for windows task to start the azure storage emulator (reboot scenario)
        Write-Log "Creating the configuration to register windows task to start the azure storage emulator"
        
        $script = @"
        DynamicsScheduledTask StartAzureStorageEmulator_ScheduledTask
        {
            TaskName  = "DynamicsStartAzureStorageEmulator"
            Ensure    = "Present"
            Command   = "${env:ProgramFiles(x86)}\Microsoft SDKs\Azure\Storage Emulator\AzureStorageEmulator.exe"
            Arguments = "START"
        }
"@
        Write-Content $script

        Write-Trace-End "start storage emulator"
    }
}

function Write-Database-Configuration
{
    [System.Xml.XmlDocument] $xd = new-object System.Xml.XmlDocument
    $xd.LoadXml($global:decodedservicemodelxml)
    $ns=New-Object System.Xml.XmlNamespaceManager($xd.NameTable)
    $ns.AddNamespace("ns",$xd.DocumentElement.NamespaceURI)
    $packageDir=$xd.SelectSingleNode("//ns:Setting[@Name='Aos.PackageDirectory']",$ns).getAttribute("Value")
    $dbserver=$xd.SelectSingleNode("//ns:Setting[@Name='DataAccess.DbServer']",$ns).getAttribute("Value")
    $dbname=$xd.SelectSingleNode("//ns:Setting[@Name='DataAccess.Database']",$ns).getAttribute("Value")
    $sqlpwd=(Get-KeyVaultSecret -VaultUri $xd.SelectSingleNode("//ns:Setting[@Name='DataAccess.SqlPwd']",$ns).getAttribute("Value"))
    $sqluser=$xd.SelectSingleNode("//ns:Setting[@Name='DataAccess.SqlUser']",$ns).getAttribute("Value")

    Write-Trace-start "Restore database"

    $script="`
    DynamicsDatabase DeployDatabase `
    { `
        Ensure=`"Present`" `
        PackageDirectory=`"$packageDir`" `
        DatabaseName=`"$dbname`" `
        DatabaseServer=`"$dbserver`" `
        UserName=`"$sqluser`" `
        Password=`"$sqlpwd`" `
        DependsOn=@(`"[DynamicsPackage]DeployPackages`") `
        MonitoringAssembly=`"$global:telemetrydll`" `
    }"
    Write-Log "Creating the configuration to deploy the Unified Operations database"
    Write-Content $script

    Write-Trace-End "Restore database"
}

function Write-WebSite-Configuration([switch]$DeployDb)
{
    Import-Module WebAdministration
    $parentdir=Split-Path -parent $PSCommandPath
    [System.Xml.XmlDocument] $xd = new-object System.Xml.XmlDocument
    $xd.LoadXml($global:decodedservicemodelxml)
    $ns=New-Object System.Xml.XmlNamespaceManager($xd.NameTable)
    $ns.AddNamespace("ns",$xd.DocumentElement.NamespaceURI)
    $websiteName=$xd.SelectSingleNode("//ns:Setting[@Name='Infrastructure.ApplicationName']",$ns).getAttribute("Value")
    $webAppPoolName=$websiteName
    $localPort=$xd.SelectSingleNode("//ns:InputEndpoint",$ns).getAttribute("LocalPort")
    $webRoot=$xd.SelectSingleNode("//ns:WorkingFolder[@Name='WebRoot']",$ns).getAttribute("Directory")
    $endpoints=$xd.SelectNodes("//ServiceModel/Endpoints/InputEndpoint")
    $hostnames=@()
    [bool]$createARRhealthprobebinding=$false
    Write-Trace-start "Create AOS website"

    if($DeployDb){
    # create the aos app-pool
    $script="`
    xWebAppPool CreateAosAppPool `
    { `
        Ensure=`"Present`" `
        State=`"Started`" `
        Name=`"$webAppPoolName`" `
        DependsOn=@(`"[DynamicsDatabase]DeployDatabase`") `
    }"}else{
     # create the aos app-pool
    $script="`
    xWebAppPool CreateAosAppPool `
    { `
        Ensure=`"Present`" `
        State=`"Started`" `
        Name=`"$webAppPoolName`" `
    }"    
    }
    Write-Log "Creating the configuration to create the AOS app pool"
    Write-Content $script

    # Task 3745881: use topology data to determine app pool settings
    $optionalAppPoolSettings = 
@"        
        PingMaxResponseTime=90
        RapidFailProtection=`$false
        IdleTimeout=20
"@
    
    $script=
@"
    DynamicsApppoolManager SetApppoolIdentity
    {
        Ensure="Present"
        IdentityType=2
        ApppoolName="$webAppPoolName"
        Username=""
        Password=""
        DependsOn=@("[xWebAppPool]CreateAosAppPool")
        MonitoringAssembly="$global:telemetrydll"
$optionalAppPoolSettings
    }
"@ 
    Write-Log "Creating the configuration to set the AOS app pool identity"
    Write-Content $script

    $bindingInfo=@()
    $endpointcollection=@{}

    Write-Log "Creating ssl bindings for the AOS website"
    for($i=0;$i -lt $endpoints.Count;$i++){
        $endpoint=$endpoints[$i]
        $baseurl=New-Object System.Uri($endpoint.BaseUrl)
        $baseurlsafe=$baseurl.DnsSafeHost
        $sslCertName=$endpoint.Certificate
        if(-not [string]::IsNullOrEmpty($sslCertName)){
            $sslCertThumbprint=$xd.SelectSingleNode("//ns:Certificate[@Name='$sslCertName']",$ns).getAttribute("Thumbprint")
            $storelocation=$xd.SelectSingleNode("//ns:Certificate[@Name='$sslCertName']",$ns).getAttribute("StoreLocation")
            $storename=$xd.SelectSingleNode("//ns:Certificate[@Name='$sslCertName']",$ns).getAttribute("StoreName")
            $cert=get-childitem Cert:\$storelocation\$storeName|where {$_.Thumbprint -eq $sslCertThumbprint}
            if($cert -ne $null){
                $thumbprint=$cert.Thumbprint
            }else{
                $message="Either the SSL binding certificate is not present in the machine store or could not be retrieved."
                Write-Log $message
                throw $message
            }
        }

        $protocol = "https"
        if ([System.String]::IsNullOrWhiteSpace($endpoint.Certificate)){
            $protocol = "http"
        }

        $port=$endpoint.LocalPort
        if($port -eq 80 -and $baseurlsafe -ne "127.0.0.1")
        {
            $createARRhealthprobebinding=$true
        }

        if(IsUniqueUrlAndPort -endpointcollection:$endpointcollection -baseurl:$baseurlsafe -port:$port){
            $endpointcollection[$i]=@($baseurlsafe,$port,$protocol)
            if($baseurlsafe -ne "127.0.0.1"){
                $hostnames+=$baseurlsafe
                write-verbose "Adding url '$baseurlsafe' to the hosts file" 
            }
        }
    }

    #special binding to support the ARR health probing
    if($createARRhealthprobebinding)
    {
        $protocol='http'
        $baseurl=""
        $port=80
        $ipaddress=Get-WMIObject win32_NetworkAdapterConfiguration|Where-Object{$_.IPEnabled -eq $true}|Foreach-Object {$_.IPAddress}|Foreach-Object {[IPAddress]$_ }|Where-Object {$_.AddressFamily -eq 'Internetwork'}|Foreach-Object {$_.IPAddressToString}
        $msftwebbindinginfo="@(MSFT_xWebBindingInformation { `
                    Protocol=`"$protocol`" `
                    Port=$port `
                    HostName=`"$baseurl`" `
                    IPAddress=`"$ipaddres`" `
                    });"

        $bindingInfo+=$msftwebbindinginfo
    }

    # create the binding info collection
    for($i=0;$i -lt $endpointcollection.Keys.Count;$i++)
    {
        $bindinginfotuple=$endpointcollection[$i]
        $baseurl=$bindinginfotuple[0]
        $port=$bindinginfotuple[1]
        $protocol=$bindinginfotuple[2]
        if($i -eq $endpointcollection.Keys.Count-1){
	        $msftwebbindinginfo="@(MSFT_xWebBindingInformation { `
                    Protocol=`"$protocol`" `
                    Port=$port `
                    CertificateThumbprint=`"$thumbprint`" `
                    CertificateStoreName=`"My`" `
                    HostName=`"$baseurl`" `
                    })"
        }else{
            $msftwebbindinginfo="@(MSFT_xWebBindingInformation { `
                    Protocol=`"$protocol`" `
                    Port=$port `
                    CertificateThumbprint=`"$thumbprint`" `
                    CertificateStoreName=`"My`" `
                    HostName=`"$baseurl`" `
                    });"
        }

		$bindingInfo+=$msftwebbindinginfo
    }

    $script="`
    xWebSite CreateAosWebSite `
    { `
        Ensure=`"Present`" `
        Name=`"$websiteName`" `
        PhysicalPath=`"$webRoot`" `
        State=`"Started`" `
        ApplicationPool=`"$webAppPoolName`" `
        BindingInfo=@($bindingInfo) `
        DependsOn=@(`"[DynamicsApppoolManager]SetApppoolIdentity`") `
    }"

    Write-Log "Creating the configuration to create the AOS web site"
    Write-Content $script

    $script = "`
    DynamicsIISAdministration SetIISConfiguration `
    { `
        Ensure=`"Present`" `
        ConfigurationPath=`"MACHINE/WEBROOT/APPHOST/$websiteName/Apps`" `
        Filter=`"system.webServer/security/requestFiltering/fileExtensions/add[@fileExtension='.config']`"
        SettingName=`"allowed`" `
        SettingValue=`"True`" `
        DependsOn=@(`"[xWebSite]CreateAosWebSite`") `
        MonitoringAssembly=`"$global:telemetrydll`" `
    }"
    Write-Log "Creating the configuration to allow the config files from being served from the IIS server"
    Write-content $script

    $hostentries=@()
    for($i=0;$i -lt $hostnames.Length;$i++)
    {
        $hostname=$hostnames[$i]
        if($i -eq $hostnames.Length-1){
            $entry="`@{Ipaddress=`"127.0.0.1`";Hostname=`"$hostname`"`}"
        }else{
            $entry="@{Ipaddress=`"127.0.0.1`";Hostname=`"$hostname`"`},"
        }

        $hostentries+=$entry
    }

    $script = "`
    DynamicsHostsFileManager SetHostsFileEntries `
    { `
        Ensure=`"Present`" `
        WebsiteName=`"$websiteName`" `
        HostEntries=$hostentries `
        DependsOn=@(`"[DynamicsIISAdministration]SetIISConfiguration`") `
        MonitoringAssembly=`"$global:telemetrydll`" `
    }"
    Write-Log "Creating the configuration to add hosts file entries"
    Write-content $script
    
    Write-Trace-End "Create AOS website" 
}

function Write-WebConfigFile-Configuration([string]$servicemodel)
{
    Write-Trace-start "Update web config file"
    $script = "`
    DynamicsWebConfigKeyValue UpdateWebConfigSetting`
    { `
        Ensure=`"Present`" `
        ServiceModel=`"$servicemodel`" `
        DependsOn=@(`"[DynamicsHostsFileManager]SetHostsFileEntries`") `
        MonitoringAssembly=`"$global:telemetrydll`" `
    }"

    Write-Log "Creating the configuration to update the web.config file"
    Write-Content $script

    Write-Trace-End "Update web config file"
}

function Write-WifConfigFile-Configuration([string]$servicemodel)
{
    Write-Trace-start "Update wif and wif.services config file"
    $script = "`
    DynamicsWifConfigKeyValue UpdateWifConfigSetting `
    { `
        ServiceModel=`"$servicemodel`" `
        Ensure=`"Present`" `
        DependsOn=@(`"[DynamicsWebConfigKeyValue]UpdateWebConfigSetting`") `
        MonitoringAssembly=`"$global:telemetrydll`" `
    }"

    Write-Log "Creating the configuration to update the wif.config and wif.services.config files"
    write-content $script

    Write-Trace-End "Update wif and wif.services config file"
}

function Write-Aos-Http-Configuration([string]$webroot,[string]$protocol)
{
    Write-Trace-start "Configure the HTTP protocol for the AOS website"
    $script = "`
    ConfigureAosProtocol AosHttpConfiguration `
    { `
        WebRoot=`"$webroot`" `
        Ensure=`"Present`" `
        DependsOn=@(`"[DynamicsWifConfigKeyValue]UpdateWifConfigSetting`") `
        MonitoringAssembly=`"$global:telemetrydll`" `
        Protocol=`"$protocol`" `
    }"

    Write-Log "Creating the configuration to set the AOS protocol"
    write-content $script

    Write-Trace-End "Configure the HTTP protocol for the AOS website"
}

function Write-AosUser-Configuration
{
    [System.Xml.XmlDocument] $xd = new-object System.Xml.XmlDocument
    $xd.LoadXml($global:decodedservicemodelxml)
    $ns=New-Object System.Xml.XmlNamespaceManager($xd.NameTable)
    $ns.AddNamespace("ns",$xd.DocumentElement.NamespaceURI)

    $dbserver=$xd.SelectSingleNode("//ns:Setting[@Name='DataAccess.DbServer']",$ns).getAttribute("Value")
    $dbname=$xd.SelectSingleNode("//ns:Setting[@Name='DataAccess.Database']",$ns).getAttribute("Value")
    $username=$xd.SelectSingleNode("//ns:Setting[@Name='DataAccess.SqlUser']",$ns).getAttribute("Value")
    $password=(Get-KeyVaultSecret -VaultUri $xd.SelectSingleNode("//ns:Setting[@Name='DataAccess.SqlPwd']",$ns).getAttribute("Value"))
    $hosrurl=$xd.SelectSingleNode("//ns:Setting[@Name='Infrastructure.HostUrl']",$ns).getAttribute("Value")

     $script = "
     DynamicsAosAdminManager UpdateAosUser `
    { `
        Ensure=`"Present`" `
        HostUrl=`"$hosrurl`" `
        DatabaseServer=`"$dbserver`" `
        DependsOn=@(`"[ConfigureAosProtocol]AosHttpConfiguration`") `
        DatabaseName=`"$dbname`" `
        UserName=`"$username`" `
        Password=`"$password`" `
        MonitoringAssembly=`"$global:telemetrydll`" `
    }"

    Write-Log "Creating the configuration to update the AOS user"
    Write-Content $script
}

function Write-DBSYNC-Configuration
{
    $parentDir=Split-Path -parent $PSCommandPath
    [System.Xml.XmlDocument] $xd = new-object System.Xml.XmlDocument
    $xd.LoadXml($global:decodedservicemodelxml)
    $ns=New-Object System.Xml.XmlNamespaceManager($xd.NameTable)
    $ns.AddNamespace("ns",$xd.DocumentElement.NamespaceURI)
    $bindir=$xd.SelectSingleNode("//ns:Setting[@Name='Common.BinDir']",$ns).getAttribute("Value")
    $metadataDir=$bindir
    $sqlServer=$xd.SelectSingleNode("//ns:Setting[@Name='DataAccess.DbServer']",$ns).getAttribute("Value")
    $database=$xd.SelectSingleNode("//ns:Setting[@Name='DataAccess.Database']",$ns).getAttribute("Value")
    $webRoot=$xd.SelectSingleNode("//ns:Setting[@Name='Infrastructure.WebRoot']",$ns).getAttribute("Value")

    $arguments="-bindir `"$binDir`" -metadatadir `"$metadataDir`" -sqlcredentialinenvironment `"$sqlPwd`" -sqlserver `"$sqlServer`" -sqldatabase `"$database`" -setupmode `"sync`" -syncmode `"fullall`""
    $codedir=Join-Path $webRoot "bin"
    $dbsyncexe= join-path "$codedir" "Microsoft.Dynamics.AX.Deployment.Setup.exe"

    $standardout=Join-Path $global:logdir "dbsync.output"
    $standarderr=Join-Path $global:logdir "dbsync.error"

    Write-Trace-start "Perform DBSync"

    $script = "`
    DynamicsProcess DbSync `
    { `
        Ensure=`"Present`" `
        Arguments='$arguments' `
        File=`"$dbsyncexe`" `
        StandardErrorPath=`"$standarderr`" `
        StandardOutputPath=`"$standardout`" `
        MonitoringAssembly=`"$global:telemetrydll`" `
        WaitForExit=`$true `
        DependsOn=@(`"[DynamicsAosAdminManager]UpdateAosUser`") `
    }"
    
    Write-Log "Creating the configuration to execute the DBSync process"
    Write-Content $script

    Write-Trace-End "Perform DBSync"
}

function Write-InterNode-Sync-Configuration([string]$primarynode)
{
    $script="WaitForAll DbSync `
    {
        ResourceName = '[DynamicsProcess]DbSync' `
        NodeName = '$primarynode' `
        RetryIntervalSec = 60 `
        RetryCount = 50 `
    }"

    Write-Log "Creating the configuration to synchronize actions between multiple AOS instances"
    Write-Content $script
}

function Write-SymbolicLinkGeneration-Configuration([switch]$primarynode)
{
    [System.Xml.XmlDocument] $xd = new-object System.Xml.XmlDocument
    $xd.LoadXml($global:decodedservicemodelxml)
    $ns=New-Object System.Xml.XmlNamespaceManager($xd.NameTable)
    $ns.AddNamespace("ns",$xd.DocumentElement.NamespaceURI)
    $vstoolscount=$xd.SelectSingleNode("//ns:Setting[@Name='Infrastructure.VSToolsCount']",$ns).getAttribute("Value")
    $webRoot=$xd.SelectSingleNode("//ns:Setting[@Name='Infrastructure.WebRoot']",$ns).getAttribute("Value")
    $packagedir=$xd.SelectSingleNode("//ns:WorkingFolder[@Name='PackagesLocalDirectory']",$ns).getAttribute("Directory")
    if($vstoolscount -eq "0"){
        Write-Trace-start "Create symlink"

        if($primarynode){
        $script = "`
    DynamicsSymLink CreateSymLink `
    { `
        Ensure=`"Present`" `
        Webroot=`"$webRoot`" `
        PackageDir=`"$packageDir`" `
        DependsOn=@(`"[DynamicsProcess]DbSync`") `
        MonitoringAssembly=`"$global:telemetrydll`" `
    }"
        }else{
         $script = "`
    DynamicsSymLink CreateSymLink `
    { `
        Ensure=`"Present`" `
        Webroot=`"$webRoot`" `
        PackageDir=`"$packageDir`" `
        DependsOn=@(`"[DynamicsWifConfigKeyValue]UpdateWifConfigSetting`") `
        MonitoringAssembly=`"$global:telemetrydll`" `
    }"
    }
        Write-Log "Creating the configuration to create sym links"
        Write-Content $script

        Write-Trace-End "Create symlink"
    }
}

function Write-NGen-Configuration
{
    [System.Xml.XmlDocument] $xd = new-object System.Xml.XmlDocument
    $xd.LoadXml($global:decodedservicemodelxml)
    $ns=New-Object System.Xml.XmlNamespaceManager($xd.NameTable)
    $ns.AddNamespace("ns",$xd.DocumentElement.NamespaceURI)
    $vstoolscount=$xd.SelectSingleNode("//ns:Setting[@Name='Infrastructure.VSToolsCount']",$ns).getAttribute("Value")
    $webRoot=$xd.SelectSingleNode("//ns:Setting[@Name='Infrastructure.WebRoot']",$ns).getAttribute("Value")
    $packagedir=$xd.SelectSingleNode("//ns:WorkingFolder[@Name='PackagesLocalDirectory']",$ns).getAttribute("Directory")
    if($vstoolscount -eq "0"){
        $script = "`
    DynamicsNgen GenerateNativeImages `
    { `
        Ensure=`"Present`" `
        Webroot=`"$webRoot`" `
        PackageDir=`"$packageDir`" `
        DependsOn=@(`"[DynamicsSymLink]CreateSymLink`") `
        UpdateProbingPath=`$true `
        UseLazyTypeLoader=`$false `
        MonitoringAssembly=`"$global:telemetrydll`" `
        PerformNgen=`$true `
    }"
    }else{
        $script = "`
    DynamicsNgen GenerateNativeImages `
    { `
        Ensure=`"Present`" `
        Webroot=`"$webRoot`" `
        PackageDir=`"$packageDir`" `
        DependsOn=@(`"[DynamicsWifConfigKeyValue]UpdateWifConfigSetting`") `
        UpdateProbingPath=`$false `
        UseLazyTypeLoader=`$true `
        MonitoringAssembly=`"$global:telemetrydll`" `
        PerformNgen=`$false `
    }"
    }

    Write-Log "Creating the configuration to generate native images of the Dynamics assemblies"
    Write-Content $script
}

function Write-Resources-Configuration
{
    [System.Xml.XmlDocument] $xd = new-object System.Xml.XmlDocument
    $xd.LoadXml($global:decodedservicemodelxml)
    $ns=New-Object System.Xml.XmlNamespaceManager($xd.NameTable)
    $ns.AddNamespace("ns",$xd.DocumentElement.NamespaceURI)
    $webRoot=$xd.SelectSingleNode("//ns:Setting[@Name='Infrastructure.WebRoot']",$ns).getAttribute("Value")
    $packageDir=$xd.SelectSingleNode("//ns:WorkingFolder[@Name='PackagesLocalDirectory']",$ns).getAttribute("Directory")

    Write-Trace-start "Deploy website resources"
    $script = "`
    DynamicsWebsiteResource AosResources `
    { `
        Ensure=`"Present`" `
        WebRoot=`"$webRoot`" `
        PackageDir=`"$packageDir`" `
        DependsOn=@(`"[DynamicsNgen]GenerateNativeImages`") `
        MonitoringAssembly=`"$global:telemetrydll`" `
    }"

    Write-Log "Creating the configuration to deploy the AOS resources"
    Write-Content $script
    
    Write-Trace-End "Deploy resources"
}

function Write-BatchService-Configuration
{
    [System.Xml.XmlDocument] $xd = new-object System.Xml.XmlDocument
    $xd.LoadXml($global:decodedservicemodelxml)
    $ns=New-Object System.Xml.XmlNamespaceManager($xd.NameTable)
    $ns.AddNamespace("ns",$xd.DocumentElement.NamespaceURI)
    $webRoot=$xd.SelectSingleNode("//ns:WorkingFolder[@Name='WebRoot']",$ns).getAttribute("Directory")
    $sqlUser=$xd.SelectSingleNode("//ns:Setting[@Name='DataAccess.SqlUser']",$ns).getAttribute("Value")
    $sqlPwd=(Get-KeyVaultSecret -VaultUri $xd.SelectSingleNode("//ns:Setting[@Name='DataAccess.SqlPwd']",$ns).getAttribute("Value"))
    $sqlServer=$xd.SelectSingleNode("//ns:Setting[@Name='DataAccess.DbServer']",$ns).getAttribute("Value")
    $database=$xd.SelectSingleNode("//ns:Setting[@Name='DataAccess.Database']",$ns).getAttribute("Value")

    $webconfig=join-path $webRoot "web.config"
    $batchexe=join-path $webroot "bin\Batch.exe"
    $binarypathname="$batchexe -service $webconfig"

    Write-Trace-start "Install batch service"

    # setting the state to Running will result in the service resource timing out as the timeout is hardcoded to 2 seconds :(
    $script = "`
    Service InstallBatchService `
    { `
        Ensure=`"Present`" `
        Name=`"DynamicsAxBatch`" `
        BuiltInAccount=`"NetworkService`" `
        State=`"Stopped`" `
        DisplayName=`"Microsoft Dynamics 365 Unified Operations: Batch Management Service`" `
        Path='$binarypathname' `
        DependsOn=@(`"[DynamicsWebsiteResource]AosResources`") `
        StartupType=`"Manual`"
    }"

    Write-Log "Creating the configuration to install the Dynamics batch service"
    Write-Content $script

    $sc=Join-Path $env:windir "system32\sc.exe"
    $standardout=Join-Path $global:logdir "DynamicsAXBatch-sc-start-output.log"
    $standarderr=Join-Path $global:logdir "DynamicsAXBatch-sc-start-error.log"

    $script = "`
    DynamicsProcess StartBatchService `
    { `
        Ensure=`"Present`" `
        Arguments=`"start DynamicsAXBatch`" `
        File=`"$sc`" `
        StandardErrorPath=`"$standarderr`" `
        StandardOutputPath=`"$standardout`" `
        MonitoringAssembly=`"$global:telemetrydll`" `
        DependsOn=@(`"[Service]InstallBatchService`") `
        WaitForExit=`$true `
    }"

    Write-Log "Creating the configuration to start the Dynamics batch service"
    Write-Content $script

    # Generate script for windows task to start the batch service (reboot scenario)
    Write-Log "Creating the configuration to register windows task to start the batch service"
        
    $script = @"
    DynamicsScheduledTask StartBatch_ScheduledTask
    {
        TaskName  = "DynamicsStartBatch"
        Ensure    = "Present"
        Command   = "POWERSHELL.EXE"
        Arguments = "Start-Service 'MSSQLSERVER' | %{$_.WaitForStatus('Running', '00:05:00')}; Start-Service 'DynamicsAxBatch'"
        DependsOn = @("[Service]InstallBatchService")
    }
"@
    Write-Content $script

    Write-Trace-End "Install batch service"
}

function Write-Reports-Configuration
{
    $parentDir=Split-Path -parent $PSCommandPath
    [System.Xml.XmlDocument] $xd = new-object System.Xml.XmlDocument
    $xd.LoadXml($global:decodedservicemodelxml)
    $settings=$xd.SelectNodes("/ServiceModel/Configuration/Setting")
    $configuration=@{}
    foreach($setting in $settings){
        $key=$setting.getAttribute("Name")
        $value=$setting.getAttribute("Value")
        $configuration[$key]=$value
    }

    $configjson=convertto-json $configuration
    $jsontobytes=[System.Text.Encoding]::UTF8.GetBytes($configjson)
    $encodedconfiguration=[System.Convert]::ToBase64String($jsontobytes)

    $scriptPath = Join-Path $parentDir "AXDeployReports.ps1"
    $log=join-path $global:logdir "AXDeployReports.log"
    if(!(Test-path $log)){
        New-Item $log -ItemType File -Force|out-null
    }

    $expr = "$scriptPath `"$encodedconfiguration`" `"$log`""

    Write-Trace-start "Deploy reports"

    $script = "
    Script DeployReports `
    { `
        GetScript={@{}} `
        TestScript={return `$false} `
        SetScript={& $expr} `
        DependsOn=@(`"[DynamicsProcess]StartBatchService`") `
    }"

    Write-Log "Creating the configuration to deploy the reports"
    Write-Content $script

    Write-Trace-End "Deploy reports"
}

function Write-RetailPerfCounters-Configuration
{
    $parentDir=Split-Path -parent $PSCommandPath
    [System.Xml.XmlDocument] $xd = new-object System.Xml.XmlDocument
    $xd.LoadXml($global:decodedservicemodelxml)
    $ns=New-Object System.Xml.XmlNamespaceManager($xd.NameTable)
    $ns.AddNamespace("ns",$xd.DocumentElement.NamespaceURI)
    $webRoot=$xd.SelectSingleNode("//ns:Setting[@Name='Infrastructure.WebRoot']",$ns).getAttribute("Value")
    $instrumentedAssemblyPath=join-path $webRoot "bin\Microsoft.Dynamics.Retail.Diagnostics.dll"
    $scriptPath = Join-Path $parentDir "Register-PerfCounters.ps1"
    $log=join-path $global:logdir "RegisterRetailPerfCounters.log"
    if(!(Test-path $log)){
        New-Item $log -ItemType File -Force|out-null
    }

	$expr = "$scriptPath $instrumentedAssemblyPath $log"
	if(!(Test-Path "$log\RegisterRetailPerfCounters")){
		New-Item -ItemType directory -Path "$log\RegisterRetailPerfCounters" -Force|out-null
	}

	Write-Trace-start "Create retail perf counters"
	if(Test-path $scriptPath)
	{
		$script = "`
		Script RetailPerfCounters `
		{ `
			GetScript={@{}} `
			TestScript={return `$false} `
			SetScript={& $expr} `
			DependsOn=@(`"[DynamicsProcess]StartBatchService`") `
		}"
	}
	else
	{
		Write-Log "Retail perf counters script not found, dummy script used for execution"
		$script = "`
		Script RetailPerfCounters `
		{ `
			GetScript={@{}} `
			TestScript={return `$false} `
			SetScript={return `$true} `
			DependsOn=@(`"[DynamicsProcess]StartBatchService`") `
		}"
	}

	Write-Log "Creating the configuration to execute the Retail perf counters script"
	Write-Content $script 

	Write-Trace-End "Create retail perf counters"
}

function Write-ProductConfiguration
{
    [string]$pcAppPool="ProductConfiguration"	
    [System.Xml.XmlDocument] $xd = new-object System.Xml.XmlDocument
    $xd.LoadXml($global:decodedservicemodelxml)
    $ns=New-Object System.Xml.XmlNamespaceManager($xd.NameTable)
    $ns.AddNamespace("ns",$xd.DocumentElement.NamespaceURI)
    $webRoot=$xd.SelectSingleNode("//ns:Setting[@Name='Infrastructure.WebRoot']",$ns).getAttribute("Value")
    $websiteName=$xd.SelectSingleNode("//ns:Setting[@Name='Infrastructure.ApplicationName']",$ns).getAttribute("Value")

    $packageNames = $xd.SelectSingleNode("//ns:Setting[@Name='Aos.Packages']",$ns).getAttribute("Value")
    $packagesSourceDir = Join-Path (Split-Path -Path $PSScriptRoot -Parent) "Packages"

    # product configuration variables
	$productconfigurationdir=join-path $webRoot "productconfiguration"
    $pcwebsitepath=join-path $webRoot "productconfiguration"

    Write-Trace-start "Create product configuration web application"

    # check of production configuration package will be installed
    $productConfigurationPackageFound = $false
    $targetPackageName = 'dynamicsax-productconfiguration'
    
    Add-Type -AssemblyName "System.IO.Compression"
    Add-Type -AssemblyName "System.IO.Compression.FileSystem"

    foreach($packageName in $packageNames.Split(','))
    {
        $packageName = $packageName.Trim()
        $filter = "$packageName.*.nupkg"
        $files = Get-ChildItem -Path $packagesSourceDir -Filter $filter
        foreach($file in $files)
        {
            [System.IO.Compression.ZipArchive] $archive = [System.IO.Compression.ZipFile]::OpenRead($file.FullName)
            [System.IO.Compression.ZipArchiveEntry]$entry = $archive.GetEntry("$($packageName).nuspec")
            if ($entry -ne $null)
            {
                [xml]$xml = New-Object System.Xml.XmlDocument
                $xml.Load($entry.Open())
                $ns = @{"ns"=$xml.DocumentElement.NamespaceURI}
                $dependency = select-xml -xml $xml -Namespace $ns -XPath "//ns:dependencies/ns:dependency[@id='$targetPackageName']"
                if ($dependency -ne $null)
                {
                    $productConfigurationPackageFound = $true
                }
            }
        }
    }

    if ($productConfigurationPackageFound)
    {        
        $script = 
@"
        xWebAppPool CreateProductConfigurationWebAppPool
        {
            Ensure="Present"
            State="Started"
            Name="$pcAppPool"
            DependsOn=@("[Script]RetailPerfCounters")
        }
    	
        # create product configuration web application
        xWebApplication CreateProductConfigurationWebApplication `
        {
            Ensure="Present"
            Name="ProductConfiguration"
            Website="$websiteName"
            WebAppPool="$pcAppPool"
            PhysicalPath="$pcwebsitepath"
            DependsOn=@("[xWebAppPool]CreateProductConfigurationWebAppPool")
        }
"@

        Write-Log "Creating the configuration to create the product configuration web application"
        Write-Content $script

        
        # Configure app pool settings
        $optionalAppPoolSettings = 
@"        
        PingMaxResponseTime=90
        RapidFailProtection=`$true
        IdleTimeout=20
"@

        $script=
@"
        DynamicsApppoolManager SetProductConfigurationApppoolIdentity
        {
            Ensure="Present"
            IdentityType=2
            ApppoolName="$pcAppPool"
            Username=""
            Password=""
            DependsOn=@("[xWebAppPool]CreateProductConfigurationWebAppPool")
            MonitoringAssembly="$global:telemetrydll"
$optionalAppPoolSettings
        }
"@ 
        Write-Log "Creating the configuration to set the product configuration app pool identity"
        Write-Content $script

    }
    else
    {
        Write-Log "Skipping product configuration web site DSC because package file not found: '$targetPackageName'."
    }

    Write-Trace-End "Create product configuration web application"
}

function Write-ConfigInstallationInfo-Configuration([string]$servicemodel)
{
    Write-Trace-start "Create config installation info"
    $script = "`
    ConfigInstallationInfoManager CreateConfigInstallationInfo `
    { `
        Ensure=`"Present`" `
        MonitoringAssembly=`"$global:telemetrydll`" `
        ServiceXml=`"$servicemodel`" `
        Log=`"$global:logdir`" `
        InstallationAssembly=`"$installationdll`" `
        InstallationInfoXml=`"$installationinfoxml`" `
        DependsOn=@(`"[Script]RetailPerfCounters`") `
    } "

    Write-Content $script
    Write-Trace-End "Create config installation info"
}

function Write-EncryptionConfiguration-Configuration([string]$webroot)
{
    Write-Trace-start "Create config to encrypt web configuration"
    $script = "`
    EncryptionManager EncryptConfiguration `
    { `
        Ensure=`"Present`" `
        MonitoringAssembly=`"$global:telemetrydll`" `
        WebRoot=`"$webroot`" `
        Log=`"$global:logdir`" `
        DependsOn=@(`"[ConfigInstallationInfoManager]CreateConfigInstallationInfo`") `
    } "

    Write-Content $script
    Write-Trace-End "Create config to encrypt web configuration"
}

#endregion

#region helper functions
function Initialize-Log([string]$logdir,[string]$logfile)
{
    if(-not (Test-Path $logdir)){
        New-Item -ItemType Directory -Path $logdir|out-null
    }
    
    if(Test-Path $logfile){
        Remove-Item $logfile -Force|out-null
    }

    New-item $logfile -ItemType File -Force|out-null
}

function Write-Log([string]$message)
{
    Add-Content $global:logfile $message
    Write-Host $message
}

function Write-Header
{
    $datetime=Get-Date
    $header="`
###
# ==++==
#
# Copyright (c) Microsoft Corporation. All rights reserved.
#
# Generated date: $datetime
#
# This file is auto-generated by a tool. Any changes made to this file will be lost.
#
# This file will be compiled to generate a Windows DSC configuration that will deploy 
# the Dynamics AOS service on this machine.
###

#region imports
Import-Module `"`$PSScriptRoot\DeploymentHelper.psm1`" -DisableNameChecking
#endregion

#region Instrumentation helpers
StartMonitoring -monitoringdll:`"`$PSScriptRoot\Microsoft.Dynamics.AX7Deployment.Instrumentation.dll`"
#endregion

#region service configuration
Configuration AosServiceConfiguration { `

    Import-DscResource -Module xWebAdministration `
    Import-DscResource -Module xNetworking `
    Import-DscResource -Module xDynamics `
    Import-DscResource -Module xDatabase `
    Import-DscResource –ModuleName PSDesiredStateConfiguration `
    
    Node `"localhost`" { 
    "
    Write-Content $header
}

function Write-Footer([string]$outputpath)
{
    $footer="}`
    }`

`$configData=@{
    AllNodes=@(
        @{ NodeName = `"localhost`";CertificateFile=`"$global:encryptioncertpublickeyfile`";Thumbprint=`"$global:encryptioncertthumbprint`";PSDscAllowDomainUser=`$true; }
    )
}

#endregion

# generate the MOF file `    
AosServiceConfiguration -OutputPath:$outputpath -ConfigurationData:`$configData"

    Write-Content $footer
}

function Write-Content([string]$content)
{
   Add-Content $global:dscconfigfile -Value $content
}

function Write-Trace-Start([string]$message)
{
    $tracestart="Start-Trace `"$message`""
    Add-Content $global:dscconfigfile -value ([string]::Empty)
    Add-Content $global:dscconfigfile -value $tracestart
}

function Write-Trace-End([string]$message)
{
    $traceend="End-Trace `"$message`""
    Add-Content $global:dscconfigfile -value $traceend
}

function Get-MSIProperties([string]$msiFile)
{
    [hashtable]$msiprops=@{}
 
    [System.IO.FileInfo]$file=Get-Item $msiFile
    $windowsInstaller=New-Object -com WindowsInstaller.Installer
    $database=$windowsInstaller.GetType().InvokeMember("OpenDatabase", "InvokeMethod",$null,$windowsInstaller,@($file.FullName,0))
    # product code
    $q = "SELECT Value FROM Property WHERE Property = 'ProductCode'"
    $View = $database.GetType().InvokeMember("OpenView", "InvokeMethod", $Null, $database, ($q))
    $View.GetType().InvokeMember("Execute", "InvokeMethod", $Null, $View, $Null)
    $record = $View.GetType().InvokeMember("Fetch", "InvokeMethod", $Null, $View, $Null)
    [string]$productCode = $record.GetType().InvokeMember("StringData", "GetProperty", $Null, $record, 1)
    $productCode=$productCode.TrimStart("{")
    $productCode=$productCode.TrimEnd("}")

    # product name
    $q = "SELECT Value FROM Property WHERE Property = 'ProductName'"
    $View = $database.GetType().InvokeMember("OpenView", "InvokeMethod", $Null, $database, ($q))
    $View.GetType().InvokeMember("Execute", "InvokeMethod", $Null, $View, $Null)
    $record = $View.GetType().InvokeMember("Fetch", "InvokeMethod", $Null, $View, $Null)
    [string]$productname=$record.GetType().InvokeMember("StringData", "GetProperty", $Null, $record, 1)
    $View.GetType().InvokeMember("Close", "InvokeMethod", $Null, $View, $Null)

    # product version
    $q = "SELECT Value FROM Property WHERE Property = 'ProductVersion'"
    $View = $database.GetType().InvokeMember("OpenView", "InvokeMethod", $Null, $database, ($q))
    $View.GetType().InvokeMember("Execute", "InvokeMethod", $Null, $View, $Null)
    $record = $View.GetType().InvokeMember("Fetch", "InvokeMethod", $Null, $View, $Null)
    [string]$productversion=$record.GetType().InvokeMember("StringData", "GetProperty", $Null, $record, 1)
    $View.GetType().InvokeMember("Close", "InvokeMethod", $Null, $View, $Null)

    $msiprops.productcode=$productCode
    $msiprops.productname=$productname
    $msiprops.productversion=$productversion
    return $msiprops
}

function IsUniqueUrlAndPort($endpointcollection,[string]$baseurl,[string]$port){
    for($i=0;$i -lt $endpointcollection.Keys.Count;$i++){
        $baseurlandport=$endpointcollection[$i]
        if($baseurlandport[0] -eq $baseurl -and $baseurlandport[1] -eq $port){
            return $false
        }
    }

    return $true
}

function Get-RegistryKeyValue([string]$registryKey,[string]$registryKeyValueName,[string]$defaultValue=[string]::Empty)
{
    $item=Get-ItemProperty "$registryKey" -ErrorAction SilentlyContinue
    $value=$item.$registryKeyValueName
    if([string]::IsNullOrEmpty($value)){
        return $defaultValue
    }

    return $value
}

function Get-AzureStorageEmulatorInstallPath
{
    $registrykey="HKLM:\SOFTWARE\Wow6432Node\Microsoft\Windows Azure Storage Emulator\"
    $registrykeyvaluename="InstallPath"
    $emulatorInstallPath=Get-RegistryKeyValue -registryKey:$registrykey -registryKeyValueName:$registrykeyvaluename
    Write-Verbose "Emulator installation path: '$emulatorInstallPath'"
    return $emulatorInstallPath
}

Function Get-ProductEntry
{
    param
    (
        [string] $Name,
        [string] $IdentifyingNumber
    )
    
    $uninstallKey = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall"
    $uninstallKeyWow64 = "HKLM:\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall"
    
    if($IdentifyingNumber)
    {
        $keyLocation = "$uninstallKey\$identifyingNumber"
        $item = Get-Item $keyLocation -EA SilentlyContinue
        if(-not $item)
        {
            $keyLocation = "$uninstallKeyWow64\$identifyingNumber"
            $item = Get-Item $keyLocation -EA SilentlyContinue
        }

        return $item
    }
    
    foreach($item in (Get-ChildItem -EA Ignore $uninstallKey, $uninstallKeyWow64))
    {
        if($Name -eq (Get-LocalizableRegKeyValue $item "DisplayName"))
        {
            return $item
        }
    }
    
    return $null
}

function Get-LocalizableRegKeyValue
{
    param(
        [object] $RegKey,
        [string] $ValueName
    )
    
    $res = $RegKey.GetValue("{0}_Localized" -f $ValueName)
    if(-not $res)
    {
        $res = $RegKey.GetValue($ValueName)
    }
    
    return $res
}

function Copy-Files([string]$targetdir)
{
    Copy-Item "$PSScriptRoot\DeploymentHelper.psm1" $targetdir
    Copy-Item "$PSScriptRoot\..\ETWManifest\Microsoft.Dynamics.AX7Deployment.Instrumentation.dll" $targetdir
}

function CreateConfiguration($configData)
{
    [System.Xml.XmlDocument] $xd = new-object System.Xml.XmlDocument
    $xd.LoadXml($global:decodedservicemodelxml)
    $ns=New-Object System.Xml.XmlNamespaceManager($xd.NameTable)
    $ns.AddNamespace("ns",$xd.DocumentElement.NamespaceURI)
    $deploydb=$xd.SelectSingleNode("//ns:Setting[@Name='Deploy.DeployDatabase']",$ns).getAttribute("Value")
    $webroot=$xd.SelectSingleNode("//ns:Setting[@Name='Infrastructure.WebRoot']",$ns).getAttribute("Value")
    $startStorageEmulatorNode=$xd.SelectSingleNode("//ns:Setting[@Name='Infrastructure.StartStorageEmulator']",$ns)
    $protocol=$xd.SelectSingleNode("//ns:Setting[@Name='Infrastructure.HttpProtocol']",$ns).getAttribute("Value")
    $deployReportsNode=$xd.SelectSingleNode("//ns:Setting[@Name='Deploy.DeployReports']",$ns)
    
    $startStorageEmulator="false"
    if($startStorageEmulatorNode -ne $null)
    {
        $startStorageEmulator=$startStorageEmulatorNode.getAttribute("Value")
    }
    
    $deployReports="true"
    if($deployReportsNode -ne $null)
    {
        $deployReports=$deployReportsNode.getAttribute("Value")
    }

    # get the name of the primary node
    $nodes=$ConfigData.AllNodes
    foreach($node in $nodes){
        if($node.Role -eq "Primary"){
            [string]$primarynodename=$node.NodeName
            Write-Log "The primary AOS node is $primarynodename"
            break;
        }
    }

    # create the configuration file
    Write-Header 
    Write-LCM-Configuration -configdata:$ConfigData
    Write-Certificate-Configuration
    Write-Dependency-Configuration
    Write-Firewall-Ports-Configuration
    Write-Perf-Counters-Configuration
    Write-DynamicsTools-Configuration
    Write-AosWebsite-Configuration
    Write-Packages-Configuration -deploydb:$deploydb
    if($startStorageEmulator -eq "true")
    {
        Write-Storage-Emulator-Configuration
    }

    Write-WebSite-Configuration
    Write-WebConfigFile-Configuration -servicemodel:$servicemodelxml
    Write-WifConfigFile-Configuration -servicemodel:$servicemodelxml
    Write-Aos-Http-Configuration -webroot:$webroot -protocol:$protocol

    $fqdn=[System.Net.Dns]::GetHostByName(($env:computerName))

    # on a work group machine the GetHostByName() returns the netbios name
    $netbiosname=$primarynodename.Split(".")[0]
   if($primarynodename -eq $fqdn.HostName -or $netbiosname -eq $fqdn.HostName -or $primarynodename -eq $env:computerName){
        Write-AosUser-Configuration

        #TODO: refactor this code so that it uses a separate flag to determine if the DBSync should be run or not
        if($startStorageEmulator -eq "false") # if emulator is not started, we are on a non onebox deployment and run DBSync
        {
            Write-DBSYNC-Configuration
        }
               
        Write-SymbolicLinkGeneration-Configuration -primarynode
    }else{
        Write-InterNode-Sync-Configuration -primarynode:$primarynodename
        Write-SymbolicLinkGeneration-Configuration
    }
    
    Write-NGen-Configuration
    Write-Resources-Configuration
    Write-BatchService-Configuration
    if($deployReports -ne "false")
    {
        Write-Reports-Configuration
    }
    Write-RetailPerfCounters-Configuration
    Write-ProductConfiguration
    Write-ConfigInstallationInfo-Configuration -servicemodel:$servicemodelxml
    Write-EncryptionConfiguration-Configuration -webroot:$webroot
    Write-Footer -outputpath:$outputpath
}

function Copy-CustomDSCResources([string]$grandparentDir)
{
    if(Test-Path "$grandparentDir\Scripts\xDynamics"){
        Write-Log "Copying the custom DSC resources"
        Copy-Item -Path "$grandparentDir\Scripts\xDynamics" -Destination "$env:ProgramFiles\WindowsPowerShell\Modules" -Force -Recurse -Verbose
        Get-ChildItem -Path "$env:ProgramFiles\WindowsPowerShell\Modules" -Recurse | Unblock-File -Verbose  
    }else{
        Write-Log "No custom DSC resources to copy"
    }
}

function Save-EncryptionCertificate-PublicKey($certificate)
{
    Write-Log "Saving the encryption cert public key to file..."
    $global:encryptioncertpublickeyfile=join-path $global:logdir "EncryptCert.cer"
    Export-Certificate -cert:$certificate -FilePath $global:encryptioncertpublickeyfile -Force -Type CERT | out-null
}

function Get-EncryptionCertificate-Thumbprint
{
    $subject="MicrosoftDynamicsAXDSCEncryptionCert"

    #get or create a new self-signed encryption certificate to secure sensitive info in the MOF files
    $cert=Get-Make-Encryption-Cert -subject:$subject
    Save-EncryptionCertificate-PublicKey -certificate:$cert
    $cert.Thumbprint
}

function Get-Make-Encryption-Cert([string]$subject)
{
    Write-Log "Checking if a self-signed encryption cert with subject '$subject' exists..."
    $formattersubject="CN=$subject"
    $cert=Get-ChildItem Cert:\LocalMachine\My|where {$_.Subject -eq $formattersubject}
    if($cert -ne $null) # if cert existed make sure it is valid
    {
        if(!(Is-ValidCert -certificate:$cert))
        {
            Write-Log "Dynamics DSC self-signed encryption cert is expired. Generating a new self-signed encryption certificate..."
            Write-Log "Deleting the invalid self-signed encryption certificate with subject '$cert.subject'... "
            $thumbprint=$cert.Thumbprint
            Remove-Item -Path Cert:\LocalMachine\My\$thumbprint -Force -DeleteKey |out-null
            $cert=Make-Certificate -subject:$subject
        }
    }
    else
    {
        $cert=Make-Certificate -subject:$subject 
    }

    $cert
}

function Is-ValidCert($certificate)
{
    $subject=$certificate.Subject
    Write-Log "Checking if the certificate '$subject' is valid..."
    $thumbprint=$certificate.Thumbprint
    $cert=Get-ChildItem -Path Cert:\LocalMachine\My\$thumbprint
    if($cert -ne $null)
    {
        if($cert.NotAfter -lt (Get-Date)) #expired
        {
            return $false
        }
        else
        {
            return $true
        }
    }

    #if cert is not found, return false
    return $false
}

function Make-Certificate([string]$subject)
{
     Write-Log "Creating a new DSC self-signed encryption certificate with subject '$subject'..."
     return New-SelfSignedCertificate -DnsName $subject -CertStoreLocation cert:\LocalMachine\My
}

#endregion

#region Main...
$parentdir=Split-Path -parent $PSCommandPath
$grandparentdir=Split-Path -parent $parentdir

$global:decodedservicemodelxml=[System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($servicemodelxml))
$global:logfile=$log
$global:logdir=[System.IO.Path]::GetDirectoryName($log)
$global:dscconfigfile=join-path $global:logdir "Install.ps1"
$outputpath=join-path $global:logdir "Install"

$etwpath=join-path $grandparentdir "ETWManifest"
$global:telemetrydll = join-path $etwpath "Microsoft.Dynamics.AX7Deployment.Instrumentation.dll"
$installationdll=Join-Path $parentdir "Microsoft.Dynamics.AX.AXInstallationInfo.dll"
$installationinfoxml=join-path $parentdir "InstallationInfo.xml"
$keyVaultModule=Join-Path -Path $PSScriptRoot -ChildPath "KeyVault.psm1"

[System.Xml.XmlDocument] $xd = new-object System.Xml.XmlDocument
$xd.LoadXml($global:decodedservicemodelxml)
$ns=New-Object System.Xml.XmlNamespaceManager($xd.NameTable)
$ns.AddNamespace("ns",$xd.DocumentElement.NamespaceURI)
$keyVaultName=$xd.SelectSingleNode("//ns:Setting[@Name='Infrastructure.AzureKeyVaultName']",$ns).getAttribute("Value")
$appId=$xd.SelectSingleNode("//ns:Setting[@Name='Infrastructure.AzureKeyVaultAppId']",$ns).getAttribute("Value")
$thumprint=$xd.SelectSingleNode("//ns:Setting[@Name='Infrastructure.AzureKeyVaultCertThumbprint']",$ns).getAttribute("Value")

Import-Module $keyVaultModule -ArgumentList ($keyVaultName, $appId, $thumprint)

if(-not (Test-Path $global:telemetrydll)){
    throw "The deployment telemetry assembly does not exist"
}

if(Test-Path $global:dscconfigfile){
    Remove-Item $global:dscconfigfile -Force
}

Initialize-Log -logdir:$global:logdir -logfile:$log
Copy-Files -targetdir:$global:logdir
Copy-CustomDSCResources -grandparentDir:$grandparentdir

Write-Log "Enabling WinRM remote management"
WinRM quickconfig -q

# construct the config data
[System.Xml.XmlDocument] $xd = new-object System.Xml.XmlDocument
$xd.LoadXml($global:decodedservicemodelxml)
$ns=New-Object System.Xml.XmlNamespaceManager($xd.NameTable)
$ns.AddNamespace("ns",$xd.DocumentElement.NamespaceURI)
[string]$nodes=$xd.SelectSingleNode("//ns:Setting[@Name='Deploy.AosNodes']",$ns).getAttribute("Value")

if($env:USERDOMAIN -eq $env:COMPUTERNAME){
    $global:domain="builtin"
}else{
    $global:domain=$env:USERDOMAIN
}

$global:username=$env:USERNAME

[string[]]$aosvms=$nodes.Split(",")

if($aosvms.Count -eq 0){
    throw "Atleast one AOS node should be defined in the servicemodel.xml"
}

$global:encryptioncertthumbprint=Get-EncryptionCertificate-Thumbprint

$configData=@{
    AllNodes=@(
        @{ NodeName="*";CertificateFile=$global:encryptioncertpublickeyfile;Thumbprint=$global:encryptioncertthumbprint;PSDscAllowDomainUser=$true;}
        @{ NodeName=$aosvms[0];Role="Primary" }
    )
}

for($i=1;$i -lt $aosvms.Count;$i++){
    $configData.AllNodes += @{NodeName=$aosvms[$i];Role="Secondary" }
}

CreateConfiguration -configData:$ConfigData
#endregion

#region generate MOF and execute the configuration
try
{
    Write-Log "Generating the MOF..."
    & $global:dscconfigfile

    Set-Location $outputpath

    Write-Log "Setting up LCM to decrypt credentials..."
    Set-DscLocalConfigurationManager -path "$outputpath" -Verbose *>&1 | Tee-Object $log

    Write-Log "Applying the configuration..."
    $errorsBeforeDSCConfig=$error.Count
    Start-DscConfiguration -wait -Verbose -path "$outputpath" -Force *>&1 | Tee-Object $log
    $errorsAfterDSCConfig=$error.Count

    $configstatuslog=join-path $global:logdir "aosservice-installation-status.log"
    $ConfigStatus = Get-DscConfigurationStatus
    $ConfigStatus | Format-List -Property * | Out-File -FilePath $configstatuslog -Force
    Write-Log "Error baseline: $errorsBeforeDSCConfig, Errors after DSCConfiguration: $errorsAfterDSCConfig"

    if($ConfigStatus.Status -ieq 'Success' -and $errorsBeforeDSCConfig -eq $errorsAfterDSCConfig)
    {
        return 0
    }
    else
    {
        throw "AOS service configuration did not complete, Message: $($ConfigStatus.StatusMessage), see log for details"
    }
}
catch
{
    throw $_
}

#endregion

# SIG # Begin signature block
# MIIkDAYJKoZIhvcNAQcCoIIj/TCCI/kCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCCsy4P9FeIB+qiU
# NMfn8j7+aeSVKQR6Fn/4dp6+dU+yIKCCDYIwggYAMIID6KADAgECAhMzAAAAww6b
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
# SEXAQsmbdlsKgEhr/Xmfwb1tbWrJUnMTDXpQzTGCFeAwghXcAgEBMIGVMH4xCzAJ
# BgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25k
# MR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xKDAmBgNVBAMTH01pY3Jv
# c29mdCBDb2RlIFNpZ25pbmcgUENBIDIwMTECEzMAAADDDpun2LLc9ywAAAAAAMMw
# DQYJYIZIAWUDBAIBBQCggdIwGQYJKoZIhvcNAQkDMQwGCisGAQQBgjcCAQQwHAYK
# KwYBBAGCNwIBCzEOMAwGCisGAQQBgjcCARUwLwYJKoZIhvcNAQkEMSIEIE17uDN3
# 7ZS1LRy1iVXRgOqcD/y26FguoDj/xn1kip8GMGYGCisGAQQBgjcCAQwxWDBWoDiA
# NgBBAG8AcwBTAGUAcgB2AGkAYwBlAEMAbwBuAGYAaQBnAHUAcgBhAHQAaQBvAG4A
# LgBwAHMAMaEagBhodHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20wDQYJKoZIhvcNAQEB
# BQAEggEAe/ygpHLCPRi3ef8OJr1vahs8HzzxDnJ/ArHiZ0mHssOaLdoB9HPmMe7C
# /HXetVbGAowzS148LdOkvBK3KkVl/oJ6I6G6zaJDIZxH+KE/wOW5jPePltkdxys1
# KpJ8kAt3ru5GR8JzJPaDRCAD+5wB5S2QNlvGXiqSF/zS6QKn5jnx107hITz5fgcG
# I3RzJHFJN84NAA5/QLHSA7TrUVA1W5A4RmwZBuHoRoS1eTJ6aYQQrEW46UkYkcXi
# LVt9TG+4Bs5J+YW+sxL6RbjU+iaus5C0lXAeMEkR1FVGGLeB0dGi5LoQcFRBwWGm
# IvJXfM5tC8XDALstVot9WqIDuGSAx6GCE0YwghNCBgorBgEEAYI3AwMBMYITMjCC
# Ey4GCSqGSIb3DQEHAqCCEx8wghMbAgEDMQ8wDQYJYIZIAWUDBAIBBQAwggE8Bgsq
# hkiG9w0BCRABBKCCASsEggEnMIIBIwIBAQYKKwYBBAGEWQoDATAxMA0GCWCGSAFl
# AwQCAQUABCAnOEHgPWZ2Gxxy+Xb51t73yu0MJSQf1prvjAa3ITZAxgIGWrKbaunX
# GBMyMDE4MDMyNTIxMDU1My41NTdaMAcCAQGAAgH0oIG4pIG1MIGyMQswCQYDVQQG
# EwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwG
# A1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMQwwCgYDVQQLEwNBT0MxJzAlBgNV
# BAsTHm5DaXBoZXIgRFNFIEVTTjo3QUI1LTJERjItREEzRjElMCMGA1UEAxMcTWlj
# cm9zb2Z0IFRpbWUtU3RhbXAgU2VydmljZaCCDsowggZxMIIEWaADAgECAgphCYEq
# AAAAAAACMA0GCSqGSIb3DQEBCwUAMIGIMQswCQYDVQQGEwJVUzETMBEGA1UECBMK
# V2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0
# IENvcnBvcmF0aW9uMTIwMAYDVQQDEylNaWNyb3NvZnQgUm9vdCBDZXJ0aWZpY2F0
# ZSBBdXRob3JpdHkgMjAxMDAeFw0xMDA3MDEyMTM2NTVaFw0yNTA3MDEyMTQ2NTVa
# MHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdS
# ZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xJjAkBgNVBAMT
# HU1pY3Jvc29mdCBUaW1lLVN0YW1wIFBDQSAyMDEwMIIBIjANBgkqhkiG9w0BAQEF
# AAOCAQ8AMIIBCgKCAQEAqR0NvHcRijog7PwTl/X6f2mUa3RUENWlCgCChfvtfGhL
# LF/Fw+Vhwna3PmYrW/AVUycEMR9BGxqVHc4JE458YTBZsTBED/FgiIRUQwzXTbg4
# CLNC3ZOs1nMwVyaCo0UN0Or1R4HNvyRgMlhgRvJYR4YyhB50YWeRX4FUsc+TTJLB
# xKZd0WETbijGGvmGgLvfYfxGwScdJGcSchohiq9LZIlQYrFd/XcfPfBXday9ikJN
# QFHRD5wGPmd/9WbAA5ZEfu/QS/1u5ZrKsajyeioKMfDaTgaRtogINeh4HLDpmc08
# 5y9Euqf03GS9pAHBIAmTeM38vMDJRF1eFpwBBU8iTQIDAQABo4IB5jCCAeIwEAYJ
# KwYBBAGCNxUBBAMCAQAwHQYDVR0OBBYEFNVjOlyKMZDzQ3t8RhvFM2hahW1VMBkG
# CSsGAQQBgjcUAgQMHgoAUwB1AGIAQwBBMAsGA1UdDwQEAwIBhjAPBgNVHRMBAf8E
# BTADAQH/MB8GA1UdIwQYMBaAFNX2VsuP6KJcYmjRPZSQW9fOmhjEMFYGA1UdHwRP
# ME0wS6BJoEeGRWh0dHA6Ly9jcmwubWljcm9zb2Z0LmNvbS9wa2kvY3JsL3Byb2R1
# Y3RzL01pY1Jvb0NlckF1dF8yMDEwLTA2LTIzLmNybDBaBggrBgEFBQcBAQROMEww
# SgYIKwYBBQUHMAKGPmh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2kvY2VydHMv
# TWljUm9vQ2VyQXV0XzIwMTAtMDYtMjMuY3J0MIGgBgNVHSABAf8EgZUwgZIwgY8G
# CSsGAQQBgjcuAzCBgTA9BggrBgEFBQcCARYxaHR0cDovL3d3dy5taWNyb3NvZnQu
# Y29tL1BLSS9kb2NzL0NQUy9kZWZhdWx0Lmh0bTBABggrBgEFBQcCAjA0HjIgHQBM
# AGUAZwBhAGwAXwBQAG8AbABpAGMAeQBfAFMAdABhAHQAZQBtAGUAbgB0AC4gHTAN
# BgkqhkiG9w0BAQsFAAOCAgEAB+aIUQ3ixuCYP4FxAz2do6Ehb7Prpsz1Mb7PBeKp
# /vpXbRkws8LFZslq3/Xn8Hi9x6ieJeP5vO1rVFcIK1GCRBL7uVOMzPRgEop2zEBA
# QZvcXBf/XPleFzWYJFZLdO9CEMivv3/Gf/I3fVo/HPKZeUqRUgCvOA8X9S95gWXZ
# qbVr5MfO9sp6AG9LMEQkIjzP7QOllo9ZKby2/QThcJ8ySif9Va8v/rbljjO7Yl+a
# 21dA6fHOmWaQjP9qYn/dxUoLkSbiOewZSnFjnXshbcOco6I8+n99lmqQeKZt0uGc
# +R38ONiU9MalCpaGpL2eGq4EQoO4tYCbIjggtSXlZOz39L9+Y1klD3ouOVd2onGq
# BooPiRa6YacRy5rYDkeagMXQzafQ732D8OE7cQnfXXSYIghh2rBQHm+98eEA3+cx
# B6STOvdlR3jo+KhIq/fecn5ha293qYHLpwmsObvsxsvYgrRyzR30uIUBHoD7G4kq
# VDmyW9rIDVWZeodzOwjmmC3qjeAzLhIp9cAvVCch98isTtoouLGp25ayp0Kiyc8Z
# QU3ghvkqmqMRZjDTu3QyS99je/WZii8bxyGvWbWu3EQ8l1Bx16HSxVXjad5XwdHe
# MMD9zOZN+w2/XU/pnR4ZOC+8z1gFLu8NoFA12u8JJxzVs341Hgi62jbb01+P3nSI
# SRIwggTZMIIDwaADAgECAhMzAAAAq15Ane5G3yxsAAAAAACrMA0GCSqGSIb3DQEB
# CwUAMHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQH
# EwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xJjAkBgNV
# BAMTHU1pY3Jvc29mdCBUaW1lLVN0YW1wIFBDQSAyMDEwMB4XDTE2MDkwNzE3NTY1
# NFoXDTE4MDkwNzE3NTY1NFowgbIxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNo
# aW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29y
# cG9yYXRpb24xDDAKBgNVBAsTA0FPQzEnMCUGA1UECxMebkNpcGhlciBEU0UgRVNO
# OjdBQjUtMkRGMi1EQTNGMSUwIwYDVQQDExxNaWNyb3NvZnQgVGltZS1TdGFtcCBT
# ZXJ2aWNlMIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAs+Z+UJigRgmw
# ZgEmijTTKcl9mDWaDCzdM8oDzw4C1wvvu+HILkmk09DZ3HPTu0WFnF3lAfX8K6Zi
# m+GAAqfzNyhFSzXeuLpu+4aQ7eGrEPI48HfCW89AE+45ShvSKnoe/IsB+Km8mo95
# A8PjcNGsAPOmwMsh3XTU1IeEKIGtGllSYt7s/czFA4lMTQezoNQennsBwjrNY2kJ
# kIgTk8MtlKEsBCm4N9VKtTGK5L5ukTPbfO7MMnxcwS3huLDWIokhKiR54uSjzy4Z
# 1lXJSBEkpKjJ9UjIUsIxkpD6ZjYA+aEwGmgPrWlkS1rx62mfc4Z6tmAflJFejiC9
# 1N8OKpDISwIDAQABo4IBGzCCARcwHQYDVR0OBBYEFA3HR9AcYMvpwGuUzF8GDmK4
# 2GqnMB8GA1UdIwQYMBaAFNVjOlyKMZDzQ3t8RhvFM2hahW1VMFYGA1UdHwRPME0w
# S6BJoEeGRWh0dHA6Ly9jcmwubWljcm9zb2Z0LmNvbS9wa2kvY3JsL3Byb2R1Y3Rz
# L01pY1RpbVN0YVBDQV8yMDEwLTA3LTAxLmNybDBaBggrBgEFBQcBAQROMEwwSgYI
# KwYBBQUHMAKGPmh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2kvY2VydHMvTWlj
# VGltU3RhUENBXzIwMTAtMDctMDEuY3J0MAwGA1UdEwEB/wQCMAAwEwYDVR0lBAww
# CgYIKwYBBQUHAwgwDQYJKoZIhvcNAQELBQADggEBAD+f/rouYfFyKq2qFWaVoARL
# fbPCRt3Q61tAPPSMdQWtoYFvJHsNLtKjibrwNiv5yMV3Dnq4fN5U4v0PJl88DHYt
# +hjRohCoiF5LKlmVyF93f/5EJLgCmYSRlK8Cx6YqhoSxi/iRJMfQbqM2v/v4uAea
# bz5p7bbxm2FnVK026Nvy2uVipjvIbcxDmiYi80SM6y1HJnXTwuab1oqdFU+T6IAg
# zg4tlQNT80DgGtxpXEwh10oTKC9F1YL9pMHfITvJ6z84pT8y+s0GS7gfvJsas5Gx
# k13i/3mhFtG4Nfbhkcr3cez9/orD4GU1WMukXg+W5qcir2jzPs/epI2q2O4SpOKh
# ggN0MIICXAIBATCB4qGBuKSBtTCBsjELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldh
# c2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBD
# b3Jwb3JhdGlvbjEMMAoGA1UECxMDQU9DMScwJQYDVQQLEx5uQ2lwaGVyIERTRSBF
# U046N0FCNS0yREYyLURBM0YxJTAjBgNVBAMTHE1pY3Jvc29mdCBUaW1lLVN0YW1w
# IFNlcnZpY2WiJQoBATAJBgUrDgMCGgUAAxUAyey7SC012ZS+to73JqkxboqHjjKg
# gcEwgb6kgbswgbgxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAw
# DgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24x
# DDAKBgNVBAsTA0FPQzEnMCUGA1UECxMebkNpcGhlciBOVFMgRVNOOjI2NjUtNEMz
# Ri1DNURFMSswKQYDVQQDEyJNaWNyb3NvZnQgVGltZSBTb3VyY2UgTWFzdGVyIENs
# b2NrMA0GCSqGSIb3DQEBBQUAAgUA3mHqvTAiGA8yMDE4MDMyNTA5MzAzN1oYDzIw
# MTgwMzI2MDkzMDM3WjB0MDoGCisGAQQBhFkKBAExLDAqMAoCBQDeYeq9AgEAMAcC
# AQACAiXFMAcCAQACAhouMAoCBQDeYzw9AgEAMDYGCisGAQQBhFkKBAIxKDAmMAwG
# CisGAQQBhFkKAwGgCjAIAgEAAgMW42ChCjAIAgEAAgMHoSAwDQYJKoZIhvcNAQEF
# BQADggEBAH5aL0yKj8iqkMLhqYxCGQy35PUXyglz4Cz/uAnNu+kuxGTqoT7xQ8sv
# 5nTgkG2mGGXTbu5TX3+DMIuNyUGBCF7zllXt6ZqEs0XkPDTHhaEaAbErQ0RJKDHF
# RlJMuoN5Od7iH1B4gI/gucCmZbooyaD7xTJfBeEmyBDoj5DLtCk3qtrlj8/QNscy
# 9xdCC2I0MVnxH/oLjebSImREcFC3TiV/6+cBzkXU9xgjZYapk/ifMfCXncJNEiGY
# tUMTZyAATUdfAcKY6XegICydsEyyZxc0qqyw0vodcKTOI+LgjZeXbPT4sgA/UBa/
# g8+wdZo3jKfyGXjGQ2T3Z1dhguKDKCwxggL1MIIC8QIBATCBkzB8MQswCQYDVQQG
# EwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwG
# A1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQg
# VGltZS1TdGFtcCBQQ0EgMjAxMAITMwAAAKteQJ3uRt8sbAAAAAAAqzANBglghkgB
# ZQMEAgEFAKCCATIwGgYJKoZIhvcNAQkDMQ0GCyqGSIb3DQEJEAEEMC8GCSqGSIb3
# DQEJBDEiBCAZ9NA5lyoycUxW6/xo2h4EkmkJMex7hwAEGI+GA4icPzCB4gYLKoZI
# hvcNAQkQAgwxgdIwgc8wgcwwgbEEFMnsu0gtNdmUvraO9yapMW6Kh44yMIGYMIGA
# pH4wfDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcT
# B1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEmMCQGA1UE
# AxMdTWljcm9zb2Z0IFRpbWUtU3RhbXAgUENBIDIwMTACEzMAAACrXkCd7kbfLGwA
# AAAAAKswFgQU9EZ8rGhsBOqvgJDjVqYWE6bwxjkwDQYJKoZIhvcNAQELBQAEggEA
# InYcfxDbyc+AY0lJrQS0hMvuxvXglVlqtu35dMMoUnZz0yfZQ1VaT5JiMDMF0gTR
# xs8q4yd/f9PEuOy1bd5zq6wbGXdL9NniPaJIxL/rT52T109JdOLAwCAYY0mYuzRc
# PxMnvoaBv/fzjon+Op6dePU06vpjHUj3VB1kQlNOG1dtJXIhMzsBwj0rjHq5zWI/
# gaKHgp+yezrvUJpfSUiAc9FPYPjrTrCMU75CjlUabEiGJaxQSfvrCVYY0EsDJq54
# wKuxeEz18y5cYboC9AY2KjNkDH2+2fHkImMAnyEWw3d0BWpE5QAGsVJGezwTS4uh
# CE5dMWLj2fJRWSTCJDkRGw==
# SIG # End signature block
