$module=Join-Path -Path $PSScriptRoot -ChildPath "CommonRollbackUtilities.psm1" 
Import-Module $module -DisableNameChecking -force

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

function Upgrade-Web-Config([string]$webroot)
{
    Decrypt-Config -webroot:$webroot
    $webconfig=Join-Path -Path $webroot -ChildPath "Web.config"
    Upgrade-WebConfig-NewKeys -webconfig:$webconfig
    #Upgrade-WebConfig-DeleteKeys -webconfig:$webconfig
    Upgrade-WebConfig-updateKeys -webconfig:$webconfig
    #Upgrade-WebConfig-AssemblyReferences -webconfig:$webconfig
    Encrypt-Config -webroot:$webroot
}

function Upgrade-WebConfig-AssemblyReferences([string] $webConfig)
{
    [System.Xml.XmlDocument] $xmlDoc = new-object System.Xml.XmlDocument
    $xmlDoc.Load($webconfig)

    $assembliesNode = $xmlDoc.SelectSingleNode("/configuration/location/system.web/compilation/assemblies")

    #Add your assembly name here and call Add-NewAssembly prior to save

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
    Add-NewKey -key $key -value $value -parentNode $appsettings -xmlDoc $xmlDoc

    $xmlDoc.Save($webconfig);
}

function Upgrade-WebConfig-DeleteKeys([string]$webconfig)
{
    [System.Xml.XmlDocument] $xmlDoc=new-object System.Xml.XmlDocument
    $xmlDoc.Load($webconfig)
    
    #$key = ''
    #Remove-Key -key $key -xmlDoc $xmlDoc

    $xmlDoc.Save($webconfig);
}

function Upgrade-WebConfig-updateKeys([string]$webconfig)
{
    [System.Xml.XmlDocument] $xmlDoc=new-object System.Xml.XmlDocument
    $xmlDoc.Load($webconfig)
    
    # Update the AppInsightsKey if it was the old production key to the new production key. Test keys are unchanged.
    $key = "OfficeApps.AppInsightsKey"
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

function Rename-File([string]$from,[string]$to)
{
    Move-Item -Path $from -Destination $to -Force|out-null
    Write-Log "Renamed file '$from' to '$to'."
}

function Validate
{
    if(!(Is-Website-Stopped -name:$AosWebsiteName))
    {
        Log-Error "Cannot perform the upgrade as the AOS website '$AosWebsiteName' is started. Stop the website and retry." -throw
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

Export-ModuleMember -Function Initialize-Log,Write-Log,Write-Error,Validate,Create-Backup,Upgrade-Web-Config,Upgrade-Wif-Config,Upgrade-Wif-Services-Config -Variable $logfile
# SIG # Begin signature block
# MIIkFAYJKoZIhvcNAQcCoIIkBTCCJAECAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCDDfsdzxzs/Fnrt
# cpcxY3PwNt84dkXIiUtB5O70O3pf1KCCDYIwggYAMIID6KADAgECAhMzAAAAww6b
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
# KwYBBAGCNwIBCzEOMAwGCisGAQQBgjcCARUwLwYJKoZIhvcNAQkEMSIEIJgRUW4q
# zHaOiTcnEr46wq/PI8RSvewJ82es0URFmvU8MG4GCisGAQQBgjcCAQwxYDBeoECA
# PgBVAHAAZwByAGEAZABlAEMAbwBuAGYAaQBnAEgAZQBsAHAAZQByAFUAcABkAGEA
# dABlADIALgBwAHMAbQAxoRqAGGh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbTANBgkq
# hkiG9w0BAQEFAASCAQCY+fN5VOR0DowVy9Cqnfl4qGfRP+tcNA7iAAqA9hO8AznN
# ugnYCYSBasmNFvEPyu0rrUWHrPNI2PaTd34sQLAqr2SArrc/6blRd1b0wZ1IlfHj
# 7JO6ICq6sUtUqOSDRqmnmGrCQIdVYGG++4FYHGMtFAsmRXg7O1fvrj5Qd7VR4gWE
# ocEP2NqJmKC38njuZbfbWuo0yrrklwQEkkp1hZ8P8bf5V1OLTPqU1aBCKPl7OVda
# 87wBcfT/ZIpCEZEsJG6n57NdB3X0E31sBwKzt03TL/YZN5bYKFgvHQKRSTEZcdwx
# 0UC90IEK/IaDNYCG7kz+08iyD/uBHUlmFitc0Yb0oYITRjCCE0IGCisGAQQBgjcD
# AwExghMyMIITLgYJKoZIhvcNAQcCoIITHzCCExsCAQMxDzANBglghkgBZQMEAgEF
# ADCCATwGCyqGSIb3DQEJEAEEoIIBKwSCAScwggEjAgEBBgorBgEEAYRZCgMBMDEw
# DQYJYIZIAWUDBAIBBQAEIMhT9zNZYzLeMpMo+4/0jS7J3P7O+qN37nx/Sy30uY32
# AgZasoCDlb4YEzIwMTgwMzI1MjEwNTU3LjgzNlowBwIBAYACAfSggbikgbUwgbIx
# CzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRt
# b25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xDDAKBgNVBAsTA0FP
# QzEnMCUGA1UECxMebkNpcGhlciBEU0UgRVNOOjEyQjQtMkQ1Ri04N0Q0MSUwIwYD
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
# NtvTX4/edIhJEjCCBNkwggPBoAMCAQICEzMAAACnZF3FKA8BPUQAAAAAAKcwDQYJ
# KoZIhvcNAQELBQAwfDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24x
# EDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlv
# bjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRpbWUtU3RhbXAgUENBIDIwMTAwHhcNMTYw
# OTA3MTc1NjUyWhcNMTgwOTA3MTc1NjUyWjCBsjELMAkGA1UEBhMCVVMxEzARBgNV
# BAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jv
# c29mdCBDb3Jwb3JhdGlvbjEMMAoGA1UECxMDQU9DMScwJQYDVQQLEx5uQ2lwaGVy
# IERTRSBFU046MTJCNC0yRDVGLTg3RDQxJTAjBgNVBAMTHE1pY3Jvc29mdCBUaW1l
# LVN0YW1wIFNlcnZpY2UwggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIBAQCm
# 6hpQwF9P0lP5oewEfA3XIFcxIVHYx+4DCi54zosuIiNrljYQHwpReoXnXRT+c7LX
# 0nxjVcEKuMaUNOi4idkXnAmxGKGRP0NWVVbZW8VP1oN+5OgQiBtMehuQotS1AtPR
# +L+bzv81atUujkyTRnqzfU5S0BgR2MyXzEyU5HKLUPzq0lIJEDiDEbiWAzE4XEGN
# OimHEVgTow6tfa3e+uZuytC4oXNtvrWppWdJawd8eYi0ZjbyMSc4FOI1H8EnXXjI
# 4ioya2eBRlMF1ntDNWpEMO27Ie03SX+yRAmb2lnAKz6S+A7AJksXiu8I01TnjAuP
# io1S9qB5qE9mBjK5iyrxAgMBAAGjggEbMIIBFzAdBgNVHQ4EFgQUfA1KC337T/9e
# ECw9eW8gTUJQiF0wHwYDVR0jBBgwFoAU1WM6XIoxkPNDe3xGG8UzaFqFbVUwVgYD
# VR0fBE8wTTBLoEmgR4ZFaHR0cDovL2NybC5taWNyb3NvZnQuY29tL3BraS9jcmwv
# cHJvZHVjdHMvTWljVGltU3RhUENBXzIwMTAtMDctMDEuY3JsMFoGCCsGAQUFBwEB
# BE4wTDBKBggrBgEFBQcwAoY+aHR0cDovL3d3dy5taWNyb3NvZnQuY29tL3BraS9j
# ZXJ0cy9NaWNUaW1TdGFQQ0FfMjAxMC0wNy0wMS5jcnQwDAYDVR0TAQH/BAIwADAT
# BgNVHSUEDDAKBggrBgEFBQcDCDANBgkqhkiG9w0BAQsFAAOCAQEAmsYkS+eXslIB
# ZIcP4kKTKFZ5dvT5ChVnTXoOiYA8PzNC3o5y8lym83izubCF0o8l7duKveEsfVZg
# BBLPJ/NjePhGVFRKFtpr6ly7+4Z6bF5/TXNioDadsN6z6c8SYoz68JxsJAxriC6R
# l77fTjKMXG4nhCd5m53L3+jsEQsACVx6L2ol9tL2OiqHbUd2zFWvTrbx1Xoas/mc
# HQhIKP1x/14HmyVCsKP4C/1h0l+6dOhh1fPi4ES/KQ3jivBtXYxa4uUODYEH0SuO
# 0nlQma0Boss1Abq+AEKDI3G2HWCHqoxb/nvtcIYOCHG1V4UvlBAjbbQfvKNGt+UW
# S67wrra6TqGCA3QwggJcAgEBMIHioYG4pIG1MIGyMQswCQYDVQQGEwJVUzETMBEG
# A1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWlj
# cm9zb2Z0IENvcnBvcmF0aW9uMQwwCgYDVQQLEwNBT0MxJzAlBgNVBAsTHm5DaXBo
# ZXIgRFNFIEVTTjoxMkI0LTJENUYtODdENDElMCMGA1UEAxMcTWljcm9zb2Z0IFRp
# bWUtU3RhbXAgU2VydmljZaIlCgEBMAkGBSsOAwIaBQADFQDkgi6dMjZtdAAyDx7B
# IbQN6wx32aCBwTCBvqSBuzCBuDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hp
# bmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jw
# b3JhdGlvbjEMMAoGA1UECxMDQU9DMScwJQYDVQQLEx5uQ2lwaGVyIE5UUyBFU046
# MjY2NS00QzNGLUM1REUxKzApBgNVBAMTIk1pY3Jvc29mdCBUaW1lIFNvdXJjZSBN
# YXN0ZXIgQ2xvY2swDQYJKoZIhvcNAQEFBQACBQDeYefPMCIYDzIwMTgwMzI1MDkx
# ODA3WhgPMjAxODAzMjYwOTE4MDdaMHQwOgYKKwYBBAGEWQoEATEsMCowCgIFAN5h
# 588CAQAwBwIBAAICID0wBwIBAAICGYgwCgIFAN5jOU8CAQAwNgYKKwYBBAGEWQoE
# AjEoMCYwDAYKKwYBBAGEWQoDAaAKMAgCAQACAxbjYKEKMAgCAQACAwehIDANBgkq
# hkiG9w0BAQUFAAOCAQEABx7EJHtdjgMxUNxkh0L7Qjf+L+RTGmQf8YTmM8CZFgli
# 0HPH00yrmfspvP7Tld+G2cEoRY5hveDwqP8sILNJi5tz650P+k1LoNguAvl3NFwe
# icycyNboyQUWbS0V7xQPCekG75qIZDdT276BPfE1Zk8rS9HdvfVbRtUZQZiSlx1m
# bv09MR0zLGyfuIZoLvAKwPCYZQ6WcB4KhIB7ixlr2QJjATJ7+0fe2Btwp7w5Fxtc
# Bp0Hp1R4h57Pmq1nT5CXSkgkn0JdYQp6gizmT6RBhOnsUdWMYTBtgkISwtBOUlZx
# cgzAppVKES29m+lWZhkkp7wCjgT7cYbl8PaSisaVpDGCAvUwggLxAgEBMIGTMHwx
# CzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRt
# b25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xJjAkBgNVBAMTHU1p
# Y3Jvc29mdCBUaW1lLVN0YW1wIFBDQSAyMDEwAhMzAAAAp2RdxSgPAT1EAAAAAACn
# MA0GCWCGSAFlAwQCAQUAoIIBMjAaBgkqhkiG9w0BCQMxDQYLKoZIhvcNAQkQAQQw
# LwYJKoZIhvcNAQkEMSIEIOuu66kxtkGuIiUrUO8hc2LBK9adkPrWR2HXkmfixgcY
# MIHiBgsqhkiG9w0BCRACDDGB0jCBzzCBzDCBsQQU5IIunTI2bXQAMg8ewSG0DesM
# d9kwgZgwgYCkfjB8MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQ
# MA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9u
# MSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0EgMjAxMAITMwAAAKdk
# XcUoDwE9RAAAAAAApzAWBBRhjz/2IczTl8Uag1UtwEj7DPO9jjANBgkqhkiG9w0B
# AQsFAASCAQBonWo9QMDbFQGznHhce1NcbIJir4qgib1xPIKEFhoYHgefXcMMZuCW
# g3xRBfqlVUq38vwMTrKq8Yof7HcyY912IrMMngDuIjKOT1lyRvG36Lkp4lfyrqiv
# eJVqRcUAajzI+dDT1UWz+tkUjCO6pxT8fyi2SLk49P6fbkRhNSIuei0EClUvLbDG
# s9GL6r6ce6Qx4icfY2QBSOC5c9Fm9Hznef8D/NRSJD/SLFczxGVRQ/2nvSHM2wxI
# nyNWPc1IwyIykdxmec7QJ7JLYGVqNcSrB6OOuEleoCuTkB1pUzns/tN5CSlPlGcc
# 9gCLzy+ChOMgL8U+27n4i7XWZZaabbeD
# SIG # End signature block
