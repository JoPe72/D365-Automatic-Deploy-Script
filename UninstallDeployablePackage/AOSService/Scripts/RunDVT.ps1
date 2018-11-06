[CmdletBinding()]
Param
(
   [Parameter(Mandatory = $true)]
   [string]$config,
   [Parameter(Mandatory = $true)]
   [string]$log,
   [Parameter(Mandatory = $true)]
   [string]$testList
)

Import-Module "$PSScriptRoot\AosCommon.psm1" -Force -DisableNameChecking
Initialize-Log $log

Write-Log "Decoding settings"
$settings = Decode-Settings $config

[string]$parentDir = Split-Path -Path $PSCommandPath -Parent 
$ServiceName = $settings.'Infrastructure.ApplicationName'
$endpointValue = $settings.'Infrastructure.HostUrl'
$batchService = 'DynamicsAxBatch'
$serviceState = 'Running'
$appPoolState = 'Started'
$installPath = $settings.'Infrastructure.WebRoot'
$manifestPath = Join-Path $installPath 'web.config'
$appPoolName = $settings.'Infrastructure.ApplicationName'
$IsPrivateAOSInstance = $settings.'Infrastructure.IsPrivateAOSInstance'
$ValidateBatch = ([System.String]::IsNullOrWhiteSpace($IsPrivateAOSInstance) -or ![System.Convert]::ToBoolean($IsPrivateAOSInstance))

Write-Log "Running DVT Process for $ServiceName"

$DiagnosticsPath = Join-Path -Path $env:SERVICEDRIVE -ChildPath "DynamicsDiagnostics\$ServiceName"

foreach ($test in $testList.Split(";"))
{
    Write-Log "Processing $test"    
    
    $DVTLocalRoot = Join-Path -Path $DiagnosticsPath -ChildPath ([System.IO.Path]::GetFileNameWithoutExtension($test))

    $DVTLocalBin = Join-Path $DVTLocalRoot "input"
    if(-not (Test-Path -Path $DVTLocalBin))
    {
        Write-Log "Creating DVT local bin at: '$DVTLocalBin'"
        New-Item -Path $DVTLocalBin -Type Directory -Force | Out-Null
    }   
        
    $DVTScript = Join-Path -Path $parentDir -ChildPath $test
    Write-Log "Copy DVT Script '$DVTScript' to $DVTLocalBin"
    Copy-Item -Path $DVTScript -Destination $DVTLocalBin -Recurse -Force | Out-Null

    Write-Log "Copy AosCommon.psm1 to DVTLocalBin"
    $AosCommon = Join-Path -Path $parentDir -ChildPath "AosCommon.psm1"
    Copy-Item -Path $AosCommon -Destination $DVTLocalBin -Recurse -Force | Out-Null

        
    [string]$DVTOutputBin = Join-Path -Path $DVTLocalRoot -ChildPath "Output"

    ####################################################################################
    ## DVT input XML Template
    ####################################################################################
    [xml]$xmlTemplate = "<?xml version=`"1.0`"?>
    <DVTParameters xmlns:xsi=`"http://www.w3.org/2001/XMLSchema-instance`" xmlns:xsd=`"http://www.w3.org/2001/XMLSchema`">
        <AosWebRootPath>$($settings.'Infrastructure.WebRoot')</AosWebRootPath>
        <ServiceName>$ServiceName</ServiceName>        
        <OutputPath>$DVTOutputBin</OutputPath>
        <EndPoint>$endpointValue</EndPoint>
        <InstallPath>$installPath</InstallPath>
        <ManifestPath>$manifestPath</ManifestPath>
        <BatchService>$batchService</BatchService>
        <ServiceState>$serviceState</ServiceState>
        <AppPoolName>$appPoolName</AppPoolName>
        <AppPoolState>$appPoolState</AppPoolState>
        <ValidateBatch>$ValidateBatch</ValidateBatch>
    </DVTParameters>"

    $XMLInputPath = Join-Path -Path $DVTLocalBin -ChildPath "$([System.IO.Path]::GetFileNameWithoutExtension($test)).xml"
    Write-Log "Executing DVT XML at: $XMLInputPath"
    $xmlTemplate.InnerXml | Out-File -FilePath $XMLInputPath -Force -Encoding utf8
    

    ####################################################################################
    ## Execute DVT Script
    ####################################################################################
    try
    {
        $DVTLocalScript = Join-Path -Path $DVTLocalBin -ChildPath $test
        if(Test-Path -Path $DVTLocalScript)
        {
            Write-Log "Executing DVT Script: $DVTLocalScript"
            $commandArgs = @{
                "InputXML" = $XMLInputPath;                
                "Log" = $Log
            }
    
            & $DVTLocalScript @commandArgs
        }
        else
        {
            throw "$DVTLocalScript was not found."
        }
    }
    catch
    {     
        Write-Exception $_       
        throw "DVT Script Failed, see $log for details."
    }
}    
# SIG # Begin signature block
# MIIj6gYJKoZIhvcNAQcCoIIj2zCCI9cCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCDGce6kuddSnHNf
# vY6i4Ge8+ZjSR48b3Jc6wHAN/09Wk6CCDYIwggYAMIID6KADAgECAhMzAAAAww6b
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
# SEXAQsmbdlsKgEhr/Xmfwb1tbWrJUnMTDXpQzTGCFb4wghW6AgEBMIGVMH4xCzAJ
# BgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25k
# MR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xKDAmBgNVBAMTH01pY3Jv
# c29mdCBDb2RlIFNpZ25pbmcgUENBIDIwMTECEzMAAADDDpun2LLc9ywAAAAAAMMw
# DQYJYIZIAWUDBAIBBQCggbAwGQYJKoZIhvcNAQkDMQwGCisGAQQBgjcCAQQwHAYK
# KwYBBAGCNwIBCzEOMAwGCisGAQQBgjcCARUwLwYJKoZIhvcNAQkEMSIEIGt+aZv9
# ai+3B+Kq2hws1vcJl0QBRwooWpLsppTcj/ivMEQGCisGAQQBgjcCAQwxNjA0oBaA
# FABSAHUAbgBEAFYAVAAuAHAAcwAxoRqAGGh0dHA6Ly93d3cubWljcm9zb2Z0LmNv
# bTANBgkqhkiG9w0BAQEFAASCAQBARB8uvMqPmOfeNO7NUaMsrk2ci/WLMMKyUESv
# cBzot41SiVQZIwc++mHxEMIdkzyQ0gPjhhMloJ81bWNN4iofs/NCQF3emHufVigR
# I1SPICghh7JGKOK+IIR5SwCOpB4eH1bguF350ystK5WuG9ec8rOdcxPkarMfa/qM
# +EScrNYM4BA3mgz+vxfLEU7ZZEAc/sjUuYbY4Xlgev1AtKgMg2wkFGHcHAtxEWKz
# fG/4QcmBl4xanPRndlhDU/O1p6z+1ecgmz46sBpwm+b4cb0odlGiESJzPm8F0wN7
# UX3W+dozM4SvXKNOBkrAL2jXLaiiaHp1nKHpzrvbEaX+td3ZoYITRjCCE0IGCisG
# AQQBgjcDAwExghMyMIITLgYJKoZIhvcNAQcCoIITHzCCExsCAQMxDzANBglghkgB
# ZQMEAgEFADCCATsGCyqGSIb3DQEJEAEEoIIBKgSCASYwggEiAgEBBgorBgEEAYRZ
# CgMBMDEwDQYJYIZIAWUDBAIBBQAEIMY6wfC4cVgbEX/e4MgsyoPQd4dBRXYItfvA
# d1DSjtygAgZasq9gsxUYEzIwMTgwMzI1MjEwNTUyLjI4OVowBwIBAYACAfSggbek
# gbQwgbExCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQH
# EwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xDDAKBgNV
# BAsTA0FPQzEmMCQGA1UECxMdVGhhbGVzIFRTUyBFU046OTZGRi00QkM1LUE3REMx
# JTAjBgNVBAMTHE1pY3Jvc29mdCBUaW1lLVN0YW1wIFNlcnZpY2Wggg7LMIIGcTCC
# BFmgAwIBAgIKYQmBKgAAAAAAAjANBgkqhkiG9w0BAQsFADCBiDELMAkGA1UEBhMC
# VVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNV
# BAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEyMDAGA1UEAxMpTWljcm9zb2Z0IFJv
# b3QgQ2VydGlmaWNhdGUgQXV0aG9yaXR5IDIwMTAwHhcNMTAwNzAxMjEzNjU1WhcN
# MjUwNzAxMjE0NjU1WjB8MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3Rv
# bjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0
# aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0EgMjAxMDCCASIw
# DQYJKoZIhvcNAQEBBQADggEPADCCAQoCggEBAKkdDbx3EYo6IOz8E5f1+n9plGt0
# VBDVpQoAgoX77XxoSyxfxcPlYcJ2tz5mK1vwFVMnBDEfQRsalR3OCROOfGEwWbEw
# RA/xYIiEVEMM1024OAizQt2TrNZzMFcmgqNFDdDq9UeBzb8kYDJYYEbyWEeGMoQe
# dGFnkV+BVLHPk0ySwcSmXdFhE24oxhr5hoC732H8RsEnHSRnEnIaIYqvS2SJUGKx
# Xf13Hz3wV3WsvYpCTUBR0Q+cBj5nf/VmwAOWRH7v0Ev9buWayrGo8noqCjHw2k4G
# kbaICDXoeByw6ZnNPOcvRLqn9NxkvaQBwSAJk3jN/LzAyURdXhacAQVPIk0CAwEA
# AaOCAeYwggHiMBAGCSsGAQQBgjcVAQQDAgEAMB0GA1UdDgQWBBTVYzpcijGQ80N7
# fEYbxTNoWoVtVTAZBgkrBgEEAYI3FAIEDB4KAFMAdQBiAEMAQTALBgNVHQ8EBAMC
# AYYwDwYDVR0TAQH/BAUwAwEB/zAfBgNVHSMEGDAWgBTV9lbLj+iiXGJo0T2UkFvX
# zpoYxDBWBgNVHR8ETzBNMEugSaBHhkVodHRwOi8vY3JsLm1pY3Jvc29mdC5jb20v
# cGtpL2NybC9wcm9kdWN0cy9NaWNSb29DZXJBdXRfMjAxMC0wNi0yMy5jcmwwWgYI
# KwYBBQUHAQEETjBMMEoGCCsGAQUFBzAChj5odHRwOi8vd3d3Lm1pY3Jvc29mdC5j
# b20vcGtpL2NlcnRzL01pY1Jvb0NlckF1dF8yMDEwLTA2LTIzLmNydDCBoAYDVR0g
# AQH/BIGVMIGSMIGPBgkrBgEEAYI3LgMwgYEwPQYIKwYBBQUHAgEWMWh0dHA6Ly93
# d3cubWljcm9zb2Z0LmNvbS9QS0kvZG9jcy9DUFMvZGVmYXVsdC5odG0wQAYIKwYB
# BQUHAgIwNB4yIB0ATABlAGcAYQBsAF8AUABvAGwAaQBjAHkAXwBTAHQAYQB0AGUA
# bQBlAG4AdAAuIB0wDQYJKoZIhvcNAQELBQADggIBAAfmiFEN4sbgmD+BcQM9naOh
# IW+z66bM9TG+zwXiqf76V20ZMLPCxWbJat/15/B4vceoniXj+bzta1RXCCtRgkQS
# +7lTjMz0YBKKdsxAQEGb3FwX/1z5Xhc1mCRWS3TvQhDIr79/xn/yN31aPxzymXlK
# kVIArzgPF/UveYFl2am1a+THzvbKegBvSzBEJCI8z+0DpZaPWSm8tv0E4XCfMkon
# /VWvL/625Y4zu2JfmttXQOnxzplmkIz/amJ/3cVKC5Em4jnsGUpxY517IW3DnKOi
# PPp/fZZqkHimbdLhnPkd/DjYlPTGpQqWhqS9nhquBEKDuLWAmyI4ILUl5WTs9/S/
# fmNZJQ96LjlXdqJxqgaKD4kWumGnEcua2A5HmoDF0M2n0O99g/DhO3EJ3110mCII
# YdqwUB5vvfHhAN/nMQekkzr3ZUd46PioSKv33nJ+YWtvd6mBy6cJrDm77MbL2IK0
# cs0d9LiFAR6A+xuJKlQ5slvayA1VmXqHczsI5pgt6o3gMy4SKfXAL1QnIffIrE7a
# KLixqduWsqdCosnPGUFN4Ib5KpqjEWYw07t0MkvfY3v1mYovG8chr1m1rtxEPJdQ
# cdeh0sVV42neV8HR3jDA/czmTfsNv11P6Z0eGTgvvM9YBS7vDaBQNdrvCScc1bN+
# NR4Iuto229Nfj950iEkSMIIE2DCCA8CgAwIBAgITMwAAALaLR0OyzK0fBAAAAAAA
# tjANBgkqhkiG9w0BAQsFADB8MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGlu
# Z3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBv
# cmF0aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0EgMjAxMDAe
# Fw0xNzEwMDIyMzAwNTJaFw0xOTAxMDIyMzAwNTJaMIGxMQswCQYDVQQGEwJVUzET
# MBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMV
# TWljcm9zb2Z0IENvcnBvcmF0aW9uMQwwCgYDVQQLEwNBT0MxJjAkBgNVBAsTHVRo
# YWxlcyBUU1MgRVNOOjk2RkYtNEJDNS1BN0RDMSUwIwYDVQQDExxNaWNyb3NvZnQg
# VGltZS1TdGFtcCBTZXJ2aWNlMIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKC
# AQEA2IlnF0hLCLdEG5MRwzrPbkFApqhcYmOyWyNEMzX1nt39wHLLi0lsMHshAGWS
# lilEpwx7Uz9ZTiB7lm6yWBDvrj0Rh3w1Zipvtfyv0MJKcq0/zhDj1xAJxeUS41/O
# YOjb+GpJbT8loGlRp6PWLPxD4UIJSjQ9VEhKJL984d2mZwvebLFSuMfI0hGbJnT+
# nHdgGmZjLAw/2AEE3755MwrJ6j+7pRR2NYcS2XddMhbx7vL3bWBdKH0nZmkdSRfk
# le34Dv64Z5v/vLrtHdek8HsJsCgEakpzESTV88o1E2xWxcYccNYTtbNGBrQsqklE
# 55iVDxW706UteQgBgB8NpkzBMQIDAQABo4IBGzCCARcwHQYDVR0OBBYEFPNtwpAB
# JyDajzMcwF9oat+BA4XQMB8GA1UdIwQYMBaAFNVjOlyKMZDzQ3t8RhvFM2hahW1V
# MFYGA1UdHwRPME0wS6BJoEeGRWh0dHA6Ly9jcmwubWljcm9zb2Z0LmNvbS9wa2kv
# Y3JsL3Byb2R1Y3RzL01pY1RpbVN0YVBDQV8yMDEwLTA3LTAxLmNybDBaBggrBgEF
# BQcBAQROMEwwSgYIKwYBBQUHMAKGPmh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9w
# a2kvY2VydHMvTWljVGltU3RhUENBXzIwMTAtMDctMDEuY3J0MAwGA1UdEwEB/wQC
# MAAwEwYDVR0lBAwwCgYIKwYBBQUHAwgwDQYJKoZIhvcNAQELBQADggEBAC/X1eq+
# mI54HLrDKkOkTUzMZTMoRxXlOpbeFuXXOrs9PCpAxiMiuEDZ2PxRZFIROIPG70r5
# wggpmYEuloVlMpxF4OyoHYaaaynduLEE/7ff+Uoo2xDwEizMl/nZtKooYsiwKoPr
# pfXQ6Arh6lJCzaxEBykZ7l4xlj/4dbfl2O5EfMyP2UcM1sDo6xCPH8qNsF4fqI5q
# e6s25PXzMwx13ykvZMie3dt9BsMZ1jSTaQ8HWkugVJXAHnlNkWool6fVRlR0m7lp
# 9R4DOpxmOrdo68wnwgOLGuhBBYVhkkmSkgH5c2T5rQz+3d3Svx9ivrrSh1cSU0AH
# hNtMw65at7asZEihggN2MIICXgIBATCB4aGBt6SBtDCBsTELMAkGA1UEBhMCVVMx
# EzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoT
# FU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEMMAoGA1UECxMDQU9DMSYwJAYDVQQLEx1U
# aGFsZXMgVFNTIEVTTjo5NkZGLTRCQzUtQTdEQzElMCMGA1UEAxMcTWljcm9zb2Z0
# IFRpbWUtU3RhbXAgU2VydmljZaIlCgEBMAkGBSsOAwIaBQADFQD/FivvFVyz1bWW
# K74ISyH8TXQAAaCBwTCBvqSBuzCBuDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldh
# c2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBD
# b3Jwb3JhdGlvbjEMMAoGA1UECxMDQU9DMScwJQYDVQQLEx5uQ2lwaGVyIE5UUyBF
# U046MjY2NS00QzNGLUM1REUxKzApBgNVBAMTIk1pY3Jvc29mdCBUaW1lIFNvdXJj
# ZSBNYXN0ZXIgQ2xvY2swDQYJKoZIhvcNAQEFBQACBQDeYdI9MCIYDzIwMTgwMzI1
# MDc0NjA1WhgPMjAxODAzMjYwNzQ2MDVaMHcwPQYKKwYBBAGEWQoEATEvMC0wCgIF
# AN5h0j0CAQAwCgIBAAICCDwCAf8wBwIBAAICFhgwCgIFAN5jI70CAQAwNgYKKwYB
# BAGEWQoEAjEoMCYwDAYKKwYBBAGEWQoDAaAKMAgCAQACAxbjYKEKMAgCAQACAx6E
# gDANBgkqhkiG9w0BAQUFAAOCAQEAh7RUzX/VYZnrrCJbCgl2qdexAs7A2QBlM4qq
# kZ4tg5ahIc+iUnocknB/+QUl3LY8by4OTdptRVyYHtBlG1p5r0KnJwScVB5T5aw9
# J3J2NSEFj1Hbvg75hRzm5Sdj3LkMVNBM+uViIgvYhL6BtsF66w7VBKDVJTPomaTC
# RXPSHA60gKacNYwQEbCtE/rreH75VZgRtJqswV23zXopkvYJyaAAYVaphp0BdVdG
# ijiMX1Mafn3zcd+UzoBKr5iAxbkG5mGMpHcp0+i8u4HdiG3ZyJbzRWwckGRIYCA/
# tfhB7xO/hxyp0A6MHU6l458/ZNrr+SMU1InfgSuwq5lw21ubsTGCAvUwggLxAgEB
# MIGTMHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQH
# EwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xJjAkBgNV
# BAMTHU1pY3Jvc29mdCBUaW1lLVN0YW1wIFBDQSAyMDEwAhMzAAAAtotHQ7LMrR8E
# AAAAAAC2MA0GCWCGSAFlAwQCAQUAoIIBMjAaBgkqhkiG9w0BCQMxDQYLKoZIhvcN
# AQkQAQQwLwYJKoZIhvcNAQkEMSIEIErXoc4NPD2EQLW8FHqyfLAD2TZb0FovJqMW
# 0dmXYCGDMIHiBgsqhkiG9w0BCRACDDGB0jCBzzCBzDCBsQQU/xYr7xVcs9W1liu+
# CEsh/E10AAEwgZgwgYCkfjB8MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGlu
# Z3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBv
# cmF0aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0EgMjAxMAIT
# MwAAALaLR0OyzK0fBAAAAAAAtjAWBBQuFvgWmTDEmFnR8wet64AYuGLIezANBgkq
# hkiG9w0BAQsFAASCAQCRA+GAFrQWq5MITwvdJxMQBpwlz3nM+eOziPat2dZsgHSp
# Qe8SnfhETEs0Jh2KQve3nSnuopIE0I3nXzSLkNtMwAo69kqF90NyIsqlNRF3ct2U
# 6ZN8gLXmBjlOlG4GMWIGD+Jpo4h9/t1PMfMDRMCYK0wBMT8PTbWRivDrULSl4gVI
# hk7w44omCAm94nqALXKoZJbrSFVmCbguQWZr00YMFL/yQWaxVW9rwHYPW3nqfRQT
# HWq31FGp5Rw+hH5chIvcvRv/Xy90v8bCyCcUY6I344NVWuZhT3jcBHwJKGlLh12J
# MlRCOUl0mT4+RcuX1ZtepOGCPWjdZ7RrM6gA43On
# SIG # End signature block
