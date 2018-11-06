
function PrepareDeltaDBsyncReportDeployment([string]$metadataPackagePath)
{
    $deltaSyncFolder = Join-Path "$(split-Path -parent $metadataPackagePath)"  "DeltaSync"

    if(!(Test-Path $deltaSyncFolder)){
        New-Item $deltaSyncFolder -ItemType directory -Force
    }
    else
    {
        get-childitem -path "$deltaSyncFolder" | remove-item -force -recurse
    }
    
    robocopy $metadataPackagePath $deltaSyncFolder /s *AXSecurity*.md *AXTable*.md *AXView*.md *AXEdt*.md *.rdl  >$null
}

$ErrorActionPreference = 'Stop'
Import-Module "$PSScriptRoot\CommonRollbackUtilities.psm1" -Force -DisableNameChecking
Import-Module "$PSScriptRoot\AosEnvironmentUtilities.psm1" -Force -DisableNameChecking


# ALM Service keeps a "clean" copy of packages folder (i.e. only standard AX vanilla code) to start from on every build
# We want AOS service to backup the "Clean" state packages so rollback doesn't put custom code back
# after removing the ALM service's backup in the AOS update step.
# We can't do this in ALM Service script due to these inter-dependencies between ALM and AOS.
# This is a compromise solution awaiting ALM to do "clean" differently.
function Restore-ALMPackagesBackup
{
    $ALMPackagesCopyPath = Get-ALMPackageCopyPath
    if ($ALMPackagesCopyPath)
    {
        $ALMBackupFlag = Join-Path -Path $ALMPackagesCopyPath -ChildPath "Packages\BackupComplete.txt"

        # If a copy exists
        if (Test-Path $ALMBackupFlag)
        {
            Write-Output "ALM Service clean packages copy found in $ALMPackagesCopyPath. Restoring clean packages folder..."
            $ALMPackagesCopyRestore = Join-Path -Path $env:DynamicsSDK -ChildPath "PrepareForBuild.ps1"
            & $ALMPackagesCopyRestore

            # PrepareForBuild script shuts down IIS service entirely, even though individual sites are already stopped
            # This can break subsequent IIS web administration calls during servicing
            # Calling Get-AosWebSitePhysicalPath will restart the service if needed
            #      and leave the websites in the state they were in prior to IIS service stop
            $ALMTestWebRoot = Get-AosWebSitePhysicalPath
        }
    }
}


$webroot = Get-AosWebSitePhysicalPath

$packagePath = Get-AosPackageDirectory

# $RunbookBackupFolder and $PSScriptRoot variables are populated directly from runbook.
$BackupFolder = "$RunbookBackupFolder"

if ([string]::IsNullOrEmpty($BackupFolder))
{
    $BackupFolder = "$PSScriptRoot\ManualAosServiceBackup"
}

$webrootBackupFolder = "$BackupFolder\webroot"
$packageBackupFolder = "$BackupFolder\packages"

if(-Not(Test-Path -Path $webrootBackupFolder )){
    New-Item -ItemType directory -Path $webrootBackupFolder
}

if(-Not(Test-Path -Path $packageBackupFolder )){
    New-Item -ItemType directory -Path $packageBackupFolder
}

if(-Not(Test-Path -Path “$webrootBackupFolder\symlink” )){
    New-Item -ItemType directory -Path “$webrootBackupFolder\symlink”
}


if(-Not(Test-Path -Path "$packageBackupFolder\symlink" )){
    New-Item -ItemType directory -Path "$packageBackupFolder\symlink"
}


Try
{

    $exclude = ""
   
    Copy-SymbolicLinks -SourcePath $webroot -DestinationPath “$webrootBackupFolder\symlink” -Move

    Write-Output "backup AOS data at $webroot"
    Create-ZipFiles -sourceFolder:$webroot -destFile:"$webrootBackupFolder\webroot.zip" -filetypesExcluded:$exclude

    # Take care of ALMService needs (if present) before taking packages backup
    Restore-ALMPackagesBackup

    $exclude = '*.bak'  
    
    Copy-SymbolicLinks -SourcePath $packagePath -DestinationPath “$packageBackupFolder\symlink” -Move

    Write-Output "backup AOS data at $packagePath"
    Create-ZipFiles -sourceFolder:$packagePath -destFile:"$packageBackupFolder\packages.zip" -filetypesExcluded:$exclude 
}
Catch
{
    throw $_
}
Finally
{
    Copy-SymbolicLinks -SourcePath “$packageBackupFolder\symlink” -DestinationPath $packagePath 
    Copy-SymbolicLinks -SourcePath “$webrootBackupFolder\symlink” -DestinationPath $webroot 
}


PrepareDeltaDBsyncReportDeployment -metadataPackagePath:$packagePath

# SIG # Begin signature block
# MIIkBgYJKoZIhvcNAQcCoIIj9zCCI/MCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCDTQ73XPjzQPBQp
# iyp4jabhUuX3vj9/OX5klKozV+DDKKCCDYIwggYAMIID6KADAgECAhMzAAAAww6b
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
# SEXAQsmbdlsKgEhr/Xmfwb1tbWrJUnMTDXpQzTGCFdowghXWAgEBMIGVMH4xCzAJ
# BgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25k
# MR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xKDAmBgNVBAMTH01pY3Jv
# c29mdCBDb2RlIFNpZ25pbmcgUENBIDIwMTECEzMAAADDDpun2LLc9ywAAAAAAMMw
# DQYJYIZIAWUDBAIBBQCggcwwGQYJKoZIhvcNAQkDMQwGCisGAQQBgjcCAQQwHAYK
# KwYBBAGCNwIBCzEOMAwGCisGAQQBgjcCARUwLwYJKoZIhvcNAQkEMSIEIDd2Ag2H
# 1wTofk9QCoFcJY4B/vNCE8jXv86075VU387mMGAGCisGAQQBgjcCAQwxUjBQoDKA
# MABBAHUAdABvAEIAYQBjAGsAdQBwAEEATwBTAFMAZQByAHYAaQBjAGUALgBwAHMA
# MaEagBhodHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20wDQYJKoZIhvcNAQEBBQAEggEA
# HkJ/nLZyuVGAquebSGqNvYyj+agCYm7jIwGr+KP+CtDBR6GxUtTq8lnX9zGMe8Ts
# MmkppyFmYJHabARQ6JpIlIQJJTZ/+BhN2tg+6ttrD/880nKcpNfZcjxDgvpLUFyz
# T3RUlkxtI5nZFHXK3JGYTKpF+uZFX83fPd5LL4XqUn7TTC0RBxfUrMt6bvYH2JcG
# VpiBR/HKX4YhAAiaCIPX701Mvpf487oz2Gya3c+dis5ZKI/SPfyr5EXSJ2o5dpL4
# C+iQjSmmusf4GzD4mPDdRa6pYLOqLy7ee8fr4rfT6F25rnDduBuL83DZzNJFmOob
# GjhU2zHMIWjH4XNH+Uyl2KGCE0YwghNCBgorBgEEAYI3AwMBMYITMjCCEy4GCSqG
# SIb3DQEHAqCCEx8wghMbAgEDMQ8wDQYJYIZIAWUDBAIBBQAwggE8BgsqhkiG9w0B
# CRABBKCCASsEggEnMIIBIwIBAQYKKwYBBAGEWQoDATAxMA0GCWCGSAFlAwQCAQUA
# BCBcruCgoDgBlEXK0g0PyeHCU8yxCn5lWm4SpPKwT1itRAIGWrK5y/lxGBMyMDE4
# MDMyNTIxMDU1OC40OTNaMAcCAQGAAgH0oIG4pIG1MIGyMQswCQYDVQQGEwJVUzET
# MBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMV
# TWljcm9zb2Z0IENvcnBvcmF0aW9uMQwwCgYDVQQLEwNBT0MxJzAlBgNVBAsTHm5D
# aXBoZXIgRFNFIEVTTjpEMjM2LTM3REEtOTc2MTElMCMGA1UEAxMcTWljcm9zb2Z0
# IFRpbWUtU3RhbXAgU2VydmljZaCCDsowggZxMIIEWaADAgECAgphCYEqAAAAAAAC
# MA0GCSqGSIb3DQEBCwUAMIGIMQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGlu
# Z3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBv
# cmF0aW9uMTIwMAYDVQQDEylNaWNyb3NvZnQgUm9vdCBDZXJ0aWZpY2F0ZSBBdXRo
# b3JpdHkgMjAxMDAeFw0xMDA3MDEyMTM2NTVaFw0yNTA3MDEyMTQ2NTVaMHwxCzAJ
# BgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25k
# MR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xJjAkBgNVBAMTHU1pY3Jv
# c29mdCBUaW1lLVN0YW1wIFBDQSAyMDEwMIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8A
# MIIBCgKCAQEAqR0NvHcRijog7PwTl/X6f2mUa3RUENWlCgCChfvtfGhLLF/Fw+Vh
# wna3PmYrW/AVUycEMR9BGxqVHc4JE458YTBZsTBED/FgiIRUQwzXTbg4CLNC3ZOs
# 1nMwVyaCo0UN0Or1R4HNvyRgMlhgRvJYR4YyhB50YWeRX4FUsc+TTJLBxKZd0WET
# bijGGvmGgLvfYfxGwScdJGcSchohiq9LZIlQYrFd/XcfPfBXday9ikJNQFHRD5wG
# Pmd/9WbAA5ZEfu/QS/1u5ZrKsajyeioKMfDaTgaRtogINeh4HLDpmc085y9Euqf0
# 3GS9pAHBIAmTeM38vMDJRF1eFpwBBU8iTQIDAQABo4IB5jCCAeIwEAYJKwYBBAGC
# NxUBBAMCAQAwHQYDVR0OBBYEFNVjOlyKMZDzQ3t8RhvFM2hahW1VMBkGCSsGAQQB
# gjcUAgQMHgoAUwB1AGIAQwBBMAsGA1UdDwQEAwIBhjAPBgNVHRMBAf8EBTADAQH/
# MB8GA1UdIwQYMBaAFNX2VsuP6KJcYmjRPZSQW9fOmhjEMFYGA1UdHwRPME0wS6BJ
# oEeGRWh0dHA6Ly9jcmwubWljcm9zb2Z0LmNvbS9wa2kvY3JsL3Byb2R1Y3RzL01p
# Y1Jvb0NlckF1dF8yMDEwLTA2LTIzLmNybDBaBggrBgEFBQcBAQROMEwwSgYIKwYB
# BQUHMAKGPmh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2kvY2VydHMvTWljUm9v
# Q2VyQXV0XzIwMTAtMDYtMjMuY3J0MIGgBgNVHSABAf8EgZUwgZIwgY8GCSsGAQQB
# gjcuAzCBgTA9BggrBgEFBQcCARYxaHR0cDovL3d3dy5taWNyb3NvZnQuY29tL1BL
# SS9kb2NzL0NQUy9kZWZhdWx0Lmh0bTBABggrBgEFBQcCAjA0HjIgHQBMAGUAZwBh
# AGwAXwBQAG8AbABpAGMAeQBfAFMAdABhAHQAZQBtAGUAbgB0AC4gHTANBgkqhkiG
# 9w0BAQsFAAOCAgEAB+aIUQ3ixuCYP4FxAz2do6Ehb7Prpsz1Mb7PBeKp/vpXbRkw
# s8LFZslq3/Xn8Hi9x6ieJeP5vO1rVFcIK1GCRBL7uVOMzPRgEop2zEBAQZvcXBf/
# XPleFzWYJFZLdO9CEMivv3/Gf/I3fVo/HPKZeUqRUgCvOA8X9S95gWXZqbVr5MfO
# 9sp6AG9LMEQkIjzP7QOllo9ZKby2/QThcJ8ySif9Va8v/rbljjO7Yl+a21dA6fHO
# mWaQjP9qYn/dxUoLkSbiOewZSnFjnXshbcOco6I8+n99lmqQeKZt0uGc+R38ONiU
# 9MalCpaGpL2eGq4EQoO4tYCbIjggtSXlZOz39L9+Y1klD3ouOVd2onGqBooPiRa6
# YacRy5rYDkeagMXQzafQ732D8OE7cQnfXXSYIghh2rBQHm+98eEA3+cxB6STOvdl
# R3jo+KhIq/fecn5ha293qYHLpwmsObvsxsvYgrRyzR30uIUBHoD7G4kqVDmyW9rI
# DVWZeodzOwjmmC3qjeAzLhIp9cAvVCch98isTtoouLGp25ayp0Kiyc8ZQU3ghvkq
# mqMRZjDTu3QyS99je/WZii8bxyGvWbWu3EQ8l1Bx16HSxVXjad5XwdHeMMD9zOZN
# +w2/XU/pnR4ZOC+8z1gFLu8NoFA12u8JJxzVs341Hgi62jbb01+P3nSISRIwggTZ
# MIIDwaADAgECAhMzAAAArg7WTpaJ2wD1AAAAAACuMA0GCSqGSIb3DQEBCwUAMHwx
# CzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRt
# b25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xJjAkBgNVBAMTHU1p
# Y3Jvc29mdCBUaW1lLVN0YW1wIFBDQSAyMDEwMB4XDTE2MDkwNzE3NTY1NVoXDTE4
# MDkwNzE3NTY1NVowgbIxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9u
# MRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRp
# b24xDDAKBgNVBAsTA0FPQzEnMCUGA1UECxMebkNpcGhlciBEU0UgRVNOOkQyMzYt
# MzdEQS05NzYxMSUwIwYDVQQDExxNaWNyb3NvZnQgVGltZS1TdGFtcCBTZXJ2aWNl
# MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEA3pIvw6SVcvU+DWZkw/rm
# 6CIPdIxNwZ7HtlS48Y9OfR/7RjC+fMt7ntvEZ1iSL/pUgAafoz6fFyH9qf/wymG9
# KP0EjifJBlKBWHrDUz7asn/6qIS1ta3C4o4haDCwAR/xg5w24EWR8VRcR1BvijcH
# 33QtAWAt1X6t/trjjvHM0ZY9dIER1NgSvJqEs+d1aNmcBd0zGclYLwL5YObGqzYE
# cAGMG8FlucBKqXjgxV9VQP5wHi5I4qwpoPO+TNV4hMj7a1wwBS54Of8uTJQHFDGC
# enR7kgQ6iy14qY42GpEKKQdx9fvbPIsg6ATNOyaj/bueVT+Wtp/yGRTTcCR3gk0r
# ywIDAQABo4IBGzCCARcwHQYDVR0OBBYEFH6P5TQ0RIvyeUC4xqDRnEMeISWxMB8G
# A1UdIwQYMBaAFNVjOlyKMZDzQ3t8RhvFM2hahW1VMFYGA1UdHwRPME0wS6BJoEeG
# RWh0dHA6Ly9jcmwubWljcm9zb2Z0LmNvbS9wa2kvY3JsL3Byb2R1Y3RzL01pY1Rp
# bVN0YVBDQV8yMDEwLTA3LTAxLmNybDBaBggrBgEFBQcBAQROMEwwSgYIKwYBBQUH
# MAKGPmh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2kvY2VydHMvTWljVGltU3Rh
# UENBXzIwMTAtMDctMDEuY3J0MAwGA1UdEwEB/wQCMAAwEwYDVR0lBAwwCgYIKwYB
# BQUHAwgwDQYJKoZIhvcNAQELBQADggEBAD1ZTXjw9Fw0CNG1QWADUwz5jKZN5SIe
# oDyIpYNISkKWTTAAy25o/pGr9BmXMbVp8KwaEfn6QbLmqMFoMMRMQhwaOpose0S3
# ibzcjWJQpNiUE/xmvNEkVczgC+TcZbNT6rw24BYIQ3EU5qWTLwA36sHbuUehTciI
# HnGDaMm+wOAKgi31dVsdz6z8ml22rbJJOZk/Dali2C7IQc7dgmtG4SSWX+qkMIOq
# 9oM9aRtebnupw6v5o2KU5gg4WM+Om/K8ayJ9LEMZxU5rZ7b89mdYwhrPfZ9a69mR
# axlziUuAYZ9bcihBcBiY630OBm9qcgPWikcFMivQRyylguWSw9IQGiChggN0MIIC
# XAIBATCB4qGBuKSBtTCBsjELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0
# b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3Jh
# dGlvbjEMMAoGA1UECxMDQU9DMScwJQYDVQQLEx5uQ2lwaGVyIERTRSBFU046RDIz
# Ni0zN0RBLTk3NjExJTAjBgNVBAMTHE1pY3Jvc29mdCBUaW1lLVN0YW1wIFNlcnZp
# Y2WiJQoBATAJBgUrDgMCGgUAAxUAx8G9MHulGJ5kXmd0Nvq745m8aPuggcEwgb6k
# gbswgbgxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQH
# EwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xDDAKBgNV
# BAsTA0FPQzEnMCUGA1UECxMebkNpcGhlciBOVFMgRVNOOjI2NjUtNEMzRi1DNURF
# MSswKQYDVQQDEyJNaWNyb3NvZnQgVGltZSBTb3VyY2UgTWFzdGVyIENsb2NrMA0G
# CSqGSIb3DQEBBQUAAgUA3mHsnzAiGA8yMDE4MDMyNTA5MzgzOVoYDzIwMTgwMzI2
# MDkzODM5WjB0MDoGCisGAQQBhFkKBAExLDAqMAoCBQDeYeyfAgEAMAcCAQACAhdV
# MAcCAQACAhmyMAoCBQDeYz4fAgEAMDYGCisGAQQBhFkKBAIxKDAmMAwGCisGAQQB
# hFkKAwGgCjAIAgEAAgMW42ChCjAIAgEAAgMehIAwDQYJKoZIhvcNAQEFBQADggEB
# AFskFFEQc+eBw9yHkc2vHKr3vR9krCZiSpQIqfQoViW33pGQrDaXkmXDTtCtjaM1
# EEBW3aCNGPAOW5pQVzzf8xTQkw2a/RxFB79KoP4DbxKbb9C+FP/HnZCsmErKixJL
# +RmKXaBfglm/EIciyZ7tBlsRpBSe9tL7UJZlMiC7ytVBivu6B+MQ5EX3KU9F8Lqg
# 5R076/7grJU2emc7a5JnBvWuaMx7e/zYccURgce0iXWS6qNiNO0AKK/ckIGeL0Bv
# bTfCbimx1KKwkAnBMJoYDDcnGLL1vsolDVr7jL9CaWqqLHcHn0TXGAV2+mCnfdqa
# nqIGAThEPY440S63oqA6kE8xggL1MIIC8QIBATCBkzB8MQswCQYDVQQGEwJVUzET
# MBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMV
# TWljcm9zb2Z0IENvcnBvcmF0aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1T
# dGFtcCBQQ0EgMjAxMAITMwAAAK4O1k6WidsA9QAAAAAArjANBglghkgBZQMEAgEF
# AKCCATIwGgYJKoZIhvcNAQkDMQ0GCyqGSIb3DQEJEAEEMC8GCSqGSIb3DQEJBDEi
# BCCDsBikg3jSOvwGpvn9u/88bGJUZbmL5neplhNYO9CemjCB4gYLKoZIhvcNAQkQ
# AgwxgdIwgc8wgcwwgbEEFMfBvTB7pRieZF5ndDb6u+OZvGj7MIGYMIGApH4wfDEL
# MAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1v
# bmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEmMCQGA1UEAxMdTWlj
# cm9zb2Z0IFRpbWUtU3RhbXAgUENBIDIwMTACEzMAAACuDtZOlonbAPUAAAAAAK4w
# FgQURRIf1STm8i/a3CKsseco7aFEIW8wDQYJKoZIhvcNAQELBQAEggEAtRnNQ1C2
# L6QWZlFUjgrSXEnw8e81a2W0tETTEt2zlje7qnM59/sg9jh/6P4QmS/9/yH9qWGy
# 2bh1haJ4uVR/LWSRYQVSvIOPPy/NYNb/O422x2L+89GWHsMYJbjoFqR10wX+Wb46
# xloMmNF7vFPZfpLSj7Rgb9P2PQ115ZY4DskySi+Nba7eP9UqTeGyYt+RFrmcav7A
# /+7rYGZkFwnOk7ffwW/GxRcMsge7ikRwBtT8GbeTG5bMjT6IB0AP294GjvJ7jycU
# hObMGsibNIB/KyrPdjI02+utAebwv/DhQPRPBGSFmLXBdep769kGb3v/KAJzQXDt
# +Kr7sy5VBAY+dw==
# SIG # End signature block
