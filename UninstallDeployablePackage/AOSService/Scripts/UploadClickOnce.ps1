param
(
    [Parameter(Mandatory=$true)]
    $config,
    [Parameter(Mandatory=$true)]
    $log
)


function GetStorageAccountName([string]$connectionString)
{
    $splitConnectionString = $connectionString.Split(";")
    foreach($splitPart in $splitConnectionString)
    {
        $individualPart = $splitPart.Split("=")
        if($individualPart[0] -eq "AccountName")
        {
            return $individualPart[1]
        }
    }
}

function Get-BlobMetadata($blob)
{
    $metadata = new-object 'System.Collections.Generic.Dictionary``2[System.String,System.String]'
    if($blob -ne $null)
    {
        foreach($attribute in $blob.Attributes)
        {
            $metadata.Add($attribute.name,$attribute.value)
        }
    }

    return $metadata
}

Import-Module "$PSScriptRoot\AosCommon.psm1" -Force -DisableNameChecking
Initialize-Log $log

Write-Log "Decoding settings"
$settings = Decode-Settings $config

$buildRegistrationData = join-path $PSScriptRoot "BuildRegistrationData.xml"
[System.Reflection.Assembly]::LoadFrom("$PSScriptRoot\Microsoft.WindowsAzure.Storage.dll") | Out-Null   
[System.Reflection.Assembly]::LoadFrom("$PSScriptRoot\Microsoft.WindowsAzure.StorageClient.dll") | Out-Null
[System.Reflection.Assembly]::LoadFrom("$PSScriptRoot\Microsoft.DynamicsOnline.Deployment.Providers.dll") | Out-Null
[System.Reflection.Assembly]::LoadFrom("$PSScriptRoot\Microsoft.DynamicsOnline.Deployment.Engine.dll") | Out-Null
[System.Reflection.Assembly]::LoadFrom("$PSScriptRoot\Microsoft.DynamicsOnline.Infrastructure.dll") | Out-Null


[System.Reflection.Assembly]::LoadWithPartialName("System.Collections.Generic") | Out-Null
    
$storageConnectionString = $settings.'AzureStorage.StorageConnectionString'

$storageAccountName = GetStorageAccountName -connectionString:$storageConnectionString
Write-Log "Azure storage account name: '$storageAccountName'."

[xml]$blobs = Get-Content $buildRegistrationData
$cloudStorageAccount = [Microsoft.WindowsAzure.Storage.CloudStorageAccount]::Parse($storageConnectionString)
$cloudBlobClient = $cloudStorageAccount.CreateCloudBlobClient()
    
foreach($blob in $blobs.Build.Blobs.Blob)
{
    $container = $blob.container    
    $blobFqdn = join-path $($settings.'Infrastructure.WebRoot') $blob.path
    $name = $blob.name
    if(Test-Path "$blobFqdn")
    {
        $cloudBlobContainer = $cloudBlobClient.GetContainerReference($container)
        $cloudBlobContainer.CreateIfNotExists()
        $permissions = $cloudBlobContainer.GetPermissions()
        if($blob.PublicAccess -eq "true")
        {
            $publicAccessPermission = [Microsoft.WindowsAzure.Storage.Blob.BlobContainerPublicAccessType]::Blob
        }
        else
        {
            $publicAccessPermission = [Microsoft.WindowsAzure.Storage.Blob.BlobContainerPublicAccessType]::Off
        }

        if($permissions.PublicAccess -ne $publicAccessPermission)
        {
            $permissions.PublicAccess = $publicAccessPermission
        }

        $cloudBlobContainer.SetPermissions($permissions)
        $blobMetadata = Get-BlobMetadata($blob)
        $blobContainer = new-object -typename Microsoft.DynamicsOnline.Deployment.Providers.BlobContainer -ArgumentList $cloudBlobContainer
        Write-Log "Uploading blob '$name' to the container '$container' in Azure storage account '$storageAccountName'."
        $blobContainer.UploadFile($blobFqdn,$name,$blobMetadata,$blob.contentType)
    }
    else
    {
        Write-Log "Skipping blob '$name' as it does not exist at '$blobFqdn'."
    }
}
# SIG # Begin signature block
# MIIj/AYJKoZIhvcNAQcCoIIj7TCCI+kCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCCOzDBF9hbCfOYx
# 1oEod1Q4Hr1dmJmqV2Mmqu4j0DGHRqCCDYIwggYAMIID6KADAgECAhMzAAAAww6b
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
# KwYBBAGCNwIBCzEOMAwGCisGAQQBgjcCARUwLwYJKoZIhvcNAQkEMSIEICJ5QhEx
# JJgd0Bs4CIXYpZygrWrQhyoGtg1oclso63wdMFYGCisGAQQBgjcCAQwxSDBGoCiA
# JgBVAHAAbABvAGEAZABDAGwAaQBjAGsATwBuAGMAZQAuAHAAcwAxoRqAGGh0dHA6
# Ly93d3cubWljcm9zb2Z0LmNvbTANBgkqhkiG9w0BAQEFAASCAQAM7PxsBTNbUxWz
# UCVapaSXIvVCvAp5usDmm6FcOUgjpBgayOQQcbcZ7cwU8/XZCvXpEZRoQPxClIXH
# SDstkLLDYP0x8pghq5RoXIuBX5i1o8uz2vSQmLAtvcSVeIbG9/QgvjmBr+PDW8Bg
# 4rM2VulNDOp1sHyUqPDQtckZHYYj0OZvlPHj1KR5iyoowZyQT8cMtomMY6QB0tCX
# yk1FWFg9Oyi0mqlK1cZLYSWK9ZL4vsHvZgRhkmjjxXCITSdx+8/zcm21KXXProQA
# WSIKYv23gt8CbTqXpYzzsq4PRG5PQ0+PTENAmRBpnal0m/BASHwcgx00k8/XYDI5
# Z8qubEU7oYITRjCCE0IGCisGAQQBgjcDAwExghMyMIITLgYJKoZIhvcNAQcCoIIT
# HzCCExsCAQMxDzANBglghkgBZQMEAgEFADCCATwGCyqGSIb3DQEJEAEEoIIBKwSC
# AScwggEjAgEBBgorBgEEAYRZCgMBMDEwDQYJYIZIAWUDBAIBBQAEIB2w4hJM2H9P
# ZiF+Ey0OpLU+oSsha3zZnuMRQ+UhsqlaAgZasnRJxsAYEzIwMTgwMzI1MjEwNTUy
# LjQ5NlowBwIBAYACAfSggbikgbUwgbIxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpX
# YXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQg
# Q29ycG9yYXRpb24xDDAKBgNVBAsTA0FPQzEnMCUGA1UECxMebkNpcGhlciBEU0Ug
# RVNOOkY2RkYtMkRBNy1CQjc1MSUwIwYDVQQDExxNaWNyb3NvZnQgVGltZS1TdGFt
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
# EzMAAAClSBdyJ/lwvmMAAAAAAKUwDQYJKoZIhvcNAQELBQAwfDELMAkGA1UEBhMC
# VVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNV
# BAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRp
# bWUtU3RhbXAgUENBIDIwMTAwHhcNMTYwOTA3MTc1NjUwWhcNMTgwOTA3MTc1NjUw
# WjCBsjELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcT
# B1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEMMAoGA1UE
# CxMDQU9DMScwJQYDVQQLEx5uQ2lwaGVyIERTRSBFU046RjZGRi0yREE3LUJCNzUx
# JTAjBgNVBAMTHE1pY3Jvc29mdCBUaW1lLVN0YW1wIFNlcnZpY2UwggEiMA0GCSqG
# SIb3DQEBAQUAA4IBDwAwggEKAoIBAQC02pLUvUxe8NtXB99ZYYE6JrbTGLNpw/37
# zCNv0g3M0xtWFsxQTb7DEvtc1sE0s8I5ybT7Ifoy12FsCgpebk++Cpcv0a0C5OHQ
# 72mBnx8yxk2EJv3ie6jSIiw88cwrOTIv/hvsnk9v/YvHVPOFnX6CS1ISju4PYz22
# N0T6Tlu7X92P/uaF1wNSEZ7BlP81+4cy9hMgkaeaN6HyT6QyVEvgKBTl5yGG7dbD
# mpk0ISYwdQeYoGXoU7fQmVqUEma721ZWNNREkWGJ0LjUXzpO5YA6x/JSmzp119x2
# qCBTIMcZtxRVdXz7ygIiDqFLgfOw5lnFGqULgcoXAj5qxQuOv8G3AgMBAAGjggEb
# MIIBFzAdBgNVHQ4EFgQU4hOrS/LtsWC4ePGFoFH+cuexL6QwHwYDVR0jBBgwFoAU
# 1WM6XIoxkPNDe3xGG8UzaFqFbVUwVgYDVR0fBE8wTTBLoEmgR4ZFaHR0cDovL2Ny
# bC5taWNyb3NvZnQuY29tL3BraS9jcmwvcHJvZHVjdHMvTWljVGltU3RhUENBXzIw
# MTAtMDctMDEuY3JsMFoGCCsGAQUFBwEBBE4wTDBKBggrBgEFBQcwAoY+aHR0cDov
# L3d3dy5taWNyb3NvZnQuY29tL3BraS9jZXJ0cy9NaWNUaW1TdGFQQ0FfMjAxMC0w
# Ny0wMS5jcnQwDAYDVR0TAQH/BAIwADATBgNVHSUEDDAKBggrBgEFBQcDCDANBgkq
# hkiG9w0BAQsFAAOCAQEANn1teSvGLi8kIMol9TQVjNzyS0cH9KM+7oZ4CN57h9YG
# xVjp+8vzF04f6TGgxtDCZgOfrs3w7JwrWZOCU7qRERwKnsdiGlqj1RbLLabqwPK0
# /3l++w7wM+pOG65c2vRQLuhLqGcZBqvH38F9YQUiMGHOpZjAwAIofWkxKZkgbqQ2
# 5+KU0oRs3A0aScn14zZVbW331VsR1Dm6AN+m0STLSTG8JYCCYKTrGeYhgmkvSJKy
# UMUPDp033x68/rhy65ND/lvGHxteoGhd3g4U5CLUahVW5Oji562Pyic4YmbWbNsm
# Ei8Jg8WucEHiOR6ELQux74lwJlIEMuk8DAOebGz4bqGCA3QwggJcAgEBMIHioYG4
# pIG1MIGyMQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UE
# BxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMQwwCgYD
# VQQLEwNBT0MxJzAlBgNVBAsTHm5DaXBoZXIgRFNFIEVTTjpGNkZGLTJEQTctQkI3
# NTElMCMGA1UEAxMcTWljcm9zb2Z0IFRpbWUtU3RhbXAgU2VydmljZaIlCgEBMAkG
# BSsOAwIaBQADFQCbwjXd+7ImKxoUMWVQLx1TlGmCb6CBwTCBvqSBuzCBuDELMAkG
# A1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQx
# HjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEMMAoGA1UECxMDQU9DMScw
# JQYDVQQLEx5uQ2lwaGVyIE5UUyBFU046MjY2NS00QzNGLUM1REUxKzApBgNVBAMT
# Ik1pY3Jvc29mdCBUaW1lIFNvdXJjZSBNYXN0ZXIgQ2xvY2swDQYJKoZIhvcNAQEF
# BQACBQDeYesXMCIYDzIwMTgwMzI1MDkzMjA3WhgPMjAxODAzMjYwOTMyMDdaMHQw
# OgYKKwYBBAGEWQoEATEsMCowCgIFAN5h6xcCAQAwBwIBAAICLcEwBwIBAAICGIgw
# CgIFAN5jPJcCAQAwNgYKKwYBBAGEWQoEAjEoMCYwDAYKKwYBBAGEWQoDAaAKMAgC
# AQACAxbjYKEKMAgCAQACAwehIDANBgkqhkiG9w0BAQUFAAOCAQEAYck2lC3t5JaS
# 3af4+szThRs18bJYaYr366welafDuAHCEJuRcx9tA9VDdxXVkJNGEvZq4pAKYix1
# uwI97QQX6tJ5e0kqaLt+77uEwFufQj/kxBVVwN14oowjyZAv+LB3CiybZZX+8IVq
# v9opiMaLZ0aST/buEWpiAr8NBUzsF6xKioED1CzRE+6hw1z1aDNmcpf+4OgwxsNt
# KmbgxsnSRv3lrfYshwz9pwabXaqmKv98sccq8z9ynaZAPVDNPFcz5mwdCjXc60nm
# Ji8cnASGxkbS25zsS/pw/bnFp/wEfBJF/KEX4LYbz+vB59AKRFL4iiO1Alo2U6Td
# yUAC0aAVhTGCAvUwggLxAgEBMIGTMHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpX
# YXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQg
# Q29ycG9yYXRpb24xJjAkBgNVBAMTHU1pY3Jvc29mdCBUaW1lLVN0YW1wIFBDQSAy
# MDEwAhMzAAAApUgXcif5cL5jAAAAAAClMA0GCWCGSAFlAwQCAQUAoIIBMjAaBgkq
# hkiG9w0BCQMxDQYLKoZIhvcNAQkQAQQwLwYJKoZIhvcNAQkEMSIEIM+Mh4wpIMsO
# YiPsSDw32fNWBngnGEURvGYizMicg8sNMIHiBgsqhkiG9w0BCRACDDGB0jCBzzCB
# zDCBsQQUm8I13fuyJisaFDFlUC8dU5Rpgm8wgZgwgYCkfjB8MQswCQYDVQQGEwJV
# UzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UE
# ChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGlt
# ZS1TdGFtcCBQQ0EgMjAxMAITMwAAAKVIF3In+XC+YwAAAAAApTAWBBRTuaz69p++
# yIlnWGVdpZKQIz1F2zANBgkqhkiG9w0BAQsFAASCAQBc5eRq26UqHb8DNFFP3XCD
# Fr90uic6upAQLSw3XWj9hvjZjWx49uTdgcQNK22yFI7tDKY5j1TYAhPOdRlppMbu
# DM/63WGtcbzA6OqjgkVnaC50S8OUTxZs1/fl03HeOduzdhSruAj3hlAvcnaBnU+4
# PAjSLLDodd6YHUU6xXqmpHOWT7ITnRGeL6OXDNOihvBgUOh5jnVFuO/FQ3wqnMfC
# cy9FJSAHPyKmTAkOW/FsG0U3WoLuRmiqY5XPWGsY4gAMn1ElyQpDJpPiJw8IDw3h
# C5hPKuh4qGcTU/5rGll3VOA0gwyw6vGb83p2xI28JVh1MMKCwuvdoZtzLOoaag5X
# SIG # End signature block
