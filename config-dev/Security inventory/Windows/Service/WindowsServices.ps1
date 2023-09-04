. $PSScriptRoot\..\Shared\Helper.ps1 -Force

function Get-vlServiceLocations {
   <#
   .SYNOPSIS
       Checks whether services are located outside common locations
   .DESCRIPTION
       Checks whether services are located outside common locations
   .LINK

   .NOTES

   .OUTPUTS
       A [psobject] containing services located outside common locations. Empty if nothing was found.
   .EXAMPLE
       Get-vlServiceLocations
   #>

   param (

   )

   process {
      $riskScore = 100

      try {
         $result = @()
         Get-vlRegSubkeys -Hive HKLM -Path 'SYSTEM\CurrentControlSet\Services' | Where-Object { $_.ImagePath } | ForEach-Object -process {
            $ImagePath = $PSItem.ImagePath
            $ServiceName = $PSItem.PSChildName
            if ($ImagePath -inotmatch '^(\\\?\?\\)?\\?SystemRoot.*$|^(system32|syswow64|servicing).*$|^(\\\?\?\\)?"?C:\\WINDOWS\\(system32|syswow64|servicing).*$|^(\\\?\?\\)?"?C:\\Program Files( \(x86\))?\\.*$|^(\\\?\?\\)?"?C:\\WINDOWS\\Microsoft\.NET\\.*$|^(\\\?\?\\)?"?C:\\ProgramData\\Microsoft\\Windows Defender\\.*$' -AND $ServiceName -inotmatch '^ehRecvr$|^ehSched$') {
               $result += [PSCustomObject]@{
                  Service   = $ServiceName
                  ImagePath = $ImagePath
               }
            }

         }

         if (-not $result) {
            # No services outside common locations found
            return New-vlResultObject -result $result -score 10 -riskScore $riskScore
         }
         else {
            # Services outside common location found
            return New-vlResultObject -result $result -score 1 -riskScore $riskScore
         }
      }
      catch {

         return New-vlErrorObject($_)
      }
      finally {

      }

   }

}

function Get-vlServiceDLLLocations {
   <#
    .SYNOPSIS
        Checks whether service.dll files are located outside common locations
    .DESCRIPTION
        Checks whether service.dll files are located outside common locations
    .LINK

    .NOTES

    .OUTPUTS
        A [psobject] containing services with service.dll files located outside common locations. Empty if nothing was found.
    .EXAMPLE
        Get-vlServiceDLLLocations
    #>

   param (

   )

   process {
      $riskScore = 90
      $result = @()

      try {
         $services = Get-ChildItem 'hklm:\SYSTEM\CurrentControlSet\Services'
      }
      catch {
         return New-vlErrorObject($_)
      }

      $services | ForEach-Object {
         try {
             $property = Get-ItemProperty -Path "$($_.PSPath)\Parameters" -ErrorAction Stop
             if ($property.ServiceDLL) {
               $ServiceDLL = $property.ServiceDLL
               $ServiceName = ($property.PSParentPath).split('\\')[-1]
               if ($ServiceDLL -inotmatch '^((\\\?\?\\)?%SystemRoot%|C:\\WINDOWS)\\System32\\.*' -AND $ServiceName -inotmatch '^AzureAttestService$|^WinDefend$|^WinHttpAutoProxySvc$') {

                  $result += [PSCustomObject]@{
                     Service    = $ServiceName
                     ServiceDLL = $ServiceDLL
                  }
               }
             }
         }
         catch [System.Management.Automation.ItemNotFoundException] {
            # This error happens if the registry key does not exist, which can happen in case of user services like CaptureService_* which are gone after logoff
            # If that happens, skip the service
         }
         catch {
            return New-vlErrorObject($_)
         }
     }

     if (-not $result) {
      # No service.dll file outside common locations found
      return New-vlResultObject -result $result -score 10 -riskScore $riskScore
     }
     else {
        # Service.dll file outside common location found
        return New-vlResultObject -result $result -score 1 -riskScore $riskScore
     }



   }

}


function Get-vlWindowsServicesCheck {
   <#
   .SYNOPSIS
       Function that performs the Windows services check and returns the result to the uberAgent.
   .DESCRIPTION
       Function that performs the Windows services check and returns the result to the uberAgent.
   .NOTES
       The result will be converted to JSON. Each test returns a vlResultObject or vlErrorObject.
       Specific tests can be called by passing the test name as a parameter to the script args.
       Passing no parameters or -all to the script will run all tests.
   .LINK
       https://uberagent.com
   .OUTPUTS
       A list with vlResultObject | vlErrorObject [psobject] containing the test results
   .EXAMPLE
       Get-vlWindowsServicesCheck
   #>

   $params = if ($global:args) { $global:args } else { "all" }
   $Output = @()

   if ($params.Contains("all") -or $params.Contains("ServiceLocations")) {
      $ServiceLocations = Get-vlServiceLocations
      $Output += [PSCustomObject]@{
         Name         = "Locations"
         DisplayName  = "Uncommon locations"
         Description  = "This test evaluates whether services are running in unusual or unexpected locations on the system. Unusual or unexpected locations in this case means outside of folders such as C:\Windows\System32 or C:\Program Files, which may indicate a potential security issue or a compromise."
         Score        = $ServiceLocations.Score
         ResultData   = $ServiceLocations.Result
         RiskScore    = $ServiceLocations.RiskScore
         ErrorCode    = $ServiceLocations.ErrorCode
         ErrorMessage = $ServiceLocations.ErrorMessage
      }
   }

   if ($params.Contains("all") -or $params.Contains("ServiceDLLLocations")) {
      $ServiceDLLLocations = Get-vlServiceDLLLocations
      $Output += [PSCustomObject]@{
         Name         = "Service.dll"
         DisplayName  = "Uncommon locations of service.dll"
         Description  = "This test scans the Windows registry for service DLL files and determines whether a DLL file is located outside the Windows system directory. DLL files are important components used by various services and applications of the Windows operating system. Malicious actors try to execute code and gain persistence by registering their malicious DLL files."
         Score        = $ServiceDLLLocations.Score
         ResultData   = $ServiceDLLLocations.Result
         RiskScore    = $ServiceDLLLocations.RiskScore
         ErrorCode    = $ServiceDLLLocations.ErrorCode
         ErrorMessage = $ServiceDLLLocations.ErrorMessage
      }
   }

   return $output
}

try {
   [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
}
catch {
   $OutputEncoding = [System.Text.Encoding]::UTF8
}


Write-Output (Get-vlWindowsServicesCheck | ConvertTo-Json -Compress)
