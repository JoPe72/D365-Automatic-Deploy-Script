﻿
param
(
    [Parameter(Mandatory=$false)]
    [string]$LogDir,
    [Parameter(Mandatory=$false)]
    [switch] $useStaging = $false
)

Import-Module WebAdministration
Import-Module "$PSScriptRoot\CommonRollbackUtilities.psm1" -DisableNameChecking
Import-Module "$PSScriptRoot\AosEnvironmentUtilities.psm1" -Force -DisableNameChecking -Function Get-ALMPackageCopyPath


if (Test-Path "$($PSScriptRoot)\NonAdminDevToolsInterject.ps1")
{
    & "$PSScriptRoot\NonAdminDevToolsInterject.ps1"
}

$ErrorActionPreference = "stop"

if($useStaging)
{
    $webroot = join-path $(Get-AosServiceStagingPath) "webroot"
}
else
{
    $webroot = Get-AosWebSitePhysicalPath

    #stop aosservice again - this is simply a mitigation where customer manually restart machine or start service during middle of applying deployable package
    & "$PSScriptRoot\AutoStopAOS.ps1"

    StopMonitoring
}

$source = "$(split-Path -parent $PSScriptRoot)\Code" 

if([string]::IsNullOrWhiteSpace( $webroot ))
{
    throw "fail to find the webroot of AOS Service website, update aborted."
}

$exclude = @('*.config')
#region Update the AOS web root
Write-Output "updating AOS data at $webroot  $source"

Get-ChildItem -Path $source -Recurse -Exclude $exclude | Copy-Item -Force -Destination {
        if ($_.GetType() -eq [System.IO.FileInfo]) {
          Join-Path $webroot $_.FullName.Substring($source.length)
        } 
        else {
          Join-Path $webroot $_.Parent.FullName.Substring($source.length)
        }
    }
#endregion

#region Update SQL ODBC Driver
Write-Output "Install updated SQL ODBC driver if necessary."
invoke-expression "$PSScriptRoot\InstallUpdatedODBCDriver.ps1 -LogDir:`"$LogDir`""
#endregion

#region ALM Service clean copy removal
$ALMPackagesCopyPath = Get-ALMPackageCopyPath
if ($ALMPackagesCopyPath)
{
    $ALMPackagesCopyPath = Join-Path -Path $ALMPackagesCopyPath -ChildPath "Packages"
    if (Test-Path $ALMPackagesCopyPath)
    {
        Write-Output "Removing ALM Service copy of packages..."
        Invoke-Expression "cmd.exe /c rd /s /q $ALMPackagesCopyPath"
        if ($LastExitCode -ne 0)
        {
            throw [System.Exception] "Error removing ALM Service copy of packages"
        }
    }
}
#endregion

#region Remove module packages
if(Test-Path "$PSScriptRoot\AutoRemoveAosModule.ps1")
{
    Write-Output "Removing module packages..."
    invoke-Expression "$PSScriptRoot\AutoRemoveAosModule.ps1 -LogDir:`"$LogDir`""
}
#endregion

#region Update module packages
Write-Output "Installing module packages..."
if($useStaging)
{
    invoke-Expression "$PSScriptRoot\InstallMetadataPackages.ps1 -useStaging -LogDir:`"$LogDir`""
}
else
{
    invoke-Expression "$PSScriptRoot\InstallMetadataPackages.ps1 -LogDir:`"$LogDir`""
}
#endregion


StartMonitoring

# SIG # Begin signature block
# MIIkAwYJKoZIhvcNAQcCoIIj9DCCI/ACAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCAI7XrUvJXIi60R
# Xalgdue+QkxQFLGXEjBntQrHQroOoqCCDYIwggYAMIID6KADAgECAhMzAAAAww6b
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
# SEXAQsmbdlsKgEhr/Xmfwb1tbWrJUnMTDXpQzTGCFdcwghXTAgEBMIGVMH4xCzAJ
# BgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25k
# MR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xKDAmBgNVBAMTH01pY3Jv
# c29mdCBDb2RlIFNpZ25pbmcgUENBIDIwMTECEzMAAADDDpun2LLc9ywAAAAAAMMw
# DQYJYIZIAWUDBAIBBQCggcwwGQYJKoZIhvcNAQkDMQwGCisGAQQBgjcCAQQwHAYK
# KwYBBAGCNwIBCzEOMAwGCisGAQQBgjcCARUwLwYJKoZIhvcNAQkEMSIEIPbUw9sw
# Ap7F/zf1Bk+yT6x59BtFWN+krjKfcDXVdIYUMGAGCisGAQQBgjcCAQwxUjBQoDKA
# MABBAHUAdABvAFUAcABkAGEAdABlAEEATwBTAFMAZQByAHYAaQBjAGUALgBwAHMA
# MaEagBhodHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20wDQYJKoZIhvcNAQEBBQAEggEA
# P9yNjEzUIM1F/Rqx2sbX3iCqlNaCUYz18AkdnhcnHl3w3fHxFbGpCNd3ba9b9enk
# r0kPPseyZ60VFqv5b/jSoIYbGq4o641R61nC7ZqqaZbWJO31SG75D4ErQfU4WHSH
# Oyv8RGy6lkg4D9hKaLoWvbi/67/OOFrWKQvieedtVS8aqQP6eRQk3ivzuqP+tPvx
# WraCcw/LDx6QtSdx+B50Ea0/TAw8W/WcIzREMSHkSPbv5IMkeSbhooxeswAs+H06
# uC0qRDMa35RTmgaAIfHntr/ObFSq4y8ylWCvky0Kpuy42oMRnZpgCdx9NkmQxhJi
# GwbkRLmWzQfawbor2iwqmqGCE0MwghM/BgorBgEEAYI3AwMBMYITLzCCEysGCSqG
# SIb3DQEHAqCCExwwghMYAgEDMQ8wDQYJYIZIAWUDBAIBBQAwggE7BgsqhkiG9w0B
# CRABBKCCASoEggEmMIIBIgIBAQYKKwYBBAGEWQoDATAxMA0GCWCGSAFlAwQCAQUA
# BCCu+5O5snBtSw1qaCHMGKUj7+4F2UqCtoY1KgfxCLhg+AIGWrKlzVUZGBMyMDE4
# MDMyNTIxMDU1OC43MDNaMAcCAQGAAgH0oIG3pIG0MIGxMQswCQYDVQQGEwJVUzET
# MBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMV
# TWljcm9zb2Z0IENvcnBvcmF0aW9uMQwwCgYDVQQLEwNBT0MxJjAkBgNVBAsTHVRo
# YWxlcyBUU1MgRVNOOkMzQjAtMEY2QS00MTExMSUwIwYDVQQDExxNaWNyb3NvZnQg
# VGltZS1TdGFtcCBTZXJ2aWNloIIOyDCCBnEwggRZoAMCAQICCmEJgSoAAAAAAAIw
# DQYJKoZIhvcNAQELBQAwgYgxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5n
# dG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9y
# YXRpb24xMjAwBgNVBAMTKU1pY3Jvc29mdCBSb290IENlcnRpZmljYXRlIEF1dGhv
# cml0eSAyMDEwMB4XDTEwMDcwMTIxMzY1NVoXDTI1MDcwMTIxNDY1NVowfDELMAkG
# A1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQx
# HjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEmMCQGA1UEAxMdTWljcm9z
# b2Z0IFRpbWUtU3RhbXAgUENBIDIwMTAwggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAw
# ggEKAoIBAQCpHQ28dxGKOiDs/BOX9fp/aZRrdFQQ1aUKAIKF++18aEssX8XD5WHC
# drc+Zitb8BVTJwQxH0EbGpUdzgkTjnxhMFmxMEQP8WCIhFRDDNdNuDgIs0Ldk6zW
# czBXJoKjRQ3Q6vVHgc2/JGAyWGBG8lhHhjKEHnRhZ5FfgVSxz5NMksHEpl3RYRNu
# KMYa+YaAu99h/EbBJx0kZxJyGiGKr0tkiVBisV39dx898Fd1rL2KQk1AUdEPnAY+
# Z3/1ZsADlkR+79BL/W7lmsqxqPJ6Kgox8NpOBpG2iAg16HgcsOmZzTznL0S6p/Tc
# ZL2kAcEgCZN4zfy8wMlEXV4WnAEFTyJNAgMBAAGjggHmMIIB4jAQBgkrBgEEAYI3
# FQEEAwIBADAdBgNVHQ4EFgQU1WM6XIoxkPNDe3xGG8UzaFqFbVUwGQYJKwYBBAGC
# NxQCBAweCgBTAHUAYgBDAEEwCwYDVR0PBAQDAgGGMA8GA1UdEwEB/wQFMAMBAf8w
# HwYDVR0jBBgwFoAU1fZWy4/oolxiaNE9lJBb186aGMQwVgYDVR0fBE8wTTBLoEmg
# R4ZFaHR0cDovL2NybC5taWNyb3NvZnQuY29tL3BraS9jcmwvcHJvZHVjdHMvTWlj
# Um9vQ2VyQXV0XzIwMTAtMDYtMjMuY3JsMFoGCCsGAQUFBwEBBE4wTDBKBggrBgEF
# BQcwAoY+aHR0cDovL3d3dy5taWNyb3NvZnQuY29tL3BraS9jZXJ0cy9NaWNSb29D
# ZXJBdXRfMjAxMC0wNi0yMy5jcnQwgaAGA1UdIAEB/wSBlTCBkjCBjwYJKwYBBAGC
# Ny4DMIGBMD0GCCsGAQUFBwIBFjFodHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20vUEtJ
# L2RvY3MvQ1BTL2RlZmF1bHQuaHRtMEAGCCsGAQUFBwICMDQeMiAdAEwAZQBnAGEA
# bABfAFAAbwBsAGkAYwB5AF8AUwB0AGEAdABlAG0AZQBuAHQALiAdMA0GCSqGSIb3
# DQEBCwUAA4ICAQAH5ohRDeLG4Jg/gXEDPZ2joSFvs+umzPUxvs8F4qn++ldtGTCz
# wsVmyWrf9efweL3HqJ4l4/m87WtUVwgrUYJEEvu5U4zM9GASinbMQEBBm9xcF/9c
# +V4XNZgkVkt070IQyK+/f8Z/8jd9Wj8c8pl5SpFSAK84Dxf1L3mBZdmptWvkx872
# ynoAb0swRCQiPM/tA6WWj1kpvLb9BOFwnzJKJ/1Vry/+tuWOM7tiX5rbV0Dp8c6Z
# ZpCM/2pif93FSguRJuI57BlKcWOdeyFtw5yjojz6f32WapB4pm3S4Zz5Hfw42JT0
# xqUKloakvZ4argRCg7i1gJsiOCC1JeVk7Pf0v35jWSUPei45V3aicaoGig+JFrph
# pxHLmtgOR5qAxdDNp9DvfYPw4TtxCd9ddJgiCGHasFAeb73x4QDf5zEHpJM692VH
# eOj4qEir995yfmFrb3epgcunCaw5u+zGy9iCtHLNHfS4hQEegPsbiSpUObJb2sgN
# VZl6h3M7COaYLeqN4DMuEin1wC9UJyH3yKxO2ii4sanblrKnQqLJzxlBTeCG+Sqa
# oxFmMNO7dDJL32N79ZmKLxvHIa9Zta7cRDyXUHHXodLFVeNp3lfB0d4wwP3M5k37
# Db9dT+mdHhk4L7zPWAUu7w2gUDXa7wknHNWzfjUeCLraNtvTX4/edIhJEjCCBNgw
# ggPAoAMCAQICEzMAAACtgCM3ZcRaI2oAAAAAAK0wDQYJKoZIhvcNAQELBQAwfDEL
# MAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1v
# bmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEmMCQGA1UEAxMdTWlj
# cm9zb2Z0IFRpbWUtU3RhbXAgUENBIDIwMTAwHhcNMTYwOTA3MTc1NjU1WhcNMTgw
# OTA3MTc1NjU1WjCBsTELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24x
# EDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlv
# bjEMMAoGA1UECxMDQU9DMSYwJAYDVQQLEx1UaGFsZXMgVFNTIEVTTjpDM0IwLTBG
# NkEtNDExMTElMCMGA1UEAxMcTWljcm9zb2Z0IFRpbWUtU3RhbXAgU2VydmljZTCC
# ASIwDQYJKoZIhvcNAQEBBQADggEPADCCAQoCggEBAO2zDf5lGt2NsVXvRym+KFTj
# FQLByzq2Wh6ejANxzNtKrOeNVL9eofo1ARQi/FyT70eal7jqau/R6qeqJblHXObJ
# a9O0B5oG8ueyNMiLGHvYdbV4aUUM11IijLEQEqm7Jlo+v0ZSGjlhSAuUWniibqko
# XHFBrT6DVoMkLKHVqfDFvm/c9u8SVqcy6+nLx6kkflGbefoHa7cmCgMwrKi2M7pE
# rRo3g5dXK4SQaDTBgH8eUWDJ1X42CrKp+T60frfehPeb8U+oJgjmGKYqAllxzMGX
# +CliedfWzk12z//BFQHmk5hgkdNqBYksIAGH3BA9Ost2rIOdEAn8hw2crlyZ/acC
# AwEAAaOCARswggEXMB0GA1UdDgQWBBRkIbrAL6z4nMcMlOXnH8kK1rz9azAfBgNV
# HSMEGDAWgBTVYzpcijGQ80N7fEYbxTNoWoVtVTBWBgNVHR8ETzBNMEugSaBHhkVo
# dHRwOi8vY3JsLm1pY3Jvc29mdC5jb20vcGtpL2NybC9wcm9kdWN0cy9NaWNUaW1T
# dGFQQ0FfMjAxMC0wNy0wMS5jcmwwWgYIKwYBBQUHAQEETjBMMEoGCCsGAQUFBzAC
# hj5odHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20vcGtpL2NlcnRzL01pY1RpbVN0YVBD
# QV8yMDEwLTA3LTAxLmNydDAMBgNVHRMBAf8EAjAAMBMGA1UdJQQMMAoGCCsGAQUF
# BwMIMA0GCSqGSIb3DQEBCwUAA4IBAQAShUe51J2YxHxkbrWquE1TiiKG3HaVdV0i
# jzd1PF72pW86jRl/u+qUNP4gpmpUNk80VP8AA5VUJvN5Z+/xwBj66bcw7Xf/aXTa
# M4QRDpOvgRjHJVq4hdZgobRrWzOj/rSGGCTYIZVb7pAVxtlj7tSk2Pnket1LsnOs
# FrmgwAQW7zV1O1A8+WF23AHoCx9mUBrdqllPTIPYxYcEQiJ3qMr3TaWuGpHFxx0g
# fCFYdVOvTyW64sy4cHDjWmFdXKzja/yM06w4P2I/JmDDeaaVdfyP/OYtLJR9AtEb
# 7sN/pMHZpEYiN9evf5i6Xvd3k12rC68UUE7pZkEvOeqE4xd5+VxUoYIDczCCAlsC
# AQEwgeGhgbekgbQwgbExCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9u
# MRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRp
# b24xDDAKBgNVBAsTA0FPQzEmMCQGA1UECxMdVGhhbGVzIFRTUyBFU046QzNCMC0w
# RjZBLTQxMTExJTAjBgNVBAMTHE1pY3Jvc29mdCBUaW1lLVN0YW1wIFNlcnZpY2Wi
# JQoBATAJBgUrDgMCGgUAAxUAnBjmGt8bA4gXXRzGxyxLmq/hMNmggcEwgb6kgbsw
# gbgxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdS
# ZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xDDAKBgNVBAsT
# A0FPQzEnMCUGA1UECxMebkNpcGhlciBOVFMgRVNOOjI2NjUtNEMzRi1DNURFMSsw
# KQYDVQQDEyJNaWNyb3NvZnQgVGltZSBTb3VyY2UgTWFzdGVyIENsb2NrMA0GCSqG
# SIb3DQEBBQUAAgUA3mJ1GTAiGA8yMDE4MDMyNTE5MjA1N1oYDzIwMTgwMzI2MTky
# MDU3WjB0MDoGCisGAQQBhFkKBAExLDAqMAoCBQDeYnUZAgEAMAcCAQACAlhpMAcC
# AQACAhZnMAoCBQDeY8aZAgEAMDYGCisGAQQBhFkKBAIxKDAmMAwGCisGAQQBhFkK
# AwGgCjAIAgEAAgMW42ChCjAIAgEAAgMehIAwDQYJKoZIhvcNAQEFBQADggEBAHgF
# dT2A5izt5HZCo4jxKJIjz49vI4FccPhYcLPvSGfGgPPGQ5CbbC5h29o3zS2OVu/B
# lr/PsYPb2WWVYY/E5joCPl7qI9UVkYhiWhbpyoVmJ3TnaMsx3YsJihuzHE4+KD1n
# 3aWbKti5RYY/MLvQzDjdQlyFMwnSYtBuAxZY9fKrT2TYaNmAbL2CV/Qu3MlBRigq
# r9qwd6jP8hg6BTyMdm80+0MlqekyB5yOKAz59i4YFGzLscCAxNznkR390B78Y1TP
# YSK0JSx++iFJ8lQDiU5YZq6XMwepDTx/XVf90tkoROVAU7Ese3l4S9A2xqysNiY9
# WHaOuA0waOmkR7AQinoxggL1MIIC8QIBATCBkzB8MQswCQYDVQQGEwJVUzETMBEG
# A1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWlj
# cm9zb2Z0IENvcnBvcmF0aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1TdGFt
# cCBQQ0EgMjAxMAITMwAAAK2AIzdlxFojagAAAAAArTANBglghkgBZQMEAgEFAKCC
# ATIwGgYJKoZIhvcNAQkDMQ0GCyqGSIb3DQEJEAEEMC8GCSqGSIb3DQEJBDEiBCA8
# W/dlVqnfgJlMqxM28q88BzBU0qP+wtz7Kt9I1lNsTjCB4gYLKoZIhvcNAQkQAgwx
# gdIwgc8wgcwwgbEEFJwY5hrfGwOIF10cxscsS5qv4TDZMIGYMIGApH4wfDELMAkG
# A1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQx
# HjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEmMCQGA1UEAxMdTWljcm9z
# b2Z0IFRpbWUtU3RhbXAgUENBIDIwMTACEzMAAACtgCM3ZcRaI2oAAAAAAK0wFgQU
# seXvT/5AO8LI237drFKXpNZq61IwDQYJKoZIhvcNAQELBQAEggEA5CQs2RKs/he/
# /1o0EzLtnZVKrsAIOSXgSaQRdr6DYQxYHgc8xHRAf/lkOfH7mgCFRFpjPQb9lxUV
# his0YlwtyUa4u/DwHZQV8I0WPkC2mf04M4owupc+CleRPWRaiG7TRLIdpz1k+T0V
# utXg2h9VfLK5Qne6NK2l82j4xHI78H2c189rX7lD5PM3K3+MufOp13u1LBMm/pV5
# saDZsVwVB331fc2qbh6ahH1pqVk6YOkcO3K8yjKn71tjoyLj1OPz72vKbD6qu9Jt
# gNrB+lF/t59gg26hs2UGxITAuMKoPgAX407Hvv18prlrnIICMzCj6sUaDv0eewP7
# zxovsMrAIw==
# SIG # End signature block
