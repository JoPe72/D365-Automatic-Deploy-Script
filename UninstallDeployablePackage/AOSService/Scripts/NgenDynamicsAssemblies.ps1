 param
(
    [Parameter(Mandatory=$true)]
    $config,
    [Parameter(Mandatory=$true)]
    $log
)

Import-Module "$PSScriptRoot\AosCommon.psm1" -Force -DisableNameChecking
Initialize-Log $log

Write-Log "Decoding settings"
$settings = Decode-Settings $config

function Run-Process($cmd, $arguments, [switch]$throwonerror){
    $process=New-Object System.Diagnostics.Process
    $process.StartInfo = New-Object System.Diagnostics.ProcessStartInfo
    $process.StartInfo.FileName=$cmd
    $process.StartInfo.Arguments=$arguments
    $process.StartInfo.UseShellExecute=$false
    $process.StartInfo.CreateNoWindow = $true
    $process.StartInfo.RedirectStandardError=$true
    $process.StartInfo.RedirectStandardOutput=$true
    Write-Log "Running: $cmd with arguments: $arguments"

    Write-Debug "Register ErrorDataReceived event on process"
    $action = { $errors += $Event.SourceEventArgs.Data }
    Register-ObjectEvent -InputObject $process -EventName ErrorDataReceived -Action $action | Out-Null
    $process.Start() | Out-Null
    $process.BeginErrorReadLine()  
    if ($process.StandardOutput -ne $null) { $ngenoutput = $process.StandardOutput.ReadToEnd() }
    $process.WaitForExit()
    Write-Log $ngenoutput
    Write-Log $errors
    if($throwonerror -and ($process.ExitCode -ne 0)){
        throw "$cmd failed."
    }
}

function UpdateProbingPath($settings){
    $webroot=$($settings.'Infrastructure.WebRoot')
    $webconfig=join-path $webroot "web.config"
    $appassembliesdir="bin\appassemblies"
    [System.Xml.XmlDocument] $xd=new-object System.Xml.XmlDocument
    $xd.Load($webconfig)
    $ns=New-Object System.Xml.XmlNamespaceManager($xd.NameTable)
    $ns.AddNamespace("ns",$xd.DocumentElement.NamespaceURI)

    # update probing path
    $tmp=join-path $webroot "bin\appassemblies"
    if(Test-Path $tmp){
        [string]$privatepath=$xd.Configuration.RunTime.AssemblyBinding.Probing.privatePath
        [string[]] $probingpaths=$privatepath.Split(";")
        if(!$probingpaths.Contains($appassembliesdir)){
            Write-Log "Adding $appassembliesdir to the private probing path in web.config"
            $privatepath += ";$appassembliesdir"
            $xd.Configuration.RunTime.AssemblyBinding.Probing.privatePath=$privatepath

            # save changes
            $xd.Save($webconfig)
        }
    }
}

function NgenFiles($settings,[switch] $updateprobingpath)
{
    Write-Log "Creating the native image for Dynamics assemblies"
    $webroot=$($settings.'Infrastructure.WebRoot')
    $appassembliesdir=Join-Path $webroot "bin\appassemblies"

    if(!(Test-Path "$appassembliesdir")){
        throw "sbin\appassemblie (symlink to Dynamics assemblies) folder doesn't exist under the webroot."
    }

    $codeblock={
        $ngen=Join-Path ([System.Runtime.InteropServices.RuntimeEnvironment]::GetRuntimeDirectory()) "ngen.exe"
        Write-Log "Calling ngen.exe from $ngen"

        # ngen.exe needs an exe and config to generate native images
        $ngenexe=join-path $webroot "__ngen_exe.exe"
        $ngenexeconfig=join-path $webroot "__ngen_exe.exe.config"

        # delete existing files
        if(Test-Path $ngenexe){
            Write-Log "Removing existing $ngenexe"
            Remove-Item $ngenexe -Force
        }

        if(Test-Path $ngenexeconfig){
            Write-Log "Removing existing $ngenexeconfig"
            Remove-Item $ngenexeconfig -Force
        }

        if($updateprobingpath){
            UpdateProbingPath -settings:$settings
        }

        $webconfig=Join-Path $webroot "web.config"
        Write-Log "Copying $webconfig to $ngenexe"
        Copy-Item $webconfig $ngenexe

        Write-Log "Copying $webconfig to $ngenexeconfig"
        Copy-Item $webconfig $ngenexeconfig

        $dlls=New-Object 'System.Collections.Generic.List[System.String]'
        $dlls.AddRange([System.IO.Directory]::EnumerateFiles($appassembliesdir,"Dynamics.Ax.*.dll",[System.IO.SearchOption]::TopDirectoryOnly))

        # uninstall
        Write-Log "Uninstalling old assemblies."
        foreach($dllpath in $dlls){
            $argument="uninstall `"$dllpath`" /nologo"
            Run-Process -cmd:$ngen -arguments:$argument # ngen uninstall throws error if assembly isn't registered which is expected; don't fail on it
        }
<#
        #install
        Write-Log "Ngen assemblies."
        foreach($dllpath in $dlls){
            $argument="install `"$dllpath`" /ExeConfig:`"$ngenexe`" /queue:1 /nologo /verbose"
            Run-Process -cmd:$ngen -arguments:$argument -throwonerror
        }

        Write-Log "Executing queued ngen jobs."
        $argument="executeQueuedItems /nologo /verbose"
        Run-Process -cmd:$ngen -arguments:$argument
#>
        return $true
    }

    ExecuteWith-Retry $codeblock "Ngen files"
    Write-Log "Native images for the Dynamics assemblies are created successfully."
}

function UpdateWebconfig($settings,[string]$uselazytypeloader)
{
    $webroot=$($settings.'Infrastructure.WebRoot')
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
    	Write-Log "Updating configuration '$key'='$value'"
		$existingNode.SetAttribute("value",$value)
	}
    else{
		$addElement=$xd.CreateElement("add")
		$addElement.SetAttribute("key",$key)
		$addElement.SetAttribute("value",$value)
        $appSettings=$xd.SelectSingleNode("//ns:appSettings",$ns)
		Write-Log "Adding configuration '$key'='$value' to web.config"
		$appSettings.AppendChild($addElement)
	}

    # save changes
    $xd.Save($webconfig)
}

function UpdateBatchConfig($settings,[string]$uselazytypeloader,[switch]$addprobingpath)
{
    $webroot=$($settings.'Infrastructure.WebRoot')
    $batchconfig=join-path $webroot "bin\batch.exe.config"
    if(!(Test-Path $batchconfig)){
        Write-Log "Batch.exe.config not found at $webroot\bin"
        return
    } 

    [System.Xml.XmlDocument] $xd=new-object System.Xml.XmlDocument
    $xd.Load($batchconfig)
    $ns=New-Object System.Xml.XmlNamespaceManager($xd.NameTable)
    $ns.AddNamespace("ns",$xd.DocumentElement.NamespaceURI)

    # add UseLazyTypeLoader setting
    $key="UseLazyTypeLoader"
    $value=$uselazytypeloader
    $existingNode = $xd.SelectSingleNode("//ns:add[@key='$key']",$ns)

    if($existingNode -ne $null){
        Write-Log "Updating configuration '$key'='$value'"
        $existingNode.SetAttribute("value",$value)
    }
    else{
        # add UseLazyTypeLoader key
        $addElement=$xd.CreateElement("add")
        $addElement.SetAttribute("key",$key)
        $addElement.SetAttribute("value",$value)
        $appSettings=$xd.SelectSingleNode("//ns:appSettings",$ns)
        Write-Log "Adding configuration '$key'='$value' to Batch.exe.config"
        $appSettings.AppendChild($addElement)
    }
    
    if($addprobingpath){
        # add appassemblies to the probing path
        $appassemblies="appassemblies"
        $probingelement=$xd.Configuration.RunTime.AssemblyBinding.Probing
        if($probingelement -ne $null){
            [string]$privatepath=$xd.Configuration.RunTime.AssemblyBinding.Probing.privatePath
            [string[]] $probingpaths=$privatepath.Split(";")
            if(-not $probingpaths.Contains($appassemblies)){
                Write-Log "Adding $appassemblies to the private probing path in Batch.exe.config"
                $privatepath += ";$appassemblies"
                $xd.Configuration.RunTime.AssemblyBinding.Probing.privatePath=$privatepath
            }
        }
        else{
            # add probing element
            $assemblyBindingNodes=$xd.Configuration.RunTime.AssemblyBinding
            $assemblyBinding=$assemblyBindingNodes[0]
            if(-not $assemblyBinding)
            {
                $assemblyBinding=$assemblyBindingNodes
            }
            $xmlns=$assemblyBinding.xmlns
            $probingElement=$xd.CreateElement("probing")
            $probingElement.SetAttribute("privatePath",$appassemblies)
            $probingElement.SetAttribute("xmlns",$xmlns)
            Write-Log "Adding private probing path to the batch.exe.config"
            $assemblyBinding.AppendChild($probingelement)
        }
    }

    Write-Log "Saving changes to the Batch.exe.config"
    # save changes
    $xd.Save($batchconfig)
}

# ngen should be done only if VStools is not installed
$vstoolscount=$($settings.'Infrastructure.VSToolsCount')
if($vstoolscount -eq "0"){
    Write-Log "Native image will be generated for the Dynamics assemblies as the Dynamics 365 Unified Operations: Dev Tools is not installed on this machine."
    NgenFiles -settings:$settings -updateprobingpath
    UpdateWebconfig -settings:$settings -uselazytypeloader:"false"
    UpdateBatchConfig -settings:$settings -uselazytypeloader:"false" -addprobingpath
}
else{
    UpdateWebconfig -settings:$settings -uselazytypeloader:"true" 
    UpdateBatchConfig -settings:$settings -uselazytypeloader:"true"
}

# SIG # Begin signature block
# MIIkCgYJKoZIhvcNAQcCoIIj+zCCI/cCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCCq3mG2nEwDpW+w
# 3ycAo2GQNVwvPXfBKkCRPlUEXDlUXaCCDYIwggYAMIID6KADAgECAhMzAAAAww6b
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
# KwYBBAGCNwIBCzEOMAwGCisGAQQBgjcCARUwLwYJKoZIhvcNAQkEMSIEIAXIcKdQ
# Y7PkzQkoPjbIf9pFLHH5FMBb0apJR14BhgXTMGQGCisGAQQBgjcCAQwxVjBUoDaA
# NABOAGcAZQBuAEQAeQBuAGEAbQBpAGMAcwBBAHMAcwBlAG0AYgBsAGkAZQBzAC4A
# cABzADGhGoAYaHR0cDovL3d3dy5taWNyb3NvZnQuY29tMA0GCSqGSIb3DQEBAQUA
# BIIBAJVU0uKSFs7QTo2EiYKkPrNHKD+0PxjwvIoUbGbcDJy0EqZwXvr9mYOsARFe
# PvqMx9F7dE1KPpZHEUx+eratYkqp1IIWnAuETCYecan+lur1FPW//gEANOXdnfi6
# f0jD871yvYgKuXUugkiZHuxoGb7wiJBnbFejaI52T6FINRxt0Q6FiDB+PgZ7Um/o
# 4wIi36PUEwMJKokTOQx6nU9F6o6ixeLAFSMyJbj/3zkmbA4hsitf4oaoKjWjikbs
# DB7BF3NrkOYD19CXGxWiXtFVFgak/nwnAfOOZYStTnMhbtgwjTYtldJjb/74sFqO
# Wfg+o7NiCLNySF6e/Dg43ye9/nGhghNGMIITQgYKKwYBBAGCNwMDATGCEzIwghMu
# BgkqhkiG9w0BBwKgghMfMIITGwIBAzEPMA0GCWCGSAFlAwQCAQUAMIIBPAYLKoZI
# hvcNAQkQAQSgggErBIIBJzCCASMCAQEGCisGAQQBhFkKAwEwMTANBglghkgBZQME
# AgEFAAQgaz28/fRM7tYWCEpnxXEUnJDYPg+wy6VmihzYAFLA4tYCBlqyjUywARgT
# MjAxODAzMjUyMTA1NTcuMTMxWjAHAgEBgAID56CBuKSBtTCBsjELMAkGA1UEBhMC
# VVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNV
# BAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEMMAoGA1UECxMDQU9DMScwJQYDVQQL
# Ex5uQ2lwaGVyIERTRSBFU046ODQzRC0zN0Y2LUYxMDQxJTAjBgNVBAMTHE1pY3Jv
# c29mdCBUaW1lLVN0YW1wIFNlcnZpY2Wggg7KMIIGcTCCBFmgAwIBAgIKYQmBKgAA
# AAAAAjANBgkqhkiG9w0BAQsFADCBiDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldh
# c2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBD
# b3Jwb3JhdGlvbjEyMDAGA1UEAxMpTWljcm9zb2Z0IFJvb3QgQ2VydGlmaWNhdGUg
# QXV0aG9yaXR5IDIwMTAwHhcNMTAwNzAxMjEzNjU1WhcNMjUwNzAxMjE0NjU1WjB8
# MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVk
# bW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSYwJAYDVQQDEx1N
# aWNyb3NvZnQgVGltZS1TdGFtcCBQQ0EgMjAxMDCCASIwDQYJKoZIhvcNAQEBBQAD
# ggEPADCCAQoCggEBAKkdDbx3EYo6IOz8E5f1+n9plGt0VBDVpQoAgoX77XxoSyxf
# xcPlYcJ2tz5mK1vwFVMnBDEfQRsalR3OCROOfGEwWbEwRA/xYIiEVEMM1024OAiz
# Qt2TrNZzMFcmgqNFDdDq9UeBzb8kYDJYYEbyWEeGMoQedGFnkV+BVLHPk0ySwcSm
# XdFhE24oxhr5hoC732H8RsEnHSRnEnIaIYqvS2SJUGKxXf13Hz3wV3WsvYpCTUBR
# 0Q+cBj5nf/VmwAOWRH7v0Ev9buWayrGo8noqCjHw2k4GkbaICDXoeByw6ZnNPOcv
# RLqn9NxkvaQBwSAJk3jN/LzAyURdXhacAQVPIk0CAwEAAaOCAeYwggHiMBAGCSsG
# AQQBgjcVAQQDAgEAMB0GA1UdDgQWBBTVYzpcijGQ80N7fEYbxTNoWoVtVTAZBgkr
# BgEEAYI3FAIEDB4KAFMAdQBiAEMAQTALBgNVHQ8EBAMCAYYwDwYDVR0TAQH/BAUw
# AwEB/zAfBgNVHSMEGDAWgBTV9lbLj+iiXGJo0T2UkFvXzpoYxDBWBgNVHR8ETzBN
# MEugSaBHhkVodHRwOi8vY3JsLm1pY3Jvc29mdC5jb20vcGtpL2NybC9wcm9kdWN0
# cy9NaWNSb29DZXJBdXRfMjAxMC0wNi0yMy5jcmwwWgYIKwYBBQUHAQEETjBMMEoG
# CCsGAQUFBzAChj5odHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20vcGtpL2NlcnRzL01p
# Y1Jvb0NlckF1dF8yMDEwLTA2LTIzLmNydDCBoAYDVR0gAQH/BIGVMIGSMIGPBgkr
# BgEEAYI3LgMwgYEwPQYIKwYBBQUHAgEWMWh0dHA6Ly93d3cubWljcm9zb2Z0LmNv
# bS9QS0kvZG9jcy9DUFMvZGVmYXVsdC5odG0wQAYIKwYBBQUHAgIwNB4yIB0ATABl
# AGcAYQBsAF8AUABvAGwAaQBjAHkAXwBTAHQAYQB0AGUAbQBlAG4AdAAuIB0wDQYJ
# KoZIhvcNAQELBQADggIBAAfmiFEN4sbgmD+BcQM9naOhIW+z66bM9TG+zwXiqf76
# V20ZMLPCxWbJat/15/B4vceoniXj+bzta1RXCCtRgkQS+7lTjMz0YBKKdsxAQEGb
# 3FwX/1z5Xhc1mCRWS3TvQhDIr79/xn/yN31aPxzymXlKkVIArzgPF/UveYFl2am1
# a+THzvbKegBvSzBEJCI8z+0DpZaPWSm8tv0E4XCfMkon/VWvL/625Y4zu2JfmttX
# QOnxzplmkIz/amJ/3cVKC5Em4jnsGUpxY517IW3DnKOiPPp/fZZqkHimbdLhnPkd
# /DjYlPTGpQqWhqS9nhquBEKDuLWAmyI4ILUl5WTs9/S/fmNZJQ96LjlXdqJxqgaK
# D4kWumGnEcua2A5HmoDF0M2n0O99g/DhO3EJ3110mCIIYdqwUB5vvfHhAN/nMQek
# kzr3ZUd46PioSKv33nJ+YWtvd6mBy6cJrDm77MbL2IK0cs0d9LiFAR6A+xuJKlQ5
# slvayA1VmXqHczsI5pgt6o3gMy4SKfXAL1QnIffIrE7aKLixqduWsqdCosnPGUFN
# 4Ib5KpqjEWYw07t0MkvfY3v1mYovG8chr1m1rtxEPJdQcdeh0sVV42neV8HR3jDA
# /czmTfsNv11P6Z0eGTgvvM9YBS7vDaBQNdrvCScc1bN+NR4Iuto229Nfj950iEkS
# MIIE2TCCA8GgAwIBAgITMwAAAKlUcNl5wIRl4gAAAAAAqTANBgkqhkiG9w0BAQsF
# ADB8MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMH
# UmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSYwJAYDVQQD
# Ex1NaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0EgMjAxMDAeFw0xNjA5MDcxNzU2NTNa
# Fw0xODA5MDcxNzU2NTNaMIGyMQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGlu
# Z3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBv
# cmF0aW9uMQwwCgYDVQQLEwNBT0MxJzAlBgNVBAsTHm5DaXBoZXIgRFNFIEVTTjo4
# NDNELTM3RjYtRjEwNDElMCMGA1UEAxMcTWljcm9zb2Z0IFRpbWUtU3RhbXAgU2Vy
# dmljZTCCASIwDQYJKoZIhvcNAQEBBQADggEPADCCAQoCggEBAKyUhRim5VbTnd8D
# Zy7bmJFHj5WJck2adPM0QN5rEafUx5J+Dv+fNTp/p2SMcZthxRlZPpRdkS9OwO3B
# QG4nB5HU5az2HjzOUBFTJ2iE0tJmpB9uHXspiybjCa5050z8n4O3Rg3bFakN+1f3
# s5sQ3gwcpE0aw5YkRjYpkFzeHUfWlz9CjQf/qC8njusSELFHQvcEvTk2xMW7wOy2
# vI6BnMndskA8PaPrG70wdf5bBXMdFDER1PA6v+zRE95EycT+SOFXxC54CBV+80UG
# Nkm2tf1YHRHdiGQDQhA5765TFkYRW1x9Elp3SHZwKWEhGpNTnCJpbpy0eXqOTDiE
# FRlsX6ECAwEAAaOCARswggEXMB0GA1UdDgQWBBQP1UH7u/Od9L5JUtqMN1fOZA/z
# fTAfBgNVHSMEGDAWgBTVYzpcijGQ80N7fEYbxTNoWoVtVTBWBgNVHR8ETzBNMEug
# SaBHhkVodHRwOi8vY3JsLm1pY3Jvc29mdC5jb20vcGtpL2NybC9wcm9kdWN0cy9N
# aWNUaW1TdGFQQ0FfMjAxMC0wNy0wMS5jcmwwWgYIKwYBBQUHAQEETjBMMEoGCCsG
# AQUFBzAChj5odHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20vcGtpL2NlcnRzL01pY1Rp
# bVN0YVBDQV8yMDEwLTA3LTAxLmNydDAMBgNVHRMBAf8EAjAAMBMGA1UdJQQMMAoG
# CCsGAQUFBwMIMA0GCSqGSIb3DQEBCwUAA4IBAQAImRilB4svciR1LI4ghAL9CqGv
# DuGwMhGGqsWGIJ276EQ7lcy1OueLRqUT04wgG6g6VxwV93NtjQuyB0VuhkV2JEa6
# dEzxNm9Snbbk5JSMySmriaq+coLTuptVq6CCOeAZLtgRrUWJA0vAL+IAnrh7h9vK
# 13W4LgS0jJM3ih4mROTZQWWO0UK5XhMQvBlndbvOhKnpH457zxuUuDldbVdZ7Ap+
# xtaVDTvn+ogvVqxVBFByZz+yAAPDjsL8PsiVq+DUZ7amNG20YAiyQonef2DaWCG8
# 04w4MlPyCszb3yS3AOuTSj8JejQ7S8Bza2pShFOhmwREWWFCrXLwQMBu/JqyoYID
# dDCCAlwCAQEwgeKhgbikgbUwgbIxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNo
# aW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29y
# cG9yYXRpb24xDDAKBgNVBAsTA0FPQzEnMCUGA1UECxMebkNpcGhlciBEU0UgRVNO
# Ojg0M0QtMzdGNi1GMTA0MSUwIwYDVQQDExxNaWNyb3NvZnQgVGltZS1TdGFtcCBT
# ZXJ2aWNloiUKAQEwCQYFKw4DAhoFAAMVAF06v1a94Q8pynIOZPd1O3gaIuv0oIHB
# MIG+pIG7MIG4MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4G
# A1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMQww
# CgYDVQQLEwNBT0MxJzAlBgNVBAsTHm5DaXBoZXIgTlRTIEVTTjoyNjY1LTRDM0Yt
# QzVERTErMCkGA1UEAxMiTWljcm9zb2Z0IFRpbWUgU291cmNlIE1hc3RlciBDbG9j
# azANBgkqhkiG9w0BAQUFAAIFAN5h6OwwIhgPMjAxODAzMjUwOTIyNTJaGA8yMDE4
# MDMyNjA5MjI1MlowdDA6BgorBgEEAYRZCgQBMSwwKjAKAgUA3mHo7AIBADAHAgEA
# AgIf0zAHAgEAAgIZXDAKAgUA3mM6bAIBADA2BgorBgEEAYRZCgQCMSgwJjAMBgor
# BgEEAYRZCgMBoAowCAIBAAIDHoCYoQowCAIBAAIDHoSAMA0GCSqGSIb3DQEBBQUA
# A4IBAQALaSU17fVmJkZARUL8rojVP9Oz1BjfZXsfbxfStrhSvCG3acNurBD5quyj
# yJWUp8ODpy5HfnOO+YeMobJj4HYlViFxc8eVOm2kMdNonaIwzxihq571EEbr1EFb
# 46CUBoEg/QS3IMYntw6ZT5zkUuZuGx8b7PMUxuHng8I85ax4sjoqnGTRUJz7OEuE
# 8kDBFNxObRhHBwKTMyinkvrB2vzmbKez4Ls76wUo9eWlFO3INnz0OerNJLE+E6XE
# /7EFN7+6i8/HVRoqHw/B9iLmpQHzJ8cpfkhn4BfKMCzfpXA05M66wjujP0lNGEZV
# Dx9Olc0J83bvwE2Jl+ehcSvsMulSMYIC9TCCAvECAQEwgZMwfDELMAkGA1UEBhMC
# VVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNV
# BAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRp
# bWUtU3RhbXAgUENBIDIwMTACEzMAAACpVHDZecCEZeIAAAAAAKkwDQYJYIZIAWUD
# BAIBBQCgggEyMBoGCSqGSIb3DQEJAzENBgsqhkiG9w0BCRABBDAvBgkqhkiG9w0B
# CQQxIgQgKg8ajEBwWFFnqk+0hCcY+3m2J3i6RHO1nhDBSV10auUwgeIGCyqGSIb3
# DQEJEAIMMYHSMIHPMIHMMIGxBBRdOr9WveEPKcpyDmT3dTt4GiLr9DCBmDCBgKR+
# MHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdS
# ZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xJjAkBgNVBAMT
# HU1pY3Jvc29mdCBUaW1lLVN0YW1wIFBDQSAyMDEwAhMzAAAAqVRw2XnAhGXiAAAA
# AACpMBYEFOQK0b0CjM2rZxutF33QACO77qVtMA0GCSqGSIb3DQEBCwUABIIBAEan
# MLTaX5pK6IuHM4pX/tnjozQ5dwfYaveF7O6617evrI2oUQxeGaRf3h6frmABi0NB
# ZXTpSaLR9obshhCzDfFJfCRNu2/zvAn0kn8nY/a4D3PAvaGkef1HD2G+8Qz+3phU
# CR2ht89ck86nxINqZwC994AZrjgWQpMCfCEo+LsZA7rmJwDN2n1rl1IJdLptXNjq
# d97NVjKF+ikUSAlXruGafrxdiKcvDd0M3nHkVdwSJHu9AD2sviFwXSd07tZVBZn6
# b28xa3OkDQy/3W3dkExeqKTXMgzo/IBkLLnV15Y01Yoy3sf/WfGhd+cGzolcjjlV
# YM7TachfhRk3KsRSDCQ=
# SIG # End signature block
