function CleanupDeltaDBsyncReportDeployment([string]$metadataPackagePath)
{
    $deltaSyncFolder = Join-Path "$(split-Path -parent $metadataPackagePath)"  "DeltaSync"

    if(Test-Path $deltaSyncFolder)
    {
        get-childitem -path "$deltaSyncFolder" | remove-item -force -recurse
    }
}

$ErrorActionPreference = "Stop"
Import-Module "$PSScriptRoot\CommonRollbackUtilities.psm1" -Force -DisableNameChecking
Import-Module "$PSScriptRoot\AosEnvironmentUtilities.psm1" -Force -DisableNameChecking

function GenerateSymLinkNgen([string]$webroot,[string]$metadataPackagePath)
{
    $webconfig=join-path $webroot "web.config"
    [System.Xml.XmlDocument] $xd=new-object System.Xml.XmlDocument
    $xd.Load($webconfig)
    $ns=New-Object System.Xml.XmlNamespaceManager($xd.NameTable)
    $ns.AddNamespace("ns",$xd.DocumentElement.NamespaceURI)

    $key="UseLazyTypeLoader"
    $value="false"
    $existingNode = $xd.SelectSingleNode("//ns:add[@key='$key']",$ns)

    if($existingNode -ne $null){
        $existingValue=$existingNode.GetAttribute("value")
        if($existingValue -eq $value)
        { 
            write-output "Updating Symlink and Ngen Assemblies"
            $SymLinkNgenLog = join-path $PSScriptRoot "update_SymLink_NgenAssemblies.log"
            $argumentList = '–webroot:"$webroot" –packagedir:"$metadataPackagePath" –log:"$SymLinkNgenLog"'
            invoke-Expression "$metadataPackagePath\bin\CreateSymLinkAndNgenAssemblies.ps1 $argumentList"
        }
	}   
}

$webroot = Get-AosWebSitePhysicalPath

#stop aosservice again - this is simply a mitigation where customer manually restart machine or start service during middle of applying deployable package
& "$PSScriptRoot\AutoStopAOS.ps1"

# $RunbookBackupFolder and $PSScriptRoot variables are populated directly from runbook.
$BackupFolder = "$RunbookBackupFolder"

if ([string]::IsNullOrEmpty($BackupFolder))
{
    $BackupFolder = "$PSScriptRoot\ManualAosServiceBackup"
}

$webrootBackupFolder = "$BackupFolder\webroot"
$packageBackupFolder = "$BackupFolder\packages"

if(-Not(Test-Path -Path "$webrootBackupFolder\webroot.zip" )){
    Write-Output "fail to find the backup file for AOS webroot, restore aborted."
    exit
}

if(-Not(Test-Path -Path "$packageBackupFolder\packages.zip" )){
    Write-Output "fail to find the backup file for AOS package, restore aborted."
    exit
}

StopMonitoring

$exclude = @('*.config')

Write-Output "removinging AOS data at $webroot"
Copy-SymbolicLinks -SourcePath $webroot -DestinationPath “$webrootBackupFolder\junk” -Move
get-childitem -path "$webroot" -recurse | remove-item -force -recurse -Exclude $exclude
Write-Output "restore AOS data at $webroot"
Unpack-ZipFiles -sourceFile:"$webrootBackupFolder\webroot.zip" -destFolder:$webroot 

$packagePath = $(Get-AOSPackageDirectory)
$exclude = '*.bak'
Write-Output "removing AOS data at $packagePath" 
Copy-SymbolicLinks -SourcePath $packagePath -DestinationPath “$packageBackupFolder\junk” -Move
get-childitem -path "$packagePath" -recurse | remove-item -force -recurse -Exclude $exclude   
Write-Output "restore AOS data at $packagePath"  
Unpack-ZipFiles -sourceFile:"$packageBackupFolder\packages.zip" -destFolder:$packagePath 

Copy-SymbolicLinks -SourcePath “$packageBackupFolder\symlink” -DestinationPath $packagePath 
Copy-SymbolicLinks -SourcePath “$webrootBackupFolder\symlink” -DestinationPath $webroot 

CleanupDeltaDBsyncReportDeployment -metadataPackagePath:$packagePath

StartMonitoring

try
{
    $DeveloperBox = Get-DevToolsInstalled
    if(!($DeveloperBox))
    {
        if(Test-Path "$PSScriptRoot\RemoveSymLinkAndNgenAssemblies.ps1")
        {
            Write-Output "Removing SymLink And NgenAssemblies..."
            invoke-Expression "$PSScriptRoot\RemoveSymLinkAndNgenAssemblies.ps1"   
        }
    }    
}
 catch
{
    GenerateSymLinkNgen -webroot:$webroot -metadataPackagePath:$packagePath
}

GenerateMetadataModuleInstallationInfo
# SIG # Begin signature block
# MIIkCAYJKoZIhvcNAQcCoIIj+TCCI/UCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCA7Og5/8pKjpi53
# RGpV+51pV35hHTSPU6GlJrT/RrlyoKCCDYIwggYAMIID6KADAgECAhMzAAAAww6b
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
# KwYBBAGCNwIBCzEOMAwGCisGAQQBgjcCARUwLwYJKoZIhvcNAQkEMSIEIAYCEy2d
# J78by4VYbD364VY/JR9e6BdpBQa3JHnBpuAjMGIGCisGAQQBgjcCAQwxVDBSoDSA
# MgBBAHUAdABvAFIAZQBzAHQAbwByAGUAQQBPAFMAUwBlAHIAdgBpAGMAZQAuAHAA
# cwAxoRqAGGh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbTANBgkqhkiG9w0BAQEFAASC
# AQA6T+StWZU6e1EV12uT0DLDIREj8c3pSEwTqJrH6yt96+flmxwmUC5DmyortLfT
# xfv2M0nwRnJXS1DmAXUQ9earDouvaH9NwFVd8pxDjcE6HVww8Qbdy9KNUg9P2bO0
# UJzTjOVhPzs6gCqchUA7aL4M+okoaTU1LUDEW5afvm7k3J7tT60S5M3z9IWfl1+P
# VY0JW67N3NVFKCni5HgNjXunvllG5+n8vNXyYA2HF7Gs34yrcemPSzpnf9/DlcSN
# cz4YuSvps3yRnJ5OIadxklXfcEA9Rta30rwBstO2JtaH2M5rZaEBQ75KHSoK1E0Q
# hR0HXKZdrgdXkiFNPMqYAcNVoYITRjCCE0IGCisGAQQBgjcDAwExghMyMIITLgYJ
# KoZIhvcNAQcCoIITHzCCExsCAQMxDzANBglghkgBZQMEAgEFADCCATwGCyqGSIb3
# DQEJEAEEoIIBKwSCAScwggEjAgEBBgorBgEEAYRZCgMBMDEwDQYJYIZIAWUDBAIB
# BQAEIBN4F3oZyzjxkfhtXBr0mh/vw01NgTIdcuQ/4y+/x0amAgZasnRJxyAYEzIw
# MTgwMzI1MjEwNTU3Ljc5NlowBwIBAYACAfSggbikgbUwgbIxCzAJBgNVBAYTAlVT
# MRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQK
# ExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xDDAKBgNVBAsTA0FPQzEnMCUGA1UECxMe
# bkNpcGhlciBEU0UgRVNOOkY2RkYtMkRBNy1CQjc1MSUwIwYDVQQDExxNaWNyb3Nv
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
# BNkwggPBoAMCAQICEzMAAAClSBdyJ/lwvmMAAAAAAKUwDQYJKoZIhvcNAQELBQAw
# fDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1Jl
# ZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEmMCQGA1UEAxMd
# TWljcm9zb2Z0IFRpbWUtU3RhbXAgUENBIDIwMTAwHhcNMTYwOTA3MTc1NjUwWhcN
# MTgwOTA3MTc1NjUwWjCBsjELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0
# b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3Jh
# dGlvbjEMMAoGA1UECxMDQU9DMScwJQYDVQQLEx5uQ2lwaGVyIERTRSBFU046RjZG
# Ri0yREE3LUJCNzUxJTAjBgNVBAMTHE1pY3Jvc29mdCBUaW1lLVN0YW1wIFNlcnZp
# Y2UwggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIBAQC02pLUvUxe8NtXB99Z
# YYE6JrbTGLNpw/37zCNv0g3M0xtWFsxQTb7DEvtc1sE0s8I5ybT7Ifoy12FsCgpe
# bk++Cpcv0a0C5OHQ72mBnx8yxk2EJv3ie6jSIiw88cwrOTIv/hvsnk9v/YvHVPOF
# nX6CS1ISju4PYz22N0T6Tlu7X92P/uaF1wNSEZ7BlP81+4cy9hMgkaeaN6HyT6Qy
# VEvgKBTl5yGG7dbDmpk0ISYwdQeYoGXoU7fQmVqUEma721ZWNNREkWGJ0LjUXzpO
# 5YA6x/JSmzp119x2qCBTIMcZtxRVdXz7ygIiDqFLgfOw5lnFGqULgcoXAj5qxQuO
# v8G3AgMBAAGjggEbMIIBFzAdBgNVHQ4EFgQU4hOrS/LtsWC4ePGFoFH+cuexL6Qw
# HwYDVR0jBBgwFoAU1WM6XIoxkPNDe3xGG8UzaFqFbVUwVgYDVR0fBE8wTTBLoEmg
# R4ZFaHR0cDovL2NybC5taWNyb3NvZnQuY29tL3BraS9jcmwvcHJvZHVjdHMvTWlj
# VGltU3RhUENBXzIwMTAtMDctMDEuY3JsMFoGCCsGAQUFBwEBBE4wTDBKBggrBgEF
# BQcwAoY+aHR0cDovL3d3dy5taWNyb3NvZnQuY29tL3BraS9jZXJ0cy9NaWNUaW1T
# dGFQQ0FfMjAxMC0wNy0wMS5jcnQwDAYDVR0TAQH/BAIwADATBgNVHSUEDDAKBggr
# BgEFBQcDCDANBgkqhkiG9w0BAQsFAAOCAQEANn1teSvGLi8kIMol9TQVjNzyS0cH
# 9KM+7oZ4CN57h9YGxVjp+8vzF04f6TGgxtDCZgOfrs3w7JwrWZOCU7qRERwKnsdi
# Glqj1RbLLabqwPK0/3l++w7wM+pOG65c2vRQLuhLqGcZBqvH38F9YQUiMGHOpZjA
# wAIofWkxKZkgbqQ25+KU0oRs3A0aScn14zZVbW331VsR1Dm6AN+m0STLSTG8JYCC
# YKTrGeYhgmkvSJKyUMUPDp033x68/rhy65ND/lvGHxteoGhd3g4U5CLUahVW5Oji
# 562Pyic4YmbWbNsmEi8Jg8WucEHiOR6ELQux74lwJlIEMuk8DAOebGz4bqGCA3Qw
# ggJcAgEBMIHioYG4pIG1MIGyMQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGlu
# Z3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBv
# cmF0aW9uMQwwCgYDVQQLEwNBT0MxJzAlBgNVBAsTHm5DaXBoZXIgRFNFIEVTTjpG
# NkZGLTJEQTctQkI3NTElMCMGA1UEAxMcTWljcm9zb2Z0IFRpbWUtU3RhbXAgU2Vy
# dmljZaIlCgEBMAkGBSsOAwIaBQADFQCbwjXd+7ImKxoUMWVQLx1TlGmCb6CBwTCB
# vqSBuzCBuDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNV
# BAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEMMAoG
# A1UECxMDQU9DMScwJQYDVQQLEx5uQ2lwaGVyIE5UUyBFU046MjY2NS00QzNGLUM1
# REUxKzApBgNVBAMTIk1pY3Jvc29mdCBUaW1lIFNvdXJjZSBNYXN0ZXIgQ2xvY2sw
# DQYJKoZIhvcNAQEFBQACBQDeYesXMCIYDzIwMTgwMzI1MDkzMjA3WhgPMjAxODAz
# MjYwOTMyMDdaMHQwOgYKKwYBBAGEWQoEATEsMCowCgIFAN5h6xcCAQAwBwIBAAIC
# LcEwBwIBAAICGIgwCgIFAN5jPJcCAQAwNgYKKwYBBAGEWQoEAjEoMCYwDAYKKwYB
# BAGEWQoDAaAKMAgCAQACAxbjYKEKMAgCAQACAwehIDANBgkqhkiG9w0BAQUFAAOC
# AQEAYck2lC3t5JaS3af4+szThRs18bJYaYr366welafDuAHCEJuRcx9tA9VDdxXV
# kJNGEvZq4pAKYix1uwI97QQX6tJ5e0kqaLt+77uEwFufQj/kxBVVwN14oowjyZAv
# +LB3CiybZZX+8IVqv9opiMaLZ0aST/buEWpiAr8NBUzsF6xKioED1CzRE+6hw1z1
# aDNmcpf+4OgwxsNtKmbgxsnSRv3lrfYshwz9pwabXaqmKv98sccq8z9ynaZAPVDN
# PFcz5mwdCjXc60nmJi8cnASGxkbS25zsS/pw/bnFp/wEfBJF/KEX4LYbz+vB59AK
# RFL4iiO1Alo2U6TdyUAC0aAVhTGCAvUwggLxAgEBMIGTMHwxCzAJBgNVBAYTAlVT
# MRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQK
# ExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xJjAkBgNVBAMTHU1pY3Jvc29mdCBUaW1l
# LVN0YW1wIFBDQSAyMDEwAhMzAAAApUgXcif5cL5jAAAAAAClMA0GCWCGSAFlAwQC
# AQUAoIIBMjAaBgkqhkiG9w0BCQMxDQYLKoZIhvcNAQkQAQQwLwYJKoZIhvcNAQkE
# MSIEIIYoyPUpUhYKCEwNnEaMVUbhVojobNJJOMOgvrACS6Q1MIHiBgsqhkiG9w0B
# CRACDDGB0jCBzzCBzDCBsQQUm8I13fuyJisaFDFlUC8dU5Rpgm8wgZgwgYCkfjB8
# MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVk
# bW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSYwJAYDVQQDEx1N
# aWNyb3NvZnQgVGltZS1TdGFtcCBQQ0EgMjAxMAITMwAAAKVIF3In+XC+YwAAAAAA
# pTAWBBRTuaz69p++yIlnWGVdpZKQIz1F2zANBgkqhkiG9w0BAQsFAASCAQBAS4AZ
# D8Nfm72qqPV2uLRkt5Z+zwVqF9RlqWfCZAW8n0QNNadq76bnjEqq69WHBnqSIFPe
# P/n6yED9Ztmn2x7Ywbg6KJql9q7DD4knk4crJ9SWRVMhYU1+iK53dz9XofuRPzmj
# P0xwnPCPVZdAtRgLZLMPcfF2KPpNOHgFkb6amsgOwL7PvrmMbic7xRZmbPwJZrCx
# 5YTWwsDUwxr9FNZMVEoq6csl3Mv3QO9yOWpIqVmNb+3e/GtDlC2B28YoEVtCmOQQ
# /fMNnwenb4lbUzbAfcU7qVcQvEyt7N2mIpK2RDpHXXTOuBrLs+zN3CLxhqxDprJF
# a8tVwjoMyetwVukL
# SIG # End signature block
