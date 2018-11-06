$global:logfile=""
$NEWSETTING = "###CTP8###"
$BatchService = "DynamicsAxBatch"
$PrintService = "DynamicsAXPrintService"
$DataSigningCertThumbprintLegacyKey="DataAccess.DataSigningCertificateThumbprintLegacy"
$DataEncryptionCertThumbprintLegacyKey="DataAccess.DataEncryptionCertificateThumbprintLegacy"
$DataSigningCertThumbprintKey="DataAccess.DataSigningCertificateThumbprint"
$DataEncryptionCertThumbprintKey="DataAccess.DataEncryptionCertificateThumbprint"
$configEncryptor="Microsoft.Dynamics.AX.Framework.ConfigEncryptor.exe"
$InternalServiceCertThumbprints="Infrastructure.InternalServiceCertificateThumbprints"
$DataAccessAxAdminSqlPwd="DataAccess.AxAdminSqlPwd"
$DataAccessAxAdminSqlUser="DataAccess.AxAdminSqlUser"

$ErrorActionPreference="Stop"

function Initialize-Log([string]$log)
{
    if(Test-Path -Path $log)
    {
        Write-Output "Removing the existing log file '$log'."
        Remove-Item -Path $log -Force|Out-Null
    }

    Write-Output "Creating the log file '$log'."
    New-Item -Path $log -ItemType File -Force|out-null
    $global:logfile=$log
}

function Write-Log([string]$message)
{
    $datetime=Get-Date -Format "MM-dd-yyyy:HH:mm:ss"
    Add-Content -Path $global:logfile -Value "$datetime`: $message"|out-null
    Write-Output "$datetime`: $message"
}

function Log-Error([string]$error,[switch]$throw)
{
    Write-Error $error
    if($throw)
    {
        throw $error
    }
}

function Create-Backup([string]$webroot,[string]$backupdir)
{
    $orig_webconfig= Join-Path -Path $webroot -ChildPath "web.config"
    $orig_wifconfig= Join-Path -Path $webroot -ChildPath "wif.config"
    $orig_wifservicesconfig=Join-Path -Path $webroot -ChildPath "wif.services.config"

    $backup_webconfig= Join-Path -Path $backupdir -ChildPath "web.config.backup"
    $backup_wifconfig= Join-Path -Path $backupdir -ChildPath "wif.config.backup"
    $backup_wifservicesconfig=Join-Path -Path $backupdir -ChildPath "wif.services.config.backup"
    
    Copy-Item -Path $orig_webconfig -Destination $backup_webconfig -Force|out-null
    Write-Log "Copied '$orig_webconfig' to '$backup_webconfig."

    Copy-item -Path $orig_wifconfig -Destination $backup_wifconfig -Force|out-null
    Write-Log "Copied '$orig_wifconfig' to '$backup_wifconfig'."

    Copy-item -Path $orig_wifservicesconfig -Destination $backup_wifservicesconfig -Force|out-null
    Write-Log "Copied '$orig_wifservicesconfig' to '$backup_wifservicesconfig'."
}

function Upgrade-Web-Config([string]$webroot,[string]$ctp8configdir)
{
    Decrypt-Config -webroot:$webroot
    Upgrade-App-Settings -webroot:$webroot -parentdir:$ctp8configdir
    Upgrade-Bindings -webroot:$webroot -parentdir:$ctp8configdir
    Upgrade-Service-Behaviors -webroot:$webroot -parentdir:$ctp8configdir
    Update-Machine-Config-Keys -webroot:$webroot -parenrdir:$ctp8configdir

    $ctp7webconfig=Join-Path -Path $webroot -ChildPath "web.config"
    $ctp7webconfigbackup=Join-Path -Path $webroot -ChildPath "web.config.ctp7"
    $ctp8webconfig=Join-Path -Path $webroot -ChildPath "web.config.ctp8"
    $webconfig=Join-Path -Path $webroot -ChildPath "web.config"
    
    Rename-File -from:$ctp8webconfig -to:$webconfig
    Encrypt-Config -webroot:$webroot
}

function Upgrade-Wif-Config([string]$webroot,[string]$ctp8configdir)
{
    $ctp7wifconfig=Join-Path -Path $webroot -ChildPath "wif.config"
    $ctp8_wifconfig_template=Join-Path -Path $ctp8configdir -ChildPath "wif.config"
    $ctp8wifconfig=Join-Path -Path $webroot -ChildPath "wif.config.ctp8"
    Copy-Item -Path $ctp8_wifconfig_template -Destination $ctp8wifconfig -Force |out-null
    Write-Log "Copied the CTP8 wif.config template from '$ctp8_wifconfig_template' to '$ctp8wifconfig'."

    [System.Xml.XmlDocument] $ctp7xd = new-object System.Xml.XmlDocument
    $ctp7xd.Load($ctp7wifconfig)

    [System.Xml.XmlDocument] $ctp8xd = new-object System.Xml.XmlDocument
    $ctp8xd.Load($ctp8wifconfig)

    #region audienceUris
    $ctp7audienceUri=$ctp7xd.SelectSingleNode("/system.identityModel/identityConfiguration/securityTokenHandlers/securityTokenHandlerConfiguration/audienceUris/add")
    if($ctp7audienceUri -ne $null)
    {
        $ctp7audienceUriValue=$ctp7audienceUri.Attributes.GetNamedItem("value").Value
        $ctp8audienceUri=$ctp8xd.SelectSingleNode("/system.identityModel/identityConfiguration/securityTokenHandlers/securityTokenHandlerConfiguration/audienceUris/add")
        $ctp8audienceUri.Attributes.GetNamedItem("value").Value=$ctp7audienceUriValue
        Write-Log "setting the audienceUri value to '$ctp7audienceUriValue'."
    }

    $ctp8xd.Save($ctp8wifconfig)
    #endregion

    #region authority
    $ctp8IssuerNameRegistry=$ctp8xd.SelectSingleNode("/system.identityModel/identityConfiguration/securityTokenHandlers/securityTokenHandlerConfiguration/issuerNameRegistry")
    $ctp7AuthorityNameNodes=$ctp7xd.SelectNodes("/system.identityModel/identityConfiguration/securityTokenHandlers/securityTokenHandlerConfiguration/issuerNameRegistry/authority/@name")
    $ctp8AuthorityNameNodes=$ctp8xd.SelectNodes("/system.identityModel/identityConfiguration/securityTokenHandlers/securityTokenHandlerConfiguration/issuerNameRegistry/authority/@name")

    $ctp7AuthorityNames=@()
    $ctp8AuthorityNames=@()

    foreach($authority in $ctp7AuthorityNameNodes)
    {
        $ctp7AuthorityNames += $authority.'#text'
    }

    foreach($authority in $ctp8AuthorityNameNodes)
    {
        $ctp8AuthorityNames += $authority.'#text'
    }

    $ctp7UniqueAuthorities=$ctp7AuthorityNames|?{-not ($ctp8AuthorityNames -contains $_)}
    $intersection=$ctp7AuthorityNames|?{($ctp8AuthorityNames -contains $_)}
    
    # process the intersections
    foreach($name in $intersection)
    {
        $ctp7authority=$ctp7xd.SelectSingleNode("/system.identityModel/identityConfiguration/securityTokenHandlers/securityTokenHandlerConfiguration/issuerNameRegistry/authority[@name='$name']")
        $ctp8authoritykeys=$ctp8xd.SelectNodes("/system.identityModel/identityConfiguration/securityTokenHandlers/securityTokenHandlerConfiguration/issuerNameRegistry/authority[@name='$name']/keys")

        # remove the CTP8 authority keys
        $ctp8authoritykeys.RemoveAll()|out-null

        # get the thumbprint value(s) from the ctp7 wif.config and update it in the ctp8 wif.config
        $ctp7authoritykeys=$ctp7xd.SelectSingleNode("/system.identityModel/identityConfiguration/securityTokenHandlers/securityTokenHandlerConfiguration/issuerNameRegistry/authority[@name='$name']/keys/add")

        # add the authority keys from the CTP7 wif.config
        foreach($authoritykey in $ctp7authoritykeys)
        {
            $thumbprint=$authoritykey.Attributes.GetNamedItem("thumbprint").Value
            $newauthority = $ctp8xd.CreateElement("add")
            $newauthority.SetAttribute("thumbprint",$thumbprint)|out-null
            $ctp8authoritykeys.AppendChild($newauthority)|out-null
            Write-Log "Added an authority key to authority '$name' with thumbprint '$thumbprint'."
        }
    }

    # add the ctp7 only authorities to ctp8
    foreach($name in $ctp7UniqueAuthorities)
    {
        $ctp7Authority=$ctp7xd.SelectSingleNode("/system.identityModel/identityConfiguration/securityTokenHandlers/securityTokenHandlerConfiguration/issuerNameRegistry/authority[@name='$name']")
        $newauthority=$ctp8xd.CreateElement("authority")
        $newauthority.SetAttribute("name",$ctp7Authority.Attributes.GetNamedItem("name").Value)|out-null
        $newkeys=$ctp8xd.CreateElement("keys")
        $newValidIssuers=$ctp8xd.CreateElement("validIssuers")

        # add thumbprints
        foreach($thumbprint in $ctp7Authority.keys.add)
        {
            $newthumbprint = $ctp8xd.CreateElement("add")
            $newthumbprint.SetAttribute("thumbprint",$thumbprint.Attributes.GetNamedItem("thumbprint").value)|out-null
            $newkeys.AppendChild($newthumbprint)|out-null
        }

        # add valid issuers
        foreach($validIssuer in $ctp7Authority.validIssuers.add)
        {
            $newValidIssuer = $ctp8xd.CreateElement("add")
            $newValidIssuer.SetAttribute("name",$validIssuer.Attributes.GetNamedItem("name").value)|out-null
            $newValidIssuers.AppendChild($newValidIssuer)|out-null
        }

        $newauthority.AppendChild($newkeys)|out-null
        $newauthority.AppendChild($newValidIssuers)|out-null
        $ctp8IssuerNameRegistry.AppendChild($newAuthority)|out-null
    }

    $ctp8xd.Save($ctp8wifconfig)
    
    # set the thumbprints for the AxTokenIssuer authority
    $wc = Join-Path -Path $webroot -ChildPath "web.config"
    [System.Xml.XmlDocument] $wcxd = new-object System.Xml.XmlDocument
    $wcxd.Load($wc)

    $ctp8xd.Load($ctp8wifconfig)
    $trustedThumbprintsNode = $wcxd.SelectSingleNode("/configuration/appSettings/add[@key='Infrastructure.TrustedCertificates']")
    if($trustedThumbprintsNode -ne $null)
    {
        $trustedThumbprints =  $trustedThumbprintsNode.Attributes.GetNamedItem("value").Value
        [string[]]$thumbprints = $trustedThumbprints.Split(";")
        $axTokenIssuerKeys = $ctp8xd.SelectSingleNode("/system.identityModel/identityConfiguration/securityTokenHandlers/securityTokenHandlerConfiguration/issuerNameRegistry/authority[@name='AxTokenIssuer']/keys")
        $axTokenIssuers = $ctp8xd.SelectNodes("/system.identityModel/identityConfiguration/securityTokenHandlers/securityTokenHandlerConfiguration/issuerNameRegistry/authority[@name='AxTokenIssuer']/keys/add")

        if($axTokenIssuers -ne $null)
        {
            $axTokenIssuers.RemoveAll()|out-null
        }

        foreach($thumbprint in $thumbprints)
        {
            $newthumbprint = $ctp8xd.CreateElement("add")
            $newthumbprint.SetAttribute("thumbprint",$thumbprint)|out-null
            $axTokenIssuerKeys.AppendChild($newthumbprint)|out-null
        }

        $ctp8xd.Save($ctp8wifconfig)
    }
    #endregion

     Write-Log "Saved the CTP8 wif.config with updated values from CTP7 wif.config."

     # replace the wif.config file
     $wifconfig=Join-Path -Path $webroot -ChildPath "wif.config"
     Rename-File -from:$ctp8wifconfig -to:$wifconfig
}

function Upgrade-Wif-Services-Config([string]$webroot,[string]$ctp8configdir)
{
    $ctp7wifservicesconfig=Join-Path -Path $webroot -ChildPath "wif.services.config"
    $ctp8_wifservicesconfig_template=Join-Path -Path $ctp8configdir -ChildPath "wif.services.config"
    $ctp8wifservicesconfig=Join-Path -Path $webroot -ChildPath "wif.services.config.ctp8"
    Copy-Item -Path $ctp8_wifservicesconfig_template -Destination $ctp8wifservicesconfig -Force |out-null
    Write-Log "Copied the CTP8 wif.services.config template from '$ctp8_wifservicesconfig_template' to '$ctp8wifservicesconfig'."

    [System.Xml.XmlDocument] $ctp7xd = new-object System.Xml.XmlDocument
    $ctp7xd.Load($ctp7wifservicesconfig)

    [System.Xml.XmlDocument] $ctp8xd = new-object System.Xml.XmlDocument
    $ctp8xd.Load($ctp8wifservicesconfig)

    #region wsFederation
    $ctp8wsfederation=$ctp8xd.SelectSingleNode("/system.identityModel.services/federationConfiguration/wsFederation")
    $ctp7wsfederation=$ctp7xd.SelectSingleNode("/system.identityModel.services/federationConfiguration/wsFederation")

    # replace reply url
    $ctp7reply=$ctp7wsfederation.Attributes.GetNamedItem("reply").Value
    $ctp8wsfederation.Attributes.GetNamedItem("reply").Value=$ctp7reply
    Write-Log "Setting wsFederation reply='$ctp7reply'."

    # replace realm
    $ctp7realm=$ctp7wsfederation.Attributes.GetNamedItem("realm").Value
    $ctp8wsfederation.Attributes.GetNamedItem("realm").Value=$ctp7realm
    Write-Log "Setting wsFederation relam='$ctp7realm'."

    # replace issuer
    $ctp7issuer=$ctp7wsfederation.Attributes.GetNamedItem("issuer").Value
    $ctp8wsfederation.Attributes.GetNamedItem("issuer").Value=$ctp7issuer
    Write-Log "Setting wsFederation issuer='$ctp7issuer'."

    #endregion

    #region cookieHandler
    $ctp8cookieHandler=$ctp8xd.SelectSingleNode("/system.identityModel.services/federationConfiguration/cookieHandler")
    $ctp7cookieHandler=$ctp7xd.SelectSingleNode("/system.identityModel.services/federationConfiguration/cookieHandler")

    #replace path
    $ctp7path=$ctp7cookieHandler.Attributes.GetNamedItem("path").Value
    $ctp8cookieHandler.Attributes.GetNamedItem("path").Value=$ctp7path
    Write-Log "Setting cookie handler path='$path'."

    # replace domain
    $ctp7domain=$ctp7cookieHandler.Attributes.GetNamedItem("domain").Value
    $ctp8cookieHandler.Attributes.GetNamedItem("domain").Value=$ctp7domain
    Write-Log "Setting cookie handler domain='$ctp7domain'."
    #endregion

    #region certificateReference
    $ctp8certReference=$ctp8xd.SelectSingleNode("/system.identityModel.services/federationConfiguration/serviceCertificate/certificateReference")
    $ctp7certReference=$ctp7xd.SelectSingleNode("/system.identityModel.services/federationConfiguration/serviceCertificate/certificateReference")

    # replace findValue
    $ctp7findValue=$ctp7certReference.Attributes.GetNamedItem("findValue").Value
    $ctp8certReference.Attributes.GetNamedItem("findValue").Value=$ctp7findValue
    Write-Log "Setting certificateReference findValue='$ctp7findValue'."
    #endregion
    
    $ctp8xd.Save($ctp8wifservicesconfig)
    Write-Log "Saved the CTP8 wif.services.config with updated values from CTP7 wif.services.config."
    
    # replace the wif.services.config file
    $wifservicesconfig=Join-Path -Path $webroot -ChildPath "wif.services.config"
    Rename-File -from:$ctp8wifservicesconfig -to:$wifservicesconfig
}

function Upgrade-App-Settings([string]$webroot,[string]$parentdir)
{
    $ctp7webconfig=Join-Path -Path $webroot -ChildPath "web.config"
    $ctp8_webconfig_template=Join-Path -Path $ctp8configdir -ChildPath "web.config"
    $ctp8webconfig=Join-Path -Path $webroot -ChildPath "web.config.ctp8"
    Copy-Item -Path $ctp8_webconfig_template -Destination $ctp8webconfig -Force |out-null
    Write-Log "Copied the CTP8 web.config template from '$ctp8_webconfig_template' to '$ctp8webconfig'."

    # add/update appsettings
    [System.Xml.XmlDocument] $ctp7xd = new-object System.Xml.XmlDocument
    $ctp7xd.Load($ctp7webconfig)

    [System.Xml.XmlDocument] $ctp8xd = new-object System.Xml.XmlDocument
    $ctp8xd.Load($ctp8webconfig)

    $ctp8appsettings=$ctp8xd.SelectNodes("/configuration/appSettings/add")

    foreach($setting in $ctp8appsettings)
    {
        $ctp8keyname=$setting.Attributes.GetNamedItem("key").Value

        # special handling for the 'DataAccess.DataEncryptionCertificateThumbprintLegacy' and 'DataAccess.DataSigningCertificateThumbprintLegacy' keys
        if($ctp8keyname -eq $DataSigningCertThumbprintLegacyKey)
        {
            # get the legacy signing cert thumbprint from the CTP7 web.config
            $signingcertthumbprintnode=$ctp7xd.SelectSingleNode("/configuration/appSettings/add[@key='$DataSigningCertThumbprintKey']")
            $keyvalue=$signingcertthumbprintnode.Attributes.GetNamedItem("value").Value
        }
        elseif($ctp8keyname -eq $DataEncryptionCertThumbprintLegacyKey)
        {
            # get the legacy encryption cert thumbprint from the CTP7 web.config
            $encryptioncertthumbprintnode=$ctp7xd.SelectSingleNode("/configuration/appSettings/add[@key='$DataEncryptionCertThumbprintKey']")
            $keyvalue=$encryptioncertthumbprintnode.Attributes.GetNamedItem("value").Value
        }
        elseif($ctp8keyname -eq $DataEncryptionCertThumbprintKey -or
                $ctp8keyname -eq $DataSigningCertThumbprintKey
               )
        {
            # if the key is either a encryption or signing cert thumbprint key, continue
            continue
        }
        elseif($ctp8keyname -eq $InternalServiceCertThumbprints)
        {
            # combine the existing thumbrints from the CTP7 web.config and the thumbprint in the ctp8 web.config
            # the ctp8 cert thumbprint should be the third value after the values are combined
            $internalservicecertthumbprintsnode=$ctp7xd.SelectSingleNode("/configuration/appSettings/add[@key='$InternalServiceCertThumbprints']")
            $ctp7value=$internalservicecertthumbprintsnode.Attributes.GetNamedItem("value").Value
            $ctp8value=$setting.Attributes.GetNamedItem("value").Value
            $keyvalue="$ctp7value`;$ctp8value"
        }
        elseif($ctp8keyname -eq $DataAccessAxAdminSqlUser)
        {
            $keyvalue=$ctp7xd.SelectSingleNode("/configuration/appSettings/add[@key='DataAccess.SqlUser']").Attributes.GetNamedItem("value").Value
        }
        elseif($ctp8keyname -eq $DataAccessAxAdminSqlPwd)
        {
            $keyvalue=$ctp7xd.SelectSingleNode("/configuration/appSettings/add[@key='DataAccess.SqlPwd']").Attributes.GetNamedItem("value").Value
        }
        else
        {
            # if the key exists in the ctp7 web.config use its value
            $ctp7keyname=$ctp7xd.SelectSingleNode("/configuration/appSettings/add[@key='$ctp8keyname']")
            if($ctp7keyname -eq $null)
            {
                # we found a new CTP8 appsetting. Update the key value to indicate it
                # $keyvalue=$NEWSETTING
            }
            else
            {
                # use the value from the ctp7 appsetting in the ctp8 appsetting
                $keyvalue=$ctp7keyname.Attributes.GetNamedItem("value").Value
            }
        }

        $setting.Attributes.GetNamedItem("value").Value=$keyvalue
        Write-Log "Setting '$ctp8keyname=$keyvalue'."
    }
    
    $ctp8xd.Save($ctp8webconfig)
    Write-Log "Saved the CTP8 web.config with the updated appsettings."
}

function Upgrade-Service-Behaviors([string]$webroot,[string]$parentdir)
{
    $ctp7webconfig=Join-Path -Path $webroot -ChildPath "web.config"
    $ctp8webconfig=Join-Path -Path $webroot -ChildPath "web.config.ctp8"

    [System.Xml.XmlDocument] $ctp7xd = new-object System.Xml.XmlDocument
    $ctp7xd.Load($ctp7webconfig)

    [System.Xml.XmlDocument] $ctp8xd = new-object System.Xml.XmlDocument
    $ctp8xd.Load($ctp8webconfig)

    # retrieve the service certificate thumbprint
    $servicecertthumbprint=Get-ServiceBehavior-Thumbprint -xmldoc:$ctp7xd

    if([system.string]::IsNullOrEmpty($servicecertthumbprint))
    {
        Log-Error "Unable to find the certificate thumbprint that is required to configure the service behaviors." -throw
    }

    # set the service certificate thumbprint to the ctp7 value
    $ctp8servicecertificates=$ctp8xd.SelectNodes("/configuration/location/system.serviceModel/behaviors/serviceBehaviors/behavior/serviceCredentials/serviceCertificate")
    foreach($servicecertificate in $ctp8servicecertificates)
    {
        $servicecertificate.Attributes.GetNamedItem("findValue").Value=$servicecertthumbprint
    }

    Write-Log "Setting the service behavior certificate thumbprint to '$servicecertthumbprint'."
    $ctp8xd.Save($ctp8webconfig)
}

function Upgrade-Bindings([string]$webroot,[string]$parentdir)
{
    # open both files
    $ctp7webconfig=Join-Path -Path $webroot -ChildPath "web.config"
    $ctp8webconfig=Join-Path -Path $webroot -ChildPath "web.config.ctp8"

    [System.Xml.XmlDocument] $ctp7xd = new-object System.Xml.XmlDocument
    $ctp7xd.Load($ctp7webconfig)

    [System.Xml.XmlDocument] $ctp8xd = new-object System.Xml.XmlDocument
    $ctp8xd.Load($ctp8webconfig)

    #region customBinding
    $ctp8customBindings = $ctp8xd.SelectNodes("/configuration/location/system.serviceModel/bindings/customBinding")
    foreach($binding in $ctp8customBindings)
    {
        $name=$binding.name
        $ctp7CustomBinding = $ctp7xd.SelectNodes("/configuration/location/system.serviceModel/bindings/customBinding/binding[@name='$name']")
        if($ctp7CustomBinding -ne $null)
        {
            $ctp7CustomBinding.sendTimeout = $binding.sendTimeout
            $ctp7CustomBinding.receiveTimeout = $binding.receiveTimeout
        


        # update security
        $ctp8Security = $ctp8xd.SelectSingleNode("/configuration/location/system.serviceModel/bindings/customBinding/binding[@name='$name']/security")
        $ctp7Security = $ctp7xd.SelectSingleNode("/configuration/location/system.serviceModel/bindings/customBinding/binding[@name='$name']/security")
     
        $ctp8Security.authenticationMode = $ctp7Security.authenticationMode
      
     

        # update issuedTokenParameters
        $ctp8IssuedTokenParameters = $ctp8xd.SelectSingleNode("/configuration/location/system.serviceModel/bindings/customBinding/binding[@name='$name']/security/issuedTokenParameters")
        $ctp7IssuedTokenParameters = $ctp7xd.SelectSingleNode("/configuration/location/system.serviceModel/bindings/customBinding/binding[@name='$name']/security/issuedTokenParameters")
        $ctp8IssuedTokenParameters.keyType = $ctp7IssuedTokenParameters.keyType
        $ctp8IssuedTokenParameters.tokenType = $ctp7IssuedTokenParameters.tokenType

        # update textMessageEncoding
        $ctp8textMessageEncodingReaderQuotas = $ctp8xd.SelectSingleNode("/configuration/location/system.serviceModel/bindings/customBinding/binding[@name='$name']/textMessageEncoding/readerQuotas")
        $ctp7textMessageEncodingReaderQuotas = $ctp7xd.SelectSingleNode("/configuration/location/system.serviceModel/bindings/customBinding/binding[@name='$name']/textMessageEncoding/readerQuotas")
        $ctp8textMessageEncodingReaderQuotas.maxDepth = $ctp7textMessageEncodingReaderQuotas.maxDepth 
        $ctp8textMessageEncodingReaderQuotas.maxStringContentLength = $ctp7textMessageEncodingReaderQuotas.maxStringContentLength
        $ctp8textMessageEncodingReaderQuotas.maxArrayLength = $ctp7textMessageEncodingReaderQuotas.maxArrayLength
        $ctp8textMessageEncodingReaderQuotas.maxBytesPerRead = $ctp7textMessageEncodingReaderQuotas.maxBytesPerRead
        $ctp8textMessageEncodingReaderQuotas.maxNameTableCharCount = $ctp7textMessageEncodingReaderQuotas.maxNameTableCharCount
        }
    }
    #endregion

    #region webHttpBinding
    $ctp8webHttpBinding = $ctp8xd.SelectNodes("/configuration/location/system.serviceModel/bindings/webHttpBinding")
    foreach($binding in $ctp8webHttpBinding)
    {
        $name=$binding.name
        $ctp7webHttpBinding = $ctp7xd.SelectSingleNode("/configuration/location/system.serviceModel/bindings/webHttpBinding/binding[@name='$name']")
        if($ctp7webHttpBinding -ne $null)
        {
            $binding.allowCookies = $ctp7webHttpBinding.allowCookies
            $binding.maxReceivedMessageSize = $ctp7webHttpBinding.maxReceivedMessageSize
            if($ctp7webHttpBinding.Attributes["contentTypeMapper"] -ne $null)
            {
                $binding.contentTypeMapper = $ctp7webHttpBinding.contentTypeMapper
            }
        

        # update security
        $ctp8webHttpBindingSecurity = $ctp8xd.SelectSingleNode("/configuration/location/system.serviceModel/bindings/webHttpBinding/binding[@name='$name']/security")
        $ctp7webHttpBindingSecurity = $ctp7xd.SelectSingleNode("/configuration/location/system.serviceModel/bindings/webHttpBinding/binding[@name='$name']/security")
        $ctp8webHttpBindingSecurity.mode = $ctp7webHttpBindingSecurity.mode

        # update readerQuotas
        $ctp8webHttpBindingReaderQuotas = $ctp8xd.SelectSingleNode("/configuration/location/system.serviceModel/bindings/webHttpBinding/binding[@name='$name']/readerQuotas")
        $ctp7webHttpBindingReaderQuotas = $ctp7xd.SelectSingleNode("/configuration/location/system.serviceModel/bindings/webHttpBinding/binding[@name='$name']/readerQuotas")
        $ctp8webHttpBindingReaderQuotas.maxStringContentLength = $ctp7webHttpBindingReaderQuotas.maxStringContentLength
        }
    }
    #endregion

    $ctp8xd.Save($ctp8webconfig)
    Write-Log "Upgraded the bindings."
}

function Update-Machine-Config-Keys([string]$webroot,[string]$parenrdir)
{
    $ctp7webconfig=Join-Path -Path $webroot -ChildPath "web.config"
    $ctp8webconfig=Join-Path -Path $webroot -ChildPath "web.config.ctp8"

    # load the web.config files
    [System.Xml.XmlDocument] $ctp7xd = new-object System.Xml.XmlDocument
    $ctp7xd.Load($ctp7webconfig)

    [System.Xml.XmlDocument] $ctp8xd = new-object System.Xml.XmlDocument
    $ctp8xd.Load($ctp8webconfig)

    # fetch the ctp7 machineKey values
    $ctp7machineKey = $ctp7xd.SelectSingleNode("/configuration/location/system.web/machineKey")
    $decryption=$ctp7machineKey.Attributes.GetNamedItem("decryption").Value
    $decryptionKey = $ctp7machineKey.Attributes.GetNamedItem("decryptionKey").Value
    $validationKey = $ctp7machineKey.Attributes.GetNamedItem("validationKey").Value
    $validation = $ctp7machineKey.Attributes.GetNamedItem("validation").Value

    # update the ctp8 machineKey values
    $ctp8machineKey=$ctp8xd.SelectSingleNode("/configuration/location/system.web/machineKey")
    $ctp8machineKey.Attributes.GetNamedItem("decryption").Value=$decryption
    $ctp8machineKey.Attributes.GetNamedItem("decryptionKey").Value=$decryptionKey
    $ctp8machineKey.Attributes.GetNamedItem("validation").Value=$validation
    $ctp8machineKey.Attributes.GetNamedItem("validationKey").Value=$validationKey

    # log
    Write-Log "Setting the machine decryption value to '$decryption'."
    Write-Log "Setting the machine decryption key value to '$decryptionKey'."
    Write-Log "Setting the machine validation value to '$validation'."
    Write-Log "Setting the machine validation key value to '$validationKey'."

    # save the ctp8 web.config with the updated values
    $ctp8xd.Save($ctp8webconfig)
}

function Get-ServiceBehavior-Thumbprint($xmldoc)
{
    # well-known service behavior names
    $behaviornames=@("AxILSessionServiceBehaviour","AxInteractiveILSessionServiceBehaviour","InteractionServiceBehavior","ODataQueryServiceBehavior")

    # try to get the service behavior thumbprint using one of the known behavior names
    foreach($name in $behaviornames)
    {
        $thumbprint=$xmldoc.SelectSingleNode("/configuration/location/system.serviceModel/behaviors/serviceBehaviors/behavior[@name='$name']/serviceCredentials/serviceCertificate/@findValue").value
        if(![system.string]::IsNullOrEmpty($thumbprint))
        {
            return $thumbprint
        }
    }

    return [string]::Empty
}

function Rename-File([string]$from,[string]$to)
{
    Move-Item -Path $from -Destination $to -Force|out-null
    Write-Log "Renamed file '$from' to '$to'."
}

function Validate
{
    Import-Module "$PSScriptRoot\CommonRollbackUtilities.psm1" -DisableNameChecking
    
    $aosWebsiteName = Get-AosWebSiteName
    if(!(Is-Website-Stopped -name:$aosWebsiteName))
    {
        Log-Error "Cannot perform the upgrade as the AOS website '$aosWebsiteName' is started. Stop the website and retry." -throw
    }

    if(!(Is-Service-Stopped -name:$BatchService))
    {
        Log-Error "Cannot perform the upgrade as the NT service '$BatchService' is running. Stop the service and retry." -throw
    }

    if(!(Is-Service-Stopped -name:$PrintService))
    {
        Log-Error "Cannot perform the upgrade as the NT service '$PrintService' is running. Stop the service and retry." -throw
    }
}

function Is-Website-Stopped([string]$name)
{
    Import-Module WebAdministration
    Write-Log "Checking the state of the web site '$name'."|Out-Null
    $website=Get-Website -Name:$name -ErrorAction SilentlyContinue
    if($website -eq $null)
    {
        return $true
    }

    if($website.State -eq "Started")
    {
        return $false
    }

    return $true
}

function Is-Service-Stopped([string]$name)
{
    Write-Log "Checking the status of the service '$name'."|out-null
    $service=Get-Service -Name:$name -ErrorAction SilentlyContinue
    if($service -eq $null)
    {
        return $true
    }

    if($service.Status -eq "Running")
    {
        return $false
    }

    return $true
}

function Decrypt-Config([string]$webroot)
{
    $command = Join-Path -Path "$webroot\bin" -ChildPath $configEncryptor
    if(!(Test-Path -Path $command))
    {
        Log-Error "Cannot find the Microsoft.Dynamics.AX.Framework.ConfigEncryptor.exe at '$webroot\bin\'." -throw
    }

    $webconfig=Join-Path -Path $webroot -ChildPath "Web.config"
    $commandParameter = " -decrypt `"$webconfig`""
    $logdir=[System.IO.Path]::GetDirectoryName($global:logfile)
    $stdOut=Join-Path -Path $logdir -ChildPath "config_decrypt.log"
    $stdErr= Join-Path -Path $logdir -ChildPath "config_decrypt.error.log"
    Start-Process $command $commandParameter -PassThru -Wait -RedirectStandardOutput $stdOut -RedirectStandardError $stdErr

    $decryptError = Get-Content $stdErr
    if ($decryptError -ne $null) {
        Log-Error $decryptError -throw
    }

    Write-Log "Finished decrypting the CTP7 web.config."
}

function Encrypt-Config([string]$webroot)
{
    $command = Join-Path -Path "$PSScriptRoot\EncryptionTool" -ChildPath $configEncryptor
    if(!(Test-Path -Path $command))
    {
        Log-Error "Cannot find the CTP8 Microsoft.Dynamics.AX.Framework.ConfigEncryptor.exe at '$PSScriptRoot\EncryptionTool\'." -throw
    }

    $webconfig=Join-Path -Path $webroot -ChildPath "Web.config"
    $commandParameter = " -encrypt `"$webconfig`""
    $logdir=[System.IO.Path]::GetDirectoryName($global:logfile)
    $stdOut=Join-Path -Path $logdir -ChildPath "config_encrypt.log"
    $stdErr= Join-Path -Path $logdir -ChildPath "config_encrypt.error.log"
    Start-Process $command $commandParameter -PassThru -Wait -RedirectStandardOutput $stdOut -RedirectStandardError $stdErr

    $encryptError = Get-Content $stdErr
    if ($encryptError -ne $null) {
        Log-Error $encryptError -throw
    }

    Write-Log "Finished encrypting the CTP8 web.config."
}

Export-ModuleMember -Function Initialize-Log,Write-Log,Write-Error,Validate,Create-Backup,Upgrade-Web-Config,Upgrade-Wif-Config,Upgrade-Wif-Services-Config -Variable $logfile

# SIG # Begin signature block
# MIIj+gYJKoZIhvcNAQcCoIIj6zCCI+cCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCAFtoHbPK5XPz6U
# yKSkeOH9OrU39SSz6puyJiuuoTo186CCDYIwggYAMIID6KADAgECAhMzAAAAww6b
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
# SEXAQsmbdlsKgEhr/Xmfwb1tbWrJUnMTDXpQzTGCFc4wghXKAgEBMIGVMH4xCzAJ
# BgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25k
# MR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xKDAmBgNVBAMTH01pY3Jv
# c29mdCBDb2RlIFNpZ25pbmcgUENBIDIwMTECEzMAAADDDpun2LLc9ywAAAAAAMMw
# DQYJYIZIAWUDBAIBBQCggcAwGQYJKoZIhvcNAQkDMQwGCisGAQQBgjcCAQQwHAYK
# KwYBBAGCNwIBCzEOMAwGCisGAQQBgjcCARUwLwYJKoZIhvcNAQkEMSIEIA01Ad+d
# m+rNhbCDvUolmvVIwRjHv+7lRSKMyvkM3lHzMFQGCisGAQQBgjcCAQwxRjBEoCaA
# JABVAHAAZwByAGEAZABlAEgAZQBsAHAAZQByAC4AcABzAG0AMaEagBhodHRwOi8v
# d3d3Lm1pY3Jvc29mdC5jb20wDQYJKoZIhvcNAQEBBQAEggEAQBeDjPJ5Kw0HEq1I
# qYZl6JO/3Y7G/bG86Tk2aqhQc8P4a34HukQgVAAXugE6ASxXwGnsOpP9Ryke4Amo
# nlGBdgQX2cknBezi+uZPiTYGYwPM2g0xwKbdWaMFS3kU98TTxuetrOZBT6ioThy+
# eYDoWRyhIsGlUgd90jojCR6B0gmda1LGJiG+Ney3Vv02Gy4yEPmj2fwbSPAgdceA
# pSq2WArHVoweO8xvtRPThvxyRR6a/eacjYJMbHpkdDNJW0na6JbPYN2Gcb43LFYL
# 2A3T7wSPp3gvI9kxs5cpZxnwRjghGy4awYg5EdiuuQt6x6ogYVOaAJP5fplzWZgR
# uz2Vu6GCE0YwghNCBgorBgEEAYI3AwMBMYITMjCCEy4GCSqGSIb3DQEHAqCCEx8w
# ghMbAgEDMQ8wDQYJYIZIAWUDBAIBBQAwggE8BgsqhkiG9w0BCRABBKCCASsEggEn
# MIIBIwIBAQYKKwYBBAGEWQoDATAxMA0GCWCGSAFlAwQCAQUABCAPVF1ptrF7A7TY
# pGPC/1zN9ii2cMpbb5gUHU1epxx1GwIGWrJ0ScalGBMyMDE4MDMyNTIxMDU1MC41
# NzJaMAcCAQGAAgH0oIG4pIG1MIGyMQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2Fz
# aGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENv
# cnBvcmF0aW9uMQwwCgYDVQQLEwNBT0MxJzAlBgNVBAsTHm5DaXBoZXIgRFNFIEVT
# TjpGNkZGLTJEQTctQkI3NTElMCMGA1UEAxMcTWljcm9zb2Z0IFRpbWUtU3RhbXAg
# U2VydmljZaCCDsowggZxMIIEWaADAgECAgphCYEqAAAAAAACMA0GCSqGSIb3DQEB
# CwUAMIGIMQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UE
# BxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMTIwMAYD
# VQQDEylNaWNyb3NvZnQgUm9vdCBDZXJ0aWZpY2F0ZSBBdXRob3JpdHkgMjAxMDAe
# Fw0xMDA3MDEyMTM2NTVaFw0yNTA3MDEyMTQ2NTVaMHwxCzAJBgNVBAYTAlVTMRMw
# EQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVN
# aWNyb3NvZnQgQ29ycG9yYXRpb24xJjAkBgNVBAMTHU1pY3Jvc29mdCBUaW1lLVN0
# YW1wIFBDQSAyMDEwMIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAqR0N
# vHcRijog7PwTl/X6f2mUa3RUENWlCgCChfvtfGhLLF/Fw+Vhwna3PmYrW/AVUycE
# MR9BGxqVHc4JE458YTBZsTBED/FgiIRUQwzXTbg4CLNC3ZOs1nMwVyaCo0UN0Or1
# R4HNvyRgMlhgRvJYR4YyhB50YWeRX4FUsc+TTJLBxKZd0WETbijGGvmGgLvfYfxG
# wScdJGcSchohiq9LZIlQYrFd/XcfPfBXday9ikJNQFHRD5wGPmd/9WbAA5ZEfu/Q
# S/1u5ZrKsajyeioKMfDaTgaRtogINeh4HLDpmc085y9Euqf03GS9pAHBIAmTeM38
# vMDJRF1eFpwBBU8iTQIDAQABo4IB5jCCAeIwEAYJKwYBBAGCNxUBBAMCAQAwHQYD
# VR0OBBYEFNVjOlyKMZDzQ3t8RhvFM2hahW1VMBkGCSsGAQQBgjcUAgQMHgoAUwB1
# AGIAQwBBMAsGA1UdDwQEAwIBhjAPBgNVHRMBAf8EBTADAQH/MB8GA1UdIwQYMBaA
# FNX2VsuP6KJcYmjRPZSQW9fOmhjEMFYGA1UdHwRPME0wS6BJoEeGRWh0dHA6Ly9j
# cmwubWljcm9zb2Z0LmNvbS9wa2kvY3JsL3Byb2R1Y3RzL01pY1Jvb0NlckF1dF8y
# MDEwLTA2LTIzLmNybDBaBggrBgEFBQcBAQROMEwwSgYIKwYBBQUHMAKGPmh0dHA6
# Ly93d3cubWljcm9zb2Z0LmNvbS9wa2kvY2VydHMvTWljUm9vQ2VyQXV0XzIwMTAt
# MDYtMjMuY3J0MIGgBgNVHSABAf8EgZUwgZIwgY8GCSsGAQQBgjcuAzCBgTA9Bggr
# BgEFBQcCARYxaHR0cDovL3d3dy5taWNyb3NvZnQuY29tL1BLSS9kb2NzL0NQUy9k
# ZWZhdWx0Lmh0bTBABggrBgEFBQcCAjA0HjIgHQBMAGUAZwBhAGwAXwBQAG8AbABp
# AGMAeQBfAFMAdABhAHQAZQBtAGUAbgB0AC4gHTANBgkqhkiG9w0BAQsFAAOCAgEA
# B+aIUQ3ixuCYP4FxAz2do6Ehb7Prpsz1Mb7PBeKp/vpXbRkws8LFZslq3/Xn8Hi9
# x6ieJeP5vO1rVFcIK1GCRBL7uVOMzPRgEop2zEBAQZvcXBf/XPleFzWYJFZLdO9C
# EMivv3/Gf/I3fVo/HPKZeUqRUgCvOA8X9S95gWXZqbVr5MfO9sp6AG9LMEQkIjzP
# 7QOllo9ZKby2/QThcJ8ySif9Va8v/rbljjO7Yl+a21dA6fHOmWaQjP9qYn/dxUoL
# kSbiOewZSnFjnXshbcOco6I8+n99lmqQeKZt0uGc+R38ONiU9MalCpaGpL2eGq4E
# QoO4tYCbIjggtSXlZOz39L9+Y1klD3ouOVd2onGqBooPiRa6YacRy5rYDkeagMXQ
# zafQ732D8OE7cQnfXXSYIghh2rBQHm+98eEA3+cxB6STOvdlR3jo+KhIq/fecn5h
# a293qYHLpwmsObvsxsvYgrRyzR30uIUBHoD7G4kqVDmyW9rIDVWZeodzOwjmmC3q
# jeAzLhIp9cAvVCch98isTtoouLGp25ayp0Kiyc8ZQU3ghvkqmqMRZjDTu3QyS99j
# e/WZii8bxyGvWbWu3EQ8l1Bx16HSxVXjad5XwdHeMMD9zOZN+w2/XU/pnR4ZOC+8
# z1gFLu8NoFA12u8JJxzVs341Hgi62jbb01+P3nSISRIwggTZMIIDwaADAgECAhMz
# AAAApUgXcif5cL5jAAAAAAClMA0GCSqGSIb3DQEBCwUAMHwxCzAJBgNVBAYTAlVT
# MRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQK
# ExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xJjAkBgNVBAMTHU1pY3Jvc29mdCBUaW1l
# LVN0YW1wIFBDQSAyMDEwMB4XDTE2MDkwNzE3NTY1MFoXDTE4MDkwNzE3NTY1MFow
# gbIxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdS
# ZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xDDAKBgNVBAsT
# A0FPQzEnMCUGA1UECxMebkNpcGhlciBEU0UgRVNOOkY2RkYtMkRBNy1CQjc1MSUw
# IwYDVQQDExxNaWNyb3NvZnQgVGltZS1TdGFtcCBTZXJ2aWNlMIIBIjANBgkqhkiG
# 9w0BAQEFAAOCAQ8AMIIBCgKCAQEAtNqS1L1MXvDbVwffWWGBOia20xizacP9+8wj
# b9INzNMbVhbMUE2+wxL7XNbBNLPCOcm0+yH6MtdhbAoKXm5PvgqXL9GtAuTh0O9p
# gZ8fMsZNhCb94nuo0iIsPPHMKzkyL/4b7J5Pb/2Lx1TzhZ1+gktSEo7uD2M9tjdE
# +k5bu1/dj/7mhdcDUhGewZT/NfuHMvYTIJGnmjeh8k+kMlRL4CgU5echhu3Ww5qZ
# NCEmMHUHmKBl6FO30JlalBJmu9tWVjTURJFhidC41F86TuWAOsfyUps6ddfcdqgg
# UyDHGbcUVXV8+8oCIg6hS4HzsOZZxRqlC4HKFwI+asULjr/BtwIDAQABo4IBGzCC
# ARcwHQYDVR0OBBYEFOITq0vy7bFguHjxhaBR/nLnsS+kMB8GA1UdIwQYMBaAFNVj
# OlyKMZDzQ3t8RhvFM2hahW1VMFYGA1UdHwRPME0wS6BJoEeGRWh0dHA6Ly9jcmwu
# bWljcm9zb2Z0LmNvbS9wa2kvY3JsL3Byb2R1Y3RzL01pY1RpbVN0YVBDQV8yMDEw
# LTA3LTAxLmNybDBaBggrBgEFBQcBAQROMEwwSgYIKwYBBQUHMAKGPmh0dHA6Ly93
# d3cubWljcm9zb2Z0LmNvbS9wa2kvY2VydHMvTWljVGltU3RhUENBXzIwMTAtMDct
# MDEuY3J0MAwGA1UdEwEB/wQCMAAwEwYDVR0lBAwwCgYIKwYBBQUHAwgwDQYJKoZI
# hvcNAQELBQADggEBADZ9bXkrxi4vJCDKJfU0FYzc8ktHB/SjPu6GeAjee4fWBsVY
# 6fvL8xdOH+kxoMbQwmYDn67N8OycK1mTglO6kREcCp7HYhpao9UWyy2m6sDytP95
# fvsO8DPqThuuXNr0UC7oS6hnGQarx9/BfWEFIjBhzqWYwMACKH1pMSmZIG6kNufi
# lNKEbNwNGknJ9eM2VW1t99VbEdQ5ugDfptEky0kxvCWAgmCk6xnmIYJpL0iSslDF
# Dw6dN98evP64cuuTQ/5bxh8bXqBoXd4OFOQi1GoVVuTo4uetj8onOGJm1mzbJhIv
# CYPFrnBB4jkehC0Lse+JcCZSBDLpPAwDnmxs+G6hggN0MIICXAIBATCB4qGBuKSB
# tTCBsjELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcT
# B1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEMMAoGA1UE
# CxMDQU9DMScwJQYDVQQLEx5uQ2lwaGVyIERTRSBFU046RjZGRi0yREE3LUJCNzUx
# JTAjBgNVBAMTHE1pY3Jvc29mdCBUaW1lLVN0YW1wIFNlcnZpY2WiJQoBATAJBgUr
# DgMCGgUAAxUAm8I13fuyJisaFDFlUC8dU5Rpgm+ggcEwgb6kgbswgbgxCzAJBgNV
# BAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4w
# HAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xDDAKBgNVBAsTA0FPQzEnMCUG
# A1UECxMebkNpcGhlciBOVFMgRVNOOjI2NjUtNEMzRi1DNURFMSswKQYDVQQDEyJN
# aWNyb3NvZnQgVGltZSBTb3VyY2UgTWFzdGVyIENsb2NrMA0GCSqGSIb3DQEBBQUA
# AgUA3mHrFzAiGA8yMDE4MDMyNTA5MzIwN1oYDzIwMTgwMzI2MDkzMjA3WjB0MDoG
# CisGAQQBhFkKBAExLDAqMAoCBQDeYesXAgEAMAcCAQACAi3BMAcCAQACAhiIMAoC
# BQDeYzyXAgEAMDYGCisGAQQBhFkKBAIxKDAmMAwGCisGAQQBhFkKAwGgCjAIAgEA
# AgMW42ChCjAIAgEAAgMHoSAwDQYJKoZIhvcNAQEFBQADggEBAGHJNpQt7eSWkt2n
# +PrM04UbNfGyWGmK9+usHpWnw7gBwhCbkXMfbQPVQ3cV1ZCTRhL2auKQCmIsdbsC
# Pe0EF+rSeXtJKmi7fu+7hMBbn0I/5MQVVcDdeKKMI8mQL/iwdwosm2WV/vCFar/a
# KYjGi2dGkk/27hFqYgK/DQVM7BesSoqBA9Qs0RPuocNc9WgzZnKX/uDoMMbDbSpm
# 4MbJ0kb95a32LIcM/acGm12qpir/fLHHKvM/cp2mQD1QzTxXM+ZsHQo13OtJ5iYv
# HJwEhsZG0tuc7Ev6cP25xaf8BHwSRfyhF+C2G8/rwefQCkRS+IojtQJaNlOk3clA
# AtGgFYUxggL1MIIC8QIBATCBkzB8MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2Fz
# aGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENv
# cnBvcmF0aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0EgMjAx
# MAITMwAAAKVIF3In+XC+YwAAAAAApTANBglghkgBZQMEAgEFAKCCATIwGgYJKoZI
# hvcNAQkDMQ0GCyqGSIb3DQEJEAEEMC8GCSqGSIb3DQEJBDEiBCAi8mo3ldaGcGsw
# olU9soTe93TUhuS7SU8LjL6dMohWFTCB4gYLKoZIhvcNAQkQAgwxgdIwgc8wgcww
# gbEEFJvCNd37siYrGhQxZVAvHVOUaYJvMIGYMIGApH4wfDELMAkGA1UEBhMCVVMx
# EzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoT
# FU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRpbWUt
# U3RhbXAgUENBIDIwMTACEzMAAAClSBdyJ/lwvmMAAAAAAKUwFgQUU7ms+vafvsiJ
# Z1hlXaWSkCM9RdswDQYJKoZIhvcNAQELBQAEggEAcCo00iGuxuEmxmgt0jHK2du9
# jOmMnhtGvztX17Cob2O49tLYv1imhxtsBclMpgHjpxqvQmmj8VlVo1RqeJKjwGBg
# +tV1/pH2WIo4uVUc8FeDuBvUWTk4YNsVrWNTLmZ4V5kHfVjmE56HLHratY0SU+K0
# mSrtC+vTqmbAoe4whmTr4amXA9ZDP4BNIaf84Hefy0U6TKlWIKMxoGB7Zz4XtyM2
# xlVMc6shzmunV63skUYhJH2LC6mAi83e708ELsryRi7zmNrsX9FD3/o53c6YhLQg
# daKBmX6nBqb3f12lcj3iyI8ts/4NOlhAJck5lRiMSVSvFroXoq9MxO+2qaQRYQ==
# SIG # End signature block
