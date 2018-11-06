[CmdletBinding()]
param
(
    [Parameter(Mandatory=$true)]
    [string]$ServiceModelXml,

    [Parameter(Mandatory=$true)]
    [string]$log,

    [Parameter(Mandatory=$false)]
    [string]$config
)

Import-Module WebAdministration

#region configuration generators
function Write-Storage-Emulator-Configuration([string]$logDir)
{
    $registrykey="HKLM:\SOFTWARE\Wow6432Node\Microsoft\Windows Azure Storage Emulator\"
    $registrykeyvaluename="InstallPath"
    $emulatorInstallPath=Get-RegistryKeyValue -registryKey:$registrykey -registryKeyValueName:$registrykeyvaluename
    if([string]::IsNullOrEmpty($emulatorInstallPath)){
        Write-Log "Skipping Azure sdk configuration as the Azure emulator is not installed."
        break
    }

    $azurestorageemulator= join-path $emulatorInstallPath "azurestorageemulator.exe"

    $standardout=join-path $global:logdir "azurestorageemulator.stopprocess.output"
    $standarderr=join-path $global:logdir "azurestorageemulator.stopprocess.error"
    $script="`
    WindowsProcess StopEmulatorProcesses `
    { `
        Ensure=`"Absent`" `
        Arguments=`"start /inprocess`" `
        Path=`"$azurestorageemulator`" `
        DependsOn=@() `
    }"

    Write-Log "Creating the configuration to stop any storage emulator process(es)"
    Write-Content $script

    $script = @"
    DynamicsScheduledTask StartAzureStorageEmulator_ScheduledTask
    {
        TaskName = "DynamicsStartAzureStorageEmulator"
        Ensure = "Absent"
    }
"@
    Write-Content $script

}

function Write-Miscellaneous-Processes-Configuration([string]$webroot,[string]$logDir)
{
    $binarypathname=join-path $webroot "bin\Microsoft.Dynamics.AX.Deployment.Setup.exe"
    $standardoutdir=join-path $logDir "Microsoft.Dynamics.AX.Deployment.Setup.exe.output"
    $standarderrdir=join-path $logDir "Microsoft.Dynamics.AX.Deployment.Setup.exe.error"

    $script="`
    DynamicsProcess StopDeploymentSetupProcess `
    { `
        Ensure=`"Absent`" `
        Arguments=`"`" `
        File=`"$binarypathname`" `
        StandardErrorPath=`"$standardoutdir`" `
        StandardOutputPath=`"$standarderrdir`" `
        DependsOn=@(`"[WindowsProcess]StopEmulatorProcesses`") `
        MonitoringAssembly=`"$global:telemetrydll`" `
    } "

    Write-Log "Creating the configuration to stop the deployment setup process"
    Write-Content $script
}

function Write-BatchService-Configuration([string]$webroot,[string]$logDir)
{
    $webconfig= join-path $webroot "web.config"
    $binarypathname=join-path $webroot "bin\Batch.exe"
    $standardout=join-path $logDir "batch.exe.output"
    $standarderr=join-path $logDir "batch.exe.error"
    $deleteBatchServiceDependency=""
    if(Test-Path $binarypathname){
        $script="`
        WindowsProcess StopBatchProcess `
        { `
            Ensure=`"Absent`" `
            Arguments='-service $webconfig' `
            Path=`"$binarypathname`" `
        } "

        Write-Log "Creating the configuration to stop the Dynamics AX Batch process"
        Write-Content $script
        $deleteBatchServiceDependency="`"[WindowsProcess]StopBatchProcess`""
    }
    
    $servicepath=join-path $webroot "bin\Batch.exe -service $webconfig"
    $script = "`
    Service DeleteBatchService `
    { `
        Ensure=`"Absent`" `
        Name=`"DynamicsAxBatch`" `
        State=`"Stopped`" `
        DisplayName=`"Dynamics AX Batch Management`" `
        Path='$servicepath' `
        DependsOn=@($deleteBatchServiceDependency) `
    }"

    Write-Log "Creating the configuration to delete the Dynamics AX Batch service"
    Write-Content $script

    $script = @"
    DynamicsScheduledTask StartBatch_ScheduledTask
    {
        TaskName = "DynamicsStartBatch"
        Ensure = "Absent"
    }
"@
    Write-Content $script
}

function Write-WebSite-Configuration([string]$websitename,[string]$webroot,[string]$apppoolname)
{
    $source=$env:TEMP
    $script="`
    xWebSite DeleteAosWebSite `
    { `
        Ensure=`"Absent`" `
        Name=`"$websiteName`" `
        PhysicalPath=`"$webRoot`" `
        State=`"Stopped`" `
    }"

    Write-Log "Creating the configuration to delete the AOS web site"
    Write-Content $script

    if(![string]::IsNullOrEmpty($apppoolname)){
         # delete the aos apppool if it exists
        $script="`
        xWebAppPool DeleteAosAppPool `
        { `
            Ensure=`"Absent`" `
            State=`"Stopped`" `
            Name=`"$apppoolname`" `
            DependsOn=@(`"[xWebSite]DeleteAosWebSite`") `
        }"

        Write-Log "Creating the configuration to delete the AOS web app pool"
        Write-Content $script
    }

    $script= @"
    xWebAppPool DeleteProductConfigurationAppPool
    {
        Ensure="Absent"
        State="Stopped"
        Name="ProductConfiguration"
        DependsOn=@("[xWebSite]DeleteAosWebSite")
    }
"@
    Write-Log "Creating the configuration to delete the product configuration web app pool"
    Write-Content $script

    $script = "
    File DeleteWebSitePhysicalPath`
    { `
        Ensure=`"Absent`" `
        DestinationPath=`"$webRoot`" `
        Recurse=`$true `
        SourcePath=`"`" `
        Type=`"Directory`" `
        DependsOn=@(`"[xWebSite]DeleteAosWebSite`", `"[Service]DeleteBatchService`") `
        Force=`$true `
    }"

     Write-Log "Creating the configuration to delete the AOS web site files"
     Write-Content $script
    
}

function Write-Packages-Configuration([string]$packagedir)
{
    $script = "
    File DeletePackages`
    { `
        Ensure=`"Absent`" `
        DestinationPath=`"$packageDir`" `
        Recurse=`$true `
        SourcePath=`"`" `
        Type=`"Directory`" `
        Force=`$true `
        DependsOn=@(`"[xWebSite]DeleteAosWebSite`") `
    }"

    Write-Log "Creating the configuration to delete the Dynamics packages"
    Write-Content $script
}

function Write-Database-Configuration([string]$dbName,[string]$dbServer,[string]$dbUser,[string]$dbPwd,[string]$logDir)
{
    # for dropping the db, use the temp folder name as the package dir as it is not used
    $packageDir=$env:TEMP

    $script="`
    DynamicsDatabase DropDatabase `
    { `
        Ensure=`"Absent`" `
        PackageDirectory=`"$packageDir`" `
        DatabaseName=`"$dbName`" `
        DatabaseServer=`"$dbServer`" `
        UserName=`"$dbUser`" `
        Password=`"$dbPwd`" `
        DependsOn=@(`"[File]DeletePackages`") `
        MonitoringAssembly=`"$global:telemetrydll`" `
    }"

    Write-Log "Creating the configuration to drop the AX database"
    Write-Content $script
}

function Write-LCM-Configuration($thumbprint)
{
    Write-Verbose "Creating the LCM configuration to set the encryption certificate thumbprint..."
    $script="`
    LocalConfigurationManager 
    {
        CertificateId=`"$thumbprint`"
    }"
    
    write-content $script
}
#endregion

#region helper functions
function Initialize-Log([string]$logdir,[string]$logfile)
{
    if(-not (Test-Path $logdir)){
        New-Item -ItemType Directory -Path $logdir
    }
    
    if(Test-Path $logfile){
        Remove-Item $logfile -Force
    }

    New-item $logfile -ItemType File -Force
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
# This file will be compiled to generate a Windows DSC configuration that will remove 
# the Dynamics AOS service on this machine.
###

#region service configuration
Configuration RemoveAosServiceConfiguration { `
`
Import-DscResource -Module xWebAdministration `
Import-DscResource -Module xDynamics `
Import-DscResource -Module PSDesiredStateConfiguration `

Node `"localhost`"{"

    Write-Content $header
}

function Write-Footer([string]$outputpath)
{
    $footer="}`
    } `

`$configData=@{
    AllNodes=@(
        @{NodeName=`"localhost`";CertificateFile=`"$global:encryptioncertpublickeyfile`";Thumbprint=`"$global:encryptioncertthumbprint`";PSDscAllowDomainUser=`$true; }
    )
}`

#endregion

# generate the MOF file `    
RemoveAosServiceConfiguration -OutputPath:$outputpath -ConfigurationData:`$configData"

    Write-Content $footer
}

function Write-Content([string]$content)
{
   Add-Content $global:dscconfigfile -Value $content
}

function Get-RegistryKeyValue([string]$registryKey,[string]$registryKeyValueName,[string]$defaultValue=[string]::Empty)
{
    $value=(Get-ItemProperty "$registryKey").$registryKeyValueName
    if([string]::IsNullOrEmpty($value)){
        return $defaultValue
    }

    return $value
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
    Export-Certificate -cert:$certificate -FilePath $global:encryptioncertpublickeyfile -Force -Type CERT | Out-Null
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

function Output-CurrentEnvironmentState([string]$websitePath, [string]$packagePath)
{
    $handleExePath=join-path $env:SystemDrive "SysInternals\Handle.exe"
    $openHandlesLog=join-path $global:logDir "aosservice-uninstallation-openhandles.log"
    if(-not (Test-Path $handleExePath))
    {
        return
    }
    
    #dump any handles to files in the website directory
    if(Test-Path $websitePath)
    {
        Write-Log "AOS WebRoot still exists at $websitePath. Dumping open handles to $openHandlesLog..."
        & "$handleExePath" -AcceptEula $websitePath | Out-File $openHandlesLog -Append
    }
    
    #dump any handles to files in the package directory
    if(Test-Path $packagePath)
    {
        Write-Log "AOS packages directory still exists at $packagePath. Dumping open handles to $openHandlesLog..."
        & "$handleExePath" -AcceptEula $packagePath | Out-File $openHandlesLog -Append
    }
}

#endregion

#region Main
$parentdir=Split-Path -parent $PSCommandPath
$grandparentdir=Split-Path -parent $parentdir
$global:logfile=$log
$global:logdir=[System.IO.Path]::GetDirectoryName($log)

Initialize-Log -logdir:$global:logdir -logfile:$log
Copy-CustomDSCResources -grandparentDir:$grandparentdir

$global:decodedservicemodelxml=[System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($servicemodelxml))

$global:dscconfigfile=join-path $global:logdir "Uninstall.ps1"

if(Test-Path $global:dscconfigfile){
    Remove-Item $global:dscconfigfile -Force
}

$outputpath=join-path $global:logdir "Uninstall"
$etwpath=join-path $grandparentdir "ETWManifest"
$global:telemetrydll = join-path $etwpath "Microsoft.Dynamics.AX7Deployment.Instrumentation.dll"

if(-not (Test-Path $global:telemetrydll)){
    throw "The deployment telemetry assembly does not exist"
}

[System.Xml.XmlDocument] $xd = new-object System.Xml.XmlDocument
$xd.LoadXml($global:decodedservicemodelxml)
$ns=New-Object System.Xml.XmlNamespaceManager($xd.NameTable)
$ns.AddNamespace("ns",$xd.DocumentElement.NamespaceURI)

if($env:USERDOMAIN -eq $env:COMPUTERNAME){
    $global:domain="builtin"
}else{
    $global:domain=$env:USERDOMAIN
}

$global:username=$env:USERNAME

$global:encryptioncertthumbprint=Get-EncryptionCertificate-Thumbprint

[string]$websiteName=$xd.SelectSingleNode("//ns:ServiceModel",$ns).getAttribute("Name")
[string]$webRoot=$xd.SelectSingleNode("//ns:Setting[@Name='Infrastructure.WebRoot']",$ns).getAttribute("Value")
Write-Log "The web root is $webRoot"
[string]$packageDir=$xd.SelectSingleNode("//ns:WorkingFolder[@Name='PackagesLocalDirectory']",$ns).getAttribute("Directory")
Write-Log "The package directory is $packageDir"

$website=Get-Website $websiteName
if($website -ne $null)
{
    $apppool=$website.applicationPool
}

$uninstallAttempt=1
while($uninstallAttempt -le 3 -and !$success)
{
    if($uninstallAttempt -gt 1)
    {
        $retryAttempt=$uninstallAttempt-1
        Write-Log "Retry attempt $retryAttempt`: Retrying AOS service uninstallation..."
    }

    # create the configuration file
    Write-Header 
    Write-LCM-Configuration -thumbprint:$global:encryptioncertthumbprint
    Write-Storage-Emulator-Configuration -logDir:$log
    Write-Miscellaneous-Processes-Configuration -webroot:$webroot -logDir:$log
    Write-BatchService-Configuration -webroot:$webroot -logDir:$log
    Write-WebSite-Configuration -websitename:$websiteName -webroot:$webroot -apppoolname:$apppool
    Write-Packages-Configuration -packagedir:$packageDir

    Write-Footer -outputpath:$outputpath
    #endregion

    #region execute the configuration
    Write-Log "Executing the configuration.."
    & $global:dscconfigfile
    [bool]$success=$false
    $dscConfigApplied = $false
    try
    {
        $dscConfigApplied = $false
        Set-Location $outputpath
        Write-Log ("PSModulePath is currently: "+$env:PSModulePath)

        Write-Log "Setting up LCM to decrypt credentials..."
        Set-DscLocalConfigurationManager -path "$outputpath" -Verbose *>&1 | Tee-Object $log
        
        try
        {
            Write-Log("Dumping available DSC resources before applying the configuration...")
            $availableDSCResourceLog=join-path $global:logdir "aosservice-uninstallation-availabledscresources.log"
            Get-DSCResource -Name * | Format-List | Out-File -FilePath $availableDSCResourceLog
        }
        catch
        {
            Write-Log "Failed to get DSC resources, Error: $_"
        }
        
        Write-Log "Applying the configuration..."
        Start-DscConfiguration -wait -Verbose -path "$outputpath" -Force *>&1 | Tee-Object $log
        $dscConfigApplied = $true
    }
    catch
    {
        Write-Log "Uninstall attempt $uninstallAttempt`: Error: $_"
    }

    $configstatuslog=join-path $global:logdir "aosservice-uninstallation-status.log"
    $ConfigStatus = Get-DscConfigurationStatus
    $ConfigStatus | Format-List -Property * | Out-File -FilePath $configstatuslog -Force
    if($ConfigStatus.Status -ieq 'Success' -and $dscConfigApplied -eq $true)
    {
        $success=$true
    }
    else
    {
        Output-CurrentEnvironmentState $webRoot $packageDir
        Move-Item $global:dscconfigfile (join-path $global:logdir "Uninstall_Attempt_$uninstallAttempt.ps1")
        $uninstallAttempt++
    }
}

if($success)
{
    Write-Log "Configuration applied."
    return 0
}
else
{
    throw "AOS uninstallation did not complete after 3 retries, Message: $($ConfigJob.StatusMessage), see log for details."    
}

#endregion

# SIG # Begin signature block
# MIIj8AYJKoZIhvcNAQcCoIIj4TCCI90CAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCAfYjrp8MucsvnP
# mhosShlB1xRhnlNlyhBUqLPqcZEgqKCCDYIwggYAMIID6KADAgECAhMzAAAAww6b
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
# SEXAQsmbdlsKgEhr/Xmfwb1tbWrJUnMTDXpQzTGCFcQwghXAAgEBMIGVMH4xCzAJ
# BgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25k
# MR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xKDAmBgNVBAMTH01pY3Jv
# c29mdCBDb2RlIFNpZ25pbmcgUENBIDIwMTECEzMAAADDDpun2LLc9ywAAAAAAMMw
# DQYJYIZIAWUDBAIBBQCggbYwGQYJKoZIhvcNAQkDMQwGCisGAQQBgjcCAQQwHAYK
# KwYBBAGCNwIBCzEOMAwGCisGAQQBgjcCARUwLwYJKoZIhvcNAQkEMSIEIIOzsGos
# ZDORA82nz0Aoml8K1eloH/adjSDrLGNtPzK/MEoGCisGAQQBgjcCAQwxPDA6oByA
# GgBVAG4AaQBuAHMAdABhAGwAbAAuAHAAcwAxoRqAGGh0dHA6Ly93d3cubWljcm9z
# b2Z0LmNvbTANBgkqhkiG9w0BAQEFAASCAQCXkUHxAS027s/tkeu8R4Tc2P2SRr/x
# hunOdhKqTEPYoLhiPEAbP9AtLTzw5fEdkFTg4Ov8AAUTdu5jPUAgF0/JEJWD3WXS
# 0i86AB/rOIj+8dnrVCj3Rcv6T430TIH04vHwfPOy90RXloJf3a6MQbrp9sAovkpu
# 4muN9Ek2josrlm2CSkGMxb/ItokcrkK22Ch2w7Dt9xsvNoP6wdxB4dqVgSeuQgPV
# HAzOMIsQ+Ds/T+VpUC67drbSON7E8c7czf6WxaV7pHGAkkTlI9D1Nxi9G7zEs4oo
# AD8Y0k+iAK+FG0k5ErD2e7SaVVBpD831Y5KO0xjqEXngpM4RvQCNEVuAoYITRjCC
# E0IGCisGAQQBgjcDAwExghMyMIITLgYJKoZIhvcNAQcCoIITHzCCExsCAQMxDzAN
# BglghkgBZQMEAgEFADCCATwGCyqGSIb3DQEJEAEEoIIBKwSCAScwggEjAgEBBgor
# BgEEAYRZCgMBMDEwDQYJYIZIAWUDBAIBBQAEIMSJnglfDcs2CapsRuoMPz/BcpL/
# 3Fo6qRHNhw1DhG+3AgZasnRJxx8YEzIwMTgwMzI1MjEwNTU3Ljc2OVowBwIBAYAC
# AfSggbikgbUwgbIxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAw
# DgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24x
# DDAKBgNVBAsTA0FPQzEnMCUGA1UECxMebkNpcGhlciBEU0UgRVNOOkY2RkYtMkRB
# Ny1CQjc1MSUwIwYDVQQDExxNaWNyb3NvZnQgVGltZS1TdGFtcCBTZXJ2aWNloIIO
# yjCCBnEwggRZoAMCAQICCmEJgSoAAAAAAAIwDQYJKoZIhvcNAQELBQAwgYgxCzAJ
# BgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25k
# MR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xMjAwBgNVBAMTKU1pY3Jv
# c29mdCBSb290IENlcnRpZmljYXRlIEF1dGhvcml0eSAyMDEwMB4XDTEwMDcwMTIx
# MzY1NVoXDTI1MDcwMTIxNDY1NVowfDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldh
# c2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBD
# b3Jwb3JhdGlvbjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRpbWUtU3RhbXAgUENBIDIw
# MTAwggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIBAQCpHQ28dxGKOiDs/BOX
# 9fp/aZRrdFQQ1aUKAIKF++18aEssX8XD5WHCdrc+Zitb8BVTJwQxH0EbGpUdzgkT
# jnxhMFmxMEQP8WCIhFRDDNdNuDgIs0Ldk6zWczBXJoKjRQ3Q6vVHgc2/JGAyWGBG
# 8lhHhjKEHnRhZ5FfgVSxz5NMksHEpl3RYRNuKMYa+YaAu99h/EbBJx0kZxJyGiGK
# r0tkiVBisV39dx898Fd1rL2KQk1AUdEPnAY+Z3/1ZsADlkR+79BL/W7lmsqxqPJ6
# Kgox8NpOBpG2iAg16HgcsOmZzTznL0S6p/TcZL2kAcEgCZN4zfy8wMlEXV4WnAEF
# TyJNAgMBAAGjggHmMIIB4jAQBgkrBgEEAYI3FQEEAwIBADAdBgNVHQ4EFgQU1WM6
# XIoxkPNDe3xGG8UzaFqFbVUwGQYJKwYBBAGCNxQCBAweCgBTAHUAYgBDAEEwCwYD
# VR0PBAQDAgGGMA8GA1UdEwEB/wQFMAMBAf8wHwYDVR0jBBgwFoAU1fZWy4/oolxi
# aNE9lJBb186aGMQwVgYDVR0fBE8wTTBLoEmgR4ZFaHR0cDovL2NybC5taWNyb3Nv
# ZnQuY29tL3BraS9jcmwvcHJvZHVjdHMvTWljUm9vQ2VyQXV0XzIwMTAtMDYtMjMu
# Y3JsMFoGCCsGAQUFBwEBBE4wTDBKBggrBgEFBQcwAoY+aHR0cDovL3d3dy5taWNy
# b3NvZnQuY29tL3BraS9jZXJ0cy9NaWNSb29DZXJBdXRfMjAxMC0wNi0yMy5jcnQw
# gaAGA1UdIAEB/wSBlTCBkjCBjwYJKwYBBAGCNy4DMIGBMD0GCCsGAQUFBwIBFjFo
# dHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20vUEtJL2RvY3MvQ1BTL2RlZmF1bHQuaHRt
# MEAGCCsGAQUFBwICMDQeMiAdAEwAZQBnAGEAbABfAFAAbwBsAGkAYwB5AF8AUwB0
# AGEAdABlAG0AZQBuAHQALiAdMA0GCSqGSIb3DQEBCwUAA4ICAQAH5ohRDeLG4Jg/
# gXEDPZ2joSFvs+umzPUxvs8F4qn++ldtGTCzwsVmyWrf9efweL3HqJ4l4/m87WtU
# VwgrUYJEEvu5U4zM9GASinbMQEBBm9xcF/9c+V4XNZgkVkt070IQyK+/f8Z/8jd9
# Wj8c8pl5SpFSAK84Dxf1L3mBZdmptWvkx872ynoAb0swRCQiPM/tA6WWj1kpvLb9
# BOFwnzJKJ/1Vry/+tuWOM7tiX5rbV0Dp8c6ZZpCM/2pif93FSguRJuI57BlKcWOd
# eyFtw5yjojz6f32WapB4pm3S4Zz5Hfw42JT0xqUKloakvZ4argRCg7i1gJsiOCC1
# JeVk7Pf0v35jWSUPei45V3aicaoGig+JFrphpxHLmtgOR5qAxdDNp9DvfYPw4Ttx
# Cd9ddJgiCGHasFAeb73x4QDf5zEHpJM692VHeOj4qEir995yfmFrb3epgcunCaw5
# u+zGy9iCtHLNHfS4hQEegPsbiSpUObJb2sgNVZl6h3M7COaYLeqN4DMuEin1wC9U
# JyH3yKxO2ii4sanblrKnQqLJzxlBTeCG+SqaoxFmMNO7dDJL32N79ZmKLxvHIa9Z
# ta7cRDyXUHHXodLFVeNp3lfB0d4wwP3M5k37Db9dT+mdHhk4L7zPWAUu7w2gUDXa
# 7wknHNWzfjUeCLraNtvTX4/edIhJEjCCBNkwggPBoAMCAQICEzMAAAClSBdyJ/lw
# vmMAAAAAAKUwDQYJKoZIhvcNAQELBQAwfDELMAkGA1UEBhMCVVMxEzARBgNVBAgT
# Cldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29m
# dCBDb3Jwb3JhdGlvbjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRpbWUtU3RhbXAgUENB
# IDIwMTAwHhcNMTYwOTA3MTc1NjUwWhcNMTgwOTA3MTc1NjUwWjCBsjELMAkGA1UE
# BhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAc
# BgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEMMAoGA1UECxMDQU9DMScwJQYD
# VQQLEx5uQ2lwaGVyIERTRSBFU046RjZGRi0yREE3LUJCNzUxJTAjBgNVBAMTHE1p
# Y3Jvc29mdCBUaW1lLVN0YW1wIFNlcnZpY2UwggEiMA0GCSqGSIb3DQEBAQUAA4IB
# DwAwggEKAoIBAQC02pLUvUxe8NtXB99ZYYE6JrbTGLNpw/37zCNv0g3M0xtWFsxQ
# Tb7DEvtc1sE0s8I5ybT7Ifoy12FsCgpebk++Cpcv0a0C5OHQ72mBnx8yxk2EJv3i
# e6jSIiw88cwrOTIv/hvsnk9v/YvHVPOFnX6CS1ISju4PYz22N0T6Tlu7X92P/uaF
# 1wNSEZ7BlP81+4cy9hMgkaeaN6HyT6QyVEvgKBTl5yGG7dbDmpk0ISYwdQeYoGXo
# U7fQmVqUEma721ZWNNREkWGJ0LjUXzpO5YA6x/JSmzp119x2qCBTIMcZtxRVdXz7
# ygIiDqFLgfOw5lnFGqULgcoXAj5qxQuOv8G3AgMBAAGjggEbMIIBFzAdBgNVHQ4E
# FgQU4hOrS/LtsWC4ePGFoFH+cuexL6QwHwYDVR0jBBgwFoAU1WM6XIoxkPNDe3xG
# G8UzaFqFbVUwVgYDVR0fBE8wTTBLoEmgR4ZFaHR0cDovL2NybC5taWNyb3NvZnQu
# Y29tL3BraS9jcmwvcHJvZHVjdHMvTWljVGltU3RhUENBXzIwMTAtMDctMDEuY3Js
# MFoGCCsGAQUFBwEBBE4wTDBKBggrBgEFBQcwAoY+aHR0cDovL3d3dy5taWNyb3Nv
# ZnQuY29tL3BraS9jZXJ0cy9NaWNUaW1TdGFQQ0FfMjAxMC0wNy0wMS5jcnQwDAYD
# VR0TAQH/BAIwADATBgNVHSUEDDAKBggrBgEFBQcDCDANBgkqhkiG9w0BAQsFAAOC
# AQEANn1teSvGLi8kIMol9TQVjNzyS0cH9KM+7oZ4CN57h9YGxVjp+8vzF04f6TGg
# xtDCZgOfrs3w7JwrWZOCU7qRERwKnsdiGlqj1RbLLabqwPK0/3l++w7wM+pOG65c
# 2vRQLuhLqGcZBqvH38F9YQUiMGHOpZjAwAIofWkxKZkgbqQ25+KU0oRs3A0aScn1
# 4zZVbW331VsR1Dm6AN+m0STLSTG8JYCCYKTrGeYhgmkvSJKyUMUPDp033x68/rhy
# 65ND/lvGHxteoGhd3g4U5CLUahVW5Oji562Pyic4YmbWbNsmEi8Jg8WucEHiOR6E
# LQux74lwJlIEMuk8DAOebGz4bqGCA3QwggJcAgEBMIHioYG4pIG1MIGyMQswCQYD
# VQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEe
# MBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMQwwCgYDVQQLEwNBT0MxJzAl
# BgNVBAsTHm5DaXBoZXIgRFNFIEVTTjpGNkZGLTJEQTctQkI3NTElMCMGA1UEAxMc
# TWljcm9zb2Z0IFRpbWUtU3RhbXAgU2VydmljZaIlCgEBMAkGBSsOAwIaBQADFQCb
# wjXd+7ImKxoUMWVQLx1TlGmCb6CBwTCBvqSBuzCBuDELMAkGA1UEBhMCVVMxEzAR
# BgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1p
# Y3Jvc29mdCBDb3Jwb3JhdGlvbjEMMAoGA1UECxMDQU9DMScwJQYDVQQLEx5uQ2lw
# aGVyIE5UUyBFU046MjY2NS00QzNGLUM1REUxKzApBgNVBAMTIk1pY3Jvc29mdCBU
# aW1lIFNvdXJjZSBNYXN0ZXIgQ2xvY2swDQYJKoZIhvcNAQEFBQACBQDeYesXMCIY
# DzIwMTgwMzI1MDkzMjA3WhgPMjAxODAzMjYwOTMyMDdaMHQwOgYKKwYBBAGEWQoE
# ATEsMCowCgIFAN5h6xcCAQAwBwIBAAICLcEwBwIBAAICGIgwCgIFAN5jPJcCAQAw
# NgYKKwYBBAGEWQoEAjEoMCYwDAYKKwYBBAGEWQoDAaAKMAgCAQACAxbjYKEKMAgC
# AQACAwehIDANBgkqhkiG9w0BAQUFAAOCAQEAYck2lC3t5JaS3af4+szThRs18bJY
# aYr366welafDuAHCEJuRcx9tA9VDdxXVkJNGEvZq4pAKYix1uwI97QQX6tJ5e0kq
# aLt+77uEwFufQj/kxBVVwN14oowjyZAv+LB3CiybZZX+8IVqv9opiMaLZ0aST/bu
# EWpiAr8NBUzsF6xKioED1CzRE+6hw1z1aDNmcpf+4OgwxsNtKmbgxsnSRv3lrfYs
# hwz9pwabXaqmKv98sccq8z9ynaZAPVDNPFcz5mwdCjXc60nmJi8cnASGxkbS25zs
# S/pw/bnFp/wEfBJF/KEX4LYbz+vB59AKRFL4iiO1Alo2U6TdyUAC0aAVhTGCAvUw
# ggLxAgEBMIGTMHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAw
# DgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24x
# JjAkBgNVBAMTHU1pY3Jvc29mdCBUaW1lLVN0YW1wIFBDQSAyMDEwAhMzAAAApUgX
# cif5cL5jAAAAAAClMA0GCWCGSAFlAwQCAQUAoIIBMjAaBgkqhkiG9w0BCQMxDQYL
# KoZIhvcNAQkQAQQwLwYJKoZIhvcNAQkEMSIEIO2LGELAOi/ym9mL+2+BqPcq/Et4
# GBQbaFusUsek+tPOMIHiBgsqhkiG9w0BCRACDDGB0jCBzzCBzDCBsQQUm8I13fuy
# JisaFDFlUC8dU5Rpgm8wgZgwgYCkfjB8MQswCQYDVQQGEwJVUzETMBEGA1UECBMK
# V2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0
# IENvcnBvcmF0aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0Eg
# MjAxMAITMwAAAKVIF3In+XC+YwAAAAAApTAWBBRTuaz69p++yIlnWGVdpZKQIz1F
# 2zANBgkqhkiG9w0BAQsFAASCAQBxQZyujsDluGhXilT76lvtX7QoOhNjnadCh/nn
# wqrdxziPzTa1XXnlvkmWnL0eglCk4Y6ebz5a4WiKbLyJjFKBORrlzmZU1ognuS/c
# 60PxYNlFCh8o80R+wIqsARoNv6Gp+cGxDtZXZKS5kZsboqJY3WDPCrKuVc9UIK3o
# ean89ag68zL3zYYfP1vxNhW2FErDckmrDiDJrRcKO2q6UqdnNtM2Mh2xvmsV3tfY
# 9Q7ygbL8xRJOXhW03kZfDDDc9spZKUfdNJAgwb/3xARW9RVxs1iOY7mXC5tNKS3Y
# bu2Ne7F4AS1/il3nPeOK4vuwfvxGvBN7rt0FFVfYWYIsphVB
# SIG # End signature block
