Import-Module WebAdministration
Import-Module "$PSScriptRoot\CommonRollbackUtilities.psm1" -DisableNameChecking

######################################################################
###                                                                ###
###  Helper Functions                                              ###
###                                                                ###
######################################################################
Function Add-ServiceBinding([string] $siteName, [string] $prodEnvName, [string] $upgradeEnvName)
{
    $siteBindings = Get-WebBinding -Name $siteName -HostHeader "*.cloud*"

    foreach ($binding in $siteBindings)
    {
        $protocol = $Binding.protocol
        $values = $Binding.BindingInformation.Split(":")
        $ipAddress = $Values[0]
        $port = $Values[1]
        $originalHostHeader = $Values[2]
        $newHostHeader = $originalHostHeader -ireplace $UpradeENVName, $prodEnvName

        if($originalHostHeader -ne $newHostHeader)
        {
            try
            {
                New-WebBinding -Name $siteName -IPAddress $ipAddress -Port $port -HostHeader $newHostHeader -Protocol $protocol
            }
            catch 
            {
                if ($Error[0].ToString().Contains("duplicate"))
                {
                    #Ignore unable to add duplicate errors (possible script re-run or case difference)
                    Write-Output "Binding already exists for $newHostHeader"
                }
                else
                {
                    Throw "Unable to add new binding " + $Error[0].ToString()
                }
            }
        }
    }
}

######################################################################
###                                                                ###
###  Replace values with actual values from production enviroments ###
###                                                                ###
######################################################################
$ExistingProductionEnvName = '<Production Environment Name>'
$UpradeENVName = '<Upgrade Environment Name>'

######################################################################
###                                                                ###
###  Script starts Here                                            ###
###                                                                ###
######################################################################

# Update AOS 
$aosSiteName = Get-AosWebSiteName
if (![string]::IsNullOrWhitespace($aosSiteName))
{
    Add-ServiceBinding -siteName $aosSiteName -prodEnvName $ExistingProductionEnvName -upgradeEnvName $UpradeENVName
}

#Update Retail Server
if (Test-Path 'iis:\sites\RetailServer')
{
    $webrootRetailServer = $(get-item 'iis:\sites\RetailServer')
}
else
{
   Write-Output "Retail Server site not found"
}

If ($webrootRetailServer)
{
   Add-ServiceBinding -siteName $webrootRetailServer.name -prodEnvName $ExistingProductionEnvName -upgradeEnvName $UpradeENVName
}

#Update Retail POS
if (Test-Path 'iis:\sites\RetailCloudPos')
{
    $webrootRetailcloudPos = $(get-item 'iis:\sites\RetailCloudPos')
}
else
{
   Write-Output "Retail Cloud Pos site not found"
}

If ($webrootRetailcloudPos)
{
    Add-ServiceBinding -siteName $webrootRetailcloudPos.name -prodEnvName $ExistingProductionEnvName -upgradeEnvName $UpradeENVName
}
# SIG # Begin signature block
# MIIj/gYJKoZIhvcNAQcCoIIj7zCCI+sCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCDAc9CHh1+M+nex
# ojS1JkpeQOYw/iZTiqobusiXArJ47qCCDYIwggYAMIID6KADAgECAhMzAAAAww6b
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
# SEXAQsmbdlsKgEhr/Xmfwb1tbWrJUnMTDXpQzTGCFdIwghXOAgEBMIGVMH4xCzAJ
# BgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25k
# MR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xKDAmBgNVBAMTH01pY3Jv
# c29mdCBDb2RlIFNpZ25pbmcgUENBIDIwMTECEzMAAADDDpun2LLc9ywAAAAAAMMw
# DQYJYIZIAWUDBAIBBQCggcQwGQYJKoZIhvcNAQkDMQwGCisGAQQBgjcCAQQwHAYK
# KwYBBAGCNwIBCzEOMAwGCisGAQQBgjcCARUwLwYJKoZIhvcNAQkEMSIEIE01Louw
# HtOnJia8fqIPIyWQ0AFj9jbr0Z7njFETRQ6CMFgGCisGAQQBgjcCAQwxSjBIoCqA
# KABVAHAAZABhAHQAZQBXAFMAQgBpAG4AZABpAG4AZwBzAC4AcABzADGhGoAYaHR0
# cDovL3d3dy5taWNyb3NvZnQuY29tMA0GCSqGSIb3DQEBAQUABIIBADgVnhw0u3cF
# zuqLz6smg0gZgqijHFnPyy/4Rt85yt1eCVXESD6Zcy4lGDj+lTBwSbB4q0aTXwPR
# AFmlpefz3WQw28SdR/DAU39Gxca7HN0dwHdMg10GGtvJ5VTm0S2aXD3S6UHgzB3x
# SNFKJ12NGPSojrPE/r61Uh3KW16y/MXCjlNcjvb+fgYK39MLa2BAsYSwlq+0o4xv
# 45X209/fv2cDUMcopaxlHPPak80eQSiauiGNRdGxLExl/Hzw7XCvBuAnHyRE/JcM
# 04YmedqT7AxUyjp8QW1Hg/znrvlWBxOq3JORXay0bHSeeH1Kq3P46eAI/v1FJGed
# fjo24NEj4oWhghNGMIITQgYKKwYBBAGCNwMDATGCEzIwghMuBgkqhkiG9w0BBwKg
# ghMfMIITGwIBAzEPMA0GCWCGSAFlAwQCAQUAMIIBPAYLKoZIhvcNAQkQAQSgggEr
# BIIBJzCCASMCAQEGCisGAQQBhFkKAwEwMTANBglghkgBZQMEAgEFAAQgCPXg6evc
# PUTNL3i8SxaurDfJC1gGV6aznvLIl0suzkUCBlqym2rqJRgTMjAxODAzMjUyMTA1
# NTguMDY3WjAHAgEBgAIB9KCBuKSBtTCBsjELMAkGA1UEBhMCVVMxEzARBgNVBAgT
# Cldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29m
# dCBDb3Jwb3JhdGlvbjEMMAoGA1UECxMDQU9DMScwJQYDVQQLEx5uQ2lwaGVyIERT
# RSBFU046N0FCNS0yREYyLURBM0YxJTAjBgNVBAMTHE1pY3Jvc29mdCBUaW1lLVN0
# YW1wIFNlcnZpY2Wggg7KMIIGcTCCBFmgAwIBAgIKYQmBKgAAAAAAAjANBgkqhkiG
# 9w0BAQsFADCBiDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAO
# BgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEy
# MDAGA1UEAxMpTWljcm9zb2Z0IFJvb3QgQ2VydGlmaWNhdGUgQXV0aG9yaXR5IDIw
# MTAwHhcNMTAwNzAxMjEzNjU1WhcNMjUwNzAxMjE0NjU1WjB8MQswCQYDVQQGEwJV
# UzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UE
# ChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGlt
# ZS1TdGFtcCBQQ0EgMjAxMDCCASIwDQYJKoZIhvcNAQEBBQADggEPADCCAQoCggEB
# AKkdDbx3EYo6IOz8E5f1+n9plGt0VBDVpQoAgoX77XxoSyxfxcPlYcJ2tz5mK1vw
# FVMnBDEfQRsalR3OCROOfGEwWbEwRA/xYIiEVEMM1024OAizQt2TrNZzMFcmgqNF
# DdDq9UeBzb8kYDJYYEbyWEeGMoQedGFnkV+BVLHPk0ySwcSmXdFhE24oxhr5hoC7
# 32H8RsEnHSRnEnIaIYqvS2SJUGKxXf13Hz3wV3WsvYpCTUBR0Q+cBj5nf/VmwAOW
# RH7v0Ev9buWayrGo8noqCjHw2k4GkbaICDXoeByw6ZnNPOcvRLqn9NxkvaQBwSAJ
# k3jN/LzAyURdXhacAQVPIk0CAwEAAaOCAeYwggHiMBAGCSsGAQQBgjcVAQQDAgEA
# MB0GA1UdDgQWBBTVYzpcijGQ80N7fEYbxTNoWoVtVTAZBgkrBgEEAYI3FAIEDB4K
# AFMAdQBiAEMAQTALBgNVHQ8EBAMCAYYwDwYDVR0TAQH/BAUwAwEB/zAfBgNVHSME
# GDAWgBTV9lbLj+iiXGJo0T2UkFvXzpoYxDBWBgNVHR8ETzBNMEugSaBHhkVodHRw
# Oi8vY3JsLm1pY3Jvc29mdC5jb20vcGtpL2NybC9wcm9kdWN0cy9NaWNSb29DZXJB
# dXRfMjAxMC0wNi0yMy5jcmwwWgYIKwYBBQUHAQEETjBMMEoGCCsGAQUFBzAChj5o
# dHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20vcGtpL2NlcnRzL01pY1Jvb0NlckF1dF8y
# MDEwLTA2LTIzLmNydDCBoAYDVR0gAQH/BIGVMIGSMIGPBgkrBgEEAYI3LgMwgYEw
# PQYIKwYBBQUHAgEWMWh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9QS0kvZG9jcy9D
# UFMvZGVmYXVsdC5odG0wQAYIKwYBBQUHAgIwNB4yIB0ATABlAGcAYQBsAF8AUABv
# AGwAaQBjAHkAXwBTAHQAYQB0AGUAbQBlAG4AdAAuIB0wDQYJKoZIhvcNAQELBQAD
# ggIBAAfmiFEN4sbgmD+BcQM9naOhIW+z66bM9TG+zwXiqf76V20ZMLPCxWbJat/1
# 5/B4vceoniXj+bzta1RXCCtRgkQS+7lTjMz0YBKKdsxAQEGb3FwX/1z5Xhc1mCRW
# S3TvQhDIr79/xn/yN31aPxzymXlKkVIArzgPF/UveYFl2am1a+THzvbKegBvSzBE
# JCI8z+0DpZaPWSm8tv0E4XCfMkon/VWvL/625Y4zu2JfmttXQOnxzplmkIz/amJ/
# 3cVKC5Em4jnsGUpxY517IW3DnKOiPPp/fZZqkHimbdLhnPkd/DjYlPTGpQqWhqS9
# nhquBEKDuLWAmyI4ILUl5WTs9/S/fmNZJQ96LjlXdqJxqgaKD4kWumGnEcua2A5H
# moDF0M2n0O99g/DhO3EJ3110mCIIYdqwUB5vvfHhAN/nMQekkzr3ZUd46PioSKv3
# 3nJ+YWtvd6mBy6cJrDm77MbL2IK0cs0d9LiFAR6A+xuJKlQ5slvayA1VmXqHczsI
# 5pgt6o3gMy4SKfXAL1QnIffIrE7aKLixqduWsqdCosnPGUFN4Ib5KpqjEWYw07t0
# MkvfY3v1mYovG8chr1m1rtxEPJdQcdeh0sVV42neV8HR3jDA/czmTfsNv11P6Z0e
# GTgvvM9YBS7vDaBQNdrvCScc1bN+NR4Iuto229Nfj950iEkSMIIE2TCCA8GgAwIB
# AgITMwAAAKteQJ3uRt8sbAAAAAAAqzANBgkqhkiG9w0BAQsFADB8MQswCQYDVQQG
# EwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwG
# A1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQg
# VGltZS1TdGFtcCBQQ0EgMjAxMDAeFw0xNjA5MDcxNzU2NTRaFw0xODA5MDcxNzU2
# NTRaMIGyMQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UE
# BxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMQwwCgYD
# VQQLEwNBT0MxJzAlBgNVBAsTHm5DaXBoZXIgRFNFIEVTTjo3QUI1LTJERjItREEz
# RjElMCMGA1UEAxMcTWljcm9zb2Z0IFRpbWUtU3RhbXAgU2VydmljZTCCASIwDQYJ
# KoZIhvcNAQEBBQADggEPADCCAQoCggEBALPmflCYoEYJsGYBJoo00ynJfZg1mgws
# 3TPKA88OAtcL77vhyC5JpNPQ2dxz07tFhZxd5QH1/CumYpvhgAKn8zcoRUs13ri6
# bvuGkO3hqxDyOPB3wlvPQBPuOUob0ip6HvyLAfipvJqPeQPD43DRrADzpsDLId10
# 1NSHhCiBrRpZUmLe7P3MxQOJTE0Hs6DUHp57AcI6zWNpCZCIE5PDLZShLAQpuDfV
# SrUxiuS+bpEz23zuzDJ8XMEt4biw1iKJISokeeLko88uGdZVyUgRJKSoyfVIyFLC
# MZKQ+mY2APmhMBpoD61pZEta8etpn3OGerZgH5SRXo4gvdTfDiqQyEsCAwEAAaOC
# ARswggEXMB0GA1UdDgQWBBQNx0fQHGDL6cBrlMxfBg5iuNhqpzAfBgNVHSMEGDAW
# gBTVYzpcijGQ80N7fEYbxTNoWoVtVTBWBgNVHR8ETzBNMEugSaBHhkVodHRwOi8v
# Y3JsLm1pY3Jvc29mdC5jb20vcGtpL2NybC9wcm9kdWN0cy9NaWNUaW1TdGFQQ0Ff
# MjAxMC0wNy0wMS5jcmwwWgYIKwYBBQUHAQEETjBMMEoGCCsGAQUFBzAChj5odHRw
# Oi8vd3d3Lm1pY3Jvc29mdC5jb20vcGtpL2NlcnRzL01pY1RpbVN0YVBDQV8yMDEw
# LTA3LTAxLmNydDAMBgNVHRMBAf8EAjAAMBMGA1UdJQQMMAoGCCsGAQUFBwMIMA0G
# CSqGSIb3DQEBCwUAA4IBAQA/n/66LmHxciqtqhVmlaAES32zwkbd0OtbQDz0jHUF
# raGBbyR7DS7So4m68DYr+cjFdw56uHzeVOL9DyZfPAx2LfoY0aIQqIheSypZlchf
# d3/+RCS4ApmEkZSvAsemKoaEsYv4kSTH0G6jNr/7+LgHmm8+ae228ZthZ1StNujb
# 8trlYqY7yG3MQ5omIvNEjOstRyZ108Lmm9aKnRVPk+iAIM4OLZUDU/NA4BrcaVxM
# IddKEygvRdWC/aTB3yE7yes/OKU/MvrNBku4H7ybGrORsZNd4v95oRbRuDX24ZHK
# 93Hs/f6Kw+BlNVjLpF4PluanIq9o8z7P3qSNqtjuEqTioYIDdDCCAlwCAQEwgeKh
# gbikgbUwgbIxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYD
# VQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xDDAK
# BgNVBAsTA0FPQzEnMCUGA1UECxMebkNpcGhlciBEU0UgRVNOOjdBQjUtMkRGMi1E
# QTNGMSUwIwYDVQQDExxNaWNyb3NvZnQgVGltZS1TdGFtcCBTZXJ2aWNloiUKAQEw
# CQYFKw4DAhoFAAMVAMnsu0gtNdmUvraO9yapMW6Kh44yoIHBMIG+pIG7MIG4MQsw
# CQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9u
# ZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMQwwCgYDVQQLEwNBT0Mx
# JzAlBgNVBAsTHm5DaXBoZXIgTlRTIEVTTjoyNjY1LTRDM0YtQzVERTErMCkGA1UE
# AxMiTWljcm9zb2Z0IFRpbWUgU291cmNlIE1hc3RlciBDbG9jazANBgkqhkiG9w0B
# AQUFAAIFAN5h6r0wIhgPMjAxODAzMjUwOTMwMzdaGA8yMDE4MDMyNjA5MzAzN1ow
# dDA6BgorBgEEAYRZCgQBMSwwKjAKAgUA3mHqvQIBADAHAgEAAgIlxTAHAgEAAgIa
# LjAKAgUA3mM8PQIBADA2BgorBgEEAYRZCgQCMSgwJjAMBgorBgEEAYRZCgMBoAow
# CAIBAAIDFuNgoQowCAIBAAIDB6EgMA0GCSqGSIb3DQEBBQUAA4IBAQB+Wi9Mio/I
# qpDC4amMQhkMt+T1F8oJc+As/7gJzbvpLsRk6qE+8UPLL+Z04JBtphhl027uU19/
# gzCLjclBgQhe85ZV7emahLNF5Dw0x4WhGgGxK0NESSgxxUZSTLqDeTne4h9QeICP
# 4LnApmW6KMmg+8UyXwXhJsgQ6I+Qy7QpN6ra5Y/P0DbHMvcXQgtiNDFZ8R/6C43m
# 0iJkRHBQt04lf+vnAc5F1PcYI2WGqZP4nzHwl53CTRIhmLVDE2cgAE1HXwHCmOl3
# oCAsnbBMsmcXNKqssNL6HXCkziPi4I2Xl2z0+LIAP1AWv4PPsHWaN4yn8hl4xkNk
# 92dXYYLigygsMYIC9TCCAvECAQEwgZMwfDELMAkGA1UEBhMCVVMxEzARBgNVBAgT
# Cldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29m
# dCBDb3Jwb3JhdGlvbjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRpbWUtU3RhbXAgUENB
# IDIwMTACEzMAAACrXkCd7kbfLGwAAAAAAKswDQYJYIZIAWUDBAIBBQCgggEyMBoG
# CSqGSIb3DQEJAzENBgsqhkiG9w0BCRABBDAvBgkqhkiG9w0BCQQxIgQgca7lr+22
# /reH5qgpq/l49yLQ70nyLnhvmMCDIQxYdmkwgeIGCyqGSIb3DQEJEAIMMYHSMIHP
# MIHMMIGxBBTJ7LtILTXZlL62jvcmqTFuioeOMjCBmDCBgKR+MHwxCzAJBgNVBAYT
# AlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYD
# VQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xJjAkBgNVBAMTHU1pY3Jvc29mdCBU
# aW1lLVN0YW1wIFBDQSAyMDEwAhMzAAAAq15Ane5G3yxsAAAAAACrMBYEFPRGfKxo
# bATqr4CQ41amFhOm8MY5MA0GCSqGSIb3DQEBCwUABIIBAK9T8fQuxIjueo2wwXhK
# 301CcRfyCMsQFl4HYbyTVBNm9tL7L6fjqKLROwZF1GBx/+6VYzMrBWtcza2MGu3U
# Rm8DHzQyFKsoVa+jX3yddMsi//xhL9LhVJV6nAiZOn5h2fY7tGmny48RVD77luaY
# TJrpeKrlCX55iojeJytXMgsRrRlrmBYG/wUAYkEp5ZRb2r6OBX0I57dTwVNBJm4F
# UrairKp5YCisMG3zV+jdGTL821Hx6ZlfTKTIiV1FzsgCrhgqi7EYpXgzcfxgzZKc
# yjVw330caQ5MgBQqzV78hfYAndIhgvSAJJk8AzwkH+zVk7nov1gqhB7kc6bZF7Ef
# 4Jg=
# SIG # End signature block
