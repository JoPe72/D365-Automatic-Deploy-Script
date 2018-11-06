param
(
    [parameter(Position=0,Mandatory=$false)][boolean] $useServiceFabric=$false 
)

if(!$useServiceFabric)
{
    Import-Module WebAdministration
}


function Create-ZipFiles(
    [string] $sourceFolder = $(Throw 'sourceFolder parameter required'),
    [string] $destFile = $(Throw 'destFile parameter required'),
    [string] $filetypesExcluded,
    [string] $folderExcluded,
    [string] $fileFilter)
{
    Set-Variable zipLocation -Option Constant -Value (Join-Path $env:SystemDrive "DynamicsTools\7za.exe")

    if(-Not (Test-Path $sourceFolder))
    {
        throw "Path not found: $sourceFolder"
    }
    
    if(Test-Path $destFile)
    {
        Remove-Item $destFile -Force
    }

    Push-Location $sourceFolder
    $argumentList = "a -r -y"
    
    if(![string]::IsNullOrEmpty($filetypesExcluded))
    {
        $argumentList = $argumentList + " -x!$filetypesExcluded"
    }
    
    if(![string]::IsNullOrEmpty($folderExcluded))
    {
        $argumentList = $argumentList + " -xr!$folderExcluded"
    }

    $argumentList = $argumentList + " $destFile"

    if(![string]::IsNullOrEmpty($fileFilter))
    {
        $argumentList = $argumentList + " $fileFilter"
    }

    $ZipLog = Join-Path $PSScriptRoot tempZipLog.txt
    if(Test-Path $ZipLog)
    {
        Remove-Item $ZipLog
    }

    $process = Start-Process $zipLocation -ArgumentList $argumentList -NoNewWindow -Wait -PassThru -RedirectStandardOutput $ZipLog #7zip doesn't have stderr
    try { if (!($process.HasExited)) { Wait-Process $process } } catch { }

    Pop-Location
    if($process.ExitCode -ne 0)
    {
        throw "fail to generate zip archive: $destFile, check the log file for more detail: $ZipLog"
    }
    if(Test-Path $ZipLog)
    {
        Remove-Item $ZipLog
    }
}

function StopMonitoring()
{
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
    }
}

function StartMonitoring()
{
    # Read the registry key to find the instrumentation folder
    $regPath = "HKLM:\SOFTWARE\Microsoft\Dynamics\AX\Diagnostics\MonitoringInstall"
    $instrumentationPathKey = "ManifestPath"
    $installPathKey = "InstallPath"

    if (Test-Path $regPath) 
    {
        # Run the scheduled task
        $scheduledTask = Get-ScheduledTask | ? {$_.TaskName -eq "MonitoringInstall"}
        If ($scheduledTask -ne $Null)
        {
            Write-Output "ScheduledTask $scheduledTask exists"
            Start-ScheduledTask $scheduledTask.TaskName -TaskPath $scheduledTask.TaskPath
            Write-Output "$scheduledTask triggered."
        }
    } 
}

function Create-ZipFiles-FromFileList(
    [string[]] $fileList = $(Throw 'fileList parameter required'),
    [string] $destFile = $(Throw 'destFile parameter required'))
{
    Set-Variable zipLocation -Option Constant -Value (Join-Path $env:SystemDrive "DynamicsTools\7za.exe")

    foreach ($element in $fileList) 
    {
        if(-Not (Test-Path $element))
        {
            throw "Path not found: $element"
        }
    }
    
    if(Test-Path $destFile)
    {
        Remove-Item $destFile -Force
    }

    $argumentList = "a" + " $destFile"

    foreach ($element in $fileList) 
    {
        $argumentList = $argumentList + " $element"
    }

    $ZipLog = Join-Path $PSScriptRoot tempZipLog.txt
    if(Test-Path $ZipLog)
    {
        Remove-Item $ZipLog
    }

    $process = Start-Process $zipLocation -ArgumentList $argumentList -NoNewWindow -Wait -PassThru -RedirectStandardOutput $ZipLog #7zip doesn't have stderr
    try { if (!($process.HasExited)) { Wait-Process $process } } catch { }

    if($process.ExitCode -ne 0)
    {
        throw "fail to generate zip archive: $destFile, check the log file for more detail: $ZipLog"
    }
    if(Test-Path $ZipLog)
    {
        Remove-Item $ZipLog
    }
}

function Unpack-ZipFiles(
    [string] $sourceFile = $(Throw 'sourceFile parameter required'),
    [string] $destFolder = $(Throw 'destFolder parameter required'))
{
    Set-Variable zipLocation -Option Constant -Value (Join-Path $env:SystemDrive "DynamicsTools\7za.exe")

    if(-Not (Test-Path $sourceFile))
    {
        throw "File not found: $sourceFile"
    }    

    if(-Not (Test-Path $destFolder))
    {
        throw "Path not found: $destFolder"
    }
    Push-Location $destFolder
    $argumentList = "x -y $sourceFile"

    $process = Start-Process $zipLocation -ArgumentList $argumentList -NoNewWindow -Wait -PassThru
    try { if (!($process.HasExited)) { Wait-Process $process } } catch { }

    Pop-Location
    if($process.ExitCode -ne 0)
    {
        $argumentList
        throw "fail to extract zip archive: $sourceFile"
    }
}

function Get-WebSitePhysicalPath([string]$Name = $(Throw 'Name parameter required'))
{
    if (Get-Service W3SVC | where status -ne 'Running')
    {
        #IIS service is not running, starting IIS Service.
        Start-Service W3SVC
    }

    $webSitePhysicalPath = (Get-WebSite | Where-Object { $_.Name -eq $Name }).PhysicalPath
    
    return $webSitePhysicalPath	
}

function Get-AosWebSitePhysicalPath()
{
    $websiteName = Get-AosWebSiteName
    if($websiteName)
    {
        $websitePath = Get-WebSitePhysicalPath -Name $websiteName
        if([string]::IsNullOrWhiteSpace($websitePath))
        {
            throw "Failed to find the webroot of AOS Service website."
        }
        return $websitePath
    }
    else
    {
        throw "Failed to find the website name. Unable to determine the physical website path."
    }
}

function Get-AosServicePath()
{
    $websitePath = Get-AosWebSitePhysicalPath
    $aosWebServicePath = "$(split-Path -parent $websitePath)"
    return $aosWebServicePath
}

function Get-AosServiceStagingPath()
{
    $aosWebServicePath = Get-AosServicePath
    $stagingFolder = Join-Path  "$(split-Path -parent $aosWebServicePath)" "AosServiceStaging"
    return $stagingFolder
}

function Get-AosServiceBackupPath()
{
    $aosWebServicePath = Get-AosServicePath
    $stagingFolder = Join-Path  "$(split-Path -parent $aosWebServicePath)" "AosServiceBackup"
    return $stagingFolder
}

function Get-AosWebSiteName()
{
    if(test-path "iis:\sites\AosService")
    {
        return "AosService"
    }
    elseif(test-path "iis:\sites\AosServiceDSC")
    {
        return "AosServiceDSC"
    }
    elseif(test-path "iis:\sites\AosWebApplication")
    {
        return "AosWebApplication"
    }
    else
    {
        throw "Failed to find the AOS website name."
    }
}

function Get-AosAppPoolName()
{
    $websiteName=Get-AosWebSiteName
    if($websiteName)
    {
        if($websiteName -eq "AosWebApplication")
        {
            #Non service-model deployments have a different app pool and site name
            return "AOSAppPool"        
        }
        else
        {
            #Service model-based deployments have app pool and site use the same name
            return $websiteName
        }
    }
    else
    {
        throw "Failed to find the AOS website name. Unable to determine application pool name."
    }
}

function Backup-WebSite(
    [ValidateNotNullOrEmpty()]
    [string]$Name = $(Throw 'Name parameter required'),
    
    [string]$BackupFolder)
{
    Write-Output "Executing backup for [$Name] website"
    
    $webroot = Get-WebSitePhysicalPath -Name $Name
    if([string]::IsNullOrEmpty($webroot))
    {
        throw "Failed to locate physical path for [$Name] website."
    }

    if ([string]::IsNullOrEmpty($BackupFolder))
    {
        $BackupFolder = ("$PSScriptRoot\{0}_Backup" -f $Name)
    }

    $webrootBackupFolder = Join-Path $BackupFolder 'webroot'

    if(-not (Test-Path -Path $webrootBackupFolder ))
    {
        New-Item -ItemType Directory -Path $webrootBackupFolder -Force
    }

    Write-Output "Begin backup of [$Name] website at $webroot"
    Create-ZipFiles -sourceFolder $webroot -destFile (Join-Path $webrootBackupFolder 'webroot.zip')
    Write-Output "Finished executing backup for [$Name]"
}

function Restore-WebSite(
    [ValidateNotNullOrEmpty()]
    [string]$Name = $(Throw 'Name parameter required'),
    
    [string]$BackupFolder)
{
    Write-Output "Executing restore for [$Name] website"
    
    $webroot = Get-WebSitePhysicalPath -Name $Name
    if([string]::IsNullOrEmpty($webroot))
    {
        throw "Failed to locate physical path for [$Name] website."
    }

    if ([string]::IsNullOrEmpty($BackupFolder))
    {
        $BackupFolder = ("$PSScriptRoot\{0}_Backup" -f $Name)
    }

    $webrootBackupFolder = Join-Path $BackupFolder 'webroot'

    if(-not (Test-Path -Path $webrootBackupFolder ))
    {
        throw "Failed to find the backup file for website [$Name], restore aborted."
    }

    Write-Output "Removing website data at $webroot"
    Remove-Item -Path "$webroot\*" -Recurse -Force
    
    Write-Output "Restoring website data at $webroot"
    Unpack-ZipFiles -sourceFile "$webrootBackupFolder\webroot.zip" -destFolder $webroot 
    
    Write-Output "Finished executing restore for [$Name] website"
}

function Copy-FullFolder([string] $SourcePath, [string] $DestinationPath)
{
    if (-not (Test-Path $SourcePath))
    {
        throw error "$SourcePath path does not exist"
    }
  
    if (-not (Test-Path $DestinationPath))
    {
        New-Item -ItemType Directory -Path $DestinationPath
    }
    $robocopyOptions = @("/E", "/MT")
    #Bug 3822095:Servicing - in HA env the aos backup step failed with filename or extension too long error message
   
    $cmdArgs = @($robocopyOptions, "$SourcePath", "$DestinationPath")
    & robocopy @cmdArgs >$null
    
}

function Copy-SymbolicLinks([string] $SourcePath, [string] $DestinationPath, [switch] $Move = $false)
{
    if (-not (Test-Path $SourcePath))
    {
        throw error "$SourcePath path does not exist"
    }

    $filesToCopy = @{} # Hashtable for each folder and files inside that folder to copy
    $foldersToCopy = @() # List of folders to copy

    # Parse existing files into folders and files that needs to be copied.
    Get-ChildItem -Recurse $SourcePath | Where-Object { $_.LinkType -eq "SymbolicLink" } | ForEach-Object {
        $dir = Split-Path $_.FullName -Parent
        $fileName = $_.Name


        if ($_.PSIsContainer)
        {
            $foldersToCopy += $_.FullName
        }
        else
        {
            if ($filesToCopy.ContainsKey($dir))
            {
                $fileList = $filesToCopy.Get_Item($dir)
                $fileList += $fileName
                $filesToCopy.Set_Item($dir, $fileList)
            }
            else
            {
                $fileList = @()
                $fileList += $fileName
                $filesToCopy.Add($dir, $fileList)
            }
        }
    }

    # Robocopy files, with each iteration going through a new directory
    $filesToCopy.GetEnumerator() | ForEach-Object {
        $source = $_.Key
        $files = $_.Value
        $relative = Get-RelativePath -ChildPath $source -ParentPath $SourcePath
        $destination = Join-Path $DestinationPath $relative
        
        if (-not (Test-Path $destination))
        {
            New-Item -ItemType Directory -Path $destination
        }
        $robocopyOptions = @("/SL")
        #Bug 3822095:Servicing - in HA env the aos backup step failed with filename or extension too long error message
        foreach ($file in $files)
        {
            $cmdArgs = @($robocopyOptions, "$source", "$destination", @($file))
            & robocopy @cmdArgs >$null
        }
    }

    # Copy symbolic link folders, since robocopy does not support them
    $foldersToCopy | ForEach-Object {
        $source = $_
        $relative = Get-RelativePath -ChildPath $source -ParentPath $SourcePath
        $destination = Join-Path $DestinationPath $relative
        xcopy /b /i $source $destination >$null
    }

    if ($Move)
    {
        $filesToCopy.GetEnumerator() | ForEach-Object {
            $folder = $_.Key
            $_.Value | ForEach-Object{
                $file = $_
                $fullPath = Join-Path $folder $file
                Remove-Item -Force $fullPath
            }
        }

        $foldersToCopy | ForEach-Object {
            [System.IO.Directory]::Delete($_, $true)
        }
    }
}

function Get-RelativePath([string] $ChildPath, [string] $ParentPath)
{
    # Parent path must be resolved to literal
    $parentLiteralPath = Resolve-Path $ParentPath
    $childLiteralPath = Resolve-Path $ChildPath

    $parentMatch = $parentLiteralPath -replace "\\", "\\"
    if ($childLiteralPath -match "^$parentMatch(.+)$")
    {
        return $Matches[1]
    }
    else
    {
        # ChildPath is not a child of ParentPath, return empty string
        return ''
    }
}

Export-ModuleMember -Function Backup-WebSite
Export-ModuleMember -Function Create-ZipFiles
Export-ModuleMember -Function Get-AosAppPoolName
Export-ModuleMember -Function Get-AosWebSiteName
Export-ModuleMember -Function Get-AosWebSitePhysicalPath
Export-ModuleMember -Function Get-WebSitePhysicalPath
Export-ModuleMember -Function Restore-WebSite
Export-ModuleMember -Function Unpack-ZipFiles
Export-ModuleMember -Function Copy-SymbolicLinks
Export-ModuleMember -Function Copy-FullFolder
Export-ModuleMember -Function Get-RelativePath
Export-ModuleMember -Function Get-AosServicePath
Export-ModuleMember -Function Get-AosServiceStagingPath
Export-ModuleMember -Function Get-AosServiceBackupPath
Export-ModuleMember -Function Create-ZipFiles-FromFileList
Export-ModuleMember -Function Create-ZipFiles-FromFileList
Export-ModuleMember -Function StopMonitoring
Export-ModuleMember -Function StartMonitoring
# SIG # Begin signature block
# MIIkDgYJKoZIhvcNAQcCoIIj/zCCI/sCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCBAIckmujoe3qqT
# SrDHHSrx92TUCDNQBT8egxF040FTUqCCDYIwggYAMIID6KADAgECAhMzAAAAww6b
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
# SEXAQsmbdlsKgEhr/Xmfwb1tbWrJUnMTDXpQzTGCFeIwghXeAgEBMIGVMH4xCzAJ
# BgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25k
# MR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xKDAmBgNVBAMTH01pY3Jv
# c29mdCBDb2RlIFNpZ25pbmcgUENBIDIwMTECEzMAAADDDpun2LLc9ywAAAAAAMMw
# DQYJYIZIAWUDBAIBBQCggdQwGQYJKoZIhvcNAQkDMQwGCisGAQQBgjcCAQQwHAYK
# KwYBBAGCNwIBCzEOMAwGCisGAQQBgjcCARUwLwYJKoZIhvcNAQkEMSIEIIP7tEYr
# qJb7GeYFuHnwRpUGG2RrR+YcCqRebngc4srlMGgGCisGAQQBgjcCAQwxWjBYoDqA
# OABDAG8AbQBtAG8AbgBSAG8AbABsAGIAYQBjAGsAVQB0AGkAbABpAHQAaQBlAHMA
# LgBwAHMAbQAxoRqAGGh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbTANBgkqhkiG9w0B
# AQEFAASCAQCNzHV5IiLSOrNeMBScQjSbWzWaLJfPlsWC0I8HWogWMp5Mw5pgSfG0
# u1plsSVcdMfx6OwZH8afeLSgG6XX8obbC33Jnbao0rLpxbs3YAM/7Ry64KETVhm6
# rcX5NrrBkl1QFLRZRcF2dNaoupVPGiiqKMtrOj64wmj/6i76tUe/frs2zQhTc+0+
# wcSUnk9+pfPMrOLb1vtLA8ARJng52x43KT6qI+7cAW3VV7QXyqMcK6KJgNdiijnr
# aO18TpuYLpdbmKXBYvtwAHTFHb96ODeba6ABmqMjJavQYPtUZZjNBLHbUgvVU88I
# ktDT3ohewcnH+SDH49biCd/UqCKGYu66oYITRjCCE0IGCisGAQQBgjcDAwExghMy
# MIITLgYJKoZIhvcNAQcCoIITHzCCExsCAQMxDzANBglghkgBZQMEAgEFADCCATsG
# CyqGSIb3DQEJEAEEoIIBKgSCASYwggEiAgEBBgorBgEEAYRZCgMBMDEwDQYJYIZI
# AWUDBAIBBQAEIKB4XduqhVQREpSFzHXOEVCtWJT4sElRZ1SQD/hvO6RqAgZasq/A
# D6sYEzIwMTgwMzI1MjEwNTU2LjIwMVowBwIBAYACAfSggbekgbQwgbExCzAJBgNV
# BAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4w
# HAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xDDAKBgNVBAsTA0FPQzEmMCQG
# A1UECxMdVGhhbGVzIFRTUyBFU046NzBERC00QjVCLTQ1NjgxJTAjBgNVBAMTHE1p
# Y3Jvc29mdCBUaW1lLVN0YW1wIFNlcnZpY2Wggg7LMIIGcTCCBFmgAwIBAgIKYQmB
# KgAAAAAAAjANBgkqhkiG9w0BAQsFADCBiDELMAkGA1UEBhMCVVMxEzARBgNVBAgT
# Cldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29m
# dCBDb3Jwb3JhdGlvbjEyMDAGA1UEAxMpTWljcm9zb2Z0IFJvb3QgQ2VydGlmaWNh
# dGUgQXV0aG9yaXR5IDIwMTAwHhcNMTAwNzAxMjEzNjU1WhcNMjUwNzAxMjE0NjU1
# WjB8MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMH
# UmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSYwJAYDVQQD
# Ex1NaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0EgMjAxMDCCASIwDQYJKoZIhvcNAQEB
# BQADggEPADCCAQoCggEBAKkdDbx3EYo6IOz8E5f1+n9plGt0VBDVpQoAgoX77Xxo
# SyxfxcPlYcJ2tz5mK1vwFVMnBDEfQRsalR3OCROOfGEwWbEwRA/xYIiEVEMM1024
# OAizQt2TrNZzMFcmgqNFDdDq9UeBzb8kYDJYYEbyWEeGMoQedGFnkV+BVLHPk0yS
# wcSmXdFhE24oxhr5hoC732H8RsEnHSRnEnIaIYqvS2SJUGKxXf13Hz3wV3WsvYpC
# TUBR0Q+cBj5nf/VmwAOWRH7v0Ev9buWayrGo8noqCjHw2k4GkbaICDXoeByw6ZnN
# POcvRLqn9NxkvaQBwSAJk3jN/LzAyURdXhacAQVPIk0CAwEAAaOCAeYwggHiMBAG
# CSsGAQQBgjcVAQQDAgEAMB0GA1UdDgQWBBTVYzpcijGQ80N7fEYbxTNoWoVtVTAZ
# BgkrBgEEAYI3FAIEDB4KAFMAdQBiAEMAQTALBgNVHQ8EBAMCAYYwDwYDVR0TAQH/
# BAUwAwEB/zAfBgNVHSMEGDAWgBTV9lbLj+iiXGJo0T2UkFvXzpoYxDBWBgNVHR8E
# TzBNMEugSaBHhkVodHRwOi8vY3JsLm1pY3Jvc29mdC5jb20vcGtpL2NybC9wcm9k
# dWN0cy9NaWNSb29DZXJBdXRfMjAxMC0wNi0yMy5jcmwwWgYIKwYBBQUHAQEETjBM
# MEoGCCsGAQUFBzAChj5odHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20vcGtpL2NlcnRz
# L01pY1Jvb0NlckF1dF8yMDEwLTA2LTIzLmNydDCBoAYDVR0gAQH/BIGVMIGSMIGP
# BgkrBgEEAYI3LgMwgYEwPQYIKwYBBQUHAgEWMWh0dHA6Ly93d3cubWljcm9zb2Z0
# LmNvbS9QS0kvZG9jcy9DUFMvZGVmYXVsdC5odG0wQAYIKwYBBQUHAgIwNB4yIB0A
# TABlAGcAYQBsAF8AUABvAGwAaQBjAHkAXwBTAHQAYQB0AGUAbQBlAG4AdAAuIB0w
# DQYJKoZIhvcNAQELBQADggIBAAfmiFEN4sbgmD+BcQM9naOhIW+z66bM9TG+zwXi
# qf76V20ZMLPCxWbJat/15/B4vceoniXj+bzta1RXCCtRgkQS+7lTjMz0YBKKdsxA
# QEGb3FwX/1z5Xhc1mCRWS3TvQhDIr79/xn/yN31aPxzymXlKkVIArzgPF/UveYFl
# 2am1a+THzvbKegBvSzBEJCI8z+0DpZaPWSm8tv0E4XCfMkon/VWvL/625Y4zu2Jf
# mttXQOnxzplmkIz/amJ/3cVKC5Em4jnsGUpxY517IW3DnKOiPPp/fZZqkHimbdLh
# nPkd/DjYlPTGpQqWhqS9nhquBEKDuLWAmyI4ILUl5WTs9/S/fmNZJQ96LjlXdqJx
# qgaKD4kWumGnEcua2A5HmoDF0M2n0O99g/DhO3EJ3110mCIIYdqwUB5vvfHhAN/n
# MQekkzr3ZUd46PioSKv33nJ+YWtvd6mBy6cJrDm77MbL2IK0cs0d9LiFAR6A+xuJ
# KlQ5slvayA1VmXqHczsI5pgt6o3gMy4SKfXAL1QnIffIrE7aKLixqduWsqdCosnP
# GUFN4Ib5KpqjEWYw07t0MkvfY3v1mYovG8chr1m1rtxEPJdQcdeh0sVV42neV8HR
# 3jDA/czmTfsNv11P6Z0eGTgvvM9YBS7vDaBQNdrvCScc1bN+NR4Iuto229Nfj950
# iEkSMIIE2DCCA8CgAwIBAgITMwAAALf4IhR9AyL++gAAAAAAtzANBgkqhkiG9w0B
# AQsFADB8MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UE
# BxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSYwJAYD
# VQQDEx1NaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0EgMjAxMDAeFw0xNzEwMDIyMzAw
# NTJaFw0xOTAxMDIyMzAwNTJaMIGxMQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2Fz
# aGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENv
# cnBvcmF0aW9uMQwwCgYDVQQLEwNBT0MxJjAkBgNVBAsTHVRoYWxlcyBUU1MgRVNO
# OjcwREQtNEI1Qi00NTY4MSUwIwYDVQQDExxNaWNyb3NvZnQgVGltZS1TdGFtcCBT
# ZXJ2aWNlMIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAtIV2Zy5+zQJd
# UAsSfGQTNy72V6DaEzWh4oMtVkjQ3K/Iyj7Fa62+ZK2RJcDPnYtRuN3n4uZNzthE
# jxtfBPp63WjCa5zqH/nwsF0S4heF3Uzl0CNoM7cPRMFZWJ3X9Hc3SWeO+9cbZiSY
# wTQNhpABO5iUD1wLfklCx4fHyB68D98VcE/C8uDTcCVqs5Z9dVNyZtTUrFDOvGXQ
# qocQbkR9BOKzL5nA8MY52p84pO86u9aENniLuBxfwqb/4Xu0RtkSmdrgcJKJvGAR
# HYrlAaBLm5FyUgc0S9EGUWy1mmA7PX2DM1VefZIzWJEvN334zjprO+2bIw8QJ2o6
# XL7m2tieOwIDAQABo4IBGzCCARcwHQYDVR0OBBYEFG1ir4N7RIZ1cXfSTVuP7kQu
# YDVpMB8GA1UdIwQYMBaAFNVjOlyKMZDzQ3t8RhvFM2hahW1VMFYGA1UdHwRPME0w
# S6BJoEeGRWh0dHA6Ly9jcmwubWljcm9zb2Z0LmNvbS9wa2kvY3JsL3Byb2R1Y3Rz
# L01pY1RpbVN0YVBDQV8yMDEwLTA3LTAxLmNybDBaBggrBgEFBQcBAQROMEwwSgYI
# KwYBBQUHMAKGPmh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2kvY2VydHMvTWlj
# VGltU3RhUENBXzIwMTAtMDctMDEuY3J0MAwGA1UdEwEB/wQCMAAwEwYDVR0lBAww
# CgYIKwYBBQUHAwgwDQYJKoZIhvcNAQELBQADggEBAGmkqdLrsaKfiuZ7JHu0J+7e
# eqI2Vog1VRyH2bzb+wEZTMRAnnTPjv84cEcI4Q/43zx8MFrIIO9OdodSWig8Zweq
# 8SFiZDb1N/lKG7KY2kg2mRXUVKU01txA6c1oRrP/kiGpoIPlFGQviVWBeZjAHe2+
# mHTMVAPmAHfNtzTR3sKVJRG96JOkJWn0/SWXjqrvU08wjnC/qdlnjmdPe3XqsfW3
# jHeOofSlMqYH9vD6Y3UjnIFmUZr4llbum+L+OOeOtDTiAxkA8AYaGDrtVzE/ysY5
# 0T968uU6vvrOESNEHoMKcSieo6WBkP12jYY4ZHIdsKy1gvOHiIzqq1OCldjh+Gmh
# ggN2MIICXgIBATCB4aGBt6SBtDCBsTELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldh
# c2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBD
# b3Jwb3JhdGlvbjEMMAoGA1UECxMDQU9DMSYwJAYDVQQLEx1UaGFsZXMgVFNTIEVT
# Tjo3MERELTRCNUItNDU2ODElMCMGA1UEAxMcTWljcm9zb2Z0IFRpbWUtU3RhbXAg
# U2VydmljZaIlCgEBMAkGBSsOAwIaBQADFQDV49D+WTbkwmRZSQfp1yKMx0XqDaCB
# wTCBvqSBuzCBuDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAO
# BgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEM
# MAoGA1UECxMDQU9DMScwJQYDVQQLEx5uQ2lwaGVyIE5UUyBFU046MjY2NS00QzNG
# LUM1REUxKzApBgNVBAMTIk1pY3Jvc29mdCBUaW1lIFNvdXJjZSBNYXN0ZXIgQ2xv
# Y2swDQYJKoZIhvcNAQEFBQACBQDeYoenMCIYDzIwMTgwMzI1MjA0MDA3WhgPMjAx
# ODAzMjYyMDQwMDdaMHcwPQYKKwYBBAGEWQoEATEvMC0wCgIFAN5ih6cCAQAwCgIB
# AAICJ3ACAf8wBwIBAAICGHAwCgIFAN5j2ScCAQAwNgYKKwYBBAGEWQoEAjEoMCYw
# DAYKKwYBBAGEWQoDAaAKMAgCAQACAxbjYKEKMAgCAQACAx6EgDANBgkqhkiG9w0B
# AQUFAAOCAQEAGge5yd9qflKfqybV2bCApjLpffwYXEQT+0y+xVED1527hv72GqHd
# CAbGN3iqm/MNJiSkkHMX+sR0s0iYcWAcfkT+p/A8ecqZ8+BntSnRgIky5dS4l1Tu
# tm62xpbwRn7mVOi+jB/DDAVE3KGQj0YQjDbioIxhtuAaLFthZnYokDGo2mZzuinM
# hmYhOjSX6EbAvrzcWixyMrVQXdDrqfX88yzJcdP12sZBSv6LzzyR78fhzaTfO70D
# paHkGcbmohXPdxfStTpikYgls0HvRQc+EXxf5j9S3Ql33Ey8wYgTv+t14WwHRR2U
# St5ZZd+RJFUsVc+Ou27qXmgC8f+vfBgt5DGCAvUwggLxAgEBMIGTMHwxCzAJBgNV
# BAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4w
# HAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xJjAkBgNVBAMTHU1pY3Jvc29m
# dCBUaW1lLVN0YW1wIFBDQSAyMDEwAhMzAAAAt/giFH0DIv76AAAAAAC3MA0GCWCG
# SAFlAwQCAQUAoIIBMjAaBgkqhkiG9w0BCQMxDQYLKoZIhvcNAQkQAQQwLwYJKoZI
# hvcNAQkEMSIEIHDrI7WSJ+SY0pZZGcnBDfXLJXjzL4QfWqaLQEgqbRlKMIHiBgsq
# hkiG9w0BCRACDDGB0jCBzzCBzDCBsQQU1ePQ/lk25MJkWUkH6dcijMdF6g0wgZgw
# gYCkfjB8MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UE
# BxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSYwJAYD
# VQQDEx1NaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0EgMjAxMAITMwAAALf4IhR9AyL+
# +gAAAAAAtzAWBBTcFdd75IjHNZEZ4MTLKywSp0RTCzANBgkqhkiG9w0BAQsFAASC
# AQBW+HjZkNrsfQukwXeQZdV4xHXena78jVpeB0j76O1ig1PZdezMBNCm/z3xURrK
# /KQaXaWCrG/syIRR7Iq6S6JxToHlCMDX0RvXKeOyiEfY/dREnUrgntFwpjNdQOFR
# OnaVTkNfzdz1M1hksJ0CLR9wY5U6+nsB0mKkBBjYMWCZONFrc3ygHyTlTMYHVIYS
# HnuMHpBVW7auHvDlesna/kNt767KdclI99U5S2f/D0D5o5hyjymLKCNSo3xhXsxe
# 2wsk09rp+8Y+UO+DbXNox2K5AfftmdKnrNhPXIWH8G45IXSL0ZSQB4vWD+ICBTTZ
# 7uJPnuf7rAl31r2aMyui2IVl
# SIG # End signature block
