param
(
    [Parameter(Mandatory=$true)]
    $config,
    [Parameter(Mandatory=$true)]
    $log
)

Import-Module "$PSScriptRoot\AosCommon.psm1" -Force -DisableNameChecking

function Set-RegistryValues($settings)
{
    New-Item -Path HKLM:\SOFTWARE\Microsoft\Dynamics -Name Deployment -Force -Confirm:$false
    New-ItemProperty -Path HKLM:\SOFTWARE\Microsoft\Dynamics\Deployment -Name DeploymentDirectory -PropertyType String -Value $($settings.'Infrastructure.WebRoot') -Force -Confirm:$false
    New-ItemProperty -Path HKLM:\SOFTWARE\Microsoft\Dynamics\Deployment -Name BinDir -PropertyType String -Value $($settings.'Common.BinDir') -Force -Confirm:$false
    New-ItemProperty -Path HKLM:\SOFTWARE\Microsoft\Dynamics\Deployment -Name metadatadirectory -PropertyType String -Value $($settings.'Aos.MetadataDirectory') -Force -Confirm:$false
    New-ItemProperty -Path HKLM:\SOFTWARE\Microsoft\Dynamics\Deployment -Name frameworkdirectory -PropertyType String -Value $($settings.'Aos.PackageDirectory') -Force -Confirm:$false
}

function Configure-ClaimIssuers($webConfig, $settings)
{
    Write-Log "Start processing claim issuer restrictions."
    $ClaimIssuers = $settings.'Infrastructure.ClaimIssuers'
    if (![System.String]::IsNullOrWhitespace($ClaimIssuers))
    {
        $Issuers = $ClaimIssuers.Split(';')
        Write-Log "Processing claim issuer restrictions: $Issuers"

        #add missing elements to the web.config
        if ($Issuers.Count -gt 0)
        {
            $ClaimIssuerRestrictions = $webConfig.SelectNodes("configuration/claimIssuerRestrictions")
            if ($ClaimIssuerRestrictions -eq $null)
            {
                Write-Log "Web config does not contain element configuration/claimIssuerRestrictions. Creating."
                $ClaimIssuerRestrictions = $webConfig.CreateElement("claimIssuerRestrictions")
                $web.configuration.AppendChild($ClaimIssuerRestrictions)
            }

            $IssuerRestrictions = $ClaimIssuerRestrictions.issuerRestrictions
            if ($IssuerRestrictions -eq $null)
            {
                Write-Log "Web config does not contain element configuration/claimIssuerRestrictions/issuerRestrictions. Creating."
                $IssuerRestrictions = $webConfig.CreateElement("issuerRestrictions")
                $ClaimIssuerRestrictions.AppendChild($IssuerRestrictions)
            }
        }

        #add claim issuer restrictions
        foreach($Issuer in $Issuers)
        {
            $Tokens = $Issuer.Split(':')
            if ($Tokens.Count -lt 2 -or $Tokens.Count -gt 3)
            {
                throw "Claim issuer restriction is not in a valid format (expected format: issuerName:userId[,userId,userId,...[:defaultUserId]]): $Issuer"
            }

            $IssuerName = $Tokens[0]
            $AllowedUserIds = $Tokens[1]

            Write-Log "Processing issuer $IssuerName."

            $IssuerRestriction = $IssuerRestrictions.add | where { ($_.name -eq $IssuerName) }
            if ($IssuerRestriction -eq $null)
            {
                Write-Log "Creating new claim issuer restriction for issuer $IssuerName."

                $IssuerRestriction = $webConfig.CreateElement("add")
                $IssuerRestriction.SetAttribute("name", $IssuerName)
                $IssuerRestrictions.AppendChild($IssuerRestriction) | Out-Null
            }
            else
            {
                Write-Log "Claim issuer restriction already exists for issuer $IssuerName. Overriding with new restrictions."
            }

            $IssuerRestriction.SetAttribute("allowedUserIds", $AllowedUserIds)
            Write-Log "User ids $AllowedUserIds were set for $IssuerName."

            if ($Tokens.Count -eq 3)
            {
                $DefaultUserId = $Tokens[2]
                Write-Log "Setting default user id $DefaultUserId for $IssuerName."
                $IssuerRestriction.SetAttribute("defaultUserId", $DefaultUserId)
            }
        }
    }

    Write-Log "Finished processing claim issuer restrictions."
}

function Configure-MachineKeys($webConfig, $settings)
{
    Write-Log "Start processing machine keys."
    $DecryptionKey = $settings.'Infrastructure.MachineDecryptionKey'
    $ValidationKey = $settings.'Infrastructure.MachineValidationKey'

    if ($DecryptionKey -eq $null)
    {
        Write-Log "DecryptionKey not provided, skipping configuration."
        return
    }

    if ($ValidationKey -eq $null)
    {
        Write-Log "ValidationKey not provided, skipping configuration."
        return
    }

    $Web = $webConfig.SelectNodes("configuration/location[@path='.']/system.web")

    $MachineKey = $Web.machineKey

    if ($MachineKey -eq $null)
    {
        Write-Log "Creating machineKey element."

        $MachineKey = $webConfig.CreateElement("machineKey")
        $MachineKey.SetAttribute("decryption", "AES")
        $MachineKey.SetAttribute("decryptionKey", $DecryptionKey)
        $MachineKey.SetAttribute("validation", "HMACSHA256")
        $MachineKey.SetAttribute("validationKey", $ValidationKey)
        $Web.AppendChild($MachineKey) | Out-Null
    }
    else
    {
        Write-Log "Updating machineKey element."
        $MachineKey.decryption = "AES"
        $MachineKey.decryptionKey = $DecryptionKey
        $MachineKey.validation = "HMACSHA256"
        $MachineKey.validationKey = $ValidationKey
    }

    Write-Log "Finished processing machine keys."
}

function CreateFlightingCacheFolder($settings)
{
    Write-Log "Creating the Flighting Cache Folder for Application Platform Flighting"
    $webroot= $settings.'Infrastructure.WebRoot'
    $flightingcachefolder = $settings.'DataAccess.FlightingServiceCacheFolder'
    $flightingcachepath = Join-Path $webroot $flightingcachefolder

    if(!(Test-Path $flightingcachepath))
    {
        Write-Log "Creating $flightingcachepath."
        New-Item -ItemType Directory -Path $flightingcachepath -Force
    }
}

function Configure-FlightingCachePath($webConfig, $settings)
{
    Write-Log "Start processing Flighting Cache Path."

    #add missing elements to the web.config
    $add = $webConfig.configuration.appSettings.add | where key -eq 'DataAccess.FlightingCachePath' | select -First 1
    if ($add -eq $null)
    {
        $webRootDirectory = ($webConfig.configuration.appSettings.add | Where {$_.Key -eq 'Infrastructure.WebRoot'}).Value 
        if ([System.String]::IsNullOrWhitespace($webRootDirectory))
        {
            Write-Log "Could not find web root!!!!"
        }
        else 
        {
            $flightingcachefolder = $settings.'DataAccess.FlightingServiceCacheFolder'
            $flightingcachepath = Join-Path $webRootDirectory $flightingcachefolder
            $add = $webConfig.CreateElement("add")
            $add.SetAttribute("key", "DataAccess.FlightingCachePath")
            $add.SetAttribute("value", $flightingcachepath)
            $webConfig.configuration.appSettings.AppendChild($add) | Out-Null
        }
    }
}

function Update-WifServicesConfig($settings)
{
    $siteAdmin = $settings.'Provisioning.AdminPrincipalName'

    Write-Log "Reading wif.services.config at $($settings.'Infrastructure.WebRoot')"

    [xml]$wifServicesConfig = Get-Content "$($settings.'Infrastructure.WebRoot')\wif.services.config"
    [Uri]$uri = New-Object Uri $($settings.'Aad.AADLoginWsfedEndpointFormat' -f $($siteAdmin.Split('@')[1]))

    $wifServicesConfig.'system.identityModel.services'.federationConfiguration.wsFederation.issuer = "$($uri.AbsoluteUri)"

    $HostUri = New-Object Uri $settings.'Infrastructure.HostUrl'
    $wifServicesConfig.'system.identityModel.services'.federationConfiguration.cookieHandler.domain = $HostUri.DnsSafeHost

    $wifServicesConfig.Save("$($settings.'Infrastructure.WebRoot')\wif.services.config")
}

function Update-AADTenantInfo($settings, $web)
{
    Write-Log "Reading AAD metadata"

    $aadMetadataLocation = $($settings.'Aad.AADMetadataLocationFormat' -f $($settings.'Provisioning.AdminPrincipalName'.Split('@')[1]))
    Write-Log "AAD metadata location [$aadMetadataLocation]"

    $tempAadMetadataFile = [System.IO.Path]::GetTempFileName()
    Write-Log "Metadata will be stored in temporary file [$tempAadMetadataFile]"

    Write-Log "Invoking request"
    Invoke-WebRequest $aadMetadataLocation -UseBasicParsing -OutFile $tempAadMetadataFile

    Write-Log "Reading metadata from file at [$tempAadMetadataFile]"
    [xml]$aadMetadata = Get-Content $tempAadMetadataFile

    Write-Log "Removing temporary file at [$tempAadMetadataFile]"
    Remove-Item $tempAadMetadataFile -Force -Confirm:$false

    Write-Log "Extracting tenant guid from metadata"
    $url = New-Object System.Uri($aadMetadata.EntityDescriptor.entityId)

    $add = $web.configuration.appSettings.add | where key -eq 'Aad.TenantDomainGUID' | select -First 1
    $add.value = $url.AbsolutePath.Trim('/')

    Write-Log "Tenant guid updated"
}

function Update-DataAccessFlightingInfo($settings, $web)
{
    Write-Log "Reading DataAccess Flighting metadata"

    $flightingEnvironment = $settings.'DataAccess.FlightingEnvironment'
    Write-Log "flighting Environment [$flightingEnvironment]"

    $flightingCertificateThumbprint = $settings.'DataAccess.FlightingCertificateThumbprint'
    Write-Log "flighting Certificate Thumbprint [$flightingCertificateThumbprint]"

    $flightingServiceCatalogID = $settings.'DataAccess.FlightingServiceCatalogID'
    Write-Log "flighting ServiceCatalogID [$flightingServiceCatalogID]"

    $add = $web.configuration.appSettings.add | where key -eq 'DataAccess.FlightingEnvironment' | select -First 1
    $add.value = $flightingEnvironment

    $add = $web.configuration.appSettings.add | where key -eq 'DataAccess.FlightingCertificateThumbprint' | select -First 1
    $add.value = $flightingCertificateThumbprint

    $add = $web.configuration.appSettings.add | where key -eq 'DataAccess.FlightingServiceCatalogID' | select -First 1
    $add.value = $flightingServiceCatalogID

    Write-Log "DataAccess Flighting Infomation updated"
}

function Update-WebConfig($settings)
{
    Write-Log "Reading web.config at $($settings.'Infrastructure.WebRoot')"

    [xml]$web = Get-Content "$($settings.'Infrastructure.WebRoot')\web.config"

    $uri = New-Object Uri $settings.'Infrastructure.HostUrl'

    $add = $web.configuration.appSettings.add | where key -eq 'Infrastructure.FullyQualifiedDomainName' | select -First 1
    $add.value = $uri.DnsSafeHost

    $add = $web.configuration.appSettings.add | where key -eq 'Infrastructure.HostedServiceName' | select -First 1
    $add.value = $uri.DnsSafeHost.Split('.')[0]

    $add = $web.configuration.appSettings.add | where key -eq 'Infrastructure.HostName' | select -First 1
    $add.value = $uri.DnsSafeHost

    $siteAdmin = $settings.'Provisioning.AdminPrincipalName'
    $add = $web.configuration.appSettings.add | where key -eq 'Aad.AADTenantId' | select -First 1
    $add.value = $siteAdmin.Split('@')[1]

    Update-AADTenantInfo $settings $web

    Update-DataAccessFlightingInfo $settings $web

    $ClickOnceUnpackDir = $settings.'Infrastructure.ClickonceAppsDirectory'

    Write-Log "Click-once package dir $ClickOnceUnpackDir"

    if ((Test-Path $ClickOnceUnpackDir))
    {
        $ClickOnceTargetDir = Join-Path $settings.'Infrastructure.WebRoot' "apps"
        Write-Log "Click-once package dir $ClickOnceUnpackDir exists, copying click-one packages to webroot $ClickOnceTargetDir"

        if (!(Test-Path $ClickOnceTargetDir))
        {
            New-Item $ClickOnceTargetDir -ItemType Directory -Force
        }

        Copy-Item "$ClickOnceUnpackDir\*" $ClickOnceTargetDir -Recurse -Confirm:$false -Force

        $add = $web.configuration.appSettings.add | where key -eq 'Infrastructure.ClickonceAppsDirectory' | select -First 1
        $add.value = "$(split-path $ClickOnceTargetDir -Leaf)"

        Write-Log "Providing read access to the configuration files in APPS folder under web root: required for clickonce packages to work"
        Set-WebConfigurationProperty -pspath "MACHINE/WEBROOT/APPHOST/$($settings.'Infrastructure.ApplicationName')/Apps" -filter "system.webServer/security/requestFiltering/fileExtensions/add[@fileExtension='.config']" -name "allowed" -value "True"
    }

    Configure-ClaimIssuers $web $settings

    Configure-MachineKeys $web $settings

    CreateFlightingCacheFolder $settings
    Configure-FlightingCachePath $web $settings

    $web.Save("$($settings.'Infrastructure.WebRoot')\web.config")
}

function Update-WifConfig($settings)
{
    $siteAdmin = $settings.'Provisioning.AdminPrincipalName'

    Write-Log "Reading wif.config at $($settings.'Infrastructure.WebRoot')"

    $wifConfig = (Get-Content "$($settings.'Infrastructure.WebRoot')\wif.config").Replace('TENANT_ID_PLACEHOLDER',"$($siteAdmin.Split('@')[1])")
    $wifConfig = $wifConfig.Replace('https://sts.windows.net/',$settings.'Provisioning.AdminIdentityProvider')

    Add-Type -AssemblyName "System.Xml"

    Write-Log "Adding dynamic trusted certificates to wif.config"
    [xml]$wif = Get-Content "$($settings.'Infrastructure.WebRoot')\wif.config"

    $issuerNameRegistry = $wif.SelectSingleNode("system.identityModel/identityConfiguration/securityTokenHandlers/securityTokenHandlerConfiguration/issuerNameRegistry")
    $authorities = $issuerNameRegistry.SelectNodes("authority")
    $TrustedCerts = $($settings.'Infrastructure.TrustedCertificates').Split(';')

    $TrustedIssuer = $null
    $TokenIssuer = $authorities | where { $_.name -eq $($settings.'Aad.AcsTokenIssuer') }
    $TokenIssuerKeys = $null

    if ($TokenIssuer -ne $null)
    {
        $TokenIssuerKeys = $TokenIssuer.SelectSingleNode("keys")
    }

    foreach($TrustedCert in $TrustedCerts)
    {
        foreach ($auth in $authorities)
        {
            $TrustedIssuer = $auth.keys.add | where thumbprint -eq $TrustedCert

            if ($TrustedIssuer -ne $null)
            {
                break
            }
        }

        if ($TrustedIssuer -eq $null)
        {
            if ($TokenIssuer -eq $null)
            {
                $TokenIssuer = $wif.CreateElement("authority")
                $TokenIssuer.SetAttribute("name",$($settings.'Aad.AcsTokenIssuer'))

                $TokenIssuerKeys = $wif.CreateElement("keys")
                $TokenIssuer.AppendChild($TokenIssuerKeys)

                $ValidIssuers = $wif.CreateElement("validIssuers")

                $newAdd = $wif.CreateElement("add")
                $newAdd.SetAttribute("name", $($settings.'Aad.AcsTokenIssuer'))
                $ValidIssuers.AppendChild($newAdd)

                $TokenIssuer.AppendChild($ValidIssuers)

                $issuerNameRegistry.AppendChild($TokenIssuer) | Out-Null
            }

            $newAdd = $wif.CreateElement("add")
            $newAdd.SetAttribute("thumbprint", $TrustedCert)
            $TokenIssuerKeys.AppendChild($newAdd)
        }
    }

    Write-Log "Removing duplicate authorities in wif.config"
    #we only dedup based on the authority name since a static authority only has one issuer/thumbprint

    $authorities = $issuerNameRegistry.SelectNodes("authority")
    $uniqueAuthorities  = New-Object 'System.Collections.Generic.HashSet[System.Xml.XmlElement]'
    foreach($auth in $authorities)
    {
        $existingAuth = $uniqueAuthorities | Where-Object {$_.name -eq $auth.name}
        if ($existingAuth -eq $null)
        {
            $newAuth = $wif.CreateElement("authority")
            $newAuth.SetAttribute("name",$auth.name)
            $newAuth.InnerXml = $auth.InnerXml
            $uniqueAuthorities.Add($newAuth) | Out-Null
        }
    }

    $type = $issuerNameRegistry.type
    $issuerNameRegistry.RemoveAll()
    $issuerNameRegistry.SetAttribute("type", $type)

    foreach($auth in $uniqueAuthorities)
    {
        $issuerNameRegistry.AppendChild($auth) | Out-Null
    }

    $wif.Save("$($settings.'Infrastructure.WebRoot')\wif.config")
}

Initialize-Log $log
Write-Log "Decoding settings"
$settings = Decode-Settings $config

Write-Log "Updating AOS web.config"
Update-WebConfig $settings
Write-Log "AOS web.config update complete"

Write-Log "Updating AOS wif.config"
Update-WifConfig $settings
Write-Log "AOS wif.config update complete"

Write-Log "Updating AOS web.services.config"
Update-WifServicesConfig $settings
Write-Log "AOS web.services.config update complete"

#Temporary removing this:
#if these are present DBSync assumes we are in local onebox mode and behaves differently
#Set-RegistryValues $settings

Write-Log "Restarting IIS"
iisreset

Write-Log "Finished, exiting"

# SIG # Begin signature block
# MIIj/AYJKoZIhvcNAQcCoIIj7TCCI+kCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCDahQB5Dd+kujC+
# 8ox6uRHHdogIh9t5Zh50/B9rsCdF5KCCDYIwggYAMIID6KADAgECAhMzAAAAww6b
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
# SEXAQsmbdlsKgEhr/Xmfwb1tbWrJUnMTDXpQzTGCFdAwghXMAgEBMIGVMH4xCzAJ
# BgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25k
# MR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xKDAmBgNVBAMTH01pY3Jv
# c29mdCBDb2RlIFNpZ25pbmcgUENBIDIwMTECEzMAAADDDpun2LLc9ywAAAAAAMMw
# DQYJYIZIAWUDBAIBBQCggcIwGQYJKoZIhvcNAQkDMQwGCisGAQQBgjcCAQQwHAYK
# KwYBBAGCNwIBCzEOMAwGCisGAQQBgjcCARUwLwYJKoZIhvcNAQkEMSIEIKYnlxWI
# 1POmtZ0RxoMl3n6Fon2JdQVnNYSF+W/cmYNuMFYGCisGAQQBgjcCAQwxSDBGoCiA
# JgBVAHAAZABhAHQAZQBXAGUAYgBDAG8AbgBmAGkAZwAuAHAAcwAxoRqAGGh0dHA6
# Ly93d3cubWljcm9zb2Z0LmNvbTANBgkqhkiG9w0BAQEFAASCAQAq7n/EeLI+Vi0n
# 0WTfp/oOdcHDzglXKAYEpb03TOkZ6YIjFBfdxLri5JsDK7SRgPu2pUN5ZuW8/sON
# 1BUfpVl2ku6LuwH+7DJStq8uBiGC6kK4EAYUzX6AlUf3TflI7iDv7fuzmrJcs3j/
# ySzCl6DrVlItLDotLPAhzJTFXo1s18vMibZ5pQfn9vSHvFraM+4d8h4bh/WLtYpk
# MjOqWI3kSdBZO5dfqcVlfr6JOlJtZrPSmI53eGOWOu8Mb+WxYELtm/QEOdP7PJT+
# dfNWTjC5iOPm4PGG7R3d7RrcVt7aJSKlN1cX7dMFF+9i+T+3wtfM6hP7TgATKMPX
# lVYx3FF7oYITRjCCE0IGCisGAQQBgjcDAwExghMyMIITLgYJKoZIhvcNAQcCoIIT
# HzCCExsCAQMxDzANBglghkgBZQMEAgEFADCCATwGCyqGSIb3DQEJEAEEoIIBKwSC
# AScwggEjAgEBBgorBgEEAYRZCgMBMDEwDQYJYIZIAWUDBAIBBQAEINX3pbUr0Jbc
# PLYVj0YosBx9s6HEQvntIL4MxA/GfTpJAgZaso1Mr7gYEzIwMTgwMzI1MjEwNTUy
# LjQ5M1owBwIBAYACA+eggbikgbUwgbIxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpX
# YXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQg
# Q29ycG9yYXRpb24xDDAKBgNVBAsTA0FPQzEnMCUGA1UECxMebkNpcGhlciBEU0Ug
# RVNOOjg0M0QtMzdGNi1GMTA0MSUwIwYDVQQDExxNaWNyb3NvZnQgVGltZS1TdGFt
# cCBTZXJ2aWNloIIOyjCCBnEwggRZoAMCAQICCmEJgSoAAAAAAAIwDQYJKoZIhvcN
# AQELBQAwgYgxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYD
# VQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xMjAw
# BgNVBAMTKU1pY3Jvc29mdCBSb290IENlcnRpZmljYXRlIEF1dGhvcml0eSAyMDEw
# MB4XDTEwMDcwMTIxMzY1NVoXDTI1MDcwMTIxNDY1NVowfDELMAkGA1UEBhMCVVMx
# EzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoT
# FU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRpbWUt
# U3RhbXAgUENBIDIwMTAwggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIBAQCp
# HQ28dxGKOiDs/BOX9fp/aZRrdFQQ1aUKAIKF++18aEssX8XD5WHCdrc+Zitb8BVT
# JwQxH0EbGpUdzgkTjnxhMFmxMEQP8WCIhFRDDNdNuDgIs0Ldk6zWczBXJoKjRQ3Q
# 6vVHgc2/JGAyWGBG8lhHhjKEHnRhZ5FfgVSxz5NMksHEpl3RYRNuKMYa+YaAu99h
# /EbBJx0kZxJyGiGKr0tkiVBisV39dx898Fd1rL2KQk1AUdEPnAY+Z3/1ZsADlkR+
# 79BL/W7lmsqxqPJ6Kgox8NpOBpG2iAg16HgcsOmZzTznL0S6p/TcZL2kAcEgCZN4
# zfy8wMlEXV4WnAEFTyJNAgMBAAGjggHmMIIB4jAQBgkrBgEEAYI3FQEEAwIBADAd
# BgNVHQ4EFgQU1WM6XIoxkPNDe3xGG8UzaFqFbVUwGQYJKwYBBAGCNxQCBAweCgBT
# AHUAYgBDAEEwCwYDVR0PBAQDAgGGMA8GA1UdEwEB/wQFMAMBAf8wHwYDVR0jBBgw
# FoAU1fZWy4/oolxiaNE9lJBb186aGMQwVgYDVR0fBE8wTTBLoEmgR4ZFaHR0cDov
# L2NybC5taWNyb3NvZnQuY29tL3BraS9jcmwvcHJvZHVjdHMvTWljUm9vQ2VyQXV0
# XzIwMTAtMDYtMjMuY3JsMFoGCCsGAQUFBwEBBE4wTDBKBggrBgEFBQcwAoY+aHR0
# cDovL3d3dy5taWNyb3NvZnQuY29tL3BraS9jZXJ0cy9NaWNSb29DZXJBdXRfMjAx
# MC0wNi0yMy5jcnQwgaAGA1UdIAEB/wSBlTCBkjCBjwYJKwYBBAGCNy4DMIGBMD0G
# CCsGAQUFBwIBFjFodHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20vUEtJL2RvY3MvQ1BT
# L2RlZmF1bHQuaHRtMEAGCCsGAQUFBwICMDQeMiAdAEwAZQBnAGEAbABfAFAAbwBs
# AGkAYwB5AF8AUwB0AGEAdABlAG0AZQBuAHQALiAdMA0GCSqGSIb3DQEBCwUAA4IC
# AQAH5ohRDeLG4Jg/gXEDPZ2joSFvs+umzPUxvs8F4qn++ldtGTCzwsVmyWrf9efw
# eL3HqJ4l4/m87WtUVwgrUYJEEvu5U4zM9GASinbMQEBBm9xcF/9c+V4XNZgkVkt0
# 70IQyK+/f8Z/8jd9Wj8c8pl5SpFSAK84Dxf1L3mBZdmptWvkx872ynoAb0swRCQi
# PM/tA6WWj1kpvLb9BOFwnzJKJ/1Vry/+tuWOM7tiX5rbV0Dp8c6ZZpCM/2pif93F
# SguRJuI57BlKcWOdeyFtw5yjojz6f32WapB4pm3S4Zz5Hfw42JT0xqUKloakvZ4a
# rgRCg7i1gJsiOCC1JeVk7Pf0v35jWSUPei45V3aicaoGig+JFrphpxHLmtgOR5qA
# xdDNp9DvfYPw4TtxCd9ddJgiCGHasFAeb73x4QDf5zEHpJM692VHeOj4qEir995y
# fmFrb3epgcunCaw5u+zGy9iCtHLNHfS4hQEegPsbiSpUObJb2sgNVZl6h3M7COaY
# LeqN4DMuEin1wC9UJyH3yKxO2ii4sanblrKnQqLJzxlBTeCG+SqaoxFmMNO7dDJL
# 32N79ZmKLxvHIa9Zta7cRDyXUHHXodLFVeNp3lfB0d4wwP3M5k37Db9dT+mdHhk4
# L7zPWAUu7w2gUDXa7wknHNWzfjUeCLraNtvTX4/edIhJEjCCBNkwggPBoAMCAQIC
# EzMAAACpVHDZecCEZeIAAAAAAKkwDQYJKoZIhvcNAQELBQAwfDELMAkGA1UEBhMC
# VVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNV
# BAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRp
# bWUtU3RhbXAgUENBIDIwMTAwHhcNMTYwOTA3MTc1NjUzWhcNMTgwOTA3MTc1NjUz
# WjCBsjELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcT
# B1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEMMAoGA1UE
# CxMDQU9DMScwJQYDVQQLEx5uQ2lwaGVyIERTRSBFU046ODQzRC0zN0Y2LUYxMDQx
# JTAjBgNVBAMTHE1pY3Jvc29mdCBUaW1lLVN0YW1wIFNlcnZpY2UwggEiMA0GCSqG
# SIb3DQEBAQUAA4IBDwAwggEKAoIBAQCslIUYpuVW053fA2cu25iRR4+ViXJNmnTz
# NEDeaxGn1MeSfg7/nzU6f6dkjHGbYcUZWT6UXZEvTsDtwUBuJweR1OWs9h48zlAR
# UydohNLSZqQfbh17KYsm4wmudOdM/J+Dt0YN2xWpDftX97ObEN4MHKRNGsOWJEY2
# KZBc3h1H1pc/Qo0H/6gvJ47rEhCxR0L3BL05NsTFu8DstryOgZzJ3bJAPD2j6xu9
# MHX+WwVzHRQxEdTwOr/s0RPeRMnE/kjhV8QueAgVfvNFBjZJtrX9WB0R3YhkA0IQ
# Oe+uUxZGEVtcfRJad0h2cClhIRqTU5wiaW6ctHl6jkw4hBUZbF+hAgMBAAGjggEb
# MIIBFzAdBgNVHQ4EFgQUD9VB+7vznfS+SVLajDdXzmQP830wHwYDVR0jBBgwFoAU
# 1WM6XIoxkPNDe3xGG8UzaFqFbVUwVgYDVR0fBE8wTTBLoEmgR4ZFaHR0cDovL2Ny
# bC5taWNyb3NvZnQuY29tL3BraS9jcmwvcHJvZHVjdHMvTWljVGltU3RhUENBXzIw
# MTAtMDctMDEuY3JsMFoGCCsGAQUFBwEBBE4wTDBKBggrBgEFBQcwAoY+aHR0cDov
# L3d3dy5taWNyb3NvZnQuY29tL3BraS9jZXJ0cy9NaWNUaW1TdGFQQ0FfMjAxMC0w
# Ny0wMS5jcnQwDAYDVR0TAQH/BAIwADATBgNVHSUEDDAKBggrBgEFBQcDCDANBgkq
# hkiG9w0BAQsFAAOCAQEACJkYpQeLL3IkdSyOIIQC/Qqhrw7hsDIRhqrFhiCdu+hE
# O5XMtTrni0alE9OMIBuoOlccFfdzbY0LsgdFboZFdiRGunRM8TZvUp225OSUjMkp
# q4mqvnKC07qbVauggjngGS7YEa1FiQNLwC/iAJ64e4fbytd1uC4EtIyTN4oeJkTk
# 2UFljtFCuV4TELwZZ3W7zoSp6R+Oe88blLg5XW1XWewKfsbWlQ075/qIL1asVQRQ
# cmc/sgADw47C/D7Ilavg1Ge2pjRttGAIskKJ3n9g2lghvNOMODJT8grM298ktwDr
# k0o/CXo0O0vAc2tqUoRToZsERFlhQq1y8EDAbvyasqGCA3QwggJcAgEBMIHioYG4
# pIG1MIGyMQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UE
# BxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMQwwCgYD
# VQQLEwNBT0MxJzAlBgNVBAsTHm5DaXBoZXIgRFNFIEVTTjo4NDNELTM3RjYtRjEw
# NDElMCMGA1UEAxMcTWljcm9zb2Z0IFRpbWUtU3RhbXAgU2VydmljZaIlCgEBMAkG
# BSsOAwIaBQADFQBdOr9WveEPKcpyDmT3dTt4GiLr9KCBwTCBvqSBuzCBuDELMAkG
# A1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQx
# HjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEMMAoGA1UECxMDQU9DMScw
# JQYDVQQLEx5uQ2lwaGVyIE5UUyBFU046MjY2NS00QzNGLUM1REUxKzApBgNVBAMT
# Ik1pY3Jvc29mdCBUaW1lIFNvdXJjZSBNYXN0ZXIgQ2xvY2swDQYJKoZIhvcNAQEF
# BQACBQDeYejsMCIYDzIwMTgwMzI1MDkyMjUyWhgPMjAxODAzMjYwOTIyNTJaMHQw
# OgYKKwYBBAGEWQoEATEsMCowCgIFAN5h6OwCAQAwBwIBAAICH9MwBwIBAAICGVww
# CgIFAN5jOmwCAQAwNgYKKwYBBAGEWQoEAjEoMCYwDAYKKwYBBAGEWQoDAaAKMAgC
# AQACAx6AmKEKMAgCAQACAx6EgDANBgkqhkiG9w0BAQUFAAOCAQEAC2klNe31ZiZG
# QEVC/K6I1T/Ts9QY32V7H28X0ra4Urwht2nDbqwQ+arso8iVlKfDg6cuR35zjvmH
# jKGyY+B2JVYhcXPHlTptpDHTaJ2iMM8Yoaue9RBG69RBW+OglAaBIP0EtyDGJ7cO
# mU+c5FLmbhsfG+zzFMbh54PCPOWseLI6Kpxk0VCc+zhLhPJAwRTcTm0YRwcCkzMo
# p5L6wdr85myns+C7O+sFKPXlpRTtyDZ89DnqzSSxPhOlxP+xBTe/uovPx1UaKh8P
# wfYi5qUB8yfHKX5IZ+AXyjAs36VwNOTOusI7oz9JTRhGVQ8fTpXNCfN278BNiZfn
# oXEr7DLpUjGCAvUwggLxAgEBMIGTMHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpX
# YXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQg
# Q29ycG9yYXRpb24xJjAkBgNVBAMTHU1pY3Jvc29mdCBUaW1lLVN0YW1wIFBDQSAy
# MDEwAhMzAAAAqVRw2XnAhGXiAAAAAACpMA0GCWCGSAFlAwQCAQUAoIIBMjAaBgkq
# hkiG9w0BCQMxDQYLKoZIhvcNAQkQAQQwLwYJKoZIhvcNAQkEMSIEIEnq3vobkL4s
# hAzvE8whTJOFoDYkF3d5FtsECUuVd3ehMIHiBgsqhkiG9w0BCRACDDGB0jCBzzCB
# zDCBsQQUXTq/Vr3hDynKcg5k93U7eBoi6/QwgZgwgYCkfjB8MQswCQYDVQQGEwJV
# UzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UE
# ChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGlt
# ZS1TdGFtcCBQQ0EgMjAxMAITMwAAAKlUcNl5wIRl4gAAAAAAqTAWBBTkCtG9AozN
# q2cbrRd90AAju+6lbTANBgkqhkiG9w0BAQsFAASCAQCTc663F/9Davh70c/Yb1pN
# xAxppSdSLiOCZFHTTzn1SNTFbeBQfnFCCr5q0hrBc87TTKF2/GqQJpt2+uqbRnWK
# tILzA0ErFC9GVSGB3obVhCh5xLZl83gnCy7oCXesb7qx8+cNwQ+IbnDReD2xbTmd
# g8+sbFX6i62EJBrQ/8+s9+ahl1a8rhsO/FOrrY1zdfPnlpT7amjovJagmCQ7LgC6
# 224PGt1W1wQymgmlzo+obhw7B4jwo20KHUiNqqaz4hFQtPYVlX5YkJ4KMEnEw8rf
# 8djK6LHDsFKliUKlPkCoyk3+Bqud99BzLE7mKKKbl6Ph/TZnjwikrsYlbvEpyQXd
# SIG # End signature block
