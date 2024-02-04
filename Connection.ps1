function Connect-Tenant {
    <#
   .Description
   This function uses the various PowerShell modules to establish
   a connection to an M365 Tenant associated with provided
   credentials
   .Functionality
   Internal
   #>
   [CmdletBinding(DefaultParameterSetName='Manual')]
   param (
   [Parameter(ParameterSetName = 'Auto')]
   [Parameter(ParameterSetName = 'Manual')]
   [Parameter(Mandatory = $true)]
   [ValidateNotNullOrEmpty()]
   [ValidateSet("teams", "exo", "defender", "aad", "powerplatform", "sharepoint", IgnoreCase = $false)]
   [string[]]
   $ProductNames,

   [Parameter(ParameterSetName = 'Auto')]
   [Parameter(ParameterSetName = 'Manual')]
   [Parameter(Mandatory = $true)]
   [ValidateNotNullOrEmpty()]
   [ValidateSet("commercial", "gcc", "gcchigh", "dod", IgnoreCase = $false)]
   [string]
   $M365Environment,

   [Parameter(ParameterSetName = 'Auto')]
   [Parameter(Mandatory = $false)]
   [AllowNull()]
   [hashtable]
   $ServicePrincipalParams
   )
   Import-Module (Join-Path -Path $PSScriptRoot -ChildPath "ConnectHelpers.psm1")

   # Prevent duplicate sign ins
   $EXOAuthRequired = $true
   $SPOAuthRequired = $true
   $AADAuthRequired = $true

   $ProdAuthFailed = @()

   $N = 0
   $Len = $ProductNames.Length

   foreach ($Product in $ProductNames) {
       $N += 1
       $Percent = $N*100/$Len
       $ProgressParams = @{
           'Activity' = "Authenticating to each Product";
           'Status' = "Authenticating to $($Product); $($N) of $($Len) Products authenticated to.";
           'PercentComplete' = $Percent;
       }
       Write-Progress @ProgressParams
       try {
           switch ($Product) {
               "aad" {
                   $GraphScopes = (
                       'User.Read.All',
                       'Policy.Read.All',
                       'Organization.Read.All',
                       'RoleManagement.Read.Directory',
                       'GroupMember.Read.All',
                       'Directory.Read.All'
                   )
                   $GraphParams = @{
                       'ErrorAction' = 'Stop';
                   }
                   if ($ServicePrincipalParams.CertThumbprintParams) {
                       $GraphParams += @{
                           CertificateThumbprint = $ServicePrincipalParams.CertThumbprintParams.CertificateThumbprint;
                           ClientID = $ServicePrincipalParams.CertThumbprintParams.AppID;
                           TenantId  = $ServicePrincipalParams.CertThumbprintParams.Organization; # Organization also works here
                       }
                   }
                   else {
                       $GraphParams += @{Scopes = $GraphScopes;}
                   }
                   switch ($M365Environment) {
                       "gcchigh" {
                           $GraphParams += @{'Environment' = "USGov";}
                       }
                       "dod" {
                           $GraphParams += @{'Environment' = "USGovDoD";}
                       }
                   }
                   Write-Host "Connecting"
                   #Connect-MgGraph @GraphParams 
                   Connect-MgGraph -Identity
                   $AADAuthRequired = $false
               }
               {($_ -eq "exo") -or ($_ -eq "defender")} {
                   if ($EXOAuthRequired) {
                       $EXOHelperParams = @{
                           M365Environment = $M365Environment;
                       }
                       if ($ServicePrincipalParams) {
                           $EXOHelperParams += @{ServicePrincipalParams = $ServicePrincipalParams}
                       }
                       Write-Verbose "Defender will require a sign in every single run regardless of what the LogIn parameter is set"
                       Connect-EXOHelper @EXOHelperParams
                       $EXOAuthRequired = $false
                   }
               }
               "powerplatform" {
                   $AddPowerAppsParams = @{
                       'ErrorAction' = 'Stop';
                   }
                   if ($ServicePrincipalParams.CertThumbprintParams) {
                       $AddPowerAppsParams += @{
                           CertificateThumbprint = $ServicePrincipalParams.CertThumbprintParams.CertificateThumbprint;
                           ApplicationId = $ServicePrincipalParams.CertThumbprintParams.AppID;
                           TenantID  = $ServicePrincipalParams.CertThumbprintParams.Organization; # Organization also works here
                       }
                   }
                   switch ($M365Environment) {
                       "commercial" {
                           $AddPowerAppsParams += @{'Endpoint'='prod';}
                       }
                       "gcc" {
                           $AddPowerAppsParams += @{'Endpoint'='usgov';}
                       }
                       "gcchigh" {
                           $AddPowerAppsParams += @{'Endpoint'='usgovhigh';}
                       }
                       "dod" {
                           $AddPowerAppsParams += @{'Endpoint'='dod';}
                       }
                   }
                   Add-PowerAppsAccount @AddPowerAppsParams | Out-Null
               }
               "sharepoint" {
                   if ($AADAuthRequired) {
                       $LimitedGraphParams = @{
                           'ErrorAction' = 'Stop';
                       }
                       if ($ServicePrincipalParams.CertThumbprintParams) {
                           $LimitedGraphParams += @{
                               CertificateThumbprint = $ServicePrincipalParams.CertThumbprintParams.CertificateThumbprint;
                               ClientID = $ServicePrincipalParams.CertThumbprintParams.AppID;
                               TenantId  = $ServicePrincipalParams.CertThumbprintParams.Organization; # Organization also works here
                           }
                       }
                       switch ($M365Environment) {
                           "gcchigh" {
                               $LimitedGraphParams += @{'Environment' = "USGov";}
                           }
                           "dod" {
                               $LimitedGraphParams += @{'Environment' = "USGovDoD";}
                           }
                       }
                       Connect-MgGraph @LimitedGraphParams | Out-Null
                       $AADAuthRequired = $false
                   }
                   if ($SPOAuthRequired) {
                       $InitialDomain = (Get-MgBetaOrganization).VerifiedDomains | Where-Object {$_.isInitial}
                       $InitialDomainPrefix = $InitialDomain.Name.split(".")[0]
                       $SPOParams = @{
                           'ErrorAction' = 'Stop';
                       }
                       $PnPParams = @{
                           'ErrorAction' = 'Stop';
                       }
                       switch ($M365Environment) {
                           {($_ -eq "commercial") -or ($_ -eq "gcc")} {
                               $SPOParams += @{
                                   'Url'= "https://$($InitialDomainPrefix)-admin.sharepoint.com";
                               }
                               $PnPParams += @{
                                   'Url'= "$($InitialDomainPrefix)-admin.sharepoint.com";
                               }
                           }
                           "gcchigh" {
                               $SPOParams += @{
                                   'Url'= "https://$($InitialDomainPrefix)-admin.sharepoint.us";
                                   'Region' = "ITAR";
                               }
                               $PnPParams += @{
                                   'Url'= "$($InitialDomainPrefix)-admin.sharepoint.us";
                                   'AzureEnvironment' = 'USGovernmentHigh'
                               }
                           }
                           "dod" {
                               $SPOParams += @{
                                   'Url'= "https://$($InitialDomainPrefix)-admin.sharepoint-mil.us";
                                   'Region' = "ITAR";
                               }
                               $PnPParams += @{
                                   'Url'= "$($InitialDomainPrefix)-admin.sharepoint-mil.us";
                                   'AzureEnvironment' = 'USGovernmentDoD'
                               }
                           }
                       }
                       if ($ServicePrincipalParams.CertThumbprintParams) {
                           $PnPParams += @{
                               Thumbprint = $ServicePrincipalParams.CertThumbprintParams.CertificateThumbprint;
                               ClientId = $ServicePrincipalParams.CertThumbprintParams.AppID;
                               Tenant  = $ServicePrincipalParams.CertThumbprintParams.Organization; # Organization Domain is actually required here.
                           }
                           Connect-PnPOnline @PnPParams | Out-Null
                       }
                       else {
                           Connect-SPOService @SPOParams | Out-Null
                       }
                       $SPOAuthRequired = $false
                   }
               }
               "teams" {
                   $TeamsParams = @{'ErrorAction'= 'Stop'}
                   if ($ServicePrincipalParams.CertThumbprintParams) {
                       $TeamsConnectToTenant = @{
                           CertificateThumbprint = $ServicePrincipalParams.CertThumbprintParams.CertificateThumbprint;
                           ApplicationId = $ServicePrincipalParams.CertThumbprintParams.AppID;
                           TenantId  = $ServicePrincipalParams.CertThumbprintParams.Organization; # Organization Domain is actually required here.
                       }
                       $TeamsParams += $TeamsConnectToTenant
                   }
                   switch ($M365Environment) {
                       "gcchigh" {
                           $TeamsParams += @{'TeamsEnvironmentName'= 'TeamsGCCH';}
                       }
                       "dod" {
                           $TeamsParams += @{'TeamsEnvironmentName'= 'TeamsDOD';}
                       }
                   }
                   Connect-MicrosoftTeams @TeamsParams | Out-Null
               }
               default {
                   throw "Invalid ProductName argument"
               }
           }
       }
       catch {
           Write-Error "Error establishing a connection with $($Product). $($_)"
           $ProdAuthFailed += $Product
           Write-Warning "$($Product) will be omitted from the output because of failed authentication"
       }
   }
   Write-Progress -Activity "Authenticating to each service" -Status "Ready" -Completed
   $ProdAuthFailed
}

function Disconnect-SCuBATenant {
   <#
   .SYNOPSIS
       Disconnect all active M365 connection sessions made by ScubaGear
   .DESCRIPTION
       Forces disconnect of all outstanding open sessions associated with
       M365 product APIs within the current PowerShell session.
       Best used after an ScubaGear run to ensure a new tenant connection is
       used for future ScubaGear runs.
   .Parameter ProductNames
   A list of one or more M365 shortened product names this function will disconnect from. By default this function will disconnect from all possible products ScubaGear can run against.
   .EXAMPLE
   Disconnect-SCuBATenant
   .EXAMPLE
   Disconnect-SCuBATenant -ProductNames teams
   .EXAMPLE
   Disconnect-SCuBATenant -ProductNames aad, exo
   .Functionality
   Public
   #>
   [CmdletBinding()]
   param(
       [ValidateSet("aad", "defender", "exo","powerplatform", "sharepoint", "teams", IgnoreCase = $false)]
       [ValidateNotNullOrEmpty()]
       [string[]]
       $ProductNames = @("aad", "defender", "exo", "powerplatform", "sharepoint", "teams")
   )
   $ErrorActionPreference = "SilentlyContinue"

   try {
       $N = 0
       $Len = $ProductNames.Length

       foreach ($Product in $ProductNames) {
           $N += 1
           $Percent = $N*100/$Len
           Write-Progress -Activity "Disconnecting from each service" -Status "Disconnecting from $($Product); $($n) of $($Len) disconnected." -PercentComplete $Percent
           Write-Verbose "Disconnecting from $Product."
           if (($Product -eq "aad") -or ($Product -eq "sharepoint")) {
               Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null

               if($Product -eq "sharepoint") {
                   Disconnect-SPOService -ErrorAction SilentlyContinue
                   Disconnect-PnPOnline -ErrorAction SilentlyContinue
               }
           }
           elseif ($Product -eq "teams") {
               Disconnect-MicrosoftTeams -Confirm:$false -ErrorAction SilentlyContinue
           }
           elseif ($Product -eq "powerplatform") {
               Remove-PowerAppsAccount -ErrorAction SilentlyContinue -WarningAction SilentlyContinue
           }
           elseif (($Product -eq "exo") -or ($Product -eq "defender")) {
               Disconnect-ExchangeOnline -Confirm:$false -ErrorAction SilentlyContinue -InformationAction SilentlyContinue | Out-Null
           }
           else {
               Write-Warning "Product $Product not recognized, skipping..."
           }
       }
       Write-Progress -Activity "Disconnecting from each service" -Status "Done" -Completed

   } catch [System.InvalidOperationException] {
       # Suppress error due to disconnect from service with no active connection
       continue
   } catch {
       Write-Error "ERRROR: Could not disconnect from $Product`n$($Error[0]): "
   } finally {
       $ErrorActionPreference = "Continue"
   }

}

Export-ModuleMember -Function @(
   'Connect-Tenant',
   'Disconnect-SCuBATenant'
)

# SIG # Begin signature block
# MIIoJgYJKoZIhvcNAQcCoIIoFzCCKBMCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCBP1Mzu3R1XlNo+
# i046p3C2B8dg9SPGB9YKtcxuYO41TqCCISkwggWNMIIEdaADAgECAhAOmxiO+dAt
# 5+/bUOIIQBhaMA0GCSqGSIb3DQEBDAUAMGUxCzAJBgNVBAYTAlVTMRUwEwYDVQQK
# EwxEaWdpQ2VydCBJbmMxGTAXBgNVBAsTEHd3dy5kaWdpY2VydC5jb20xJDAiBgNV
# BAMTG0RpZ2lDZXJ0IEFzc3VyZWQgSUQgUm9vdCBDQTAeFw0yMjA4MDEwMDAwMDBa
# Fw0zMTExMDkyMzU5NTlaMGIxCzAJBgNVBAYTAlVTMRUwEwYDVQQKEwxEaWdpQ2Vy
# dCBJbmMxGTAXBgNVBAsTEHd3dy5kaWdpY2VydC5jb20xITAfBgNVBAMTGERpZ2lD
# ZXJ0IFRydXN0ZWQgUm9vdCBHNDCCAiIwDQYJKoZIhvcNAQEBBQADggIPADCCAgoC
# ggIBAL/mkHNo3rvkXUo8MCIwaTPswqclLskhPfKK2FnC4SmnPVirdprNrnsbhA3E
# MB/zG6Q4FutWxpdtHauyefLKEdLkX9YFPFIPUh/GnhWlfr6fqVcWWVVyr2iTcMKy
# unWZanMylNEQRBAu34LzB4TmdDttceItDBvuINXJIB1jKS3O7F5OyJP4IWGbNOsF
# xl7sWxq868nPzaw0QF+xembud8hIqGZXV59UWI4MK7dPpzDZVu7Ke13jrclPXuU1
# 5zHL2pNe3I6PgNq2kZhAkHnDeMe2scS1ahg4AxCN2NQ3pC4FfYj1gj4QkXCrVYJB
# MtfbBHMqbpEBfCFM1LyuGwN1XXhm2ToxRJozQL8I11pJpMLmqaBn3aQnvKFPObUR
# WBf3JFxGj2T3wWmIdph2PVldQnaHiZdpekjw4KISG2aadMreSx7nDmOu5tTvkpI6
# nj3cAORFJYm2mkQZK37AlLTSYW3rM9nF30sEAMx9HJXDj/chsrIRt7t/8tWMcCxB
# YKqxYxhElRp2Yn72gLD76GSmM9GJB+G9t+ZDpBi4pncB4Q+UDCEdslQpJYls5Q5S
# UUd0viastkF13nqsX40/ybzTQRESW+UQUOsxxcpyFiIJ33xMdT9j7CFfxCBRa2+x
# q4aLT8LWRV+dIPyhHsXAj6KxfgommfXkaS+YHS312amyHeUbAgMBAAGjggE6MIIB
# NjAPBgNVHRMBAf8EBTADAQH/MB0GA1UdDgQWBBTs1+OC0nFdZEzfLmc/57qYrhwP
# TzAfBgNVHSMEGDAWgBRF66Kv9JLLgjEtUYunpyGd823IDzAOBgNVHQ8BAf8EBAMC
# AYYweQYIKwYBBQUHAQEEbTBrMCQGCCsGAQUFBzABhhhodHRwOi8vb2NzcC5kaWdp
# Y2VydC5jb20wQwYIKwYBBQUHMAKGN2h0dHA6Ly9jYWNlcnRzLmRpZ2ljZXJ0LmNv
# bS9EaWdpQ2VydEFzc3VyZWRJRFJvb3RDQS5jcnQwRQYDVR0fBD4wPDA6oDigNoY0
# aHR0cDovL2NybDMuZGlnaWNlcnQuY29tL0RpZ2lDZXJ0QXNzdXJlZElEUm9vdENB
# LmNybDARBgNVHSAECjAIMAYGBFUdIAAwDQYJKoZIhvcNAQEMBQADggEBAHCgv0Nc
# Vec4X6CjdBs9thbX979XB72arKGHLOyFXqkauyL4hxppVCLtpIh3bb0aFPQTSnov
# Lbc47/T/gLn4offyct4kvFIDyE7QKt76LVbP+fT3rDB6mouyXtTP0UNEm0Mh65Zy
# oUi0mcudT6cGAxN3J0TU53/oWajwvy8LpunyNDzs9wPHh6jSTEAZNUZqaVSwuKFW
# juyk1T3osdz9HNj0d1pcVIxv76FQPfx2CWiEn2/K2yCNNWAcAgPLILCsWKAOQGPF
# mCLBsln1VWvPJ6tsds5vIy30fnFqI2si/xK4VC0nftg62fC2h5b9W9FcrBjDTZ9z
# twGpn1eqXijiuZQwggauMIIElqADAgECAhAHNje3JFR82Ees/ShmKl5bMA0GCSqG
# SIb3DQEBCwUAMGIxCzAJBgNVBAYTAlVTMRUwEwYDVQQKEwxEaWdpQ2VydCBJbmMx
# GTAXBgNVBAsTEHd3dy5kaWdpY2VydC5jb20xITAfBgNVBAMTGERpZ2lDZXJ0IFRy
# dXN0ZWQgUm9vdCBHNDAeFw0yMjAzMjMwMDAwMDBaFw0zNzAzMjIyMzU5NTlaMGMx
# CzAJBgNVBAYTAlVTMRcwFQYDVQQKEw5EaWdpQ2VydCwgSW5jLjE7MDkGA1UEAxMy
# RGlnaUNlcnQgVHJ1c3RlZCBHNCBSU0E0MDk2IFNIQTI1NiBUaW1lU3RhbXBpbmcg
# Q0EwggIiMA0GCSqGSIb3DQEBAQUAA4ICDwAwggIKAoICAQDGhjUGSbPBPXJJUVXH
# JQPE8pE3qZdRodbSg9GeTKJtoLDMg/la9hGhRBVCX6SI82j6ffOciQt/nR+eDzMf
# UBMLJnOWbfhXqAJ9/UO0hNoR8XOxs+4rgISKIhjf69o9xBd/qxkrPkLcZ47qUT3w
# 1lbU5ygt69OxtXXnHwZljZQp09nsad/ZkIdGAHvbREGJ3HxqV3rwN3mfXazL6IRk
# tFLydkf3YYMZ3V+0VAshaG43IbtArF+y3kp9zvU5EmfvDqVjbOSmxR3NNg1c1eYb
# qMFkdECnwHLFuk4fsbVYTXn+149zk6wsOeKlSNbwsDETqVcplicu9Yemj052FVUm
# cJgmf6AaRyBD40NjgHt1biclkJg6OBGz9vae5jtb7IHeIhTZgirHkr+g3uM+onP6
# 5x9abJTyUpURK1h0QCirc0PO30qhHGs4xSnzyqqWc0Jon7ZGs506o9UD4L/wojzK
# QtwYSH8UNM/STKvvmz3+DrhkKvp1KCRB7UK/BZxmSVJQ9FHzNklNiyDSLFc1eSuo
# 80VgvCONWPfcYd6T/jnA+bIwpUzX6ZhKWD7TA4j+s4/TXkt2ElGTyYwMO1uKIqjB
# Jgj5FBASA31fI7tk42PgpuE+9sJ0sj8eCXbsq11GdeJgo1gJASgADoRU7s7pXche
# MBK9Rp6103a50g5rmQzSM7TNsQIDAQABo4IBXTCCAVkwEgYDVR0TAQH/BAgwBgEB
# /wIBADAdBgNVHQ4EFgQUuhbZbU2FL3MpdpovdYxqII+eyG8wHwYDVR0jBBgwFoAU
# 7NfjgtJxXWRM3y5nP+e6mK4cD08wDgYDVR0PAQH/BAQDAgGGMBMGA1UdJQQMMAoG
# CCsGAQUFBwMIMHcGCCsGAQUFBwEBBGswaTAkBggrBgEFBQcwAYYYaHR0cDovL29j
# c3AuZGlnaWNlcnQuY29tMEEGCCsGAQUFBzAChjVodHRwOi8vY2FjZXJ0cy5kaWdp
# Y2VydC5jb20vRGlnaUNlcnRUcnVzdGVkUm9vdEc0LmNydDBDBgNVHR8EPDA6MDig
# NqA0hjJodHRwOi8vY3JsMy5kaWdpY2VydC5jb20vRGlnaUNlcnRUcnVzdGVkUm9v
# dEc0LmNybDAgBgNVHSAEGTAXMAgGBmeBDAEEAjALBglghkgBhv1sBwEwDQYJKoZI
# hvcNAQELBQADggIBAH1ZjsCTtm+YqUQiAX5m1tghQuGwGC4QTRPPMFPOvxj7x1Bd
# 4ksp+3CKDaopafxpwc8dB+k+YMjYC+VcW9dth/qEICU0MWfNthKWb8RQTGIdDAiC
# qBa9qVbPFXONASIlzpVpP0d3+3J0FNf/q0+KLHqrhc1DX+1gtqpPkWaeLJ7giqzl
# /Yy8ZCaHbJK9nXzQcAp876i8dU+6WvepELJd6f8oVInw1YpxdmXazPByoyP6wCeC
# RK6ZJxurJB4mwbfeKuv2nrF5mYGjVoarCkXJ38SNoOeY+/umnXKvxMfBwWpx2cYT
# gAnEtp/Nh4cku0+jSbl3ZpHxcpzpSwJSpzd+k1OsOx0ISQ+UzTl63f8lY5knLD0/
# a6fxZsNBzU+2QJshIUDQtxMkzdwdeDrknq3lNHGS1yZr5Dhzq6YBT70/O3itTK37
# xJV77QpfMzmHQXh6OOmc4d0j/R0o08f56PGYX/sr2H7yRp11LB4nLCbbbxV7HhmL
# NriT1ObyF5lZynDwN7+YAN8gFk8n+2BnFqFmut1VwDophrCYoCvtlUG3OtUVmDG0
# YgkPCr2B2RP+v6TR81fZvAT6gt4y3wSJ8ADNXcL50CN/AAvkdgIm2fBldkKmKYcJ
# RyvmfxqkhQ/8mJb2VVQrH4D6wPIOK+XW+6kvRBVK5xMOHds3OBqhK/bt1nz8MIIG
# sDCCBJigAwIBAgIQCK1AsmDSnEyfXs2pvZOu2TANBgkqhkiG9w0BAQwFADBiMQsw
# CQYDVQQGEwJVUzEVMBMGA1UEChMMRGlnaUNlcnQgSW5jMRkwFwYDVQQLExB3d3cu
# ZGlnaWNlcnQuY29tMSEwHwYDVQQDExhEaWdpQ2VydCBUcnVzdGVkIFJvb3QgRzQw
# HhcNMjEwNDI5MDAwMDAwWhcNMzYwNDI4MjM1OTU5WjBpMQswCQYDVQQGEwJVUzEX
# MBUGA1UEChMORGlnaUNlcnQsIEluYy4xQTA/BgNVBAMTOERpZ2lDZXJ0IFRydXN0
# ZWQgRzQgQ29kZSBTaWduaW5nIFJTQTQwOTYgU0hBMzg0IDIwMjEgQ0ExMIICIjAN
# BgkqhkiG9w0BAQEFAAOCAg8AMIICCgKCAgEA1bQvQtAorXi3XdU5WRuxiEL1M4zr
# PYGXcMW7xIUmMJ+kjmjYXPXrNCQH4UtP03hD9BfXHtr50tVnGlJPDqFX/IiZwZHM
# gQM+TXAkZLON4gh9NH1MgFcSa0OamfLFOx/y78tHWhOmTLMBICXzENOLsvsI8Irg
# nQnAZaf6mIBJNYc9URnokCF4RS6hnyzhGMIazMXuk0lwQjKP+8bqHPNlaJGiTUyC
# EUhSaN4QvRRXXegYE2XFf7JPhSxIpFaENdb5LpyqABXRN/4aBpTCfMjqGzLmysL0
# p6MDDnSlrzm2q2AS4+jWufcx4dyt5Big2MEjR0ezoQ9uo6ttmAaDG7dqZy3SvUQa
# khCBj7A7CdfHmzJawv9qYFSLScGT7eG0XOBv6yb5jNWy+TgQ5urOkfW+0/tvk2E0
# XLyTRSiDNipmKF+wc86LJiUGsoPUXPYVGUztYuBeM/Lo6OwKp7ADK5GyNnm+960I
# HnWmZcy740hQ83eRGv7bUKJGyGFYmPV8AhY8gyitOYbs1LcNU9D4R+Z1MI3sMJN2
# FKZbS110YU0/EpF23r9Yy3IQKUHw1cVtJnZoEUETWJrcJisB9IlNWdt4z4FKPkBH
# X8mBUHOFECMhWWCKZFTBzCEa6DgZfGYczXg4RTCZT/9jT0y7qg0IU0F8WD1Hs/q2
# 7IwyCQLMbDwMVhECAwEAAaOCAVkwggFVMBIGA1UdEwEB/wQIMAYBAf8CAQAwHQYD
# VR0OBBYEFGg34Ou2O/hfEYb7/mF7CIhl9E5CMB8GA1UdIwQYMBaAFOzX44LScV1k
# TN8uZz/nupiuHA9PMA4GA1UdDwEB/wQEAwIBhjATBgNVHSUEDDAKBggrBgEFBQcD
# AzB3BggrBgEFBQcBAQRrMGkwJAYIKwYBBQUHMAGGGGh0dHA6Ly9vY3NwLmRpZ2lj
# ZXJ0LmNvbTBBBggrBgEFBQcwAoY1aHR0cDovL2NhY2VydHMuZGlnaWNlcnQuY29t
# L0RpZ2lDZXJ0VHJ1c3RlZFJvb3RHNC5jcnQwQwYDVR0fBDwwOjA4oDagNIYyaHR0
# cDovL2NybDMuZGlnaWNlcnQuY29tL0RpZ2lDZXJ0VHJ1c3RlZFJvb3RHNC5jcmww
# HAYDVR0gBBUwEzAHBgVngQwBAzAIBgZngQwBBAEwDQYJKoZIhvcNAQEMBQADggIB
# ADojRD2NCHbuj7w6mdNW4AIapfhINPMstuZ0ZveUcrEAyq9sMCcTEp6QRJ9L/Z6j
# fCbVN7w6XUhtldU/SfQnuxaBRVD9nL22heB2fjdxyyL3WqqQz/WTauPrINHVUHmI
# moqKwba9oUgYftzYgBoRGRjNYZmBVvbJ43bnxOQbX0P4PpT/djk9ntSZz0rdKOtf
# JqGVWEjVGv7XJz/9kNF2ht0csGBc8w2o7uCJob054ThO2m67Np375SFTWsPK6Wrx
# oj7bQ7gzyE84FJKZ9d3OVG3ZXQIUH0AzfAPilbLCIXVzUstG2MQ0HKKlS43Nb3Y3
# LIU/Gs4m6Ri+kAewQ3+ViCCCcPDMyu/9KTVcH4k4Vfc3iosJocsL6TEa/y4ZXDlx
# 4b6cpwoG1iZnt5LmTl/eeqxJzy6kdJKt2zyknIYf48FWGysj/4+16oh7cGvmoLr9
# Oj9FpsToFpFSi0HASIRLlk2rREDjjfAVKM7t8RhWByovEMQMCGQ8M4+uKIw8y4+I
# Cw2/O/TOHnuO77Xry7fwdxPm5yg/rBKupS8ibEH5glwVZsxsDsrFhsP2JjMMB0ug
# 0wcCampAMEhLNKhRILutG4UI4lkNbcoFUCvqShyepf2gpx8GdOfy1lKQ/a+FSCH5
# Vzu0nAPthkX0tGFuv2jiJmCG6sivqf6UHedjGzqGVnhOMIIGwjCCBKqgAwIBAgIQ
# BUSv85SdCDmmv9s/X+VhFjANBgkqhkiG9w0BAQsFADBjMQswCQYDVQQGEwJVUzEX
# MBUGA1UEChMORGlnaUNlcnQsIEluYy4xOzA5BgNVBAMTMkRpZ2lDZXJ0IFRydXN0
# ZWQgRzQgUlNBNDA5NiBTSEEyNTYgVGltZVN0YW1waW5nIENBMB4XDTIzMDcxNDAw
# MDAwMFoXDTM0MTAxMzIzNTk1OVowSDELMAkGA1UEBhMCVVMxFzAVBgNVBAoTDkRp
# Z2lDZXJ0LCBJbmMuMSAwHgYDVQQDExdEaWdpQ2VydCBUaW1lc3RhbXAgMjAyMzCC
# AiIwDQYJKoZIhvcNAQEBBQADggIPADCCAgoCggIBAKNTRYcdg45brD5UsyPgz5/X
# 5dLnXaEOCdwvSKOXejsqnGfcYhVYwamTEafNqrJq3RApih5iY2nTWJw1cb86l+uU
# UI8cIOrHmjsvlmbjaedp/lvD1isgHMGXlLSlUIHyz8sHpjBoyoNC2vx/CSSUpIIa
# 2mq62DvKXd4ZGIX7ReoNYWyd/nFexAaaPPDFLnkPG2ZS48jWPl/aQ9OE9dDH9kgt
# XkV1lnX+3RChG4PBuOZSlbVH13gpOWvgeFmX40QrStWVzu8IF+qCZE3/I+PKhu60
# pCFkcOvV5aDaY7Mu6QXuqvYk9R28mxyyt1/f8O52fTGZZUdVnUokL6wrl76f5P17
# cz4y7lI0+9S769SgLDSb495uZBkHNwGRDxy1Uc2qTGaDiGhiu7xBG3gZbeTZD+BY
# QfvYsSzhUa+0rRUGFOpiCBPTaR58ZE2dD9/O0V6MqqtQFcmzyrzXxDtoRKOlO0L9
# c33u3Qr/eTQQfqZcClhMAD6FaXXHg2TWdc2PEnZWpST618RrIbroHzSYLzrqawGw
# 9/sqhux7UjipmAmhcbJsca8+uG+W1eEQE/5hRwqM/vC2x9XH3mwk8L9CgsqgcT2c
# kpMEtGlwJw1Pt7U20clfCKRwo+wK8REuZODLIivK8SgTIUlRfgZm0zu++uuRONhR
# B8qUt+JQofM604qDy0B7AgMBAAGjggGLMIIBhzAOBgNVHQ8BAf8EBAMCB4AwDAYD
# VR0TAQH/BAIwADAWBgNVHSUBAf8EDDAKBggrBgEFBQcDCDAgBgNVHSAEGTAXMAgG
# BmeBDAEEAjALBglghkgBhv1sBwEwHwYDVR0jBBgwFoAUuhbZbU2FL3MpdpovdYxq
# II+eyG8wHQYDVR0OBBYEFKW27xPn783QZKHVVqllMaPe1eNJMFoGA1UdHwRTMFEw
# T6BNoEuGSWh0dHA6Ly9jcmwzLmRpZ2ljZXJ0LmNvbS9EaWdpQ2VydFRydXN0ZWRH
# NFJTQTQwOTZTSEEyNTZUaW1lU3RhbXBpbmdDQS5jcmwwgZAGCCsGAQUFBwEBBIGD
# MIGAMCQGCCsGAQUFBzABhhhodHRwOi8vb2NzcC5kaWdpY2VydC5jb20wWAYIKwYB
# BQUHMAKGTGh0dHA6Ly9jYWNlcnRzLmRpZ2ljZXJ0LmNvbS9EaWdpQ2VydFRydXN0
# ZWRHNFJTQTQwOTZTSEEyNTZUaW1lU3RhbXBpbmdDQS5jcnQwDQYJKoZIhvcNAQEL
# BQADggIBAIEa1t6gqbWYF7xwjU+KPGic2CX/yyzkzepdIpLsjCICqbjPgKjZ5+PF
# 7SaCinEvGN1Ott5s1+FgnCvt7T1IjrhrunxdvcJhN2hJd6PrkKoS1yeF844ektrC
# QDifXcigLiV4JZ0qBXqEKZi2V3mP2yZWK7Dzp703DNiYdk9WuVLCtp04qYHnbUFc
# jGnRuSvExnvPnPp44pMadqJpddNQ5EQSviANnqlE0PjlSXcIWiHFtM+YlRpUurm8
# wWkZus8W8oM3NG6wQSbd3lqXTzON1I13fXVFoaVYJmoDRd7ZULVQjK9WvUzF4UbF
# KNOt50MAcN7MmJ4ZiQPq1JE3701S88lgIcRWR+3aEUuMMsOI5ljitts++V+wQtaP
# 4xeR0arAVeOGv6wnLEHQmjNKqDbUuXKWfpd5OEhfysLcPTLfddY2Z1qJ+Panx+VP
# NTwAvb6cKmx5AdzaROY63jg7B145WPR8czFVoIARyxQMfq68/qTreWWqaNYiyjvr
# moI1VygWy2nyMpqy0tg6uLFGhmu6F/3Ed2wVbK6rr3M66ElGt9V/zLY4wNjsHPW2
# obhDLN9OTH0eaHDAdwrUAuBcYLso/zjlUlrWrBciI0707NMX+1Br/wd3H3GXREHJ
# uEbTbDJ8WC9nR2XlG3O2mflrLAZG70Ee8PBf4NvZrZCARK+AEEGKMIIHaDCCBVCg
# AwIBAgIQBRMJkZ8fE7wl9ag7a9rrUjANBgkqhkiG9w0BAQsFADBpMQswCQYDVQQG
# EwJVUzEXMBUGA1UEChMORGlnaUNlcnQsIEluYy4xQTA/BgNVBAMTOERpZ2lDZXJ0
# IFRydXN0ZWQgRzQgQ29kZSBTaWduaW5nIFJTQTQwOTYgU0hBMzg0IDIwMjEgQ0Ex
# MB4XDTIzMDEwNDAwMDAwMFoXDTIzMTIxOTIzNTk1OVowbTELMAkGA1UEBhMCVVMx
# HTAbBgNVBAgTFERpc3RyaWN0IG9mIENvbHVtYmlhMRMwEQYDVQQHEwpXYXNoaW5n
# dG9uMQ0wCwYDVQQKEwRDSVNBMQwwCgYDVQQLEwNDU0QxDTALBgNVBAMTBENJU0Ew
# ggIiMA0GCSqGSIb3DQEBAQUAA4ICDwAwggIKAoICAQDLXR6b9qXsackjyuwFq4mP
# VniUW6L0dLFjmEkAAL3EGNjUJcU3sC1gHkdLJFuLS7hM3DrnpDSQP5tQ9x6IZWNi
# 7jZ03iObmo+cLTxzfLL/Tcm+LZHRUNG70WfWZjd5Ng0spZ9cGS2Af4Hi0QsAsPlo
# Y6sKiFmr5UK1erV30ChSGl50cvOHCwWZIDzrq/ZtaZ0ypQd2CWz/f4HMME+WJXUK
# l3iB/hZ8ZcuQXeSiKRLVLc7oRcug/FVs+ZUoQha/fj/Utp9uJ0eZG7j37bzwpMAx
# O2LlAXg0hw1XwA/Ol63w1k+ar2WmwMhsai0NSsBVEe5RbPlcMawM/myIb0yHlgQn
# QvmbgwSKMiYWgvCFthY01ZseIe+R+KOYS78E+c3pn8eAK8+h8q+nkxiQ6Ax70U6a
# 0O4+1/7XO5FmDfKZTGKueNpoPh+GrkdwwGtH6X7jtrqgNmrBFKDA3t95+JMnhdec
# Z3JTdQwjHw8udLd0MULJEYvrGXQZDWwW1C3wV/EEL88wuyb2ZO5ptWiAHCkLmSax
# 0A++f7P7DV18bpsBcCLFDxX4sJWGdOvUWPDkfKygrg/2B31SAeeWLjXx5/f5W4KE
# UHcXuIavTwx5V2O2Y6bcSG5B1SzFnWpNLHetJCsQQF25ytGA8T2HVCiwdUcwtSfV
# HveN0xbu4oTTYEEHz5BRVwIDAQABo4ICBjCCAgIwHwYDVR0jBBgwFoAUaDfg67Y7
# +F8Rhvv+YXsIiGX0TkIwHQYDVR0OBBYEFLnGiFWxQ7K4Wp8VN1w7VoQeP2D8MA4G
# A1UdDwEB/wQEAwIHgDATBgNVHSUEDDAKBggrBgEFBQcDAzCBtQYDVR0fBIGtMIGq
# MFOgUaBPhk1odHRwOi8vY3JsMy5kaWdpY2VydC5jb20vRGlnaUNlcnRUcnVzdGVk
# RzRDb2RlU2lnbmluZ1JTQTQwOTZTSEEzODQyMDIxQ0ExLmNybDBToFGgT4ZNaHR0
# cDovL2NybDQuZGlnaWNlcnQuY29tL0RpZ2lDZXJ0VHJ1c3RlZEc0Q29kZVNpZ25p
# bmdSU0E0MDk2U0hBMzg0MjAyMUNBMS5jcmwwPgYDVR0gBDcwNTAzBgZngQwBBAEw
# KTAnBggrBgEFBQcCARYbaHR0cDovL3d3dy5kaWdpY2VydC5jb20vQ1BTMIGUBggr
# BgEFBQcBAQSBhzCBhDAkBggrBgEFBQcwAYYYaHR0cDovL29jc3AuZGlnaWNlcnQu
# Y29tMFwGCCsGAQUFBzAChlBodHRwOi8vY2FjZXJ0cy5kaWdpY2VydC5jb20vRGln
# aUNlcnRUcnVzdGVkRzRDb2RlU2lnbmluZ1JTQTQwOTZTSEEzODQyMDIxQ0ExLmNy
# dDAMBgNVHRMBAf8EAjAAMA0GCSqGSIb3DQEBCwUAA4ICAQAL8rkzWNZ800AoHwRx
# PinaHJwyolXhUBlW9uUVV2ZZ7tUxTdPuBRjS4WV67/r4pStSioaQLE3+HyneO1G7
# WXBJcKaextOjSLO+RKSgGe0JQcQd+8lHMZ2gCq7FbrOQK/ge1BgummQIajAtcq6v
# IZE00Nnt7tiWthq8GGCEq3TFrBdy4TdMagUvrpYiMIvAjQ71CszN/1phgVG12svZ
# uO60r/o2DrhvsmDDOvvRvEsMOK4YQ1+XPZUdXX/cP2LeHTksfvy+bjGPxeYwgbfb
# DT2lnOvdtqK/3Goc/ORERK3/jmzNmRwQROsZKHOTrSnwyfYj5W6FFGqhxikPeDrp
# bUes7V2Qxmfak0/dQuU1NNzHx6BAXfHLnapL+JkHWWG03WL7SyAjnuFykXe91LAZ
# Ibkr/2Q0KqV/+1ZiCsvvAB5G460WGW0ib7m+MK+0m3aOzPsSoLHOC8fyinHPZNOu
# u+6zBE4XXRsTxypS+z33B5sHbmiublffXS16GmOKT47Z85GfRVueg/sDG8/fBvgp
# Kuy2AjwvwlGe4mUdJzCLafDFrfqcht4iuPDeFwj+S5lZSfOgKrVmRZQcd50X70K6
# N0SXRyWaAXBTC22fFXIfM/8VkDkwIyLPPQ1+92kq99Zh+XkIuCY2jq9ckI+YuOwc
# 2udi1gf8OTWjOjFQsiQVLF5AQzGCBlMwggZPAgEBMH0waTELMAkGA1UEBhMCVVMx
# FzAVBgNVBAoTDkRpZ2lDZXJ0LCBJbmMuMUEwPwYDVQQDEzhEaWdpQ2VydCBUcnVz
# dGVkIEc0IENvZGUgU2lnbmluZyBSU0E0MDk2IFNIQTM4NCAyMDIxIENBMQIQBRMJ
# kZ8fE7wl9ag7a9rrUjANBglghkgBZQMEAgEFAKCBhDAYBgorBgEEAYI3AgEMMQow
# CKACgAChAoAAMBkGCSqGSIb3DQEJAzEMBgorBgEEAYI3AgEEMBwGCisGAQQBgjcC
# AQsxDjAMBgorBgEEAYI3AgEVMC8GCSqGSIb3DQEJBDEiBCBnJ9xe+q1oajz1i7Tz
# QkVcBDFTQNC9Xxl9nmxP/zMirjANBgkqhkiG9w0BAQEFAASCAgBSI0OaafF6UuLW
# 71WLmHv+B4zNy36dq4E61Ua4VruzcyyaUM69JquL1lSLvyKSS8Ypfx12NsMWY61X
# s+7Pem42ansiCv88Uawgu63HHOk4LzlokwIN0ypkPqc+uRuOXlvw66RPjz97eoGx
# 0+3q7kK39P9B7cGgwijzpbRa3N34kieoSrsuP9ZW0rHl++Z1De5ItqQTkBZ9p0wL
# wC7YPP19UJ+F1VxN7XRmgo/MnEFQTesdFnOhewLveNgfM7Gpis+9yG07rHu4tV2p
# G6YuWnXNv6DFZSmRYYbfI1diXv9wAHliA4fO6MR7HCDdU3Vt1x2a9ZLonZ48kYjX
# 7vFcNBLRfK4ZTNji1SAoeI4dcTnmleNUti2gRZdzIE4NQm7CQ6GpaP+SKrQE9CzU
# fL/vdNKY3ti1A9KRRqT2Z8bNVTvYl6BBZYhaXvCK2d2w5mLdnb2nSAApG7PJI2k1
# T2SFIPLzxvgzRKO4nB2DnYLCYX3cR3p9eYOg8YodzhFHAxdtNohvl6MOfIb3uq1S
# y09wuYCBdey7F4HodE71iEXNN5foDQB4ADQeTufxCEM55GdT20BVx+DOxVErZj0K
# 9hcV5nPQLsPI7zUx+7zjCPuda1Vpp5BP3ikci8iqVA166b0KwwljULR3kS5vCaFK
# 5yBTucBTleCCylCIycJ+1SVrwcZhlaGCAyAwggMcBgkqhkiG9w0BCQYxggMNMIID
# CQIBATB3MGMxCzAJBgNVBAYTAlVTMRcwFQYDVQQKEw5EaWdpQ2VydCwgSW5jLjE7
# MDkGA1UEAxMyRGlnaUNlcnQgVHJ1c3RlZCBHNCBSU0E0MDk2IFNIQTI1NiBUaW1l
# U3RhbXBpbmcgQ0ECEAVEr/OUnQg5pr/bP1/lYRYwDQYJYIZIAWUDBAIBBQCgaTAY
# BgkqhkiG9w0BCQMxCwYJKoZIhvcNAQcBMBwGCSqGSIb3DQEJBTEPFw0yMzEyMTMx
# NzU5MjNaMC8GCSqGSIb3DQEJBDEiBCDq5VAYkAa1UuNynyOgILONKDL6tFcbRfzk
# h0tduEFNGTANBgkqhkiG9w0BAQEFAASCAgBx36k7e25eft+OFCahYCisScoWFm1H
# ZA9a1ydDtucNvBj3BFB2D7rlSq7TGmJ5KXP+esGMf4kxwEoRy+7prgURBFwfmRoy
# LvnilPPL9K4F9tHi/5obxkpt+jTxqI214wXrbcEg0IZRDei5kek4mZRWx/5iVH11
# 9063kngWKmqJXp3RNPvYoqaMqtivOkuryjzF7crecoBMgybGfHZNJSiXCYbQXZD3
# h+QpPMT5ZDaEvBnuSVSrjhI0/C3LsVeiRUpWiWkn8nzf0Gq6FOfYB0UHf2fuKfVc
# DqrHOgwBxs8SLTVO/EmFJcoHUjla/7UIe2AKqEyVTqrMdnOvsASGowBR2PozTKkS
# NTYpaKMEQbhy/hNoQAFRkquSxkK5QZz7xypi7vLHitI+enKwR57OgiEcmLCf6maJ
# DKRmFWLE9fYNAfnmxgEJDNs8EwDNKjD63iSrApormygmKqa2dDZKCZyTNZllFrvo
# +CGV5ATLLfg3NwPwvuWrIhaZL6ghPfx2FFRssV4kA2sSdACNMrL1lT9lk6cgHkvB
# 5RHzERdWbMkEluf4FOiXeHjXQXRZFMTWs5jAwBHMtk2b0fDeY2njUw04Aql+lS3f
# EASNVYto2ekMJrdm5zpTgipHa2t2n2vO6Zl/b1IfMkKRvPP33VjOtXtp0ClXI60m
# g7f/IDJmv2uEbQ==
# SIG # End signature block
