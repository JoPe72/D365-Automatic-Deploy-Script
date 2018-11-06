function Initialize-Log($log)
{	
    if ($log -ne $null)
    {        
        $Global:GlobalLogFile = $log
        if(!(Test-Path $Global:GlobalLogFile))
        {
            New-Item -Path $Global:GlobalLogFile -ItemType File -Force | Out-Null
        }
    }    	
}


function Write-Log($message)
{    
    $log = $Global:GlobalLogFile
    if (![System.String]::IsNullOrWhiteSpace($log)) { Add-content "$log" ("`n[{0}]: {1}`n" -f (Get-Date), $message) }
}

function Write-Exception($Exception)
{
    Write-Log "$($Exception.Exception) : $($Exception.InvocationInfo.PositionMessage)"
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
                Write-Exception $exception                
                Write-Log "Sleeping 30s before retrying"
                Sleep $sleepTime
            }
            else
            {
                $message = "Max retry count reached during $blockMessage`: "
                Write-Log $message
                Write-Exception $exception
                throw $exception
            }
        }
    }
    $retry++
    Write-Log "$blockMessage`: Completed execution in $retry iterations"
}

function Decode-Settings($config)
{
    $settings = @{}
    if ($config -ne $null)
    {
        $decodedConfig = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($config))
        $settings = ConvertFrom-Json $decodedConfig
    }

    return $settings
}

function Construct-PrivateAosInstanceUrl($PublicUrl)
{
    $publicUrlSegments = $PublicUrl.Split('.')
    $publicUrlSegments[0] += "private"
    $privateUrl = $publicUrlSegments -join "."
    return $privateUrl
}

function SqlTableExists($TableName, $Server, $Database, $Login, $Password)
{
    $TableExistsQuery = "if exists(select * from INFORMATION_SCHEMA.TABLES where table_name = '$TableName' and table_schema = 'dbo') select 1 as result else select 0 as result"
    $connectionString = "Server='{0}';Database='{1}';Trusted_Connection=false;UID='{2}';Pwd='{3}';" -f $Server,$Database,$Login,$Password
    $connection = new-object system.data.SqlClient.SQLConnection($connectionString)
    $command = new-object system.data.sqlclient.sqlcommand($TableExistsQuery,$connection)
    $command.CommandTimeout = 15    
    $connection.Open()
    $queryResult = $command.ExecuteScalar()

    $result = $false   
    if ($queryResult -eq 0)
    {      
        $result = $false        
    }
    else
    {
        $result = $true
    }

    $connection.Close()

    return $result
}

function StopAndDisableService($ServiceName)
{
    if (Get-Service $ServiceName)
    {
        $timeout = new-timespan -Minutes 5
        $serviceProcessStarting = $true;
        $sw = [diagnostics.stopwatch]::StartNew()
        while ($sw.elapsed -lt $timeout -and $serviceProcessStarting)
        {
            if ((Get-Service $ServiceName | where status -ne 'Running' ) -and (Get-Service $ServiceName | where status -ne 'Stopped' ))
            {
                start-sleep -seconds 60 
            }
            else
            {
                $serviceProcessStarting = $false;
            }
        }
        if($serviceProcessStarting)
        {
            throw "Unable to execute the $ServiceName shutdown script because the  process is not in a state where operation can be performed."
        }

        Set-Service $ServiceName -startupType Disabled
        Stop-Service $ServiceName
        Write-Output "$ServiceName stopped."
    }
}
# SIG # Begin signature block
# MIIj8gYJKoZIhvcNAQcCoIIj4zCCI98CAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCD/DDuK8q/VHcuE
# uh3ma/ahDJJufBtQRlMk/bALkxMyXKCCDYIwggYAMIID6KADAgECAhMzAAAAww6b
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
# SEXAQsmbdlsKgEhr/Xmfwb1tbWrJUnMTDXpQzTGCFcYwghXCAgEBMIGVMH4xCzAJ
# BgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25k
# MR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xKDAmBgNVBAMTH01pY3Jv
# c29mdCBDb2RlIFNpZ25pbmcgUENBIDIwMTECEzMAAADDDpun2LLc9ywAAAAAAMMw
# DQYJYIZIAWUDBAIBBQCggbgwGQYJKoZIhvcNAQkDMQwGCisGAQQBgjcCAQQwHAYK
# KwYBBAGCNwIBCzEOMAwGCisGAQQBgjcCARUwLwYJKoZIhvcNAQkEMSIEIOnboAY5
# VyTzUP4LiT88PagzdxS0EefpOEWd94kpVjlwMEwGCisGAQQBgjcCAQwxPjA8oB6A
# HABBAG8AcwBDAG8AbQBtAG8AbgAuAHAAcwBtADGhGoAYaHR0cDovL3d3dy5taWNy
# b3NvZnQuY29tMA0GCSqGSIb3DQEBAQUABIIBAGfhGon13+m5Js92wxIul2g28ZNc
# VVvcX316tbqOQZhRcwH17tpzLxWdVtvEhT3cnOnEYerbc6Y/5aYMBs7RhhGXssfn
# I6Z6zowVr7+NWSntw9Bugtp3Ra8I6oWRXr2rufzzccPaJQKrpWwcxKaaEB11DI0R
# bS7W4YZ6N5+GIOc6AMKvtFI2zBdJSZkZSotXl8AQzzUjtVOw2JWZpliDdUGTNtQW
# S/zcKTzl/N6revUD8tO/LZMp5npl95hIFXXwCQ1o6qiA087EGB5/xWD/AUzBZZPl
# +JsX/TE8grF6l+FHnwWXNggBImtG4Zl3ECW8oaXQyi3wJ2XTNNrvZF+rxqyhghNG
# MIITQgYKKwYBBAGCNwMDATGCEzIwghMuBgkqhkiG9w0BBwKgghMfMIITGwIBAzEP
# MA0GCWCGSAFlAwQCAQUAMIIBOwYLKoZIhvcNAQkQAQSgggEqBIIBJjCCASICAQEG
# CisGAQQBhFkKAwEwMTANBglghkgBZQMEAgEFAAQgyvP0lR0DMgA06gBHNVvc5s9Y
# dURtW5R/AZtBpVH+TtACBlqyr2CzCRgTMjAxODAzMjUyMTA1NTEuMzI5WjAHAgEB
# gAIB9KCBt6SBtDCBsTELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24x
# EDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlv
# bjEMMAoGA1UECxMDQU9DMSYwJAYDVQQLEx1UaGFsZXMgVFNTIEVTTjo5NkZGLTRC
# QzUtQTdEQzElMCMGA1UEAxMcTWljcm9zb2Z0IFRpbWUtU3RhbXAgU2VydmljZaCC
# DsswggZxMIIEWaADAgECAgphCYEqAAAAAAACMA0GCSqGSIb3DQEBCwUAMIGIMQsw
# CQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9u
# ZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMTIwMAYDVQQDEylNaWNy
# b3NvZnQgUm9vdCBDZXJ0aWZpY2F0ZSBBdXRob3JpdHkgMjAxMDAeFw0xMDA3MDEy
# MTM2NTVaFw0yNTA3MDEyMTQ2NTVaMHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpX
# YXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQg
# Q29ycG9yYXRpb24xJjAkBgNVBAMTHU1pY3Jvc29mdCBUaW1lLVN0YW1wIFBDQSAy
# MDEwMIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAqR0NvHcRijog7PwT
# l/X6f2mUa3RUENWlCgCChfvtfGhLLF/Fw+Vhwna3PmYrW/AVUycEMR9BGxqVHc4J
# E458YTBZsTBED/FgiIRUQwzXTbg4CLNC3ZOs1nMwVyaCo0UN0Or1R4HNvyRgMlhg
# RvJYR4YyhB50YWeRX4FUsc+TTJLBxKZd0WETbijGGvmGgLvfYfxGwScdJGcSchoh
# iq9LZIlQYrFd/XcfPfBXday9ikJNQFHRD5wGPmd/9WbAA5ZEfu/QS/1u5ZrKsajy
# eioKMfDaTgaRtogINeh4HLDpmc085y9Euqf03GS9pAHBIAmTeM38vMDJRF1eFpwB
# BU8iTQIDAQABo4IB5jCCAeIwEAYJKwYBBAGCNxUBBAMCAQAwHQYDVR0OBBYEFNVj
# OlyKMZDzQ3t8RhvFM2hahW1VMBkGCSsGAQQBgjcUAgQMHgoAUwB1AGIAQwBBMAsG
# A1UdDwQEAwIBhjAPBgNVHRMBAf8EBTADAQH/MB8GA1UdIwQYMBaAFNX2VsuP6KJc
# YmjRPZSQW9fOmhjEMFYGA1UdHwRPME0wS6BJoEeGRWh0dHA6Ly9jcmwubWljcm9z
# b2Z0LmNvbS9wa2kvY3JsL3Byb2R1Y3RzL01pY1Jvb0NlckF1dF8yMDEwLTA2LTIz
# LmNybDBaBggrBgEFBQcBAQROMEwwSgYIKwYBBQUHMAKGPmh0dHA6Ly93d3cubWlj
# cm9zb2Z0LmNvbS9wa2kvY2VydHMvTWljUm9vQ2VyQXV0XzIwMTAtMDYtMjMuY3J0
# MIGgBgNVHSABAf8EgZUwgZIwgY8GCSsGAQQBgjcuAzCBgTA9BggrBgEFBQcCARYx
# aHR0cDovL3d3dy5taWNyb3NvZnQuY29tL1BLSS9kb2NzL0NQUy9kZWZhdWx0Lmh0
# bTBABggrBgEFBQcCAjA0HjIgHQBMAGUAZwBhAGwAXwBQAG8AbABpAGMAeQBfAFMA
# dABhAHQAZQBtAGUAbgB0AC4gHTANBgkqhkiG9w0BAQsFAAOCAgEAB+aIUQ3ixuCY
# P4FxAz2do6Ehb7Prpsz1Mb7PBeKp/vpXbRkws8LFZslq3/Xn8Hi9x6ieJeP5vO1r
# VFcIK1GCRBL7uVOMzPRgEop2zEBAQZvcXBf/XPleFzWYJFZLdO9CEMivv3/Gf/I3
# fVo/HPKZeUqRUgCvOA8X9S95gWXZqbVr5MfO9sp6AG9LMEQkIjzP7QOllo9ZKby2
# /QThcJ8ySif9Va8v/rbljjO7Yl+a21dA6fHOmWaQjP9qYn/dxUoLkSbiOewZSnFj
# nXshbcOco6I8+n99lmqQeKZt0uGc+R38ONiU9MalCpaGpL2eGq4EQoO4tYCbIjgg
# tSXlZOz39L9+Y1klD3ouOVd2onGqBooPiRa6YacRy5rYDkeagMXQzafQ732D8OE7
# cQnfXXSYIghh2rBQHm+98eEA3+cxB6STOvdlR3jo+KhIq/fecn5ha293qYHLpwms
# ObvsxsvYgrRyzR30uIUBHoD7G4kqVDmyW9rIDVWZeodzOwjmmC3qjeAzLhIp9cAv
# VCch98isTtoouLGp25ayp0Kiyc8ZQU3ghvkqmqMRZjDTu3QyS99je/WZii8bxyGv
# WbWu3EQ8l1Bx16HSxVXjad5XwdHeMMD9zOZN+w2/XU/pnR4ZOC+8z1gFLu8NoFA1
# 2u8JJxzVs341Hgi62jbb01+P3nSISRIwggTYMIIDwKADAgECAhMzAAAAtotHQ7LM
# rR8EAAAAAAC2MA0GCSqGSIb3DQEBCwUAMHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQI
# EwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3Nv
# ZnQgQ29ycG9yYXRpb24xJjAkBgNVBAMTHU1pY3Jvc29mdCBUaW1lLVN0YW1wIFBD
# QSAyMDEwMB4XDTE3MTAwMjIzMDA1MloXDTE5MDEwMjIzMDA1MlowgbExCzAJBgNV
# BAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4w
# HAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xDDAKBgNVBAsTA0FPQzEmMCQG
# A1UECxMdVGhhbGVzIFRTUyBFU046OTZGRi00QkM1LUE3REMxJTAjBgNVBAMTHE1p
# Y3Jvc29mdCBUaW1lLVN0YW1wIFNlcnZpY2UwggEiMA0GCSqGSIb3DQEBAQUAA4IB
# DwAwggEKAoIBAQDYiWcXSEsIt0QbkxHDOs9uQUCmqFxiY7JbI0QzNfWe3f3AcsuL
# SWwweyEAZZKWKUSnDHtTP1lOIHuWbrJYEO+uPRGHfDVmKm+1/K/QwkpyrT/OEOPX
# EAnF5RLjX85g6Nv4akltPyWgaVGno9Ys/EPhQglKND1USEokv3zh3aZnC95ssVK4
# x8jSEZsmdP6cd2AaZmMsDD/YAQTfvnkzCsnqP7ulFHY1hxLZd10yFvHu8vdtYF0o
# fSdmaR1JF+SV7fgO/rhnm/+8uu0d16TwewmwKARqSnMRJNXzyjUTbFbFxhxw1hO1
# s0YGtCyqSUTnmJUPFbvTpS15CAGAHw2mTMExAgMBAAGjggEbMIIBFzAdBgNVHQ4E
# FgQU823CkAEnINqPMxzAX2hq34EDhdAwHwYDVR0jBBgwFoAU1WM6XIoxkPNDe3xG
# G8UzaFqFbVUwVgYDVR0fBE8wTTBLoEmgR4ZFaHR0cDovL2NybC5taWNyb3NvZnQu
# Y29tL3BraS9jcmwvcHJvZHVjdHMvTWljVGltU3RhUENBXzIwMTAtMDctMDEuY3Js
# MFoGCCsGAQUFBwEBBE4wTDBKBggrBgEFBQcwAoY+aHR0cDovL3d3dy5taWNyb3Nv
# ZnQuY29tL3BraS9jZXJ0cy9NaWNUaW1TdGFQQ0FfMjAxMC0wNy0wMS5jcnQwDAYD
# VR0TAQH/BAIwADATBgNVHSUEDDAKBggrBgEFBQcDCDANBgkqhkiG9w0BAQsFAAOC
# AQEAL9fV6r6YjngcusMqQ6RNTMxlMyhHFeU6lt4W5dc6uz08KkDGIyK4QNnY/FFk
# UhE4g8bvSvnCCCmZgS6WhWUynEXg7KgdhpprKd24sQT/t9/5SijbEPASLMyX+dm0
# qihiyLAqg+ul9dDoCuHqUkLNrEQHKRnuXjGWP/h1t+XY7kR8zI/ZRwzWwOjrEI8f
# yo2wXh+ojmp7qzbk9fMzDHXfKS9kyJ7d230GwxnWNJNpDwdaS6BUlcAeeU2RaiiX
# p9VGVHSbuWn1HgM6nGY6t2jrzCfCA4sa6EEFhWGSSZKSAflzZPmtDP7d3dK/H2K+
# utKHVxJTQAeE20zDrlq3tqxkSKGCA3YwggJeAgEBMIHhoYG3pIG0MIGxMQswCQYD
# VQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEe
# MBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMQwwCgYDVQQLEwNBT0MxJjAk
# BgNVBAsTHVRoYWxlcyBUU1MgRVNOOjk2RkYtNEJDNS1BN0RDMSUwIwYDVQQDExxN
# aWNyb3NvZnQgVGltZS1TdGFtcCBTZXJ2aWNloiUKAQEwCQYFKw4DAhoFAAMVAP8W
# K+8VXLPVtZYrvghLIfxNdAABoIHBMIG+pIG7MIG4MQswCQYDVQQGEwJVUzETMBEG
# A1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWlj
# cm9zb2Z0IENvcnBvcmF0aW9uMQwwCgYDVQQLEwNBT0MxJzAlBgNVBAsTHm5DaXBo
# ZXIgTlRTIEVTTjoyNjY1LTRDM0YtQzVERTErMCkGA1UEAxMiTWljcm9zb2Z0IFRp
# bWUgU291cmNlIE1hc3RlciBDbG9jazANBgkqhkiG9w0BAQUFAAIFAN5h0j0wIhgP
# MjAxODAzMjUwNzQ2MDVaGA8yMDE4MDMyNjA3NDYwNVowdzA9BgorBgEEAYRZCgQB
# MS8wLTAKAgUA3mHSPQIBADAKAgEAAgIIPAIB/zAHAgEAAgIWGDAKAgUA3mMjvQIB
# ADA2BgorBgEEAYRZCgQCMSgwJjAMBgorBgEEAYRZCgMBoAowCAIBAAIDFuNgoQow
# CAIBAAIDHoSAMA0GCSqGSIb3DQEBBQUAA4IBAQCHtFTNf9VhmeusIlsKCXap17EC
# zsDZAGUziqqRni2DlqEhz6JSehyScH/5BSXctjxvLg5N2m1FXJge0GUbWnmvQqcn
# BJxUHlPlrD0ncnY1IQWPUdu+DvmFHOblJ2PcuQxU0Ez65WIiC9iEvoG2wXrrDtUE
# oNUlM+iZpMJFc9IcDrSAppw1jBARsK0T+ut4fvlVmBG0mqzBXbfNeimS9gnJoABh
# VqmGnQF1V0aKOIxfUxp+ffNx35TOgEqvmIDFuQbmYYykdynT6Ly7gd2IbdnIlvNF
# bByQZEhgID+1+EHvE7+HHKnQDowdTqXjnz9k2uv5IxTUid+BK7CrmXDbW5uxMYIC
# 9TCCAvECAQEwgZMwfDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24x
# EDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlv
# bjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRpbWUtU3RhbXAgUENBIDIwMTACEzMAAAC2
# i0dDssytHwQAAAAAALYwDQYJYIZIAWUDBAIBBQCgggEyMBoGCSqGSIb3DQEJAzEN
# BgsqhkiG9w0BCRABBDAvBgkqhkiG9w0BCQQxIgQgby0EsIvM++TMen6d2dfYsbdI
# dNcrCI0t5E3PPGFiMQ4wgeIGCyqGSIb3DQEJEAIMMYHSMIHPMIHMMIGxBBT/Fivv
# FVyz1bWWK74ISyH8TXQAATCBmDCBgKR+MHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQI
# EwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3Nv
# ZnQgQ29ycG9yYXRpb24xJjAkBgNVBAMTHU1pY3Jvc29mdCBUaW1lLVN0YW1wIFBD
# QSAyMDEwAhMzAAAAtotHQ7LMrR8EAAAAAAC2MBYEFC4W+BaZMMSYWdHzB63rgBi4
# Ysh7MA0GCSqGSIb3DQEBCwUABIIBAFa8FCrTa7xxV3T09igV5sLUOIa/V2UHUwYH
# uh3tFI7oS/zGDzLgJ0KXatGU13z+UGacRw32otJP6/gIi4u3WFQ0OpyVVeN8otbj
# 4/PNXDQDGN18J7bNjGo60tzgy0OBse2l8QDRu3ms9T9Oa0VLzLHZ+zkaQH/AQ+fd
# ZKRgoPirnCPRu77DVYou5jut6IrYxrTwLgRtdBr5t6gyB6osuXIKH4SO0qgF6MO2
# aygZDJSO5EJozNKYeZb10NoIb6hvhZGlNE45XxJXwYeBsU+TdBKkD3uEOYSDgB8+
# 3hrkpBJLswv5dkj6mHhZ+BPgz6AN/n4uuTxSYwKgV89gazsrVwE=
# SIG # End signature block
