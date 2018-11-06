﻿[CmdletBinding()]
param
(
    [Parameter(Mandatory=$false)]
    [string]$LogDir
)


Import-Module "$PSScriptRoot\AosEnvironmentUtilities.psm1" -Force -DisableNameChecking

$ErrorActionPreference = "stop"

$metadatadir = $(Get-AOSPackageDirectory)

$deltaSyncFolder = Join-Path "$(split-Path -parent $metadatadir)"  "DeltaSync"
$deltaSyncOutputSecurityMD = Join-Path $deltaSyncFolder  "DeltaSyncSecurityMD.xml"
$deltaSyncOutputTableMD = Join-Path $deltaSyncFolder  "DeltaSyncTableMD.xml"
$deltaSyncOutputEdtMD = Join-Path $deltaSyncFolder  "DeltaSyncEdtMD.xml"
$comparerDllPath = "$(split-Path -parent $PSScriptRoot)" | Split-Path -Parent


[System.Reflection.Assembly]::LoadFile("$comparerDllPath\Microsoft.Dynamics.AXCreateDeployablePackageBase.dll") >$null
        
    
$SecurityMdFileIdentical = [Microsoft.Dynamics.AXCreateDeployablePackageBase.DirectoryProcessing]::CustomDirectoryCompareIsIdentical($deltaSyncFolder,$metadatadir, "*AXSecurity*.md", $deltaSyncOutputSecurityMD  )
$TableMdFileIdentical = [Microsoft.Dynamics.AXCreateDeployablePackageBase.DirectoryProcessing]::CustomDirectoryCompareIsIdentical($deltaSyncFolder,$metadatadir, "*AXTable*.md", $deltaSyncOutputTableMD  )
$EdtMdFileIdentical = [Microsoft.Dynamics.AXCreateDeployablePackageBase.DirectoryProcessing]::CustomDirectoryCompareIsIdentical($deltaSyncFolder,$metadatadir, "*AXEdt*.md", $deltaSyncOutputEdtMD  )

$noSchemaImpactFlag = $(Join-Path $deltaSyncFolder  "noSchemaImpactMDChangeFound.xml")

if(($SecurityMdFileIdentical -eq $true) -and
($TableMdFileIdentical -eq $true) -and
($EdtMdFileIdentical -eq $true))
{
    Copy-Item $deltaSyncOutputTableMD -Destination $noSchemaImpactFlag
    Write-Output "No Schema Change detected, performing delta DbSync operation."
}
elseif(Test-Path $noSchemaImpactFlag)
{
    Remove-Item $noSchemaImpactFlag
}

$deploymentSetupParameter = "-setupmode servicesync -syncmode fullall"

if(!$LogDir)
{
    $LogDir = $PSScriptRoot
}

$logfile = Join-Path $LogDir "dbsync.log"
$errorfile = Join-Path $LogDir "dbsync.error.log"

$deploySetupPs1 = "$PSScriptRoot\TriggerDeploymentSetupEngine.ps1"

invoke-Expression "$deploySetupPs1 -deploymentSetupParameter: `"$deploymentSetupParameter`" -logfile:`"$logfile`" -errorfile:`"$errorfile`""

Write-Output "DbSync completed."

#creating AX ping service user
$deploymentSetupParameter = "-setupmode runstaticxppmethod -classname AxPingHelper -methodname createServiceUser"
$logfile = Join-Path $LogDir "createAXPingServiceUser.log"
$errorfile = Join-Path $LogDir "createAXPingServiceUser.error.log"

try
{
    invoke-Expression "$deploySetupPs1 -deploymentSetupParameter: `"$deploymentSetupParameter`" -logfile:`"$logfile`" -errorfile:`"$errorfile`""
}
catch
{
    $createAXPingServiceUserError = Get-Content $errorfile
    if ($createAXPingServiceUserError -ne $null) 
    {
        if($createAXPingServiceUserError -like "*Couldn't find id for class AxPingHelper*")
        {
            Write-Output "AXPulse Module not found, skipping create AX Ping service user operation"
            return
        }
        throw $createAXPingServiceUserError
    }
}


# SIG # Begin signature block
# MIIj8QYJKoZIhvcNAQcCoIIj4jCCI94CAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCD3CZp1F/vHFYxm
# c4uYhbzbgdFXiHdek1se2UlZvZiRYaCCDYIwggYAMIID6KADAgECAhMzAAAAww6b
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
# SEXAQsmbdlsKgEhr/Xmfwb1tbWrJUnMTDXpQzTGCFcUwghXBAgEBMIGVMH4xCzAJ
# BgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25k
# MR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xKDAmBgNVBAMTH01pY3Jv
# c29mdCBDb2RlIFNpZ25pbmcgUENBIDIwMTECEzMAAADDDpun2LLc9ywAAAAAAMMw
# DQYJYIZIAWUDBAIBBQCggbgwGQYJKoZIhvcNAQkDMQwGCisGAQQBgjcCAQQwHAYK
# KwYBBAGCNwIBCzEOMAwGCisGAQQBgjcCARUwLwYJKoZIhvcNAQkEMSIEIIFgZVQU
# 69TnzwtBlRcFTEmEboY7qltL1VOu0Sc6k9IcMEwGCisGAQQBgjcCAQwxPjA8oB6A
# HABBAHUAdABvAEQAQgBTAHkAbgBjAC4AcABzADGhGoAYaHR0cDovL3d3dy5taWNy
# b3NvZnQuY29tMA0GCSqGSIb3DQEBAQUABIIBAIZTPGrYu7c+SKT6lkgaZbycQUgy
# 0e/cTFL6Al7JobHRcTVceelz4nAoKHLgopbpUZi3KV+46DJeslNbQJOo2//xiU9l
# PwSsWzDyGviEa1rtM3gfK1/bKE9TSOQ54FqvDeXROpNWW8ZOFWENj+Fl6BlytGEp
# mUwGsCSGA6ORqLnOSBSPH3mEVvqV5pDOsvla3bLRYKpHGlGAkKu/SCgOhlp2VFgJ
# LUYQ8S8dyQHs8zjKYEw7eQsnPC9phlW8NUWkJfzrvC498onk7ZAomYFq14CDQkdB
# 9bCFglGBEAOGSQ3QgYDRI2KRH4+ohyoOE+w71IxCidHcZ05lfhX4okYNqPehghNF
# MIITQQYKKwYBBAGCNwMDATGCEzEwghMtBgkqhkiG9w0BBwKgghMeMIITGgIBAzEP
# MA0GCWCGSAFlAwQCAQUAMIIBOgYLKoZIhvcNAQkQAQSgggEpBIIBJTCCASECAQEG
# CisGAQQBhFkKAwEwMTANBglghkgBZQMEAgEFAAQgwv8kXkD65bJLNpQDXfCuA2UW
# 5FkW1OX/lMN7uL1J2x8CBlqyr2CzCxgSMjAxODAzMjUyMTA1NTEuMzlaMAcCAQGA
# AgH0oIG3pIG0MIGxMQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQ
# MA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9u
# MQwwCgYDVQQLEwNBT0MxJjAkBgNVBAsTHVRoYWxlcyBUU1MgRVNOOjk2RkYtNEJD
# NS1BN0RDMSUwIwYDVQQDExxNaWNyb3NvZnQgVGltZS1TdGFtcCBTZXJ2aWNloIIO
# yzCCBnEwggRZoAMCAQICCmEJgSoAAAAAAAIwDQYJKoZIhvcNAQELBQAwgYgxCzAJ
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
# 7wknHNWzfjUeCLraNtvTX4/edIhJEjCCBNgwggPAoAMCAQICEzMAAAC2i0dDssyt
# HwQAAAAAALYwDQYJKoZIhvcNAQELBQAwfDELMAkGA1UEBhMCVVMxEzARBgNVBAgT
# Cldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29m
# dCBDb3Jwb3JhdGlvbjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRpbWUtU3RhbXAgUENB
# IDIwMTAwHhcNMTcxMDAyMjMwMDUyWhcNMTkwMTAyMjMwMDUyWjCBsTELMAkGA1UE
# BhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAc
# BgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEMMAoGA1UECxMDQU9DMSYwJAYD
# VQQLEx1UaGFsZXMgVFNTIEVTTjo5NkZGLTRCQzUtQTdEQzElMCMGA1UEAxMcTWlj
# cm9zb2Z0IFRpbWUtU3RhbXAgU2VydmljZTCCASIwDQYJKoZIhvcNAQEBBQADggEP
# ADCCAQoCggEBANiJZxdISwi3RBuTEcM6z25BQKaoXGJjslsjRDM19Z7d/cByy4tJ
# bDB7IQBlkpYpRKcMe1M/WU4ge5ZuslgQ7649EYd8NWYqb7X8r9DCSnKtP84Q49cQ
# CcXlEuNfzmDo2/hqSW0/JaBpUaej1iz8Q+FCCUo0PVRISiS/fOHdpmcL3myxUrjH
# yNIRmyZ0/px3YBpmYywMP9gBBN++eTMKyeo/u6UUdjWHEtl3XTIW8e7y921gXSh9
# J2ZpHUkX5JXt+A7+uGeb/7y67R3XpPB7CbAoBGpKcxEk1fPKNRNsVsXGHHDWE7Wz
# Rga0LKpJROeYlQ8Vu9OlLXkIAYAfDaZMwTECAwEAAaOCARswggEXMB0GA1UdDgQW
# BBTzbcKQAScg2o8zHMBfaGrfgQOF0DAfBgNVHSMEGDAWgBTVYzpcijGQ80N7fEYb
# xTNoWoVtVTBWBgNVHR8ETzBNMEugSaBHhkVodHRwOi8vY3JsLm1pY3Jvc29mdC5j
# b20vcGtpL2NybC9wcm9kdWN0cy9NaWNUaW1TdGFQQ0FfMjAxMC0wNy0wMS5jcmww
# WgYIKwYBBQUHAQEETjBMMEoGCCsGAQUFBzAChj5odHRwOi8vd3d3Lm1pY3Jvc29m
# dC5jb20vcGtpL2NlcnRzL01pY1RpbVN0YVBDQV8yMDEwLTA3LTAxLmNydDAMBgNV
# HRMBAf8EAjAAMBMGA1UdJQQMMAoGCCsGAQUFBwMIMA0GCSqGSIb3DQEBCwUAA4IB
# AQAv19XqvpiOeBy6wypDpE1MzGUzKEcV5TqW3hbl1zq7PTwqQMYjIrhA2dj8UWRS
# ETiDxu9K+cIIKZmBLpaFZTKcReDsqB2Gmmsp3bixBP+33/lKKNsQ8BIszJf52bSq
# KGLIsCqD66X10OgK4epSQs2sRAcpGe5eMZY/+HW35djuRHzMj9lHDNbA6OsQjx/K
# jbBeH6iOanurNuT18zMMdd8pL2TInt3bfQbDGdY0k2kPB1pLoFSVwB55TZFqKJen
# 1UZUdJu5afUeAzqcZjq3aOvMJ8IDixroQQWFYZJJkpIB+XNk+a0M/t3d0r8fYr66
# 0odXElNAB4TbTMOuWre2rGRIoYIDdjCCAl4CAQEwgeGhgbekgbQwgbExCzAJBgNV
# BAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4w
# HAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xDDAKBgNVBAsTA0FPQzEmMCQG
# A1UECxMdVGhhbGVzIFRTUyBFU046OTZGRi00QkM1LUE3REMxJTAjBgNVBAMTHE1p
# Y3Jvc29mdCBUaW1lLVN0YW1wIFNlcnZpY2WiJQoBATAJBgUrDgMCGgUAAxUA/xYr
# 7xVcs9W1liu+CEsh/E10AAGggcEwgb6kgbswgbgxCzAJBgNVBAYTAlVTMRMwEQYD
# VQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNy
# b3NvZnQgQ29ycG9yYXRpb24xDDAKBgNVBAsTA0FPQzEnMCUGA1UECxMebkNpcGhl
# ciBOVFMgRVNOOjI2NjUtNEMzRi1DNURFMSswKQYDVQQDEyJNaWNyb3NvZnQgVGlt
# ZSBTb3VyY2UgTWFzdGVyIENsb2NrMA0GCSqGSIb3DQEBBQUAAgUA3mHSPTAiGA8y
# MDE4MDMyNTA3NDYwNVoYDzIwMTgwMzI2MDc0NjA1WjB3MD0GCisGAQQBhFkKBAEx
# LzAtMAoCBQDeYdI9AgEAMAoCAQACAgg8AgH/MAcCAQACAhYYMAoCBQDeYyO9AgEA
# MDYGCisGAQQBhFkKBAIxKDAmMAwGCisGAQQBhFkKAwGgCjAIAgEAAgMW42ChCjAI
# AgEAAgMehIAwDQYJKoZIhvcNAQEFBQADggEBAIe0VM1/1WGZ66wiWwoJdqnXsQLO
# wNkAZTOKqpGeLYOWoSHPolJ6HJJwf/kFJdy2PG8uDk3abUVcmB7QZRtaea9CpycE
# nFQeU+WsPSdydjUhBY9R274O+YUc5uUnY9y5DFTQTPrlYiIL2IS+gbbBeusO1QSg
# 1SUz6JmkwkVz0hwOtICmnDWMEBGwrRP663h++VWYEbSarMFdt816KZL2CcmgAGFW
# qYadAXVXRoo4jF9TGn5983HflM6ASq+YgMW5BuZhjKR3KdPovLuB3Yht2ciW80Vs
# HJBkSGAgP7X4Qe8Tv4ccqdAOjB1OpeOfP2Ta6/kjFNSJ34ErsKuZcNtbm7ExggL1
# MIIC8QIBATCBkzB8MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQ
# MA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9u
# MSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0EgMjAxMAITMwAAALaL
# R0OyzK0fBAAAAAAAtjANBglghkgBZQMEAgEFAKCCATIwGgYJKoZIhvcNAQkDMQ0G
# CyqGSIb3DQEJEAEEMC8GCSqGSIb3DQEJBDEiBCDpFkpq8FctKAfWsaulScc7vAby
# uqgxaiCF4qa15ev40zCB4gYLKoZIhvcNAQkQAgwxgdIwgc8wgcwwgbEEFP8WK+8V
# XLPVtZYrvghLIfxNdAABMIGYMIGApH4wfDELMAkGA1UEBhMCVVMxEzARBgNVBAgT
# Cldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29m
# dCBDb3Jwb3JhdGlvbjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRpbWUtU3RhbXAgUENB
# IDIwMTACEzMAAAC2i0dDssytHwQAAAAAALYwFgQULhb4FpkwxJhZ0fMHreuAGLhi
# yHswDQYJKoZIhvcNAQELBQAEggEA2DdAGDOo2RtxUOyhvIac/IPJbqLDgxBwzesw
# 2MxFcaJmrUql9IZrUJWJNADgQpu8gAomqP+5txjzTKm6689TWvjkMCUUP0sZeXY+
# wqgonE7XX47ffanjmwRHgO1F3A2iQ7045DrJBqOj+meXlVLvbk5V3tug0Cu4Unwu
# 9Qlf+nPYc4WxTV3GwcJZt8kOv9m8o5D6nx9spFR3JL20RyXvWvm9R85iGe2goMzE
# J963oU/yAC+qM+r5iPTN1sNg/e6u2Ru08PI4gHiUwfEnnOC6KyX3Odosh5ZlHEXH
# tkaiJNWnfZBVbN8BGzplyVTfGwtxvuB+opcrNYPB+nIC9hpKhQ==
# SIG # End signature block
