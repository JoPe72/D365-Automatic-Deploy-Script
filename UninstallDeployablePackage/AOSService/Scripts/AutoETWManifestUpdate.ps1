$ETWManifestPath = "$(split-Path -parent $PSScriptRoot)\ETWManifest"

$settingsFilePath = Join-Path $PSScriptRoot 'Servicing.settings'
if (Test-Path $settingsFilePath)
{
    $settingsJson = Get-Content $settingsFilePath -Raw | ConvertFrom-Json

    if ($settingsJson.ETWManifestUpdate.Skip)
    {
        Write-Output 'Update is not applicable. Skipping ETW manifest update step.'
        exit 0
    }
    else
    {
        Write-Output 'Update is applicable.'
    }
}

$BackupFolder = "$RunbookBackupFolder"

if ([string]::IsNullOrEmpty($BackupFolder))
{
    $BackupFolder = "$PSScriptRoot\ManualETWManifestBackup"
}

if(-Not(Test-Path -Path $BackupFolder )){
    New-Item -ItemType directory -Path $BackupFolder
}

Write-Output "ETWManifestPath: $($ETWManifestPath)"

# Read the registry key to find the instrumentation folder
$regPath = "HKLM:\SOFTWARE\Microsoft\Dynamics\AX\Diagnostics\MonitoringInstall"
$instrumentationPathKey = "ManifestPath"
$installPathKey = "InstallPath"

if (Test-Path $regPath) 
{
    $instrumentationPath = $(Get-ItemProperty $regPath).$instrumentationPathKey 
    $installPath = $(Get-ItemProperty $regPath).$installPathKey

    $timeout = new-timespan -Minutes 15
    $logFileLocked = $true;
    $sw = [diagnostics.stopwatch]::StartNew()
    while ($sw.elapsed -lt $timeout -and $logFileLocked)
    {
        try 
        { 
            [IO.File]::OpenWrite("$installPath\MonitoringInstall\MonitoringInstall.log").close();
            Invoke-Expression "$installPath\MonitoringInstall\MonitoringInstall.exe /stopsessions /log:$installPath\MonitoringInstall\StopSessions.log /append"
            $logFileLocked = $false
        }
        catch 
        {
            start-sleep -seconds 15
        }
    }
    if($logFileLocked)
    {
        throw "fail to stop monitoring sessions"
    }

    $logFileLocked = $true;
    $sw = [diagnostics.stopwatch]::StartNew()
    while ($sw.elapsed -lt $timeout -and $logFileLocked)
    {
        try 
        { 
            [IO.File]::OpenWrite("$installPath\MonitoringInstall\MonitoringInstall.log").close();
            Invoke-Expression "$installPath\MonitoringInstall\MonitoringInstall.exe /stopagents /log:$installPath\MonitoringInstall\StopAgents.log /append"
            $logFileLocked = $false
        }
        catch 
        {
            start-sleep -seconds 15
        }
    }
    if($logFileLocked)
    {
        throw "fail to stop monitoring agents"
    }


    if (![String]::IsNullOrWhiteSpace($instrumentationPath))
    {
        Write-Output "InstrumentationPath: $($instrumentationPath)"
        if (Test-Path $instrumentationPath)
        {
            # Backup instrumentationPath prior to update
            Get-ChildItem -Path $instrumentationPath -Recurse | Copy-Item -Force -Destination {
                if ($_.GetType() -eq [System.IO.FileInfo]) {
                  Join-Path $BackupFolder $_.FullName.Substring($instrumentationPath.length)
                } 
                else {
                  Join-Path $BackupFolder $_.Parent.FullName.Substring($instrumentationPath.length)
                }
            }
            Write-Output "Manifest files copied to backup folder."
        }
        
        if (Test-Path $ETWManifestPath)
        {
            Restart-Service EventLog -Force 
            Copy-Item -Path "$ETWManifestPath\*" -Destination $instrumentationPath –Recurse -force
            Write-Output "Manifest files updated."
        }
    }

    # Run the scheduled task
    $scheduledTask = Get-ScheduledTask | ? {$_.TaskName -eq "MonitoringInstall"}
    If ($scheduledTask -ne $Null)
    {
        Write-Output "ScheduledTask $scheduledTask exists"
        Start-ScheduledTask $scheduledTask.TaskName -TaskPath $scheduledTask.TaskPath
        Write-Output "$scheduledTask triggered."
    }
} 
# SIG # Begin signature block
# MIIkCAYJKoZIhvcNAQcCoIIj+TCCI/UCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCCOMDxSX3GGfkcd
# UYDTk7IiZ9Jh01mPIRGCHDuV6MgIQaCCDYIwggYAMIID6KADAgECAhMzAAAAww6b
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
# SEXAQsmbdlsKgEhr/Xmfwb1tbWrJUnMTDXpQzTGCFdwwghXYAgEBMIGVMH4xCzAJ
# BgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25k
# MR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xKDAmBgNVBAMTH01pY3Jv
# c29mdCBDb2RlIFNpZ25pbmcgUENBIDIwMTECEzMAAADDDpun2LLc9ywAAAAAAMMw
# DQYJYIZIAWUDBAIBBQCggc4wGQYJKoZIhvcNAQkDMQwGCisGAQQBgjcCAQQwHAYK
# KwYBBAGCNwIBCzEOMAwGCisGAQQBgjcCARUwLwYJKoZIhvcNAQkEMSIEIBGzFaz8
# vM9g5UWkoLyiXXMKcOFSqd/0s1Cgg28s+VxvMGIGCisGAQQBgjcCAQwxVDBSoDSA
# MgBBAHUAdABvAEUAVABXAE0AYQBuAGkAZgBlAHMAdABVAHAAZABhAHQAZQAuAHAA
# cwAxoRqAGGh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbTANBgkqhkiG9w0BAQEFAASC
# AQBUjfEuS4j4By0KwVQX33AQJxbijh0HZ8KQd9EewRhHP7DgG1N0UTKUfa6vJovY
# 5C+DhkgGFiN6TdS5nsTBGYCwLWGz2md4xaFVtV9KMAZ/YKgx631HaJdl4aOZFnyA
# ePprWXWQa/CpTUie86chMffU2B9l87nbRuWGl99boYvK3Ix4/bNcgQu9MzUNpGNU
# IV6/ZW1QBs4nfqDQNc9GyRVzSPzcqhW5T3/FSwNDiF9JtvOlvYFkjWmlTtI1yK3a
# mpp7hUt1lT9aCoOxYVfLvhLJNJxjNUrhzhgj9Wp31ePuvZ/ZT6KE/zfca9N+Cht5
# oR/AA/gj9kZlznX3gE1rBUt4oYITRjCCE0IGCisGAQQBgjcDAwExghMyMIITLgYJ
# KoZIhvcNAQcCoIITHzCCExsCAQMxDzANBglghkgBZQMEAgEFADCCATwGCyqGSIb3
# DQEJEAEEoIIBKwSCAScwggEjAgEBBgorBgEEAYRZCgMBMDEwDQYJYIZIAWUDBAIB
# BQAEID4kG9CKEyr1FPZ8KVobf/8ysz5ySlFkkiPdBDhc3UkSAgZasq59GCYYEzIw
# MTgwMzI1MjEwNTU4LjUxNVowBwIBAYACAfSggbikgbUwgbIxCzAJBgNVBAYTAlVT
# MRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQK
# ExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xDDAKBgNVBAsTA0FPQzEnMCUGA1UECxMe
# bkNpcGhlciBEU0UgRVNOOjIxMzctMzdBMC00QUFBMSUwIwYDVQQDExxNaWNyb3Nv
# ZnQgVGltZS1TdGFtcCBTZXJ2aWNloIIOyjCCBnEwggRZoAMCAQICCmEJgSoAAAAA
# AAIwDQYJKoZIhvcNAQELBQAwgYgxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNo
# aW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29y
# cG9yYXRpb24xMjAwBgNVBAMTKU1pY3Jvc29mdCBSb290IENlcnRpZmljYXRlIEF1
# dGhvcml0eSAyMDEwMB4XDTEwMDcwMTIxMzY1NVoXDTI1MDcwMTIxNDY1NVowfDEL
# MAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1v
# bmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEmMCQGA1UEAxMdTWlj
# cm9zb2Z0IFRpbWUtU3RhbXAgUENBIDIwMTAwggEiMA0GCSqGSIb3DQEBAQUAA4IB
# DwAwggEKAoIBAQCpHQ28dxGKOiDs/BOX9fp/aZRrdFQQ1aUKAIKF++18aEssX8XD
# 5WHCdrc+Zitb8BVTJwQxH0EbGpUdzgkTjnxhMFmxMEQP8WCIhFRDDNdNuDgIs0Ld
# k6zWczBXJoKjRQ3Q6vVHgc2/JGAyWGBG8lhHhjKEHnRhZ5FfgVSxz5NMksHEpl3R
# YRNuKMYa+YaAu99h/EbBJx0kZxJyGiGKr0tkiVBisV39dx898Fd1rL2KQk1AUdEP
# nAY+Z3/1ZsADlkR+79BL/W7lmsqxqPJ6Kgox8NpOBpG2iAg16HgcsOmZzTznL0S6
# p/TcZL2kAcEgCZN4zfy8wMlEXV4WnAEFTyJNAgMBAAGjggHmMIIB4jAQBgkrBgEE
# AYI3FQEEAwIBADAdBgNVHQ4EFgQU1WM6XIoxkPNDe3xGG8UzaFqFbVUwGQYJKwYB
# BAGCNxQCBAweCgBTAHUAYgBDAEEwCwYDVR0PBAQDAgGGMA8GA1UdEwEB/wQFMAMB
# Af8wHwYDVR0jBBgwFoAU1fZWy4/oolxiaNE9lJBb186aGMQwVgYDVR0fBE8wTTBL
# oEmgR4ZFaHR0cDovL2NybC5taWNyb3NvZnQuY29tL3BraS9jcmwvcHJvZHVjdHMv
# TWljUm9vQ2VyQXV0XzIwMTAtMDYtMjMuY3JsMFoGCCsGAQUFBwEBBE4wTDBKBggr
# BgEFBQcwAoY+aHR0cDovL3d3dy5taWNyb3NvZnQuY29tL3BraS9jZXJ0cy9NaWNS
# b29DZXJBdXRfMjAxMC0wNi0yMy5jcnQwgaAGA1UdIAEB/wSBlTCBkjCBjwYJKwYB
# BAGCNy4DMIGBMD0GCCsGAQUFBwIBFjFodHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20v
# UEtJL2RvY3MvQ1BTL2RlZmF1bHQuaHRtMEAGCCsGAQUFBwICMDQeMiAdAEwAZQBn
# AGEAbABfAFAAbwBsAGkAYwB5AF8AUwB0AGEAdABlAG0AZQBuAHQALiAdMA0GCSqG
# SIb3DQEBCwUAA4ICAQAH5ohRDeLG4Jg/gXEDPZ2joSFvs+umzPUxvs8F4qn++ldt
# GTCzwsVmyWrf9efweL3HqJ4l4/m87WtUVwgrUYJEEvu5U4zM9GASinbMQEBBm9xc
# F/9c+V4XNZgkVkt070IQyK+/f8Z/8jd9Wj8c8pl5SpFSAK84Dxf1L3mBZdmptWvk
# x872ynoAb0swRCQiPM/tA6WWj1kpvLb9BOFwnzJKJ/1Vry/+tuWOM7tiX5rbV0Dp
# 8c6ZZpCM/2pif93FSguRJuI57BlKcWOdeyFtw5yjojz6f32WapB4pm3S4Zz5Hfw4
# 2JT0xqUKloakvZ4argRCg7i1gJsiOCC1JeVk7Pf0v35jWSUPei45V3aicaoGig+J
# FrphpxHLmtgOR5qAxdDNp9DvfYPw4TtxCd9ddJgiCGHasFAeb73x4QDf5zEHpJM6
# 92VHeOj4qEir995yfmFrb3epgcunCaw5u+zGy9iCtHLNHfS4hQEegPsbiSpUObJb
# 2sgNVZl6h3M7COaYLeqN4DMuEin1wC9UJyH3yKxO2ii4sanblrKnQqLJzxlBTeCG
# +SqaoxFmMNO7dDJL32N79ZmKLxvHIa9Zta7cRDyXUHHXodLFVeNp3lfB0d4wwP3M
# 5k37Db9dT+mdHhk4L7zPWAUu7w2gUDXa7wknHNWzfjUeCLraNtvTX4/edIhJEjCC
# BNkwggPBoAMCAQICEzMAAACvNY//0yJFdksAAAAAAK8wDQYJKoZIhvcNAQELBQAw
# fDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1Jl
# ZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEmMCQGA1UEAxMd
# TWljcm9zb2Z0IFRpbWUtU3RhbXAgUENBIDIwMTAwHhcNMTYwOTA3MTc1NjU2WhcN
# MTgwOTA3MTc1NjU2WjCBsjELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0
# b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3Jh
# dGlvbjEMMAoGA1UECxMDQU9DMScwJQYDVQQLEx5uQ2lwaGVyIERTRSBFU046MjEz
# Ny0zN0EwLTRBQUExJTAjBgNVBAMTHE1pY3Jvc29mdCBUaW1lLVN0YW1wIFNlcnZp
# Y2UwggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIBAQCT6ECGDhrLcfADDaaP
# pOdhEtBh6pBqlVa6t6BNSylk2FGaO11nk62I7kPU3V3U7xJxn20/9eqXKsg6t1UR
# 1KcztXRETZhN4Xqlx92pLMyIHwhvPvHPhOXhbA/nw+45gYspMydZ+E/OpZuNBgOu
# 3tRJU2LjWSf16ApMvMbgH1fd0Zv/TgfQbGCYl4GuYQ6QeeQLKMv5vRBrPMFzERBe
# 4uNS9j9heuRFr3VBrUsMtek0GhE3cKA/6KwrtAeTvq6DydnidJFwYbAVekT0hJEN
# /NskM2YAzCCL7sFoPXEfn30L5dJoJ4aeabKqsxxKF1T5B2n+d2/HP8ac0vFSUKvH
# lzijAgMBAAGjggEbMIIBFzAdBgNVHQ4EFgQUfR5VxjGK2mALBmawFNlq/HsS9uEw
# HwYDVR0jBBgwFoAU1WM6XIoxkPNDe3xGG8UzaFqFbVUwVgYDVR0fBE8wTTBLoEmg
# R4ZFaHR0cDovL2NybC5taWNyb3NvZnQuY29tL3BraS9jcmwvcHJvZHVjdHMvTWlj
# VGltU3RhUENBXzIwMTAtMDctMDEuY3JsMFoGCCsGAQUFBwEBBE4wTDBKBggrBgEF
# BQcwAoY+aHR0cDovL3d3dy5taWNyb3NvZnQuY29tL3BraS9jZXJ0cy9NaWNUaW1T
# dGFQQ0FfMjAxMC0wNy0wMS5jcnQwDAYDVR0TAQH/BAIwADATBgNVHSUEDDAKBggr
# BgEFBQcDCDANBgkqhkiG9w0BAQsFAAOCAQEAasgAhnj7DEKcENb3KKwPhGqL/N1b
# 6h9aQESpLhNfixpJdmkSKuaE5vjmutGPPC4p7Us1IOCBuvrVgxcVm3VTmjx/Y5DL
# oAhkL/Nh80rwivBFToiNPGuQjQDiayNJrHlnIOdlM6765CLBQg11ZQ/Unc0e4zDe
# rFqGGsKFh0ck7nw84nI4ORhuPHWN5gHZx3dwo9r6WbmJQFmRtsXyu4UtndUYf+OT
# G3J/sQmtEAOuxSUm582jfqK1uPVK1TQUfI/ygsM2CNIwiDZ11wgZa2IXkdMDQrJz
# jNEVqHUprP+ARQtFsd1y9lk1uVIGzuaIf/8trKzR/OCjz/wcOR/b0BDT26GCA3Qw
# ggJcAgEBMIHioYG4pIG1MIGyMQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGlu
# Z3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBv
# cmF0aW9uMQwwCgYDVQQLEwNBT0MxJzAlBgNVBAsTHm5DaXBoZXIgRFNFIEVTTjoy
# MTM3LTM3QTAtNEFBQTElMCMGA1UEAxMcTWljcm9zb2Z0IFRpbWUtU3RhbXAgU2Vy
# dmljZaIlCgEBMAkGBSsOAwIaBQADFQDY6qwVLW8upS2m/QIDUOKAG/5OI6CBwTCB
# vqSBuzCBuDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNV
# BAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEMMAoG
# A1UECxMDQU9DMScwJQYDVQQLEx5uQ2lwaGVyIE5UUyBFU046MjY2NS00QzNGLUM1
# REUxKzApBgNVBAMTIk1pY3Jvc29mdCBUaW1lIFNvdXJjZSBNYXN0ZXIgQ2xvY2sw
# DQYJKoZIhvcNAQEFBQACBQDeYeeEMCIYDzIwMTgwMzI1MDkxNjUyWhgPMjAxODAz
# MjYwOTE2NTJaMHQwOgYKKwYBBAGEWQoEATEsMCowCgIFAN5h54QCAQAwBwIBAAIC
# HFMwBwIBAAICGZUwCgIFAN5jOQQCAQAwNgYKKwYBBAGEWQoEAjEoMCYwDAYKKwYB
# BAGEWQoDAaAKMAgCAQACAxbjYKEKMAgCAQACAx6EgDANBgkqhkiG9w0BAQUFAAOC
# AQEAOSdLMOVdo6FYeLZ0uESDJRujYuFjME5wgcd2DbNiyQO9L2puHhxn659w8/aE
# 9Gye+Dz83RodG7oIrY1QawlRiAjcafJQcVp02R8Vh0ar7SwAl6Hl0VOaDw0FLobs
# yqpx1hh15ZH2vnE1nhqmbXITK/PtUM+IlUtLIuxJa8jkL5mmmSJYt5cRiaUVYGyD
# iTBugL6/mVpFNAz8Pwvc9xMC66Bhw+shxjZ9Vq8Ov8C7v/oxKMjagvTt6IhtPufu
# HuTnWINf6XAesANwOP6XZlVvT54IL2JgBDeXoI459MqgltTSTY74AjAFvOoHYeHf
# 1xjvCdZjupzflg8mYnhHWakJgTGCAvUwggLxAgEBMIGTMHwxCzAJBgNVBAYTAlVT
# MRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQK
# ExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xJjAkBgNVBAMTHU1pY3Jvc29mdCBUaW1l
# LVN0YW1wIFBDQSAyMDEwAhMzAAAArzWP/9MiRXZLAAAAAACvMA0GCWCGSAFlAwQC
# AQUAoIIBMjAaBgkqhkiG9w0BCQMxDQYLKoZIhvcNAQkQAQQwLwYJKoZIhvcNAQkE
# MSIEIOSnbBr/bYMgtKWikH3ys/N6Mergy8iYHPhSvNgVyWDCMIHiBgsqhkiG9w0B
# CRACDDGB0jCBzzCBzDCBsQQU2OqsFS1vLqUtpv0CA1DigBv+TiMwgZgwgYCkfjB8
# MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVk
# bW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSYwJAYDVQQDEx1N
# aWNyb3NvZnQgVGltZS1TdGFtcCBQQ0EgMjAxMAITMwAAAK81j//TIkV2SwAAAAAA
# rzAWBBR+fVP1wws0A5LVen8Z5A7XeBvTHDANBgkqhkiG9w0BAQsFAASCAQBMu113
# cH8E55yhEmlaik3h+DVeqzyG11SsnqikDutLl/m4S3BnzCCVMIABpvNmFUeNoygK
# fibM4/FqxdQuNzaOzGaf0yRlK1xOwyu0BBb4HXY6mcBacqjBPeL68/w1fShFFB8z
# +qyCFWfcsTNx0g2fbfa+bnaVN+aviHUB+XWdHLJGMWdbtnz/++WawSgczA78JpvV
# zPWwUXAz4oq1s4E+evdBH7sI4K6pMw2IQgafXRtIvWrjQvt8T+rKOsNPiesbXdK6
# ZisLHo6oFs6h7u+3FGpaS9MN1SNL5Z1FWFQ+3YXJUQG6/i3qaap6ChpPbYgpzinM
# kyf0+m7Yj3EFl68T
# SIG # End signature block
