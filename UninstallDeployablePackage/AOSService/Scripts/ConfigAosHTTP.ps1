param
(
    [Parameter(Mandatory=$true)]
    $config,
    [Parameter(Mandatory=$true)]
    $log
)

Import-Module "$PSScriptRoot\AosCommon.psm1" -Force -DisableNameChecking

function RemoveHttpModule($webConfig, $location, $httpModuleName)
{
    Write-Log "Adding remove $httpModuleName HTTP module for $location location"
    $webHttpRemoveModules = $webConfig.SelectNodes("configuration/location[@path='$location']/system.webServer/modules")
    $httpRemoveModule = $webHttpRemoveModules.remove | where { $_.name -eq $httpModuleName }
    if ($httpRemoveModule -eq $null)
    {
        $newAdd = $webConfig.CreateElement("remove")
        $newAdd.SetAttribute("name", "$httpModuleName")
        $webHttpRemoveModules.AppendChild($newAdd) | Out-Null    
    }
}

function ConfigureHttp-WebConfig($settings)
{
    Write-Log "Configuring web.config for HTTP"
    $WebRootPath = $settings.'Infrastructure.WebRoot'

    Write-Log "Setting webHttpBinding security to None"
    [xml]$webConfig = Get-Content "$WebRootPath\web.config"
    $webBindingSecurity = $webConfig.SelectNodes("configuration/location/system.serviceModel/bindings/webHttpBinding/binding/security")

    foreach ($bindingSecurity in $webBindingSecurity)
    {
        $bindingSecurity.mode = "None"
    }

    Write-Log "Adding SecureCookieHttpModule HTTP module"
    $SecureCookieHttpModuleName = "SecureCookieHttpModule"
    $webHttpModules = $webConfig.SelectNodes("configuration/system.webServer/modules")
    $secureCookieModule = $webHttpModules.add | where { $_.name -eq $SecureCookieHttpModuleName }
    if ($secureCookieModule -eq $null)
    {
        $newAdd = $webConfig.CreateElement("add")
        $newAdd.SetAttribute("name", "$SecureCookieHttpModuleName")
        $newAdd.SetAttribute("type", "Microsoft.Dynamics.AX.HttpModule.SecureCookieHttpModule, AOSKernel, Version=7.0.0.0, Culture=neutral, PublicKeyToken=31bf3856ad364e35")
        $newAdd.SetAttribute("preCondition", "managedHandler")
        $webHttpModules.AppendChild($newAdd) | Out-Null    
    }

    $webConfig.Save("$WebRootPath\web.config")  
}

function ConfigureHttp-WifServicesConfig($settings)
{
    Write-Log "Configuring wif.services.config for HTTP"
    $WebRootPath = $settings.'Infrastructure.WebRoot'

    Write-Log "Setting requireSsl = false in wif.services.config"
    [xml]$wifServices = Get-Content "$WebRootPath\wif.services.config"
    $cookieHandler = $wifServices.SelectSingleNode("system.identityModel.services/federationConfiguration/cookieHandler")

    $cookieHandler.requireSsl = "false"

    $wifServices.Save("$WebRootPath\wif.services.config")   
}

function ConfigureHttp-IIS($settings)
{
    Write-Log "Adding website HTTP binding" 

    Import-Module WebAdministration

    $AosWebSiteName = $settings.'Infrastructure.ApplicationName'
    $AosWebSite = Get-Website -Name "$AosWebSiteName"
    $existingBinding = Get-WebBinding -Name "$AosWebSiteName" -Protocol "https" -Port 443
    if($existingBinding -eq $null)
    {    
        Write-Log "Https binding is not configured, configure http binding from IIS management console."
    }
    
    $hostheader = $existingBinding.bindingInformation.Split(":") | select -Last 1

    New-WebBinding -Name "$AosWebSiteName" -Force -HostHeader "$hostheader" -IPAddress "*" -port 80 -Protocol "http"
}

Initialize-Log $log
Write-Log "Decoding settings"
$settings = Decode-Settings $config

# in powershell this is case-insensitive
if ($settings.'Infrastructure.HttpProtocol' -eq "Http")
{
    Write-Log "Updating AOS web.config for HTTP"
    ConfigureHttp-WebConfig $settings
    Write-Log "AOS web.config update complete"

    Write-Log "Updating AOS wif.services.config for HTTP"
    ConfigureHttp-WifServicesConfig $settings
    Write-Log "AOS wif.services.config update complete"

<#
    Write-Log "Updating AOS IIS website configuration"
    ConfigureHttp-IIS $settings
    Write-Log "AOS IIS website configuration update complete"
#>
    
    Write-Log "Restarting IIS"
    iisreset

    Write-Log "AOS Http configuration complete, exiting"
}
else
{
    Write-Log "Protocol is set to $($settings.'Infrastructure.Protocol'), exiting."
}
# SIG # Begin signature block
# MIIj+AYJKoZIhvcNAQcCoIIj6TCCI+UCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCDO0EJ46e9uFr+F
# QESY4Dnm6S01o3DW/eNlyFHkRkhPbaCCDYIwggYAMIID6KADAgECAhMzAAAAww6b
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
# SEXAQsmbdlsKgEhr/Xmfwb1tbWrJUnMTDXpQzTGCFcwwghXIAgEBMIGVMH4xCzAJ
# BgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25k
# MR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xKDAmBgNVBAMTH01pY3Jv
# c29mdCBDb2RlIFNpZ25pbmcgUENBIDIwMTECEzMAAADDDpun2LLc9ywAAAAAAMMw
# DQYJYIZIAWUDBAIBBQCggb4wGQYJKoZIhvcNAQkDMQwGCisGAQQBgjcCAQQwHAYK
# KwYBBAGCNwIBCzEOMAwGCisGAQQBgjcCARUwLwYJKoZIhvcNAQkEMSIEIKDq5+bf
# s6RQ/UHE8y03l5Y0gYzpzfxUd753wXjbslP6MFIGCisGAQQBgjcCAQwxRDBCoCSA
# IgBDAG8AbgBmAGkAZwBBAG8AcwBIAFQAVABQAC4AcABzADGhGoAYaHR0cDovL3d3
# dy5taWNyb3NvZnQuY29tMA0GCSqGSIb3DQEBAQUABIIBAEj1F+N7xZ5bHgP80n1W
# ATa6w2raksn5BMbypkMZFsBRjlCxYRFz+Ubuv2lvBEQP6gTwK1ZLVvOrpC84L38W
# g2eat5hptowtglhomiDR7P6iEsmpPJqQXDX5j60qy3miTicPHWa7UhxQ3Ft8j6MI
# H4cBXJNCqYwEN0R+CzlGrAEc/uChRcbvks1C7bODFzD6a2u5pQtpb/eCNrrskUgE
# 3Jmqtl12cvnkScXsfaV97hyLGzcbhimzKnuFj2jNZhUkefoqJhja0YBfzT9ba28U
# VY5TqGJaqiFiXBCdqvHj/C5aPN6YtrBGzik+w64xGKtqCDfusPfI4Wvct83e5bIM
# 2QWhghNGMIITQgYKKwYBBAGCNwMDATGCEzIwghMuBgkqhkiG9w0BBwKgghMfMIIT
# GwIBAzEPMA0GCWCGSAFlAwQCAQUAMIIBPAYLKoZIhvcNAQkQAQSgggErBIIBJzCC
# ASMCAQEGCisGAQQBhFkKAwEwMTANBglghkgBZQMEAgEFAAQgnypre65jyqhYFPer
# pxl/hS/bEdSEl6HlJBByw1I5C3UCBlqypbvNSBgTMjAxODAzMjUyMTA1NDcuNjAy
# WjAHAgEBgAIB9KCBuKSBtTCBsjELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hp
# bmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jw
# b3JhdGlvbjEMMAoGA1UECxMDQU9DMScwJQYDVQQLEx5uQ2lwaGVyIERTRSBFU046
# MTJFNy0zMDY0LTYxMTIxJTAjBgNVBAMTHE1pY3Jvc29mdCBUaW1lLVN0YW1wIFNl
# cnZpY2Wggg7KMIIGcTCCBFmgAwIBAgIKYQmBKgAAAAAAAjANBgkqhkiG9w0BAQsF
# ADCBiDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcT
# B1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEyMDAGA1UE
# AxMpTWljcm9zb2Z0IFJvb3QgQ2VydGlmaWNhdGUgQXV0aG9yaXR5IDIwMTAwHhcN
# MTAwNzAxMjEzNjU1WhcNMjUwNzAxMjE0NjU1WjB8MQswCQYDVQQGEwJVUzETMBEG
# A1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWlj
# cm9zb2Z0IENvcnBvcmF0aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1TdGFt
# cCBQQ0EgMjAxMDCCASIwDQYJKoZIhvcNAQEBBQADggEPADCCAQoCggEBAKkdDbx3
# EYo6IOz8E5f1+n9plGt0VBDVpQoAgoX77XxoSyxfxcPlYcJ2tz5mK1vwFVMnBDEf
# QRsalR3OCROOfGEwWbEwRA/xYIiEVEMM1024OAizQt2TrNZzMFcmgqNFDdDq9UeB
# zb8kYDJYYEbyWEeGMoQedGFnkV+BVLHPk0ySwcSmXdFhE24oxhr5hoC732H8RsEn
# HSRnEnIaIYqvS2SJUGKxXf13Hz3wV3WsvYpCTUBR0Q+cBj5nf/VmwAOWRH7v0Ev9
# buWayrGo8noqCjHw2k4GkbaICDXoeByw6ZnNPOcvRLqn9NxkvaQBwSAJk3jN/LzA
# yURdXhacAQVPIk0CAwEAAaOCAeYwggHiMBAGCSsGAQQBgjcVAQQDAgEAMB0GA1Ud
# DgQWBBTVYzpcijGQ80N7fEYbxTNoWoVtVTAZBgkrBgEEAYI3FAIEDB4KAFMAdQBi
# AEMAQTALBgNVHQ8EBAMCAYYwDwYDVR0TAQH/BAUwAwEB/zAfBgNVHSMEGDAWgBTV
# 9lbLj+iiXGJo0T2UkFvXzpoYxDBWBgNVHR8ETzBNMEugSaBHhkVodHRwOi8vY3Js
# Lm1pY3Jvc29mdC5jb20vcGtpL2NybC9wcm9kdWN0cy9NaWNSb29DZXJBdXRfMjAx
# MC0wNi0yMy5jcmwwWgYIKwYBBQUHAQEETjBMMEoGCCsGAQUFBzAChj5odHRwOi8v
# d3d3Lm1pY3Jvc29mdC5jb20vcGtpL2NlcnRzL01pY1Jvb0NlckF1dF8yMDEwLTA2
# LTIzLmNydDCBoAYDVR0gAQH/BIGVMIGSMIGPBgkrBgEEAYI3LgMwgYEwPQYIKwYB
# BQUHAgEWMWh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9QS0kvZG9jcy9DUFMvZGVm
# YXVsdC5odG0wQAYIKwYBBQUHAgIwNB4yIB0ATABlAGcAYQBsAF8AUABvAGwAaQBj
# AHkAXwBTAHQAYQB0AGUAbQBlAG4AdAAuIB0wDQYJKoZIhvcNAQELBQADggIBAAfm
# iFEN4sbgmD+BcQM9naOhIW+z66bM9TG+zwXiqf76V20ZMLPCxWbJat/15/B4vceo
# niXj+bzta1RXCCtRgkQS+7lTjMz0YBKKdsxAQEGb3FwX/1z5Xhc1mCRWS3TvQhDI
# r79/xn/yN31aPxzymXlKkVIArzgPF/UveYFl2am1a+THzvbKegBvSzBEJCI8z+0D
# pZaPWSm8tv0E4XCfMkon/VWvL/625Y4zu2JfmttXQOnxzplmkIz/amJ/3cVKC5Em
# 4jnsGUpxY517IW3DnKOiPPp/fZZqkHimbdLhnPkd/DjYlPTGpQqWhqS9nhquBEKD
# uLWAmyI4ILUl5WTs9/S/fmNZJQ96LjlXdqJxqgaKD4kWumGnEcua2A5HmoDF0M2n
# 0O99g/DhO3EJ3110mCIIYdqwUB5vvfHhAN/nMQekkzr3ZUd46PioSKv33nJ+YWtv
# d6mBy6cJrDm77MbL2IK0cs0d9LiFAR6A+xuJKlQ5slvayA1VmXqHczsI5pgt6o3g
# My4SKfXAL1QnIffIrE7aKLixqduWsqdCosnPGUFN4Ib5KpqjEWYw07t0MkvfY3v1
# mYovG8chr1m1rtxEPJdQcdeh0sVV42neV8HR3jDA/czmTfsNv11P6Z0eGTgvvM9Y
# BS7vDaBQNdrvCScc1bN+NR4Iuto229Nfj950iEkSMIIE2TCCA8GgAwIBAgITMwAA
# AKyKIbx60pty9AAAAAAArDANBgkqhkiG9w0BAQsFADB8MQswCQYDVQQGEwJVUzET
# MBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMV
# TWljcm9zb2Z0IENvcnBvcmF0aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1T
# dGFtcCBQQ0EgMjAxMDAeFw0xNjA5MDcxNzU2NTRaFw0xODA5MDcxNzU2NTRaMIGy
# MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVk
# bW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMQwwCgYDVQQLEwNB
# T0MxJzAlBgNVBAsTHm5DaXBoZXIgRFNFIEVTTjoxMkU3LTMwNjQtNjExMjElMCMG
# A1UEAxMcTWljcm9zb2Z0IFRpbWUtU3RhbXAgU2VydmljZTCCASIwDQYJKoZIhvcN
# AQEBBQADggEPADCCAQoCggEBAKHE9DyljnMxoRdBXKt3CLep0UOqu9/cdPm6NVZq
# hAnYqbv7VPcY2cals0Po+iYBzD019X4L5EyYKtOGlSUFXN67Ow0vYuyP2Yx0rzeL
# F5trN6dKsDStcsiJ9YHModU/qPOxBaj3pwe6QdmojzFGne1iK+Bqm3ksuuf1GbYm
# f4TSHaUoM7Dmwi15mKuI4w8fZnua2BhebIHxOGB0Hjqnp+s0alxevXWlrVWSV2XS
# JjqgEApBBLEnkGfg3u6LlaPnAOQNnMYCDqfWm0w9M8mEva6ixbzhiOdKn/ay41qn
# eo6MoRheakbO9qyrmrKo/K9+p+Sw580Fome1+kLx0gMkqucCAwEAAaOCARswggEX
# MB0GA1UdDgQWBBTYR3CohTWLE2Gvh5DoRRck4JinDTAfBgNVHSMEGDAWgBTVYzpc
# ijGQ80N7fEYbxTNoWoVtVTBWBgNVHR8ETzBNMEugSaBHhkVodHRwOi8vY3JsLm1p
# Y3Jvc29mdC5jb20vcGtpL2NybC9wcm9kdWN0cy9NaWNUaW1TdGFQQ0FfMjAxMC0w
# Ny0wMS5jcmwwWgYIKwYBBQUHAQEETjBMMEoGCCsGAQUFBzAChj5odHRwOi8vd3d3
# Lm1pY3Jvc29mdC5jb20vcGtpL2NlcnRzL01pY1RpbVN0YVBDQV8yMDEwLTA3LTAx
# LmNydDAMBgNVHRMBAf8EAjAAMBMGA1UdJQQMMAoGCCsGAQUFBwMIMA0GCSqGSIb3
# DQEBCwUAA4IBAQBI7OheJ8MbGJxdtM52bjcMH11jHA1dpCPSFbTO0EAJ5ZtfrPF5
# 7XDtMl5dDHUh9PPUFYkB9WVrscDWjFrQuIX9R/qt9G8QSYaYev3BYRuvfGISuWVM
# UTZX+Z1gFITB2PvibxAsF4VjfsKPHhMV74AH8VCXLeS9+skoNphhNNdMAVgAqmLQ
# BwNNwRJdlyyEn87xRmz1+vQGCs6bmHup5DUIk2YMxUSoSVC39wU7d3GqsAq/cW7+
# exPkaQAG768iJuDFfq02apxwghcoAuC/vMMhpEABa1dX0vCeay0NRsinx0f+hJWb
# e0+cI+WsHf4Lby8+e8l1u0mL/I64RN36suf6oYIDdDCCAlwCAQEwgeKhgbikgbUw
# gbIxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdS
# ZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xDDAKBgNVBAsT
# A0FPQzEnMCUGA1UECxMebkNpcGhlciBEU0UgRVNOOjEyRTctMzA2NC02MTEyMSUw
# IwYDVQQDExxNaWNyb3NvZnQgVGltZS1TdGFtcCBTZXJ2aWNloiUKAQEwCQYFKw4D
# AhoFAAMVADlwJYsUyHndXwxd6Yucs5SZ9xy3oIHBMIG+pIG7MIG4MQswCQYDVQQG
# EwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwG
# A1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMQwwCgYDVQQLEwNBT0MxJzAlBgNV
# BAsTHm5DaXBoZXIgTlRTIEVTTjoyNjY1LTRDM0YtQzVERTErMCkGA1UEAxMiTWlj
# cm9zb2Z0IFRpbWUgU291cmNlIE1hc3RlciBDbG9jazANBgkqhkiG9w0BAQUFAAIF
# AN5h7TQwIhgPMjAxODAzMjUwOTQxMDhaGA8yMDE4MDMyNjA5NDEwOFowdDA6Bgor
# BgEEAYRZCgQBMSwwKjAKAgUA3mHtNAIBADAHAgEAAgInFjAHAgEAAgIZzjAKAgUA
# 3mM+tAIBADA2BgorBgEEAYRZCgQCMSgwJjAMBgorBgEEAYRZCgMBoAowCAIBAAID
# FuNgoQowCAIBAAIDB6EgMA0GCSqGSIb3DQEBBQUAA4IBAQBjV+JYN94eW9JXHzI8
# OS9EYs8Zc/vj66u9ZgHN6me/p3y9eFZLkywLos/z5tNadLMxawO+mNk63G5OcUvB
# vMigMvualIRiMSa0KKA01BJP5mloShf4fiV04HqL0RCNkToMGeWN6cbh4sAQiUUO
# K54cPaWz1pptxmXuYio8IBaWCBAKVd6SMm1mPqoir0tpVNn3OAbnsjcZsZxyB8Lq
# LyChnd0Q/Sk0UyAkoAM3WNmFqPGcA/O76dngC1BW9KBwOgh/31R7zNSVRBSAbR/s
# Q74mqdvZLI8tYHSFWy5ZjEimkOdaF4udvNcH49XZn/lt6zQAE1LsPzmbbo6QgMh1
# Lc6FMYIC9TCCAvECAQEwgZMwfDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hp
# bmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jw
# b3JhdGlvbjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRpbWUtU3RhbXAgUENBIDIwMTAC
# EzMAAACsiiG8etKbcvQAAAAAAKwwDQYJYIZIAWUDBAIBBQCgggEyMBoGCSqGSIb3
# DQEJAzENBgsqhkiG9w0BCRABBDAvBgkqhkiG9w0BCQQxIgQgsjwFbBjl0Hk4Zsf8
# FxBCaOs605t8Dt9GtaTYO9E7zAgwgeIGCyqGSIb3DQEJEAIMMYHSMIHPMIHMMIGx
# BBQ5cCWLFMh53V8MXemLnLOUmfcctzCBmDCBgKR+MHwxCzAJBgNVBAYTAlVTMRMw
# EQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVN
# aWNyb3NvZnQgQ29ycG9yYXRpb24xJjAkBgNVBAMTHU1pY3Jvc29mdCBUaW1lLVN0
# YW1wIFBDQSAyMDEwAhMzAAAArIohvHrSm3L0AAAAAACsMBYEFOjObY5rI9l/qOHL
# cWYw9jQGQ4c4MA0GCSqGSIb3DQEBCwUABIIBAB0NMXE9Jtptcx1BFFLku0nKjFrc
# q+g8W4jO3MILf7l99QKEQBPF1D5ovyktOgKUA0z5htAQgVtndbh9WJvSbUU50FsN
# OSGtCtKk85Ar+ihM1PMU/GAkNT9rUYVdEwKJ240S8Be0R+cbORf/cGNaboqBdBv+
# SZE1zc2yxEPJiqplLOqzL7IkdC03I2Jt4nGL56ciFkZxIry+Xe4zDuOolmoHFsRf
# D0NmoJP4NxzuYE+IEcvcC8OrH36ZsJEGzEIRLp7ynyYam+xYimnZZIeBDDTCDnx3
# HAO92yA1jQegt3quVpwLkoxUwy0YpcNdVzRKM5YX9cD/gcr7xKEu9CXmTWo=
# SIG # End signature block
