################################################################################
# Write message to log file and output stream
################################################################################
Function Write-LogOutput($message)
{
    Write-Log $message
    Write-Output $message
}

################################################################################
# Install AX SSRS extension components
################################################################################
Function Install-AxSsrsExtension
{
    param
    (
        [Parameter(Mandatory=$true)]
        [string]$config,
        [Parameter(Mandatory=$true)]
        [string]$log
    )

    Import-Module "$PSScriptRoot\AosCommon.psm1" -DisableNameChecking

    # Initialize log file
    Initialize-Log $log

    # Get EnableSecurity value
    $settings = Decode-Settings($config)
    Write-LogOutput $("")
    Write-LogOutput $settings | Format-List *
    if ($settings.EnableSecurity -eq $null)
    {
        throw "Missing EnableSecurity value."
    }

    [Switch]$enableSecurity = [System.Convert]::ToBoolean($settings.EnableSecurity)

    # Gets account list to acess reports
    [string[]] $accounts = $null
    if ($settings.AccountListToAccessReports -ne $null)
    {
        $accounts = $settings.AccountListToAccessReports.split(',')
    }

    # Use AxReportVmRoleStartupTask.exe to install reporting extensions
    Write-LogOutput $("Start installing AX SSRS extensions ...")
    [string] $reportServerUri = "http://localhost:80/ReportServer"
    [int]$IntExitCode = 0
    $deployExtensionExe = Join-Path -Path $PSScriptRoot -ChildPath "AxReportVmRoleStartupTask.exe"
    Write-LogOutput $deployExtensionExe
    $allArgs = @("-config", $config)
    & $deployExtensionExe $allArgs *>&1
    $exitCode = $LASTEXITCODE
    if ($exitCode -eq 0)
    {
        Write-LogOutput $("Completed installing AX SSRS extension.")

        [string] $ManagementAssemblyPath = Join-Path -Path $PSScriptRoot -ChildPath "Microsoft.Dynamics.AX.Framework.Management.dll"
        Import-Module $ManagementAssemblyPath
			
        #Added this step to warmup SSRS to avoid the timeout error
        Restart-WindowsService -log $log -computerName $env:COMPUTERNAME -serviceName ReportServer -ErrorAction stop
        Test-ReportServer -reportServerUri $reportServerUri -log $log -ErrorAction Stop

        if ($enableSecurity)
        {
            # Start Creating and configuring AX reports root folder
            Write-LogOutput $("")
            Write-LogOutput $("Start creating and configuring AX reports root folder ...")			
            Install-AxReportRootFolder -Accounts $accounts  -ErrorAction Stop | Tee-Object -Variable InstallLog          
            Add-Content -Path $log -Value $InstallLog
            Write-LogOutput $("Completed creating and configuring AX reports root folder.")
        }

	Write-LogOutput $("")
        Write-LogOutput $("Start creating report shared data sources...")
        Install-SharedDataSource -ErrorAction Stop | Tee-Object -Variable InstallLog
        Add-Content -Path $log -Value $InstallLog
        Write-LogOutput $("Completed creating report shared data sources.")
    }
    else
    {
        throw "Error occurred when running AxReportVmRoleStartupTask.exe to install extension. Please see details in events for AX-ReportPVMSetup."
    }

    # Test the SSRS instance prior to completing this step. If this is not successful then we should fail.
    Restart-WindowsService -log $log -computerName $env:COMPUTERNAME -serviceName ReportServer -ErrorAction stop
    Test-ReportServer -reportServerUri $reportServerUri -log $log -ErrorAction Stop
}


################################################################################
# Uninstall AX SSRS extension components
# $config parameter must have a property EnableSecurity with value "true" or "false"
################################################################################
Function Remove-AxSsrsExtension
{
    param
    (
        [Parameter(Mandatory=$true)]
        [string]$config,
        [Parameter(Mandatory=$true)]
        [string]$log
    )

    Import-Module "$PSScriptRoot\AosCommon.psm1" -DisableNameChecking

    # Initialize log file
    Initialize-Log $log

    # Verify deployment type
    $settings = Decode-Settings($config)
    Write-LogOutput $("")
    Write-LogOutput $settings | Format-List *
    if ($settings.EnableSecurity -eq $null)
    {
        throw "Missing EnableSecurity value."
    }

    [Switch]$enableSecurity = [System.Convert]::ToBoolean($settings.EnableSecurity)


    # Verify/Add IsUninstallOnly value (true) to the $config string
    Write-LogOutput $("Verify/Add IsUninstallOnly parameter to the config string...")
    [string]$uninstallConfig = $config
    if (Get-Member -InputObject $settings -Name "IsUninstallOnly" -MemberType Properties)
    {
        if (![string]::Equals($settings.IsUninstallOnly, "true", [System.StringComparison]::OrdinalIgnoreCase))
        {
            throw "IsUninstallOnly must be true for uninstallation."
        }

        Write-LogOutput $("Completed verifying IsUninstallOnly value in the config string.")
    }
    else
    {
        $settings|Add-Member -type NoteProperty -Name "IsUninstallOnly" -Value "true"
        $uninstallConfig = ConvertTo-Json $settings
        $uninstallConfig = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($uninstallConfig))
        Write-LogOutput $("Completed Adding IsUninstallOnly value in the config string.")
    }

    # Use AxReportVmRoleStartupTask.exe to uninstall reporting extensions
    Write-LogOutput("")
    Write-LogOutput $("Start uninstalling AX SSRS extensions ...")

    $deployExtensionExe = Join-Path -Path $PSScriptRoot -ChildPath "AxReportVmRoleStartupTask.exe"
    $allArgs = @("-config", $uninstallConfig)
    & $deployExtensionExe $allArgs *>&1
    $exitCode = $LASTEXITCODE
    if ($exitCode -eq 0)
    {
        Write-LogOutput $("Completed uninstalling AX SSRS extension.")
    }
    else
    {
        throw "Error occurred when running AxReportVmRoleStartupTask.exe to uninstall extension. Please see details in events for AX-ReportPVMSetup."
    }
}


################################################################################
# Format report publishing results
################################################################################
Function Format-PublishOutput 
{
    param
    (
        [Parameter(ValueFromPipeline=$true,Position=0)] 
        $result
    )

    process
    {
        if ($result -is [Microsoft.Dynamics.AX.Framework.Management.Reports.ReportDeploymentResult])
        {
            $result | Select-Object ReportName, ReportDeploymentStatus
        }
        else
        {
            $result
        }
    }
}


################################################################################
# Deploy AX reports To SSRS server
################################################################################
Function Deploy-AxReport
{
    param
    (
        [Parameter(Mandatory=$true)]
        [string]$config,
        [Parameter(Mandatory=$true)]
        [string]$log
    )

    Import-Module "$PSScriptRoot\AosCommon.psm1" -DisableNameChecking

    # Initialize the log file
    Initialize-Log $log

    # Getting values from the JSON configuration string
    $settings = Decode-Settings($config)

    [string]$reportingServers = $settings."BiReporting.ReportingServers"
    [string]$packageInstallLocation = $settings."Microsoft.Dynamics.AX.AosConfig.AzureConfig.bindir"
    [string[]]$module = $settings.Module 
    [string[]]$reportName = $settings.ReportName

    Write-LogOutput $('Reporting Servers: ' + $reportingServers)

    # split report servers string
    $rsServers = $reportingServers.Split(",", [System.StringSplitOptions]::RemoveEmptyEntries)|%{$_.trim()}
    $rsServers = $rsServers.Where({-not [System.String]::IsNullOrWhiteSpace($_)})

    # Test each SSRS instance prior to deploying any reports. If this is not successful
    # then there is no need to deploy reports.
    foreach ($rsServer in $rsServers)
    {
        [string]$reportServerUri = "http://" + $rsServer + "/ReportServer"
        Test-ReportServer -reportServerUri $reportServerUri -log $log -ErrorAction Stop
    }

    Write-LogOutput $('Microsoft.Dynamics.AX.AosConfig.AzureConfig.bindir: ' + $packageInstallLocation)
    Write-LogOutput $('Module: ' + $module)
    Write-LogOutput $('ReportName: ' + $reportName)

    if ($module -eq $null -or $module.Length -eq 0)
    {
        $module = "*"
    }

    if ($reportName -eq $null -or $reportName.Length -eq 0)
    {
        $reportName = "*"
    }

    # Start deploying reports
    $startTime = $(Get-Date)

    if ($rsServers.Count -eq 1)
    {
        [string]$ManagementAssemblyPath = Join-Path -Path $PSScriptRoot -ChildPath "Microsoft.Dynamics.AX.Framework.Management.dll"
        Import-Module $ManagementAssemblyPath

        $err = @()
        Publish-AXReport -MaxDegreeOfParallelism 1 -ErrorAction Continue -ErrorVariable err -ReportName $reportName -SkipReportServerAdminCheck -ReportServerAddress $rsServers[0] -BinDirectory $PackageInstallLocation -DeleteExisting -Module $module *>&1 | Format-PublishOutput | Tee-Object -Variable DeployReportsLog
        Add-Content -Path $log -Value $($DeployReportsLog | Out-String)
        Write-LogOutput $(($(Get-Date) - $startTime).TotalSeconds.ToString() + " Seconds.")

        if ($err.Count -gt 0)
        {
            throw "Errors occured during report deployment."
        }
    }
    else
    {

        foreach ($rsServer in $rsServers)
        {
            Start-Job -Name $("Job" + $rsServer) -ScriptBlock {
                Param
                (
                    [Parameter(Mandatory=$true)]
                    [string]$scriptRoot,
                    [Parameter(Mandatory=$true)]
                    [string]$rsServerArg,
                    [Parameter(Mandatory=$true)]
                    [string[]]$reportNameArg,
                    [Parameter(Mandatory=$true)]
                    [string]$packageInstallLocationArg,
                    [Parameter(Mandatory=$true)]
                    [string[]]$moduleArg
                )

                Import-Module "$scriptRoot\AosCommon.psm1" -Force -DisableNameChecking -ErrorAction Stop
                Import-Module "$scriptRoot\Reporting.psm1" -Force -DisableNameChecking -ErrorAction Stop

                [string]$ManagementAssemblyPath = Join-Path -Path $scriptRoot -ChildPath "Microsoft.Dynamics.AX.Framework.Management.dll"
                Import-Module $ManagementAssemblyPath -ErrorAction Stop

                $err = @()
                Publish-AXReport -MaxDegreeOfParallelism 1 -ErrorAction Continue -ErrorVariable err -ReportName $reportNameArg -SkipReportServerAdminCheck -ReportServerAddress $rsServerArg -BinDirectory $packageInstallLocationArg -DeleteExisting -Module $moduleArg *>&1 | Format-PublishOutput | Out-String -OutVariable DeployReportsLog
                return @{"Error" = $err; "Log" = $DeployReportsLog}
            } -ArgumentList $PSScriptRoot, $rsServer, $reportName, $packageInstallLocation, $module
        }

        $allErrors = @() 
        foreach ($rsServer in $rsServers)
        {
            $job = Get-Job $("Job" + $rsServer)
            $jobResult = Receive-Job -Job $job -Wait -AutoRemoveJob

            if ($jobResult."Error")
            {
                $allErrors += $jobResult."Error"
            }

            if ($jobResult."Log")
            {
                Write-LogOutput $($jobResult."Log" | Out-String)
            }
        }

        Write-LogOutput $(($(Get-Date) - $startTime).TotalSeconds.ToString() + " Seconds.")

        foreach ($error in $allErrors)
        {
            if ($error.Count -gt 0)
            {
                throw @("Errors occured during report deployment for server " + $rsServer)
            }
        }
    }
}


################################################################################
# Remove all AX reports from SSRS server
################################################################################
Function Remove-AllAxReports
{
    param
    (
        [Parameter(Mandatory=$true)]
        [string]$config,
        [Parameter(Mandatory=$true)]
        [string]$log
    )

    Import-Module "$PSScriptRoot\AosCommon.psm1" -DisableNameChecking

    # Initialize the log file
    Initialize-Log $log

    # Getting values from the JSON configuration string
    $settings = Decode-Settings($config)

    [string]$reportingServers = $settings."BiReporting.ReportingServers"
    [string[]]$reportName = $settings.ReportName

    # split report servers string
    Write-LogOutput $('Reporting Servers: ' + $reportingServers)
    $rsServers = $reportingServers.Split(",", [System.StringSplitOptions]::RemoveEmptyEntries)|%{$_.trim()}
    $rsServers = $rsServers.Where({-not [System.String]::IsNullOrWhiteSpace($_)})
    
    # report name validation
    Write-LogOutput $('ReportName: ' + $reportName)
    if ($reportName -eq $null -or $reportName.Length -eq 0)
    {
        $reportName = "*"
    }

    # Start clearing reports
    $startTime = $(Get-Date)

    if ($rsServers.Count -eq 1)
    {
        [string]$ManagementAssemblyPath = Join-Path -Path $PSScriptRoot -ChildPath "Microsoft.Dynamics.AX.Framework.Management.dll"
        Import-Module $ManagementAssemblyPath

        Remove-AxReport -ErrorAction Continue -MaxDegreeOfParallelism 1 -ReportName $reportName -ReportServerAddress $rsServers[0] *>&1 |  Format-PublishOutput | Tee-Object -Variable ReportRemovalLog
        Add-Content -Path $log -Value $ReportRemovalLog
        Write-LogOutput $(($(Get-Date) - $startTime).TotalSeconds.ToString() + " Seconds.")
    }
    else
    {
        foreach ($rsServer in $rsServers)
        {
            Start-Job -Name $("RmJob" + $rsServer) -ScriptBlock {
                Param
                (
                    [Parameter(Mandatory=$true)]
                    [string]$scriptRoot,
                    [Parameter(Mandatory=$true)]
                    [string]$rsServerArg,
                    [Parameter(Mandatory=$true)]
                    [string[]]$reportNameArg
                )

                Import-Module "$scriptRoot\AosCommon.psm1" -Force -DisableNameChecking -ErrorAction Stop
                Import-Module "$scriptRoot\Reporting.psm1" -Force -DisableNameChecking -ErrorAction Stop

                [string]$ManagementAssemblyPath = Join-Path -Path $scriptRoot -ChildPath "Microsoft.Dynamics.AX.Framework.Management.dll"
                Import-Module $ManagementAssemblyPath -ErrorAction Stop

                Remove-AxReport -ErrorAction Continue -MaxDegreeOfParallelism 1 -ReportName $reportNameArg -ReportServerAddress $rsServerArg *>&1 | Format-PublishOutput | Out-String -OutVariable ReportRemovalLog
            } -ArgumentList $PSScriptRoot, $rsServer, $reportName
        }

        foreach ($rsServer in $rsServers)
        {
            $job = Get-Job $("RmJob" + $rsServer)
            $jobResultLog = Receive-Job -Job $job -Wait -AutoRemoveJob

            if ($jobResultLog)
            {
                Write-LogOutput $($jobResultLog | Out-String)
            }
        }

        Write-LogOutput $(($(Get-Date) - $startTime).TotalSeconds.ToString() + " Seconds.")
    }
}

################################################################################
# Install report fonts to SSRS server
################################################################################
Function Install-Font
{
    param
    (
        [Parameter(Mandatory=$true)]
        [string]$config,
        [Parameter(Mandatory=$true)]
        [string]$log,
        [Parameter(Mandatory=$true)]
        [string]$fontFilePath
    )

    Import-Module "$PSScriptRoot\AosCommon.psm1" -DisableNameChecking

    # Initialize the log file
    Initialize-Log $log

    # Start installing fonts
    Write-Output("")
    Write-LogOutput "Start installing fonts to SSRS ..."
    Write-LogOutput $("Font file path: " + $fontFilePath)
    $MangementAssemblyPath = Join-Path -Path $PSScriptRoot -ChildPath "Microsoft.Dynamics.AX.Framework.Management.dll"
    Import-Module $MangementAssemblyPath

    (Get-ChildItem -Path $fontFilePath -Filter "*.ttf").FullName | Install-ReportFont *>&1 | Tee-Object -Variable ReportFontLog
    Add-Content -Path $log -Value $ReportFontLog

    # Restart SSRS
    Get-Service -Name ReportServer | Restart-Service *>&1 | Tee-Object -Variable RestartSsrsLog
    Add-Content -Path $log -Value $RestartSsrsLog

    Write-LogOutput $("Completed installing fonts to SSRS.")
}

#####################################################
# Configure SSRS web service and web app protocols
#####################################################
function Config-SsrsEndpoint
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory=$true)]
        [int]$Port,
        [Parameter(Mandatory=$true)]
        [string]$log,
        [Parameter(Mandatory=$false)]
        [string]$SslCertThumbprint
    )

    Import-Module "$PSScriptRoot\AosCommon.psm1" -DisableNameChecking

    $rsConfig = Get-RsConfig -ComputerName $env:COMPUTERNAME
    if (!$rsConfig)
    {
        throw "Could not find reporting service WMI object MSReportServer_ConfigurationSetting"
    }

    $lcid = [System.Globalization.CultureInfo]::GetCultureInfo('en-US').LCID
    $rsWebServiceAppName = 'ReportServerWebService'
    $reportManagerAppName = 'ReportServerWebApp'

    # Remove all existing ResvervedUrls
    $result = $rsConfig.ListReservedUrls()
    Verify-SsrsWmiCall -resultObject $result -methodName 'ListReservedurls'
    if ($result.Application)
    {
        for ($i = 0; $i -lt $result.Application.length; $i++)
        {
            $removeResult = $rsConfig.RemoveURL($result.Application[$i], $result.UrlString[$i], $lcid)
            Verify-SsrsWmiCall -resultObject $removeResult -methodName 'RemoveURL'
            Write-LogOutput $([string]::Format("Removed URL Application={0} UrlString= {1}", $result.Application[$i], $result.UrlString[$i]))
        }
    }

    # Remove all SSL Certficate Bindings
    $result = $rsConfig.ListSSLCertificateBindings($lcid)
    if ($result.Application)
    {
        for ($i = 0; $i -lt $result.Application.length; $i++)
        {
            $removeResult = $rsConfig.RemoveSSLCertificateBindings($result.Application[$i], $result.CertificateHash[$i], $result.IPAddress[$i], $result.Port[$i], $lcid)
            Verify-SsrsWmiCall -resultObject $removeResult -methodName 'RemoveSSLCertificateBindings'
            Write-LogOutput $([string]::Format("Removed SSL Binding Application={0} Certificate={1} IPAddress={2} Port={3}", $result.Application[$i], $result.CertificateHash[$i], $result.IPAddress[$i], $result.Port[$i]))
        }
    }

    # Reserve URL for web service and web app
    $urlString = $([string]::Format("http://+:{0}", $Port))
    if ($SslCertThumbprint)
    {
        $urlString = [string]::Format("https://+:{0}", $Port)
    }

    $result = $rsConfig.ReserveURL($rsWebServiceAppName, $urlString, $lcid)
    Verify-SsrsWmiCall -resultObject $result -methodName 'ReserveURL'
    Write-LogOutput $([string]::Format("Reserved URL string {0} for {1}", $urlString, $rsWebServiceAppName))

    if ($rsConfig.VirtualDirectoryReportManager)
    {
        $result = $rsConfig.ReserveURL($reportManagerAppName, $urlString, $lcid)
        Verify-SsrsWmiCall -resultObject $result -methodName 'ReserveURL'
        Write-LogOutput $([string]::Format("Reserved URL string {0} for {1}", $urlString, $reportManagerAppName))
    }

    # Create SSL Certificate Bindings for web service and web app
    if ($SslCertThumbprint)
    {
        $ipV4Address = "0.0.0.0";
        $ipV6Address = "::";

        $result = $rsConfig.CreateSSLCertificateBinding($rsWebServiceAppName, $SslCertThumbprint, $ipV4Address, $Port, $lcid);
        Verify-SsrsWmiCall -resultObject $result -methodName 'CreateSSLCertificateBinding'
        Write-LogOutput $([string]::Format("Created SSL Certificate Binding Application={0} SslCertThumbPrint={1} IPAddress={2} Port={3}", $rsWebServiceAppName, $SslCertThumbprint, $ipV4Address, $Port))

        $result = $rsConfig.CreateSSLCertificateBinding($rsWebServiceAppName, $SslCertThumbprint, $ipV6Address, $Port, $lcid);
        Verify-SsrsWmiCall -resultObject $result -methodName 'CreateSSLCertificateBinding'
        Write-LogOutput $([string]::Format("Created SSL Certificate Binding Application={0} SslCertThumbPrint={1} IPAddress={2} Port={3}", $rsWebServiceAppName, $SslCertThumbprint, $ipV6Address, $Port))

        if ($rsConfig.VirtualDirectoryReportManager)
        {
            $result = $rsConfig.CreateSSLCertificateBinding($reportManagerAppName, $SslCertThumbprint, $ipV4Address, $Port, $lcid);
            Verify-SsrsWmiCall -resultObject $result -methodName 'CreateSSLCertificateBinding'
            Write-LogOutput $([string]::Format("Created SSL Certificate Binding Application={0} SslCertThumbPrint={1} IPAddress={2} Port={3}", $reportManagerAppName, $SslCertThumbprint, $ipV4Address, $Port))

            $result = $rsConfig.CreateSSLCertificateBinding($reportManagerAppName, $SslCertThumbprint, $ipV6Address, $Port, $lcid);
            Verify-SsrsWmiCall -resultObject $result -methodName 'CreateSSLCertificateBinding'
            Write-LogOutput $([string]::Format("Created SSL Certificate Binding Application={0} SslCertThumbPrint={1} IPAddress={2} Port={3}", $reportManagerAppName, $SslCertThumbprint, $ipV6Address, $Port))
        }
    }

    #Restart reporting services service
    Restart-WindowsService -computerName $env:COMPUTERNAME -serviceName ReportServer -log $log
}


####################################################################
# Verify SSRS WMI calls
####################################################################
function Verify-SsrsWmiCall
{
    param
    (
        $resultObject,
        $methodName
    )

    if (!$resultObject)
    {
        throw $("Returned Null object when calling $methodName")
    }

    if ($resultObject.HRESULT > 0)
    {
        throw $("Error occured when calling {0}. HResult = {1} Error={2}" -f $methodName, $resultObject.HRESULT, $resultObject.Error)
    }
}


################################################################################
# Test the SSRS Server
################################################################################
Function Test-ReportServer
{
    param
    (
        [Parameter(Mandatory=$true)]
        [string]$reportServerUri,
        [Parameter(Mandatory=$false)]
        [bool]$ignoreServerCertificate = $false,
        [Parameter(Mandatory=$true)]
        [string]$log
    )

    # Initialize the log file
    Initialize-Log $log

    Write-LogOutput $('Checking status of Report Server URL: ' + $reportServerUri)

    # Assume a bad request
    $statusCode = 400

    try
    {
        # Invoke the web request and get the status
        $uri = New-Object -TypeName System.Uri($reportServerUri)
        [System.Net.HttpWebRequest]$request = [System.Net.HttpWebRequest]::CreateHttp($uri)
        $request.Timeout = 10 * 60 * 1000 
        $request.UseDefaultCredentials = $true
        $request.KeepAlive = $false
        if ($ignoreServerCertificate)
        {
            $request.ServerCertificateValidationCallback = {$true}
        }

        [System.Net.WebResponse]$response = $request.GetResponse()
        $statusCode = $response.StatusCode
    }
    catch [System.Net.WebException]
    {
        Write-LogOutput $('Failure! Status check of Report Server URL: ' + $reportServerUri)
        Write-LogOutput $($_.Exception.ToString())

        throw "An exception of type System.Net.WebException occurred when making an http request to: " + $reportServerUri + ". Refer to the log file for more details."
    }
    
    # check the status code is 200 OK 
    if ($statusCode -eq 200)
    {
        Write-LogOutput $('Success! Status check of Report Server URL: ' + $reportServerUri)
    }
    else
    {
        Write-LogOutput $('Failure! Status check of Report Server URL: ' + $reportServerUri)
        Write-LogOutput $('StatusCode value: ' + $statusCode)
            
        throw "Http response contains StatusCode of " + $statusCode + ". Unable to communicate with the SQL Server ReportServer service."
    }
}

################################################################################
# Restart a windows service
################################################################################
function Restart-WindowsService
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory=$true)]
        [string]$log,
        [Parameter(Mandatory=$true)]
        [string]$computerName,
        [Parameter(Mandatory=$true)]
        [string]$serviceName
    )

    Import-Module "$PSScriptRoot\AosCommon.psm1" -DisableNameChecking

    # Initialize log file
    Initialize-Log $log

    $retryCount = 3;

    while ($retryCount -gt 0)
    {
        Write-LogOutput $("Restart " + $serviceName + " service on " + $computerName + "...")
        
        try
        {
            Get-Service -ErrorAction Stop -Name $serviceName -ComputerName $computerName | Restart-Service -ErrorAction Stop -Force *>&1 | Tee-Object -Variable RestartServiceLog
            Add-Content -Path $log -Value $RestartServiceLog
            break
        }
        catch
        {
            $retryCount -= 1;
            if ($retryCount -le 0)
            {
                throw
            }

            Start-Sleep -Seconds 30
        }
    }

    Write-LogOutput $($serviceName + " service restarted on " + $computerName)
}

################################################################################
# Get reporting service config WMI object
################################################################################
function Get-RsConfig
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory=$true)]
        [string]$ComputerName
    )

    try
    {
        # SQL Server 2016
        $rsconfig = Get-WmiObject -ErrorAction Stop –namespace "root\Microsoft\SqlServer\ReportServer\RS_MSSQLSERVER\v13\Admin" –class MSReportServer_ConfigurationSetting –ComputerName $ComputerName -Filter "InstanceName='MSSQLSERVER'"
    }
    catch
    {
        if ($_.Exception.Message.IndexOf("Invalid namespace", [System.StringComparison]::OrdinalIgnoreCase) -ge 0)
        {
            # SQL Server 2014
            $rsconfig = Get-WmiObject -ErrorAction Stop –namespace "root\Microsoft\SqlServer\ReportServer\RS_MSSQLSERVER\v12\Admin" –class MSReportServer_ConfigurationSetting –ComputerName $ComputerName -Filter "InstanceName='MSSQLSERVER'"
        }
        else
        {
            throw
        }
    }

    return $rsconfig
}
# SIG # Begin signature block
# MIIj7gYJKoZIhvcNAQcCoIIj3zCCI9sCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCCJgm78q59UONAE
# sj0oGX25DB0BVE26mE0EUOJjlQEYl6CCDYIwggYAMIID6KADAgECAhMzAAAAww6b
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
# SEXAQsmbdlsKgEhr/Xmfwb1tbWrJUnMTDXpQzTGCFcIwghW+AgEBMIGVMH4xCzAJ
# BgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25k
# MR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xKDAmBgNVBAMTH01pY3Jv
# c29mdCBDb2RlIFNpZ25pbmcgUENBIDIwMTECEzMAAADDDpun2LLc9ywAAAAAAMMw
# DQYJYIZIAWUDBAIBBQCggbgwGQYJKoZIhvcNAQkDMQwGCisGAQQBgjcCAQQwHAYK
# KwYBBAGCNwIBCzEOMAwGCisGAQQBgjcCARUwLwYJKoZIhvcNAQkEMSIEILhOcqXI
# yii/deX6ldfMspU0Pl3+TumqFRgjPzMSp7pXMEwGCisGAQQBgjcCAQwxPjA8oB6A
# HABSAGUAcABvAHIAdABpAG4AZwAuAHAAcwBtADGhGoAYaHR0cDovL3d3dy5taWNy
# b3NvZnQuY29tMA0GCSqGSIb3DQEBAQUABIIBAIc3fNUJqEa0mwbCaGjJQZZvOGto
# UDwZ5glreu+Kz/ZdM0KIPVy8g/ECCGvNM8AcBy9fFUHS4WEH6Z/xZotm6mpm8/Vp
# dJPJ97sHBxR1QQaoxdYfKgqDzS9sMyTcNPMov+kjlXJeFDJRfbzHPBP+amgc0+w7
# gKibJj4bl0B7/j4kOC2JFYfqdEurVD09Xwu7b4KOphsYZCKc9qQ0U3xItoBmajhl
# vMEFMKLNIX0ReuWi2kZMDQvLKcapeLxp342iwnuxQ1XznJxxlcX566NFh6c6mulI
# GUt13RlG7q+Sac76B8rZLEalgoVk03+jNlMnel/ktSZdmWEOfa6aLUffoSehghNC
# MIITPgYKKwYBBAGCNwMDATGCEy4wghMqBgkqhkiG9w0BBwKgghMbMIITFwIBAzEP
# MA0GCWCGSAFlAwQCAQUAMIIBOgYLKoZIhvcNAQkQAQSgggEpBIIBJTCCASECAQEG
# CisGAQQBhFkKAwEwMTANBglghkgBZQMEAgEFAAQg6ASueC/9v0/1qjpTpmV+R1BD
# XIRJO6Q//7oPSIU7D6UCBlqypc1UvhgSMjAxODAzMjUyMTA1NTQuMDlaMAcCAQGA
# AgH0oIG3pIG0MIGxMQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQ
# MA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9u
# MQwwCgYDVQQLEwNBT0MxJjAkBgNVBAsTHVRoYWxlcyBUU1MgRVNOOkMzQjAtMEY2
# QS00MTExMSUwIwYDVQQDExxNaWNyb3NvZnQgVGltZS1TdGFtcCBTZXJ2aWNloIIO
# yDCCBnEwggRZoAMCAQICCmEJgSoAAAAAAAIwDQYJKoZIhvcNAQELBQAwgYgxCzAJ
# BgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25k
# MR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xMjAwBgNVBAMTKU1pY3Jv
# c29mdCBSb290IENlcnRpZmljYXRlIEF1dGhvcml0eSAyMDEwMB4XDTEwMDcwMTIx
# MzY1NVoXDTI1MDcwMTIxNDY1NVowfDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldh
# c2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBD
# b3Jwb3JhdGlvbjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRpbWUtU3RhbXAgUENBIDIw
# MTAwggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIBAQCpHQ28dxGKOiDs/BOX
# 9fp/aZRrdFQQ1aUKAIKF++18aEssX8XD5WHCdrc+Zitb8BVTJwQxH0EbGpUdzgkT
# jnxhMFmxMEQP8WCIhFRDDNdNuDgIs0Ldk6zWczBXJoKjRQ3Q6vVHgc2/JGAyWGBG
# 8lhHhjKEHnRhZ5FfgVSxz5NMksHEpl3RYRNuKMYa+YaAu99h/EbBJx0kZxJyGiGK
# r0tkiVBisV39dx898Fd1rL2KQk1AUdEPnAY+Z3/1ZsADlkR+79BL/W7lmsqxqPJ6
# Kgox8NpOBpG2iAg16HgcsOmZzTznL0S6p/TcZL2kAcEgCZN4zfy8wMlEXV4WnAEF
# TyJNAgMBAAGjggHmMIIB4jAQBgkrBgEEAYI3FQEEAwIBADAdBgNVHQ4EFgQU1WM6
# XIoxkPNDe3xGG8UzaFqFbVUwGQYJKwYBBAGCNxQCBAweCgBTAHUAYgBDAEEwCwYD
# VR0PBAQDAgGGMA8GA1UdEwEB/wQFMAMBAf8wHwYDVR0jBBgwFoAU1fZWy4/oolxi
# aNE9lJBb186aGMQwVgYDVR0fBE8wTTBLoEmgR4ZFaHR0cDovL2NybC5taWNyb3Nv
# ZnQuY29tL3BraS9jcmwvcHJvZHVjdHMvTWljUm9vQ2VyQXV0XzIwMTAtMDYtMjMu
# Y3JsMFoGCCsGAQUFBwEBBE4wTDBKBggrBgEFBQcwAoY+aHR0cDovL3d3dy5taWNy
# b3NvZnQuY29tL3BraS9jZXJ0cy9NaWNSb29DZXJBdXRfMjAxMC0wNi0yMy5jcnQw
# gaAGA1UdIAEB/wSBlTCBkjCBjwYJKwYBBAGCNy4DMIGBMD0GCCsGAQUFBwIBFjFo
# dHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20vUEtJL2RvY3MvQ1BTL2RlZmF1bHQuaHRt
# MEAGCCsGAQUFBwICMDQeMiAdAEwAZQBnAGEAbABfAFAAbwBsAGkAYwB5AF8AUwB0
# AGEAdABlAG0AZQBuAHQALiAdMA0GCSqGSIb3DQEBCwUAA4ICAQAH5ohRDeLG4Jg/
# gXEDPZ2joSFvs+umzPUxvs8F4qn++ldtGTCzwsVmyWrf9efweL3HqJ4l4/m87WtU
# VwgrUYJEEvu5U4zM9GASinbMQEBBm9xcF/9c+V4XNZgkVkt070IQyK+/f8Z/8jd9
# Wj8c8pl5SpFSAK84Dxf1L3mBZdmptWvkx872ynoAb0swRCQiPM/tA6WWj1kpvLb9
# BOFwnzJKJ/1Vry/+tuWOM7tiX5rbV0Dp8c6ZZpCM/2pif93FSguRJuI57BlKcWOd
# eyFtw5yjojz6f32WapB4pm3S4Zz5Hfw42JT0xqUKloakvZ4argRCg7i1gJsiOCC1
# JeVk7Pf0v35jWSUPei45V3aicaoGig+JFrphpxHLmtgOR5qAxdDNp9DvfYPw4Ttx
# Cd9ddJgiCGHasFAeb73x4QDf5zEHpJM692VHeOj4qEir995yfmFrb3epgcunCaw5
# u+zGy9iCtHLNHfS4hQEegPsbiSpUObJb2sgNVZl6h3M7COaYLeqN4DMuEin1wC9U
# JyH3yKxO2ii4sanblrKnQqLJzxlBTeCG+SqaoxFmMNO7dDJL32N79ZmKLxvHIa9Z
# ta7cRDyXUHHXodLFVeNp3lfB0d4wwP3M5k37Db9dT+mdHhk4L7zPWAUu7w2gUDXa
# 7wknHNWzfjUeCLraNtvTX4/edIhJEjCCBNgwggPAoAMCAQICEzMAAACtgCM3ZcRa
# I2oAAAAAAK0wDQYJKoZIhvcNAQELBQAwfDELMAkGA1UEBhMCVVMxEzARBgNVBAgT
# Cldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29m
# dCBDb3Jwb3JhdGlvbjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRpbWUtU3RhbXAgUENB
# IDIwMTAwHhcNMTYwOTA3MTc1NjU1WhcNMTgwOTA3MTc1NjU1WjCBsTELMAkGA1UE
# BhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAc
# BgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEMMAoGA1UECxMDQU9DMSYwJAYD
# VQQLEx1UaGFsZXMgVFNTIEVTTjpDM0IwLTBGNkEtNDExMTElMCMGA1UEAxMcTWlj
# cm9zb2Z0IFRpbWUtU3RhbXAgU2VydmljZTCCASIwDQYJKoZIhvcNAQEBBQADggEP
# ADCCAQoCggEBAO2zDf5lGt2NsVXvRym+KFTjFQLByzq2Wh6ejANxzNtKrOeNVL9e
# ofo1ARQi/FyT70eal7jqau/R6qeqJblHXObJa9O0B5oG8ueyNMiLGHvYdbV4aUUM
# 11IijLEQEqm7Jlo+v0ZSGjlhSAuUWniibqkoXHFBrT6DVoMkLKHVqfDFvm/c9u8S
# Vqcy6+nLx6kkflGbefoHa7cmCgMwrKi2M7pErRo3g5dXK4SQaDTBgH8eUWDJ1X42
# CrKp+T60frfehPeb8U+oJgjmGKYqAllxzMGX+CliedfWzk12z//BFQHmk5hgkdNq
# BYksIAGH3BA9Ost2rIOdEAn8hw2crlyZ/acCAwEAAaOCARswggEXMB0GA1UdDgQW
# BBRkIbrAL6z4nMcMlOXnH8kK1rz9azAfBgNVHSMEGDAWgBTVYzpcijGQ80N7fEYb
# xTNoWoVtVTBWBgNVHR8ETzBNMEugSaBHhkVodHRwOi8vY3JsLm1pY3Jvc29mdC5j
# b20vcGtpL2NybC9wcm9kdWN0cy9NaWNUaW1TdGFQQ0FfMjAxMC0wNy0wMS5jcmww
# WgYIKwYBBQUHAQEETjBMMEoGCCsGAQUFBzAChj5odHRwOi8vd3d3Lm1pY3Jvc29m
# dC5jb20vcGtpL2NlcnRzL01pY1RpbVN0YVBDQV8yMDEwLTA3LTAxLmNydDAMBgNV
# HRMBAf8EAjAAMBMGA1UdJQQMMAoGCCsGAQUFBwMIMA0GCSqGSIb3DQEBCwUAA4IB
# AQAShUe51J2YxHxkbrWquE1TiiKG3HaVdV0ijzd1PF72pW86jRl/u+qUNP4gpmpU
# Nk80VP8AA5VUJvN5Z+/xwBj66bcw7Xf/aXTaM4QRDpOvgRjHJVq4hdZgobRrWzOj
# /rSGGCTYIZVb7pAVxtlj7tSk2Pnket1LsnOsFrmgwAQW7zV1O1A8+WF23AHoCx9m
# UBrdqllPTIPYxYcEQiJ3qMr3TaWuGpHFxx0gfCFYdVOvTyW64sy4cHDjWmFdXKzj
# a/yM06w4P2I/JmDDeaaVdfyP/OYtLJR9AtEb7sN/pMHZpEYiN9evf5i6Xvd3k12r
# C68UUE7pZkEvOeqE4xd5+VxUoYIDczCCAlsCAQEwgeGhgbekgbQwgbExCzAJBgNV
# BAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4w
# HAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xDDAKBgNVBAsTA0FPQzEmMCQG
# A1UECxMdVGhhbGVzIFRTUyBFU046QzNCMC0wRjZBLTQxMTExJTAjBgNVBAMTHE1p
# Y3Jvc29mdCBUaW1lLVN0YW1wIFNlcnZpY2WiJQoBATAJBgUrDgMCGgUAAxUAnBjm
# Gt8bA4gXXRzGxyxLmq/hMNmggcEwgb6kgbswgbgxCzAJBgNVBAYTAlVTMRMwEQYD
# VQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNy
# b3NvZnQgQ29ycG9yYXRpb24xDDAKBgNVBAsTA0FPQzEnMCUGA1UECxMebkNpcGhl
# ciBOVFMgRVNOOjI2NjUtNEMzRi1DNURFMSswKQYDVQQDEyJNaWNyb3NvZnQgVGlt
# ZSBTb3VyY2UgTWFzdGVyIENsb2NrMA0GCSqGSIb3DQEBBQUAAgUA3mJ1GTAiGA8y
# MDE4MDMyNTE5MjA1N1oYDzIwMTgwMzI2MTkyMDU3WjB0MDoGCisGAQQBhFkKBAEx
# LDAqMAoCBQDeYnUZAgEAMAcCAQACAlhpMAcCAQACAhZnMAoCBQDeY8aZAgEAMDYG
# CisGAQQBhFkKBAIxKDAmMAwGCisGAQQBhFkKAwGgCjAIAgEAAgMW42ChCjAIAgEA
# AgMehIAwDQYJKoZIhvcNAQEFBQADggEBAHgFdT2A5izt5HZCo4jxKJIjz49vI4Fc
# cPhYcLPvSGfGgPPGQ5CbbC5h29o3zS2OVu/Blr/PsYPb2WWVYY/E5joCPl7qI9UV
# kYhiWhbpyoVmJ3TnaMsx3YsJihuzHE4+KD1n3aWbKti5RYY/MLvQzDjdQlyFMwnS
# YtBuAxZY9fKrT2TYaNmAbL2CV/Qu3MlBRigqr9qwd6jP8hg6BTyMdm80+0Mlqeky
# B5yOKAz59i4YFGzLscCAxNznkR390B78Y1TPYSK0JSx++iFJ8lQDiU5YZq6XMwep
# DTx/XVf90tkoROVAU7Ese3l4S9A2xqysNiY9WHaOuA0waOmkR7AQinoxggL1MIIC
# 8QIBATCBkzB8MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4G
# A1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSYw
# JAYDVQQDEx1NaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0EgMjAxMAITMwAAAK2AIzdl
# xFojagAAAAAArTANBglghkgBZQMEAgEFAKCCATIwGgYJKoZIhvcNAQkDMQ0GCyqG
# SIb3DQEJEAEEMC8GCSqGSIb3DQEJBDEiBCDuAbUD8Ogy1Rl1jqnQ7aehb5bpVYfw
# S2YzvLpOogt08TCB4gYLKoZIhvcNAQkQAgwxgdIwgc8wgcwwgbEEFJwY5hrfGwOI
# F10cxscsS5qv4TDZMIGYMIGApH4wfDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldh
# c2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBD
# b3Jwb3JhdGlvbjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRpbWUtU3RhbXAgUENBIDIw
# MTACEzMAAACtgCM3ZcRaI2oAAAAAAK0wFgQUseXvT/5AO8LI237drFKXpNZq61Iw
# DQYJKoZIhvcNAQELBQAEggEAzIgiQcgUDox0tXT0OI7KELXVg5R/E1PxUWdHahi4
# VZ9FTqW1te76u6P80uUsaOskhjNnNvGzv+EsCYaQ7vBPFeI+mDDrdXkh7D3gTrOZ
# Oc2ae6JuSUHSC33ky+75EYl08FfzO1LvhglO70H3/i2I9E87VBcu15iGxBHKVZVA
# CNcaMqosyXYuRIMzKNHn7O86Vp0FlXbHY54J5VrBfhRfEGM8PiVPWcGGvGU6pV9H
# 8KO79SnkS7UFi2qkNoV9D/Yps0RF4W/hl4XBwp6egwOy/ZIf5JTIMbFTOriGKkcw
# nGTtj4YAPlDbPKivfn4krZaOQ60RvEKrGDKKVZAdbV5T4A==
# SIG # End signature block
