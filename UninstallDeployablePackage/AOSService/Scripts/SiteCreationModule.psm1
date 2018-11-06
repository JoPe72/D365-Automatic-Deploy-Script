function Add-Cert($pfx, $credentialXml)
{
	Write-Output "Start processing certificate '$pfx.Name'." 
    $certInstance = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2

	# Get the password for certificate.
	$pathNode = $credentialXml.Credentials.Certificates.Certificate | where { $_.Path -eq "Deployment\Onebox\"+$pfx.Name}
	if($pathNode.Count -gt 0)
	{
		$password = $pathNode[0].Password
	}
	else
	{
		$password = $pathNode.Password
	}
 
	if($password -ne $null -and [string]::IsNullOrEmpty($password) -eq $false )
	{
		$certInstance.import($pfx.FullName, $password, "Exportable,PersistKeySet,MachineKeySet"); 
		$certTP = $certInstance.Thumbprint;
        Add-CertToStore -certTP:$certTP -certInstance:$certInstance -pfx:$pfx
	}
}

function Add-CertToStore([string]$certTP,$certInstance,$pfx)
{
    $store = Get-Item Cert:\LocalMachine\My
    $store.Open("ReadWrite")

    $trustedStore = Get-Item Cert:\LocalMachine\Root
    $trustedStore.Open("ReadWrite")
    
    # add certificate to trusted root store if not present
	$trustedRootCert = Get-ChildItem "Cert:\LocalMachine\Root" | where {$_.Thumbprint -eq "$certTP"}
	if($trustedRootCert -eq $null -or [string]::IsNullOrEmpty($trustedRootCert) -eq $true)
	{
		Write-output "Adding certificate $pfx.Name to the machine trusted root store."
		$trustedStore.Add($certInstance)
	}

    # add certificate to local machine store if not present
	$localStoreCert = Get-ChildItem "Cert:\LocalMachine\My" |where {$_.Thumbprint -eq "$certTP"}
	if ($localStoreCert -eq $null -or $localStoreCert -eq "") 
	{
		Write-output "Adding certificate $pfx.Name to the local machine store."
		$store.Add($certInstance)

        # Grant permissin to Network Service to the private key.
		$sslCertPrivKey = $certInstance.PrivateKey.CspKeyContainerInfo.UniqueKeyContainerName
		$privateKeyCertFile = Get-Item -path "$ENV:ProgramData\Microsoft\Crypto\RSA\MachineKeys\*"  | where {$_.Name -eq $sslCertPrivKey} 
		$privateKeyAcl = (Get-Item -Path $privateKeyCertFile.FullName).GetAccessControl("Access") 
		$permission = "NT AUTHORITY\NETWORK SERVICE","Read","Allow" 
		$accessRule = new-object System.Security.AccessControl.FileSystemAccessRule $permission 
		$privateKeyAcl.AddAccessRule($accessRule) 
		Set-Acl $privateKeyCertFile.FullName $privateKeyAcl
		Write-output "Network Service account is granted access to the private key of certificate $pfx.Name"

		# Configure the SSL certificate "star1.cloud.onebox.dynamics.com.pfx" to the port 443
		try
		{
			if($pfx.Name -eq "star1.cloud.onebox.dynamics.com.pfx")
			{
				get-item cert:\LocalMachine\My\$certTP | new-item IIS:\SslBindings\0.0.0.0!443 -ErrorAction SilentlyContinue
			}
		}
		catch 
		{
			Write-output "SSL is configured for the AOS website."
			$_.Exception.Message    
		}
    }

    $store.Close()
    $trustedStore.Close()
}

function Remove-CertFromStore($certInstance)
{
    $store = Get-Item Cert:\LocalMachine\My
    $store.Open("ReadWrite")

    $trustedStore = Get-Item Cert:\LocalMachine\Root
    $trustedStore.Open("ReadWrite")

    # remove certificate from the trusted root store if present
	$trustedRootCert = Get-ChildItem "Cert:\LocalMachine\Root" | where {$_.Thumbprint -eq "$certTP"}
	if($trustedRootCert -ne $null -or [string]::IsNullOrEmpty($trustedRootCert) -eq $false)
	{
		Write-output "Removing certificate $pfx.Name from the machine trusted root store."
		$trustedStore.Remove($certInstance)
	}

    # remove certificate from the local machine store if present
	$localStoreCert = Get-ChildItem "Cert:\LocalMachine\My" |where {$_.Thumbprint -eq "$certTP"}
	if ($localStoreCert -ne $null -or [string]::IsNullOrEmpty($localStoreCert) -eq $false) 
	{
		Write-output "Removing certificate $pfx.Name from the local machine store."
		$store.Remove($certInstance)
    }

    $store.Close()
    $trustedStore.Close()
}

function Remove-Cert($pfx, $credentialXml)
{
    $certInstance = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2

    # Get the password for certificate.
    $pathNode = $credentialXml.Credentials.Certificates.Certificate | where { $_.Path -eq "Deployment\Onebox\"+$pfx.Name}
    
    if($pathNode.Count -gt 0)
    {
        $password = $pathNode[0].Password
    }
    else
    {
        $password = $pathNode.Password
    }
 
    if($password -ne $null -and [string]::IsNullOrEmpty($password) -eq $false )
    {
       $certInstance.import($pfx.FullName, $password, "Exportable,PersistKeySet,MachineKeySet"); 
       $certTP = $certInstance.Thumbprint;
       
       Remove-CertFromStore -certInstance:$certInstance
    }
}

function AddOrRemoveWebsiteCerts([string] $rootPath, [bool] $remove)
{
	# Add all certificates to store.
	$credentialXml = [xml](Get-Content "$rootPath\DObind\Deployment\Onebox\Credentials.xml")

	# Get all the available certificate files.
	$allPFX = Get-ChildItem "$rootPath\DObind\Deployment\Onebox\*.pfx"

	# Loop through all each certificate and install it if not installed.
	foreach($pfx in $allPFX)
	{
		if($remove)
		{
			Remove-Cert $pfx $credentialXml
		}
		else
		{
			Add-Cert $pfx $credentialXml
		}
	}
}

function Add-WebsiteCerts([string] $rootPath)
{
	AddOrRemoveWebsiteCerts $rootPath $false
}

function Remove-WebsiteCerts([string] $rootPath)
{
	AddOrRemoveWebsiteCerts $rootPath $true
}

function Remove-ExistingAppPools([string] $appPoolName)
{
	$machineName = $env:COMPUTERNAME;
    $serverManager = [Microsoft.Web.Administration.ServerManager]::OpenRemote($machineName)
    $existingAppPool = $serverManager.ApplicationPools | Where-Object{$_.Name -eq "$appPoolName"}
    if($existingAppPool -ne $null)
    {
        Write-Output "Removing app pool '$appPoolName'."
        $serverManager.ApplicationPools.Remove($existingAppPool)
		$serverManager.CommitChanges()
    }
}

function Remove-ExistingWebsites([string] $siteName, $port, $hostHeaderStrs)
{
	$machineName = $env:COMPUTERNAME;
	$serverManager = [Microsoft.Web.Administration.ServerManager]::OpenRemote($machineName)
    $existingSite = $serverManager.Sites | Where-Object{$_.Name -eq "$siteName"}
    if($existingSite -ne $null)
    {
        Write-Output "Removing website '$siteName'."
        $serverManager.Sites.Remove($existingSite)
		$serverManager.CommitChanges()
    }
 
    #remove anything already using that port
    [Microsoft.Web.Administration.Site]$site
    foreach($site in $serverManager.Sites) 
    {
        foreach($hostHeader in $hostHeaderStrs)
		{
            foreach($binding in $site.Bindings)
            {
                if($binding.EndPoint.Port -eq $port -and $binding.EndPoint.Address -eq $hostHeader)
                {
                    Write-Warning "Warning: Found an existing site '$($site.Name)' already using port $port; removing it."
				    $serverManager.Sites.Remove($site)
					$serverManager.CommitChanges()
				    Write-Output "Website $($site.Name) removed."
                }
            }
        }
    }
}

function New-AppPool([string] $appPoolName, [string] $user, [string] $password, [int] $pingTimeoutSeconds)
{
	$machineName = $env:COMPUTERNAME;
	$serverManager = [Microsoft.Web.Administration.ServerManager]::OpenRemote($machineName)

    Write-output "Creating an app pool named '$appPoolName' under v4.0 runtime, default (Integrated) pipeline."
    $pool = $serverManager.ApplicationPools.Add($appPoolName);
    $pool.managedRuntimeVersion = "v4.0"
    $pool.processModel.identityType = [Microsoft.Web.Administration.ProcessModelIdentityType]::NetworkService
	$pool.processModel.PingResponseTime = [System.TimeSpan]::FromSeconds($pingTimeoutSeconds)
	$pool.Failure.RapidFailProtection =$false
	
	if ($user -ne $null -AND $password -ne $null -AND $user -ne "" -AND $password -ne "") {
	    Write-Output "Setting AppPool to run as user '$user'."
		$pool.processmodel.identityType = [Microsoft.Web.Administration.ProcessModelIdentityType]::SpecificUser
		$pool.processmodel.username = $user
		$pool.processmodel.password = $password
	} 
	
    $serverManager.CommitChanges()

	for($tryCount= 30; $tryCount -gt 0; --$tryCount)
	{
		if ($serverManager.ApplicationPools[$appPoolName].State -eq [Microsoft.Web.Administration.ObjectState]::Started)
		{
			Write-Output "The AppPool was created and started successfully."
			return
		}

		Start-Sleep -Milliseconds 100
	}

	throw "App pool '$appPoolName' was created but did not start automatically."
}

function New-Website([string] $siteName, [string] $aosSitePath, [string] $port, $hostHeaderStrs,$cert, [string] $appPoolName)
{
	$machineName = $env:COMPUTERNAME
	$serverManager = [Microsoft.Web.Administration.ServerManager]::OpenRemote($machineName)
	$bindingArguments = "*:443:"+$hostHeaderStrs[0]
	Write-Output "Creating website. Site name: '$siteName'; Bindings: '$bindingArguments'; Website root: '$aosSitePath'."
	$website = $serverManager.Sites.Add($siteName, "https", $bindingArguments, $aosSitePath)
	for($i = 1; $i -lt $hostHeaderStrs.Length ; $i++)
	{
		$bindingArguments = "*:443:"+$hostHeaderStrs[$i]
		Write-Output "Adding binding '$bindingArguments' to the AOS website."
        $website.Bindings.Add($bindingArguments, $cert.GetCertHash(), "My")
	}

	Write-Output "Setting the website app pool to '$appPoolName'."
	# Set the app pool for the website
	$website.Applications[0].ApplicationPoolName = $appPoolName
    $serverManager.CommitChanges()

    
    Set-WebConfigurationProperty -pspath "MACHINE/WEBROOT/APPHOST/$siteName/Apps"  -filter "system.webServer/security/requestFiltering/fileExtensions/add[@fileExtension='.config']" -name "allowed" -value "True"


	for($tryCount= 100; $tryCount -gt 0; --$tryCount)
	{
		if ($serverManager.Sites[$siteName].State -eq [Microsoft.Web.Administration.ObjectState]::Started)
		{
			Write-Output "AOS website was created and started successfully."
			return
		}

		Start-Sleep -Milliseconds 100
	}
	
	throw "The AOS website '$siteName' was created but did not start after waiting for 10 seconds. Check the event log for further details."
}

function New-AosWebsite([string] $rootPath, [string] $siteName, [string] $aosSitePath, [string] $appPoolName, [string] $port, $hostHeaderStrs, [string] $user, [string] $userPassword, [string] $certTP, [int] $pingTimeoutSeconds = 600)
{
	# start IIS.
	Invoke-Command -script {iisreset.exe /start}

    # Cleanup old websites and app pools
	Remove-ExistingWebsites $siteName $appPoolName $port
	Remove-ExistingAppPools $appPoolName

	# Add certs
	Add-WebsiteCerts $rootPath

	# Create new app Pool
	New-AppPool $appPoolName $user $userPassword $pingTimeoutSeconds
	
	# Create the new site
	$cert = Get-ChildItem "Cert:\LocalMachine\My" |where {$_.Thumbprint -eq "$certTP"}
	New-Website $siteName $aosSitePath $port $hostHeaderStrs $cert $appPoolName
}

function Remove-Website([string] $rootPath, [string] $websiteName, [string] $appPoolName)
{
	# Cleanup certs
	Write-Output "Removing certificates."
	Remove-WebsiteCerts $rootPath

	# Cleanup old websites and app pools
	Write-Output "Remvoing website '$websiteName'."
	Remove-ExistingWebsites $websiteName $appPoolName 0

	Write-Output "Remvoing App pool '$appPoolName'."
	Remove-ExistingAppPools $appPoolName
}

function Delete-Service([string]$serviceName)
{
    try
    {
        $service = Get-WmiObject -Class Win32_Service -Filter "Name='$serviceName'" -ErrorAction SilentlyContinue
	    if($service -ne $null)
	    {
		    # stop and delete the batch Service
            Write-output "Stopping service '$serviceName'."
		    Stop-Service "$serviceName" -ErrorAction SilentlyContinue -Force
            $service = Get-Service $serviceName
            while($service -ne $null -and $service.Status -ne "Stopped")
            {
                $service = Get-Service $serviceName
                Write-output "Sleeping for 5 minutes while waiting for the service '$serviceName' to stop."
                Start-Sleep 5
            }

            Write-output "Deleting service '$serviceName'."
		    sc.exe delete "$serviceName" 
	    }
    }
    catch
    {
    }
}

function Terminate-process
{
    # kill process
	$processes = @("batch","batch.exe","mmc")
	foreach($process in $processes)
	{
		$handle = get-process "$process" -ErrorAction SilentlyContinue
		if($handle -ne $null)
		{
			try
			{
                # special case for Event viewer
                if($process -eq "mmc" -and $handle.MainWindowTitle -eq "Event Viewer")
                {
                    $procName = $handle.MainWindowTitle
                    Write-output "Terminating process '$procName'."
				    $handle.kill()
                }
                else
                {
                    Write-output "Terminating process '$handle'."
                    $handle.Kill()
                }
			}
			catch
			{
			}
		}
	}

    # stop and delete Dynamics Rainier services
    Delete-Service -serviceName:"DynamicsAxBatch"
}

function Register-RestartTask([string]$deploymentDir,[string]$logDir,[bool]$deployChocolateyPackage,[string]$packageDir)
{
    Write-Output "Registering a scheduled task to auto start Azure storage emulator upon machine restart."
    $localMachineName = $env:COMPUTERNAME
    $batchFilename = [IO.Path]::Combine("$deploymentDir","AOSDeploy.cmd")
    Write-Output "Creating scheduler task batch file '$batchFilename'."

    "$deploymentDir\DoBind\aosdeploy.exe /action:Restart /rd:`"$deploymentDir`" /ld:`"$logDir`" /td:`"$packageDir`" /chocopkg:$deployChocolateyPackage"|Set-Content $batchFilename

    $taskName = "DynamicsRainierRestartTask"
    & schtasks /create /ru SYSTEM /sc ONSTART /tn $taskName /tr "cmd /c $batchFilename" /F /RL HIGHEST
    if (!$?)
    {
        throw "There was an error creating the task $taskName."
    }
}

function Delete-RestartTask
{
    $taskName = "DynamicsRainierRestartTask"
    Write-Output "Deleting scheduled task '$taskName'."
    $SchTsk = Get-ScheduledTask | Select Name, State | ? {$_.Name -eq $taskName}
    if($SchTsk -ne $null)
    {
        & schtasks /delete /tn $taskName /F
    }
}

function Configure-ProductConfiguration([string]$sitename)
{
    Write-output "Starting the configuration of the production configuration application."
    $aossite=Get-Website -Name $sitename
    if($aossite -eq $null){
        $message="The website '$sitename' does not exist."
        Write-Output $message
        throw $message
    }

    $webroot=$aossite.physicalPath
    $productconfigurationdir=join-path $webRoot "productconfiguration"

    if(!(Test-Path "$productconfigurationdir")){
        Write-Output "Skipping product configuration as the product configuration directory does not exist under the aos web root $webroot."
        return
    }

    $pcapppool="productconfiguration"
    Write-output "Removing web app pool $pcapppool."
    Remove-WebAppPool -Name:$pcapppool -ErrorAction SilentlyContinue
    write-output "Creating web app pool $pcapppool."
    $newapppool=New-WebAppPool -Name:$pcapppool -ErrorAction SilentlyContinue
    write-output "Setting the identity for the web app pool '$pcapppool' to NetworkService."
    $newapppool.processModel.identityType="NetworkService"
    $newapppool|Set-Item
    write-output "Starting web app pool $pcapppool."
    Start-WebAppPool -Name:$pcapppool

    Write-Output "Deleting web application 'ProductConfiguration' under web site '$sitename'."
    Remove-WebApplication -Site:$aossite.Name -Name:"ProductConfiguration" -ErrorAction SilentlyContinue
    Write-Output "Creating new web application 'ProductConfiguration' under web site '$sitename' with application pool `"$pcapppool`"."
    New-WebApplication -Site:$aossite.Name -Name:"ProductConfiguration" -PhysicalPath:$productconfigurationdir -ApplicationPool:$pcapppool -Force 
    Write-Output "Product configuration application successfully configured."
}

Export-ModuleMember -Function New-AosWebsite,Remove-Website,Terminate-process,Register-RestartTask,Delete-RestartTask,Delete-Service,Configure-ProductConfiguration,Add-WebsiteCerts,Remove-WebsiteCerts
# SIG # Begin signature block
# MIIkBAYJKoZIhvcNAQcCoIIj9TCCI/ECAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCD4vYul+/4MT2Y/
# shNR1m8EcMqg8PK/RZCg1SpB/rUJ2qCCDYIwggYAMIID6KADAgECAhMzAAAAww6b
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
# SEXAQsmbdlsKgEhr/Xmfwb1tbWrJUnMTDXpQzTGCFdgwghXUAgEBMIGVMH4xCzAJ
# BgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25k
# MR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xKDAmBgNVBAMTH01pY3Jv
# c29mdCBDb2RlIFNpZ25pbmcgUENBIDIwMTECEzMAAADDDpun2LLc9ywAAAAAAMMw
# DQYJYIZIAWUDBAIBBQCggcowGQYJKoZIhvcNAQkDMQwGCisGAQQBgjcCAQQwHAYK
# KwYBBAGCNwIBCzEOMAwGCisGAQQBgjcCARUwLwYJKoZIhvcNAQkEMSIEINtB1m9P
# HGgEpV2EU8rkJQfhGL66oYCwLnP9gtUKVx9hMF4GCisGAQQBgjcCAQwxUDBOoDCA
# LgBTAGkAdABlAEMAcgBlAGEAdABpAG8AbgBNAG8AZAB1AGwAZQAuAHAAcwBtADGh
# GoAYaHR0cDovL3d3dy5taWNyb3NvZnQuY29tMA0GCSqGSIb3DQEBAQUABIIBAHBE
# tg65aSV0Fbk/y/x/IIMNCvJoBhPEWuQIi+7YcyTRny1SaMeX7Rpb5RIbrYjxdRUT
# eXbhAQrvEkdsqcG4NCM92J/gzvVG04Vl/M3RTydx3mlmX070sQnx79tIudokQN5I
# ZADmaqgflwpR9GDrGYBphVpY+9dF3NgmnGmmSbsVX+a9oekDyIwJCim203MBMLII
# +tyYdS0eJmzVUlwTDDFqrJmwonbqlZmQzoBYR4/ZRaFe3wOKML4dA48lXehx6i0N
# wzlDm8fVc+imSh4gRlz0DHF3RXlvbI2ctOkC1MeBOpT5p5xpHBZsznIHIVSxhMgk
# prlirgj5mRBeMlC4FLOhghNGMIITQgYKKwYBBAGCNwMDATGCEzIwghMuBgkqhkiG
# 9w0BBwKgghMfMIITGwIBAzEPMA0GCWCGSAFlAwQCAQUAMIIBOwYLKoZIhvcNAQkQ
# AQSgggEqBIIBJjCCASICAQEGCisGAQQBhFkKAwEwMTANBglghkgBZQMEAgEFAAQg
# N0gy3ENpvQDMOg7jyDRcSnUh6+SoQj0qS4OPbeuZu6sCBlqyr8APhxgTMjAxODAz
# MjUyMTA1NTAuNTY0WjAHAgEBgAIB9KCBt6SBtDCBsTELMAkGA1UEBhMCVVMxEzAR
# BgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1p
# Y3Jvc29mdCBDb3Jwb3JhdGlvbjEMMAoGA1UECxMDQU9DMSYwJAYDVQQLEx1UaGFs
# ZXMgVFNTIEVTTjo3MERELTRCNUItNDU2ODElMCMGA1UEAxMcTWljcm9zb2Z0IFRp
# bWUtU3RhbXAgU2VydmljZaCCDsswggZxMIIEWaADAgECAgphCYEqAAAAAAACMA0G
# CSqGSIb3DQEBCwUAMIGIMQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3Rv
# bjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0
# aW9uMTIwMAYDVQQDEylNaWNyb3NvZnQgUm9vdCBDZXJ0aWZpY2F0ZSBBdXRob3Jp
# dHkgMjAxMDAeFw0xMDA3MDEyMTM2NTVaFw0yNTA3MDEyMTQ2NTVaMHwxCzAJBgNV
# BAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4w
# HAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xJjAkBgNVBAMTHU1pY3Jvc29m
# dCBUaW1lLVN0YW1wIFBDQSAyMDEwMIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIB
# CgKCAQEAqR0NvHcRijog7PwTl/X6f2mUa3RUENWlCgCChfvtfGhLLF/Fw+Vhwna3
# PmYrW/AVUycEMR9BGxqVHc4JE458YTBZsTBED/FgiIRUQwzXTbg4CLNC3ZOs1nMw
# VyaCo0UN0Or1R4HNvyRgMlhgRvJYR4YyhB50YWeRX4FUsc+TTJLBxKZd0WETbijG
# GvmGgLvfYfxGwScdJGcSchohiq9LZIlQYrFd/XcfPfBXday9ikJNQFHRD5wGPmd/
# 9WbAA5ZEfu/QS/1u5ZrKsajyeioKMfDaTgaRtogINeh4HLDpmc085y9Euqf03GS9
# pAHBIAmTeM38vMDJRF1eFpwBBU8iTQIDAQABo4IB5jCCAeIwEAYJKwYBBAGCNxUB
# BAMCAQAwHQYDVR0OBBYEFNVjOlyKMZDzQ3t8RhvFM2hahW1VMBkGCSsGAQQBgjcU
# AgQMHgoAUwB1AGIAQwBBMAsGA1UdDwQEAwIBhjAPBgNVHRMBAf8EBTADAQH/MB8G
# A1UdIwQYMBaAFNX2VsuP6KJcYmjRPZSQW9fOmhjEMFYGA1UdHwRPME0wS6BJoEeG
# RWh0dHA6Ly9jcmwubWljcm9zb2Z0LmNvbS9wa2kvY3JsL3Byb2R1Y3RzL01pY1Jv
# b0NlckF1dF8yMDEwLTA2LTIzLmNybDBaBggrBgEFBQcBAQROMEwwSgYIKwYBBQUH
# MAKGPmh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2kvY2VydHMvTWljUm9vQ2Vy
# QXV0XzIwMTAtMDYtMjMuY3J0MIGgBgNVHSABAf8EgZUwgZIwgY8GCSsGAQQBgjcu
# AzCBgTA9BggrBgEFBQcCARYxaHR0cDovL3d3dy5taWNyb3NvZnQuY29tL1BLSS9k
# b2NzL0NQUy9kZWZhdWx0Lmh0bTBABggrBgEFBQcCAjA0HjIgHQBMAGUAZwBhAGwA
# XwBQAG8AbABpAGMAeQBfAFMAdABhAHQAZQBtAGUAbgB0AC4gHTANBgkqhkiG9w0B
# AQsFAAOCAgEAB+aIUQ3ixuCYP4FxAz2do6Ehb7Prpsz1Mb7PBeKp/vpXbRkws8LF
# Zslq3/Xn8Hi9x6ieJeP5vO1rVFcIK1GCRBL7uVOMzPRgEop2zEBAQZvcXBf/XPle
# FzWYJFZLdO9CEMivv3/Gf/I3fVo/HPKZeUqRUgCvOA8X9S95gWXZqbVr5MfO9sp6
# AG9LMEQkIjzP7QOllo9ZKby2/QThcJ8ySif9Va8v/rbljjO7Yl+a21dA6fHOmWaQ
# jP9qYn/dxUoLkSbiOewZSnFjnXshbcOco6I8+n99lmqQeKZt0uGc+R38ONiU9Mal
# CpaGpL2eGq4EQoO4tYCbIjggtSXlZOz39L9+Y1klD3ouOVd2onGqBooPiRa6YacR
# y5rYDkeagMXQzafQ732D8OE7cQnfXXSYIghh2rBQHm+98eEA3+cxB6STOvdlR3jo
# +KhIq/fecn5ha293qYHLpwmsObvsxsvYgrRyzR30uIUBHoD7G4kqVDmyW9rIDVWZ
# eodzOwjmmC3qjeAzLhIp9cAvVCch98isTtoouLGp25ayp0Kiyc8ZQU3ghvkqmqMR
# ZjDTu3QyS99je/WZii8bxyGvWbWu3EQ8l1Bx16HSxVXjad5XwdHeMMD9zOZN+w2/
# XU/pnR4ZOC+8z1gFLu8NoFA12u8JJxzVs341Hgi62jbb01+P3nSISRIwggTYMIID
# wKADAgECAhMzAAAAt/giFH0DIv76AAAAAAC3MA0GCSqGSIb3DQEBCwUAMHwxCzAJ
# BgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25k
# MR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xJjAkBgNVBAMTHU1pY3Jv
# c29mdCBUaW1lLVN0YW1wIFBDQSAyMDEwMB4XDTE3MTAwMjIzMDA1MloXDTE5MDEw
# MjIzMDA1MlowgbExCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAw
# DgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24x
# DDAKBgNVBAsTA0FPQzEmMCQGA1UECxMdVGhhbGVzIFRTUyBFU046NzBERC00QjVC
# LTQ1NjgxJTAjBgNVBAMTHE1pY3Jvc29mdCBUaW1lLVN0YW1wIFNlcnZpY2UwggEi
# MA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIBAQC0hXZnLn7NAl1QCxJ8ZBM3LvZX
# oNoTNaHigy1WSNDcr8jKPsVrrb5krZElwM+di1G43efi5k3O2ESPG18E+nrdaMJr
# nOof+fCwXRLiF4XdTOXQI2gztw9EwVlYndf0dzdJZ4771xtmJJjBNA2GkAE7mJQP
# XAt+SULHh8fIHrwP3xVwT8Ly4NNwJWqzln11U3Jm1NSsUM68ZdCqhxBuRH0E4rMv
# mcDwxjnanzik7zq71oQ2eIu4HF/Cpv/he7RG2RKZ2uBwkom8YBEdiuUBoEubkXJS
# BzRL0QZRbLWaYDs9fYMzVV59kjNYkS83ffjOOms77ZsjDxAnajpcvuba2J47AgMB
# AAGjggEbMIIBFzAdBgNVHQ4EFgQUbWKvg3tEhnVxd9JNW4/uRC5gNWkwHwYDVR0j
# BBgwFoAU1WM6XIoxkPNDe3xGG8UzaFqFbVUwVgYDVR0fBE8wTTBLoEmgR4ZFaHR0
# cDovL2NybC5taWNyb3NvZnQuY29tL3BraS9jcmwvcHJvZHVjdHMvTWljVGltU3Rh
# UENBXzIwMTAtMDctMDEuY3JsMFoGCCsGAQUFBwEBBE4wTDBKBggrBgEFBQcwAoY+
# aHR0cDovL3d3dy5taWNyb3NvZnQuY29tL3BraS9jZXJ0cy9NaWNUaW1TdGFQQ0Ff
# MjAxMC0wNy0wMS5jcnQwDAYDVR0TAQH/BAIwADATBgNVHSUEDDAKBggrBgEFBQcD
# CDANBgkqhkiG9w0BAQsFAAOCAQEAaaSp0uuxop+K5nske7Qn7t56ojZWiDVVHIfZ
# vNv7ARlMxECedM+O/zhwRwjhD/jfPHwwWsgg7052h1JaKDxnB6rxIWJkNvU3+Uob
# spjaSDaZFdRUpTTW3EDpzWhGs/+SIamgg+UUZC+JVYF5mMAd7b6YdMxUA+YAd823
# NNHewpUlEb3ok6QlafT9JZeOqu9TTzCOcL+p2WeOZ097deqx9beMd46h9KUypgf2
# 8PpjdSOcgWZRmviWVu6b4v445460NOIDGQDwBhoYOu1XMT/KxjnRP3ry5Tq++s4R
# I0QegwpxKJ6jpYGQ/XaNhjhkch2wrLWC84eIjOqrU4KV2OH4aaGCA3YwggJeAgEB
# MIHhoYG3pIG0MIGxMQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQ
# MA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9u
# MQwwCgYDVQQLEwNBT0MxJjAkBgNVBAsTHVRoYWxlcyBUU1MgRVNOOjcwREQtNEI1
# Qi00NTY4MSUwIwYDVQQDExxNaWNyb3NvZnQgVGltZS1TdGFtcCBTZXJ2aWNloiUK
# AQEwCQYFKw4DAhoFAAMVANXj0P5ZNuTCZFlJB+nXIozHReoNoIHBMIG+pIG7MIG4
# MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVk
# bW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMQwwCgYDVQQLEwNB
# T0MxJzAlBgNVBAsTHm5DaXBoZXIgTlRTIEVTTjoyNjY1LTRDM0YtQzVERTErMCkG
# A1UEAxMiTWljcm9zb2Z0IFRpbWUgU291cmNlIE1hc3RlciBDbG9jazANBgkqhkiG
# 9w0BAQUFAAIFAN5ih6cwIhgPMjAxODAzMjUyMDQwMDdaGA8yMDE4MDMyNjIwNDAw
# N1owdzA9BgorBgEEAYRZCgQBMS8wLTAKAgUA3mKHpwIBADAKAgEAAgIncAIB/zAH
# AgEAAgIYcDAKAgUA3mPZJwIBADA2BgorBgEEAYRZCgQCMSgwJjAMBgorBgEEAYRZ
# CgMBoAowCAIBAAIDFuNgoQowCAIBAAIDHoSAMA0GCSqGSIb3DQEBBQUAA4IBAQAa
# B7nJ32p+Up+rJtXZsICmMul9/BhcRBP7TL7FUQPXnbuG/vYaod0IBsY3eKqb8w0m
# JKSQcxf6xHSzSJhxYBx+RP6n8Dx5ypnz4Ge1KdGAiTLl1LiXVO62brbGlvBGfuZU
# 6L6MH8MMBUTcoZCPRhCMNuKgjGG24BosW2FmdiiQMajaZnO6KcyGZiE6NJfoRsC+
# vNxaLHIytVBd0Oup9fzzLMlx0/XaxkFK/ovPPJHvx+HNpN87vQOloeQZxuaiFc93
# F9K1OmKRiCWzQe9FBz4RfF/mP1LdCXfcTLzBiBO/63XhbAdFHZRK3lll35EkVSxV
# z467bupeaALx/698GC3kMYIC9TCCAvECAQEwgZMwfDELMAkGA1UEBhMCVVMxEzAR
# BgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1p
# Y3Jvc29mdCBDb3Jwb3JhdGlvbjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRpbWUtU3Rh
# bXAgUENBIDIwMTACEzMAAAC3+CIUfQMi/voAAAAAALcwDQYJYIZIAWUDBAIBBQCg
# ggEyMBoGCSqGSIb3DQEJAzENBgsqhkiG9w0BCRABBDAvBgkqhkiG9w0BCQQxIgQg
# mjTkuU4CG7meAgDeI718pS3GcC8P01XRVNQ5RykibjUwgeIGCyqGSIb3DQEJEAIM
# MYHSMIHPMIHMMIGxBBTV49D+WTbkwmRZSQfp1yKMx0XqDTCBmDCBgKR+MHwxCzAJ
# BgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25k
# MR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xJjAkBgNVBAMTHU1pY3Jv
# c29mdCBUaW1lLVN0YW1wIFBDQSAyMDEwAhMzAAAAt/giFH0DIv76AAAAAAC3MBYE
# FNwV13vkiMc1kRngxMsrLBKnRFMLMA0GCSqGSIb3DQEBCwUABIIBADtvSsZjxd3o
# nN0OWZzoNB/F6V3Gv/JnztDSDAgl4h4qY/u94QcYSssTpy4fcdvs6vItu4jdeRU+
# lUaYu2iBZbVTk/ptoIo0ua7FNC9kpM7Oml7NE4QApSmrEmgccMyLZsY37f3wHIJX
# NWpAd03TL895xJjtrnDIv4kqnN7btFFR7gfktEENvD8nKjZGv3y4g8Ig8MZVaU60
# P6GrH9BkJQfD1RA5Hj0KMLbpAFJrgyCqytqreaUHYHMRGQExMC2U8bH+qwukC5Nv
# +NyLlAXMnBbp+E6jDdwlVyddRUjyc2jLp2gY1SOM4nj+gGsZb2vbPBd1CAzy3gcR
# 2QlyQdOxFfM=
# SIG # End signature block
