param
(
    # web root directory for the AOS web application
    [Parameter(Mandatory=$true)]
    $webroot,
    # directory where the models are deployed
    [Parameter(Mandatory=$true)]
    $packagedir,
    # log file
    [Parameter(Mandatory=$true)]
    $log
)

$signature = @’
[DllImport("kernel32.dll")] 
public static extern bool CreateSymbolicLink(string symlinkFileName, string targetFileName, int flags);
‘@

$type = Add-Type -MemberDefinition $signature -Name Win32Utils -Namespace CreateSymbolicLink -PassThru

function InitializeLog
{
    if(Test-Path $Global:log){
        Write-Output "Deleting existing log file $Global:log."
        Remove-Item $Global:log -Force
    }

    New-Item -ItemType file $Global:log -Force
}

function Write-Log ([string]$message)
{
    $datetime=get-date -Format "MMddyyyyhhmmss"
    if($Global:log -ne $null){
        "$datetime`: $message" >> $Global:log
    }

    Write-Output "$datetime`: $message"
}

function CreateSymbolicLink([string]$webroot,[string]$packagedir)
{
    Write-Log "Starting the creation of symlinks."
    Write-Log "Dynamics 365 Unified Operations package directory is: $packagedir"
    Write-Log "AOS webroot is: $webroot"
    $appassembliesdir=Join-Path $webroot "bin\appassemblies"

    if(!(Test-Path $appassembliesdir)){
        Write-Log "Creating $appassembliesdir"
        New-Item -ItemType Directory -Path $appassembliesdir -Force
    }

    $packagesbindir=join-path $packagedir "bin"

    $directories=[System.IO.Directory]::EnumerateDirectories($packagedir,"*",[System.IO.SearchOption]::TopDirectoryOnly)
    foreach($moduledir in $directories)
    {
        if($moduledir -ne "$packagesbindir"){
            $bindir=Join-Path $moduledir "bin"
        }else{
            $bindir=$moduledir
        }

        if(Test-Path $bindir){
            Write-Log "Enumerating applicable files at '$bindir'."
            $files=New-Object 'System.Collections.Generic.List[System.String]'
            $files.AddRange([System.IO.Directory]::EnumerateFiles($bindir,"*.dll",[System.IO.SearchOption]::TopDirectoryOnly))
            $files.AddRange([System.IO.Directory]::EnumerateFiles($bindir,"*.netmodule",[System.IO.SearchOption]::TopDirectoryOnly))
            $files.AddRange([System.IO.Directory]::EnumerateFiles($bindir,"*.runtime",[System.IO.SearchOption]::TopDirectoryOnly))
            $files.AddRange([System.IO.Directory]::EnumerateFiles($bindir,"*.xml",[System.IO.SearchOption]::TopDirectoryOnly))

            foreach($filepath in $files){
               $file=[System.IO.Path]::GetFileName($filepath)
               $tmp1=Join-Path $webroot "bin\$file"
               $tmp2=Join-Path $appassembliesdir $file
               if(((Test-Path "$tmp1") -eq $false)){
                   if((Test-Path "$tmp2") -eq $true){
                        Write-Log "Removing existing symlink $tmp2"
                        Remove-Item $tmp2 -Force
                   }

                   Write-Log "Creating a symlink at: $tmp2 for source: $filepath"
                   if(-not $type::CreateSymbolicLink($tmp2,$filepath,0)){
                        throw "Symlink creation failed for file: $tmp2"
                   }
               }
            }
        }
    }

    Write-Log "Symlinks created."
}

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

function UpdateProbingPath([string]$webroot){
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

function NgenFiles([string]$webroot,[switch]$updateprobingpath)
{
    Write-Log "Creating the native images for Dynamics assemblies."
    $appassembliesdir=Join-Path $webroot "bin\appassemblies"

    if(!(Test-Path "$appassembliesdir")){
        throw "bin\appassemblies (symlink to Dynamics assemblies) folder doesn't exist under the webroot."
    }
    
    $ngen=Join-Path ([System.Runtime.InteropServices.RuntimeEnvironment]::GetRuntimeDirectory()) "ngen.exe"
    Write-Log "Ngen.exe path: $ngen"

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
        UpdateProbingPath -webroot:$webroot
    }

    $webconfig=Join-Path $webroot "web.config"
    Write-Log "Copying $webconfig to $ngenexe"
    Copy-Item $webconfig $ngenexe

    Write-Log "Copying $webconfig to $ngenexeconfig"
    Copy-Item $webconfig $ngenexeconfig

    $dlls=New-Object 'System.Collections.Generic.List[System.String]'
    $dlls.AddRange([System.IO.Directory]::EnumerateFiles($appassembliesdir,"Dynamics.Ax.*.dll",[System.IO.SearchOption]::TopDirectoryOnly))

    # uninstall
    Write-Log "Uninstalling existing Dynamics native assembly images."
    foreach($dllpath in $dlls){
        $argument="uninstall `"$dllpath`" /nologo"
        Run-Process -cmd:$ngen -arguments:$argument # ngen uninstall throws error if assembly isn't registered which is expected; don't fail on it
    }

<#
    #install
    Write-Log "Creating native images for Dynamics assemblies..."
    foreach($dllpath in $dlls){
        $argument="install `"$dllpath`" /ExeConfig:`"$ngenexe`" /queue:1 /nologo /verbose"
        Run-Process -cmd:$ngen -arguments:$argument -throwonerror
    }

    Write-Log "Executing queued Ngen.exe jobs."
    $argument="executeQueuedItems /nologo /verbose"
    Run-Process -cmd:$ngen -arguments:$argument
    
    Write-Log "Native images for the Dynamics assemblies are created."
#>
}

function UpdateWebconfig([string]$webroot,[string]$uselazytypeloader)
{
   	Write-Log "Updating the AOS web configuration."
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
    	    Write-Log "Updating configuration '$key'='$value'"
		    $existingNode.SetAttribute("value",$value)
            $xd.Save($webconfig) # save changes
        }
	}
    else{
		$addElement=$xd.CreateElement("add")
		$addElement.SetAttribute("key",$key)
		$addElement.SetAttribute("value",$value)
        $appSettings=$xd.SelectSingleNode("//ns:appSettings",$ns)
		Write-Log "Adding configuration '$key'='$value' to web.config"
		$appSettings.AppendChild($addElement)
        $xd.Save($webconfig) # save changes
	}
}

function UpdateBatchConfig([string]$webroot,[string]$uselazytypeloader,[switch]$addprobingpath)
{
    Write-Log "Updating the Dynamics Batch configuration file."
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
            Write-Log "Updating configuration '$key'='$value'"
            $existingNode.SetAttribute("value",$value)
            $save=$true
        }
    }
    else{
        # add UseLazyTypeLoader key
        $addElement=$xd.CreateElement("add")
        $addElement.SetAttribute("key",$key)
        $addElement.SetAttribute("value",$value)
        $appSettings=$xd.SelectSingleNode("//ns:appSettings",$ns)
        Write-Log "Adding configuration '$key'='$value' to Batch.exe.config"
        $appSettings.AppendChild($addElement)
        $save=$true
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
                $save=$true
            }
        }
        else{
            # add probing element
            $assemblyBinding=$xd.Configuration.RunTime.AssemblyBinding
            $xmlns=$assemblyBinding.xmlns
            $probingElement=$xd.CreateElement("probing")
            $probingElement.SetAttribute("privatePath",$appassemblies)
            $probingElement.SetAttribute("xmlns",$xmlns)
            Write-Log "Adding private probing path to the batch.exe.config"
            $assemblyBinding.AppendChild($probingelement)
            $save=$true
        }
    }

    if($save -eq $true){
        Write-Log "Saving changes to the Dynamics Batch configuration file."
        $xd.Save($batchconfig)
    }
}

$Global:log=$log
InitializeLog
CreateSymbolicLink -webroot:$webroot -packagedir:$packagedir
NgenFiles -webroot:$webroot -updateprobingpath
UpdateWebconfig -webroot:$webroot -uselazytypeloader:"false"
UpdateBatchConfig -webroot:$webroot -uselazytypeloader:"false" -addprobingpath
# SIG # Begin signature block
# MIIkGgYJKoZIhvcNAQcCoIIkCzCCJAcCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCArBxJ/wB8b2s5N
# I4jXN16ByUYMnKtSQzopPF4CWt31cKCCDYIwggYAMIID6KADAgECAhMzAAAAww6b
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
# KwYBBAGCNwIBCzEOMAwGCisGAQQBgjcCARUwLwYJKoZIhvcNAQkEMSIEIL4fxgZ7
# 5N96fntIKZQxEruOw3REhE1eNc7iMTq3KO9uMHQGCisGAQQBgjcCAQwxZjBkoEaA
# RABDAHIAZQBhAHQAZQBTAHkAbQBMAGkAbgBrAEEAbgBkAE4AZwBlAG4AQQBzAHMA
# ZQBtAGIAbABpAGUAcwAuAHAAcwAxoRqAGGh0dHA6Ly93d3cubWljcm9zb2Z0LmNv
# bTANBgkqhkiG9w0BAQEFAASCAQCmPP0wNOHJGTp5NNVSaOdbHOfxG9xt6+QwmMLi
# L3F4YalPJGo0Vp2VwEsN6awEsAQ02W3JwPczJKBWUPrtw78AdUetA8QGfUwMVhVZ
# 25ZSz6zFLv/1cW9FNjant5tnwOgxY4JEF2tVPLlX77LhrWJwW9CNsD/jOEnCJCQg
# E77nGcABjAqKqRk2rrUZs3+dRvLnJtk0IWoUZvT5wqWAVBLU3aXPS3nzt6pJZAt9
# yUs6iu1wC2Ln4X14cyAQBsFOJPmQmZMAkG3O5NmT4em5vAkvz3XGy/fK5ltIxomY
# lxmm5BufdKyeeEi7jJ5WZ6HMNPoLNeZY+S/HwljWBXySQ/JjoYITRjCCE0IGCisG
# AQQBgjcDAwExghMyMIITLgYJKoZIhvcNAQcCoIITHzCCExsCAQMxDzANBglghkgB
# ZQMEAgEFADCCATwGCyqGSIb3DQEJEAEEoIIBKwSCAScwggEjAgEBBgorBgEEAYRZ
# CgMBMDEwDQYJYIZIAWUDBAIBBQAEIDjUP5XG513T0lRODZ1lSf7W0ewMX0LfBIcK
# +eIsd5HmAgZaspvFVgYYEzIwMTgwMzI1MjExNTI4LjA1M1owBwIBAYACAfSggbik
# gbUwgbIxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQH
# EwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xDDAKBgNV
# BAsTA0FPQzEnMCUGA1UECxMebkNpcGhlciBEU0UgRVNOOjU3QzgtMkQxNS0xQzhC
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
# fjUeCLraNtvTX4/edIhJEjCCBNkwggPBoAMCAQICEzMAAACqt6mI/+pXwwoAAAAA
# AKowDQYJKoZIhvcNAQELBQAwfDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hp
# bmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jw
# b3JhdGlvbjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRpbWUtU3RhbXAgUENBIDIwMTAw
# HhcNMTYwOTA3MTc1NjUzWhcNMTgwOTA3MTc1NjUzWjCBsjELMAkGA1UEBhMCVVMx
# EzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoT
# FU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEMMAoGA1UECxMDQU9DMScwJQYDVQQLEx5u
# Q2lwaGVyIERTRSBFU046NTdDOC0yRDE1LTFDOEIxJTAjBgNVBAMTHE1pY3Jvc29m
# dCBUaW1lLVN0YW1wIFNlcnZpY2UwggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEK
# AoIBAQCe2H97V3j6BfqjmreQr5q51bZ0dpHLuM67Ks4rKe9ftGt1mHUogK2Yj7mq
# 8J3StptHZJjGpVmqkXj5Hot59yR0Ruok/mkErr7rf1NTE1nVD/z7zd32B0GbGzc3
# 2Vx2md2ux8Pb061owlCcdA5Edy4unW/BHe8sxzt0rtuXLY+BxUcFQMBKN0iTvAOa
# S/CNBMtDcPvoWLGdrFDnubWE8cebB+z3mmnbr0h/rFkxhmIWcJVe8cvMOkfz6j8C
# jBC7vSOMqQNzTw64DFzxL6p/+mSbjC6YFMBGzyZPPAYjxk8it5IPGgIZ/JwpzYTe
# ga/w/a2YrKWIg4aVVIa0m3FAxi83AgMBAAGjggEbMIIBFzAdBgNVHQ4EFgQUCLhy
# HRUk9ZMC4Z/SHEzTq8xZybAwHwYDVR0jBBgwFoAU1WM6XIoxkPNDe3xGG8UzaFqF
# bVUwVgYDVR0fBE8wTTBLoEmgR4ZFaHR0cDovL2NybC5taWNyb3NvZnQuY29tL3Br
# aS9jcmwvcHJvZHVjdHMvTWljVGltU3RhUENBXzIwMTAtMDctMDEuY3JsMFoGCCsG
# AQUFBwEBBE4wTDBKBggrBgEFBQcwAoY+aHR0cDovL3d3dy5taWNyb3NvZnQuY29t
# L3BraS9jZXJ0cy9NaWNUaW1TdGFQQ0FfMjAxMC0wNy0wMS5jcnQwDAYDVR0TAQH/
# BAIwADATBgNVHSUEDDAKBggrBgEFBQcDCDANBgkqhkiG9w0BAQsFAAOCAQEAYI8O
# 7gfOGuF9n3nGeA6dzkykAZ1qZ0eXERuKcsrkwXznLeOPkWe86HR6P8rpRiQAP6HO
# 8H5P0vQaffR2OB0UNh2l2YlvysVTFO8TLCACldEKecXS7m08P5FG6blS3t9c4pyk
# TVFqHcLpk01GchYm+YT/k3fd6AM9VPzCBKBfj4e9VXSa6WSssOQaylw7IB8LVVgI
# sMPLp7xZLE1Cke1bszAukqeTjk6ADK6peTHsUpF8lRCvf8HOI9sPmcxqw8T0LB91
# ZIIsoNgOB/eaDmWoXJWBnH5Y7nnzkSGt280sv7WIcv4GG51fdg92MoiuUjxtOS7M
# Bk4kSS0vqWYA1vxoJqGCA3QwggJcAgEBMIHioYG4pIG1MIGyMQswCQYDVQQGEwJV
# UzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UE
# ChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMQwwCgYDVQQLEwNBT0MxJzAlBgNVBAsT
# Hm5DaXBoZXIgRFNFIEVTTjo1N0M4LTJEMTUtMUM4QjElMCMGA1UEAxMcTWljcm9z
# b2Z0IFRpbWUtU3RhbXAgU2VydmljZaIlCgEBMAkGBSsOAwIaBQADFQCcnMVrmMyn
# wa1HIOzTRPzObdDqA6CBwTCBvqSBuzCBuDELMAkGA1UEBhMCVVMxEzARBgNVBAgT
# Cldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29m
# dCBDb3Jwb3JhdGlvbjEMMAoGA1UECxMDQU9DMScwJQYDVQQLEx5uQ2lwaGVyIE5U
# UyBFU046MjY2NS00QzNGLUM1REUxKzApBgNVBAMTIk1pY3Jvc29mdCBUaW1lIFNv
# dXJjZSBNYXN0ZXIgQ2xvY2swDQYJKoZIhvcNAQEFBQACBQDeYem0MCIYDzIwMTgw
# MzI1MDkyNjEyWhgPMjAxODAzMjYwOTI2MTJaMHQwOgYKKwYBBAGEWQoEATEsMCow
# CgIFAN5h6bQCAQAwBwIBAAICJp4wBwIBAAICGgswCgIFAN5jOzQCAQAwNgYKKwYB
# BAGEWQoEAjEoMCYwDAYKKwYBBAGEWQoDAaAKMAgCAQACAxbjYKEKMAgCAQACAx6E
# gDANBgkqhkiG9w0BAQUFAAOCAQEASz033EpW84nZpGQKE/bTByOuDdqNUFl3448h
# NVLTcWSYPUnqnrq3Ig17AzC9zTkzlQJIfuCHRyqYabBRaIDxwJU2ZJpQMHpqOylW
# wTLFn/UwyieLX/qWMwxApoDRwmFRGbC7jLiS67X9IL4waE93CQQoXVtjue+UsJxd
# V6qLqIs4QPVxazegiyO9JzwhLVgUW8xHvbS5432I7ouRGCgYYdynLLFQxJAZQk6J
# qwk4JzIrqLRtGNFjxTBtZYfF1mswPMWa5+tq0MbU8KMFkUOWySKeFPAf6Kazsk4t
# aJ75HcBy0u99o+F9G/d3s6jINcULbm1gGIuvPlZm7gvPB384IDGCAvUwggLxAgEB
# MIGTMHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQH
# EwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xJjAkBgNV
# BAMTHU1pY3Jvc29mdCBUaW1lLVN0YW1wIFBDQSAyMDEwAhMzAAAAqrepiP/qV8MK
# AAAAAACqMA0GCWCGSAFlAwQCAQUAoIIBMjAaBgkqhkiG9w0BCQMxDQYLKoZIhvcN
# AQkQAQQwLwYJKoZIhvcNAQkEMSIEINt80MxcFLpcm4plrCSopxWefK2BciyXWaq5
# 6D9gkttVMIHiBgsqhkiG9w0BCRACDDGB0jCBzzCBzDCBsQQUnJzFa5jMp8GtRyDs
# 00T8zm3Q6gMwgZgwgYCkfjB8MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGlu
# Z3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBv
# cmF0aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0EgMjAxMAIT
# MwAAAKq3qYj/6lfDCgAAAAAAqjAWBBQoMyUfR5+52q9gS8+7I/DRhE38aDANBgkq
# hkiG9w0BAQsFAASCAQCGDgtkSfTNsPQ/lk3kTNPYomwXGh0J1aoom0812mFsFbSx
# JhSMnsc0DYxB0XYCwc+UmGtm6JZTKPTG65s3/ZQzqtd/D40QWvw+ICv/s2wymKlr
# JKbtsLCMq/6g2jA5r9fKed3faWSqpqn38sPnWdZhEG86HDsrHScOEc433XZAKSod
# TGUkrH1+/BxxVWMDNDzI5bECOaEgjVK1q5oWFFglKKiBIZDlrppYNeQHsq658jF6
# Odv2XX8ybbJ3gckBalh9NA002qsKaNdM78G+TeHIDGr0N+3K6jXnKNlQjTpPP7q7
# AmJYugzyA5s2tMl8NT7lRw7XnkoYGzm+9JIKY1bg
# SIG # End signature block
