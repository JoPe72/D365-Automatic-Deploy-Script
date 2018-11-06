<#
.SYNOPSIS
    
Provides operations and functions for the retrieval of KeyVault Keys and Passwords as
well as some other utilities for manipulating the data that is returned.

.DESCRIPTION

Provides a common module for Unified Operations Setup to retrieve and manipulate Azure Secret/Keys.

.PARAMETER VaultName

The Name of the KeyVault you want to retrieve the key from. Azure specifies that a 
KeyVault name must match this regex "^[a-zA-Z0-9-]{3,24}$".

.PARAMETER ApplicationID

The ApplicationID of the ServicePrincipal we are going to use to authenticate with.

.PARAMETER TenantID

The TenantID guid that Application is under.

.PARAMETER CertificateThumprint

The Thumprint of the certificate that is associated with the Application.

.EXAMPLE

C:\PS> Import-Module ".\KeyVault.psm1" -ArgumentList ("<KeyVaultName>", "<ApplicationID>", "<TenantID>", "<Thumbprint>")

#>
[CmdletBinding()]
param
(
    [Parameter(Mandatory=$False, Position = 0)]
    [System.String]
    $VaultName,

    [Parameter(Mandatory=$False, Position = 1)]
    [System.String]
    $ApplicationID,

    [Parameter(Mandatory=$False, Position = 2)]
    [System.String]
    $CertificateThumprint
)

Import-Module "$PSScriptRoot\AosCommon.psm1" -Force -DisableNameChecking

if (![System.String]::IsNullOrWhiteSpace($VaultName))
{
    $Script:VaultName = $VaultName
}
else
{
    $Script:VaultName = "default"
}

if (![System.String]::IsNullOrWhiteSpace($ApplicationID) -and 
    ![System.String]::IsNullOrWhiteSpace($CertificateThumprint))
{
    $Script:ApplicationID = $ApplicationID
    $Script:CertificateThumprint = $CertificateThumprint 
    Import-Module "$PSScriptRoot\DynamicsVault.psm1" -Force -DisableNameChecking
}

function Get-KeyVaultKey
{
    <#
    .SYNOPSIS
    
    Retrieves a specified Key from a KeyVault.

    .DESCRIPTION

    Retrieves a specified Key from KeyVault using the Azure PowerShell Modules and wraps
    the function up to provide an easier call. 

    .PARAMETER Name

    The Name of the Key in the selected vault we want to retrieve.

    .PARAMETER Version

    The Version of the Key we want, this is an optional field. The default Version
    is the latest one in KeyVault.

    .PARAMETER VaultName

    The Name of the KeyVault you want to retrieve the key from. This parameter is optional,
    it will default to the $Script:VaultName parameter. Azure specifies that a KeyVault name
    must match this regex "^[a-zA-Z0-9-]{3,24}$".

    .EXAMPLE

    Retrieves the latest version of the Key.
    
    C:\PS> Get-KeyVaultKey "KeyName"

    .EXAMPLE
    
    Retrieves the specific version of the Key.

    C:\PS> Get-KeyVaultKey "KeyName" "KeyVersion"

    .EXAMPLE

    Retrieves the latest version of the Key from a different KeyVault than what was passed
    from the script parameters.

    C:\PS> Get-KeyVaultKey -Name "KeyName" -VaultName "VaultName"
    #>
    param
    (
        [Parameter(Mandatory=$True, Position = 0)]
        [ValidateLength(1,127)]
        [System.String]
        $Name,

        [Parameter(ParameterSetName = "Version", Mandatory=$False, Position = 1)]
        [System.String]
        $Version,

        [Parameter(Mandatory=$False, Position = 2)]
        [ValidatePattern("^[a-zA-Z0-9-]{3,24}$")]
        [System.String]
        $VaultName = $Script:VaultName
    )


    switch ($PsCmdlet.ParameterSetName)
    {
        "Version" 
        { 
            $keyInformation = Get-AzureKeyVaultKey -VaultName $VaultName -Name $Name -Version $Version
        }
        default
        {
            $keyInformation = Get-AzureKeyVaultKey -VaultName $VaultName -Name $Name
        }
    }
    return $keyInformation
}

function Get-KeyVaultSecret
{
    <#
    .SYNOPSIS
    
    Retrieves a specified secret from a KeyVault.

    .DESCRIPTION

    Retrieves a specified secret from KeyVault using the Azure PowerShell Modules and wraps
    the function up to provide an easier call. 

    .PARAMETER VaultUri

    The Name of the secret in the selected vault we want to retrieve. The assumption is the
    URI is formatted as such "Vault://SecretName/SecretVersion", if it does not match this
    pattern we assume the secret is the VaultUri parameter.

    .PARAMETER VaultName

    The Name of the KeyVault you want to retrieve the secret from. This parameter is optional,
    it will default to the $Script:VaultName parameter. Azure specifies that a KeyVault name
    must match this regex "^[a-zA-Z0-9-]{3,24}$".

    .EXAMPLE

    Retrieves the latest version of the secret.
    
    C:\PS> Get-KeyVaultSecret "VaultUri"

    .EXAMPLE

    Retrieves the latest version of the secret from a different KeyVault than what was passed
    from the script parameters.

    C:\PS> Get-KeyVaultSecret -VaultUri "Vault://SecretName/SecretVersion" -VaultName "VaultName"
    #>
    param
    (
        [Parameter(Mandatory=$True, Position = 0)]
        [System.String]
        $VaultUri,

        [Parameter(Mandatory=$False, Position = 1)]
        [ValidatePattern("^[a-zA-Z0-9-]{3,24}$")]
        [System.String]
        $VaultName = $Script:VaultName
    )

    if (!(Test-ValidKeyVaultUri -VaultUri $VaultUri))
    {
        return $VaultUri
    }
    else
    {
        [System.Uri]$Uri = [System.Uri]::new($VaultUri)

        $secretName = $Uri.Host

        if ($Uri.Segments.Count -ge 2)
        {
            $secret = Get-VaultCredential -ClientId $Script:ApplicationID -CertificateThumbprint $Script:CertificateThumprint -VaultName $VaultName -SecretName $secretName -Version $Uri.Segments[1]
        }
        else
        {
            $secret = Get-VaultCredential -ClientId $Script:ApplicationID -CertificateThumbprint $Script:CertificateThumprint -VaultName $VaultName -SecretName $secretName
        }

        return $secret
    }
}

function Get-CertificatefromBase64String
{
    <#
    .SYNOPSIS

    Takes in a Base64 String representation of a Private Certificate (PFX) and the
    password associated with it and loads the certificate into a X509Certificate2 object.

    .DESCRIPTION

    Upon receiving the certificate information from KeyVault this allows us to convert
    the Base64 string and the password and load a certificate into a X509Certificate2 object.

    .PARAMETER Base64String

    The Base64 string representation of the PFX file.

    .PARAMETER CertificatePassword

    The password of the PFX Certificate.

    .EXAMPLE

    C:\PS> Create-CertificatefromBase64String "<Base64String>" "<Password>"

    #>
    param
    (
        [Parameter(Mandatory=$True, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [System.String]
        $Base64String,

        [Parameter(Mandatory=$False, Position = 1)]
        [System.Security.SecureString]
        $CertificatePassword
    )

    $certificateBytes = [System.Convert]::FromBase64String($Base64String)

    if ($CertificatePassword -ne $null)
    { 
        return [System.Security.Cryptography.X509Certificates.X509Certificate2]::new($CertificateBytes, $CertificatePassword)       
    }
    else
    {
        return [System.Security.Cryptography.X509Certificates.X509Certificate2]::new($CertificateBytes)
    }
}

function Get-CertificateFromJsonString
{
    <#
    .SYNOPSIS

    Takes in a JSON String representation of a Certificate and attributes 
    and loads the certificate in memory.

    .DESCRIPTION

    This functions makes the assumption that the JSON file is formatted like this.

    {
        "data": "<Base64String>",
        "dataType" :"pfx",
        "password": "<CertificatePassword>"
    }

    This is following the same format that the ARM Templates expect Certificates for 
    VM Deployments.

    .PARAMETER JsonString

    The Json String string representation of the Certificate file and its attributes.

    .PARAMETER CertificateType

    This is a reference object so that the caller of the function can determine the
    type of the certificate for example (Public or Private key).

    .EXAMPLE

    C:\PS> [System.String]$certificateType = [System.String]::Empty
    C:\PS> $jsonObject = @"
    C:\PS> {
    C:\PS> "data": "<Base64EncodedCert>",
    C:\PS> "dataType" :"pfx",
    C:\PS> "password": "<CertificatePassword>"
    C:\PS> }
    C:\PS> Get-CertificateFromJsonString $jsonObject ([ref]$certificateType)

    #>
    param
    (
        [Parameter(Mandatory=$True, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [System.String]
        $JsonString,

        [Parameter(Mandatory=$True, Position = 1)]
        [Ref]
        $CertificateType
    )

    $jsonObject = $JsonString | ConvertFrom-Json

    $CertificateType.Value = $jsonObject.dataType
    [System.Security.SecureString]$certificatePassword = $null

    if (![System.String]::IsNullOrWhiteSpace($jsonObject.password))
    {
        $certificatePassword = ConvertTo-SecureString $jsonObject.password -AsPlainText -Force
    }

    $certificate = Get-CertificatefromBase64String -Base64String $jsonObject.data -CertificatePassword $certificatePassword

    return $certificate
}

function Get-CertificateFromVault
{
    <#
    .SYNOPSIS

    Takes in two Vault Uri's. One is for the Certificate file (base64 encoded) and the
    second the password for the Certificate (Optional).

    .DESCRIPTION

    Once the information for the certificate has been retrieved we take the information and 
    create a x509Certificate2 object to be consumed.

    .PARAMETER CertUri

    The Uri of the certificate file we want.

    .PARAMETER CertPasswordUri

    The Uri of the certificate password that corresponds to the Certificate

    .PARAMETER VaultName

    The name of the Vault to retrieve the secret information.

    .EXAMPLE

    # Uses default VaultName
    C:\PS> Get-CertificateFromVault "vault://certSecretName" "vault://certSecretPasswordName"

    # overrides default VaultName
    C:\PS> Get-CertificateFromVault "vault://certSecretName" "vault://certSecretPasswordName" "VaultName"

    #>
    param
    (
        [Parameter(Mandatory=$True, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [System.String]
        $CertUri,

        [Parameter(Mandatory=$false, Position = 1)]
        [System.String]
        $CertPasswordUri,

        [Parameter(Mandatory=$False, Position = 2)]
        [System.String]
        $VaultName = $Script:VaultName
    )

    $base64Cert = Get-KeyVaultSecret -VaultUri $CertUri -VaultName $VaultName

    if (![System.String]::IsNullOrWhiteSpace($CertPasswordUri))
    {
        $certificatePassword = ConvertTo-SecureString -String $(Get-KeyVaultSecret -VaultUri $CertPasswordUri -VaultName $VaultName) -AsPlainText -Force
    }

    return Get-CertificatefromBase64String -Base64String $base64Cert -CertificatePassword $certificatePassword
}

function Get-Base64UTF8String
{
    <#
    .SYNOPSIS

    Takes in a UTF8 Encoded Base64 String and converts it to native string.

    .DESCRIPTION

    This is a helper function to unwrap the Private Key that is stored for the
    ARM Template deployment.

    Azure requires this JSON Structure to be wrapped like this 

    $JsonBlob = @{
        "data": "<Base64String>",
        "dataType" :"pfx",
        "password": "<CertificatePassword>"
    }@

    $ContentBytes = [System.Text.Encoding]::UTF8.GetBytes($JSONBlob)
    $Content = [System.Convert]::ToBase64String($ContentBytes)

    This will unwrap the JSON File.

    .PARAMETER Base64String

    The UTF8 Base64String Object to unwrap.

    .EXAMPLE

    C:\PS> Read-Base64UTF8String <UTF8 Encoded Base64String>

    #>
    param
    (
        [Parameter(Mandatory=$True, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [System.String]
        $Base64String
    )

    $ReceivedBytes = [System.Convert]::FromBase64String($Base64String)

    return [System.Text.Encoding]::UTF8.GetString($ReceivedBytes)
}

function Create-FilefromBase64String
{
    <#
    .SYNOPSIS
    
    Takes in a Base64 String representation of a File and
    Creates a file to the specified path.
    
    .DESCRIPTION

    Takes in a Base64 String representation of a File and
    Creates a file to the specified path.

    .PARAMETER Base64String

    The Base64 string representation of the PFX file. 

    .PARAMETER DestinationPath

    The Path of the file we want to save too. This includes the path and 
    file name i.e. (C:\Temp\Cert.pfx)

    .EXAMPLE

    C:\PS> Create-FilefromBase64String "<Base64String>" "C:\Temp\Cert.pfx"

    #>
    param
    (
        [Parameter(Mandatory=$True, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [System.String]
        $Base64String,

        [Parameter(Mandatory=$True, Position = 1)]
        [ValidateNotNullOrEmpty()]
        [System.String]
        $DestinationPath
    )
    
    $pfxBytes = [System.Convert]::FromBase64String($Base64String)
    
    [System.IO.File]::WriteAllBytes($DestinationPath, $pfxBytes)
}

function Test-ValidKeyVaultUri
{
    param
    (
        [Parameter(Mandatory=$True, Position = 0)]
        [System.String]
        $VaultUri
    )

    if (![System.Uri]::IsWellFormedUriString($VaultUri, [System.UriKind]::Absolute))
    {
        return $false
    }

    [System.Uri]$Uri = [System.Uri]::new($VaultUri)

    if ($Uri.Scheme -ne "vault")
    {
        return $false
    }

    return $true
}
# SIG # Begin signature block
# MIIj8AYJKoZIhvcNAQcCoIIj4TCCI90CAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCCYIEPfj2Yy48kJ
# gWEKNntz2Qhws7AgUPUErSkZHt+v0qCCDYIwggYAMIID6KADAgECAhMzAAAAww6b
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
# SEXAQsmbdlsKgEhr/Xmfwb1tbWrJUnMTDXpQzTGCFcQwghXAAgEBMIGVMH4xCzAJ
# BgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25k
# MR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xKDAmBgNVBAMTH01pY3Jv
# c29mdCBDb2RlIFNpZ25pbmcgUENBIDIwMTECEzMAAADDDpun2LLc9ywAAAAAAMMw
# DQYJYIZIAWUDBAIBBQCggbYwGQYJKoZIhvcNAQkDMQwGCisGAQQBgjcCAQQwHAYK
# KwYBBAGCNwIBCzEOMAwGCisGAQQBgjcCARUwLwYJKoZIhvcNAQkEMSIEILxvlgb5
# ANeIjvZsgvMjlnNEfIzVfFWaawyJ/VKEMb0gMEoGCisGAQQBgjcCAQwxPDA6oByA
# GgBLAGUAeQBWAGEAdQBsAHQALgBwAHMAbQAxoRqAGGh0dHA6Ly93d3cubWljcm9z
# b2Z0LmNvbTANBgkqhkiG9w0BAQEFAASCAQCgaTA5/3+vp0acAJKmR8VnAK1YOzdd
# LJMymSKOd/ORHqji+DJje4DmvFD03ZrxC5hni0V2lApV4tT3rRkU0C/kEGvy2aJ/
# lJYrNS+fqR4k2FV2fdc3BN9n2F9aVc9UwtjjiGjRM7qc2LByeUm/qtXlmHcLwS7v
# 6U5qF9kqqlCnIfaglzSxnEugGcn8iaflkVsRyq9F0O9mPtpODEylHRZTUFo6asYs
# jo4FvoxmuWiU6NmarmteLhn9WzAB8n+kBI7MLAAy2vdARIZBYkZRvumo+rvdXfwN
# SbCyUz3Ll7lPJsiESkOvXlt7J0kt95oXpN7VgkuAxGMnWRBfKVOyBSraoYITRjCC
# E0IGCisGAQQBgjcDAwExghMyMIITLgYJKoZIhvcNAQcCoIITHzCCExsCAQMxDzAN
# BglghkgBZQMEAgEFADCCATwGCyqGSIb3DQEJEAEEoIIBKwSCAScwggEjAgEBBgor
# BgEEAYRZCgMBMDEwDQYJYIZIAWUDBAIBBQAEIF3BUMsins4SDBgSOe8GnFrL+GJk
# xRSWwQKtMeamXwLoAgZasrnL+WAYEzIwMTgwMzI1MjEwNTU3LjY4MlowBwIBAYAC
# AfSggbikgbUwgbIxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAw
# DgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24x
# DDAKBgNVBAsTA0FPQzEnMCUGA1UECxMebkNpcGhlciBEU0UgRVNOOkQyMzYtMzdE
# QS05NzYxMSUwIwYDVQQDExxNaWNyb3NvZnQgVGltZS1TdGFtcCBTZXJ2aWNloIIO
# yjCCBnEwggRZoAMCAQICCmEJgSoAAAAAAAIwDQYJKoZIhvcNAQELBQAwgYgxCzAJ
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
# 7wknHNWzfjUeCLraNtvTX4/edIhJEjCCBNkwggPBoAMCAQICEzMAAACuDtZOlonb
# APUAAAAAAK4wDQYJKoZIhvcNAQELBQAwfDELMAkGA1UEBhMCVVMxEzARBgNVBAgT
# Cldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29m
# dCBDb3Jwb3JhdGlvbjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRpbWUtU3RhbXAgUENB
# IDIwMTAwHhcNMTYwOTA3MTc1NjU1WhcNMTgwOTA3MTc1NjU1WjCBsjELMAkGA1UE
# BhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAc
# BgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEMMAoGA1UECxMDQU9DMScwJQYD
# VQQLEx5uQ2lwaGVyIERTRSBFU046RDIzNi0zN0RBLTk3NjExJTAjBgNVBAMTHE1p
# Y3Jvc29mdCBUaW1lLVN0YW1wIFNlcnZpY2UwggEiMA0GCSqGSIb3DQEBAQUAA4IB
# DwAwggEKAoIBAQDeki/DpJVy9T4NZmTD+uboIg90jE3Bnse2VLjxj059H/tGML58
# y3ue28RnWJIv+lSABp+jPp8XIf2p//DKYb0o/QSOJ8kGUoFYesNTPtqyf/qohLW1
# rcLijiFoMLABH/GDnDbgRZHxVFxHUG+KNwffdC0BYC3Vfq3+2uOO8czRlj10gRHU
# 2BK8moSz53Vo2ZwF3TMZyVgvAvlg5sarNgRwAYwbwWW5wEqpeODFX1VA/nAeLkji
# rCmg875M1XiEyPtrXDAFLng5/y5MlAcUMYJ6dHuSBDqLLXipjjYakQopB3H1+9s8
# iyDoBM07JqP9u55VP5a2n/IZFNNwJHeCTSvLAgMBAAGjggEbMIIBFzAdBgNVHQ4E
# FgQUfo/lNDREi/J5QLjGoNGcQx4hJbEwHwYDVR0jBBgwFoAU1WM6XIoxkPNDe3xG
# G8UzaFqFbVUwVgYDVR0fBE8wTTBLoEmgR4ZFaHR0cDovL2NybC5taWNyb3NvZnQu
# Y29tL3BraS9jcmwvcHJvZHVjdHMvTWljVGltU3RhUENBXzIwMTAtMDctMDEuY3Js
# MFoGCCsGAQUFBwEBBE4wTDBKBggrBgEFBQcwAoY+aHR0cDovL3d3dy5taWNyb3Nv
# ZnQuY29tL3BraS9jZXJ0cy9NaWNUaW1TdGFQQ0FfMjAxMC0wNy0wMS5jcnQwDAYD
# VR0TAQH/BAIwADATBgNVHSUEDDAKBggrBgEFBQcDCDANBgkqhkiG9w0BAQsFAAOC
# AQEAPVlNePD0XDQI0bVBYANTDPmMpk3lIh6gPIilg0hKQpZNMADLbmj+kav0GZcx
# tWnwrBoR+fpBsuaowWgwxExCHBo6mix7RLeJvNyNYlCk2JQT/Ga80SRVzOAL5Nxl
# s1PqvDbgFghDcRTmpZMvADfqwdu5R6FNyIgecYNoyb7A4AqCLfV1Wx3PrPyaXbat
# skk5mT8NqWLYLshBzt2Ca0bhJJZf6qQwg6r2gz1pG15ue6nDq/mjYpTmCDhYz46b
# 8rxrIn0sQxnFTmtntvz2Z1jCGs99n1rr2ZFrGXOJS4Bhn1tyKEFwGJjrfQ4Gb2py
# A9aKRwUyK9BHLKWC5ZLD0hAaIKGCA3QwggJcAgEBMIHioYG4pIG1MIGyMQswCQYD
# VQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEe
# MBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMQwwCgYDVQQLEwNBT0MxJzAl
# BgNVBAsTHm5DaXBoZXIgRFNFIEVTTjpEMjM2LTM3REEtOTc2MTElMCMGA1UEAxMc
# TWljcm9zb2Z0IFRpbWUtU3RhbXAgU2VydmljZaIlCgEBMAkGBSsOAwIaBQADFQDH
# wb0we6UYnmReZ3Q2+rvjmbxo+6CBwTCBvqSBuzCBuDELMAkGA1UEBhMCVVMxEzAR
# BgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1p
# Y3Jvc29mdCBDb3Jwb3JhdGlvbjEMMAoGA1UECxMDQU9DMScwJQYDVQQLEx5uQ2lw
# aGVyIE5UUyBFU046MjY2NS00QzNGLUM1REUxKzApBgNVBAMTIk1pY3Jvc29mdCBU
# aW1lIFNvdXJjZSBNYXN0ZXIgQ2xvY2swDQYJKoZIhvcNAQEFBQACBQDeYeyfMCIY
# DzIwMTgwMzI1MDkzODM5WhgPMjAxODAzMjYwOTM4MzlaMHQwOgYKKwYBBAGEWQoE
# ATEsMCowCgIFAN5h7J8CAQAwBwIBAAICF1UwBwIBAAICGbIwCgIFAN5jPh8CAQAw
# NgYKKwYBBAGEWQoEAjEoMCYwDAYKKwYBBAGEWQoDAaAKMAgCAQACAxbjYKEKMAgC
# AQACAx6EgDANBgkqhkiG9w0BAQUFAAOCAQEAWyQUURBz54HD3IeRza8cqve9H2Ss
# JmJKlAip9ChWJbfekZCsNpeSZcNO0K2NozUQQFbdoI0Y8A5bmlBXPN/zFNCTDZr9
# HEUHv0qg/gNvEptv0L4U/8edkKyYSsqLEkv5GYpdoF+CWb8QhyLJnu0GWxGkFJ72
# 0vtQlmUyILvK1UGK+7oH4xDkRfcpT0XwuqDlHTvr/uCslTZ6ZztrkmcG9a5ozHt7
# /NhxxRGBx7SJdZLqo2I07QAor9yQgZ4vQG9tN8JuKbHUorCQCcEwmhgMNycYsvW+
# yiUNWvuMv0JpaqosdwefRNcYBXb6YKd92pqeogYBOEQ9jjjRLreioDqQTzGCAvUw
# ggLxAgEBMIGTMHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAw
# DgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24x
# JjAkBgNVBAMTHU1pY3Jvc29mdCBUaW1lLVN0YW1wIFBDQSAyMDEwAhMzAAAArg7W
# TpaJ2wD1AAAAAACuMA0GCWCGSAFlAwQCAQUAoIIBMjAaBgkqhkiG9w0BCQMxDQYL
# KoZIhvcNAQkQAQQwLwYJKoZIhvcNAQkEMSIEIGJkZhNPgrM3DHuP4eq8JvrWb2Tu
# k+P726jirR4V/I90MIHiBgsqhkiG9w0BCRACDDGB0jCBzzCBzDCBsQQUx8G9MHul
# GJ5kXmd0Nvq745m8aPswgZgwgYCkfjB8MQswCQYDVQQGEwJVUzETMBEGA1UECBMK
# V2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0
# IENvcnBvcmF0aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0Eg
# MjAxMAITMwAAAK4O1k6WidsA9QAAAAAArjAWBBRFEh/VJObyL9rcIqyx5yjtoUQh
# bzANBgkqhkiG9w0BAQsFAASCAQAOgtPf8V8g3Im1+5v8AI2zLEArtRoHDNCfQ9uI
# 6yZIGv7ieVZmGCQ8EjoHZf0XCBtBldwwlB10VSeWF/FUlqh6AHBJ/0xrbSu1cf4k
# ck6C6EGAia7lINq3U9uPfo5kzye+x5kWjB9OtkgQm3P8WdihBd5CFLoyfeNkoq/D
# SdRF/RLEUxhty6aokMUvVPRjFKXVeYcC4m4mtNdo7Fa1ToQlafoibpzIRdubwePQ
# RnaYd9oR2Li5py/0cY48HZtSegY/EA4RGfgD9g8+PlQk8OoYywbf+EhkaEfwy4WG
# J312VRBxHdzTI0kAbAQTxP1fqUbpUrqhw43oZHmSTwYSg7Dv
# SIG # End signature block
