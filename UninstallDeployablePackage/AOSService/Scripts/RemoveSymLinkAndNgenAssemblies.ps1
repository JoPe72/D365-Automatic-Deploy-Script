Import-Module WebAdministration
Import-Module "$PSScriptRoot\CommonRollbackUtilities.psm1" -DisableNameChecking

$ErrorActionPreference = "stop"

$webroot = Get-AosWebSitePhysicalPath

function RemoveSymbolicLinks([string]$webroot)
{
    Write-Output "Starting the removal of symlinks."
    $appassembliesdir=Join-Path $webroot "bin\appassemblies"

    if(!(Test-Path $appassembliesdir)){
        Write-Output "$appassembliesdir is not found"
        return
    }
    
    $allFiles=Join-Path $appassembliesdir "*"
    Remove-Item $allFiles -Force
    Remove-Item $appassembliesdir -Force 
    Write-Output "Symlinks removed."
}

function UpdateWebconfig([string]$webroot,[string]$uselazytypeloader)
{
   	Write-Output "Updating the AOS web configuration."
    $webconfig=join-path $webroot "web.config"
    $appassembliesdir="bin\appassemblies"
    [System.Xml.XmlDocument] $xd=new-object System.Xml.XmlDocument
    $xd.Load($webconfig)
    $ns=New-Object System.Xml.XmlNamespaceManager($xd.NameTable)
    $ns.AddNamespace("ns",$xd.DocumentElement.NamespaceURI)

    # add UseLazyTypeLoader setting
    $key="UseLazyTypeLoader"
    $value=$uselazytypeloader
    $existingNode = $xd.SelectSingleNode("//ns:add[@key='$key']",$ns)

    if($existingNode -ne $null){
        $existingValue=$existingNode.GetAttribute("value")
        if($existingValue -ne $value){ # update if the existing value -ne new value
    	    Write-Output "Updating configuration '$key'='$value'"
		    $existingNode.SetAttribute("value",$value)
        }
	}
    else{
		$addElement=$xd.CreateElement("add")
		$addElement.SetAttribute("key",$key)
		$addElement.SetAttribute("value",$value)
        $appSettings=$xd.SelectSingleNode("//ns:appSettings",$ns)
		Write-Output "Adding configuration '$key'='$value' to web.config"
		$appSettings.AppendChild($addElement)
	}


    # remove probing path
  
    [string]$privatepath=$xd.Configuration.RunTime.AssemblyBinding.Probing.privatePath
    [string[]] $probingpaths=$privatepath.Split(";")
    if($probingpaths.Contains($appassembliesdir)){
        Write-Output "Removing $appassembliesdir to the private probing path in web.config"
        if($privatepath.Equals("$appassembliesdir")){
            $privatepath = $privatepath.Replace("$appassembliesdir","")
        }
        else{
            $privatepath = $privatepath.Replace(";$appassembliesdir","")
        }      
        $xd.Configuration.RunTime.AssemblyBinding.Probing.privatePath=$privatepath

       
    }
    $xd.Save($webconfig)
}

function UpdateBatchConfig([string]$webroot,[string]$uselazytypeloader)
{
    Write-Output "Updating the Dynamics Batch configuration file."
    $batchconfig=join-path $webroot "bin\batch.exe.config"
    if(!(Test-Path $batchconfig)){
        Write-Log "Batch.exe.config is not found at $webroot\bin"
        return
    } 

    [System.Xml.XmlDocument] $xd=new-object System.Xml.XmlDocument
    $xd.Load($batchconfig)
    $ns=New-Object System.Xml.XmlNamespaceManager($xd.NameTable)
    $ns.AddNamespace("ns",$xd.DocumentElement.NamespaceURI)

    # add UseLazyTypeLoader setting
    $save=$false # flag to indicate if there are changes to save
    $key="UseLazyTypeLoader"
    $value=$uselazytypeloader
    $existingNode = $xd.SelectSingleNode("//ns:add[@key='$key']",$ns)

    if($existingNode -ne $null){
        $existingValue=$existingNode.GetAttribute("value")
        if($existingValue -ne $value){  # update if the existing value -ne new value
            Write-Output "Updating configuration '$key'='$value'"
            $existingNode.SetAttribute("value",$value)
        }
    }
    else{
        # add UseLazyTypeLoader key
        $addElement=$xd.CreateElement("add")
        $addElement.SetAttribute("key",$key)
        $addElement.SetAttribute("value",$value)
        $appSettings=$xd.SelectSingleNode("//ns:appSettings",$ns)
        Write-Output "Adding configuration '$key'='$value' to Batch.exe.config"
        $appSettings.AppendChild($addElement)
    }
    
    
    # remove appassemblies to the probing path
    $appassemblies="appassemblies"
    $probingelement=$xd.Configuration.RunTime.AssemblyBinding.Probing
    if($probingelement -ne $null){
        [string]$privatepath=$xd.Configuration.RunTime.AssemblyBinding.Probing.privatePath
        [string[]] $probingpaths=$privatepath.Split(";")
        if($probingpaths.Contains($appassemblies)){
            Write-Output "Removinging $appassemblies to the private probing path in Batch.exe.config"
            $privatepath = $privatepath.Replace("$appassemblies","")
            try
            {
                $xd.Configuration.RunTime.AssemblyBinding.Probing.privatePath=$privatepath
            }
            catch
            {
                Write-Output "no private probing path found in batch.exe.config"
            }
        }
    }
    else{
        # remove probing element
        $assemblyBinding=$xd.Configuration.RunTime.AssemblyBinding
        $xmlns=$assemblyBinding.xmlns
        $probingElement=$xd.CreateElement("probing")
        $probingElement.SetAttribute("privatePath",$appassemblies)
        $probingElement.SetAttribute("xmlns",$xmlns)
        Write-Output "Removing private probing path to the batch.exe.config"
        try
        {
            $assemblyBinding.RemoveChild($probingelement)
        }
        catch
        {
            Write-Output "no private probing path found in batch.exe.config"
        }
    }

    
    $xd.Save($batchconfig)
    
}

RemoveSymbolicLinks -webroot:$webroot
UpdateWebconfig -webroot:$webroot -uselazytypeloader:"true"
UpdateBatchConfig -webroot:$webroot -uselazytypeloader:"true"

# SIG # Begin signature block
# MIIkFwYJKoZIhvcNAQcCoIIkCDCCJAQCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCC7bbquUCGfc+xf
# 88UfXKepgtlJTUBMIWEAHUp8TEYMNaCCDYIwggYAMIID6KADAgECAhMzAAAAww6b
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
# SEXAQsmbdlsKgEhr/Xmfwb1tbWrJUnMTDXpQzTGCFeswghXnAgEBMIGVMH4xCzAJ
# BgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25k
# MR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xKDAmBgNVBAMTH01pY3Jv
# c29mdCBDb2RlIFNpZ25pbmcgUENBIDIwMTECEzMAAADDDpun2LLc9ywAAAAAAMMw
# DQYJYIZIAWUDBAIBBQCggeAwGQYJKoZIhvcNAQkDMQwGCisGAQQBgjcCAQQwHAYK
# KwYBBAGCNwIBCzEOMAwGCisGAQQBgjcCARUwLwYJKoZIhvcNAQkEMSIEIKLZO+eZ
# PwVqBLIyXaUCQuA0C0qdXolZQC86xLWPAQMEMHQGCisGAQQBgjcCAQwxZjBkoEaA
# RABSAGUAbQBvAHYAZQBTAHkAbQBMAGkAbgBrAEEAbgBkAE4AZwBlAG4AQQBzAHMA
# ZQBtAGIAbABpAGUAcwAuAHAAcwAxoRqAGGh0dHA6Ly93d3cubWljcm9zb2Z0LmNv
# bTANBgkqhkiG9w0BAQEFAASCAQA1RfTPTPNMXnwsH/cDQ7TAwPE8j4DwkOcCeQKs
# /hzDkEnydzIt/CZKO9MOeE5o/OFjP9y9/1cS/Dl7s51t2X1lV5t0mSpHIm5i1K31
# uN+3OoljCjZaZVN4q13i6UtP5h+SiwbEZBZZ/DQn7CowxhTfL7szSYju2ofK1on9
# 6rrSxT/pV/+rTELcSdsQpkJcqUB2ehR5ecIs5XCnLmM83jaDA4bcTiwJ/SmXCFNu
# bY3AR5TxYixLyvHTSRNgjv/lrZ/Nhf433iNDI9hqpeEI/wfVsIB5n6+4Wm2yi6tu
# C+EZJb4izCCPWyB9wfGNKdF1+OrXfnKd+Yyzaz4rxI6dKsQuoYITQzCCEz8GCisG
# AQQBgjcDAwExghMvMIITKwYJKoZIhvcNAQcCoIITHDCCExgCAQMxDzANBglghkgB
# ZQMEAgEFADCCATsGCyqGSIb3DQEJEAEEoIIBKgSCASYwggEiAgEBBgorBgEEAYRZ
# CgMBMDEwDQYJYIZIAWUDBAIBBQAEIDm64+inB6Ds7THt9OSgEY+O4lUUtAaaZ5Xj
# QwzzywuNAgZasqXNVPYYEzIwMTgwMzI1MjEwNTU3LjAwM1owBwIBAYACAfSggbek
# gbQwgbExCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQH
# EwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xDDAKBgNV
# BAsTA0FPQzEmMCQGA1UECxMdVGhhbGVzIFRTUyBFU046QzNCMC0wRjZBLTQxMTEx
# JTAjBgNVBAMTHE1pY3Jvc29mdCBUaW1lLVN0YW1wIFNlcnZpY2Wggg7IMIIGcTCC
# BFmgAwIBAgIKYQmBKgAAAAAAAjANBgkqhkiG9w0BAQsFADCBiDELMAkGA1UEBhMC
# VVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNV
# BAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEyMDAGA1UEAxMpTWljcm9zb2Z0IFJv
# b3QgQ2VydGlmaWNhdGUgQXV0aG9yaXR5IDIwMTAwHhcNMTAwNzAxMjEzNjU1WhcN
# MjUwNzAxMjE0NjU1WjB8MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3Rv
# bjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0
# aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0EgMjAxMDCCASIw
# DQYJKoZIhvcNAQEBBQADggEPADCCAQoCggEBAKkdDbx3EYo6IOz8E5f1+n9plGt0
# VBDVpQoAgoX77XxoSyxfxcPlYcJ2tz5mK1vwFVMnBDEfQRsalR3OCROOfGEwWbEw
# RA/xYIiEVEMM1024OAizQt2TrNZzMFcmgqNFDdDq9UeBzb8kYDJYYEbyWEeGMoQe
# dGFnkV+BVLHPk0ySwcSmXdFhE24oxhr5hoC732H8RsEnHSRnEnIaIYqvS2SJUGKx
# Xf13Hz3wV3WsvYpCTUBR0Q+cBj5nf/VmwAOWRH7v0Ev9buWayrGo8noqCjHw2k4G
# kbaICDXoeByw6ZnNPOcvRLqn9NxkvaQBwSAJk3jN/LzAyURdXhacAQVPIk0CAwEA
# AaOCAeYwggHiMBAGCSsGAQQBgjcVAQQDAgEAMB0GA1UdDgQWBBTVYzpcijGQ80N7
# fEYbxTNoWoVtVTAZBgkrBgEEAYI3FAIEDB4KAFMAdQBiAEMAQTALBgNVHQ8EBAMC
# AYYwDwYDVR0TAQH/BAUwAwEB/zAfBgNVHSMEGDAWgBTV9lbLj+iiXGJo0T2UkFvX
# zpoYxDBWBgNVHR8ETzBNMEugSaBHhkVodHRwOi8vY3JsLm1pY3Jvc29mdC5jb20v
# cGtpL2NybC9wcm9kdWN0cy9NaWNSb29DZXJBdXRfMjAxMC0wNi0yMy5jcmwwWgYI
# KwYBBQUHAQEETjBMMEoGCCsGAQUFBzAChj5odHRwOi8vd3d3Lm1pY3Jvc29mdC5j
# b20vcGtpL2NlcnRzL01pY1Jvb0NlckF1dF8yMDEwLTA2LTIzLmNydDCBoAYDVR0g
# AQH/BIGVMIGSMIGPBgkrBgEEAYI3LgMwgYEwPQYIKwYBBQUHAgEWMWh0dHA6Ly93
# d3cubWljcm9zb2Z0LmNvbS9QS0kvZG9jcy9DUFMvZGVmYXVsdC5odG0wQAYIKwYB
# BQUHAgIwNB4yIB0ATABlAGcAYQBsAF8AUABvAGwAaQBjAHkAXwBTAHQAYQB0AGUA
# bQBlAG4AdAAuIB0wDQYJKoZIhvcNAQELBQADggIBAAfmiFEN4sbgmD+BcQM9naOh
# IW+z66bM9TG+zwXiqf76V20ZMLPCxWbJat/15/B4vceoniXj+bzta1RXCCtRgkQS
# +7lTjMz0YBKKdsxAQEGb3FwX/1z5Xhc1mCRWS3TvQhDIr79/xn/yN31aPxzymXlK
# kVIArzgPF/UveYFl2am1a+THzvbKegBvSzBEJCI8z+0DpZaPWSm8tv0E4XCfMkon
# /VWvL/625Y4zu2JfmttXQOnxzplmkIz/amJ/3cVKC5Em4jnsGUpxY517IW3DnKOi
# PPp/fZZqkHimbdLhnPkd/DjYlPTGpQqWhqS9nhquBEKDuLWAmyI4ILUl5WTs9/S/
# fmNZJQ96LjlXdqJxqgaKD4kWumGnEcua2A5HmoDF0M2n0O99g/DhO3EJ3110mCII
# YdqwUB5vvfHhAN/nMQekkzr3ZUd46PioSKv33nJ+YWtvd6mBy6cJrDm77MbL2IK0
# cs0d9LiFAR6A+xuJKlQ5slvayA1VmXqHczsI5pgt6o3gMy4SKfXAL1QnIffIrE7a
# KLixqduWsqdCosnPGUFN4Ib5KpqjEWYw07t0MkvfY3v1mYovG8chr1m1rtxEPJdQ
# cdeh0sVV42neV8HR3jDA/czmTfsNv11P6Z0eGTgvvM9YBS7vDaBQNdrvCScc1bN+
# NR4Iuto229Nfj950iEkSMIIE2DCCA8CgAwIBAgITMwAAAK2AIzdlxFojagAAAAAA
# rTANBgkqhkiG9w0BAQsFADB8MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGlu
# Z3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBv
# cmF0aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0EgMjAxMDAe
# Fw0xNjA5MDcxNzU2NTVaFw0xODA5MDcxNzU2NTVaMIGxMQswCQYDVQQGEwJVUzET
# MBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMV
# TWljcm9zb2Z0IENvcnBvcmF0aW9uMQwwCgYDVQQLEwNBT0MxJjAkBgNVBAsTHVRo
# YWxlcyBUU1MgRVNOOkMzQjAtMEY2QS00MTExMSUwIwYDVQQDExxNaWNyb3NvZnQg
# VGltZS1TdGFtcCBTZXJ2aWNlMIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKC
# AQEA7bMN/mUa3Y2xVe9HKb4oVOMVAsHLOrZaHp6MA3HM20qs541Uv16h+jUBFCL8
# XJPvR5qXuOpq79Hqp6oluUdc5slr07QHmgby57I0yIsYe9h1tXhpRQzXUiKMsRAS
# qbsmWj6/RlIaOWFIC5RaeKJuqShccUGtPoNWgyQsodWp8MW+b9z27xJWpzLr6cvH
# qSR+UZt5+gdrtyYKAzCsqLYzukStGjeDl1crhJBoNMGAfx5RYMnVfjYKsqn5PrR+
# t96E95vxT6gmCOYYpioCWXHMwZf4KWJ519bOTXbP/8EVAeaTmGCR02oFiSwgAYfc
# ED06y3asg50QCfyHDZyuXJn9pwIDAQABo4IBGzCCARcwHQYDVR0OBBYEFGQhusAv
# rPicxwyU5ecfyQrWvP1rMB8GA1UdIwQYMBaAFNVjOlyKMZDzQ3t8RhvFM2hahW1V
# MFYGA1UdHwRPME0wS6BJoEeGRWh0dHA6Ly9jcmwubWljcm9zb2Z0LmNvbS9wa2kv
# Y3JsL3Byb2R1Y3RzL01pY1RpbVN0YVBDQV8yMDEwLTA3LTAxLmNybDBaBggrBgEF
# BQcBAQROMEwwSgYIKwYBBQUHMAKGPmh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9w
# a2kvY2VydHMvTWljVGltU3RhUENBXzIwMTAtMDctMDEuY3J0MAwGA1UdEwEB/wQC
# MAAwEwYDVR0lBAwwCgYIKwYBBQUHAwgwDQYJKoZIhvcNAQELBQADggEBABKFR7nU
# nZjEfGRutaq4TVOKIobcdpV1XSKPN3U8XvalbzqNGX+76pQ0/iCmalQ2TzRU/wAD
# lVQm83ln7/HAGPrptzDtd/9pdNozhBEOk6+BGMclWriF1mChtGtbM6P+tIYYJNgh
# lVvukBXG2WPu1KTY+eR63Uuyc6wWuaDABBbvNXU7UDz5YXbcAegLH2ZQGt2qWU9M
# g9jFhwRCIneoyvdNpa4akcXHHSB8IVh1U69PJbrizLhwcONaYV1crONr/IzTrDg/
# Yj8mYMN5ppV1/I/85i0slH0C0Rvuw3+kwdmkRiI3169/mLpe93eTXasLrxRQTulm
# QS856oTjF3n5XFShggNzMIICWwIBATCB4aGBt6SBtDCBsTELMAkGA1UEBhMCVVMx
# EzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoT
# FU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEMMAoGA1UECxMDQU9DMSYwJAYDVQQLEx1U
# aGFsZXMgVFNTIEVTTjpDM0IwLTBGNkEtNDExMTElMCMGA1UEAxMcTWljcm9zb2Z0
# IFRpbWUtU3RhbXAgU2VydmljZaIlCgEBMAkGBSsOAwIaBQADFQCcGOYa3xsDiBdd
# HMbHLEuar+Ew2aCBwTCBvqSBuzCBuDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldh
# c2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBD
# b3Jwb3JhdGlvbjEMMAoGA1UECxMDQU9DMScwJQYDVQQLEx5uQ2lwaGVyIE5UUyBF
# U046MjY2NS00QzNGLUM1REUxKzApBgNVBAMTIk1pY3Jvc29mdCBUaW1lIFNvdXJj
# ZSBNYXN0ZXIgQ2xvY2swDQYJKoZIhvcNAQEFBQACBQDeYnUZMCIYDzIwMTgwMzI1
# MTkyMDU3WhgPMjAxODAzMjYxOTIwNTdaMHQwOgYKKwYBBAGEWQoEATEsMCowCgIF
# AN5idRkCAQAwBwIBAAICWGkwBwIBAAICFmcwCgIFAN5jxpkCAQAwNgYKKwYBBAGE
# WQoEAjEoMCYwDAYKKwYBBAGEWQoDAaAKMAgCAQACAxbjYKEKMAgCAQACAx6EgDAN
# BgkqhkiG9w0BAQUFAAOCAQEAeAV1PYDmLO3kdkKjiPEokiPPj28jgVxw+Fhws+9I
# Z8aA88ZDkJtsLmHb2jfNLY5W78GWv8+xg9vZZZVhj8TmOgI+Xuoj1RWRiGJaFunK
# hWYndOdoyzHdiwmKG7McTj4oPWfdpZsq2LlFhj8wu9DMON1CXIUzCdJi0G4DFlj1
# 8qtPZNho2YBsvYJX9C7cyUFGKCqv2rB3qM/yGDoFPIx2bzT7QyWp6TIHnI4oDPn2
# LhgUbMuxwIDE3OeRHf3QHvxjVM9hIrQlLH76IUnyVAOJTlhmrpczB6kNPH9dV/3S
# 2ShE5UBTsSx7eXhL0DbGrKw2Jj1Ydo64DTBo6aRHsBCKejGCAvUwggLxAgEBMIGT
# MHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdS
# ZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xJjAkBgNVBAMT
# HU1pY3Jvc29mdCBUaW1lLVN0YW1wIFBDQSAyMDEwAhMzAAAArYAjN2XEWiNqAAAA
# AACtMA0GCWCGSAFlAwQCAQUAoIIBMjAaBgkqhkiG9w0BCQMxDQYLKoZIhvcNAQkQ
# AQQwLwYJKoZIhvcNAQkEMSIEIP0zmFd+AFj1cJApEuruec7iMP66q9iyZJE4MIFh
# vikLMIHiBgsqhkiG9w0BCRACDDGB0jCBzzCBzDCBsQQUnBjmGt8bA4gXXRzGxyxL
# mq/hMNkwgZgwgYCkfjB8MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3Rv
# bjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0
# aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0EgMjAxMAITMwAA
# AK2AIzdlxFojagAAAAAArTAWBBSx5e9P/kA7wsjbft2sUpek1mrrUjANBgkqhkiG
# 9w0BAQsFAASCAQDKCNebGuBKmjZc2OZ9s4tPp77rUiJeLFelNznnvz5fVg5FIbbw
# JdxN84KvYaGw3LJNoNsZUqRQ2AoyhrNzDifB9uUqPIpzb7TplQwp0d6QRyPz6t3F
# 6dXTD7LX1qiNTXclnvmpbTRK/JMwmTzyVMvUb2j54c3eJPuo8Ci6bBXyZds3W6KI
# EAMbJCNk3PnT7fMbw1ajddlB0YBdPFtRFIPg1vThzZ+FNIBmycFXduXnIjmHSH4c
# 9YMPiav0Za5PKNkcDd+djbVQmfF64HMXQZitGLkLCERD7PkTURBwgv89izpCyTQq
# oSv+nP+xBOMi4R8kqZ6RNBcxUCvuQsyyi/98
# SIG # End signature block
