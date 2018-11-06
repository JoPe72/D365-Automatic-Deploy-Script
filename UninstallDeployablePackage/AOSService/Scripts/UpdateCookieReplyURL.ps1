Import-Module WebAdministration
Import-Module "$PSScriptRoot\CommonRollbackUtilities.psm1" -DisableNameChecking

######################################################################
###                                                                ###
###  Helper Functions                                              ###
###                                                                ###
######################################################################

function Create-Backup([string]$webroot,[string]$backupdir)
{
    $orig_webconfig= Join-Path -Path $webroot -ChildPath "web.config"
    $orig_wifconfig= Join-Path -Path $webroot -ChildPath "wif.config"
    $orig_wifservicesconfig=Join-Path -Path $webroot -ChildPath "wif.services.config"

    $backup_webconfig= Join-Path -Path $backupdir -ChildPath "web.config.backup"
    $backup_wifconfig= Join-Path -Path $backupdir -ChildPath "wif.config.backup"
    $backup_wifservicesconfig=Join-Path -Path $backupdir -ChildPath "wif.services.config.backup"
    
    if (!(Test-Path $backupdir))
    {
        mkdir $backupdir
    }

    Copy-Item -Path $orig_webconfig -Destination $backup_webconfig -Force|out-null
    Write-Output "Copied '$orig_webconfig' to '$backup_webconfig."

    Copy-item -Path $orig_wifconfig -Destination $backup_wifconfig -Force|out-null
    Write-Output "Copied '$orig_wifconfig' to '$backup_wifconfig'."

    Copy-item -Path $orig_wifservicesconfig -Destination $backup_wifservicesconfig -Force|out-null
    Write-Output "Copied '$orig_wifservicesconfig' to '$backup_wifservicesconfig'."
}

function Append-KeyValue([string] $key, [string] $value, [System.Xml.XmlDocument] $xmlDoc)
{
    [System.Xml.XmlNode] $nodeForUpdate = $xmlDoc.SelectSingleNode("//add[@key='$key']")

    if($nodeForUpdate -eq $null)
    {
        Throw "Failed to find key node '$key' for update"
    }

    Write-Output "selected node '$key' for update"

    $ExistingValue = $nodeForUpdate.Value
    $AppendValue = $ExistingValue -ireplace $UpradeENVName, $value
    $nodeForUpdate.Value = $ExistingValue + '; ' +  $AppendValue
}

function Update-WifServiceConfig([string] $newValue)
{
    [System.Xml.XmlDocument] $xmlDoc=new-object System.Xml.XmlDocument
    $xmlDoc.Load($wifserviceconfig)
    
    $CookieHandlerNode = $xmlDoc.SelectSingleNode("/system.identityModel.services/federationConfiguration/cookieHandler")
    $newCookieValue = ($CookieHandlerNode.domain.ToLower().Replace($UpradeENVName.ToLower(), $newValue.ToLower()))
    $CookieHandlerNode.domain = $newCookieValue 
    
    Write-Output "Updated Cookie Domain value with '$newValue' "

    $xmlDoc.Save($wifserviceconfig);
}

function Update-RetailServerWebConfig([string] $newValue)
{
    [System.Xml.XmlDocument] $xmlDoc=new-object System.Xml.XmlDocument
    $xmlDoc.Load($retailServerWebConfig)
    
    $allowedOriginsKey = 'AllowedOrigins'
    Append-KeyValue -key $allowedOriginsKey -value $newValue -xmlDoc $xmlDoc
        
    $xmlDoc.Save($retailServerWebConfig);    
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

$ErrorActionPreference = "stop"

# Update AOS 
$webroot = Get-AosWebSitePhysicalPath

if ($webroot)
{
    Create-Backup -webroot $webroot -backupdir (Join-Path -Path $webroot -ChildPath "ConfigBackup")

    $webconfig = "$webroot\web.config"
    $wifconfig = "$webroot\wif.config"
    $wifserviceconfig = "$webroot\wif.services.config"

    Update-WifServiceConfig -newValue $ExistingProductionEnvName
}

# Update RetailServer Web Config
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
    $retailServerWebConfig = "$($webrootRetailServer.PhysicalPath)\web.config"
    Update-RetailServerWebConfig -newValue $ExistingProductionEnvName
}

# Update Retail POS Config file
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
    $retailPosConfig = "$($webrootRetailcloudPos.PhysicalPath)\config.json"
    if ($retailPosConfig)
    {
        $configuration = ConvertFrom-Json (get-Content "$retailPosConfig" -raw)
        $configuration.RetailServerUrl = $configuration.RetailServerUrl.ToLower().Replace($UpradeENVName.ToLower(), $ExistingProductionEnvName.ToLower())
        ConvertTo-json($configuration) | Out-File $retailPosConfig        
    }
}    


# SIG # Begin signature block
# MIIkBgYJKoZIhvcNAQcCoIIj9zCCI/MCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCDABZBPB0DrBIfc
# MABlvHwhT96PKB+bLI1aiVP5D/zpQKCCDYIwggYAMIID6KADAgECAhMzAAAAww6b
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
# KwYBBAGCNwIBCzEOMAwGCisGAQQBgjcCARUwLwYJKoZIhvcNAQkEMSIEIKmCuSs2
# rgGOYLezWQu1gTYfkeNQoQdxLNq57aJvwDZkMGAGCisGAQQBgjcCAQwxUjBQoDKA
# MABVAHAAZABhAHQAZQBDAG8AbwBrAGkAZQBSAGUAcABsAHkAVQBSAEwALgBwAHMA
# MaEagBhodHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20wDQYJKoZIhvcNAQEBBQAEggEA
# mAW15ozNNDDPjpom12D55qg3PE9plqLWpSax0cVtC15+ta/b1MlCyRZcshVKaQog
# iFoMwV0Sj8jniPaCzyjw2FLw5BHpX3lK6Xt45lfAdUF6OlRDEkR80toio8eLGC6x
# 0N6OpVjI7eC0tVsMAL0vakS9qiEqUbRRexkWDp0/xHh9nPKiVGNop07osVHNgfgS
# 01294blRtz0GKJd3Gd1n3tBs1fKuwXURCrC7OcNVMINjmxAfy1gb6P6RqUfQvcZF
# NcneFlkQeLnRRofsN++4HhstF755nWCatqZhmzyUPSbj/MQKwyrsSZM+/ADvOutI
# k07aSkf7WBqU5pFMJPd/T6GCE0YwghNCBgorBgEEAYI3AwMBMYITMjCCEy4GCSqG
# SIb3DQEHAqCCEx8wghMbAgEDMQ8wDQYJYIZIAWUDBAIBBQAwggE8BgsqhkiG9w0B
# CRABBKCCASsEggEnMIIBIwIBAQYKKwYBBAGEWQoDATAxMA0GCWCGSAFlAwQCAQUA
# BCBBE3Zsr4W2fSepqGatd3zVQkEdj/grDdWAkha7OmGQKgIGWrKbxTUlGBMyMDE4
# MDMyNTIxMDU1MC41ODRaMAcCAQGAAgH0oIG4pIG1MIGyMQswCQYDVQQGEwJVUzET
# MBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMV
# TWljcm9zb2Z0IENvcnBvcmF0aW9uMQwwCgYDVQQLEwNBT0MxJzAlBgNVBAsTHm5D
# aXBoZXIgRFNFIEVTTjo1N0M4LTJEMTUtMUM4QjElMCMGA1UEAxMcTWljcm9zb2Z0
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
# MIIDwaADAgECAhMzAAAAqrepiP/qV8MKAAAAAACqMA0GCSqGSIb3DQEBCwUAMHwx
# CzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRt
# b25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xJjAkBgNVBAMTHU1p
# Y3Jvc29mdCBUaW1lLVN0YW1wIFBDQSAyMDEwMB4XDTE2MDkwNzE3NTY1M1oXDTE4
# MDkwNzE3NTY1M1owgbIxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9u
# MRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRp
# b24xDDAKBgNVBAsTA0FPQzEnMCUGA1UECxMebkNpcGhlciBEU0UgRVNOOjU3Qzgt
# MkQxNS0xQzhCMSUwIwYDVQQDExxNaWNyb3NvZnQgVGltZS1TdGFtcCBTZXJ2aWNl
# MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAnth/e1d4+gX6o5q3kK+a
# udW2dHaRy7jOuyrOKynvX7RrdZh1KICtmI+5qvCd0rabR2SYxqVZqpF4+R6Lefck
# dEbqJP5pBK6+639TUxNZ1Q/8+83d9gdBmxs3N9lcdpndrsfD29OtaMJQnHQORHcu
# Lp1vwR3vLMc7dK7bly2PgcVHBUDASjdIk7wDmkvwjQTLQ3D76FixnaxQ57m1hPHH
# mwfs95pp269If6xZMYZiFnCVXvHLzDpH8+o/AowQu70jjKkDc08OuAxc8S+qf/pk
# m4wumBTARs8mTzwGI8ZPIreSDxoCGfycKc2E3oGv8P2tmKyliIOGlVSGtJtxQMYv
# NwIDAQABo4IBGzCCARcwHQYDVR0OBBYEFAi4ch0VJPWTAuGf0hxM06vMWcmwMB8G
# A1UdIwQYMBaAFNVjOlyKMZDzQ3t8RhvFM2hahW1VMFYGA1UdHwRPME0wS6BJoEeG
# RWh0dHA6Ly9jcmwubWljcm9zb2Z0LmNvbS9wa2kvY3JsL3Byb2R1Y3RzL01pY1Rp
# bVN0YVBDQV8yMDEwLTA3LTAxLmNybDBaBggrBgEFBQcBAQROMEwwSgYIKwYBBQUH
# MAKGPmh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2kvY2VydHMvTWljVGltU3Rh
# UENBXzIwMTAtMDctMDEuY3J0MAwGA1UdEwEB/wQCMAAwEwYDVR0lBAwwCgYIKwYB
# BQUHAwgwDQYJKoZIhvcNAQELBQADggEBAGCPDu4HzhrhfZ95xngOnc5MpAGdamdH
# lxEbinLK5MF85y3jj5FnvOh0ej/K6UYkAD+hzvB+T9L0Gn30djgdFDYdpdmJb8rF
# UxTvEywgApXRCnnF0u5tPD+RRum5Ut7fXOKcpE1Rah3C6ZNNRnIWJvmE/5N33egD
# PVT8wgSgX4+HvVV0mulkrLDkGspcOyAfC1VYCLDDy6e8WSxNQpHtW7MwLpKnk45O
# gAyuqXkx7FKRfJUQr3/BziPbD5nMasPE9CwfdWSCLKDYDgf3mg5lqFyVgZx+WO55
# 85EhrdvNLL+1iHL+BhudX3YPdjKIrlI8bTkuzAZOJEktL6lmANb8aCahggN0MIIC
# XAIBATCB4qGBuKSBtTCBsjELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0
# b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3Jh
# dGlvbjEMMAoGA1UECxMDQU9DMScwJQYDVQQLEx5uQ2lwaGVyIERTRSBFU046NTdD
# OC0yRDE1LTFDOEIxJTAjBgNVBAMTHE1pY3Jvc29mdCBUaW1lLVN0YW1wIFNlcnZp
# Y2WiJQoBATAJBgUrDgMCGgUAAxUAnJzFa5jMp8GtRyDs00T8zm3Q6gOggcEwgb6k
# gbswgbgxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQH
# EwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xDDAKBgNV
# BAsTA0FPQzEnMCUGA1UECxMebkNpcGhlciBOVFMgRVNOOjI2NjUtNEMzRi1DNURF
# MSswKQYDVQQDEyJNaWNyb3NvZnQgVGltZSBTb3VyY2UgTWFzdGVyIENsb2NrMA0G
# CSqGSIb3DQEBBQUAAgUA3mHptDAiGA8yMDE4MDMyNTA5MjYxMloYDzIwMTgwMzI2
# MDkyNjEyWjB0MDoGCisGAQQBhFkKBAExLDAqMAoCBQDeYem0AgEAMAcCAQACAiae
# MAcCAQACAhoLMAoCBQDeYzs0AgEAMDYGCisGAQQBhFkKBAIxKDAmMAwGCisGAQQB
# hFkKAwGgCjAIAgEAAgMW42ChCjAIAgEAAgMehIAwDQYJKoZIhvcNAQEFBQADggEB
# AEs9N9xKVvOJ2aRkChP20wcjrg3ajVBZd+OPITVS03FkmD1J6p66tyINewMwvc05
# M5UCSH7gh0cqmGmwUWiA8cCVNmSaUDB6ajspVsEyxZ/1MMoni1/6ljMMQKaA0cJh
# URmwu4y4kuu1/SC+MGhPdwkEKF1bY7nvlLCcXVeqi6iLOED1cWs3oIsjvSc8IS1Y
# FFvMR720ueN9iO6LkRgoGGHcpyyxUMSQGUJOiasJOCcyK6i0bRjRY8UwbWWHxdZr
# MDzFmufratDG1PCjBZFDlskinhTwH+ims7JOLWie+R3ActLvfaPhfRv3d7OoyDXF
# C25tYBiLrz5WZu4Lzwd/OCAxggL1MIIC8QIBATCBkzB8MQswCQYDVQQGEwJVUzET
# MBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMV
# TWljcm9zb2Z0IENvcnBvcmF0aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1T
# dGFtcCBQQ0EgMjAxMAITMwAAAKq3qYj/6lfDCgAAAAAAqjANBglghkgBZQMEAgEF
# AKCCATIwGgYJKoZIhvcNAQkDMQ0GCyqGSIb3DQEJEAEEMC8GCSqGSIb3DQEJBDEi
# BCACkr3xdtylOC35ZZ7+cuWOEqm+FWfbAiaF0I4g8QPNgDCB4gYLKoZIhvcNAQkQ
# AgwxgdIwgc8wgcwwgbEEFJycxWuYzKfBrUcg7NNE/M5t0OoDMIGYMIGApH4wfDEL
# MAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1v
# bmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEmMCQGA1UEAxMdTWlj
# cm9zb2Z0IFRpbWUtU3RhbXAgUENBIDIwMTACEzMAAACqt6mI/+pXwwoAAAAAAKow
# FgQUKDMlH0efudqvYEvPuyPw0YRN/GgwDQYJKoZIhvcNAQELBQAEggEATeEcNyVQ
# HLWFZMpulB/MLCOtCEf+kYc+84voOrFk3J5eAtdEI9idizBOjCh8Fy7uVTyofo9O
# wbZsxk1mQKK1GdoFsWwcKTDKWgH3OUusMeuUPutQDlkKyaUu//C14dostiP/t3Cw
# YH3Gh9o4NorMSdQVKkERDolwu8jaQQQFin965u3U37tpncMhypjdYLCsYDoYgKz+
# 38rA6A1YfqUub9KzU7OnuUbCftOdpVtHRwgrQIaIdpK13MgvmVZJhmVO+ccGcY6r
# 7EuPPPgGHOTuvp+y3fmRH5HNieaP7XT3Pew5fYy0PoHClgkWa1H0o65c1j24JaNX
# idk5GFuLwyKirA==
# SIG # End signature block
