param
(
    [Parameter(Mandatory=$true)]
    $config,
    [Parameter(Mandatory=$true)]
    $log
)

function Fix-SqlSequences($settings)
{
    $SqlSequenceFixScriptPath =  Join-Path $PSScriptRoot "SQLSequencePatch.sql"

    if (!(Test-Path $SqlSequenceFixScriptPath))
    {
        throw "Could not find script at path '$SqlSequenceFixScriptPath'"
    }

    Write-Log "Executing script to fix sql sequences from $SqlSequenceFixScriptPath"
    $deploymentSqlPwd = Get-KeyVaultSecret -VaultUri $settings.'DataAccess.DeploymentSqlPwd'
    $TimeoutSec = 15*60
    Invoke-Sqlcmd -InputFile $SqlSequenceFixScriptPath -ServerInstance "$($settings.'DataAccess.DbServer')" -Username "$($settings.'DataAccess.DeploymentSqlUser')" -Password $deploymentSqlPwd -Database "$($settings.'DataAccess.Database')" -QueryTimeout $TimeoutSec -ConnectionTimeout $TimeoutSec
    Write-Log "Sql sequences are now fixed"
}

Import-Module "$PSScriptRoot\AosCommon.psm1" -Force -DisableNameChecking
Initialize-Log $log

Write-Log "Decoding settings"
$settings = Decode-Settings $config

$keyVaultModule = Join-Path -Path $PSScriptRoot -ChildPath "KeyVault.psm1"

$keyVaultName = $settings.'Infrastructure.AzureKeyVaultName'
$appId = $settings.'Infrastructure.AzureKeyVaultAppId'
$thumprint = $settings.'Infrastructure.AzureKeyVaultCertThumbprint'

Import-Module $keyVaultModule -ArgumentList ($keyVaultName, $appId, $thumprint)

$sqlPwd = Get-KeyVaultSecret -VaultUri $settings.'DataAccess.SqlPwd'

$script:SqlDictExists = $false
ExecuteWith-Retry `
{        
    $script:SqlDictExists = SqlTableExists "SqlDictionary" $settings.'DataAccess.DbServer' $settings.'DataAccess.Database' $settings.'DataAccess.SqlUser' $sqlPwd
} `
"Check if SqlDictionary table exists"

if ($script:SqlDictExists -eq $true)
{
    Fix-SqlSequences $settings
}

$codeFolder = Resolve-Path "$($settings.'Common.BinDir')"

$command = "$codeFolder\bin\Microsoft.Dynamics.AX.Deployment.Setup.exe"

$commandParameter = "-bindir `"$($settings.'Common.BinDir')`""
$commandParameter += " -metadatadir `"$($settings.'Common.BinDir')`""
$commandParameter += " -sqluser `"$($settings.'DataAccess.DeploymentSqlUser')`""
$commandParameter += " -sqlserver `"$($settings.'DataAccess.DbServer')`""
$commandParameter += " -sqldatabase `"$($settings.'DataAccess.Database')`""

$EditionQuery = "select serverproperty('Edition') as Edition"
Write-Log "Determining if database is hosted in Azure using query: [$EditionQuery]"

$deploymentSqlPwd = Get-KeyVaultSecret -VaultUri $settings.'DataAccess.DeploymentSqlPwd'
$SqlEditionResult = Invoke-SqlCmd -Query $EditionQuery -ServerInstance "$($settings.'DataAccess.DbServer')" -Username "$($settings.'DataAccess.DeploymentSqlUser')" -Password $deploymentSqlPwd -Database "$($settings.'DataAccess.Database')"
if ($SqlEditionResult.Edition -eq 'SQL Azure')
{
    Write-Log "Database is hosted in Azure, setting isAzureSql = true"
    $commandParameter += " -isazuresql `"true`""
}
else
{
    Write-Log "Database is not hosted in Azure"
}

$syncCommandParameter = $commandParameter
$syncCommandParameter += " -setupmode `"sync`" -syncmode `"fullall`""

Write-Log "DbSync command: $command $syncCommandParameter"

#adding password to the command
$syncCommandParameter += " -sqlpwd `"$($deploymentSqlPwd)`""

$OutputDir = split-path $log
$OutputPath = "$OutputDir\dbsync.log"
$ErrorPath = "$OutputDir\dbsync.error.log"

Write-Log "Output file is located at $OutputPath"
Write-Log "Error file is located at $ErrorPath"

$syncCommandParameter += " -logfilename `"$OutputPath`""

Set-Location "$codeFolder\bin"
$process = Start-Process $command $syncCommandParameter -PassThru -Wait -RedirectStandardError $ErrorPath

if ($process.ExitCode -ne 0)
{
    throw "DBSync returned error code $($process.ExitCode). See error file for details."
}

Write-Log "DbSync completed."

Write-Log "Running dimensions sync."

$dimensionsCommandParameter = $commandParameter
$dimensionsCommandParameter += " -setupmode `"DimensionsSynchronization`""
Write-Log "Dimensions sync command: $command $dimensionsCommandParameter"
#adding password to the command
$dimensionsCommandParameter += " -sqlpwd `"$($deploymentSqlPwd)`""

$OutputPath = "$OutputDir\dimensionssync.log"
$ErrorPath = "$OutputDir\dimensionssync.error.log"

Write-Log "Output file is located at $OutputPath"
Write-Log "Error file is located at $ErrorPath"

$process = Start-Process $command $dimensionsCommandParameter -PassThru -Wait -RedirectStandardOutput $OutputPath -RedirectStandardError $ErrorPath

if ($process.ExitCode -ne 0)
{
    throw "Dimensions sync returned error code $($process.ExitCode). See error file for details."
}

Write-Log "Dimensions sync completed."

Write-Log "Completed."
# SIG # Begin signature block
# MIIj6gYJKoZIhvcNAQcCoIIj2zCCI9cCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCAkE/OQnz0eT+0h
# H9B5MFx7yHqejdqvORw6ZdnhkIX1h6CCDYIwggYAMIID6KADAgECAhMzAAAAww6b
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
# KwYBBAGCNwIBCzEOMAwGCisGAQQBgjcCARUwLwYJKoZIhvcNAQkEMSIEIAjqz7tf
# wyF9n7shcYSEfdldDECO/14Z/O0Pi8FQ9lNnMEQGCisGAQQBgjcCAQwxNjA0oBaA
# FABEAGIAUwB5AG4AYwAuAHAAcwAxoRqAGGh0dHA6Ly93d3cubWljcm9zb2Z0LmNv
# bTANBgkqhkiG9w0BAQEFAASCAQBGTSZHGNxzpi0ZPicI2ZM3c5qWVf7AA4HnLF2B
# zPZN/282UknDHHvt54tFUrEpSDDeI+pubWdAdDbZibGz++SD3vvC7ZHX6TFn7/xO
# sLBgX79gBd+wD+0wJLv4yc10fBUPWxL7T/LvykwS8s+r+pxI/UtY+EBJdym0Sdyy
# 8VYf8RAhSVX77TS2IUAyWtWHZLDrJM/1PtOOmuEuxDUxYN6OVFz5mRtJZXjlMSLI
# yA1Ews3e8E3oz7f6SOAXUY2T3z8ayCgc1orJdk1wDvB/eU+LSslnTqGPEVm3EQv8
# vCfr946NO8ZWU3ECzRefNin67+WNspuxxG7L7akbizMOzR0QoYITRjCCE0IGCisG
# AQQBgjcDAwExghMyMIITLgYJKoZIhvcNAQcCoIITHzCCExsCAQMxDzANBglghkgB
# ZQMEAgEFADCCATwGCyqGSIb3DQEJEAEEoIIBKwSCAScwggEjAgEBBgorBgEEAYRZ
# CgMBMDEwDQYJYIZIAWUDBAIBBQAEIMIShxXEArjXD9t/wQ8UXREgBKAw+ptTd71t
# fIC9paIiAgZasqW7zZcYEzIwMTgwMzI1MjEwNTUyLjE0N1owBwIBAYACAfSggbik
# gbUwgbIxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQH
# EwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xDDAKBgNV
# BAsTA0FPQzEnMCUGA1UECxMebkNpcGhlciBEU0UgRVNOOjEyRTctMzA2NC02MTEy
# MSUwIwYDVQQDExxNaWNyb3NvZnQgVGltZS1TdGFtcCBTZXJ2aWNloIIOyjCCBnEw
# ggRZoAMCAQICCmEJgSoAAAAAAAIwDQYJKoZIhvcNAQELBQAwgYgxCzAJBgNVBAYT
# AlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYD
# VQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xMjAwBgNVBAMTKU1pY3Jvc29mdCBS
# b290IENlcnRpZmljYXRlIEF1dGhvcml0eSAyMDEwMB4XDTEwMDcwMTIxMzY1NVoX
# DTI1MDcwMTIxNDY1NVowfDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0
# b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3Jh
# dGlvbjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRpbWUtU3RhbXAgUENBIDIwMTAwggEi
# MA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIBAQCpHQ28dxGKOiDs/BOX9fp/aZRr
# dFQQ1aUKAIKF++18aEssX8XD5WHCdrc+Zitb8BVTJwQxH0EbGpUdzgkTjnxhMFmx
# MEQP8WCIhFRDDNdNuDgIs0Ldk6zWczBXJoKjRQ3Q6vVHgc2/JGAyWGBG8lhHhjKE
# HnRhZ5FfgVSxz5NMksHEpl3RYRNuKMYa+YaAu99h/EbBJx0kZxJyGiGKr0tkiVBi
# sV39dx898Fd1rL2KQk1AUdEPnAY+Z3/1ZsADlkR+79BL/W7lmsqxqPJ6Kgox8NpO
# BpG2iAg16HgcsOmZzTznL0S6p/TcZL2kAcEgCZN4zfy8wMlEXV4WnAEFTyJNAgMB
# AAGjggHmMIIB4jAQBgkrBgEEAYI3FQEEAwIBADAdBgNVHQ4EFgQU1WM6XIoxkPND
# e3xGG8UzaFqFbVUwGQYJKwYBBAGCNxQCBAweCgBTAHUAYgBDAEEwCwYDVR0PBAQD
# AgGGMA8GA1UdEwEB/wQFMAMBAf8wHwYDVR0jBBgwFoAU1fZWy4/oolxiaNE9lJBb
# 186aGMQwVgYDVR0fBE8wTTBLoEmgR4ZFaHR0cDovL2NybC5taWNyb3NvZnQuY29t
# L3BraS9jcmwvcHJvZHVjdHMvTWljUm9vQ2VyQXV0XzIwMTAtMDYtMjMuY3JsMFoG
# CCsGAQUFBwEBBE4wTDBKBggrBgEFBQcwAoY+aHR0cDovL3d3dy5taWNyb3NvZnQu
# Y29tL3BraS9jZXJ0cy9NaWNSb29DZXJBdXRfMjAxMC0wNi0yMy5jcnQwgaAGA1Ud
# IAEB/wSBlTCBkjCBjwYJKwYBBAGCNy4DMIGBMD0GCCsGAQUFBwIBFjFodHRwOi8v
# d3d3Lm1pY3Jvc29mdC5jb20vUEtJL2RvY3MvQ1BTL2RlZmF1bHQuaHRtMEAGCCsG
# AQUFBwICMDQeMiAdAEwAZQBnAGEAbABfAFAAbwBsAGkAYwB5AF8AUwB0AGEAdABl
# AG0AZQBuAHQALiAdMA0GCSqGSIb3DQEBCwUAA4ICAQAH5ohRDeLG4Jg/gXEDPZ2j
# oSFvs+umzPUxvs8F4qn++ldtGTCzwsVmyWrf9efweL3HqJ4l4/m87WtUVwgrUYJE
# Evu5U4zM9GASinbMQEBBm9xcF/9c+V4XNZgkVkt070IQyK+/f8Z/8jd9Wj8c8pl5
# SpFSAK84Dxf1L3mBZdmptWvkx872ynoAb0swRCQiPM/tA6WWj1kpvLb9BOFwnzJK
# J/1Vry/+tuWOM7tiX5rbV0Dp8c6ZZpCM/2pif93FSguRJuI57BlKcWOdeyFtw5yj
# ojz6f32WapB4pm3S4Zz5Hfw42JT0xqUKloakvZ4argRCg7i1gJsiOCC1JeVk7Pf0
# v35jWSUPei45V3aicaoGig+JFrphpxHLmtgOR5qAxdDNp9DvfYPw4TtxCd9ddJgi
# CGHasFAeb73x4QDf5zEHpJM692VHeOj4qEir995yfmFrb3epgcunCaw5u+zGy9iC
# tHLNHfS4hQEegPsbiSpUObJb2sgNVZl6h3M7COaYLeqN4DMuEin1wC9UJyH3yKxO
# 2ii4sanblrKnQqLJzxlBTeCG+SqaoxFmMNO7dDJL32N79ZmKLxvHIa9Zta7cRDyX
# UHHXodLFVeNp3lfB0d4wwP3M5k37Db9dT+mdHhk4L7zPWAUu7w2gUDXa7wknHNWz
# fjUeCLraNtvTX4/edIhJEjCCBNkwggPBoAMCAQICEzMAAACsiiG8etKbcvQAAAAA
# AKwwDQYJKoZIhvcNAQELBQAwfDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hp
# bmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jw
# b3JhdGlvbjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRpbWUtU3RhbXAgUENBIDIwMTAw
# HhcNMTYwOTA3MTc1NjU0WhcNMTgwOTA3MTc1NjU0WjCBsjELMAkGA1UEBhMCVVMx
# EzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoT
# FU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEMMAoGA1UECxMDQU9DMScwJQYDVQQLEx5u
# Q2lwaGVyIERTRSBFU046MTJFNy0zMDY0LTYxMTIxJTAjBgNVBAMTHE1pY3Jvc29m
# dCBUaW1lLVN0YW1wIFNlcnZpY2UwggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEK
# AoIBAQChxPQ8pY5zMaEXQVyrdwi3qdFDqrvf3HT5ujVWaoQJ2Km7+1T3GNnGpbND
# 6PomAcw9NfV+C+RMmCrThpUlBVzeuzsNL2Lsj9mMdK83ixebazenSrA0rXLIifWB
# zKHVP6jzsQWo96cHukHZqI8xRp3tYivgapt5LLrn9Rm2Jn+E0h2lKDOw5sIteZir
# iOMPH2Z7mtgYXmyB8ThgdB46p6frNGpcXr11pa1Vkldl0iY6oBAKQQSxJ5Bn4N7u
# i5Wj5wDkDZzGAg6n1ptMPTPJhL2uosW84YjnSp/2suNap3qOjKEYXmpGzvasq5qy
# qPyvfqfksOfNBaJntfpC8dIDJKrnAgMBAAGjggEbMIIBFzAdBgNVHQ4EFgQU2Edw
# qIU1ixNhr4eQ6EUXJOCYpw0wHwYDVR0jBBgwFoAU1WM6XIoxkPNDe3xGG8UzaFqF
# bVUwVgYDVR0fBE8wTTBLoEmgR4ZFaHR0cDovL2NybC5taWNyb3NvZnQuY29tL3Br
# aS9jcmwvcHJvZHVjdHMvTWljVGltU3RhUENBXzIwMTAtMDctMDEuY3JsMFoGCCsG
# AQUFBwEBBE4wTDBKBggrBgEFBQcwAoY+aHR0cDovL3d3dy5taWNyb3NvZnQuY29t
# L3BraS9jZXJ0cy9NaWNUaW1TdGFQQ0FfMjAxMC0wNy0wMS5jcnQwDAYDVR0TAQH/
# BAIwADATBgNVHSUEDDAKBggrBgEFBQcDCDANBgkqhkiG9w0BAQsFAAOCAQEASOzo
# XifDGxicXbTOdm43DB9dYxwNXaQj0hW0ztBACeWbX6zxee1w7TJeXQx1IfTz1BWJ
# AfVla7HA1oxa0LiF/Uf6rfRvEEmGmHr9wWEbr3xiErllTFE2V/mdYBSEwdj74m8Q
# LBeFY37Cjx4TFe+AB/FQly3kvfrJKDaYYTTXTAFYAKpi0AcDTcESXZcshJ/O8UZs
# 9fr0BgrOm5h7qeQ1CJNmDMVEqElQt/cFO3dxqrAKv3Fu/nsT5GkABu+vIibgxX6t
# NmqccIIXKALgv7zDIaRAAWtXV9LwnmstDUbIp8dH/oSVm3tPnCPlrB3+C28vPnvJ
# dbtJi/yOuETd+rLn+qGCA3QwggJcAgEBMIHioYG4pIG1MIGyMQswCQYDVQQGEwJV
# UzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UE
# ChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMQwwCgYDVQQLEwNBT0MxJzAlBgNVBAsT
# Hm5DaXBoZXIgRFNFIEVTTjoxMkU3LTMwNjQtNjExMjElMCMGA1UEAxMcTWljcm9z
# b2Z0IFRpbWUtU3RhbXAgU2VydmljZaIlCgEBMAkGBSsOAwIaBQADFQA5cCWLFMh5
# 3V8MXemLnLOUmfcct6CBwTCBvqSBuzCBuDELMAkGA1UEBhMCVVMxEzARBgNVBAgT
# Cldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29m
# dCBDb3Jwb3JhdGlvbjEMMAoGA1UECxMDQU9DMScwJQYDVQQLEx5uQ2lwaGVyIE5U
# UyBFU046MjY2NS00QzNGLUM1REUxKzApBgNVBAMTIk1pY3Jvc29mdCBUaW1lIFNv
# dXJjZSBNYXN0ZXIgQ2xvY2swDQYJKoZIhvcNAQEFBQACBQDeYe00MCIYDzIwMTgw
# MzI1MDk0MTA4WhgPMjAxODAzMjYwOTQxMDhaMHQwOgYKKwYBBAGEWQoEATEsMCow
# CgIFAN5h7TQCAQAwBwIBAAICJxYwBwIBAAICGc4wCgIFAN5jPrQCAQAwNgYKKwYB
# BAGEWQoEAjEoMCYwDAYKKwYBBAGEWQoDAaAKMAgCAQACAxbjYKEKMAgCAQACAweh
# IDANBgkqhkiG9w0BAQUFAAOCAQEAY1fiWDfeHlvSVx8yPDkvRGLPGXP74+urvWYB
# zepnv6d8vXhWS5MsC6LP8+bTWnSzMWsDvpjZOtxuTnFLwbzIoDL7mpSEYjEmtCig
# NNQST+ZpaEoX+H4ldOB6i9EQjZE6DBnljenG4eLAEIlFDiueHD2ls9aabcZl7mIq
# PCAWlggQClXekjJtZj6qIq9LaVTZ9zgG57I3GbGccgfC6i8goZ3dEP0pNFMgJKAD
# N1jZhajxnAPzu+nZ4AtQVvSgcDoIf99Ue8zUlUQUgG0f7EO+Jqnb2SyPLWB0hVsu
# WYxIppDnWheLnbzXB+PV2Z/5bes0ABNS7D85m26OkIDIdS3OhTGCAvUwggLxAgEB
# MIGTMHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQH
# EwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xJjAkBgNV
# BAMTHU1pY3Jvc29mdCBUaW1lLVN0YW1wIFBDQSAyMDEwAhMzAAAArIohvHrSm3L0
# AAAAAACsMA0GCWCGSAFlAwQCAQUAoIIBMjAaBgkqhkiG9w0BCQMxDQYLKoZIhvcN
# AQkQAQQwLwYJKoZIhvcNAQkEMSIEIJxMGCVKd+t9Z/Jd88h504SFchbglZwnDeag
# BIDr5Fj0MIHiBgsqhkiG9w0BCRACDDGB0jCBzzCBzDCBsQQUOXAlixTIed1fDF3p
# i5yzlJn3HLcwgZgwgYCkfjB8MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGlu
# Z3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBv
# cmF0aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0EgMjAxMAIT
# MwAAAKyKIbx60pty9AAAAAAArDAWBBTozm2OayPZf6jhy3FmMPY0BkOHODANBgkq
# hkiG9w0BAQsFAASCAQASmwX0nySY2PKnDAoIpFXP0+1YjL61c/mh+VyqxcpMTAnY
# ATF2WJALk3LZ+23h4QZMPOrBmmZeHw+Qzu7JJaP0P0v4tsXHz9GHVJkbYEvJmsGZ
# hcu2ow3CR5xR0O4M84au86mHSegjJl5G6y96TeuhSaEelTbST8Mb9IhzwJuvtajs
# ukDUnQ4KM3wvK0lC/Kyz6QCgX84lOUO4seA92m2PB0XGrSdy+izXAUblKOQugdBG
# 3ZSJK/12nmhx28WJml6jfZS8YmDUP5x0Cpx0wFgpbV6UnDecmGPpUHG3zAGyfj1w
# +Zi54uH5FQgYqIR1UisxrSaTEgo7LQgKuxO4+PW5
# SIG # End signature block
