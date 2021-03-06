[CmdletBinding()]
param
(
    [Parameter(Mandatory=$false)]
    [string]$LogDir
)

Import-Module WebAdministration
Import-Module "$PSScriptRoot\ExecuteSqltoAXDB.psm1" -Force -DisableNameChecking
Import-Module "$PSScriptRoot\CommonRollBackUtilities.psm1" -Force -DisableNameChecking
Import-Module "$PSScriptRoot\AosEnvironmentUtilities.psm1" -Force -DisableNameChecking

if ((Get-Service | where Name -eq DynamicsAxBatch) -eq $null)
{
    throw 'Cannot upgrade data; DynamicsAX batch is not installed on this machine.'
}

if(!$LogDir)
{
    $LogDir = $PSScriptRoot
}

$webroot = Get-AosWebSitePhysicalPath

$metadataDirectory = Get-CommonBinDir

[xml]$web = Get-Content "$($webroot)\web.config"


function AdjustSqlSequences
{
        #Adjust sql sequences for all the tables
        Write-Output 'Start adjusting sql sequences for all the tables' 

        $adjustsqlseq = Get-Content "$PSScriptRoot\AdjustSQLSequences.sql" -Raw

        Invoke-SQL -sqlCommand:$adjustsqlseq
        Write-Output 'Finished adjusting sql sequences for all the tables'
}

$sqlPwd = Get-DataAccessSqlPwd
$sqlUser = Get-DataAccessSqlUsr
$sqlServer = Get-DataAccessDbServer
$sqlDB = Get-DataAccessDatabase

$sqlParams = @{
   'Database' = $sqlDB
   'UserName' = $sqlUser
   'Password' = $sqlPwd
   'ServerInstance' = $sqlServer
   'Query' = "SELECT Top 1 Description FROM SYSSETUPLOG WHERE Name = 'ReleaseUpdateDBGetFromVersion' 
                          and Version = '7.0' order by Description desc"
}
$Version = Invoke-SqlCmd @sqlParams

switch($version.Description)
{
 "170" 
    { 
        AdjustSqlSequences
    }
 "180" 
    { 
        AdjustSqlSequences
    }
 default 
    { 
        Write-Output "Skipping SQL Sequence Adjustment"
    }
}

Write-Output 'Update Web.Config file - set Safe Mode On'
($web.configuration.appSettings.add | where key -eq 'Aos.SafeMode' | select -First 1).Value  = 'True'
$web.Save("$($webroot)\web.config")

Write-Output 'Constructing the connection string for the SQL DB using the web.config'

$connectionString = "Data Source=$sqlServer; " +
        "Integrated Security=False; " +
        "User Id=$sqlUser; " +
        "Password='`"$sqlPwd`"'; " +
        "Initial Catalog=$sqlDB"

#Sync Engine
Write-Output 'Starting SyncEngine to trigger the kernal tables sync'
$command = Join-Path $metadataDirectory "Bin\SyncEngine.exe"
Write-Output $command "-syncmode=partiallist -synclist=userguid,batchjob,userinfo,SYSUSERINFO,SysDataCacheConfigurationTable,SYSDATASHARINGFOREIGNKEYTABLE,SYSDATASHARINGISSUES,SYSDATASHARINGORGANIZATION,SYSDATASHARINGORGANIZATIONENABLED,SYSDATASHARINGPOLICY,SYSDATASHARINGPOLICYSTAGING,SYSDATASHARINGRULE,SYSDATASHARINGRULEENABLED,SYSDATASHARINGRULEISSUES,SYSDATASHARINGTABLEFIELD,SYSDATASHARINGTABLEFIELDENABLED,SYSDATASHARINGTESTFKINKEY,SYSDATASHARINGTESTFOREIGNKEYTABLE,SYSDATASHARINGTESTTABLE,SYSDATABASELOG,SYSDATABASELOGLINES,SYSFLIGHTING,SYSUSERLOG,EVENTCUD,EVENTCUDLINES -metadatabinaries=$metadataDirectory"

$arguments = "-syncmode=partiallist -synclist=userguid,batch,batchjob,userinfo,SYSUSERINFO,SysDataCacheConfigurationTable,SYSDATASHARINGFOREIGNKEYTABLE,SYSDATASHARINGISSUES,SYSDATASHARINGORGANIZATION,SYSDATASHARINGORGANIZATIONENABLED,SYSDATASHARINGPOLICY,SYSDATASHARINGPOLICYSTAGING,SYSDATASHARINGRULE,SYSDATASHARINGRULEENABLED,SYSDATASHARINGRULEISSUES,SYSDATASHARINGTABLEFIELD,SYSDATASHARINGTABLEFIELDENABLED,SYSDATASHARINGTESTFKINKEY,SYSDATASHARINGTESTFOREIGNKEYTABLE,SYSDATASHARINGTESTTABLE,ReleaseUpdateConfiguration,ReleaseUpdateScriptsErrorLog,ReleaseUpdateScriptsLog,ReleaseUpdateDisabledIndexes,ReleaseUpdateVersions,SYSDATABASELOG,SYSDATABASELOGLINES,SYSFLIGHTING,SYSUSERLOG,EVENTCUD,EVENTCUDLINES,RELEASEUPDATESCRIPTSUSEDTABLES -metadatabinaries=$metadataDirectory -connect=`"$connectionstring`""

$process = Start-Process $command -ArgumentList $arguments -PassThru -Wait -RedirectStandardOutput "$LogDir\partialsync.log" -RedirectStandardError "$LogDir\partialsync.error.log"

#Update Web.Config file - set Safe Mode Off
[xml]$web = Get-Content "$($webroot)\web.config"
($web.configuration.appSettings.add | where key -eq 'Aos.SafeMode' | select -First 1).Value  = 'False'
$web.Save("$($webroot)\web.config")

$partialSyncError = Get-Content "$LogDir\partialsync.error.log"
if ($partialSyncError -ne $null)
{
    Write-Error 'Failed pre requisities for running the data upgrade. Please fix the issues in the error log and retry the step'
    throw $partialSyncError
}

#start aos to verify the system table and webconfig have been upgraded correctly
$aosSiteName = Get-AosWebSiteName
$aosAppPoolName = Get-AosAppPoolName
Start-WebSite $aosSiteName
Start-WebAppPool $aosAppPoolName
if((Get-WebAppPoolState $aosAppPoolName).Value -ne 'Started') 
{
    throw 'Failed to start the website $aosSiteName'
}

Stop-WebSite $aosSiteName
if((Get-WebAppPoolState $aosAppPoolName).Value -ne 'Stopped') 
{
    Stop-WebAppPool $aosAppPoolName
}


write-Output 'Finished pre requisites for running the data upgrade'
#Need a way to check if we can start AOS successfully

# SIG # Begin signature block
# MIIkCgYJKoZIhvcNAQcCoIIj+zCCI/cCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCAN4d842lQvZtF9
# LIAt5VP3ulNWtrs2K9ahs5UvJidtaaCCDYIwggYAMIID6KADAgECAhMzAAAAww6b
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
# SEXAQsmbdlsKgEhr/Xmfwb1tbWrJUnMTDXpQzTGCFd4wghXaAgEBMIGVMH4xCzAJ
# BgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25k
# MR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xKDAmBgNVBAMTH01pY3Jv
# c29mdCBDb2RlIFNpZ25pbmcgUENBIDIwMTECEzMAAADDDpun2LLc9ywAAAAAAMMw
# DQYJYIZIAWUDBAIBBQCggdAwGQYJKoZIhvcNAQkDMQwGCisGAQQBgjcCAQQwHAYK
# KwYBBAGCNwIBCzEOMAwGCisGAQQBgjcCARUwLwYJKoZIhvcNAQkEMSIEIGNLwYkX
# J3vzY6hBI6XqN8+OOLeriFT5rkxkSOlK5cNiMGQGCisGAQQBgjcCAQwxVjBUoDaA
# NABBAHUAdABvAEQAYQB0AGEAVQBwAGcAcgBhAGQAZQBQAHIAZQBSAGUAcQBzAC4A
# cABzADGhGoAYaHR0cDovL3d3dy5taWNyb3NvZnQuY29tMA0GCSqGSIb3DQEBAQUA
# BIIBADrz3TPcTfAnMAa0d8R2+CDfUsuD+x2PF5i/Mhpaw7gaT2xa+PaK8qo2gDUu
# KMSTt/Qlkneb/hDsAz90nnKaNX56tn0aFVswtPVXRgh3016S9Vr3VQv1VAsGTxEV
# D7xfyta9pPtA3Af8dcX+TDuFy6jYp5VpamYisJUIUj0VXxVpQyRdrz1Lu3OXr4yO
# k2TP/we+lzH1JZifd7LQ/DyZQXAxfQqRkORJNBw9ht8cicUlVKAuX8jBYX3Uq2wH
# 9G/5pkwjNjo0wxgzAn+XLxv0ILPY0vcbErRjTegIogRu0z5wd2r4e4GJv0Vz5Pyp
# nBtc0QlCWcteVu03oD2ah/2cq9ehghNGMIITQgYKKwYBBAGCNwMDATGCEzIwghMu
# BgkqhkiG9w0BBwKgghMfMIITGwIBAzEPMA0GCWCGSAFlAwQCAQUAMIIBOwYLKoZI
# hvcNAQkQAQSgggEqBIIBJjCCASICAQEGCisGAQQBhFkKAwEwMTANBglghkgBZQME
# AgEFAAQggjCCgqzRw+voR8yhCfm1TAdvSqNlQMbys0XA1XiAxdACBlqyr2CzARgT
# MjAxODAzMjUyMTA1NTAuNDI4WjAHAgEBgAIB9KCBt6SBtDCBsTELMAkGA1UEBhMC
# VVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNV
# BAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEMMAoGA1UECxMDQU9DMSYwJAYDVQQL
# Ex1UaGFsZXMgVFNTIEVTTjo5NkZGLTRCQzUtQTdEQzElMCMGA1UEAxMcTWljcm9z
# b2Z0IFRpbWUtU3RhbXAgU2VydmljZaCCDsswggZxMIIEWaADAgECAgphCYEqAAAA
# AAACMA0GCSqGSIb3DQEBCwUAMIGIMQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2Fz
# aGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENv
# cnBvcmF0aW9uMTIwMAYDVQQDEylNaWNyb3NvZnQgUm9vdCBDZXJ0aWZpY2F0ZSBB
# dXRob3JpdHkgMjAxMDAeFw0xMDA3MDEyMTM2NTVaFw0yNTA3MDEyMTQ2NTVaMHwx
# CzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRt
# b25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xJjAkBgNVBAMTHU1p
# Y3Jvc29mdCBUaW1lLVN0YW1wIFBDQSAyMDEwMIIBIjANBgkqhkiG9w0BAQEFAAOC
# AQ8AMIIBCgKCAQEAqR0NvHcRijog7PwTl/X6f2mUa3RUENWlCgCChfvtfGhLLF/F
# w+Vhwna3PmYrW/AVUycEMR9BGxqVHc4JE458YTBZsTBED/FgiIRUQwzXTbg4CLNC
# 3ZOs1nMwVyaCo0UN0Or1R4HNvyRgMlhgRvJYR4YyhB50YWeRX4FUsc+TTJLBxKZd
# 0WETbijGGvmGgLvfYfxGwScdJGcSchohiq9LZIlQYrFd/XcfPfBXday9ikJNQFHR
# D5wGPmd/9WbAA5ZEfu/QS/1u5ZrKsajyeioKMfDaTgaRtogINeh4HLDpmc085y9E
# uqf03GS9pAHBIAmTeM38vMDJRF1eFpwBBU8iTQIDAQABo4IB5jCCAeIwEAYJKwYB
# BAGCNxUBBAMCAQAwHQYDVR0OBBYEFNVjOlyKMZDzQ3t8RhvFM2hahW1VMBkGCSsG
# AQQBgjcUAgQMHgoAUwB1AGIAQwBBMAsGA1UdDwQEAwIBhjAPBgNVHRMBAf8EBTAD
# AQH/MB8GA1UdIwQYMBaAFNX2VsuP6KJcYmjRPZSQW9fOmhjEMFYGA1UdHwRPME0w
# S6BJoEeGRWh0dHA6Ly9jcmwubWljcm9zb2Z0LmNvbS9wa2kvY3JsL3Byb2R1Y3Rz
# L01pY1Jvb0NlckF1dF8yMDEwLTA2LTIzLmNybDBaBggrBgEFBQcBAQROMEwwSgYI
# KwYBBQUHMAKGPmh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2kvY2VydHMvTWlj
# Um9vQ2VyQXV0XzIwMTAtMDYtMjMuY3J0MIGgBgNVHSABAf8EgZUwgZIwgY8GCSsG
# AQQBgjcuAzCBgTA9BggrBgEFBQcCARYxaHR0cDovL3d3dy5taWNyb3NvZnQuY29t
# L1BLSS9kb2NzL0NQUy9kZWZhdWx0Lmh0bTBABggrBgEFBQcCAjA0HjIgHQBMAGUA
# ZwBhAGwAXwBQAG8AbABpAGMAeQBfAFMAdABhAHQAZQBtAGUAbgB0AC4gHTANBgkq
# hkiG9w0BAQsFAAOCAgEAB+aIUQ3ixuCYP4FxAz2do6Ehb7Prpsz1Mb7PBeKp/vpX
# bRkws8LFZslq3/Xn8Hi9x6ieJeP5vO1rVFcIK1GCRBL7uVOMzPRgEop2zEBAQZvc
# XBf/XPleFzWYJFZLdO9CEMivv3/Gf/I3fVo/HPKZeUqRUgCvOA8X9S95gWXZqbVr
# 5MfO9sp6AG9LMEQkIjzP7QOllo9ZKby2/QThcJ8ySif9Va8v/rbljjO7Yl+a21dA
# 6fHOmWaQjP9qYn/dxUoLkSbiOewZSnFjnXshbcOco6I8+n99lmqQeKZt0uGc+R38
# ONiU9MalCpaGpL2eGq4EQoO4tYCbIjggtSXlZOz39L9+Y1klD3ouOVd2onGqBooP
# iRa6YacRy5rYDkeagMXQzafQ732D8OE7cQnfXXSYIghh2rBQHm+98eEA3+cxB6ST
# OvdlR3jo+KhIq/fecn5ha293qYHLpwmsObvsxsvYgrRyzR30uIUBHoD7G4kqVDmy
# W9rIDVWZeodzOwjmmC3qjeAzLhIp9cAvVCch98isTtoouLGp25ayp0Kiyc8ZQU3g
# hvkqmqMRZjDTu3QyS99je/WZii8bxyGvWbWu3EQ8l1Bx16HSxVXjad5XwdHeMMD9
# zOZN+w2/XU/pnR4ZOC+8z1gFLu8NoFA12u8JJxzVs341Hgi62jbb01+P3nSISRIw
# ggTYMIIDwKADAgECAhMzAAAAtotHQ7LMrR8EAAAAAAC2MA0GCSqGSIb3DQEBCwUA
# MHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdS
# ZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xJjAkBgNVBAMT
# HU1pY3Jvc29mdCBUaW1lLVN0YW1wIFBDQSAyMDEwMB4XDTE3MTAwMjIzMDA1MloX
# DTE5MDEwMjIzMDA1MlowgbExCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5n
# dG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9y
# YXRpb24xDDAKBgNVBAsTA0FPQzEmMCQGA1UECxMdVGhhbGVzIFRTUyBFU046OTZG
# Ri00QkM1LUE3REMxJTAjBgNVBAMTHE1pY3Jvc29mdCBUaW1lLVN0YW1wIFNlcnZp
# Y2UwggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIBAQDYiWcXSEsIt0QbkxHD
# Os9uQUCmqFxiY7JbI0QzNfWe3f3AcsuLSWwweyEAZZKWKUSnDHtTP1lOIHuWbrJY
# EO+uPRGHfDVmKm+1/K/QwkpyrT/OEOPXEAnF5RLjX85g6Nv4akltPyWgaVGno9Ys
# /EPhQglKND1USEokv3zh3aZnC95ssVK4x8jSEZsmdP6cd2AaZmMsDD/YAQTfvnkz
# CsnqP7ulFHY1hxLZd10yFvHu8vdtYF0ofSdmaR1JF+SV7fgO/rhnm/+8uu0d16Tw
# ewmwKARqSnMRJNXzyjUTbFbFxhxw1hO1s0YGtCyqSUTnmJUPFbvTpS15CAGAHw2m
# TMExAgMBAAGjggEbMIIBFzAdBgNVHQ4EFgQU823CkAEnINqPMxzAX2hq34EDhdAw
# HwYDVR0jBBgwFoAU1WM6XIoxkPNDe3xGG8UzaFqFbVUwVgYDVR0fBE8wTTBLoEmg
# R4ZFaHR0cDovL2NybC5taWNyb3NvZnQuY29tL3BraS9jcmwvcHJvZHVjdHMvTWlj
# VGltU3RhUENBXzIwMTAtMDctMDEuY3JsMFoGCCsGAQUFBwEBBE4wTDBKBggrBgEF
# BQcwAoY+aHR0cDovL3d3dy5taWNyb3NvZnQuY29tL3BraS9jZXJ0cy9NaWNUaW1T
# dGFQQ0FfMjAxMC0wNy0wMS5jcnQwDAYDVR0TAQH/BAIwADATBgNVHSUEDDAKBggr
# BgEFBQcDCDANBgkqhkiG9w0BAQsFAAOCAQEAL9fV6r6YjngcusMqQ6RNTMxlMyhH
# FeU6lt4W5dc6uz08KkDGIyK4QNnY/FFkUhE4g8bvSvnCCCmZgS6WhWUynEXg7Kgd
# hpprKd24sQT/t9/5SijbEPASLMyX+dm0qihiyLAqg+ul9dDoCuHqUkLNrEQHKRnu
# XjGWP/h1t+XY7kR8zI/ZRwzWwOjrEI8fyo2wXh+ojmp7qzbk9fMzDHXfKS9kyJ7d
# 230GwxnWNJNpDwdaS6BUlcAeeU2RaiiXp9VGVHSbuWn1HgM6nGY6t2jrzCfCA4sa
# 6EEFhWGSSZKSAflzZPmtDP7d3dK/H2K+utKHVxJTQAeE20zDrlq3tqxkSKGCA3Yw
# ggJeAgEBMIHhoYG3pIG0MIGxMQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGlu
# Z3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBv
# cmF0aW9uMQwwCgYDVQQLEwNBT0MxJjAkBgNVBAsTHVRoYWxlcyBUU1MgRVNOOjk2
# RkYtNEJDNS1BN0RDMSUwIwYDVQQDExxNaWNyb3NvZnQgVGltZS1TdGFtcCBTZXJ2
# aWNloiUKAQEwCQYFKw4DAhoFAAMVAP8WK+8VXLPVtZYrvghLIfxNdAABoIHBMIG+
# pIG7MIG4MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UE
# BxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMQwwCgYD
# VQQLEwNBT0MxJzAlBgNVBAsTHm5DaXBoZXIgTlRTIEVTTjoyNjY1LTRDM0YtQzVE
# RTErMCkGA1UEAxMiTWljcm9zb2Z0IFRpbWUgU291cmNlIE1hc3RlciBDbG9jazAN
# BgkqhkiG9w0BAQUFAAIFAN5h0j0wIhgPMjAxODAzMjUwNzQ2MDVaGA8yMDE4MDMy
# NjA3NDYwNVowdzA9BgorBgEEAYRZCgQBMS8wLTAKAgUA3mHSPQIBADAKAgEAAgII
# PAIB/zAHAgEAAgIWGDAKAgUA3mMjvQIBADA2BgorBgEEAYRZCgQCMSgwJjAMBgor
# BgEEAYRZCgMBoAowCAIBAAIDFuNgoQowCAIBAAIDHoSAMA0GCSqGSIb3DQEBBQUA
# A4IBAQCHtFTNf9VhmeusIlsKCXap17ECzsDZAGUziqqRni2DlqEhz6JSehyScH/5
# BSXctjxvLg5N2m1FXJge0GUbWnmvQqcnBJxUHlPlrD0ncnY1IQWPUdu+DvmFHObl
# J2PcuQxU0Ez65WIiC9iEvoG2wXrrDtUEoNUlM+iZpMJFc9IcDrSAppw1jBARsK0T
# +ut4fvlVmBG0mqzBXbfNeimS9gnJoABhVqmGnQF1V0aKOIxfUxp+ffNx35TOgEqv
# mIDFuQbmYYykdynT6Ly7gd2IbdnIlvNFbByQZEhgID+1+EHvE7+HHKnQDowdTqXj
# nz9k2uv5IxTUid+BK7CrmXDbW5uxMYIC9TCCAvECAQEwgZMwfDELMAkGA1UEBhMC
# VVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNV
# BAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRp
# bWUtU3RhbXAgUENBIDIwMTACEzMAAAC2i0dDssytHwQAAAAAALYwDQYJYIZIAWUD
# BAIBBQCgggEyMBoGCSqGSIb3DQEJAzENBgsqhkiG9w0BCRABBDAvBgkqhkiG9w0B
# CQQxIgQgjs4yZ33GizxOYaZMWlqJITj2jtDSerwVCNZsXzkTTlcwgeIGCyqGSIb3
# DQEJEAIMMYHSMIHPMIHMMIGxBBT/FivvFVyz1bWWK74ISyH8TXQAATCBmDCBgKR+
# MHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdS
# ZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xJjAkBgNVBAMT
# HU1pY3Jvc29mdCBUaW1lLVN0YW1wIFBDQSAyMDEwAhMzAAAAtotHQ7LMrR8EAAAA
# AAC2MBYEFC4W+BaZMMSYWdHzB63rgBi4Ysh7MA0GCSqGSIb3DQEBCwUABIIBADCn
# TgqyvmPzamdjiQoEhGrmREgT0WgiABHmsBH7MZhwoRlg/W1TfRUiMX/jWO+diFVE
# d6TN4Mps/qdlZR7DH3JHuBQQhGLm6JfQgNgIVmwZXB6By/W3zjKEdHh3Ei9cjfjw
# JKNJBs3lPWSZ6Ofr2YFhkQF+aqqjHQAWy45KKDAh82O0SN0OzRZHP2GJreq3OkW3
# z7cyDIEfgW7gNcHU6ql76l7UQ5dtOPT7iq4VZOnmSzlGPzZlhwxdWuvlMfclBkUV
# NBsqFohXdfnEXme2ztQt/iObyHexH04h3mRlJi05DMgg0PI3WiE9mHXu5W6hiuL2
# JPqR/IKAvrGy7aUOCCs=
# SIG # End signature block
