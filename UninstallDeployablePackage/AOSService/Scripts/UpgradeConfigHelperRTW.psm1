$global:logfile=""
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

function Upgrade-Web-Config([string]$webroot)
{
    Decrypt-Config -webroot:$webroot
	
    $webconfig=Join-Path -Path $webroot -ChildPath "Web.config"
	
    Upgrade-WebConfig-NewKeys -webconfig:$webconfig
    Upgrade-WebConfig-DeleteKeys -webconfig:$webconfig
    Upgrade-WebConfig-updateKeys -webconfig:$webconfig
    Upgrade-WebConfig-AssemblyReferences -webconfig:$webconfig

    Upgrade-WebConfig-MRServiceModel -webconfig:$webconfig
    
    Encrypt-Config -webroot:$webroot
}

function Upgrade-WebConfig-MRServiceModel([string] $webConfig)
{
    [System.Xml.XmlDocument] $xmlDoc = new-object System.Xml.XmlDocument
    $xmlDoc.Load($webconfig)

    $claimsNode = $xmlDoc.SelectSingleNode("/configuration/claimIssuerRestrictions/issuerRestrictions")

    #exact the MR cert

    $thumbprint = (Get-ChildItem -Path Cert:\LocalMachine\My | Where-Object {$_.Subject -match "ManagementReporter"}).ThumbPrint

    if([string]::IsNullOrEmpty($thumbprint))
    {
        Log-Error -error 'Failed to retrive thumbprint for MR' -throw
    }

    [System.Xml.XmlElement] $element = $xmlDoc.CreateElement("add")
    $newAttribute = $xmlDoc.CreateAttribute('name')
    $newAttribute.Value = $thumbprint

    $element.Attributes.Append($newAttribute)

    $newAttribute = $xmlDoc.CreateAttribute('allowedUserIds')
    $newAttribute.Value = 'FRServiceUser'
    $element.Attributes.Append($newAttribute)

    $newAttribute = $xmlDoc.CreateAttribute('defaultUserId')
    $newAttribute.Value = 'FRServiceUser'
    $element.Attributes.Append($newAttribute)

    $claimsNode.AppendChild($element)

    $xmlDoc.Save($webconfig);
}

function Upgrade-WebConfig-AssemblyReferences([string] $webConfig)
{
    [System.Xml.XmlDocument] $xmlDoc = new-object System.Xml.XmlDocument
    $xmlDoc.Load($webconfig)

    $assembliesNode = $xmlDoc.SelectSingleNode("/configuration/location/system.web/compilation/assemblies")

    $assemblyName = 'Microsoft.Dynamics.AX.Security.SidGenerator';
    Add-NewAssembly -assemblyName:$assemblyName -parentNode:$assembliesNode -xmlDoc:$xmlDoc

    $assemblyName = 'Microsoft.Dynamics.ApplicationPlatform.SystemSecurity';
    Add-NewAssembly -assemblyName:$assemblyName -parentNode:$assembliesNode -xmlDoc:$xmlDoc

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
    
    $key = 'BiReporting.DW'
    $value = ''
    Add-NewKey -key $key -value $value -parentNode $appsettings -xmlDoc $xmlDoc

    $key = 'BiReporting.DWPwd'
    Add-NewKey -key $key -value $value -parentNode $appsettings -xmlDoc $xmlDoc

    $key = 'BiReporting.DWServer'
    Add-NewKey -key $key -value $value -parentNode $appsettings -xmlDoc $xmlDoc

    $key = 'BiReporting.DWUser'
    Add-NewKey -key $key -value $value -parentNode $appsettings -xmlDoc $xmlDoc

    $key = 'OfficeApps.AppInsightsKey'
    $value = '0e9ff251-74c0-4b3f-8466-c5345e5d4933'
    Add-NewKey -key $key -value $value -parentNode $appsettings -xmlDoc $xmlDoc

    #TLS 2.1 support keys
    $key = 'Infrastructure.IsPrivateAOSInstance'
    $value = ''
    Add-NewKey -key $key -value $value -parentNode $appsettings -xmlDoc $xmlDoc

    $key = 'Infrastructure.PrivateAOSInstanceIp'
    $value = ''
    Add-NewKey -key $key -value $value -parentNode $appsettings -xmlDoc $xmlDoc

    $key = 'Infrastructure.PrivateAOSInstanceUrl'
    $value = ''
    Add-NewKey -key $key -value $value -parentNode $appsettings -xmlDoc $xmlDoc


    $xmlDoc.Save($webconfig);
}

function Upgrade-WebConfig-DeleteKeys([string]$webconfig)
{
    [System.Xml.XmlDocument] $xmlDoc=new-object System.Xml.XmlDocument
    $xmlDoc.Load($webconfig)
    
    $key = 'PrintService.InstallPath'
    Remove-Key -key $key -xmlDoc $xmlDoc

    $xmlDoc.Save($webconfig);
}

function Upgrade-WebConfig-updateKeys([string]$webconfig)
{
    [System.Xml.XmlDocument] $xmlDoc=new-object System.Xml.XmlDocument
    $xmlDoc.Load($webconfig)
    
    $key = 'Services.ODataMaxPageSize'
    $value = '10000'
    Update-KeyValue -key $key -value $value -xmlDoc $xmlDoc

    $xmlDoc.Save($webconfig);
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

function Rename-File([string]$from,[string]$to)
{
    Move-Item -Path $from -Destination $to -Force|out-null
    Write-Log "Renamed file '$from' to '$to'."
}

function Validate
{
    Import-Module "$PSScriptRoot\CommonRollbackUtilities.psm1" -DisableNameChecking
    
    $aosWebsiteName = Get-AosWebSiteName
    if(!(Is-Website-Stopped -name:$aosWebsiteName))
    {
        Log-Error "Cannot perform the upgrade as the AOS website '$aosWebsiteName' is started. Stop the website and retry." -throw
    }

    if(!(Is-Service-Stopped -name:$BatchService))
    {
        Log-Error "Cannot perform the upgrade as the NT service '$BatchService' is running. Stop the service and retry." -throw
    }

    if(!(Is-Service-Stopped -name:$PrintService))
    {
        Log-Error "Cannot perform the upgrade as the NT service '$PrintService' is running. Stop the service and retry." -throw
    }
}

function Is-Website-Stopped([string]$name)
{
    Import-Module WebAdministration
    Write-Log "Checking the state of the web site '$name'."|Out-Null
    $website=Get-Website -Name:$name -ErrorAction SilentlyContinue
    if($website -eq $null)
    {
        return $true
    }

    if($website.State -eq "Started")
    {
        return $false
    }

    return $true
}

function Is-Service-Stopped([string]$name)
{
    Write-Log "Checking the status of the service '$name'."|out-null
    $service=Get-Service -Name:$name -ErrorAction SilentlyContinue
    if($service -eq $null)
    {
        return $true
    }

    if($service.Status -eq "Running")
    {
        return $false
    }

    return $true
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
    $command = Join-Path -Path "$PSScriptRoot\EncryptionTool" -ChildPath $configEncryptor
    if(!(Test-Path -Path $command))
    {
        Log-Error "Cannot find the CTP8 Microsoft.Dynamics.AX.Framework.ConfigEncryptor.exe at '$PSScriptRoot\EncryptionTool\'." -throw
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

Export-ModuleMember -Function Initialize-Log,Write-Log,Write-Error,Validate,Create-Backup,Upgrade-Web-Config,Upgrade-Wif-Config,Upgrade-Wif-Services-Config -Variable $logfile

# SIG # Begin signature block
# MIIkDAYJKoZIhvcNAQcCoIIj/TCCI/kCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCCXxUt03J1bkxVq
# dRZDsLj+E2gOHM5rJtOdXF20JEttx6CCDYIwggYAMIID6KADAgECAhMzAAAAww6b
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
# KwYBBAGCNwIBCzEOMAwGCisGAQQBgjcCARUwLwYJKoZIhvcNAQkEMSIEIF9s2OXN
# vsVCPrpbXBpqENIskBHtzO275ePBtW8Wis+dMGYGCisGAQQBgjcCAQwxWDBWoDiA
# NgBVAHAAZwByAGEAZABlAEMAbwBuAGYAaQBnAEgAZQBsAHAAZQByAFIAVABXAC4A
# cABzAG0AMaEagBhodHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20wDQYJKoZIhvcNAQEB
# BQAEggEALgsdtB7ecZ7dreZm1Iwse3YovbuZdQ3d1pVO5lUQBLh688RzV4S0rSld
# zP5Kn+SttvL9W5JeUPetyr+SADSeXDNFzjmAiyzqKuCfaz1Xu42MJl7sZ87jJ032
# VR9237Ylg8o9I/e1P7Uy3gFZoJzOtyr2E2+8b3fu/IRjjDVLyKAWaA6kU1kn/abo
# ccCXP/tMMvgL2va8IYGXV2OaOEs0rqwa6JE21zfoN5uZLzdnICa2R9i1/gDkcSwN
# SvbA1Se+xoGis7ssLIMg1QRGmO2d6k52/kgFyRhdfvATSfMLOBv6asCisGNFhCML
# AIzgAsKMykyf35YYObJ9c3nYPq/WfaGCE0YwghNCBgorBgEEAYI3AwMBMYITMjCC
# Ey4GCSqGSIb3DQEHAqCCEx8wghMbAgEDMQ8wDQYJYIZIAWUDBAIBBQAwggE7Bgsq
# hkiG9w0BCRABBKCCASoEggEmMIIBIgIBAQYKKwYBBAGEWQoDATAxMA0GCWCGSAFl
# AwQCAQUABCBzLLT5C2P5dl4WmHGgDWL64NjRUB0O3GbK4dOqP6MctwIGWrKvYLMk
# GBMyMDE4MDMyNTIxMDU1My4xMjZaMAcCAQGAAgH0oIG3pIG0MIGxMQswCQYDVQQG
# EwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwG
# A1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMQwwCgYDVQQLEwNBT0MxJjAkBgNV
# BAsTHVRoYWxlcyBUU1MgRVNOOjk2RkYtNEJDNS1BN0RDMSUwIwYDVQQDExxNaWNy
# b3NvZnQgVGltZS1TdGFtcCBTZXJ2aWNloIIOyzCCBnEwggRZoAMCAQICCmEJgSoA
# AAAAAAIwDQYJKoZIhvcNAQELBQAwgYgxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpX
# YXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQg
# Q29ycG9yYXRpb24xMjAwBgNVBAMTKU1pY3Jvc29mdCBSb290IENlcnRpZmljYXRl
# IEF1dGhvcml0eSAyMDEwMB4XDTEwMDcwMTIxMzY1NVoXDTI1MDcwMTIxNDY1NVow
# fDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1Jl
# ZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEmMCQGA1UEAxMd
# TWljcm9zb2Z0IFRpbWUtU3RhbXAgUENBIDIwMTAwggEiMA0GCSqGSIb3DQEBAQUA
# A4IBDwAwggEKAoIBAQCpHQ28dxGKOiDs/BOX9fp/aZRrdFQQ1aUKAIKF++18aEss
# X8XD5WHCdrc+Zitb8BVTJwQxH0EbGpUdzgkTjnxhMFmxMEQP8WCIhFRDDNdNuDgI
# s0Ldk6zWczBXJoKjRQ3Q6vVHgc2/JGAyWGBG8lhHhjKEHnRhZ5FfgVSxz5NMksHE
# pl3RYRNuKMYa+YaAu99h/EbBJx0kZxJyGiGKr0tkiVBisV39dx898Fd1rL2KQk1A
# UdEPnAY+Z3/1ZsADlkR+79BL/W7lmsqxqPJ6Kgox8NpOBpG2iAg16HgcsOmZzTzn
# L0S6p/TcZL2kAcEgCZN4zfy8wMlEXV4WnAEFTyJNAgMBAAGjggHmMIIB4jAQBgkr
# BgEEAYI3FQEEAwIBADAdBgNVHQ4EFgQU1WM6XIoxkPNDe3xGG8UzaFqFbVUwGQYJ
# KwYBBAGCNxQCBAweCgBTAHUAYgBDAEEwCwYDVR0PBAQDAgGGMA8GA1UdEwEB/wQF
# MAMBAf8wHwYDVR0jBBgwFoAU1fZWy4/oolxiaNE9lJBb186aGMQwVgYDVR0fBE8w
# TTBLoEmgR4ZFaHR0cDovL2NybC5taWNyb3NvZnQuY29tL3BraS9jcmwvcHJvZHVj
# dHMvTWljUm9vQ2VyQXV0XzIwMTAtMDYtMjMuY3JsMFoGCCsGAQUFBwEBBE4wTDBK
# BggrBgEFBQcwAoY+aHR0cDovL3d3dy5taWNyb3NvZnQuY29tL3BraS9jZXJ0cy9N
# aWNSb29DZXJBdXRfMjAxMC0wNi0yMy5jcnQwgaAGA1UdIAEB/wSBlTCBkjCBjwYJ
# KwYBBAGCNy4DMIGBMD0GCCsGAQUFBwIBFjFodHRwOi8vd3d3Lm1pY3Jvc29mdC5j
# b20vUEtJL2RvY3MvQ1BTL2RlZmF1bHQuaHRtMEAGCCsGAQUFBwICMDQeMiAdAEwA
# ZQBnAGEAbABfAFAAbwBsAGkAYwB5AF8AUwB0AGEAdABlAG0AZQBuAHQALiAdMA0G
# CSqGSIb3DQEBCwUAA4ICAQAH5ohRDeLG4Jg/gXEDPZ2joSFvs+umzPUxvs8F4qn+
# +ldtGTCzwsVmyWrf9efweL3HqJ4l4/m87WtUVwgrUYJEEvu5U4zM9GASinbMQEBB
# m9xcF/9c+V4XNZgkVkt070IQyK+/f8Z/8jd9Wj8c8pl5SpFSAK84Dxf1L3mBZdmp
# tWvkx872ynoAb0swRCQiPM/tA6WWj1kpvLb9BOFwnzJKJ/1Vry/+tuWOM7tiX5rb
# V0Dp8c6ZZpCM/2pif93FSguRJuI57BlKcWOdeyFtw5yjojz6f32WapB4pm3S4Zz5
# Hfw42JT0xqUKloakvZ4argRCg7i1gJsiOCC1JeVk7Pf0v35jWSUPei45V3aicaoG
# ig+JFrphpxHLmtgOR5qAxdDNp9DvfYPw4TtxCd9ddJgiCGHasFAeb73x4QDf5zEH
# pJM692VHeOj4qEir995yfmFrb3epgcunCaw5u+zGy9iCtHLNHfS4hQEegPsbiSpU
# ObJb2sgNVZl6h3M7COaYLeqN4DMuEin1wC9UJyH3yKxO2ii4sanblrKnQqLJzxlB
# TeCG+SqaoxFmMNO7dDJL32N79ZmKLxvHIa9Zta7cRDyXUHHXodLFVeNp3lfB0d4w
# wP3M5k37Db9dT+mdHhk4L7zPWAUu7w2gUDXa7wknHNWzfjUeCLraNtvTX4/edIhJ
# EjCCBNgwggPAoAMCAQICEzMAAAC2i0dDssytHwQAAAAAALYwDQYJKoZIhvcNAQEL
# BQAwfDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcT
# B1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEmMCQGA1UE
# AxMdTWljcm9zb2Z0IFRpbWUtU3RhbXAgUENBIDIwMTAwHhcNMTcxMDAyMjMwMDUy
# WhcNMTkwMTAyMjMwMDUyWjCBsTELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hp
# bmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jw
# b3JhdGlvbjEMMAoGA1UECxMDQU9DMSYwJAYDVQQLEx1UaGFsZXMgVFNTIEVTTjo5
# NkZGLTRCQzUtQTdEQzElMCMGA1UEAxMcTWljcm9zb2Z0IFRpbWUtU3RhbXAgU2Vy
# dmljZTCCASIwDQYJKoZIhvcNAQEBBQADggEPADCCAQoCggEBANiJZxdISwi3RBuT
# EcM6z25BQKaoXGJjslsjRDM19Z7d/cByy4tJbDB7IQBlkpYpRKcMe1M/WU4ge5Zu
# slgQ7649EYd8NWYqb7X8r9DCSnKtP84Q49cQCcXlEuNfzmDo2/hqSW0/JaBpUaej
# 1iz8Q+FCCUo0PVRISiS/fOHdpmcL3myxUrjHyNIRmyZ0/px3YBpmYywMP9gBBN++
# eTMKyeo/u6UUdjWHEtl3XTIW8e7y921gXSh9J2ZpHUkX5JXt+A7+uGeb/7y67R3X
# pPB7CbAoBGpKcxEk1fPKNRNsVsXGHHDWE7WzRga0LKpJROeYlQ8Vu9OlLXkIAYAf
# DaZMwTECAwEAAaOCARswggEXMB0GA1UdDgQWBBTzbcKQAScg2o8zHMBfaGrfgQOF
# 0DAfBgNVHSMEGDAWgBTVYzpcijGQ80N7fEYbxTNoWoVtVTBWBgNVHR8ETzBNMEug
# SaBHhkVodHRwOi8vY3JsLm1pY3Jvc29mdC5jb20vcGtpL2NybC9wcm9kdWN0cy9N
# aWNUaW1TdGFQQ0FfMjAxMC0wNy0wMS5jcmwwWgYIKwYBBQUHAQEETjBMMEoGCCsG
# AQUFBzAChj5odHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20vcGtpL2NlcnRzL01pY1Rp
# bVN0YVBDQV8yMDEwLTA3LTAxLmNydDAMBgNVHRMBAf8EAjAAMBMGA1UdJQQMMAoG
# CCsGAQUFBwMIMA0GCSqGSIb3DQEBCwUAA4IBAQAv19XqvpiOeBy6wypDpE1MzGUz
# KEcV5TqW3hbl1zq7PTwqQMYjIrhA2dj8UWRSETiDxu9K+cIIKZmBLpaFZTKcReDs
# qB2Gmmsp3bixBP+33/lKKNsQ8BIszJf52bSqKGLIsCqD66X10OgK4epSQs2sRAcp
# Ge5eMZY/+HW35djuRHzMj9lHDNbA6OsQjx/KjbBeH6iOanurNuT18zMMdd8pL2TI
# nt3bfQbDGdY0k2kPB1pLoFSVwB55TZFqKJen1UZUdJu5afUeAzqcZjq3aOvMJ8ID
# ixroQQWFYZJJkpIB+XNk+a0M/t3d0r8fYr660odXElNAB4TbTMOuWre2rGRIoYID
# djCCAl4CAQEwgeGhgbekgbQwgbExCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNo
# aW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29y
# cG9yYXRpb24xDDAKBgNVBAsTA0FPQzEmMCQGA1UECxMdVGhhbGVzIFRTUyBFU046
# OTZGRi00QkM1LUE3REMxJTAjBgNVBAMTHE1pY3Jvc29mdCBUaW1lLVN0YW1wIFNl
# cnZpY2WiJQoBATAJBgUrDgMCGgUAAxUA/xYr7xVcs9W1liu+CEsh/E10AAGggcEw
# gb6kgbswgbgxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYD
# VQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xDDAK
# BgNVBAsTA0FPQzEnMCUGA1UECxMebkNpcGhlciBOVFMgRVNOOjI2NjUtNEMzRi1D
# NURFMSswKQYDVQQDEyJNaWNyb3NvZnQgVGltZSBTb3VyY2UgTWFzdGVyIENsb2Nr
# MA0GCSqGSIb3DQEBBQUAAgUA3mHSPTAiGA8yMDE4MDMyNTA3NDYwNVoYDzIwMTgw
# MzI2MDc0NjA1WjB3MD0GCisGAQQBhFkKBAExLzAtMAoCBQDeYdI9AgEAMAoCAQAC
# Agg8AgH/MAcCAQACAhYYMAoCBQDeYyO9AgEAMDYGCisGAQQBhFkKBAIxKDAmMAwG
# CisGAQQBhFkKAwGgCjAIAgEAAgMW42ChCjAIAgEAAgMehIAwDQYJKoZIhvcNAQEF
# BQADggEBAIe0VM1/1WGZ66wiWwoJdqnXsQLOwNkAZTOKqpGeLYOWoSHPolJ6HJJw
# f/kFJdy2PG8uDk3abUVcmB7QZRtaea9CpycEnFQeU+WsPSdydjUhBY9R274O+YUc
# 5uUnY9y5DFTQTPrlYiIL2IS+gbbBeusO1QSg1SUz6JmkwkVz0hwOtICmnDWMEBGw
# rRP663h++VWYEbSarMFdt816KZL2CcmgAGFWqYadAXVXRoo4jF9TGn5983HflM6A
# Sq+YgMW5BuZhjKR3KdPovLuB3Yht2ciW80VsHJBkSGAgP7X4Qe8Tv4ccqdAOjB1O
# peOfP2Ta6/kjFNSJ34ErsKuZcNtbm7ExggL1MIIC8QIBATCBkzB8MQswCQYDVQQG
# EwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwG
# A1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQg
# VGltZS1TdGFtcCBQQ0EgMjAxMAITMwAAALaLR0OyzK0fBAAAAAAAtjANBglghkgB
# ZQMEAgEFAKCCATIwGgYJKoZIhvcNAQkDMQ0GCyqGSIb3DQEJEAEEMC8GCSqGSIb3
# DQEJBDEiBCDleAhzJnnXA3ocQtkPt7G7q5U9SQOdBrBCUJTMe1H39jCB4gYLKoZI
# hvcNAQkQAgwxgdIwgc8wgcwwgbEEFP8WK+8VXLPVtZYrvghLIfxNdAABMIGYMIGA
# pH4wfDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcT
# B1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEmMCQGA1UE
# AxMdTWljcm9zb2Z0IFRpbWUtU3RhbXAgUENBIDIwMTACEzMAAAC2i0dDssytHwQA
# AAAAALYwFgQULhb4FpkwxJhZ0fMHreuAGLhiyHswDQYJKoZIhvcNAQELBQAEggEA
# IN3iZ6g6gGI3e1PCXa/fKTUBtOofaVE1m8TRh0Nl8Vv0MfaOaQNVOLxJHRMgOuRI
# Rvjc627nJqnrXcv++5uFPJYkBiKIj3gOGfykwxdJWDp26mtmuK4BYPRtgH3R+3xq
# T9s80yGRanHaQmSfwGJ3icQHFpcmJm6T6AFTA/HgIiQZzKVTkfktayVDNe7K9qng
# YJDse+goM17C2pxTkzwXUd0QKe++9H4FoUTVebJ0li7ZNZoRctHNzLL7w27m1h29
# nsOQAQzJ0e0e0F3RZmUEiuclrMGu9hLEt+zs1oqBSyFi4z4uE1cvMBbgh64GH27I
# 33gFePis6fzQXyjUj8pG2w==
# SIG # End signature block
