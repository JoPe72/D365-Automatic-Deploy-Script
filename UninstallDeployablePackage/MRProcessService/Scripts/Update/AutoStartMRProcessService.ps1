$ErrorActionPreference = 'Stop'

Set-Service MR2012ProcessService -StartupType Automatic
Start-Service MR2012ProcessService
Write-Output "Financial Reporting Process Service started."

# SIG # Begin signature block
# MIIkDwYJKoZIhvcNAQcCoIIkADCCI/wCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCAhB4qtNAHOhmrv
# uywSLYcMreftmO+Ytom5QGWoVbOmO6CCDYIwggYAMIID6KADAgECAhMzAAAAww6b
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
# SEXAQsmbdlsKgEhr/Xmfwb1tbWrJUnMTDXpQzTGCFeMwghXfAgEBMIGVMH4xCzAJ
# BgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25k
# MR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xKDAmBgNVBAMTH01pY3Jv
# c29mdCBDb2RlIFNpZ25pbmcgUENBIDIwMTECEzMAAADDDpun2LLc9ywAAAAAAMMw
# DQYJYIZIAWUDBAIBBQCggdYwGQYJKoZIhvcNAQkDMQwGCisGAQQBgjcCAQQwHAYK
# KwYBBAGCNwIBCzEOMAwGCisGAQQBgjcCARUwLwYJKoZIhvcNAQkEMSIEIPylG9Xr
# o3fDZnXkCfSDXc1S5+2I75+RviOKs4XvPZLWMGoGCisGAQQBgjcCAQwxXDBaoDyA
# OgBBAHUAdABvAFMAdABhAHIAdABNAFIAUAByAG8AYwBlAHMAcwBTAGUAcgB2AGkA
# YwBlAC4AcABzADGhGoAYaHR0cDovL3d3dy5taWNyb3NvZnQuY29tMA0GCSqGSIb3
# DQEBAQUABIIBABq+TaMQ/8eLuZ7ppXUI+H5Qtzogzt0ASgkCkANeZQduJBHUjJC0
# I+0seO+3FcosG4VGUM+acJB+oKH+pHRCgy51hJ68iguL8iIL4KWAXdpI8lcvWBBs
# Ml3L7hBzBp1p7e6+F20EAdl/7XyLZlX+iZ7BRgNKIqXC6NPmEx9cj0+JH+dSaBzz
# aVZpO6oA0OWtOAjd5ZGyXh8fxhPB1/cFwzHr//58ElZ2wIe0lZbApi3Br1cisJyr
# F9eL1yyQa08sNTv8f+dAtXDfe2uiDxa1maEyKR2aGqb+u7HR6noGBxEJEDNyHbY4
# MR9ZWIjViYA07TnWuoSA0y5sBFbaU/c1Gy6hghNFMIITQQYKKwYBBAGCNwMDATGC
# EzEwghMtBgkqhkiG9w0BBwKgghMeMIITGgIBAzEPMA0GCWCGSAFlAwQCAQUAMIIB
# OwYLKoZIhvcNAQkQAQSgggEqBIIBJjCCASICAQEGCisGAQQBhFkKAwEwMTANBglg
# hkgBZQMEAgEFAAQga3KHYbJ/0iTimF4IYhH2jwZS2kIHTQMBSRMEKSI4EaUCBlqy
# m2sG1xgSMjAxODAzMjUyMTE0MjguNzZaMAcCAQGAAgH0oIG4pIG1MIGyMQswCQYD
# VQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEe
# MBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMQwwCgYDVQQLEwNBT0MxJzAl
# BgNVBAsTHm5DaXBoZXIgRFNFIEVTTjo3QUI1LTJERjItREEzRjElMCMGA1UEAxMc
# TWljcm9zb2Z0IFRpbWUtU3RhbXAgU2VydmljZaCCDsowggZxMIIEWaADAgECAgph
# CYEqAAAAAAACMA0GCSqGSIb3DQEBCwUAMIGIMQswCQYDVQQGEwJVUzETMBEGA1UE
# CBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9z
# b2Z0IENvcnBvcmF0aW9uMTIwMAYDVQQDEylNaWNyb3NvZnQgUm9vdCBDZXJ0aWZp
# Y2F0ZSBBdXRob3JpdHkgMjAxMDAeFw0xMDA3MDEyMTM2NTVaFw0yNTA3MDEyMTQ2
# NTVaMHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQH
# EwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xJjAkBgNV
# BAMTHU1pY3Jvc29mdCBUaW1lLVN0YW1wIFBDQSAyMDEwMIIBIjANBgkqhkiG9w0B
# AQEFAAOCAQ8AMIIBCgKCAQEAqR0NvHcRijog7PwTl/X6f2mUa3RUENWlCgCChfvt
# fGhLLF/Fw+Vhwna3PmYrW/AVUycEMR9BGxqVHc4JE458YTBZsTBED/FgiIRUQwzX
# Tbg4CLNC3ZOs1nMwVyaCo0UN0Or1R4HNvyRgMlhgRvJYR4YyhB50YWeRX4FUsc+T
# TJLBxKZd0WETbijGGvmGgLvfYfxGwScdJGcSchohiq9LZIlQYrFd/XcfPfBXday9
# ikJNQFHRD5wGPmd/9WbAA5ZEfu/QS/1u5ZrKsajyeioKMfDaTgaRtogINeh4HLDp
# mc085y9Euqf03GS9pAHBIAmTeM38vMDJRF1eFpwBBU8iTQIDAQABo4IB5jCCAeIw
# EAYJKwYBBAGCNxUBBAMCAQAwHQYDVR0OBBYEFNVjOlyKMZDzQ3t8RhvFM2hahW1V
# MBkGCSsGAQQBgjcUAgQMHgoAUwB1AGIAQwBBMAsGA1UdDwQEAwIBhjAPBgNVHRMB
# Af8EBTADAQH/MB8GA1UdIwQYMBaAFNX2VsuP6KJcYmjRPZSQW9fOmhjEMFYGA1Ud
# HwRPME0wS6BJoEeGRWh0dHA6Ly9jcmwubWljcm9zb2Z0LmNvbS9wa2kvY3JsL3By
# b2R1Y3RzL01pY1Jvb0NlckF1dF8yMDEwLTA2LTIzLmNybDBaBggrBgEFBQcBAQRO
# MEwwSgYIKwYBBQUHMAKGPmh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2kvY2Vy
# dHMvTWljUm9vQ2VyQXV0XzIwMTAtMDYtMjMuY3J0MIGgBgNVHSABAf8EgZUwgZIw
# gY8GCSsGAQQBgjcuAzCBgTA9BggrBgEFBQcCARYxaHR0cDovL3d3dy5taWNyb3Nv
# ZnQuY29tL1BLSS9kb2NzL0NQUy9kZWZhdWx0Lmh0bTBABggrBgEFBQcCAjA0HjIg
# HQBMAGUAZwBhAGwAXwBQAG8AbABpAGMAeQBfAFMAdABhAHQAZQBtAGUAbgB0AC4g
# HTANBgkqhkiG9w0BAQsFAAOCAgEAB+aIUQ3ixuCYP4FxAz2do6Ehb7Prpsz1Mb7P
# BeKp/vpXbRkws8LFZslq3/Xn8Hi9x6ieJeP5vO1rVFcIK1GCRBL7uVOMzPRgEop2
# zEBAQZvcXBf/XPleFzWYJFZLdO9CEMivv3/Gf/I3fVo/HPKZeUqRUgCvOA8X9S95
# gWXZqbVr5MfO9sp6AG9LMEQkIjzP7QOllo9ZKby2/QThcJ8ySif9Va8v/rbljjO7
# Yl+a21dA6fHOmWaQjP9qYn/dxUoLkSbiOewZSnFjnXshbcOco6I8+n99lmqQeKZt
# 0uGc+R38ONiU9MalCpaGpL2eGq4EQoO4tYCbIjggtSXlZOz39L9+Y1klD3ouOVd2
# onGqBooPiRa6YacRy5rYDkeagMXQzafQ732D8OE7cQnfXXSYIghh2rBQHm+98eEA
# 3+cxB6STOvdlR3jo+KhIq/fecn5ha293qYHLpwmsObvsxsvYgrRyzR30uIUBHoD7
# G4kqVDmyW9rIDVWZeodzOwjmmC3qjeAzLhIp9cAvVCch98isTtoouLGp25ayp0Ki
# yc8ZQU3ghvkqmqMRZjDTu3QyS99je/WZii8bxyGvWbWu3EQ8l1Bx16HSxVXjad5X
# wdHeMMD9zOZN+w2/XU/pnR4ZOC+8z1gFLu8NoFA12u8JJxzVs341Hgi62jbb01+P
# 3nSISRIwggTZMIIDwaADAgECAhMzAAAAq15Ane5G3yxsAAAAAACrMA0GCSqGSIb3
# DQEBCwUAMHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYD
# VQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xJjAk
# BgNVBAMTHU1pY3Jvc29mdCBUaW1lLVN0YW1wIFBDQSAyMDEwMB4XDTE2MDkwNzE3
# NTY1NFoXDTE4MDkwNzE3NTY1NFowgbIxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpX
# YXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQg
# Q29ycG9yYXRpb24xDDAKBgNVBAsTA0FPQzEnMCUGA1UECxMebkNpcGhlciBEU0Ug
# RVNOOjdBQjUtMkRGMi1EQTNGMSUwIwYDVQQDExxNaWNyb3NvZnQgVGltZS1TdGFt
# cCBTZXJ2aWNlMIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAs+Z+UJig
# RgmwZgEmijTTKcl9mDWaDCzdM8oDzw4C1wvvu+HILkmk09DZ3HPTu0WFnF3lAfX8
# K6Zim+GAAqfzNyhFSzXeuLpu+4aQ7eGrEPI48HfCW89AE+45ShvSKnoe/IsB+Km8
# mo95A8PjcNGsAPOmwMsh3XTU1IeEKIGtGllSYt7s/czFA4lMTQezoNQennsBwjrN
# Y2kJkIgTk8MtlKEsBCm4N9VKtTGK5L5ukTPbfO7MMnxcwS3huLDWIokhKiR54uSj
# zy4Z1lXJSBEkpKjJ9UjIUsIxkpD6ZjYA+aEwGmgPrWlkS1rx62mfc4Z6tmAflJFe
# jiC91N8OKpDISwIDAQABo4IBGzCCARcwHQYDVR0OBBYEFA3HR9AcYMvpwGuUzF8G
# DmK42GqnMB8GA1UdIwQYMBaAFNVjOlyKMZDzQ3t8RhvFM2hahW1VMFYGA1UdHwRP
# ME0wS6BJoEeGRWh0dHA6Ly9jcmwubWljcm9zb2Z0LmNvbS9wa2kvY3JsL3Byb2R1
# Y3RzL01pY1RpbVN0YVBDQV8yMDEwLTA3LTAxLmNybDBaBggrBgEFBQcBAQROMEww
# SgYIKwYBBQUHMAKGPmh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2kvY2VydHMv
# TWljVGltU3RhUENBXzIwMTAtMDctMDEuY3J0MAwGA1UdEwEB/wQCMAAwEwYDVR0l
# BAwwCgYIKwYBBQUHAwgwDQYJKoZIhvcNAQELBQADggEBAD+f/rouYfFyKq2qFWaV
# oARLfbPCRt3Q61tAPPSMdQWtoYFvJHsNLtKjibrwNiv5yMV3Dnq4fN5U4v0PJl88
# DHYt+hjRohCoiF5LKlmVyF93f/5EJLgCmYSRlK8Cx6YqhoSxi/iRJMfQbqM2v/v4
# uAeabz5p7bbxm2FnVK026Nvy2uVipjvIbcxDmiYi80SM6y1HJnXTwuab1oqdFU+T
# 6IAgzg4tlQNT80DgGtxpXEwh10oTKC9F1YL9pMHfITvJ6z84pT8y+s0GS7gfvJsa
# s5Gxk13i/3mhFtG4Nfbhkcr3cez9/orD4GU1WMukXg+W5qcir2jzPs/epI2q2O4S
# pOKhggN0MIICXAIBATCB4qGBuKSBtTCBsjELMAkGA1UEBhMCVVMxEzARBgNVBAgT
# Cldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29m
# dCBDb3Jwb3JhdGlvbjEMMAoGA1UECxMDQU9DMScwJQYDVQQLEx5uQ2lwaGVyIERT
# RSBFU046N0FCNS0yREYyLURBM0YxJTAjBgNVBAMTHE1pY3Jvc29mdCBUaW1lLVN0
# YW1wIFNlcnZpY2WiJQoBATAJBgUrDgMCGgUAAxUAyey7SC012ZS+to73JqkxboqH
# jjKggcEwgb6kgbswgbgxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9u
# MRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRp
# b24xDDAKBgNVBAsTA0FPQzEnMCUGA1UECxMebkNpcGhlciBOVFMgRVNOOjI2NjUt
# NEMzRi1DNURFMSswKQYDVQQDEyJNaWNyb3NvZnQgVGltZSBTb3VyY2UgTWFzdGVy
# IENsb2NrMA0GCSqGSIb3DQEBBQUAAgUA3mHqvTAiGA8yMDE4MDMyNTA5MzAzN1oY
# DzIwMTgwMzI2MDkzMDM3WjB0MDoGCisGAQQBhFkKBAExLDAqMAoCBQDeYeq9AgEA
# MAcCAQACAiXFMAcCAQACAhouMAoCBQDeYzw9AgEAMDYGCisGAQQBhFkKBAIxKDAm
# MAwGCisGAQQBhFkKAwGgCjAIAgEAAgMW42ChCjAIAgEAAgMHoSAwDQYJKoZIhvcN
# AQEFBQADggEBAH5aL0yKj8iqkMLhqYxCGQy35PUXyglz4Cz/uAnNu+kuxGTqoT7x
# Q8sv5nTgkG2mGGXTbu5TX3+DMIuNyUGBCF7zllXt6ZqEs0XkPDTHhaEaAbErQ0RJ
# KDHFRlJMuoN5Od7iH1B4gI/gucCmZbooyaD7xTJfBeEmyBDoj5DLtCk3qtrlj8/Q
# Nscy9xdCC2I0MVnxH/oLjebSImREcFC3TiV/6+cBzkXU9xgjZYapk/ifMfCXncJN
# EiGYtUMTZyAATUdfAcKY6XegICydsEyyZxc0qqyw0vodcKTOI+LgjZeXbPT4sgA/
# UBa/g8+wdZo3jKfyGXjGQ2T3Z1dhguKDKCwxggL1MIIC8QIBATCBkzB8MQswCQYD
# VQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEe
# MBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSYwJAYDVQQDEx1NaWNyb3Nv
# ZnQgVGltZS1TdGFtcCBQQ0EgMjAxMAITMwAAAKteQJ3uRt8sbAAAAAAAqzANBglg
# hkgBZQMEAgEFAKCCATIwGgYJKoZIhvcNAQkDMQ0GCyqGSIb3DQEJEAEEMC8GCSqG
# SIb3DQEJBDEiBCAGA14wJd4uUlhGbl9NU/sPD094tjFVjkddTqCWgDdrfTCB4gYL
# KoZIhvcNAQkQAgwxgdIwgc8wgcwwgbEEFMnsu0gtNdmUvraO9yapMW6Kh44yMIGY
# MIGApH4wfDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNV
# BAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEmMCQG
# A1UEAxMdTWljcm9zb2Z0IFRpbWUtU3RhbXAgUENBIDIwMTACEzMAAACrXkCd7kbf
# LGwAAAAAAKswFgQU9EZ8rGhsBOqvgJDjVqYWE6bwxjkwDQYJKoZIhvcNAQELBQAE
# ggEAB7ujnQN05P5zbaNRU3MorGtVaFYZa246L1WHRvMvgmTGoeveNZ+UG38vrfv1
# 9550XrQrwIAkefcBqxTj6nBC1Heaz87pAcGv05RjX3UrTxiM5lsNwfsA6g8F0Kfj
# 2ATe2eJl0OtLNmiHYshYSgDsoSGx+9jFLTyA+SDfHJmaz1QtWCIqmA2CZoj2LpGb
# DJ+WMEhjv7sPOhFTD+SmYcKwX57hQ0Fg7/QUQVjSuFE+mtT60BZXQDuORGdi61HB
# 2KK0h7UvPLUCEWlBz1opiQWuvrFWoc18psPLWVsLGArHQJVXBY3s1qR1h1Swhchl
# Mif87qhnqmTtPr7FdfibgeWVZw==
# SIG # End signature block
