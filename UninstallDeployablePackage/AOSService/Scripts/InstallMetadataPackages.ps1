param
(
    [switch]$multibox,
    [Parameter(Mandatory=$false)]
    [string]$relatedFilesDir,
    [Parameter(Mandatory=$false)]
    [string]$targetDirectory,
    [Parameter(Mandatory=$false)]
    [string]$deploymentDir,
	[Parameter(Mandatory=$false)]
    [string]$LogDir,
    [switch]$useServiceFabric = $false,
    [Parameter(Mandatory=$false)]
    [string]$webroot,
    [Parameter(Mandatory=$false)]
    [string]$aosPackageDirectory,
    [Parameter(Mandatory=$false)]
    [string]$sourcePackageDirectory,
    [Parameter(Mandatory=$false)]
    [switch] $useStaging
)

$Global:installedPackages=@()

function GenerateSymLinkNgen([string]$webroot,[string]$metadataPackagePath)
{
    if($useServiceFabric)
    {
        $DeveloperBox = $false
    }
    else
    {
        $DeveloperBox = Get-DevToolsInstalled
    }
    if(!($DeveloperBox))
    { 
        write-output "Updating Symlink and Ngen Assemblies"
        $SymLinkNgenLog = join-path $LogDir "update_SymLink_NgenAssemblies.log"
        $argumentList = '–webroot:"$webroot" –packagedir:"$metadataPackagePath" –log:"$SymLinkNgenLog"'
			
	    $NgenoutPutLog=join-path $LogDir "update_NgenOutput_$datetime.log"
  
		if(!(Test-Path $NgenoutPutLog)){
			New-Item -ItemType file $NgenoutPutLog -Force
        }

        invoke-Expression "$metadataPackagePath\bin\CreateSymLinkAndNgenAssemblies.ps1 $argumentList" >> $NgenoutPutLog
	}
}

function UpdateAdditionalFiles([string]$webRoot,[string]$packageDir)
{
    $directorys = Get-ChildItem $packageDir -Directory
    foreach ($moduleName in $directorys) 
    {
        $modulePath=Join-Path $packageDir $moduleName
        $additionalFilesDir=join-path $modulePath "AdditionalFiles"

        if(Test-Path $additionalFilesDir)
        {
            Write-log "Processing additional files for '$moduleName' "
            $filelocationsfile=join-path "$modulePath" "FileLocations.xml"
            if(Test-Path "$filelocationsfile")
            {
                [System.Xml.XmlDocument] $xd = new-object System.Xml.XmlDocument
                $xd.Load($filelocationsfile)
                $files=$xd.SelectNodes("//AdditionalFiles/File")
                foreach($file in $files)
                {
                    $assembly=[System.IO.Path]::GetFileName($file.Source)
                    $destination=$file.Destination
                    $relativepath=$file.RelativePath
                    $fullassemblypath=join-path "$modulePath" "AdditionalFiles\$assembly"

                    # the reason why we need to check for IsNullorEmpty() for the parameters is because the c:\pakages\bin
                    # comes from both the platform and app side. If the app bin package gets installed first
                    # it will leave a FileLocations.xml file at c:\packages\bin which will be processed by the 
                    # platform bin package when it gets installed. We want to ensure that we do not throw an exception
                    # even if we don't find the correct set of parameters being passed from the calling function. 
                    switch($destination)
                    {
                        "AOSWeb" #enum for AOS webroot
                        {
                            $target=join-path "$webRoot" "$relativepath"
                        }

                        "PackageBin" #enum for \packages\bin
                        {
                            if(-not [string]::IsNullOrEmpty($packageDir))
                            {   
                                $target=join-path "$packageDir" "bin"
                            }
                        }

                        "ModuleBin" #enum for \<<modulename>>\bin
                        {
                            $target=join-path "$modulePath" "bin"
                        }

		                "PackageDir" #enum for \packages\<<relativepath>>
		                {
                            if(-not [string]::IsNullOrEmpty($packageDir))
                            {
			                    $target=join-path "$packageDir" "$relativepath"
                            }
		                }
                    }

                    if((Test-Path "$fullassemblypath") -and (-not [string]::IsNullOrEmpty($target)))
                    {
                        if(!(Test-Path "$target"))
                        {
                            Write-log "Creating target directory '$target'"
                            New-item -Path "$target" -ItemType "directory" -Force
                        }

                        $targetfile=join-path "$target" $assembly
                        Write-log "Copying '$fullassemblypath' to '$targetfile'"
                        Copy-Item -path:"$fullassemblypath" -destination:"$targetfile" -Force
                    }
                }
            }   

            Write-log "Removing '$additionalFilesDir'..."
            Remove-Item -Path $additionalFilesDir -Recurse -Force|out-null
        } 
    }
}

function Update-PackageReferenceFile([string]$metadataPath,[string]$packageZipPath)
{
    $ErrorActionPreference = "stop"
    $7zip=join-path $env:SystemDrive "DynamicsTools\7za.exe"
    $guid=[System.Guid]::NewGuid()
    $tempdir=[System.IO.Path]::GetTempPath()+$guid
    $temppackagesdir=join-path $tempdir "DynamicsAx-Package-Reference"
   
    if(Test-Path $packageZipPath)
    {
        if(!(Test-Path $temppackagesdir)){
           
            New-Item $temppackagesdir -ItemType directory -Force >$null
        }
    
        $zip = Start-Process $7zip -ArgumentList "x $packageZipPath -o$temppackagesdir -y -mmt" -Wait -WindowStyle Hidden -PassThru
	    if($zip.ExitCode -ne "0")
	    {
		    throw "7Zip failed to extract dynamicss packages reference file."
	    }

        $directorys = Get-ChildItem $temppackagesdir -Directory
        foreach ($directory in $directorys) 
        {
            $TargetReferenceUpdateDirectory = join-path $metadataPath $directory.Name
            if(Test-Path $TargetReferenceUpdateDirectory)
            {
                Copy-Item -Path ([IO.Path]::Combine($directory.FullName,"*")) -Destination $TargetReferenceUpdateDirectory -Force -Recurse
            }
        
        }

        if(Test-Path $temppackagesdir) {
            Remove-Item $temppackagesdir -recurse -force
        } 
    }
}

function Install-Package([string]$packageName,[string]$metadataPath,[string]$source,[string]$log)
{
    $ErrorActionPreference = "stop"

    $dynamicstools="DynamicsTools"
    $installationrecords = Join-Path $metadataPath "InstallationRecords"
    $packageinstallationrecord = Join-Path $installationrecords $packageName
   
    $nuget=join-path $env:SystemDrive "$dynamicstools\nuget.exe"
    
    "removing package installation record $packageinstallationrecord.*" >> $log
    get-childitem -path "$installationrecords" -filter "$packageName.*" | remove-item -force -recurse

    "Unpacking the Dynamics packages to $installationrecords" >> $log

    "Running command: $nuget install -OutputDirectory `"$installationrecords`" $packageName -Source $source" >> $log
    if([System.Version]([System.Diagnostics.FileVersionInfo]::GetVersionInfo($nuget).FileVersion) -ge [System.Version]"2.9.0.0")
    {
        & $nuget install -OutputDirectory "$installationrecords" $packageName -Source $source -DependencyVersion highest #nuget version > 2.8 change behaviour and add a new switch to set it back
    }
    else
    {
        & $nuget install -OutputDirectory "$installationrecords" $packageName -Source $source
    }
    # check the last exit code and decide if the package(s) were installed correctly
    if($LASTEXITCODE -ne 0)
    {
        Throw "Something went wrong when installing the Dynamics package '$packageName'. Make sure the package name is correct and that it exists at the source directory '$source'."
    }
    
} 

function Install-ZipPackage ([string]$clickoncePath,[string]$metadataPath,[string]$frameworkPath,[string]$packageZipPath,[string]$source,[string]$webroot,[string]$log)
{
    $ErrorActionPreference = "stop"

    #install package
    $arguments='clickOnceInstallPath="{0}";metadataInstallPath="{1}";frameworkInstallPath="{2}";packageZipDrop="{3}";webroot="{4}";log="{5}"' -f $clickoncePath,$metadataPath,$frameworkPath,$packageZipPath,$webroot,$log
    $arguments
    $env:DynamicsPackageParameters=$arguments
    $dynamicstools="DynamicsTools"
    $installationrecords = Join-Path $metadataPath "InstallationRecords"
    $packageinstallationrecord = Join-Path $installationrecords $packageName

    # iterate over every installed package and run the custom powershell script
    $packagesdir=[System.IO.Directory]::EnumerateDirectories($installationrecords,"*",[System.IO.SearchOption]::TopDirectoryOnly)
    foreach ($dir in $packagesdir){
        $currentpackagename=[System.IO.Path]::GetFileName($dir)
        $toolsdir=Join-Path $dir "tools"
        $installscript=join-path $toolsdir "installpackage.ps1"
        if(Test-Path $installscript){ 
           $Global:installedPackages+=$currentpackagename

        }     
    }
    Parallel-Install -packagesName:$Global:installedPackages -installationrecorddir:$installationrecords
}


function Remove-MetadataSourceDirectory([string] $packageName, [string] $packageInstallPath)
{
    $basePackageName = $($packageName.split('-')[1])
    
    if ($packageName.EndsWith('-compile'))
    {
        $packageInstallPath = Join-Path $packageInstallPath $basePackageName
        $packageInstallPath = Join-Path $packageInstallPath 'XppMetadata'
        if(Test-Path $packageInstallPath)
        {
            #powershell bug - Remove-Item comlet doesn't implement -Recurse correctly
            #Remove-Item $packageInstallPath -Force -Recurse
            get-childitem -path "$packageInstallPath" -recurse | remove-item -force -recurse
        }
    }
    if ($packageName.EndsWith('-develop'))
    {
        $packageInstallPath = Join-Path $packageInstallPath $basePackageName
        $packageInstallPath = Join-Path $packageInstallPath $basePackageName
        if(Test-Path $packageInstallPath)
        {
            #powershell bug - Remove-Item comlet doesn't implement -Recurse correctly
            #Remove-Item $packageInstallPath -Force -Recurse
            get-childitem -path "$packageInstallPath" -recurse | remove-item -force -recurse
        }
    }
}

workflow Parallel-Install([string[]] $packagesName, [string] $installationrecorddir)
{
    $ErrorActionPreference = "stop"
    foreach -parallel -ThrottleLimit 2 ($pkg in $packagesName){
        $dir = Join-Path $installationrecorddir $pkg
        $toolsdir=Join-Path $dir "tools"
        $installscript=join-path $toolsdir "installpackage.ps1"
        if(Test-Path $installscript){
            Write-Output "Running script '$installScript'"
            InlineScript {& $Using:installscript}
            Move-item $installscript ($installscript+".executed") -Force
        }
        
    }
}


if(!$useServiceFabric){
    Import-Module WebAdministration
}

Import-Module "$PSScriptRoot\CommonRollbackUtilities.psm1" -ArgumentList $useServiceFabric -DisableNameChecking
Import-Module "$PSScriptRoot\AosEnvironmentUtilities.psm1"  -ArgumentList $useServiceFabric -Force -DisableNameChecking

$ErrorActionPreference = "stop"

if($useStaging)
{
    $webroot = join-path $(Get-AosServiceStagingPath) "webroot"
    $metadataPackagePath = join-path $(Get-AosServiceStagingPath) "PackagesLocalDirectory"
    $frameworkPackagePath = join-path $(Get-AosServiceStagingPath) "PackagesLocalDirectory"
    $sourcePath = [IO.Path]::Combine($(split-Path -parent $PSScriptRoot), "Packages")
}
elseif($useServiceFabric)
{

    $webroot = (Resolve-Path $webroot).ProviderPath
    $clickOncePackagePath = join-path $webroot "apps"
    $sourcePath = $sourcePackageDirectory
    $metadataPackagePath = $aosPackageDirectory
    $frameworkPackagePath = $aosPackageDirectory
}
else
{
    $webroot = Get-AosWebSitePhysicalPath
    $metadataPackagePath = $(Get-AOSPackageDirectory)
    $frameworkPackagePath = $(Get-AOSPackageDirectory)  
    $sourcePath = [IO.Path]::Combine($(split-Path -parent $PSScriptRoot), "Packages")
}

if(!$useServiceFabric)
{
    $clickOncePackagePath = $(Get-InfrastructureClickonceAppsDirectory)
    $clickOncePackagePath = [IO.Path]::Combine($webroot,$clickOncePackagePath)
}

$resourcePath = [IO.Path]::Combine($webroot,"Resources")
$packageZipDrop = [IO.Path]::Combine($sourcePath,"files")

if((![string]::IsNullOrWhiteSpace($targetDirectory)) -and (Test-path $targetDirectory))
{
    $metadataPackagePath = $targetDirectory
    $frameworkPackagePath = $targetDirectory
}   

if((![string]::IsNullOrWhiteSpace($deploymentDir)) -and (Test-path $deploymentDir))
{
    if($multibox)
    {
        $clickOncePackagePath = [IO.Path]::Combine($deploymentDir,"WebRoot\apps")
        $webroot=[IO.Path]::Combine($deploymentDir,"WebRoot")
        $resourcePath = [IO.Path]::Combine($deploymentDir,"WebRoot\Resources")
    }
    else
    {
        $clickOncePackagePath = [IO.Path]::Combine($deploymentDir,"DObind\Packages\Cloud\AosWebApplication\AosWebApplication.csx\roles\AosWeb\approot\apps")
        $webroot=[IO.Path]::Combine($deploymentDir,"DObind\Packages\Cloud\AosWebApplication\AosWebApplication.csx\roles\AosWeb\approot")
        $resourcePath = [IO.Path]::Combine($deploymentDir,"DObind\Packages\Cloud\AosWebApplication\AosWebApplication.csx\roles\AosWeb\approot\Resources")
    }
}

if((![string]::IsNullOrWhiteSpace($relatedFilesDir)) -and (Test-Path $relatedFilesDir))
{
    $sourcePath = $relatedFilesDir
    $packageZipDrop = [IO.Path]::Combine($relatedFilesDir,"files")
}    

$datetime=get-date -Format "MMddyyyyhhmmss"

if(!$LogDir)
{
    $LogDir = $PSScriptRoot
}

$log=join-path $LogDir "install-AXpackages_$datetime.log"
  
if(!(Test-Path $log)){
    New-Item -ItemType file $log -Force
}

$innerlog=join-path $LogDir "update-AXpackages_$datetime.log"
  
if(!(Test-Path $innerlog)){
    New-Item -ItemType file $innerlog -Force
}


$startdatetime=get-date
"*******************************************************" >> $log
"** Starting the package deployment at $startdatetime **" >> $log
"*******************************************************" >> $log

$installationrecords = Join-Path -Path $metadataPackagePath -ChildPath "InstallationRecords"

if(!(Test-Path $installationrecords))
{
        "creating installation record directory '$installationrecords' to kept the installation history" >> $log
        New-Item $installationrecords -ItemType directory -Force
}
else
{               
    # clean up prior nuget installation of the previous package that fail to install
    $packagesdir=[System.IO.Directory]::EnumerateDirectories($installationrecords,"*",[System.IO.SearchOption]::TopDirectoryOnly)
    foreach ($dir in $packagesdir)
    {
        $toolsdir=Join-Path $dir "tools"
        $installscript=join-path $toolsdir "installpackage.ps1"
        if(Test-Path $installscript)
        {
            Move-item $installscript ($installscript+".executed") -Force
        }
    }
}



if($useServiceFabric)
{
    $DeveloperBox = $false
}
else
{
    $DeveloperBox = Get-DevToolsInstalled
}

#Check if this is a platform update package base on existence of the config file.
#if it's platformUpdate3 or later, also perform the meta package installation for platform binarys
if ((Test-Path "$PSScriptRoot\PlatformUpdatePackages.Config") -or (Get-IsPlatformUpdate3OrLater -webroot:$webroot))
{
    if(Test-Path $sourcePath)
    {
        [Void][Reflection.Assembly]::LoadWithPartialName('System.IO.Compression.FileSystem')
        if ($DeveloperBox -eq $true)
        {
            $PackageToInstall = "dynamicsax-meta-platform-development"
        }
        else
        {
            $PackageToInstall = "dynamicsax-meta-platform-runtime"
        }
        if(![string]::IsNullOrWhiteSpace($PackageToInstall))
        {
            $zipFile = Get-Item $sourcePath\$PackageToInstall*.nupkg
            if($zipFile -eq $null)
            {
                #only throw error if it's a dedicated inplace upgrade package, 
                #on any other package it's possible that the meta package doesn't existing thus no operation required
                if(Test-Path "$PSScriptRoot\PlatformUpdatePackages.Config")
                {
                    Throw "Unable to get package information"
                }

            }
            else
            {
                $PackFiles = [IO.Compression.ZipFile]::OpenRead($zipFile).Entries
                $PackageSpec =  $PackFiles | where {($_.Name -like '*.nuspec')}

                if(!($PackageSpec))
                {
                    Throw "Unable to get package information"
                }

                [System.Xml.XmlDocument] $xmlDoc=new-object System.Xml.XmlDocument
                $XmlDoc.Load($PackageSpec.Open())

                $Dependencies = $xmlDoc.GetElementsByTagName('dependency').id

                if($Dependencies.Contains("dynamicsax-systemhealth"))
                {
                    #Remove AxPulse due to the name change to SystemHealth in PlatUpdate3
                    $axPulsePath = Join-Path -Path $metadataPackagePath -ChildPath "axpulse"
                   
                    if(Test-Path $axPulsePath)
                    {
                        Remove-Item $axPulsePath -Force -Recurse
                    }
                    if(Test-Path $installationrecords)
                    {
                        get-childitem -path "$installationrecords" -filter "dynamicsax-axpulse.*" | remove-item -force -recurse 
                    }
                }

                #Install all packages in meta-package definition
                forEach ($Package in $Dependencies)
                {
                    #if it's not appFall or later, install directory package from platform
                    #all other platform package specified in meta package will get installed
                    if(($($package.Split("-")[1]) -ne 'Directory') -or (!$(Get-IsAppFallOrLater -webroot:$webroot)))
                    {
                        "removing package installation record $Package.*" >> $log
                        get-childitem -path "$installationrecords" -filter "$Package.*" | remove-item -force -recurse  
                        
                        #Remove MetaData and Source Directories for the package before Installing
                        Remove-MetadataSourceDirectory -packageName $Package -packageInstallPath $metadataPackagePath 
                    }
                }
                Install-Package -packageName:$PackageToInstall -metadataPath:$metadataPackagePath -source:$sourcePath -log:$log >> $innerlog
            }
        }
    }
}

#dependencyaos
#Install App packages if it is sealed
if($(Get-IsAppSealed -webroot:$webroot ))
{
    if(Test-Path $sourcePath)
    {
        [Void][Reflection.Assembly]::LoadWithPartialName('System.IO.Compression.FileSystem')   
        if($useServiceFabric)
        {
            $DeveloperBox = $false
        }
        else
        {
            $DeveloperBox = Get-DevToolsInstalled
        }
        if ($DeveloperBox -eq $true)
        {
            $PackageToInstall = "dynamicsax-meta-application-development"
        }
        else
        {
            $PackageToInstall = "dynamicsax-meta-application-runtime"
        }
        if(![string]::IsNullOrWhiteSpace($PackageToInstall))
        {
            $zipFile = Get-Item $sourcePath\$PackageToInstall*.nupkg

            if($zipFile -ne $null)
            {
                $PackFiles = [IO.Compression.ZipFile]::OpenRead($zipFile).Entries
                $PackageSpec =  $PackFiles | Where-Object {($_.Name -like "*.nuspec")}

                if(!($PackageSpec))
                {
                    Throw "Unable to get package information"
                }

                [System.Xml.XmlDocument] $xmlDoc=new-object System.Xml.XmlDocument
                $XmlDoc.Load($PackageSpec.Open())

                $Dependencies = $xmlDoc.GetElementsByTagName('dependency').id

                #Install all packages in meta-package definition
                forEach ($Package in $Dependencies)
                {
                    "removing package installation record $Package.*" >> $log
                    get-childitem -path "$installationrecords" -filter "$Package.*" | remove-item -force -recurse

                    #Remove MetaData and Source Directories for the package before Installing
                    Remove-MetadataSourceDirectory -packageName $Package -packageInstallPath $metadataPackagePath
                }
                Install-Package -packageName:$PackageToInstall -metadataPath:$metadataPackagePath -source:$sourcePath -log:$log >> $innerlog
            }  
        }
    }
}

#still need to perform the aot package installation that's not part of platform or app.
if(!(Test-Path "$PSScriptRoot\PlatformUpdatePackages.Config"))
{
    if(Test-Path $sourcePath)
    {
        $files=get-childitem -Path:$sourcePath *.nupkg
        foreach ($packageFile in $files) 
        {
            #if it's not platupdate3 or later, install all package
            #if it's platupdate3 or later, install all package that's not part of platform
            if($(Get-IsModulePartOfPlatformAsBinary -packageNugetFile $packageFile.FullName))
            {
                if(!$(Get-IsPlatformUpdate3OrLater -webroot:$webroot))
                {
                    Install-Package -packageName:($packageFile.BaseName).Split(".")[0] -metadataPath:$metadataPackagePath -source:$sourcePath -log:$log >> $innerlog
                }
            }
            # If app is not sealed, install all [Application Package]
            elseif(Get-IsModulePartOfApplicationAsBinary -PackageNugetFilePath $packageFile.FullName)
            {
                if(!$(Get-IsAppSealed -webroot:$webroot))
                {
                    Install-Package -packageName:($packageFile.BaseName).Split(".")[0] -metadataPath:$metadataPackagePath -source:$sourcePath -log:$log >> $innerlog
                }
            }
            # Allow customer extension
            else
            {
                Install-Package -packageName:($packageFile.BaseName).Split(".")[0] -metadataPath:$metadataPackagePath -source:$sourcePath -log:$log >> $innerlog
            }
        }
    }
}

Install-ZipPackage -metadataPath:$metadataPackagePath -clickoncePath:$clickOncePackagePath -frameworkPath:$frameworkPackagePath -packageZipPath:$packageZipDrop -source:$sourcePath -webroot:$webroot -log:$log >> $innerlog

write-output "Updating Metadata Resources File."
$UpdateResourcesLog = join-path $LogDir "update_Resources_$datetime.log"
$ResourceConfig = @{"Common.BinDir"= $metadataPackagePath; "Infrastructure.WebRoot"= $webroot}
$ResourceBase64Config = ConvertTo-Json $ResourceConfig
$ResourceBase64Config = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($ResourceBase64Config))
$argumentList = '–config:"$ResourceBase64Config" –log:"$UpdateResourcesLog"'

$Resourceslog=join-path $LogDir "update_ResourcesOutPut_$datetime.log"
  
if(!(Test-Path $Resourceslog)){
    New-Item -ItemType file $Resourceslog -Force
}

invoke-Expression "$PSScriptRoot\DeployResources.ps1 $argumentList" >> $ResoucesLog

write-output "Updating Metadata Reference File."
Update-PackageReferenceFile -metadataPath:$metadataPackagePath -packageZipPath:$(join-path $packageZipDrop "MetadataReferenceApp.zip")
Update-PackageReferenceFile -metadataPath:$metadataPackagePath -packageZipPath:$(join-path $packageZipDrop "MetadataReferencePlat.zip")

write-output "Updating Additional File."
UpdateAdditionalFiles -webRoot:$webroot -packageDir:$metadataPackagePath

try
{
    if(!$useServiceFabric)
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
}
 catch
{
    #always generate symlink point to the none staging folder of aos services
    GenerateSymLinkNgen -webroot:$webroot -metadataPackagePath:$(Get-AOSPackageDirectory)
}

if(!$useServiceFabric)
{
    write-output "Creating Metadata Module Installation Info."
    try
    {
        $CommonBin = $(Get-CommonBinDir)
        #using Add-Type which will auto load all referenced dll
        Add-Type -Path "$CommonBin\bin\Microsoft.Dynamics.AX.AXInstallationInfo.dll"
        [Microsoft.Dynamics.AX.AXInstallationInfo.AXInstallationInfo]::ScanMetadataModelInRuntimePackage($metadataPackagePath)
        
    }
    catch
    {
        write-warning "Failed to create metadata module installation record"
    }
}
$enddatetime=get-date
"******************************************************" >> $log
"** Completed the package deployment at $enddatetime **" >> $log
"******************************************************" >> $log
"" >> $log
$duration=$enddatetime-$startdatetime
"Package deployment duration:" >> $log 
"$duration" >> $log 
    
"" >> $log
"******************************************************" >> $log
"Packages installed in this session:" >> $log
"******************************************************" >> $log
foreach($pkg in $Global:installedPackages){
    "$pkg" >> $log
}

""
"******************************************************"
"Packages installed in this session:"
"******************************************************"
foreach($pkg in $Global:installedPackages){
    "$pkg"
}
""
"installation log file: $log"


# SIG # Begin signature block
# MIIkCQYJKoZIhvcNAQcCoIIj+jCCI/YCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCBFwrSIQpLGURr1
# cu3uT/fOsdxqeJ698m/MiqgEghHPdKCCDYIwggYAMIID6KADAgECAhMzAAAAww6b
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
# SEXAQsmbdlsKgEhr/Xmfwb1tbWrJUnMTDXpQzTGCFd0wghXZAgEBMIGVMH4xCzAJ
# BgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25k
# MR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xKDAmBgNVBAMTH01pY3Jv
# c29mdCBDb2RlIFNpZ25pbmcgUENBIDIwMTECEzMAAADDDpun2LLc9ywAAAAAAMMw
# DQYJYIZIAWUDBAIBBQCggdIwGQYJKoZIhvcNAQkDMQwGCisGAQQBgjcCAQQwHAYK
# KwYBBAGCNwIBCzEOMAwGCisGAQQBgjcCARUwLwYJKoZIhvcNAQkEMSIEIPbZk+Ve
# 6GzMfOLzOAe7+apBhaVN0fAZIu3VpM8zJBtBMGYGCisGAQQBgjcCAQwxWDBWoDiA
# NgBJAG4AcwB0AGEAbABsAE0AZQB0AGEAZABhAHQAYQBQAGEAYwBrAGEAZwBlAHMA
# LgBwAHMAMaEagBhodHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20wDQYJKoZIhvcNAQEB
# BQAEggEAO6FZoly8Sbp4jXa3sIT9P1nhe2vy7YTJlxQklsl2TWVt7JFPw8eW5JP3
# 47d/Mix11mqpL74XzcNMFBwcJvQWcFAnUIzEvJTW12XVsnHS4Jtpty5GHpPomDne
# Q+qVnhYi1Rh78tHxflqLDU5wsIBkq//fHFRg35p2kTJIDtWl8fF8m3iygYhOEXr2
# cPlc9kRMRgViTy8Sn7EKf8yF793c61kx+lYu80NDthCCLktbcSxZGSYeuP9D9b37
# b9/zb6Pb9YA5kxjeTs+lCZRvFQNnCPwvpoRS+fnjOfdF9sB4T4y76GaLUY9reG+/
# o4mowitMsqkLUvcig3u86Dyz0fQMXaGCE0MwghM/BgorBgEEAYI3AwMBMYITLzCC
# EysGCSqGSIb3DQEHAqCCExwwghMYAgEDMQ8wDQYJYIZIAWUDBAIBBQAwggE7Bgsq
# hkiG9w0BCRABBKCCASoEggEmMIIBIgIBAQYKKwYBBAGEWQoDATAxMA0GCWCGSAFl
# AwQCAQUABCBKgXDK3geZsvkMWKadwYd1efl9UeWZuxxZLjydxuhu9gIGWrKlzVRr
# GBMyMDE4MDMyNTIxMDU0OC44MDFaMAcCAQGAAgH0oIG3pIG0MIGxMQswCQYDVQQG
# EwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwG
# A1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMQwwCgYDVQQLEwNBT0MxJjAkBgNV
# BAsTHVRoYWxlcyBUU1MgRVNOOkMzQjAtMEY2QS00MTExMSUwIwYDVQQDExxNaWNy
# b3NvZnQgVGltZS1TdGFtcCBTZXJ2aWNloIIOyDCCBnEwggRZoAMCAQICCmEJgSoA
# AAAAAAIwDQYJKoZIhvcNAQELBQAwgYgxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpX
# YXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQg
# Q29ycG9yYXRpb24xMjAwBgNVBAMTKU1pY3Jvc29mdCBSb290IENlcnRpZmljYXRl
# IEF1dGhvcml0eSAyMDEwMB4XDTEwMDcwMTIxMzY1NVoXDTI1MDcwMTIxNDY1NVow
# fDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1Jl
# ZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEmMCQGA1UEAxMd
# TWljcm9zb2Z0IFRpbWUtU3RhbXAgUENBIDIwMTAwggEiMA0GCSqGSIb3DQEBAQUA
# A4IBDwAwggEKAoIBAQCpHQ28dxGKOiDs/BOX9fp/aZRrdFQQ1aUKAIKF++18aEss
# X8XD5WHCdrc+Zitb8BVTJwQxH0EbGpUdzgkTjnxhMFmxMEQP8WCIhFRDDNdNuDgI
# s0Ldk6zWczBXJoKjRQ3Q6vVHgc2/JGAyWGBG8lhHhjKEHnRhZ5FfgVSxz5NMksHE
# pl3RYRNuKMYa+YaAu99h/EbBJx0kZxJyGiGKr0tkiVBisV39dx898Fd1rL2KQk1A
# UdEPnAY+Z3/1ZsADlkR+79BL/W7lmsqxqPJ6Kgox8NpOBpG2iAg16HgcsOmZzTzn
# L0S6p/TcZL2kAcEgCZN4zfy8wMlEXV4WnAEFTyJNAgMBAAGjggHmMIIB4jAQBgkr
# BgEEAYI3FQEEAwIBADAdBgNVHQ4EFgQU1WM6XIoxkPNDe3xGG8UzaFqFbVUwGQYJ
# KwYBBAGCNxQCBAweCgBTAHUAYgBDAEEwCwYDVR0PBAQDAgGGMA8GA1UdEwEB/wQF
# MAMBAf8wHwYDVR0jBBgwFoAU1fZWy4/oolxiaNE9lJBb186aGMQwVgYDVR0fBE8w
# TTBLoEmgR4ZFaHR0cDovL2NybC5taWNyb3NvZnQuY29tL3BraS9jcmwvcHJvZHVj
# dHMvTWljUm9vQ2VyQXV0XzIwMTAtMDYtMjMuY3JsMFoGCCsGAQUFBwEBBE4wTDBK
# BggrBgEFBQcwAoY+aHR0cDovL3d3dy5taWNyb3NvZnQuY29tL3BraS9jZXJ0cy9N
# aWNSb29DZXJBdXRfMjAxMC0wNi0yMy5jcnQwgaAGA1UdIAEB/wSBlTCBkjCBjwYJ
# KwYBBAGCNy4DMIGBMD0GCCsGAQUFBwIBFjFodHRwOi8vd3d3Lm1pY3Jvc29mdC5j
# b20vUEtJL2RvY3MvQ1BTL2RlZmF1bHQuaHRtMEAGCCsGAQUFBwICMDQeMiAdAEwA
# ZQBnAGEAbABfAFAAbwBsAGkAYwB5AF8AUwB0AGEAdABlAG0AZQBuAHQALiAdMA0G
# CSqGSIb3DQEBCwUAA4ICAQAH5ohRDeLG4Jg/gXEDPZ2joSFvs+umzPUxvs8F4qn+
# +ldtGTCzwsVmyWrf9efweL3HqJ4l4/m87WtUVwgrUYJEEvu5U4zM9GASinbMQEBB
# m9xcF/9c+V4XNZgkVkt070IQyK+/f8Z/8jd9Wj8c8pl5SpFSAK84Dxf1L3mBZdmp
# tWvkx872ynoAb0swRCQiPM/tA6WWj1kpvLb9BOFwnzJKJ/1Vry/+tuWOM7tiX5rb
# V0Dp8c6ZZpCM/2pif93FSguRJuI57BlKcWOdeyFtw5yjojz6f32WapB4pm3S4Zz5
# Hfw42JT0xqUKloakvZ4argRCg7i1gJsiOCC1JeVk7Pf0v35jWSUPei45V3aicaoG
# ig+JFrphpxHLmtgOR5qAxdDNp9DvfYPw4TtxCd9ddJgiCGHasFAeb73x4QDf5zEH
# pJM692VHeOj4qEir995yfmFrb3epgcunCaw5u+zGy9iCtHLNHfS4hQEegPsbiSpU
# ObJb2sgNVZl6h3M7COaYLeqN4DMuEin1wC9UJyH3yKxO2ii4sanblrKnQqLJzxlB
# TeCG+SqaoxFmMNO7dDJL32N79ZmKLxvHIa9Zta7cRDyXUHHXodLFVeNp3lfB0d4w
# wP3M5k37Db9dT+mdHhk4L7zPWAUu7w2gUDXa7wknHNWzfjUeCLraNtvTX4/edIhJ
# EjCCBNgwggPAoAMCAQICEzMAAACtgCM3ZcRaI2oAAAAAAK0wDQYJKoZIhvcNAQEL
# BQAwfDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcT
# B1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEmMCQGA1UE
# AxMdTWljcm9zb2Z0IFRpbWUtU3RhbXAgUENBIDIwMTAwHhcNMTYwOTA3MTc1NjU1
# WhcNMTgwOTA3MTc1NjU1WjCBsTELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hp
# bmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jw
# b3JhdGlvbjEMMAoGA1UECxMDQU9DMSYwJAYDVQQLEx1UaGFsZXMgVFNTIEVTTjpD
# M0IwLTBGNkEtNDExMTElMCMGA1UEAxMcTWljcm9zb2Z0IFRpbWUtU3RhbXAgU2Vy
# dmljZTCCASIwDQYJKoZIhvcNAQEBBQADggEPADCCAQoCggEBAO2zDf5lGt2NsVXv
# Rym+KFTjFQLByzq2Wh6ejANxzNtKrOeNVL9eofo1ARQi/FyT70eal7jqau/R6qeq
# JblHXObJa9O0B5oG8ueyNMiLGHvYdbV4aUUM11IijLEQEqm7Jlo+v0ZSGjlhSAuU
# WniibqkoXHFBrT6DVoMkLKHVqfDFvm/c9u8SVqcy6+nLx6kkflGbefoHa7cmCgMw
# rKi2M7pErRo3g5dXK4SQaDTBgH8eUWDJ1X42CrKp+T60frfehPeb8U+oJgjmGKYq
# AllxzMGX+CliedfWzk12z//BFQHmk5hgkdNqBYksIAGH3BA9Ost2rIOdEAn8hw2c
# rlyZ/acCAwEAAaOCARswggEXMB0GA1UdDgQWBBRkIbrAL6z4nMcMlOXnH8kK1rz9
# azAfBgNVHSMEGDAWgBTVYzpcijGQ80N7fEYbxTNoWoVtVTBWBgNVHR8ETzBNMEug
# SaBHhkVodHRwOi8vY3JsLm1pY3Jvc29mdC5jb20vcGtpL2NybC9wcm9kdWN0cy9N
# aWNUaW1TdGFQQ0FfMjAxMC0wNy0wMS5jcmwwWgYIKwYBBQUHAQEETjBMMEoGCCsG
# AQUFBzAChj5odHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20vcGtpL2NlcnRzL01pY1Rp
# bVN0YVBDQV8yMDEwLTA3LTAxLmNydDAMBgNVHRMBAf8EAjAAMBMGA1UdJQQMMAoG
# CCsGAQUFBwMIMA0GCSqGSIb3DQEBCwUAA4IBAQAShUe51J2YxHxkbrWquE1TiiKG
# 3HaVdV0ijzd1PF72pW86jRl/u+qUNP4gpmpUNk80VP8AA5VUJvN5Z+/xwBj66bcw
# 7Xf/aXTaM4QRDpOvgRjHJVq4hdZgobRrWzOj/rSGGCTYIZVb7pAVxtlj7tSk2Pnk
# et1LsnOsFrmgwAQW7zV1O1A8+WF23AHoCx9mUBrdqllPTIPYxYcEQiJ3qMr3TaWu
# GpHFxx0gfCFYdVOvTyW64sy4cHDjWmFdXKzja/yM06w4P2I/JmDDeaaVdfyP/OYt
# LJR9AtEb7sN/pMHZpEYiN9evf5i6Xvd3k12rC68UUE7pZkEvOeqE4xd5+VxUoYID
# czCCAlsCAQEwgeGhgbekgbQwgbExCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNo
# aW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29y
# cG9yYXRpb24xDDAKBgNVBAsTA0FPQzEmMCQGA1UECxMdVGhhbGVzIFRTUyBFU046
# QzNCMC0wRjZBLTQxMTExJTAjBgNVBAMTHE1pY3Jvc29mdCBUaW1lLVN0YW1wIFNl
# cnZpY2WiJQoBATAJBgUrDgMCGgUAAxUAnBjmGt8bA4gXXRzGxyxLmq/hMNmggcEw
# gb6kgbswgbgxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYD
# VQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xDDAK
# BgNVBAsTA0FPQzEnMCUGA1UECxMebkNpcGhlciBOVFMgRVNOOjI2NjUtNEMzRi1D
# NURFMSswKQYDVQQDEyJNaWNyb3NvZnQgVGltZSBTb3VyY2UgTWFzdGVyIENsb2Nr
# MA0GCSqGSIb3DQEBBQUAAgUA3mJ1GTAiGA8yMDE4MDMyNTE5MjA1N1oYDzIwMTgw
# MzI2MTkyMDU3WjB0MDoGCisGAQQBhFkKBAExLDAqMAoCBQDeYnUZAgEAMAcCAQAC
# AlhpMAcCAQACAhZnMAoCBQDeY8aZAgEAMDYGCisGAQQBhFkKBAIxKDAmMAwGCisG
# AQQBhFkKAwGgCjAIAgEAAgMW42ChCjAIAgEAAgMehIAwDQYJKoZIhvcNAQEFBQAD
# ggEBAHgFdT2A5izt5HZCo4jxKJIjz49vI4FccPhYcLPvSGfGgPPGQ5CbbC5h29o3
# zS2OVu/Blr/PsYPb2WWVYY/E5joCPl7qI9UVkYhiWhbpyoVmJ3TnaMsx3YsJihuz
# HE4+KD1n3aWbKti5RYY/MLvQzDjdQlyFMwnSYtBuAxZY9fKrT2TYaNmAbL2CV/Qu
# 3MlBRigqr9qwd6jP8hg6BTyMdm80+0MlqekyB5yOKAz59i4YFGzLscCAxNznkR39
# 0B78Y1TPYSK0JSx++iFJ8lQDiU5YZq6XMwepDTx/XVf90tkoROVAU7Ese3l4S9A2
# xqysNiY9WHaOuA0waOmkR7AQinoxggL1MIIC8QIBATCBkzB8MQswCQYDVQQGEwJV
# UzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UE
# ChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGlt
# ZS1TdGFtcCBQQ0EgMjAxMAITMwAAAK2AIzdlxFojagAAAAAArTANBglghkgBZQME
# AgEFAKCCATIwGgYJKoZIhvcNAQkDMQ0GCyqGSIb3DQEJEAEEMC8GCSqGSIb3DQEJ
# BDEiBCBctpQPtbLc0uvu4KGnE1fI5awoFKZQfBGYw6fxuvsM6jCB4gYLKoZIhvcN
# AQkQAgwxgdIwgc8wgcwwgbEEFJwY5hrfGwOIF10cxscsS5qv4TDZMIGYMIGApH4w
# fDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1Jl
# ZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEmMCQGA1UEAxMd
# TWljcm9zb2Z0IFRpbWUtU3RhbXAgUENBIDIwMTACEzMAAACtgCM3ZcRaI2oAAAAA
# AK0wFgQUseXvT/5AO8LI237drFKXpNZq61IwDQYJKoZIhvcNAQELBQAEggEA47ga
# Y/CMyRgdPoZPncDsMxwQ799Rqefxl6QCQaj1xn5KeFLZx2XbUBZlH8ca4/z1lQ42
# KeOeWCBVcfZMA4Slg/3RRuW9dz4SmNhq3qfa5Ny5QZmOl9a4rR6v8E7etq/I+fdC
# LZutOtZa8Ca2K1w9slD0UzpTsPISA/HMyZH35jSGqGWht4t9UMLWakSDciqjH8av
# jzDcnqxWA7MxdlXFgqS+NcSye4qoFjT44//QaALzZnkYBkaIghfafewE0JxHhAcD
# QNmeEtf41/fpa0M6ZGdMNeZUGjQubcvxVxMYTyxLEcZZqt5suOCyXSJbVB+MCPiV
# o+F/Mw0dQ646xx6VdQ==
# SIG # End signature block
