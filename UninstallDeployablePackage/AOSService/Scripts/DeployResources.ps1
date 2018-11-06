param
(
    [Parameter(Mandatory=$true)]
    $config,
    [Parameter(Mandatory=$true)]
    $log
)

Import-Module "$PSScriptRoot\AosCommon.psm1" -Force -DisableNameChecking

Initialize-Log $log
Write-Log "Decoding settings"
$settings = Decode-Settings $config

$PackageDirectory = $settings.'Common.BinDir'
$targetSiteRoot = $settings.'Infrastructure.WebRoot'

$m_core = Join-Path $targetSiteRoot bin/Microsoft.Dynamics.AX.Metadata.Core.dll
$m_metadata = Join-Path $targetSiteRoot bin/Microsoft.Dynamics.AX.Metadata.dll
$m_storage = Join-Path $targetSiteRoot bin/Microsoft.Dynamics.AX.Metadata.Storage.dll
$m_instrumentation = Join-Path $targetSiteRoot bin/Microsoft.Dynamics.Performance.Instrumentation.dll
$m_xppinstrumentation = Join-Path $targetSiteRoot bin/Microsoft.Dynamics.ApplicationPlatform.XppServices.Instrumentation.dll

if (!(Test-Path $m_core))
{
    $errorMessage = "Error: file $m_core does not exist."
    throw $errorMessage
}

if (!(Test-Path $m_metadata))
{
    $errorMessage = "Error: file $m_metadata does not exist."
    throw $errorMessage
}

if (!(Test-Path $m_storage))
{
    $errorMessage = "Error: file $m_storage does not exist."
    throw $errorMessage
}

if (!(Test-Path $m_instrumentation))
{
    $errorMessage = "Error: file $m_instrumentation does not exist."
    throw $errorMessage
}

if (!(Test-Path $m_xppinstrumentation))
{
    $errorMessage = "Error: file $m_xppinstrumentation does not exist."
    throw $errorMessage
}

[Reflection.Assembly]::LoadFile($m_core)
[Reflection.Assembly]::LoadFile($m_metadata)
[Reflection.Assembly]::LoadFile($m_storage)
[Reflection.Assembly]::LoadFile($m_instrumentation)
[Reflection.Assembly]::LoadFile($m_xppinstrumentation)

$runtimeConfig = new-object -TypeName Microsoft.Dynamics.AX.Metadata.Storage.Runtime.RuntimeProviderConfiguration $PackageDirectory
$factory = New-Object -TypeName Microsoft.Dynamics.AX.Metadata.Storage.MetadataProviderFactory
$provider = $factory.CreateRuntimeProvider($runtimeConfig)

$resourcesDirectory = Join-Path $targetSiteRoot "Resources"
if (!(Test-Path $resourcesDirectory)) {New-Item $resourcesDirectory -ItemType Directory}

$folderTypes = @("Images", "Scripts", "Styles", "Html") 
foreach($folderType in $folderTypes) 
{
    $subFolder = Join-Path $resourcesDirectory $folderType
    if (!(Test-Path $subFolder)) {New-Item $subFolder -ItemType Directory}
}

foreach($name in $provider.Resources.GetPrimaryKeys())
{
    $readHeader = New-Object -TypeName Microsoft.Dynamics.AX.Metadata.MetaModel.MetaReadHeader
    $axResource = $provider.Resources.Read([System.String]$name, [ref]$readHeader)
    $resourceTimeStamp = $provider.Resources.GetContentTimestampUtc($axResource, $readHeader)
    if ($folderTypes -eq $axResource.TypeOfResource)
    {
        $resourcePath = Join-Path $resourcesDirectory $axResource.TypeOfResource
        $resourcePath = Join-Path $resourcePath $axResource.FileName
        $copyFile = $false
        if (!(Test-Path $resourcePath))
        {
            $copyFile = $true
        }
        elseif ($resourceTimeStamp -ne (Get-ItemProperty -Path $resourcePath).LastWriteTimeUtc)
        {
            $copyFile = $true
        }

        if ($copyFile -eq $true)
        {
            $sourceStream = $provider.Resources.GetContent($axResource, $readHeader)
            if ($sourceStream -ne $null)
            {
                $targetStream = New-Object -TypeName System.IO.FileStream -ArgumentList @($resourcePath, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write)
                $sourceStream.CopyTo($targetStream);
                
                $sourceStream.Dispose()
                $targetStream.Dispose()

                Write-Log "Updated $resourcePath"
            }
        }
    }
}

# SIG # Begin signature block
# MIIj/AYJKoZIhvcNAQcCoIIj7TCCI+kCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCBdLzkxSJtGKY7Z
# 5cq8N4ATlQ9aBKW9cRhme/Di8fUrJaCCDYIwggYAMIID6KADAgECAhMzAAAAww6b
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
# SEXAQsmbdlsKgEhr/Xmfwb1tbWrJUnMTDXpQzTGCFdAwghXMAgEBMIGVMH4xCzAJ
# BgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25k
# MR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xKDAmBgNVBAMTH01pY3Jv
# c29mdCBDb2RlIFNpZ25pbmcgUENBIDIwMTECEzMAAADDDpun2LLc9ywAAAAAAMMw
# DQYJYIZIAWUDBAIBBQCggcIwGQYJKoZIhvcNAQkDMQwGCisGAQQBgjcCAQQwHAYK
# KwYBBAGCNwIBCzEOMAwGCisGAQQBgjcCARUwLwYJKoZIhvcNAQkEMSIEIHkgKZLh
# OAA09LsLyoF/DOfJ7Isci1J0YD/m6HEjhEsLMFYGCisGAQQBgjcCAQwxSDBGoCiA
# JgBEAGUAcABsAG8AeQBSAGUAcwBvAHUAcgBjAGUAcwAuAHAAcwAxoRqAGGh0dHA6
# Ly93d3cubWljcm9zb2Z0LmNvbTANBgkqhkiG9w0BAQEFAASCAQBsA6gpPpMmDiFB
# yzTSgFgi8dNKK8nuqV/4SW5mEZPxD4yjMuhnhZeE/MBALzHYRW3ybo/hjrB7VxMq
# HpqbQdQfVsQx3c4iC5prolbLsvOAvC6Iyl5G2AVX9WqcZZjOwMnITetxCbKKW543
# FhyLay+KHIq2eFtbK2vkTtCib1OxRNQiffTJRb8y46W90YZEyczjtg8pKdcGF57n
# QN19TmF0DLf/8aceJjlZx/nJxLyCHF8b00QcJUlgiSnJdhT/wLJLxu3yJA+5k5ce
# GPsOXjQ/FkOZk5XJgZmqwrtPwGc8737eP82Y5dHW2hK8egh3ANz/hTnD+9Bu/67r
# ryXo04rzoYITRjCCE0IGCisGAQQBgjcDAwExghMyMIITLgYJKoZIhvcNAQcCoIIT
# HzCCExsCAQMxDzANBglghkgBZQMEAgEFADCCATwGCyqGSIb3DQEJEAEEoIIBKwSC
# AScwggEjAgEBBgorBgEEAYRZCgMBMDEwDQYJYIZIAWUDBAIBBQAEIERCL+HZEWNi
# +Z9Eq44wkd5eK6QkTuZmxKanUqN/HYxGAgZasptq6g8YEzIwMTgwMzI1MjEwNTU3
# LjM0MVowBwIBAYACAfSggbikgbUwgbIxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpX
# YXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQg
# Q29ycG9yYXRpb24xDDAKBgNVBAsTA0FPQzEnMCUGA1UECxMebkNpcGhlciBEU0Ug
# RVNOOjdBQjUtMkRGMi1EQTNGMSUwIwYDVQQDExxNaWNyb3NvZnQgVGltZS1TdGFt
# cCBTZXJ2aWNloIIOyjCCBnEwggRZoAMCAQICCmEJgSoAAAAAAAIwDQYJKoZIhvcN
# AQELBQAwgYgxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYD
# VQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xMjAw
# BgNVBAMTKU1pY3Jvc29mdCBSb290IENlcnRpZmljYXRlIEF1dGhvcml0eSAyMDEw
# MB4XDTEwMDcwMTIxMzY1NVoXDTI1MDcwMTIxNDY1NVowfDELMAkGA1UEBhMCVVMx
# EzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoT
# FU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRpbWUt
# U3RhbXAgUENBIDIwMTAwggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIBAQCp
# HQ28dxGKOiDs/BOX9fp/aZRrdFQQ1aUKAIKF++18aEssX8XD5WHCdrc+Zitb8BVT
# JwQxH0EbGpUdzgkTjnxhMFmxMEQP8WCIhFRDDNdNuDgIs0Ldk6zWczBXJoKjRQ3Q
# 6vVHgc2/JGAyWGBG8lhHhjKEHnRhZ5FfgVSxz5NMksHEpl3RYRNuKMYa+YaAu99h
# /EbBJx0kZxJyGiGKr0tkiVBisV39dx898Fd1rL2KQk1AUdEPnAY+Z3/1ZsADlkR+
# 79BL/W7lmsqxqPJ6Kgox8NpOBpG2iAg16HgcsOmZzTznL0S6p/TcZL2kAcEgCZN4
# zfy8wMlEXV4WnAEFTyJNAgMBAAGjggHmMIIB4jAQBgkrBgEEAYI3FQEEAwIBADAd
# BgNVHQ4EFgQU1WM6XIoxkPNDe3xGG8UzaFqFbVUwGQYJKwYBBAGCNxQCBAweCgBT
# AHUAYgBDAEEwCwYDVR0PBAQDAgGGMA8GA1UdEwEB/wQFMAMBAf8wHwYDVR0jBBgw
# FoAU1fZWy4/oolxiaNE9lJBb186aGMQwVgYDVR0fBE8wTTBLoEmgR4ZFaHR0cDov
# L2NybC5taWNyb3NvZnQuY29tL3BraS9jcmwvcHJvZHVjdHMvTWljUm9vQ2VyQXV0
# XzIwMTAtMDYtMjMuY3JsMFoGCCsGAQUFBwEBBE4wTDBKBggrBgEFBQcwAoY+aHR0
# cDovL3d3dy5taWNyb3NvZnQuY29tL3BraS9jZXJ0cy9NaWNSb29DZXJBdXRfMjAx
# MC0wNi0yMy5jcnQwgaAGA1UdIAEB/wSBlTCBkjCBjwYJKwYBBAGCNy4DMIGBMD0G
# CCsGAQUFBwIBFjFodHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20vUEtJL2RvY3MvQ1BT
# L2RlZmF1bHQuaHRtMEAGCCsGAQUFBwICMDQeMiAdAEwAZQBnAGEAbABfAFAAbwBs
# AGkAYwB5AF8AUwB0AGEAdABlAG0AZQBuAHQALiAdMA0GCSqGSIb3DQEBCwUAA4IC
# AQAH5ohRDeLG4Jg/gXEDPZ2joSFvs+umzPUxvs8F4qn++ldtGTCzwsVmyWrf9efw
# eL3HqJ4l4/m87WtUVwgrUYJEEvu5U4zM9GASinbMQEBBm9xcF/9c+V4XNZgkVkt0
# 70IQyK+/f8Z/8jd9Wj8c8pl5SpFSAK84Dxf1L3mBZdmptWvkx872ynoAb0swRCQi
# PM/tA6WWj1kpvLb9BOFwnzJKJ/1Vry/+tuWOM7tiX5rbV0Dp8c6ZZpCM/2pif93F
# SguRJuI57BlKcWOdeyFtw5yjojz6f32WapB4pm3S4Zz5Hfw42JT0xqUKloakvZ4a
# rgRCg7i1gJsiOCC1JeVk7Pf0v35jWSUPei45V3aicaoGig+JFrphpxHLmtgOR5qA
# xdDNp9DvfYPw4TtxCd9ddJgiCGHasFAeb73x4QDf5zEHpJM692VHeOj4qEir995y
# fmFrb3epgcunCaw5u+zGy9iCtHLNHfS4hQEegPsbiSpUObJb2sgNVZl6h3M7COaY
# LeqN4DMuEin1wC9UJyH3yKxO2ii4sanblrKnQqLJzxlBTeCG+SqaoxFmMNO7dDJL
# 32N79ZmKLxvHIa9Zta7cRDyXUHHXodLFVeNp3lfB0d4wwP3M5k37Db9dT+mdHhk4
# L7zPWAUu7w2gUDXa7wknHNWzfjUeCLraNtvTX4/edIhJEjCCBNkwggPBoAMCAQIC
# EzMAAACrXkCd7kbfLGwAAAAAAKswDQYJKoZIhvcNAQELBQAwfDELMAkGA1UEBhMC
# VVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNV
# BAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRp
# bWUtU3RhbXAgUENBIDIwMTAwHhcNMTYwOTA3MTc1NjU0WhcNMTgwOTA3MTc1NjU0
# WjCBsjELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcT
# B1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEMMAoGA1UE
# CxMDQU9DMScwJQYDVQQLEx5uQ2lwaGVyIERTRSBFU046N0FCNS0yREYyLURBM0Yx
# JTAjBgNVBAMTHE1pY3Jvc29mdCBUaW1lLVN0YW1wIFNlcnZpY2UwggEiMA0GCSqG
# SIb3DQEBAQUAA4IBDwAwggEKAoIBAQCz5n5QmKBGCbBmASaKNNMpyX2YNZoMLN0z
# ygPPDgLXC++74cguSaTT0Nncc9O7RYWcXeUB9fwrpmKb4YACp/M3KEVLNd64um77
# hpDt4asQ8jjwd8Jbz0AT7jlKG9Iqeh78iwH4qbyaj3kDw+Nw0awA86bAyyHddNTU
# h4Qoga0aWVJi3uz9zMUDiUxNB7Og1B6eewHCOs1jaQmQiBOTwy2UoSwEKbg31Uq1
# MYrkvm6RM9t87swyfFzBLeG4sNYiiSEqJHni5KPPLhnWVclIESSkqMn1SMhSwjGS
# kPpmNgD5oTAaaA+taWRLWvHraZ9zhnq2YB+UkV6OIL3U3w4qkMhLAgMBAAGjggEb
# MIIBFzAdBgNVHQ4EFgQUDcdH0Bxgy+nAa5TMXwYOYrjYaqcwHwYDVR0jBBgwFoAU
# 1WM6XIoxkPNDe3xGG8UzaFqFbVUwVgYDVR0fBE8wTTBLoEmgR4ZFaHR0cDovL2Ny
# bC5taWNyb3NvZnQuY29tL3BraS9jcmwvcHJvZHVjdHMvTWljVGltU3RhUENBXzIw
# MTAtMDctMDEuY3JsMFoGCCsGAQUFBwEBBE4wTDBKBggrBgEFBQcwAoY+aHR0cDov
# L3d3dy5taWNyb3NvZnQuY29tL3BraS9jZXJ0cy9NaWNUaW1TdGFQQ0FfMjAxMC0w
# Ny0wMS5jcnQwDAYDVR0TAQH/BAIwADATBgNVHSUEDDAKBggrBgEFBQcDCDANBgkq
# hkiG9w0BAQsFAAOCAQEAP5/+ui5h8XIqraoVZpWgBEt9s8JG3dDrW0A89Ix1Ba2h
# gW8kew0u0qOJuvA2K/nIxXcOerh83lTi/Q8mXzwMdi36GNGiEKiIXksqWZXIX3d/
# /kQkuAKZhJGUrwLHpiqGhLGL+JEkx9Buoza/+/i4B5pvPmnttvGbYWdUrTbo2/La
# 5WKmO8htzEOaJiLzRIzrLUcmddPC5pvWip0VT5PogCDODi2VA1PzQOAa3GlcTCHX
# ShMoL0XVgv2kwd8hO8nrPzilPzL6zQZLuB+8mxqzkbGTXeL/eaEW0bg19uGRyvdx
# 7P3+isPgZTVYy6ReD5bmpyKvaPM+z96kjarY7hKk4qGCA3QwggJcAgEBMIHioYG4
# pIG1MIGyMQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UE
# BxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMQwwCgYD
# VQQLEwNBT0MxJzAlBgNVBAsTHm5DaXBoZXIgRFNFIEVTTjo3QUI1LTJERjItREEz
# RjElMCMGA1UEAxMcTWljcm9zb2Z0IFRpbWUtU3RhbXAgU2VydmljZaIlCgEBMAkG
# BSsOAwIaBQADFQDJ7LtILTXZlL62jvcmqTFuioeOMqCBwTCBvqSBuzCBuDELMAkG
# A1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQx
# HjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEMMAoGA1UECxMDQU9DMScw
# JQYDVQQLEx5uQ2lwaGVyIE5UUyBFU046MjY2NS00QzNGLUM1REUxKzApBgNVBAMT
# Ik1pY3Jvc29mdCBUaW1lIFNvdXJjZSBNYXN0ZXIgQ2xvY2swDQYJKoZIhvcNAQEF
# BQACBQDeYeq9MCIYDzIwMTgwMzI1MDkzMDM3WhgPMjAxODAzMjYwOTMwMzdaMHQw
# OgYKKwYBBAGEWQoEATEsMCowCgIFAN5h6r0CAQAwBwIBAAICJcUwBwIBAAICGi4w
# CgIFAN5jPD0CAQAwNgYKKwYBBAGEWQoEAjEoMCYwDAYKKwYBBAGEWQoDAaAKMAgC
# AQACAxbjYKEKMAgCAQACAwehIDANBgkqhkiG9w0BAQUFAAOCAQEAflovTIqPyKqQ
# wuGpjEIZDLfk9RfKCXPgLP+4Cc276S7EZOqhPvFDyy/mdOCQbaYYZdNu7lNff4Mw
# i43JQYEIXvOWVe3pmoSzReQ8NMeFoRoBsStDREkoMcVGUky6g3k53uIfUHiAj+C5
# wKZluijJoPvFMl8F4SbIEOiPkMu0KTeq2uWPz9A2xzL3F0ILYjQxWfEf+guN5tIi
# ZERwULdOJX/r5wHORdT3GCNlhqmT+J8x8Jedwk0SIZi1QxNnIABNR18Bwpjpd6Ag
# LJ2wTLJnFzSqrLDS+h1wpM4j4uCNl5ds9PiyAD9QFr+Dz7B1mjeMp/IZeMZDZPdn
# V2GC4oMoLDGCAvUwggLxAgEBMIGTMHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpX
# YXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQg
# Q29ycG9yYXRpb24xJjAkBgNVBAMTHU1pY3Jvc29mdCBUaW1lLVN0YW1wIFBDQSAy
# MDEwAhMzAAAAq15Ane5G3yxsAAAAAACrMA0GCWCGSAFlAwQCAQUAoIIBMjAaBgkq
# hkiG9w0BCQMxDQYLKoZIhvcNAQkQAQQwLwYJKoZIhvcNAQkEMSIEIOByW3c4HCZP
# RU4uDmqlpEa1p5SYCweHO3xSZjuhsZetMIHiBgsqhkiG9w0BCRACDDGB0jCBzzCB
# zDCBsQQUyey7SC012ZS+to73JqkxboqHjjIwgZgwgYCkfjB8MQswCQYDVQQGEwJV
# UzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UE
# ChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGlt
# ZS1TdGFtcCBQQ0EgMjAxMAITMwAAAKteQJ3uRt8sbAAAAAAAqzAWBBT0RnysaGwE
# 6q+AkONWphYTpvDGOTANBgkqhkiG9w0BAQsFAASCAQADC6iCwCg0Yj0hdizH7ri9
# YJCgkXPsdxPHDYC4+HiqocD+jXEX4haEKVgsH4e9d/1bmbSkORlp8woJ1lQWQSsA
# vihLZ/OVbYKiagd1wrV13Ekt2MWOfe7AkSx61jKhD5Q67ip7SwtZw/ip7KFcc+ig
# zEQSFRvNipFmW5jpFsvX382tH99hE4Tqjs9EQKFq3qONFyHWcWHK6E/w523neCOv
# LTMlrYqAymQ4wJBGASfPp3ppaoBn4HjkGeyagk9OflKO0wX8BYmfxz1oMZqA9p3G
# fwrM1eHID7QlzMp6f2W6le0QJkPqUzOp2dnVxitadAebJNyGAcz+L9v/gGvbsh/G
# SIG # End signature block
