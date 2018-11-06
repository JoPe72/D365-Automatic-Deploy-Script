[CmdletBinding()]
param
(
	# Directory to place logs. Passed in when upgrade is triggered through LCS.
    [string]
	$LogDir
)

function Get-ApplicationEnvironment
{
    $ErrorActionPreference = 'Stop'
    Import-Module "$PSScriptRoot\CommonRollbackUtilities.psm1" -DisableNameChecking
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
        [System.Reflection.Assembly]::Load($bytes)
    }
    catch
    {}
}

Start-Sleep -s 20

Import-Module "$PSScriptRoot\AOSCommon.psm1" -DisableNameChecking

$datetime=get-date -Format "MMddyyyyhhmmss"

if(!$LogDir)
{
    $LogDir = $PSScriptRoot
}

$log=join-path $LogDir "AutoRunDVT_AOS_$datetime.log"
  
Initialize-Log $log

$TestList = Get-ChildItem "$PSScriptRoot\DVT" -Filter 'Validate*.ps1'

$config = Get-ApplicationEnvironment

$ServiceName = $config.Infrastructure.ApplicationName
$endpointValue = $config.Infrastructure.HostUrl
$batchService = 'DynamicsAxBatch'
$serviceState = 'Running'
$appPoolState = 'Started'
$installPath = $config.Infrastructure.AOSWebRoot
$manifestPath = Join-Path $installPath 'web.config'
$appPoolName = $config.Infrastructure.ApplicationName
#Need to update the environmentassembly to add this value.
[xml]$WebConfig = Get-Content "$(join-path $installPath "web.config")"
$IsPrivateAOSInstance = $($WebConfig.configuration.appSettings.add | where { $_.key -eq 'Infrastructure.IsPrivateAOSInstance' }).value
$ValidateBatch = ([System.String]::IsNullOrWhiteSpace($IsPrivateAOSInstance) -or ![System.Convert]::ToBoolean($IsPrivateAOSInstance))

if (!$env:SERVICEDRIVE)
{
	Write-Log '%SERVICEDRIVE% was not defined. Exiting.' -Warning
	exit
}

Write-Log "Running DVT Process for $ServiceName"

$DiagnosticsPath = Join-Path -Path $env:SERVICEDRIVE -ChildPath "DynamicsDiagnostics\$ServiceName"

foreach ($test in $testList)
{
    Write-Log "Processing $test"    
    
    $DVTLocalRoot = Join-Path -Path $DiagnosticsPath -ChildPath ([System.IO.Path]::GetFileNameWithoutExtension($test))

    $DVTLocalBin = Join-Path $DVTLocalRoot "input"
    if(-not (Test-Path -Path $DVTLocalBin))
    {
        Write-Log "Creating DVT local bin at: '$DVTLocalBin'"
        New-Item -Path $DVTLocalBin -Type Directory -Force | Out-Null
    }   
        
    $DVTScript = Join-Path -Path "$PSScriptRoot\DVT" -ChildPath $test
    Write-Log "Copy DVT Script '$DVTScript' to $DVTLocalBin"
    Copy-Item -Path $DVTScript -Destination $DVTLocalBin -Recurse -Force | Out-Null

    Write-Log "Copy AosCommon.psm1 to DVTLocalBin"
    $AosCommon = Join-Path -Path $PSScriptRoot -ChildPath "AosCommon.psm1"
    Copy-Item -Path $AosCommon -Destination $DVTLocalBin -Recurse -Force | Out-Null

        
    [string]$DVTOutputBin = Join-Path -Path $DVTLocalRoot -ChildPath "Output"

    ####################################################################################
    ## DVT input XML Template
    ####################################################################################
    [xml]$xmlTemplate = "<?xml version=`"1.0`"?>
    <DVTParameters xmlns:xsi=`"http://www.w3.org/2001/XMLSchema-instance`" xmlns:xsd=`"http://www.w3.org/2001/XMLSchema`">
        <AosWebRootPath>$installPath</AosWebRootPath>
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
# MIIj8gYJKoZIhvcNAQcCoIIj4zCCI98CAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCAuX0mUGm59N7M2
# kgEW8Q7ZySBayxCPO9wQ3KjDFk/3aaCCDYIwggYAMIID6KADAgECAhMzAAAAww6b
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
# SEXAQsmbdlsKgEhr/Xmfwb1tbWrJUnMTDXpQzTGCFcYwghXCAgEBMIGVMH4xCzAJ
# BgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25k
# MR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xKDAmBgNVBAMTH01pY3Jv
# c29mdCBDb2RlIFNpZ25pbmcgUENBIDIwMTECEzMAAADDDpun2LLc9ywAAAAAAMMw
# DQYJYIZIAWUDBAIBBQCggbgwGQYJKoZIhvcNAQkDMQwGCisGAQQBgjcCAQQwHAYK
# KwYBBAGCNwIBCzEOMAwGCisGAQQBgjcCARUwLwYJKoZIhvcNAQkEMSIEIE976uvw
# nP+YL60IM+SoUAus5Kc9ut6joJ57z30ve/AoMEwGCisGAQQBgjcCAQwxPjA8oB6A
# HABBAHUAdABvAFIAdQBuAEQAVgBUAC4AcABzADGhGoAYaHR0cDovL3d3dy5taWNy
# b3NvZnQuY29tMA0GCSqGSIb3DQEBAQUABIIBAAC/Jb+57u+Or92F5DZnaGCBb9Dl
# 2Vt76wMEa43o2Amgh92B0hYJJUAxF/91uNVMehH5xjvvY8pP5tuBMMMpDt315nKS
# w1XyiwdO/8K3Jm46TpQVj0AVrgxeRkNVSCjSxHeN9F2wOQd/qOxGVYN1V8wAhf1u
# F7Hd1KjEX1fnruYEzyFkY0cEA5GNqFT9YabsvSgrUT8L2tX/pRmXCtqMtJQqY7JJ
# y86C3t2/14PY3dORB4m8AwqslrHCCbIfk8CFbiueF82v9Rl1rHbkgkO2GH+Qm4HS
# ls8g+Uyo0e16vbRHDYhaAL0ozD/c9N8aU7iU45hKt05aSGbzsJtVfGA53B6hghNG
# MIITQgYKKwYBBAGCNwMDATGCEzIwghMuBgkqhkiG9w0BBwKgghMfMIITGwIBAzEP
# MA0GCWCGSAFlAwQCAQUAMIIBPAYLKoZIhvcNAQkQAQSgggErBIIBJzCCASMCAQEG
# CisGAQQBhFkKAwEwMTANBglghkgBZQMEAgEFAAQgoJCusCp1kASgRAg3hVe2Lc5t
# 7yItpmHg/lmXaUT/QFICBlqygHQcQxgTMjAxODAzMjUyMTA1NTUuMDI3WjAHAgEB
# gAIB9KCBuKSBtTCBsjELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24x
# EDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlv
# bjEMMAoGA1UECxMDQU9DMScwJQYDVQQLEx5uQ2lwaGVyIERTRSBFU046MERFOC0y
# REM1LTNDQTkxJTAjBgNVBAMTHE1pY3Jvc29mdCBUaW1lLVN0YW1wIFNlcnZpY2Wg
# gg7KMIIGcTCCBFmgAwIBAgIKYQmBKgAAAAAAAjANBgkqhkiG9w0BAQsFADCBiDEL
# MAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1v
# bmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEyMDAGA1UEAxMpTWlj
# cm9zb2Z0IFJvb3QgQ2VydGlmaWNhdGUgQXV0aG9yaXR5IDIwMTAwHhcNMTAwNzAx
# MjEzNjU1WhcNMjUwNzAxMjE0NjU1WjB8MQswCQYDVQQGEwJVUzETMBEGA1UECBMK
# V2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0
# IENvcnBvcmF0aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0Eg
# MjAxMDCCASIwDQYJKoZIhvcNAQEBBQADggEPADCCAQoCggEBAKkdDbx3EYo6IOz8
# E5f1+n9plGt0VBDVpQoAgoX77XxoSyxfxcPlYcJ2tz5mK1vwFVMnBDEfQRsalR3O
# CROOfGEwWbEwRA/xYIiEVEMM1024OAizQt2TrNZzMFcmgqNFDdDq9UeBzb8kYDJY
# YEbyWEeGMoQedGFnkV+BVLHPk0ySwcSmXdFhE24oxhr5hoC732H8RsEnHSRnEnIa
# IYqvS2SJUGKxXf13Hz3wV3WsvYpCTUBR0Q+cBj5nf/VmwAOWRH7v0Ev9buWayrGo
# 8noqCjHw2k4GkbaICDXoeByw6ZnNPOcvRLqn9NxkvaQBwSAJk3jN/LzAyURdXhac
# AQVPIk0CAwEAAaOCAeYwggHiMBAGCSsGAQQBgjcVAQQDAgEAMB0GA1UdDgQWBBTV
# YzpcijGQ80N7fEYbxTNoWoVtVTAZBgkrBgEEAYI3FAIEDB4KAFMAdQBiAEMAQTAL
# BgNVHQ8EBAMCAYYwDwYDVR0TAQH/BAUwAwEB/zAfBgNVHSMEGDAWgBTV9lbLj+ii
# XGJo0T2UkFvXzpoYxDBWBgNVHR8ETzBNMEugSaBHhkVodHRwOi8vY3JsLm1pY3Jv
# c29mdC5jb20vcGtpL2NybC9wcm9kdWN0cy9NaWNSb29DZXJBdXRfMjAxMC0wNi0y
# My5jcmwwWgYIKwYBBQUHAQEETjBMMEoGCCsGAQUFBzAChj5odHRwOi8vd3d3Lm1p
# Y3Jvc29mdC5jb20vcGtpL2NlcnRzL01pY1Jvb0NlckF1dF8yMDEwLTA2LTIzLmNy
# dDCBoAYDVR0gAQH/BIGVMIGSMIGPBgkrBgEEAYI3LgMwgYEwPQYIKwYBBQUHAgEW
# MWh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9QS0kvZG9jcy9DUFMvZGVmYXVsdC5o
# dG0wQAYIKwYBBQUHAgIwNB4yIB0ATABlAGcAYQBsAF8AUABvAGwAaQBjAHkAXwBT
# AHQAYQB0AGUAbQBlAG4AdAAuIB0wDQYJKoZIhvcNAQELBQADggIBAAfmiFEN4sbg
# mD+BcQM9naOhIW+z66bM9TG+zwXiqf76V20ZMLPCxWbJat/15/B4vceoniXj+bzt
# a1RXCCtRgkQS+7lTjMz0YBKKdsxAQEGb3FwX/1z5Xhc1mCRWS3TvQhDIr79/xn/y
# N31aPxzymXlKkVIArzgPF/UveYFl2am1a+THzvbKegBvSzBEJCI8z+0DpZaPWSm8
# tv0E4XCfMkon/VWvL/625Y4zu2JfmttXQOnxzplmkIz/amJ/3cVKC5Em4jnsGUpx
# Y517IW3DnKOiPPp/fZZqkHimbdLhnPkd/DjYlPTGpQqWhqS9nhquBEKDuLWAmyI4
# ILUl5WTs9/S/fmNZJQ96LjlXdqJxqgaKD4kWumGnEcua2A5HmoDF0M2n0O99g/Dh
# O3EJ3110mCIIYdqwUB5vvfHhAN/nMQekkzr3ZUd46PioSKv33nJ+YWtvd6mBy6cJ
# rDm77MbL2IK0cs0d9LiFAR6A+xuJKlQ5slvayA1VmXqHczsI5pgt6o3gMy4SKfXA
# L1QnIffIrE7aKLixqduWsqdCosnPGUFN4Ib5KpqjEWYw07t0MkvfY3v1mYovG8ch
# r1m1rtxEPJdQcdeh0sVV42neV8HR3jDA/czmTfsNv11P6Z0eGTgvvM9YBS7vDaBQ
# NdrvCScc1bN+NR4Iuto229Nfj950iEkSMIIE2TCCA8GgAwIBAgITMwAAAKb9UuCL
# Fic/AAAAAAAApjANBgkqhkiG9w0BAQsFADB8MQswCQYDVQQGEwJVUzETMBEGA1UE
# CBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9z
# b2Z0IENvcnBvcmF0aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1TdGFtcCBQ
# Q0EgMjAxMDAeFw0xNjA5MDcxNzU2NTFaFw0xODA5MDcxNzU2NTFaMIGyMQswCQYD
# VQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEe
# MBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMQwwCgYDVQQLEwNBT0MxJzAl
# BgNVBAsTHm5DaXBoZXIgRFNFIEVTTjowREU4LTJEQzUtM0NBOTElMCMGA1UEAxMc
# TWljcm9zb2Z0IFRpbWUtU3RhbXAgU2VydmljZTCCASIwDQYJKoZIhvcNAQEBBQAD
# ggEPADCCAQoCggEBAMG4zZ4JJ7Rwi4X/HVpI0cDm52Fw9T2qVFvA3dWywBDrrkSa
# XKGJqa9hxVP0Amz9v2zL0fOSmhKgEW2FNz5x3dGg75oh3dhbJoOQDyZ/jR4e4+Mk
# Gy0y0bTvt8DNCkfY4E81x7sEOEUma2+o4oUms43097O8WfAiGJj/VzQYG07RtO/Y
# 7iqIbf3+HxVdKYFrdjkwxf99I6JEdBizCDTJucjXzYzvUU3g8w/vOrQt0rMl+b9k
# kxdUL+/IUWOVJbEso0hxyGeqcYfY16/K5xudoDkyxaZvahvVGHWUqap5Wazf247S
# ykmcd0Gq2DA5ZuSReNTtJ+mXw35ZRPotuWpxA90CAwEAAaOCARswggEXMB0GA1Ud
# DgQWBBQO4cVDySYb3MuHu9xMZtcGvNHAJjAfBgNVHSMEGDAWgBTVYzpcijGQ80N7
# fEYbxTNoWoVtVTBWBgNVHR8ETzBNMEugSaBHhkVodHRwOi8vY3JsLm1pY3Jvc29m
# dC5jb20vcGtpL2NybC9wcm9kdWN0cy9NaWNUaW1TdGFQQ0FfMjAxMC0wNy0wMS5j
# cmwwWgYIKwYBBQUHAQEETjBMMEoGCCsGAQUFBzAChj5odHRwOi8vd3d3Lm1pY3Jv
# c29mdC5jb20vcGtpL2NlcnRzL01pY1RpbVN0YVBDQV8yMDEwLTA3LTAxLmNydDAM
# BgNVHRMBAf8EAjAAMBMGA1UdJQQMMAoGCCsGAQUFBwMIMA0GCSqGSIb3DQEBCwUA
# A4IBAQCEICehBui41vySOspI1p3L0JaOswTayK6EX6s6ovTatWJWLwrBso8+tx8s
# YFp1Is5Hkd9BetmekDQro1gDDcOGxpbVuoXR42O0GVG9Z482ZezWGSaXB4z6Vpf+
# zFwZbXcGWOnRC68aqwsU908JUMMZa5jMIeMlhtZBN+tlLdlsbI9H/xdPvaVQNqOr
# wtx1cOFhWu9BGyoD0QZ5XsqmQxirV0STgcDrQqgTBdQYOJxbJjbcleszpbRwmvy9
# nW+kB6TfHkKnDzu5QbG2S7+EEkXZbs9YfLbjawuuAAbWpJa7ZxEvO1Dpkmz1mlnI
# h+SvZL5VLDNwNh+L9OrmnAE9pDsvoYIDdDCCAlwCAQEwgeKhgbikgbUwgbIxCzAJ
# BgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25k
# MR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xDDAKBgNVBAsTA0FPQzEn
# MCUGA1UECxMebkNpcGhlciBEU0UgRVNOOjBERTgtMkRDNS0zQ0E5MSUwIwYDVQQD
# ExxNaWNyb3NvZnQgVGltZS1TdGFtcCBTZXJ2aWNloiUKAQEwCQYFKw4DAhoFAAMV
# AH+gMGx8o+rq8oEE0zWi59zi1IU9oIHBMIG+pIG7MIG4MQswCQYDVQQGEwJVUzET
# MBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMV
# TWljcm9zb2Z0IENvcnBvcmF0aW9uMQwwCgYDVQQLEwNBT0MxJzAlBgNVBAsTHm5D
# aXBoZXIgTlRTIEVTTjoyNjY1LTRDM0YtQzVERTErMCkGA1UEAxMiTWljcm9zb2Z0
# IFRpbWUgU291cmNlIE1hc3RlciBDbG9jazANBgkqhkiG9w0BAQUFAAIFAN5idSQw
# IhgPMjAxODAzMjUxOTIxMDhaGA8yMDE4MDMyNjE5MjEwOFowdDA6BgorBgEEAYRZ
# CgQBMSwwKjAKAgUA3mJ1JAIBADAHAgEAAgI2GjAHAgEAAgIZXjAKAgUA3mPGpAIB
# ADA2BgorBgEEAYRZCgQCMSgwJjAMBgorBgEEAYRZCgMBoAowCAIBAAIDFuNgoQow
# CAIBAAIDB6EgMA0GCSqGSIb3DQEBBQUAA4IBAQCNBreYuKJVDtHK0JHmseBFWxVt
# iTgJDzV8zNy0m1zi8ei5O/dhI2ETZuqdjK3AmwGpchlKqaebwBDlI06voSqi8iKA
# /0PtmIk23sl5PvROoCaSRCb/F888Ide3pdX55WcbZugVkFBSsG3WO3v5GQ2FlUfC
# QYTSeBsr63aKOaGgd/kCunak17/9pkCntktqXmzmMpt58urzeaWfirMaqGBmSrSZ
# AQxByruE+c53r1igjS9ovVnjCJECHlNHZ4ovA+p0931fZfUeF4cHPrSHmVXi/7KM
# tLMNT73SW522+V9x+Ks1dC3W9Gi9HJpOjQGY6E2qrTIgsDu4wnrWx/S58XvUMYIC
# 9TCCAvECAQEwgZMwfDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24x
# EDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlv
# bjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRpbWUtU3RhbXAgUENBIDIwMTACEzMAAACm
# /VLgixYnPwAAAAAAAKYwDQYJYIZIAWUDBAIBBQCgggEyMBoGCSqGSIb3DQEJAzEN
# BgsqhkiG9w0BCRABBDAvBgkqhkiG9w0BCQQxIgQgVUHtX5h9u1SDEvGGZxEIJHut
# +K/0lEkqAukNOJR291AwgeIGCyqGSIb3DQEJEAIMMYHSMIHPMIHMMIGxBBR/oDBs
# fKPq6vKBBNM1oufc4tSFPTCBmDCBgKR+MHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQI
# EwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3Nv
# ZnQgQ29ycG9yYXRpb24xJjAkBgNVBAMTHU1pY3Jvc29mdCBUaW1lLVN0YW1wIFBD
# QSAyMDEwAhMzAAAApv1S4IsWJz8AAAAAAACmMBYEFHq4d/APb7GyNlNFEAo+35qx
# Q1ccMA0GCSqGSIb3DQEBCwUABIIBAEpyRfnkyMcU6Y3g+x6xhTyo9hHUPXUFtCPi
# umqVq3v/MpSxHuTnaAf6PnGrUTn9t+AnSiwzgBSp9swSSNyVT3ZFq4mzS60PROxw
# Dn/Z3Pc3Pv23y3idqS+yf0l64NrgtKSBtOYCdF0WK5tI4zBPeIMpZ4YFfqp1az+A
# GCyDNwdtLj9yY6O70Q8XdVQemsqj+N57cr5EXzaB8WZb+i4th0iNrAdn/8oskI9Q
# 8uL4r70POjO7nSsKzUuL/ff22pZbNKiIrgW6vo1e4vyfLKFkxnISL8S+xUAfRD5u
# UtjT7u5Yyir69T/2Dw0KRByXWdF8KAZKbfp5Jd+24v1XHPSBKJ4=
# SIG # End signature block
