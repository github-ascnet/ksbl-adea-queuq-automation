$cSharpEnum = @"
        public enum EmployeeType {
                INTERNAL,
                EXTERNAL,
                GENERIC,
                SERVICE,
                MANAGED_SERVICE,
                WLAN_SERVICE,
                NONE
        }
"@
if (-not ([System.Management.Automation.PSTypeName]'EmployeeType').Type) { Add-Type -TypeDefinition $cSharpEnum }

$cSharpEnum = @"
        public enum ObjectState {
                ACTIVATE,
                INACTIVATE,
                HIDE,
                UNHIDE,
                UNKNOWN
        }
"@
if (-not ([System.Management.Automation.PSTypeName]'ObjectState').Type) { Add-Type -TypeDefinition $cSharpEnum }

function Test-EventLog([String]$EventlogName, [String]$EventlogSource) {

    if (![System.Diagnostics.Eventlog]::SourceExists($EventlogName)) { 

        New-EventLog $EventlogName -Source $EventlogSource
        Write-EventLog $EventlogName -Source $EventlogSource -EventId 1 -Message "Event log $global:logName created on local machine." -EntryType Information
    } 
}

function Update-DfsShareSettings ($samAccountName) {

    $home_drive = $null
    $home_drive = Get-HomeDrive
                                                   
    if ($null -ne $home_drive) {
        $dfs_target = Join-Path -Path $home_drive.unc_path -ChildPath $($samAccountName);
                    
        Set-UserHomeDirPermissions `
            -homeDirectoryPath $dfs_target `
            -userPrincipalName $($samAccountName) `
            -userPrincipalDomain (Get-ADDomain $env:USERDNSDOMAIN).NetBIOSName `

        $dfs_path = Join-Path -Path $homeDirectory -ChildPath $($samAccountName);
        $prms = 'link add "' + $dfs_path + '" "' + $dfs_target + '"';
        Run-DfsUtil -cmdLineArguments $prms 
    } 
                
    # Changed by S. Affolter 27.11.2016
    Set-UserApplicationDrivePermissions `
        -applicationDirectoryPath $applicationDirectoryShare `
        -userPrincipalName $($samAccountName) `
        -userPrincipalDomain $($env:USERDOMAIN) `

    # Changed by S. Affolter 27.11.2016
    Set-UserApplicationDrivePermissions `
        -applicationDirectoryPath $desktopDirectoryShare `
        -userPrincipalName $($samAccountName) `
        -userPrincipalDomain $($env:USERDOMAIN) `    
}

function Update-MailboxAttributes ($workingFileEntry) {

    try {
        $sourceMailbox = $null
        $sourceMailbox = Get-Mailbox $($workingFileEntry.TargetAdObjectName) -DomainController $dc -ErrorAction SilentlyContinue
    }
    catch {
([Exception])
        if ($_.Exception.InnerException) { $msg = $($_.Exception.InnerException.Message) } else { $msg = $($_.Exception.Message) }  	
        Write-EventLog $global:logName -Source $global:logSourceName -EventId 6000 -Message "Error getting Mailbox for User $($workingFileEntry.TargetAdObjectName) from Exchange: $msg " -EntryType Error                        
    }

    if (-not [string]::IsNullOrEmpty($sourceMailbox)) {
        if ($($workingFileEntry.TargetAdObjectName).StartsWith("us") -eq $true) {
            try {
                Set-CASMailbox -Identity $sourceMailbox.Identity -OWAEnabled $true -ActiveSyncEnabled $true
            }
            catch [System.Exception] {
                if ($_.Exception.InnerException) { $msg = $($_.Exception.InnerException.Message) } else { $msg = $($_.Exception.Message) }  
                Write-EventLog $global:logName -Source $global:logSourceName -EventId 6000 -Message "Failed enabling OWA/EAS for Exchange Mailbox $($workingFileEntry.TargetAdObjectName). Error: $msg" -EntryType Error                  
            }
        } 

        try {
            Set-Mailbox -Identity $sourceMailbox.Identity -HiddenFromAddressListsEnabled $false    
        }
        catch [System.Exception] {
            if ($_.Exception.InnerException) { $msg = $($_.Exception.InnerException.Message) } else { $msg = $($_.Exception.Message) }  
            Write-EventLog $global:logName -Source $global:logSourceName -EventId 6000 -Message "Failed disabling HiddenFromAddressListsEnabled for Exchange Mailbox $($workingFileEntry.TargetAdObjectName). Error: $msg" -EntryType Error                  
        }

        try {
            Set-MailboxJunkEmailConfiguration $sourceMailbox.Identity -Enabled $false
        }
        catch [System.Exception] {
            if ($_.Exception.InnerException) { $msg = $($_.Exception.InnerException.Message) } else { $msg = $($_.Exception.Message) }  
            Write-EventLog $global:logName -Source $global:logSourceName -EventId 6000 -Message "Failed disabling MailboxJunkEmailConfiguration for Exchange Mailbox $($workingFileEntry.TargetAdObjectName). Error: $msg" -EntryType Error                  
        }
    }
}

function Update-AdAttributes ($workingFileEntry) {

    try {
        Set-ADUser $($workingFileEntry.TargetAdObjectName) -Enabled $true -Server $dc
    }
    catch {
([Exception])
        if ($_.Exception.InnerException) { $msg = $($_.Exception.InnerException.Message) } else { $msg = $($_.Exception.Message) }  	
        Write-EventLog $global:logName -Source $global:logSourceName -EventId 6000 -Message "Error enabilng User $($workingFileEntry.TargetAdObjectName): $msg " -EntryType Error                  
    }

    if (-not [string]::IsNullOrEmpty($workingFileEntry.TargetUserAdDisplayname)) {
        try {
            #$displayName = Replace-IllegalChars -stringToConvert $($workingFileEntry.TargetUserAdDisplayname)
            Set-ADUser $($workingFileEntry.TargetAdObjectName) -DisplayName $($workingFileEntry.TargetUserAdDisplayname)
        }
        catch {
    ([Exception])
            if ($_.Exception.InnerException) { $msg = $($_.Exception.InnerException.Message) } else { $msg = $($_.Exception.Message) }  	
            Write-EventLog $global:logName -Source $global:logSourceName -EventId 6000 -Message "Error setting Attribute DisplayName for User $($workingFileEntry.TargetAdObjectName): $msg " -EntryType Error                  
        }
    }    

    if ($($workingFileEntry.TargetUserAdEmployeeType) -ne "S" -and $($workingFileEntry.TargetUserAdEmployeeType) -ne "A") {
        try {
            Set-ADUser $($workingFileEntry.TargetAdObjectName) -HomeDirectory "$homeDirectory\$($workingFileEntry.TargetAdObjectName)" 
        }
        catch {
    ([Exception])
            if ($_.Exception.InnerException) { $msg = $($_.Exception.InnerException.Message) } else { $msg = $($_.Exception.Message) }  	
            Write-EventLog $global:logName -Source $global:logSourceName -EventId 6000 -Message "Error setting Attribute HomeDirectory for User $($workingFileEntry.TargetAdObjectName): $msg " -EntryType Error                  
        }

        try {
            Set-ADUser $($workingFileEntry.TargetAdObjectName) -HomeDrive $global:homeDirectoryDrive
        }
        catch {
    ([Exception])
            if ($_.Exception.InnerException) { $msg = $($_.Exception.InnerException.Message) } else { $msg = $($_.Exception.Message) }  	
            Write-EventLog $global:logName -Source $global:logSourceName -EventId 6000 -Message "Error setting Attribute HomeDrive for User $($workingFileEntry.TargetAdObjectName): $msg " -EntryType Error                  
        }
    }

    try {
        Set-ADUser $($workingFileEntry.TargetAdObjectName) -StreetAddress $streetAddress -PostalCode $zipCode -City $city -State $state -Country $country -Company $company
    }
    catch {
([Exception])
        if ($_.Exception.InnerException) { $msg = $($_.Exception.InnerException.Message) } else { $msg = $($_.Exception.Message) }  	
        Write-EventLog $global:logName -Source $global:logSourceName -EventId 6000 -Message "Error setting Attribute StreetAddress for User $($workingFileEntry.TargetAdObjectName): $msg " -EntryType Error                  
    }

    if (-not [string]::IsNullOrEmpty($workingFileEntry.TargetUserAdDepartment)) {
        try {
            Set-ADUser $($workingFileEntry.TargetAdObjectName) -Department $($workingFileEntry.TargetUserAdDepartment)
        }
        catch {
([Exception])
            if ($_.Exception.InnerException) { $msg = $($_.Exception.InnerException.Message) } else { $msg = $($_.Exception.Message) }  	
            Write-EventLog $global:logName -Source $global:logSourceName -EventId 6000 -Message "Error setting Attribute Department for User $($workingFileEntry.TargetAdObjectName): $msg " -EntryType Error                  
        }
    }

    if ($($workingFileEntry.TargetUserAdEmployeeType) -ne "S" -and $($workingFileEntry.TargetUserAdEmployeeType) -ne "A") {
        if (-not [string]::IsNullOrEmpty($workingFileEntry.TargetUserAdEmployeeId)) {
            try {
                Set-ADUser $($workingFileEntry.TargetAdObjectName) -EmployeeID $($workingFileEntry.TargetUserAdEmployeeId)
            }
            catch {
    ([Exception])
                if ($_.Exception.InnerException) { $msg = $($_.Exception.InnerException.Message) } else { $msg = $($_.Exception.Message) }  	
                Write-EventLog $global:logName -Source $global:logSourceName -EventId 6000 -Message "Error setting Attribute EmployeeID for User $($workingFileEntry.TargetAdObjectName): $msg " -EntryType Error                  
            }
        }
    }

    if (-not [string]::IsNullOrEmpty($workingFileEntry.TargetUserAdEmployeeType)) {
        try {
            Set-ADUser $($workingFileEntry.TargetAdObjectName) -replace @{"employeeType" = $($workingFileEntry.TargetUserAdEmployeeType) }
        }
        catch {
([Exception])
            if ($_.Exception.InnerException) { $msg = $($_.Exception.InnerException.Message) } else { $msg = $($_.Exception.Message) }  	
            Write-EventLog $global:logName -Source $global:logSourceName -EventId 6000 -Message "Error setting Attribute EmployeeType for User $($workingFileEntry.TargetAdObjectName): $msg " -EntryType Error                  
        }
    }
    
    if ($($workingFileEntry.TargetUserAdEmployeeType) -ne "S" -and $($workingFileEntry.TargetUserAdEmployeeType) -ne "A") {
        if (-not [string]::IsNullOrEmpty($($workingFileEntry.TargetUserBirtdayDate))) {
            try {
                Set-ADUser $($workingFileEntry.TargetAdObjectName) -add @{"ExtensionAttribute14" = $($workingFileEntry.TargetUserBirtdayDate) }
            }
            catch {
    ([Exception])
                if ($_.Exception.InnerException) { $msg = $($_.Exception.InnerException.Message) } else { $msg = $($_.Exception.Message) }  	
                Write-EventLog $global:logName -Source $global:logSourceName -EventId 6000 -Message "Error setting Attribute ExtensionAttribute14 for User $($workingFileEntry.TargetAdObjectName): $msg " -EntryType Error                  
            }
        }
    }

    if (-not [string]::IsNullOrEmpty($workingFileEntry.TargetExternalCompany)) {
        try {
            Set-ADUser $($workingFileEntry.TargetAdObjectName) -Company  $($workingFileEntry.TargetExternalCompany)
        }
        catch {
([Exception])
            if ($_.Exception.InnerException) { $msg = $($_.Exception.InnerException.Message) } else { $msg = $($_.Exception.Message) }  	
            Write-EventLog $global:logName -Source $global:logSourceName -EventId 6000 -Message "Error setting Attribute Company for User $($workingFileEntry.TargetAdObjectName): $msg " -EntryType Error                  
        }
    }

    try {
        Set-ADUser $($workingFileEntry.TargetAdObjectName) -replace @{"kisAccountName" = $($workingFileEntry.TargetAdObjectName) }
    }
    catch {
([Exception])
        if ($_.Exception.InnerException) { $msg = $($_.Exception.InnerException.Message) } else { $msg = $($_.Exception.Message) }  	
        Write-EventLog $global:logName -Source $global:logSourceName -EventId 6000 -Message "Error setting Attribute kisAccountName for User $($workingFileEntry.TargetAdObjectName): $msg " -EntryType Error                  
    }

    if ($($workingFileEntry.TargetUserAdEmployeeType) -eq "P" -or $($workingFileEntry.TargetUserAdEmployeeType) -eq "E" -or $($workingFileEntry.TargetUserAdEmployeeType) -eq "HNP") {
        try {
            Set-ADUser $($workingFileEntry.TargetAdObjectName) -UserPrincipalName "$($workingFileEntry.TargetAdObjectName)@$($global:upnDomainName)"
        } catch {([Exception])
            if ($_.Exception.InnerException) { $msg = $($_.Exception.InnerException.Message) } else { $msg = $($_.Exception.Message) }  	
            Write-EventLog $global:logName -Source $global:logSourceName -EventId 6000 -Message "Error setting Attribute UserPrincipalName for User $($workingFileEntry.TargetAdObjectName): $msg " -EntryType Error                  
        }
    }

    if ($($workingFileEntry.TargetUserAdEmployeeType) -ne "S" -and $($workingFileEntry.TargetUserAdEmployeeType) -ne "A") {

        if ($null -eq $((Get-ADUser $($workingFileEntry.TargetAdObjectName) -Properties *).memberof | Where-Object { $_ -like "cn=gg-onesign*" })) {
            try {
                Add-ADGroupMember -Identity "GG-OneSign" -Members $($workingFileEntry.TargetAdObjectName) -Server $dc
            }
            catch { ([Exception])
                if ($_.Exception.InnerException) { $msg = $($_.Exception.InnerException.Message) } else { $msg = $($_.Exception.Message) }  
                Write-EventLog $global:logName -Source $global:logSourceName -EventId 6000 -Message "Error adding User $($workingFileEntry.TargetAdObjectName) into group GG-OneSign: $msg " -EntryType Error                  
            }
        }    

        if ($null -eq $((Get-ADUser $($workingFileEntry.TargetAdObjectName) -Properties *).memberof | Where-Object { $_ -like "cn=GG-VDI8-Produktiv-WIN10*" })) {
            try {
                Add-ADGroupMember -Identity "GG-VDI8-Produktiv-WIN10" -Members $($workingFileEntry.TargetAdObjectName) -Server $dc
            }
            catch { ([Exception])
                if ($_.Exception.InnerException) { $msg = $($_.Exception.InnerException.Message) } else { $msg = $($_.Exception.Message) }  
                Write-EventLog $global:logName -Source $global:logSourceName -EventId 6000 -Message "Error adding User $($workingFileEntry.TargetAdObjectName) into group GG-VDI8-Produktiv-WIN10: $msg " -EntryType Error                  
            }
        }    
    }
}

<#
function Manage-VdiPodGroupMemberships ($userLocation, $migratedForestUserObject) {

    #if ($env:USERNAME -eq "adm00") {

        $vdiPodSearchString = "pod-$($userLocation)"

        $vdiPodGroups = $null
        $vdiPodGroups = Get-ADGroup -LDAPFilter "(extensionAttribute2=*$($vdiPodSearchString.Trim())*)" -Server $dc

        if ($vdiPodGroups -ne $null) {
                            
            $lowestMemberCount = 0
            $lowestMemberGroup = $null
            foreach ($vdiPodGroup in $vdiPodGroups) {
                                
                $vdiPodGroupMemberCount = (Get-ADGroupMember $vdiPodGroup -Server $dc).count
                            
                if ($lowestMemberCount -gt 0) {
                    if ($vdiPodGroupMemberCount -lt $lowestMemberCount) {
                        $lowestMemberCount = $vdiPodGroupMemberCount
                        $lowestMemberGroup = $vdiPodGroup 
                    }
                } else {
                    $lowestMemberCount = $vdiPodGroupMemberCount
                    $lowestMemberGroup = $vdiPodGroup 
                }
            }
        
            if ($lowestMemberGroup -ne $null) {

                $existingPodGroupMemberships = $null
                $existingPodGroupMemberships = $($migratedForestUserObject.MemberOf) -match "-pod"
                if ($existingPodGroupMemberships -ne $null) {                                        
                    foreach ($vdiPodGroupToRemove in $existingPodGroupMemberships) {
                        try {
                            Remove-ADGroupMember $vdiPodGroupToRemove -Member $migratedForestUserObject -Server $dc -Confirm:$false
                        } catch {([Exception])
                            if ($_.Exception.InnerException) { $msg = $($_.Exception.InnerException.Message) } else { $msg = $($_.Exception.Message) }  
                            Write-Host "Failed removing user account $($migratedForestUserObject.distinguishedName) from group $vdiPodGroupToRemove. Error: $msg" -ForegroundColor Red  
                            Write-EventLog $global:logName -Source $global:logSourceName `
                                            -EventId 371 `
                                            -Message "Failed removing user account $($migratedForestUserObject.distinguishedName) from group $vdiPodGroupToRemove. Error: $msg" `
                                            -EntryType Error
                        }
                    }
                } 

                try {
                    Add-ADGroupMember $lowestMemberGroup -Member $migratedForestUserObject -Server $dc
                } catch {([Exception])
                    if ($_.Exception.InnerException) { $msg = $($_.Exception.InnerException.Message) } else { $msg = $($_.Exception.Message) }  
                    Write-Host "Failed adding user account $($migratedForestUserObject.distinguishedName) into group $($lowestMemberGroup.distinguishedName). Error: $msg" -ForegroundColor Red  
                }
            } else {

                Write-Host "Unable to add user account $($migratedForestUserObject.distinguishedName) into a VDI PoD group. Failed getting the lowest group member count." -ForegroundColor Yellow  
            }

        } else {

            Write-Host "Unable to add user account $($migratedForestUserObject.distinguishedName) into a VDI PoD group. Failed getting any VDI PoD groups out of Active Directory." -ForegroundColor Yellow  
        } 
    #}    
}
#>

function Get-HomeDrive() {
  <#
      .SYNOPSIS
      Gets the HomeDrive with the least utilization
      .DESCRIPTION
      Reads the available HomeDrives from all the Home-Servers
      and gets the HomeDrive with the least utilization.
      Function brought in and maintained by Michael Hochstrasser
      Modified on:   15.08.2024
      Version:       1.1
  #>

  #------------------------------------
  $fs_server = @(
    'sv01005.ksbl.local'
    'sv01006.ksbl.local'
  )
  #------------------------------------

  $home_targets = @()

  $fs_shares = @{}
  foreach($server in $fs_server)
  {
    $fs_shares += @{ $server = @() }
    $wmi_params = @{
      Class  = 'Win32_Share'
      Filter = "Name like 'home[_][a-z]$'"
      ComputerName = $server
    }
    Get-WmiObject @wmi_params | ForEach-Object {
      $fs_shares[$server] += @{
        name = $_.Name
        path = $_.Path
      }
    }
  }

  foreach($server in $fs_shares.Keys)
  {
    foreach($share in $fs_shares[$server])
    {
      $wmi_params = @{
        Class  = 'Win32_LogicalDisk'
        Filter = "DeviceID='{0}'" -f $share.path.Substring(0, 2)
        ComputerName = $server
      }  
      $disc = Get-WmiObject @wmi_params
      $share.unc = '\\{0}\{1}' -f $server, $share.name
      if(Test-Path -Path $share.unc)
      {
        $dir_count = (Get-ChildItem -Path $share.unc).Count
      }
      else
      {
        $dir_count = 1
      }
      #$disc_size = [math]::Round($disc.Size /1024/1024/1024);
      #$disc_size = $disc.Size;
      #$free_space = [math]::Round($disc.FreeSpace /1024/1024/1024);
      $free_space = $disc.FreeSpace
      $dir_points = ($dir_count * 1024 * 1024 * 1024) * 10 # 10 GB for each folder
      $home_targets += @{
        'server' = $server
        'path' = $share.path
        'unc_path' = $share.unc
        'name' = $share.name
        #'disc_size' = $disc_size;
        'free_space' = $free_space/1GB
        'dir_count' = $dir_count
        'Points' = $free_space - $dir_points
      }
    }
  }

  $sort1 = @{Expression='Points'; Descending=$true };
  $sort2 = @{Expression='name'; Ascending=$true };

  #$home_targets | ForEach-Object { [PSCustomObject]$_ } | Sort-Object $sort1, $sort2 | Out-GridView

  return $home_targets | ForEach-Object { [PSCustomObject]$_ } | Sort-Object $sort1, $sort2 | Select-Object -First 1
}

function Run-DfsUtil($cmdLineArguments) {
    <#
 Function brought in and maintained by Michael Hochstrasser on 13.08.2015
#>

    $ps = new-object System.Diagnostics.Process
    $ps.StartInfo.Filename = 'd:\iam\dfsutil.exe' 
    $ps.StartInfo.Arguments = $cmdLineArguments
    $ps.StartInfo.RedirectStandardOutput = $True
    $ps.StartInfo.RedirectStandardError = $True
    $ps.StartInfo.UseShellExecute = $false
    $ps.start() | Out-Null
    $ps.WaitForExit() | Out-Null

    [string]$stdout = $ps.StandardOutput.ReadToEnd();
    [string]$stderr = $ps.StandardError.ReadToEnd();
    [int]$exitcode = $ps.ExitCode

    $ps.Dispose()

    if ($exitcode -ne 0) {
        Write-Host "Fehler bei Aufruf von DFSUtil: $stdout $stderr"
        Write-EventLog $global:logName -Source $global:logSourceName -EventId 6000 -Message "DFS-Util Return Message: $stdout $stderr " -EntryType Error                  
        $false
    }
    else { 
        $true 
    }
}

function Change-MailboxFeaturesAndState {
    [CmdletBinding()]
    [OutputType([bool])]
    Param
    (
        [Parameter(Mandatory = $true,
            ValueFromPipelineByPropertyName = $true,
            Position = 0)]
        $mailboxName,
        [Parameter(Mandatory = $true,
            ValueFromPipelineByPropertyName = $true,
            Position = 1)]
        $objectState
        
    )

    if ((Get-Mailbox $mailboxName).HiddenFromAddressListsEnabled -eq $true -and $objectState -eq [ObjectState]::UNHIDE ) {
        try {
            Set-CASMailbox -Identity $mailboxName -OWAEnabled $true -ActiveSyncEnabled $true
            Write-Host "Successfully enabled OWA and EAS for Exchange Mailbox $($mailboxName)" -ForegroundColor Green
        }
        catch [System.Exception] {
            if ($_.Exception.InnerException) { $msg = $($_.Exception.InnerException.Message) } else { $msg = $($_.Exception.Message) }  
            Write-EventLog $global:logName -Source $global:logSourceName -EventId 6000 -Message "Failed enabling OWA and EAS for Exchange Mailbox $($mailboxName). Error: $msg" -EntryType Error                  
            Write-Host "Failed enabling OWA and EAS for Exchange Mailbox $($mailboxName). Error: $msg" -ForegroundColor Red
        }        

        try {
            Set-Mailbox $($mailboxName) -HiddenFromAddressListsEnabled $false
            Write-Host "Successfully enabled Addressbook view for Exchange Mailbox $($mailboxName)" -ForegroundColor Green
        }
        catch [System.Exception] {
            if ($_.Exception.InnerException) { $msg = $($_.Exception.InnerException.Message) } else { $msg = $($_.Exception.Message) }  
            Write-EventLog $global:logName -Source $global:logSourceName -EventId 6000 -Message "Failed enabling Addressbook view for Exchange Mailbox $($mailboxName). Error: $msg" -EntryType Error                  
            Write-Host "Failed enabling Addressbook view for Exchange Mailbox $($mailboxName). Error: $msg" -ForegroundColor Red
        }
    }

    if ((Get-Mailbox $mailboxName).HiddenFromAddressListsEnabled -eq $false -and $objectState -eq [ObjectState]::HIDE ) {
        try {
            Set-CASMailbox -Identity $mailboxName -OWAEnabled $false -ActiveSyncEnabled $false
            Write-Host "Successfully disabled OWA and EAS for Exchange Mailbox $($mailboxName)" -ForegroundColor Green
        }
        catch [System.Exception] {
            if ($_.Exception.InnerException) { $msg = $($_.Exception.InnerException.Message) } else { $msg = $($_.Exception.Message) }  
            Write-EventLog $global:logName -Source $global:logSourceName -EventId 6000 -Message "Failed disabling OWA and EAS for Exchange Mailbox $($mailboxName). Error: $msg" -EntryType Error                  
            Write-Host "Failed disabling OWA and EAS for Exchange Mailbox $($mailboxName). Error: $msg" -ForegroundColor Red
        }        

        try {
            Set-Mailbox $($mailboxName) -HiddenFromAddressListsEnabled $true
            Write-Host "Successfully disabled Addressbook view for Exchange Mailbox $($mailboxName)" -ForegroundColor Green
        }
        catch [System.Exception] {
            if ($_.Exception.InnerException) { $msg = $($_.Exception.InnerException.Message) } else { $msg = $($_.Exception.Message) }  
            Write-EventLog $global:logName -Source $global:logSourceName -EventId 6000 -Message "Failed disabling Addressbook view for Exchange Mailbox $($mailboxName). Error: $msg" -EntryType Error                  
            Write-Host "Failed disabling Addressbook view for Exchange Mailbox $($mailboxName). Error: $msg" -ForegroundColor Red
        }
    }
}

# Changed by S. Affolter 27.11.2016
function Set-UserApplicationDrivePermissions {

    [CmdletBinding()]
    [OutputType([int])]
    Param
    (
        [string]$applicationDirectoryPath,
        [string]$userPrincipalName,
        [string]$userPrincipalDomain
    )

    try {
        
        $applicationDirectoryPath = "$applicationDirectoryPath\$userPrincipalName"
        if ((Test-Path $applicationDirectoryPath) -eq $false) {

            New-Item -ItemType directory -Path $applicationDirectoryPath
        }

        $acls = Get-Acl $applicationDirectoryPath
        $user = "$userPrincipalDomain\$userPrincipalName"

        Foreach ($acl in $acls) { 
            $folder = (convert-path $acl.pspath)   
            Foreach ($access in $acl.access) { 
                Foreach ($value in $access.identityReference.Value) { 
                    if ($value -ne "BUILTIN\Administrators") { 
                        $acl.RemoveAccessRule($access) | Out-Null 
                    } 
                }  
            } 
            Set-Acl -path $folder -aclObject $acl 
        } 
        
        $acl = Get-Acl $applicationDirectoryPath
        $acl.SetAccessRuleProtection($True, $False)

        $rule = New-Object System.Security.AccessControl.FileSystemAccessRule("Administrators", "FullControl", "ContainerInherit, ObjectInherit", "None", "Allow")
        $acl.AddAccessRule($rule)
        
        $rule = New-Object System.Security.AccessControl.FileSystemAccessRule("$userPrincipalDomain\$userPrincipalName", "Modify", "ContainerInherit, ObjectInherit", "None", "Allow")
        $acl.AddAccessRule($rule)
        Set-Acl $applicationDirectoryPath $acl
                        
        Write-Host "Successfully set ACL on application directory $applicationDirectoryPath for user account $userPrincipalDomain\$userPrincipalName" -ForegroundColor Green
        Write-EventLog $global:logName -Source $global:logSourceName -EventId 650 -Message "Successfully set ACL on application directory $applicationDirectoryPath for user account $userPrincipalDomain\$userPrincipalName" -EntryType Information

    }
    catch [System.Exception] {
        if ($_.Exception.InnerException) { $msg = $($_.Exception.InnerException.Message) } else { $msg = $($_.Exception.Message) }  
        Write-Host "Failed setting ACL on application directory $applicationDirectoryPath for user account $userPrincipalDomain\$userPrincipalName. Error: $msg" -ForegroundColor Red
        Write-EventLog $global:logName -Source $global:logSourceName -EventId 6000 -Message "Failed setting ACL on application directory $applicationDirectoryPath for user account $userPrincipalDomain\$userPrincipalName. Error: $msg" -EntryType Error
    }
}

function Set-UserHomeDirPermissions {
    [CmdletBinding()]
    [OutputType([int])]
    Param
    (
        [string]$homeDirectoryPath,
        [string]$userPrincipalName,
        [string]$userPrincipalDomain
    )

    try {
        
        if ((test-path $homeDirectoryPath) -eq $false) {

            New-Item -ItemType directory -Path "$homeDirectoryPath\SYSTEM_FOLDER"
            New-Item -ItemType directory -Path "$homeDirectoryPath\SYSTEM_FOLDER\Vorlagen"
            New-Item -ItemType directory -Path "$homeDirectoryPath\SYSTEM_FOLDER\Outlook"
            New-Item -ItemType directory -Path "$homeDirectoryPath\SYSTEM_FOLDER\Signatures"
            New-Item -ItemType directory -Path "$homeDirectoryPath\SYSTEM_FOLDER\Favoriten"                        
        }

        $acls = Get-Acl $homeDirectoryPath
        $user = "$userPrincipalDomain\$userPrincipalName"

        Foreach ($acl in $acls) { 
            $folder = (convert-path $acl.pspath)   
            Foreach ($access in $acl.access) { 
                Foreach ($value in $access.identityReference.Value) { 
                    if ($value -eq $user) { 
                        $acl.RemoveAccessRule($access) | Out-Null 
                    } 
                }  
            } 
            Set-Acl -path $folder -aclObject $acl 
            $i++ 
        } 
        
        $acl = Get-Acl $homeDirectoryPath
        $acl.SetAccessRuleProtection($True, $False)

        $rule = New-Object System.Security.AccessControl.FileSystemAccessRule("Administrators", "FullControl", "ContainerInherit, ObjectInherit", "None", "Allow")
        $acl.AddAccessRule($rule)
        
        $rule = New-Object System.Security.AccessControl.FileSystemAccessRule("$userPrincipalDomain\$userPrincipalName", "Modify", "ContainerInherit, ObjectInherit", "None", "Allow")
        $acl.AddAccessRule($rule)
        Set-Acl $homeDirectoryPath $acl
        #Get-Acl $homeDirectoryPath  | Format-List
                        
        Write-Host "Successfully set ACL on home directory $homeDirectoryPath for user account $userPrincipalDomain\$userPrincipalName" -ForegroundColor Green
        #cacls $homeDirectoryPath

    }
    catch [System.Exception] {
        if ($_.Exception.InnerException) { $msg = $($_.Exception.InnerException.Message) } else { $msg = $($_.Exception.Message) }  

        Write-Host "Failed setting ACL on home directory $homeDirectoryPath for user account $userPrincipalDomain\$userPrincipalName. Error: $msg" -ForegroundColor Red
        Write-EventLog $global:logName -Source $global:logSourceName `
            -EventId 6000 `
            -entryType Error `
            -Message  "Failed setting ACL on home directory $homeDirectoryPath for user account $userPrincipalDomain\$userPrincipalName. Error: $msg"                        
    }        

}

function Validate-EMailAddress {
    [CmdletBinding()]
    [OutputType([string])]
    Param
    (
        [Parameter(Mandatory = $true,
            ValueFromPipelineByPropertyName = $true,
            Position = 0)]
        $mailDomain,
        [Parameter(Mandatory = $true,
            ValueFromPipelineByPropertyName = $true,
            Position = 1)]
        $givenName,
        [Parameter(Mandatory = $true,
            ValueFromPipelineByPropertyName = $true,
            Position = 2)]
        $surName

    )

    $mailAddress = "$givenName.$surName@$mailDomain"                        

    try {

        if (((Get-ADObject -LDAPFilter "(|(proxyAddresses=smtp:$mailAddress)(mail=$mailAddress))" -Properties mail).mail).count -gt 0) {
                                
            $i = 0
            $mailAddressIsValid = $false
            $AnzahlGefunden = 0

            while ($mailAddressIsValid -eq $false) {
                $i++
                $mailAddress = "$givenName.$surName.$i@$mailDomain"                        
                try {
                    if (((Get-ADObject -LDAPFilter "(|(proxyAddresses=smtp:$mailAddress)(mail=$mailAddress))" -Properties mail).mail).count -eq 0) {
                        $mailAddressIsValid = $true                                    
                    }
                }
                catch {
([Exception])
                    if ($_.Exception.InnerException) { $msg = $($_.Exception.InnerException.Message) } else { $msg = $($_.Exception.Message) }  	
                    Write-EventLog $global:logName -Source $global:logSourceName -EventId 6000 -Message "Error retrieving unique Mail Address $($mailAddress) for multiple times: $msg " -EntryType Error                  
                }

            }
            return $mailAddress
        }
        else {
            return $mailAddress
        }

    }
    catch {
([Exception])
        if ($_.Exception.InnerException) { $msg = $($_.Exception.InnerException.Message) } else { $msg = $($_.Exception.Message) }  	
        Write-EventLog $global:logName -Source $global:logSourceName -EventId 6000 -Message "Error retrieving unique Mail Address $($mailAddress): $msg " -EntryType Error                  
    }

}

function Replace-IllegalChars {
    [CmdletBinding()]
    [OutputType([string])]
    Param
    (
        [Parameter(Mandatory = $true,
            ValueFromPipelineByPropertyName = $true,
            Position = 0)]
        $stringToConvert
    )

    $stringToConvert = $stringToConvert.Replace(".", "");
    $stringToConvert = $stringToConvert.Replace(" ", "-");
    $stringToConvert = $stringToConvert.Replace("'", "");
    $stringToConvert = $stringToConvert.Replace("_", "-");
    $stringToConvert = $stringToConvert.Replace("/", "-");
    $stringToConvert = $stringToConvert.Replace("\", "-");
    $stringToConvert = $stringToConvert.Replace("ä", "ae");
    $stringToConvert = $stringToConvert.Replace("Ä", "Ae");
    $stringToConvert = $stringToConvert.Replace("ö", "oe");
    $stringToConvert = $stringToConvert.Replace("Ög", "Oe");
    $stringToConvert = $stringToConvert.Replace("ü", "ue");
    $stringToConvert = $stringToConvert.Replace("Ü", "Ue");
    $stringToConvert = $stringToConvert.Replace("À", "A");
    $stringToConvert = $stringToConvert.Replace("Á", "A");
    $stringToConvert = $stringToConvert.Replace("Â", "A");
    $stringToConvert = $stringToConvert.Replace("Ã", "A");
    $stringToConvert = $stringToConvert.Replace("Ä", "A");
    $stringToConvert = $stringToConvert.Replace("Å", "A");
    $stringToConvert = $stringToConvert.Replace("Ç", "C");
    $stringToConvert = $stringToConvert.Replace("È", "E");
    $stringToConvert = $stringToConvert.Replace("É", "E");
    $stringToConvert = $stringToConvert.Replace("Ê", "E");
    $stringToConvert = $stringToConvert.Replace("Ë", "E");
    $stringToConvert = $stringToConvert.Replace("Ì", "I");
    $stringToConvert = $stringToConvert.Replace("Í", "I");
    $stringToConvert = $stringToConvert.Replace("Î", "I");
    $stringToConvert = $stringToConvert.Replace("Ï", "I");
    $stringToConvert = $stringToConvert.Replace("Ñ", "N");
    $stringToConvert = $stringToConvert.Replace("Ò", "O");
    $stringToConvert = $stringToConvert.Replace("Ó", "O");
    $stringToConvert = $stringToConvert.Replace("Ô", "O");
    $stringToConvert = $stringToConvert.Replace("Õ", "O");
    $stringToConvert = $stringToConvert.Replace("Ö", "O");
    $stringToConvert = $stringToConvert.Replace("Ù", "U");
    $stringToConvert = $stringToConvert.Replace("Ú", "U");
    $stringToConvert = $stringToConvert.Replace("Û", "U");
    $stringToConvert = $stringToConvert.Replace("Ü", "U");
    $stringToConvert = $stringToConvert.Replace("Ý", "Y");
    $stringToConvert = $stringToConvert.Replace("à", "a");
    $stringToConvert = $stringToConvert.Replace("á", "a");
    $stringToConvert = $stringToConvert.Replace("â", "a");
    $stringToConvert = $stringToConvert.Replace("ã", "a");
    $stringToConvert = $stringToConvert.Replace("ä", "a");
    $stringToConvert = $stringToConvert.Replace("å", "a");
    $stringToConvert = $stringToConvert.Replace("æ", "ae");
    $stringToConvert = $stringToConvert.Replace("ç", "c");
    $stringToConvert = $stringToConvert.Replace("è", "e");
    $stringToConvert = $stringToConvert.Replace("é", "e");
    $stringToConvert = $stringToConvert.Replace("ê", "e");
    $stringToConvert = $stringToConvert.Replace("ë", "e");
    $stringToConvert = $stringToConvert.Replace("ì", "i");
    $stringToConvert = $stringToConvert.Replace("í", "i");
    $stringToConvert = $stringToConvert.Replace("î", "i");
    $stringToConvert = $stringToConvert.Replace("ï", "i");
    $stringToConvert = $stringToConvert.Replace("Ð", "D");
    $stringToConvert = $stringToConvert.Replace("ß", "ss");
    $stringToConvert = $stringToConvert.Replace("ñ", "n");
    $stringToConvert = $stringToConvert.Replace("ò", "o");
    $stringToConvert = $stringToConvert.Replace("ó", "o");
    $stringToConvert = $stringToConvert.Replace("ô", "o");
    $stringToConvert = $stringToConvert.Replace("õ", "o");
    $stringToConvert = $stringToConvert.Replace("ö", "o");
    $stringToConvert = $stringToConvert.Replace("ù", "u");
    $stringToConvert = $stringToConvert.Replace("ú", "u");
    $stringToConvert = $stringToConvert.Replace("û", "u");
    $stringToConvert = $stringToConvert.Replace("ü", "u");
    $stringToConvert = $stringToConvert.Replace("ý", "y");
    $stringToConvert = $stringToConvert.Replace("ÿ", "y");

    return $stringToConvert
}

function Send-EMail {
    Param (
        [string]$smtpHost,
        [string]$mailFrom,
        [string]$mailTo,
        [string]$mailCc,
        [string]$mailSubject,
        [string]$mailBody,
        [String]$attachment
    )

    try {
        $mailMessage = New-Object System.Net.Mail.MailMessage($mailFrom, $mailTo, $mailSubject, $mailBody)
        $mailMessage.CC.Add($mailCc)
        $mailMessage.IsBodyHtml = $true

        <#if ($attachment -ne $null) {
            $SMTPattachment = New-Object System.Net.Mail.Attachment($attachment)
            $mailMessage.Attachments.Add($STMPattachment)
        }#>
        
        $SMTPClient = New-Object Net.Mail.SmtpClient($smtpHost, 25) 
        #$SMTPClient.EnableSsl = $true 
        $SMTPClient.Credentials = New-Object System.Net.NetworkCredential("ksbl\ServiceMailboxMove", "Basel1893"); 
        $SMTPClient.Send($mailMessage)
        
        Remove-Variable -Name SMTPClient
        #Remove-Variable -Name pwd

    }
    catch {
([Exception])
        if ($_.Exception.InnerException) { $msg = $($_.Exception.InnerException.Message) } else { $msg = $($_.Exception.Message) }  	
        Write-EventLog $global:logName -Source $global:logSourceName -EventId 300 -Message "Error sending Summary-Mail $($mailSubject): $msg " -EntryType Error                  
    }

} 

function Random-Password () {        
    $length = 10
    $punc = 46..46        
    $digits = 48..57        
    $letters = 65..90 + 97..122         
    $password = Get-Random -count $length -input ($punc + $digits + $letters) | ForEach-Object -begin { $aa = $null } -process { $aa += [char]$_ } -end { $aa }
    return $password
}

function Validate-IfisNumeric {    
    [CmdletBinding()]
    [OutputType([bool])]
    Param
    (
        [Parameter(Mandatory = $true,
            ValueFromPipelineByPropertyName = $true,
            Position = 0)]
        $var
    )    

    $var2 = 0    
    $isNum = [System.Int32]::TryParse($var, [ref]$var2)    
    return $isNum
}

function Get-NextAvailableSamAccountName {
    [CmdletBinding()]
    [OutputType([string])]
    Param
    (
        [Parameter(Mandatory = $true,
            ValueFromPipelineByPropertyName = $true,
            Position = 0)]
        $localForestDomainController,
        [Parameter(Mandatory = $true,
            ValueFromPipelineByPropertyName = $true,
            Position = 0)]
        $employeeType
    )    

    [int[]]$userIds = $null
    $newUserId = $null

    if ($employeeType -eq ([EmployeeType]::INTERNAL)) {
        [string[]]$samAccountNames = (((Get-ADUser -LDAPFilter "(|(samaccountname=us*)(samaccountname=h2ad*))" -Server $localForestDomainController).samaccountname -Replace "us", "") -Replace ("vdi", "") -Replace ("h2ad", ""))
    }
    else {
        [string[]]$samAccountNames = (((Get-ADUser -LDAPFilter "(samaccountname=ex0*)" -Server $localForestDomainController).samaccountname -Replace "ex", ""))       
    }
    
    foreach ($item in $samAccountNames) {
        if ($($item.Length) -gt 4) {
            if ((Validate-IfisNumeric $item) -eq $true) {
                $userIds += $item
            }
        }        
    }

    if ($employeeType -eq ([EmployeeType]::INTERNAL)) {

        $newUserId = "us$(($userIds | Sort-Object | select -Last 1) + 1)"

    }
    else {

        [int]$userId = ($userIds | Sort-Object | select -Last 1)

        if ($userId.ToString().length -eq 1) {
            $userId = "ex0000$($userId + 1)"        
        }
        elseif ($userId.ToString().length -eq 2) {
            $newUserId = "ex000$($userId + 1)"        
        }
        elseif ($userId.ToString().length -eq 3) {
            $newUserId = "ex00$($userId + 1)"        
        }
        elseif ($userId.ToString().length -eq 4) {
            $newUserId = "ex0$($userId + 1)"        
        }
        elseif ($userId.ToString().length -eq 5) {
            $newUserId = "ex$($userId + 1)"        
        }
    }

    return $newUserId   
   
}

function LdapSearchFilterForAccount($workingFileEntry) {

    if (-not [string]::IsNullOrEmpty($workingFileEntry.LdapSearchUserId)) {
        return "(&(sAMAccountType=805306368)(samaccountname=$($workingFileEntry.LdapSearchUserId)))"
    }

    if (-not [string]::IsNullOrEmpty($workingFileEntry.TargetUserAdEmployeeId)) {
        return "(&(sAMAccountType=805306368)(employeeid=$($workingFileEntry.TargetUserAdEmployeeId)))"
    }

    if ($($workingFileEntry.TargetUserAdEmployeeType) -eq "P") {
        
        if ([string]::IsNullOrEmpty($($workingFileEntry.TargetUserAdGivenname)) -eq $false -and [string]::IsNullOrEmpty($($workingFileEntry.TargetUserAdSurname)) -eq $false -and [string]::IsNullOrEmpty($($workingFileEntry.TargetUserBirtdayDate)) -eq $false) {

            $gn = Replace-IllegalChars -stringToConvert $($workingFileEntry.TargetUserAdGivenname)
            $sn = Replace-IllegalChars -stringToConvert $($workingFileEntry.TargetUserAdSurname)
            return "(&(sAMAccountType=805306368)(displayName=*$($sn)*$($gn)*)(extensionAttribute14=$($workingFileEntry.TargetUserBirtdayDate)))"
        }
        else {
            return $null
        }
    }

    if ($($workingFileEntry.TargetUserAdEmployeeType) -eq "E") {

        if ([string]::IsNullOrEmpty($($workingFileEntry.TargetAdObjectName)) -eq $false) {
            return "(&(sAMAccountType=805306368)(samaccountname=$($workingFileEntry.TargetAdObjectName))(employeeType=E))"
        } else {
            return $null
        }
    }

    if ($($workingFileEntry.TargetUserAdEmployeeType) -eq "A") {

        if (-not [string]::IsNullOrEmpty($($workingFileEntry.TargetUserAdEmployeeId))) {
            return "(&(sAMAccountType=805306368)(employeeid=$($workingFileEntry.TargetUserAdEmployeeId)))"
        } else {
            return $null
        }
    }

    if ($($workingFileEntry.TargetUserAdEmployeeType) -eq "HNP") {

        if ([string]::IsNullOrEmpty($($workingFileEntry.TargetUserAdGivenname)) -eq $false -and [string]::IsNullOrEmpty($($workingFileEntry.TargetUserAdSurname)) -eq $false) {

            $gn = Replace-IllegalChars -stringToConvert $($workingFileEntry.TargetUserAdGivenname)
            $sn = Replace-IllegalChars -stringToConvert $($workingFileEntry.TargetUserAdSurname)
            return "(&(sAMAccountType=805306368)(displayName=*$($sn)*$($gn)*)(employeeType=HNP))"
        }
        else {
            return $null
        }
    }

    if ($($workingFileEntry.TargetUserAdEmployeeType) -eq "S") {

        if ($global:ServiceAccountType -eq [EmployeeType]::MANAGED_SERVICE) {
            if ([string]::IsNullOrEmpty($($workingFileEntry.TargetAdObjectName)) -eq $false) {
                return "(&(sAMAccountType=805306368)(samaccountname=$($workingFileEntry.TargetAdObjectName)$)(employeeType=S))"
            }
            else {
                return $null
            }
        } else {
            if ([string]::IsNullOrEmpty($($workingFileEntry.TargetAdObjectName)) -eq $false) {
                return "(&(sAMAccountType=805306368)(samaccountname=$($workingFileEntry.TargetAdObjectName))(employeeType=S))"
            }
            else {
                return $null
            }
        }

    }

}

# Funktion für das Setzen von AD-Attributen mit Fehlerbehandlung
function Set-AdUserWithErrorHandling {
    param(
        [string]$userName,
        [string]$attribute,
        [string]$value,
        [string]$description = ""
    )
    try {
        Set-ADUser $userName -replace @{ $attribute = $value } -Description $description
    } catch {
        $msg = If ($_.Exception.InnerException) { $_.Exception.InnerException.Message } else { $_.Exception.Message }
        Write-EventLog $global:logName -Source $global:logSourceName -EventId 6000 -Message "Error setting $attribute for User $userName: $msg" -EntryType Error
    }
}

# Funktion zur Aktualisierung des Benutzer-Postfachs
function Update-Mailbox {
    param (
        [string]$userName,
        [string]$newEmail
    )
    try {
        $mailboxDatabase = $defaultMailboxDbs | Get-Random
        Enable-Mailbox -Identity $userName -Database $mailboxDatabase -PrimarySmtpAddress $newEmail -DisplayName $userName
    } catch {
        $msg = If ($_.Exception.InnerException) { $_.Exception.InnerException.Message } else { $_.Exception.Message }
        Write-EventLog $global:logName -Source $global:logSourceName -EventId 6000 -Message "Error enabling Mailbox for User $userName: $msg" -EntryType Error
    }
}

cls
Add-Type -AssemblyName System.Web

$ErrorActionPreference = "stop"

$smtpHost = "relay.ksbl.local"
$mailFrom = "informatik@ksbl.ch"
$mailCc = "ksbl.vl.iam-administrators@ksbl.ch"
#$mailCc = "sascha.affolter@ksbl.ch"

$jobsToProcess = $null
$workingPath = "D:\IAM\Queue"

$dfsNamespace = 'HomeDrives'

#$applicationDirectoryShare = "\\sv00213\Appdata$"
#$desktopDirectoryShare = "\\sv00213\desktop$"

$sendMailToCustomer = $false
$dbServer = "SV02037.ksbl.local"
$db = "KSBL_IAM"

$pshUser = "ksbl\ServiceIAMJobs10"
$pshSecret = "D:\iam\Secrets\serviceiamjobs10.sec"

$global:homeDirectory = "\\ksbl.local\HomeDrives"
$global:applicationDirectoryShare = "\\sv00213\Appdata$"
$global:desktopDirectoryShare = "\\sv00213\desktop$"
$global:homeDirectoryDrive = "Z:"
$global:userProfileDirectoryShare = @('\\sv00701\UserProfiles$', '\\sv00702\UserProfiles$')

$global:internalUserOu = "OU=Internal,OU=_Users,DC=ksbl,DC=local"
$global:externalUserOu = "OU=External,OU=_Users,DC=ksbl,DC=local"
$global:serviceUserOu = "OU=ServiceAccounts,OU=_Users,DC=ksbl,DC=local"
$global:managedServiceUserOu = "CN=Managed Service Accounts,DC=ksbl,DC=local"
$global:adminUserOu = "OU=Admins,OU=_Users,DC=ksbl,DC=local"

$global:logname = "KSBL Helpdesk GUI"
$global:logSourceName = "Process-PersonMailbox"
#[System.Diagnostics.EventLog]::CreateEventSource($global:logSourceName, $global:logname)

$global:principalsAllowedToRetrieveManagedPassword = "LG-ADS_GMSA_Domain_Servers"

$global:exchAdminGroupDn = "CN=Exchange Administrative Group (FYDIBOHF23SPDLT),CN=Administrative Groups,CN=KSBL,CN=Microsoft Exchange,CN=Services,$(([ADSI]”LDAP://rootdse”).ConfigurationNamingContext)"
$global:scheduledTaskName = "Hospis Sync to Active Directory"
$global:upnDomainName = "ksbl.ch"


try {
    $global:defaultMailboxDbs = $null
    $mailboxDbLdapFilter = "(&(objectClass=msExchPrivateMDB)(!(name=MAILDB-NODAG))(!name=maildb101)(!name=maildb102)(!name=maildb103)(!name=Mailbox Database*)(!name=MBXDB*))"
    $global:defaultMailboxDbs = (New-Object System.DirectoryServices.DirectorySearcher([ADSI]"LDAP://CN=Databases,$($global:exchAdminGroupDn)", $mailboxDbLdapFilter, @('name'))).FindAll() | % { $_.Path.Split(',')[0].Split('=')[1] } 
    #$global:defaultMailboxDbs = @("MAILDB05","MAILDB07","MAILDB06","MAILDB08","MAILDB09","MAILDB11","MAILDB13","MAILDB15","MAILDB10","MAILDB12","MAILDB14","MAILDB16")
} 
catch {
([Exception])
    if ($_.Exception.InnerException) { $msg = $($_.Exception.InnerException.Message) } else { $msg = $($_.Exception.Message) }  	
    Write-EventLog $global:logName -Source $global:logSourceName -EventId 400 -Message "Error retrieving Exchange Mailbox Databases from $($global:exchAdminGroupDn): $msg " -EntryType Error                  
    Exit
}

try {
    $dc = [System.DirectoryServices.ActiveDirectory.Domain]::GetCurrentDomain().RidRoleOwner.Name
} 
catch {
([Exception])
    if ($_.Exception.InnerException) { $msg = $($_.Exception.InnerException.Message) } else { $msg = $($_.Exception.Message) }  	
    Write-EventLog $global:logName -Source $global:logSourceName -EventId 400 -Message "Error retrieving RidRoleOwner Domain-Controller from Active-Directory: $msg " -EntryType Error                  
    Exit
}

try {
    $primaryUserDomain = [System.DirectoryServices.ActiveDirectory.Domain]::GetCurrentDomain().Name
} 
catch {
([Exception])
    if ($_.Exception.InnerException) { $msg = $($_.Exception.InnerException.Message) } else { $msg = $($_.Exception.Message) }  	
    Write-EventLog $global:logName -Source $global:logSourceName -EventId 400 -Message "Error retrieving primary User Domain from Active-Directory: $msg " -EntryType Error                  
    Exit
}

try {
    #$primaryMailDomain = (([ADSI]"LDAP://CN=Default Policy,CN=Recipient Policies,CN=KSBL,CN=Microsoft Exchange,CN=Services,$(([ADSI]”LDAP://rootdse”).ConfigurationNamingContext)").gatewayProxy | Where-Object { [regex]::IsMatch($_, '^SMTP:') }).split('@')[1]
	$primaryMailDomain = "ksbl.ch"
} 
catch {
([Exception])
    if ($_.Exception.InnerException) { $msg = $($_.Exception.InnerException.Message) } else { $msg = $($_.Exception.Message) }  	
    Write-EventLog $global:logName -Source $global:logSourceName -EventId 400 -Message "Error retrieving primary Mail Domain  from Active-Directory: $msg " -EntryType Error                  
    Exit
}

try {
    if ($null -eq (Get-PSSession | Where-Object { $_.State -like "Opened" -and $_.Availability -like "Available" })) {
        $cred = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $pshUser , (Get-Content $pshSecret | ConvertTo-SecureString) 
        $PSSession = new-pssession –configurationname Microsoft.Exchange –connectionuri http://sv00516.ksbl.local/PowerShell –credential $Cred -Authentication Kerberos 
        Import-PSSession $PSSession -AllowClobber
    }
}
catch {
([Management.Automation.Remoting.PSRemotingTransportException], [Exception])
    if ($_.Exception.InnerException) { $msg = $($_.Exception.InnerException.Message) } else { $msg = $($_.Exception.Message) }  	
    Write-EventLog $global:logName -Source $global:logSourceName -EventId 500 -Message "Exit Script! Error creating a new Remote Exchange Powershell Connection: $msg " -EntryType Error                  
    #Exit
}

$filesToProcess = Get-ChildItem $workingPath | Where-Object { ( $_.Name -like "*CreateNonStdPersonMailbox*_pshjob_.csv") } | Sort-Object LastWriteTime

foreach ($jobToProcess in $filesToProcess) {

    if ($Host.Name -eq "ConsoleHost") {
        $ErrorActionPreference = "SilentlyContinue"
        Stop-Transcript | out-null
        $ErrorActionPreference = "Continue"
        Start-Transcript -path "D:\IAM\Transcripts\Transcript_$($jobToProcess.Name).log" -append
    }
    
    $workingFile = Import-csv $($jobToProcess.FullName) -Delimiter "|" 
    foreach ($workingFileEntry in $workingFile) {

        if ($null -ne $($workingFileEntry.ActionType) -and 
            $null -ne $($workingFileEntry.TargetAdObjectName) -and 
            $null -ne $($workingFileEntry.MailboxEnable) -and 
            $null -ne $($workingFileEntry.TargetDomain) -and 
            $null -ne $($workingFileEntry.TargetUserAdSurname) -and 
            $null -ne $($workingFileEntry.TargetUserAdGivenname) -and 
            $null -ne $($workingFileEntry.TargetUserAdDisplayname) -and 
            $null -ne $($workingFileEntry.TargetLocation) -and 
            $null -ne $($workingFileEntry.TargetUserAdEmployeeType) -and 
            $null -ne $($workingFileEntry.TargetUserDomainOU) -and 
            $null -ne $($workingFileEntry.CurrentUserName) -and 
            $null -ne $($workingFileEntry.CurrentUserDomainName) -and
            $null -ne $($workingFileEntry.CurrentUserEMailAddress)) {

            $global:ServiceAccountType = [EmployeeType]::NONE

            if ($($workingFileEntry.TargetUserAdEmployeeType) -eq "S") {            
                switch ($workingFileEntry.ActionType) {
                    'CreateServiceAccount' { $global:ServiceAccountType = [EmployeeType]::SERVICE }
                    'CreateManagedServiceAccount' { $global:ServiceAccountType = [EmployeeType]::MANAGED_SERVICE }
                    'CreateWpaServiceAccount' { $global:ServiceAccountType = [EmployeeType]::WLAN_SERVICE }
                }
            }

            if ($($workingFileEntry.TargetUserAdEmployeeType) -eq "P" -or $($workingFileEntry.TargetUserAdEmployeeType) -eq "HNP") {
                While ((Get-ScheduledTask -TaskName $scheduledTaskName).State -eq "Running") {
                    Write-EventLog $global:logName -Source $global:logSourceName -EventId 6100 -Message "Scheduled Task $($scheduledTaskName) is currently running, hence we'll pause for 15 seconds." -EntryType Warning
                    Start-Sleep -Seconds 15
                }
                Write-EventLog $global:logName -Source $global:logSourceName -EventId 6100 -Message "Scheduled Task $($scheduledTaskName) is currently offline, hence we'll continue." -EntryType Information
            }

            $msg = $null
            $htmlBody = $null
            $htmlBody = "<p style=""Color:Black;font-weight:normal;Font-Size:smaller;font-family:Tahoma"">"
            $htmlBody += "Lieber Mitarbeiter, <br/><br/>"

            $errorMsg = $null

            switch ($($workingFileEntry.TargetLocation)) {
                'BH' {
                    $global:city = "Bruderholz"
                    $global:zipCode = "4101"
                    $global:streetAddress = "Bruderholz"

                }
                'LA' { 
                    $global:city = "Laufen"
                    $global:zipCode = "4242"
                    $global:streetAddress = "Lochbruggstrasse 39"
                }
                'LI' { 
                    $global:city = "Liestal"
                    $global:zipCode = "4410"
                    $global:streetAddress = "Rheinstrasse 26"
                }
                'KSBL' { 
                    $global:city = "Liestal"
                    $global:zipCode = "4410"
                    $global:streetAddress = "Rheinstrasse 26"
                }
            }

            $resourceForestAccount = $null
            $ldapFilter = $null

            if ($($workingFileEntry.TargetUserAdEmployeeType) -eq "S") {
                $surName = Replace-IllegalChars -stringToConvert $($workingFileEntry.TargetUserAdSurname)
                $givenName = Replace-IllegalChars -stringToConvert $($workingFileEntry.TargetUserAdGivenname)
                $displayname = "$($givenName) $($surName)"
                $workingFileEntry.TargetUserAdDisplayname = $displayname

            } elseif ($($workingFileEntry.TargetUserAdEmployeeType) -eq "A") {
                $surName = Replace-IllegalChars -stringToConvert $($workingFileEntry.TargetUserAdSurname)
                $givenName = Replace-IllegalChars -stringToConvert $($workingFileEntry.TargetUserAdGivenname)
                $displayname = "Admin $($surName) $($givenName)"
                $workingFileEntry.TargetUserAdDisplayname = $displayname

            } else {
                $surName = Replace-IllegalChars -stringToConvert $($workingFileEntry.TargetUserAdSurname)
                $givenName = Replace-IllegalChars -stringToConvert $($workingFileEntry.TargetUserAdGivenname)
                $displayname = "$($surName) $($givenName)"
                $workingFileEntry.TargetUserAdDisplayname = $displayname
            }

            $ldapFilter = LdapSearchFilterForAccount -workingFileEntry $workingFileEntry

            if ($null -eq $ldapFilter) {
                $resourceForestAccount = $null
            } else {
                try {
                    $ds = New-Object System.DirectoryServices.DirectorySearcher([ADSI]"LDAP://$dc", $ldapFilter, @('samaccountname', 'displayName', 'distinguishedName', 'extensionAttribute11', 'mail'))
                    $resourceForestAccount = $ds.FindOne()            
                } catch {([Exception])
                    if ($_.Exception.InnerException) { $msg = $($_.Exception.InnerException.Message) } else { $msg = $($_.Exception.Message) }  	
                    Write-EventLog $global:logName -Source $global:logSourceName -EventId 6000 -Message "Error retrieving User $($workingFileEntry.TargetAdObjectName) using LDAP-Filter $($ldapFilter): $msg " -EntryType Error                  
                }                
            }


            # Benutzerattribut setzen und Fehlerbehandlung durchführen
            if ($resourceForestAccount -ne $null -and $workingFileEntry.TargetUserAdEmployeeType -notin @("A", "E")) {
                Write-EventLog $global:logName -Source $global:logSourceName -EventId 6000 -EntryType Warning -Message "User $($displayname) matches with AD User $($resourceForestAccount.Properties["displayName"]) ($($workingFileEntry.TargetAdObjectName)) hence we'll update the existing AD object."
    
                # Attribut setzen
                Set-AdUserWithErrorHandling -userName $workingFileEntry.TargetAdObjectName -attribute "samaccountname" -value $resourceForestAccount.Properties["samaccountname"]
                Set-AdUserWithErrorHandling -userName $workingFileEntry.TargetAdObjectName -attribute "Description" -value "Updated am $(get-date -Format 'yyyy-MM-dd') von $($workingFileEntry.CurrentUserName)"
    
                # Weitere Einstellungen für HNP
                if ($workingFileEntry.TargetUserAdEmployeeType -eq "HNP") {
                    Set-AdUserWithErrorHandling -userName $workingFileEntry.TargetAdObjectName -attribute "PasswordNeverExpires" -value $true
                    Set-AdUserWithErrorHandling -userName $workingFileEntry.TargetAdObjectName -attribute "Title" -value "Hausarzt"
                    Set-AdUserWithErrorHandling -userName $workingFileEntry.TargetAdObjectName -attribute "AccountExpirationDate" -value (Get-Date).AddDays(-1)
                }

                # E-Mail aktivieren
                if ($workingFileEntry.MailboxEnable) {
                    $newEmail = Validate-EMailAddress -mailDomain $primaryMailDomain -givenName $givenName -surName $surName
                    Update-Mailbox -userName $workingFileEntry.TargetAdObjectName -newEmail $newEmail
                }

                Write-Host "Successfully updated PersonMailbox $displayname as $($workingFileEntry.TargetAdObjectName) in $($workingFileEntry.TargetUserDomainOU)" -ForegroundColor Green
            }

            # Neue AD-Objekte erstellen
            if ($resourceForestAccount -eq $null -or $workingFileEntry.TargetUserAdEmployeeType -in @("A", "E")) {
                $nextAvailableSamAccountName = Get-NextAvailableSamAccountName -localForestDomainController $dc -employeeType ([EmployeeType]::EXTERNAL)
                $workingFileEntry.TargetAdObjectName = $nextAvailableSamAccountName
                Write-EventLog $global:logName -Source $global:logSourceName -EventId 6000 -entryType Information -Message "User $($displayname) has no match with an existing AD User hence, we'll create a new AD object named ($($nextAvailableSamAccountName))."
    
                # Setzen von AD-Attributen für das neue AD-Objekt
                Set-AdUserWithErrorHandling -userName $workingFileEntry.TargetAdObjectName -attribute "Description" -value "Erstellt am $(get-date -Format 'yyyy-MM-dd') von $($workingFileEntry.CurrentUserName)"
    
                # Mailbox erstellen
                if ($workingFileEntry.MailboxEnable) {
                    $newEmail = Validate-EMailAddress -mailDomain $primaryMailDomain -givenName $givenName -surName $surName
                    Update-Mailbox -userName $workingFileEntry.TargetAdObjectName -newEmail $newEmail
                }
            }

            if ($($workingFileEntry.TargetUserAdEmployeeType) -eq "P" `
                -or $($workingFileEntry.TargetUserAdEmployeeType) -eq "E" `
                -or $($workingFileEntry.TargetUserAdEmployeeType) -eq "HNP") {

                try {
                    Set-ADUser $($workingFileEntry.TargetAdObjectName) -replace @{"hrmsBadgeFirstName" = $((Get-ADUser $workingFileEntry.TargetAdObjectName).GivenName)} -ErrorAction Stop
                } catch {([Exception])
                    if ($_.Exception.InnerException) { $msg = $($_.Exception.InnerException.Message) } else { $msg = $($_.Exception.Message) }  	
                    Write-EventLog $global:logName -Source $global:logSourceName -EventId 1969 -Message "Error setting Attribute hrmsBadgeFirstName for User $($workingFileEntry.TargetAdObjectName): $msg " -EntryType Error                  
                }

                try {
                    Set-ADUser $($workingFileEntry.TargetAdObjectName) -replace @{"hrmsBadgeLastName" = $((Get-ADUser $workingFileEntry.TargetAdObjectName).SurName)} -ErrorAction Stop
                } catch {([Exception])
                    if ($_.Exception.InnerException) { $msg = $($_.Exception.InnerException.Message) } else { $msg = $($_.Exception.Message) }  	
                    Write-EventLog $global:logName -Source $global:logSourceName -EventId 1969 -Message "Error setting Attribute hrmsBadgeLastName for User $($workingFileEntry.TargetAdObjectName): $msg " -EntryType Error                  
                }
            }

            $userSettings = $null
            # Prüfe, ob es sich um einen Service-Account handelt
            $targetIsServiceAccount = $workingFileEntry.TargetUserAdEmployeeType -eq "S"
            $isManagedServiceType = $global:ServiceAccountType -eq [EmployeeType]::MANAGED_SERVICE
            $adObjectName = $workingFileEntry.TargetAdObjectName

            # Bestimme das Cmdlet basierend auf dem Typ
            if ($targetIsServiceAccount -and $isManagedServiceType) {
                $userSettings = Get-ADServiceAccount -Identity $adObjectName -Properties *
            } else {
                $userSettings = Get-ADUser -Identity $adObjectName -Properties *
            }

            Write-EventLog $global:logName -Source $global:logSourceName `
                -EventId 6000 `
                -entryType Information `
                -Message  "Successfully created new Non Std Person User. ($userSettings | Out-String)"                        

            Write-Host "Successfully created PersonMailbox $displayname with E-Mail $newPrimaryEMail as $($workingFileEntry.TargetAdObjectName) in $($workingFileEntry.TargetUserDomainOU)" -ForegroundColor Green

            $htmlBody += "Viele Grüsse vom E-Mail Team</p>"
            Send-EMail `
                -smtpHost $smtpHost `
                -mailFrom $mailFrom `
                -mailTo $($workingFileEntry.CurrentUserEMailAddress) `
                -mailCc $mailCc `
                -mailSubject "*** Auftrag - Erstellen eines 'nicht standardisierten' Benutzerkontos ***" `
                -mailBody $htmlBody `
                -attachment $null `

        }
    }

    if ($Host.Name -eq "ConsoleHost") {
        Stop-Transcript
    }

    Move-Item $($jobToProcess.FullName) "D:\IAM\Archive\$($jobToProcess.Name)" -Force -Confirm:$false

}

$filesToProcess = Get-ChildItem -Recurse -Force $workingPath -ErrorAction SilentlyContinue | Where-Object { ( $_.Name -like "*EnableAdAccountWithGracePeriod*_pshjob_.csv") }

foreach ($jobToProcess in $filesToProcess) {

    if ($Host.Name -eq "ConsoleHost") {
        $ErrorActionPreference = "SilentlyContinue"
        Stop-Transcript | out-null
        $ErrorActionPreference = "Continue"
        Start-Transcript -path "D:\IAM\Transcripts\Transcript_$($jobToProcess.Name).log" -append
    }

    $workingFile = Import-csv $($jobToProcess.FullName) -Delimiter "|" 
    foreach ($workingFileEntry in $workingFile) {

        if ($($workingFileEntry.ActionType) -ne $null -and 
            $($workingFileEntry.AdObjectName) -ne $null -and 
            $($workingFileEntry.GracePeriod) -ne $null -and 
            $($workingFileEntry.CurrentUserName) -ne $null -and 
            $($workingFileEntry.CurrentUserDomainName) -ne $null -and 
            $($workingFileEntry.CurrentUserEMailAddress) -ne $null) {

            $msg = $null
            $htmlBody = $null
            $htmlBody = "<p style=""Color:Black;font-weight:normal;Font-Size:smaller;font-family:Tahoma"">"
            $htmlBody += "Lieber Mitarbeiter, <br/><br/>"

            try {
                $resourceForestUserObject = Get-ADUser -LDAPFilter "(samaccountname=$($workingFileEntry.AdObjectName))" -Properties mail, SamAccountName, AccountExpirationDate, mailNickname -Server $dc
            }
            catch {
([Exception])
                if ($_.Exception.InnerException) { $msg = $($_.Exception.InnerException.Message) } else { $msg = $($_.Exception.Message) }  	
                Write-EventLog $global:logName -Source $global:logSourceName -EventId 6000 -Message "Error getting User $($workingFileEntry.AdObjectName) from Active-Directory: $msg " -EntryType Error                  
            }

            if ($resourceForestUserObject -ne $null) {

                if ($resourceForestUserObject.Enabled -eq $false) {

                    try {
                        Set-ADAccountPassword -Identity $($resourceForestUserObject.SamAccountName) -Reset -NewPassword (ConvertTo-SecureString -AsPlainText "P@ssw0rd4You" -Force)                     
                    }
                    catch {
([Exception])
                        if ($_.Exception.InnerException) { $msg = $($_.Exception.InnerException.Message) } else { $msg = $($_.Exception.Message) }  	
                        Write-EventLog $global:logName -Source $global:logSourceName -EventId 6000 -Message "Error setting NewPassword for User $($workingFileEntry.TargetAdObjectName): $msg " -EntryType Error                  
                    }

                    try {
                        Set-ADUser $resourceForestUserObject.SamAccountName -Enabled $true -ChangePasswordAtLogon $true -AccountExpirationDate $($workingFileEntry.GracePeriod) -Server $dc
                        Set-ADUser $resourceForestUserObject.SamAccountName -Replace @{'hrmsIsExpired' = $true }
                    }
                    catch {
([Exception])
                        if ($_.Exception.InnerException) { $msg = $($_.Exception.InnerException.Message) } else { $msg = $($_.Exception.Message) }  	
                        Write-EventLog $global:logName -Source $global:logSourceName -EventId 6000 -Message "Error enabling User $($workingFileEntry.TargetAdObjectName): $msg " -EntryType Error                  
                    }

                    Change-MailboxFeaturesAndState -mailboxName $resourceForestUserObject.mailNickname -objectState ([ObjectState]::UNHIDE)

                    Write-Host "Successfully activated account $($resourceForestUserObject.SamAccountName) and set Expiration date to $($workingFileEntry.GracePeriod)" -ForegroundColor Green
                    $htmlBody += "Das Benutzerkonto <b> $($resourceForestUserObject.SamAccountName) </b> wurde erfolgreich aktiviert und auf den $($workingFileEntry.GracePeriod) terminiert.<br/><br/>"                
                                        
                }
                else {

                    try {
                        Set-ADUser $resourceForestUserObject.SamAccountName -AccountExpirationDate $($workingFileEntry.GracePeriod) -Server $dc
                        Set-ADUser $resourceForestUserObject.SamAccountName -Replace @{'hrmsIsExpired' = $true }
                    }
                    catch {
([Exception])
                        if ($_.Exception.InnerException) { $msg = $($_.Exception.InnerException.Message) } else { $msg = $($_.Exception.Message) }  	
                        Write-EventLog $global:logName -Source $global:logSourceName -EventId 6000 -Message "Error setting AccountExpirationDate for User $($workingFileEntry.TargetAdObjectName): $msg " -EntryType Error                  
                    }

                    Write-Host "The account account $($resourceForestUserObject.SamAccountName) was already activated so we just set the Expiration date to $($workingFileEntry.GracePeriod)" -ForegroundColor Green
                    $htmlBody += "Das Benutzerkonto <b> $($resourceForestUserObject.SamAccountName) </b> war bereits aktiv und es wurde neu auf den $($workingFileEntry.GracePeriod) terminiert.<br/><br/>"                
                    
                }

                $htmlBody += "Viele Grüsse vom E-Mail Team</p>"                        
                Send-EMail -smtpHost $smtpHost -mailFrom $mailFrom -mailTo $($workingFileEntry.CurrentUserEMailAddress) -mailCc $mailCc -mailSubject "*** Auftrag - Benutzerkonto aktivieren und terminieren ***" -mailBody $htmlBody -attachment $null
            }
        }                      
    }

    if ($Host.Name -eq "ConsoleHost") {
        Stop-Transcript
    }

    Move-Item $($jobToProcess.FullName) "D:\IAM\Archive\$($jobToProcess.Name)" -Force -Confirm:$false

}

$filesToProcess = Get-ChildItem -Recurse -Force $workingPath -ErrorAction SilentlyContinue | Where-Object { ( $_.Name -like "*ModifyMobilePhoneNumber*_pshjob_.csv") }

foreach ($jobToProcess in $filesToProcess) {

    if ($Host.Name -eq "ConsoleHost") {
        $ErrorActionPreference = "SilentlyContinue"
        Stop-Transcript | out-null
        $ErrorActionPreference = "Continue"
        Start-Transcript -path "D:\IAM\Transcripts\Transcript_$($jobToProcess.Name).log" -append
    }

    $workingFile = Import-csv $($jobToProcess.FullName) -Delimiter "|" 
    foreach ($workingFileEntry in $workingFile) {

        if ($($workingFileEntry.ActionType) -ne $null -and 
            $($workingFileEntry.AdObjectName) -ne $null -and 
            $($workingFileEntry.MobileNumber) -ne $null -and 
            $($workingFileEntry.CurrentUserName) -ne $null -and 
            $($workingFileEntry.CurrentUserDomainName) -ne $null -and 
            $($workingFileEntry.CurrentUserEMailAddress) -ne $null) {
            
            try {
                $forestUserObject = Get-ADUser -LDAPFilter "(samaccountname=$($workingFileEntry.AdObjectName))" -Properties mail, SamAccountName, extensionattribute3 -Server $dc
            }
            catch {
([Exception])
                if ($_.Exception.InnerException) { $msg = $($_.Exception.InnerException.Message) } else { $msg = $($_.Exception.Message) }  	
                Write-EventLog $global:logName -Source $global:logSourceName -EventId 6000 -Message "Error getting User $($workingFileEntry.AdObjectName) from Active-Directory: $msg " -EntryType Error                  
                Exit
            }

            if ($forestUserObject -ne $null) {

                $htmlBody = $null
                $htmlBody = "<p style=""Color:Black;font-weight:normal;Font-Size:smaller;font-family:Tahoma"">"
                $htmlBody += "Lieber Mitarbeiter, <br/><br/>"

                try {
                    Set-ADUser $forestUserObject -Server $dc -Replace @{"smsPasscodeMobile" = $($workingFileEntry.MobileNumber) }
                }
                catch [System.Exception] {
                    if ($_.Exception.InnerException) { $errorMsg = $($_.Exception.InnerException.Message) } else { $errorMsg = $($_.Exception.Message) }
                    Write-EventLog $global:logName -Source $global:logSourceName -EventId 6000 -Message "Error setting smsPasscodeMobile for User $($workingFileEntry.AdObjectName): $msg " -EntryType Error                                      
                    $htmlBody += "Während dem Modifizieren des Attributes 'smsPasscodeMobile' auf dem Benutzer <b> $($forestUserObject.Samaccountname) </b> ist folgender Fehler aufgetreten: <b> $($errorMsg) </b><br/><br/>"                     
                }

                Write-Host "Successfully changed mobile phone number of user $($forestUserObject.Samaccountname) to $($workingFileEntry.MobileNumber)" -ForegroundColor Green
                $htmlBody += "Beim Benutzer <b> $($forestUserObject.Samaccountname) </b> wurde erfolgreich der die Mobile Nummer $($workingFileEntry.MobileNumber) mutiert.<br/><br/>"                
                    
                $htmlBody += "Viele Grüsse vom E-Mail Team</p>"                        
                Send-EMail -smtpHost $smtpHost -mailFrom $mailFrom -mailTo $($workingFileEntry.CurrentUserEMailAddress) -mailCc $mailCc -mailSubject "*** Auftrag - Mutieren der Mobilen Telefonnummer ***" -mailBody $htmlBody -attachment $null                
            }                                                                   
        }
    }

    if ($Host.Name -eq "ConsoleHost") {
        Stop-Transcript
    }

    Move-Item $($jobToProcess.FullName) "D:\IAM\Archive\$($jobToProcess.Name)" -Force -Confirm:$false

}

$filesToProcess = Get-ChildItem -Recurse -Force $workingPath -ErrorAction SilentlyContinue | Where-Object { ( $_.Name -like "*ModifyMailboxFolderAce*_pshjob_.csv") }

foreach ($jobToProcess in $filesToProcess) {

    if ($Host.Name -eq "ConsoleHost") {
        $ErrorActionPreference = "SilentlyContinue"
        Stop-Transcript | out-null
        $ErrorActionPreference = "Continue"
        Start-Transcript -path "D:\IAM\Transcripts\Transcript_$($jobToProcess.Name).log" -append
    }

    $workingFile = Import-csv $($jobToProcess.FullName) -Delimiter "|" 
    foreach ($workingFileEntry in $workingFile) {

        if ($($workingFileEntry.ActionType) -ne $null -and 
            $($workingFileEntry.AdObjectName) -ne $null -and 
            $($workingFileEntry.DelegatedAdObjectName) -ne $null -and 
            $($workingFileEntry.MailboxFolderName) -ne $null -and 
            $($workingFileEntry.AclEntry) -ne $null -and 
            $($workingFileEntry.AclActionType) -ne $null -and 
            $($workingFileEntry.CurrentUserName) -ne $null -and 
            $($workingFileEntry.CurrentUserDomainName) -ne $null -and 
            $($workingFileEntry.CurrentUserEMailAddress) -ne $null) {
            
            $msg = $null
            $htmlBody = $null
            $htmlBody = "<p style=""Color:Black;font-weight:normal;Font-Size:smaller;font-family:Tahoma"">"
            $htmlBody += "Lieber Mitarbeiter, <br/><br/>"

            #$Error.Clear()

            $delegatedUser = $null
            $delegatingUser = $null

            try {
                $delegatedUser = Get-ADUser -LDAPFilter "(&(sAMAccountType=805306368)(samaccountname=$($workingFileEntry.AdObjectName)))" -Properties mailNickname
            }
            catch {
([Exception])
                if ($_.Exception.InnerException) { $msg = $($_.Exception.InnerException.Message) } else { $msg = $($_.Exception.Message) }  	
                Write-EventLog $global:logName -Source $global:logSourceName -EventId 6000 -Message "Error getting User $($workingFileEntry.AdObjectName) from Active-Directory: $msg " -EntryType Error                  
                Exit
            }

            try {
                $delegatingUser = Get-ADUser -LDAPFilter "(&(sAMAccountType=805306368)(samaccountname=$($workingFileEntry.DelegatedAdObjectName)))" -Properties mailNickname
            }
            catch {
([Exception])
                if ($_.Exception.InnerException) { $msg = $($_.Exception.InnerException.Message) } else { $msg = $($_.Exception.Message) }  	
                Write-EventLog $global:logName -Source $global:logSourceName -EventId 6000 -Message "Error getting delegated User $($workingFileEntry.DelegatedAdObjectName) from Active-Directory: $msg " -EntryType Error                  
                Exit
            }

            if ($delegatedUser -ne $null -and $delegatingUser -ne $null) {

                if (-not [string]::isNullOrEmpty($delegatedUser.mailNickname) -and -not [string]::isNullOrEmpty($delegatingUser.mailNickname)) {
                    
                    try {
                        $mbx = Get-Mailbox $($workingFileEntry.AdObjectName)
                    }
                    catch {
([Exception])
                        if ($_.Exception.InnerException) { $msg = $($_.Exception.InnerException.Message) } else { $msg = $($_.Exception.Message) }  	
                        Write-EventLog $global:logName -Source $global:logSourceName -EventId 6000 -Message "Error getting Mailbox $($workingFileEntry.AdObjectName) from Exchange: $msg " -EntryType Error                        
                        Exit
                    }

                    if ($mbx -ne $null) {

                        try {
                            $calendarName = $null
                            $calendarName = (Get-MailboxFolderStatistics -Identity $mbx.alias -FolderScope Calendar | Select-Object -First 1).Name
                        }
                        catch {
([Exception])
                            if ($_.Exception.InnerException) { $msg = $($_.Exception.InnerException.Message) } else { $msg = $($_.Exception.Message) }  	
                            Write-EventLog $global:logName -Source $global:logSourceName -EventId 6000 -Message "Error getting MailboxFolderStatistics for Mailbox $($mbx.alias) from Exchange: $msg " -EntryType Error                        
                        }

                        if ($calendarName -ne $null) {
                            
                            $folderID = $mbx.alias + ':\' + $calendarName     

                            if ($($workingFileEntry.AclActionType) -eq "RemovePermissons") {
                                try {
                                    Remove-MailboxFolderPermission -Identity $folderID -User $($delegatingUser.userPrincipalName) -Confirm:$false
                                }
                                catch {
([Exception])
                                    if ($_.Exception.InnerException) { $msg = $($_.Exception.InnerException.Message) } else { $msg = $($_.Exception.Message) }  	
                                    Write-EventLog $global:logName -Source $global:logSourceName -EventId 2000 -Message "Error removing Mailbox Permissions for Trustee $($delegatingUser.userPrincipalName) on Mailbox $($folderID): $msg " -EntryType Error                  
                                    $htmlBody += "Während dem Modifizieren des Kalenders auf dem Postfach <b> $($mbx.DisplayName) </b> ist folgender Fehler aufgetreten: <b> $($msg) </b><br/><br/>"                     
                                }
                            }
                            else {
                                try {
                                    Add-MailboxFolderPermission -Identity $folderID -User $($delegatingUser.userPrincipalName) -AccessRights $($workingFileEntry.AclEntry)                                                                
                                }
                                catch {
([Exception])
                                    if ($_.Exception.InnerException) { $msg = $($_.Exception.InnerException.Message) } else { $msg = $($_.Exception.Message) }  	
                                    Write-EventLog $global:logName -Source $global:logSourceName -EventId 2000 -Message "Error adding Mailbox Permissions $($workingFileEntry.AclEntry) for Trustee $($delegatingUser.userPrincipalName) on Mailbox $($folderID): $msg " -EntryType Error                  
                                    $htmlBody += "Während dem Modifizieren des Kalenders auf dem Postfach <b> $($mbx.DisplayName) </b> ist folgender Fehler aufgetreten: <b> $($msg) </b><br/><br/>"                     
                                }
                            }

                            $htmlBody += "Beim Postfach <b> $($mbx.DisplayName) </b> wurde auf den Kalender Berechtigungen der Benutzer $($delegatingUser.userPrincipalName) entsprechend mutiert.<br/><br/>"                
                    
                            $htmlBody += "Viele Grüsse vom E-Mail Team</p>"                        
                            Send-EMail -smtpHost $smtpHost -mailFrom $mailFrom -mailTo $($workingFileEntry.CurrentUserEMailAddress) -mailCc $mailCc -mailSubject "*** Auftrag - Hinzufügen von Kalenderberechtigung ***" -mailBody $htmlBody -attachment $null

                        }
                    }
                }                
            }                

        }
    }

    if ($Host.Name -eq "ConsoleHost") {
        Stop-Transcript
    }


    Move-Item $($jobToProcess.FullName) "D:\IAM\Archive\$($jobToProcess.Name)" -Force -Confirm:$false

}

Get-PSSession | Remove-PSSession

