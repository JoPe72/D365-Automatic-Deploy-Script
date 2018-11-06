param
(
    [Parameter(Mandatory=$true)]
    [string]$config,
    
    [Parameter(Mandatory=$true)]
    [string]$log
)

Import-Module WebAdministration

#region local functions
function Write-Log {
    Param ($message)
	Write-Output $message
    if ($log -ne $null) { Add-content "$log" ("`n[{0}]: {1}`n" -f (Get-Date), $message) }
}

function ExecuteWith-Retry($codeBlock, $blockMessage, $maxRetry, $sleepTime)
{    
    Write-Log "$blockMessage`: Starting execution with retry"
    if ($maxRetry -eq $null -or $maxRetry -le 0)
    {
        $maxRetry = 5
    }

    if ($sleepTime -eq $null -or $sleepTime -lt 0)
    {
        $sleepTime = 30
    }

    $retry = 0
    for($retry = 0; $retry -lt $maxRetry; $retry++)
    {
        try
        {
            &$codeBlock
            break;
        }
        catch
        {
            $exception = $_
            $message = "Exception during $blockMessage`: "
            if($retry -lt $maxRetry-1)
            {
                Write-Log $message
                Write-Log $exception                
                Write-Log "Sleeping 30s before retrying"
                Sleep $sleepTime
            }
            else
            {
                $message = "Max retry count reached during $blockMessage`: "
                Write-Log $message
                Write-Log $exception
                throw $exception
            }
        }
    }
    $retry++
    Write-Log "$blockMessage`: Completed execution in $retry iterations"
}

#endregion

$settings = @{}
if ($config -ne $null)
{
    $decodedConfig = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($config))
    $settings = ConvertFrom-Json $decodedConfig
}
else{
    Write-Log "Cannot proceed as the configuration is null."
    return
}

#region main method
$aosWebsiteName = $settings.'Infrastructure.ApplicationName'
Write-Log "AOS website name $aosWebsiteName"
$aossite=Get-Website -Name $aosWebsiteName
if($aossite -eq $null){
    $message="The website $aosWebsiteName does not exist."
    Write-Log $message
    throw $message
}

Write-Log "Starting the configuration of the production configuration application."
$webroot=$aossite.physicalPath
$productconfigurationdir=join-path $webRoot "productconfiguration"
if(!(Test-Path $productconfigurationdir)){
    Write-Log "Product configuration directory does not exist under the aos web root $webroot."
    return
}

$pcapppool="productconfiguration"

$codeblock={
    Write-Log "Removing web app pool $pcapppool."
    if ((Test-Path IIS:\AppPools\$pcapppool))
    {
        Remove-WebAppPool -Name:$pcapppool -ErrorAction SilentlyContinue
    }
    return $true
}

ExecuteWith-Retry $codeblock "Remove the product configuration web app pool" 

$codeblock={
    Write-Log "Creating web app pool $pcapppool."
    $newapppool=New-WebAppPool -Name:$pcapppool -ErrorAction SilentlyContinue
    Write-Log "Setting the identity for the web app pool '$pcapppool' to NetworkService."
    $newapppool.processModel.identityType="NetworkService"
    $newapppool|Set-Item
    Write-Log "Starting web app pool $pcapppool."
    Start-WebAppPool -Name:$pcapppool
    return $true
}

ExecuteWith-Retry $codeblock "Create the product configuration web app pool" 

$codeblock={
    Write-Log "Deleting web application 'ProductConfiguration' under web site `"$aossite.Name`"."
    Remove-WebApplication -Site:$aossite.Name -Name:"ProductConfiguration" -ErrorAction SilentlyContinue
    Write-Log "Creating new web application 'ProductConfiguration' under web site `"$aossite.Name`" with application pool `"$pcapppool`"."
    New-WebApplication -Site:$aossite.Name -Name:"ProductConfiguration" -PhysicalPath:$productconfigurationdir -ApplicationPool:$pcapppool -Force 
    return $true
}

ExecuteWith-Retry $codeblock "Create the product configuration web application"

Write-Log "Product configuration application successfully configured."
#endregion

# SIG # Begin signature block
# MIIkGgYJKoZIhvcNAQcCoIIkCzCCJAcCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCCPOCtj93ZAt5Ny
# GfFAgw07pNISN1ZXxLgAsLZaoBurEKCCDYIwggYAMIID6KADAgECAhMzAAAAww6b
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
# SEXAQsmbdlsKgEhr/Xmfwb1tbWrJUnMTDXpQzTGCFe4wghXqAgEBMIGVMH4xCzAJ
# BgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25k
# MR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xKDAmBgNVBAMTH01pY3Jv
# c29mdCBDb2RlIFNpZ25pbmcgUENBIDIwMTECEzMAAADDDpun2LLc9ywAAAAAAMMw
# DQYJYIZIAWUDBAIBBQCggeAwGQYJKoZIhvcNAQkDMQwGCisGAQQBgjcCAQQwHAYK
# KwYBBAGCNwIBCzEOMAwGCisGAQQBgjcCARUwLwYJKoZIhvcNAQkEMSIEICK8kzWU
# 1tPOiitw7YTuVszjK9ovHT/4ngZFezqr2v6sMHQGCisGAQQBgjcCAQwxZjBkoEaA
# RABDAG8AbgBmAGkAZwB1AHIAZQAtAFAAcgBvAGQAdQBjAHQAQwBvAG4AZgBpAGcA
# dQByAGEAdABpAG8AbgAuAHAAcwAxoRqAGGh0dHA6Ly93d3cubWljcm9zb2Z0LmNv
# bTANBgkqhkiG9w0BAQEFAASCAQCJ779h5FBwsCZzRAp4M8q8cbIs9yILa4LWF8Sj
# qowietj+52bMWqve7QJSjk18G+/0VPZCuWzoRdzkiEqO32TpdEZbyjpUF/VEt2vs
# udINazPJY9qp8MAqugQyTlru/JBnvv/z8kIOtZxFodkQ6OLOMHQfgG1j03/e0rYF
# nzZ058yyKtn+M+kz7RPdwG9zYuKcoF3HgD0ogprbinkY1OTv7rzAJUPCMh4cCEc+
# XKKEIAbSCEadyhApClYxZ+I0DuYC4lcKRGGQnUo/55nh44Shfw1tFV/0bviCOgXd
# xWbl7u+AhLgkJ8Atysrw7Kp+4w94zFScMFiZKgiqPawEMfukoYITRjCCE0IGCisG
# AQQBgjcDAwExghMyMIITLgYJKoZIhvcNAQcCoIITHzCCExsCAQMxDzANBglghkgB
# ZQMEAgEFADCCATwGCyqGSIb3DQEJEAEEoIIBKwSCAScwggEjAgEBBgorBgEEAYRZ
# CgMBMDEwDQYJYIZIAWUDBAIBBQAEIG+ACr0PEgYgQoIzHjz2wGoBkX7CTiCSc5qn
# gJPbqUf0AgZasoB0G/sYEzIwMTgwMzI1MjEwNTUwLjUxMVowBwIBAYACAfSggbik
# gbUwgbIxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQH
# EwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xDDAKBgNV
# BAsTA0FPQzEnMCUGA1UECxMebkNpcGhlciBEU0UgRVNOOjBERTgtMkRDNS0zQ0E5
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
# fjUeCLraNtvTX4/edIhJEjCCBNkwggPBoAMCAQICEzMAAACm/VLgixYnPwAAAAAA
# AKYwDQYJKoZIhvcNAQELBQAwfDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hp
# bmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jw
# b3JhdGlvbjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRpbWUtU3RhbXAgUENBIDIwMTAw
# HhcNMTYwOTA3MTc1NjUxWhcNMTgwOTA3MTc1NjUxWjCBsjELMAkGA1UEBhMCVVMx
# EzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoT
# FU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEMMAoGA1UECxMDQU9DMScwJQYDVQQLEx5u
# Q2lwaGVyIERTRSBFU046MERFOC0yREM1LTNDQTkxJTAjBgNVBAMTHE1pY3Jvc29m
# dCBUaW1lLVN0YW1wIFNlcnZpY2UwggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEK
# AoIBAQDBuM2eCSe0cIuF/x1aSNHA5udhcPU9qlRbwN3VssAQ665EmlyhiamvYcVT
# 9AJs/b9sy9HzkpoSoBFthTc+cd3RoO+aId3YWyaDkA8mf40eHuPjJBstMtG077fA
# zQpH2OBPNce7BDhFJmtvqOKFJrON9PezvFnwIhiY/1c0GBtO0bTv2O4qiG39/h8V
# XSmBa3Y5MMX/fSOiRHQYswg0ybnI182M71FN4PMP7zq0LdKzJfm/ZJMXVC/vyFFj
# lSWxLKNIcchnqnGH2NevyucbnaA5MsWmb2ob1Rh1lKmqeVms39uO0spJnHdBqtgw
# OWbkkXjU7Sfpl8N+WUT6LblqcQPdAgMBAAGjggEbMIIBFzAdBgNVHQ4EFgQUDuHF
# Q8kmG9zLh7vcTGbXBrzRwCYwHwYDVR0jBBgwFoAU1WM6XIoxkPNDe3xGG8UzaFqF
# bVUwVgYDVR0fBE8wTTBLoEmgR4ZFaHR0cDovL2NybC5taWNyb3NvZnQuY29tL3Br
# aS9jcmwvcHJvZHVjdHMvTWljVGltU3RhUENBXzIwMTAtMDctMDEuY3JsMFoGCCsG
# AQUFBwEBBE4wTDBKBggrBgEFBQcwAoY+aHR0cDovL3d3dy5taWNyb3NvZnQuY29t
# L3BraS9jZXJ0cy9NaWNUaW1TdGFQQ0FfMjAxMC0wNy0wMS5jcnQwDAYDVR0TAQH/
# BAIwADATBgNVHSUEDDAKBggrBgEFBQcDCDANBgkqhkiG9w0BAQsFAAOCAQEAhCAn
# oQbouNb8kjrKSNady9CWjrME2siuhF+rOqL02rViVi8KwbKPPrcfLGBadSLOR5Hf
# QXrZnpA0K6NYAw3DhsaW1bqF0eNjtBlRvWePNmXs1hkmlweM+laX/sxcGW13Bljp
# 0QuvGqsLFPdPCVDDGWuYzCHjJYbWQTfrZS3ZbGyPR/8XT72lUDajq8LcdXDhYVrv
# QRsqA9EGeV7KpkMYq1dEk4HA60KoEwXUGDicWyY23JXrM6W0cJr8vZ1vpAek3x5C
# pw87uUGxtku/hBJF2W7PWHy242sLrgAG1qSWu2cRLztQ6ZJs9ZpZyIfkr2S+VSwz
# cDYfi/Tq5pwBPaQ7L6GCA3QwggJcAgEBMIHioYG4pIG1MIGyMQswCQYDVQQGEwJV
# UzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UE
# ChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMQwwCgYDVQQLEwNBT0MxJzAlBgNVBAsT
# Hm5DaXBoZXIgRFNFIEVTTjowREU4LTJEQzUtM0NBOTElMCMGA1UEAxMcTWljcm9z
# b2Z0IFRpbWUtU3RhbXAgU2VydmljZaIlCgEBMAkGBSsOAwIaBQADFQB/oDBsfKPq
# 6vKBBNM1oufc4tSFPaCBwTCBvqSBuzCBuDELMAkGA1UEBhMCVVMxEzARBgNVBAgT
# Cldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29m
# dCBDb3Jwb3JhdGlvbjEMMAoGA1UECxMDQU9DMScwJQYDVQQLEx5uQ2lwaGVyIE5U
# UyBFU046MjY2NS00QzNGLUM1REUxKzApBgNVBAMTIk1pY3Jvc29mdCBUaW1lIFNv
# dXJjZSBNYXN0ZXIgQ2xvY2swDQYJKoZIhvcNAQEFBQACBQDeYnUkMCIYDzIwMTgw
# MzI1MTkyMTA4WhgPMjAxODAzMjYxOTIxMDhaMHQwOgYKKwYBBAGEWQoEATEsMCow
# CgIFAN5idSQCAQAwBwIBAAICNhowBwIBAAICGV4wCgIFAN5jxqQCAQAwNgYKKwYB
# BAGEWQoEAjEoMCYwDAYKKwYBBAGEWQoDAaAKMAgCAQACAxbjYKEKMAgCAQACAweh
# IDANBgkqhkiG9w0BAQUFAAOCAQEAjQa3mLiiVQ7RytCR5rHgRVsVbYk4CQ81fMzc
# tJtc4vHouTv3YSNhE2bqnYytwJsBqXIZSqmnm8AQ5SNOr6EqovIigP9D7ZiJNt7J
# eT70TqAmkkQm/xfPPCHXt6XV+eVnG2boFZBQUrBt1jt7+RkNhZVHwkGE0ngbK+t2
# ijmhoHf5Arp2pNe//aZAp7ZLal5s5jKbefLq83mln4qzGqhgZkq0mQEMQcq7hPnO
# d69YoI0vaL1Z4wiRAh5TR2eKLwPqdPd9X2X1HheHBz60h5lV4v+yjLSzDU+90lud
# tvlfcfirNXQt1vRovRyaTo0BmOhNqq0yILA7uMJ61sf0ufF71DGCAvUwggLxAgEB
# MIGTMHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQH
# EwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xJjAkBgNV
# BAMTHU1pY3Jvc29mdCBUaW1lLVN0YW1wIFBDQSAyMDEwAhMzAAAApv1S4IsWJz8A
# AAAAAACmMA0GCWCGSAFlAwQCAQUAoIIBMjAaBgkqhkiG9w0BCQMxDQYLKoZIhvcN
# AQkQAQQwLwYJKoZIhvcNAQkEMSIEIMU/AEQMa1ai5MH3mvzZ8FgJoD2oTvGq0nWz
# kFwiOILNMIHiBgsqhkiG9w0BCRACDDGB0jCBzzCBzDCBsQQUf6AwbHyj6urygQTT
# NaLn3OLUhT0wgZgwgYCkfjB8MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGlu
# Z3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBv
# cmF0aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0EgMjAxMAIT
# MwAAAKb9UuCLFic/AAAAAAAApjAWBBR6uHfwD2+xsjZTRRAKPt+asUNXHDANBgkq
# hkiG9w0BAQsFAASCAQBZpsg2fv8MgA4N/yg6a/orBKC/zJvWQvQvb0dC4Um5JjKk
# OaUVC4of3bIIfFLUR8Dc25l2gZaCnYnaRUVB+ll25orzgcXKH4/5ivrKWasdZeaB
# iIcLeAFX+3SH3ChjY4QteEwkrV2HJWph7jKAixYe+VC4XJwjE3IA/EaZoI6bZ9yM
# b87bubJqPQW6zUxGGecbRQHwQka96KaDQ4PlKYLmoZfCBogJW4j5Nk6ePgb3AmlM
# pGifDOLSgFUxiKSIl9dwOHt7mVfGf/N+iVBBg/zUhNKP1PZZWrjc0kpo9pNw5fPJ
# JAKkaEx+s2PjP5NRzs8v42eUUIc9ODusM/dnu0Ml
# SIG # End signature block
