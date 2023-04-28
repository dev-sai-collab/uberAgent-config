#Requires -RunAsAdministrator
#Requires -Version 3.0
. $PSScriptRoot\..\Shared\Helper.ps1 -Force

[Flags()] enum FW_PROFILE {
   Domain = 1
   Private = 2
   Public = 4
}

[Flags()] enum FW_IP_PROTOCOL_TCP {
   TCP = 6
   UDP = 17
   ICMPv4 = 1
   ICMPv6 = 58
}

[Flags()] enum FW_RULE_DIRECTION {
   IN = 1
   OUT = 2
}

[Flags()] enum FW_ACTION {
   BLOCK = 0
   ALLOW = 1
}


# function to check if firewall is enabled
function Get-vlIsFirewallEnabled {
   <#
    .SYNOPSIS
        Function that checks if the firewall is enabled.
    .DESCRIPTION
        Function that checks if the firewall is enabled.
    .LINK
        https://uberagent.com
    .OUTPUTS
        Returns a [psobject] containing the following properties:

        Domain
        Private
        Public

        The value of each property is a boolean indicating if the firewall is enabled for the specific profile.

    .EXAMPLE
        Get-vlIsFirewallEnabled
    #>

   try {
      $privateNetwork = Get-NetConnectionProfile | Where-Object {$_.NetworkCategory -eq "Private"}
      $publicNetwork = Get-NetConnectionProfile | Where-Object {$_.NetworkCategory -eq "Public"}
      $domainAuthenticatedNetwork = Get-NetConnectionProfile | Where-Object {$_.NetworkCategory -eq "DomainAuthenticated"}

      $firewall = Get-NetFirewallProfile -All
      $result = [PSCustomObject]@{
         Domain  = [PSCustomObject]@{
            Enabled = $firewall | where-object { $_.Profile -eq "Domain" } | select-object -ExpandProperty Enabled
            Connected = if ($domainAuthenticatedNetwork) { $true } else { $false }
         }
         Private = [PSCustomObject]@{
            Enabled = $firewall | where-object { $_.Profile -eq "Private" } | select-object -ExpandProperty Enabled
            Connected = if ($privateNetwork) { $true } else { $false }
         }
         Public  = [PSCustomObject]@{
            Enabled = $firewall | where-object { $_.Profile -eq "Public" } | select-object -ExpandProperty Enabled
            Connected = if ($publicNetwork) { $true } else { $false }
         }
      }

      $score = 10

      if ($result.Domain.Enabled -eq $false -or $result.Private.Enabled -eq $false) {
         $score = 5
      }

      if ($result.Public.Enabled -eq $false) {
         $score = 0
      }

      return New-vlResultObject -result $result -score $score
   }
   catch {
      return New-vlErrorObject($_)
   }
}

# function to check open firewall ports returns array of open ports
function Get-vlOpenFirewallPorts {
   <#
    .SYNOPSIS
        Function that iterates over all profiles and returns all enabled rules for all profiles.
    .DESCRIPTION
        Function that iterates over all profiles and returns all enabled rules for all profiles.
    .LINK
        https://uberagent.com

    .OUTPUTS
        Returns an array of objects containing the following properties:

        Name
        ApplicationName
        LocalPorts
        RemotePorts

    .EXAMPLE
        Get-vlOpenFirewallPorts
    #>

   try {
      $rulesEx = Get-NetFirewallRule -Enabled True -Direction Inbound -Action Allow -ErrorAction SilentlyContinue -PolicyStore ActiveStore
      $rulesSystemDefaults = Get-NetFirewallRule  -Enabled True -Direction Inbound -Action Allow -ErrorAction SilentlyContinue -PolicyStore SystemDefaults
      $rulesStaticServiceStore = Get-NetFirewallRule  -Enabled True -Direction Inbound -Action Allow -ErrorAction SilentlyContinue -PolicyStore StaticServiceStore
      #$RSOP = Get-NetFirewallRule -Enabled True -Direction Inbound -Action Allow -ErrorAction SilentlyContinue -PolicyStore RSOP

      # To get the GPO Rules use $RSOP. They are not included in $rulesEx by default.

      # get rule that contains GPO Test from rulesEx
      $rulesPersistentStore = $rulesEx | Where-Object { $_.DisplayName -like "*GPO Test RULE*" }

      # remove $rulesSystemDefaults, $rulesPersistentStore and $rulesStaticServiceStore from $rulesEx
      $rulesEx = $rulesEx | Where-Object { $_.ID -notin $rulesSystemDefaults.ID }
      $rulesEx = $rulesEx | Where-Object { $_.ID -notin $rulesStaticServiceStore.ID }
      $rulesEx = $rulesEx | Where-Object { $_.ID -notin $rulesPersistentStore.ID }

      # only keep rules where group is "" or $null
      $rulesEx = $rulesEx | Where-Object { $_.Group -eq "" -or $_.Group -eq $null }

      $rules = $rules | select-object -Property Name, DisplayName, Group, Profile, PolicyStoreSourceType

      return New-vlResultObject -result $rulesEx -score 10
   }
   catch [Microsoft.Management.Infrastructure.CimException] {
      return "[Get-vlOpenFirewallPorts] You need elevated privileges"
   }
   catch {
      return New-vlErrorObject($_)
   }
}


function Get-vlFirewallCheck {
   <#
    .SYNOPSIS
        Function that performs the Firewall check and returns the result to the uberAgent.
    .DESCRIPTION
        Function that performs the Firewall check and returns the result to the uberAgent.
    .NOTES
        The result will be converted to JSON. Each test returns a vlResultObject or vlErrorObject.
        Specific tests can be called by passing the test name as a parameter to the script args.
        Passing no parameters or -all to the script will run all tests.
    .LINK
        https://uberagent.com
    .OUTPUTS
        A list with vlResultObject | vlErrorObject [psobject] containing the test results
    .EXAMPLE
        Get-vlFirewallCheck
    #>

   $params = if ($global:args) { $global:args } else { "all" }
   $Output = @()

   if ($params.Contains("all") -or $params.Contains("FWState")) {
      $firewallEnabled = Get-vlIsFirewallEnabled
      $Output += [PSCustomObject]@{
         Name         = "FWState"
         DisplayName  = "Firewall status"
         Description  = "Checks if the firewall is enabled."
         Score        = $firewallEnabled.Score
         ResultData   = $firewallEnabled.Result
         RiskScore    = 100
         ErrorCode    = $firewallEnabled.ErrorCode
         ErrorMessage = $firewallEnabled.ErrorMessage
      }
   }

   if ($params.Contains("all") -or $params.Contains("FWPorts")) {
      $openPorts = Get-vlOpenFirewallPorts
      $Output += [PSCustomObject]@{
         Name         = "FWPorts"
         DisplayName  = "Open firewall ports"
         Description  = "Checks if there are open firewall ports and returns the list of open ports."
         Score        = $openPorts.Score
         ResultData   = $openPorts.Result
         RiskScore    = 70
         ErrorCode    = $openPorts.ErrorCode
         ErrorMessage = $openPorts.ErrorMessage
      }
   }

   return $output
}

Write-Output (Get-vlFirewallCheck | ConvertTo-Json -Compress)