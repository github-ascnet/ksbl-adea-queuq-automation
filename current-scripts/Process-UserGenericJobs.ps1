$cSharpEnum = @"
        public enum EmployeeType {
                INTERNAL,
                EXTERNAL,
                GENERIC,
                SERVICE,
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

function Update-DfsShareSettings ($samAccountName) {

    try {
        $home_drive = $null
        $home_drive = Get-HomeDrive
                                                   
        if ($home_drive -ne $null) {
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
    catch {([Exception])
	    if ($_.Exception.InnerException) { $msg = $($_.Exception.InnerException.Message) } else { $msg = $($_.Exception.Message) }  	
	    Write-EventLog $global:logName -Source $global:logSourceName -EventId 1000 -Message "Error updating DFS-Path for User $($workingFileEntry.AdObjectName): $msg " -EntryType Error                  
    }

}

function Get-HomeDrive() {
    <#
    .SYNOPSIS
        Gets the HomeDrive with the least utilization
    .DESCRIPTION
        Reads the available HomeDrives from all the Home-Servers
        and gets the HomeDrive with the least utilization.
        Function brought in and maintained by Michael Hochstrasser
        Modified on:   22.03.2016
        Version:       1.0
    #>

    #------------------------------------
    $fs_server = @(
        'sv01005.ksbl.local'
    );
    #------------------------------------

    $home_targets = @();

    $fs_shares = @{};
    foreach($server in $fs_server)
    {
        $fs_shares += @{ $server = @() };
        Get-WmiObject -class Win32_Share -Computer $server -Filter "Name like 'home[_][a-z]$'" | %{
            $fs_shares[$server] += @{ 'name' = $_.Name; 'path' = $_.Path };
        }
    }

    foreach($server in $fs_shares.Keys)
    {
        foreach($share in $fs_shares[$server])
        {
            $disc = Get-WmiObject Win32_LogicalDisk -Filter "DeviceID='$($share.path.Substring(0, 2))'" -ComputerName $server;

            $unc_path = Join-Path -Path ('\\'+$server) -ChildPath $share.name
            if(Test-Path $unc_path)
            {
                $dir_count = (Get-ChildItem -Path $unc_path).Count
            }
            else
            {
                $dir_count = 1;
            }
            #$disc_size = [math]::Round($disc.Size /1024/1024/1024);
            #$disc_size = $disc.Size;
            #$free_space = [math]::Round($disc.FreeSpace /1024/1024/1024);
            $free_space = $disc.FreeSpace;
            $dir_points = ($dir_count * 1024 * 1024 * 1024) * 2; # 2 GB for each folder
            $home_targets += @{
                'server' = $server;
                'path' = $share.path;
                'unc_path' = $unc_path;
                'name' = $share.name;
                #'disc_size' = $disc_size;
                'free_space' = $free_space;
                'dir_count' = $dir_count;
                'Points' = $free_space - $dir_points;
            };
        }
    }

    $sort1 = @{Expression='Points'; Descending=$true };
    $sort2 = @{Expression='name'; Ascending=$true };

    #$home_targets | %{ new-object PSObject -Property $_} | Sort-Object $sort1, $sort2 | Format-Table -AutoSize

    return $home_targets | %{ new-object PSObject -Property $_} | Sort-Object $sort1, $sort2 | Select-Object -First 1
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

    if ($exitcode -ne 0)
    {
        Write-Host "Fehler bei Aufruf von DFSUtil: $stdout $stderr"
        Write-EventLog $global:logName -Source $global:logSourceName -EventId 1000 -Message "DFS-Util Return Message: $stdout $stderr " -EntryType Error                  
        #Add-Content -Path $log_path -Value "Fehler bei Aufruf von DFSUtil: $stdout $stderr";
        $False
    }
    else
    { 
        $True 
    }
}

function Change-MailboxFeaturesAndState {
    [CmdletBinding()]
    [OutputType([bool])]
    Param
    (
        [Parameter(Mandatory=$true,
                   ValueFromPipelineByPropertyName=$true,
                   Position=0)]
        $mailboxName,
        [Parameter(Mandatory=$true,
                   ValueFromPipelineByPropertyName=$true,
                   Position=1)]
        $objectState
        
    )

    if ((Get-Mailbox $mailboxName).HiddenFromAddressListsEnabled -eq $true -and $objectState -eq [ObjectState]::UNHIDE ) {
        try {
            Set-CASMailbox -Identity $mailboxName -OWAEnabled $true -ActiveSyncEnabled $true
            Write-Host "Successfully enabled OWA and EAS for Exchange Mailbox $($mailboxName)" -ForegroundColor Green
        } catch [System.Exception] {
            if ($_.Exception.InnerException) { $msg = $($_.Exception.InnerException.Message) } else { $msg = $($_.Exception.Message) }  
	        Write-EventLog $global:logName -Source $global:logSourceName -EventId 1000 -Message "Failed enabling OWA and EAS for Exchange Mailbox $($mailboxName). Error: $msg" -EntryType Error                  
            Write-Host "Failed enabling OWA and EAS for Exchange Mailbox $($mailboxName). Error: $msg" -ForegroundColor Red
        }        

        try {
            Set-Mailbox $($mailboxName) -HiddenFromAddressListsEnabled $false
            Write-Host "Successfully enabled Addressbook view for Exchange Mailbox $($mailboxName)" -ForegroundColor Green
        } catch [System.Exception] {
            if ($_.Exception.InnerException) { $msg = $($_.Exception.InnerException.Message) } else { $msg = $($_.Exception.Message) }  
	        Write-EventLog $global:logName -Source $global:logSourceName -EventId 1000 -Message "Failed enabling Addressbook view for Exchange Mailbox $($mailboxName). Error: $msg" -EntryType Error                  
            Write-Host "Failed enabling Addressbook view for Exchange Mailbox $($mailboxName). Error: $msg" -ForegroundColor Red
        }
    }

    if ((Get-Mailbox $mailboxName).HiddenFromAddressListsEnabled -eq $false -and $objectState -eq [ObjectState]::HIDE ) {
        try {
            Set-CASMailbox -Identity $mailboxName -OWAEnabled $false -ActiveSyncEnabled $false
            Write-Host "Successfully disabled OWA and EAS for Exchange Mailbox $($mailboxName)" -ForegroundColor Green
        } catch [System.Exception] {
            if ($_.Exception.InnerException) { $msg = $($_.Exception.InnerException.Message) } else { $msg = $($_.Exception.Message) }  
	        Write-EventLog $global:logName -Source $global:logSourceName -EventId 1000 -Message "Failed disabling OWA and EAS for Exchange Mailbox $($mailboxName). Error: $msg" -EntryType Error                  
            Write-Host "Failed disabling OWA and EAS for Exchange Mailbox $($mailboxName). Error: $msg" -ForegroundColor Red
        }        

        try {
            Set-Mailbox $($mailboxName) -HiddenFromAddressListsEnabled $true
            Write-Host "Successfully disabled Addressbook view for Exchange Mailbox $($mailboxName)" -ForegroundColor Green
        } catch [System.Exception] {
            if ($_.Exception.InnerException) { $msg = $($_.Exception.InnerException.Message) } else { $msg = $($_.Exception.Message) }  
	        Write-EventLog $global:logName -Source $global:logSourceName -EventId 1000 -Message "Failed disabling Addressbook view for Exchange Mailbox $($mailboxName). Error: $msg" -EntryType Error                  
            Write-Host "Failed disabling Addressbook view for Exchange Mailbox $($mailboxName). Error: $msg" -ForegroundColor Red
        }
    }
}

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
        if((Test-Path $applicationDirectoryPath) -eq $false) {

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

        $rule = New-Object System.Security.AccessControl.FileSystemAccessRule("Administrators","FullControl", "ContainerInherit, ObjectInherit", "None", "Allow")
        $acl.AddAccessRule($rule)
        
        $rule = New-Object System.Security.AccessControl.FileSystemAccessRule("$userPrincipalDomain\$userPrincipalName","Modify", "ContainerInherit, ObjectInherit", "None", "Allow")
        $acl.AddAccessRule($rule)
        Set-Acl $applicationDirectoryPath $acl
                        
        Write-Host "Successfully set ACL on application directory $applicationDirectoryPath for user account $userPrincipalDomain\$userPrincipalName" -ForegroundColor Green

    } catch [System.Exception] {
        if ($_.Exception.InnerException) { $msg = $($_.Exception.InnerException.Message) } else { $msg = $($_.Exception.Message) }  
        Write-Host "Failed setting ACL on application directory $applicationDirectoryPath for user account $userPrincipalDomain\$userPrincipalName. Error: $msg" -ForegroundColor Red
	    Write-EventLog $global:logName -Source $global:logSourceName -EventId 500 -Message "Failed setting ACL on application directory $applicationDirectoryPath for user $($userPrincipalName): $msg " -EntryType Error                  
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
        
        if((test-path $homeDirectoryPath) -eq $false) {

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
        } 
        
        $acl = Get-Acl $homeDirectoryPath
        $acl.SetAccessRuleProtection($True, $False)

        $rule = New-Object System.Security.AccessControl.FileSystemAccessRule("Administrators","FullControl", "ContainerInherit, ObjectInherit", "None", "Allow")
        $acl.AddAccessRule($rule)
        
        $rule = New-Object System.Security.AccessControl.FileSystemAccessRule("$userPrincipalDomain\$userPrincipalName","Modify", "ContainerInherit, ObjectInherit", "None", "Allow")
        $acl.AddAccessRule($rule)
        Set-Acl $homeDirectoryPath $acl
        #Get-Acl $homeDirectoryPath  | Format-List
                        
        Write-Host "Successfully set ACL on home directory $homeDirectoryPath for user account $userPrincipalDomain\$userPrincipalName" -ForegroundColor Green
        #cacls $homeDirectoryPath

    } catch [System.Exception] {
        if ($_.Exception.InnerException) { $msg = $($_.Exception.InnerException.Message) } else { $msg = $($_.Exception.Message) }  
	    Write-EventLog $global:logName -Source $global:logSourceName -EventId 500 -Message "Failed setting ACL on home directory $($homeDirectoryPath) for user $($userPrincipalName): $msg " -EntryType Error                  
    }        

}

function Replace-IllegalChars {
    [CmdletBinding()]
    [OutputType([string])]
    Param
    (
        [Parameter(Mandatory=$true,
                   ValueFromPipelineByPropertyName=$true,
                   Position=0)]
        $stringToConvert
    )

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
        $mailMessage = New-Object System.Net.Mail.MailMessage($mailFrom,$mailTo,$mailSubject,$mailBody)
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

    } catch {([Exception])
	    if ($_.Exception.InnerException) { $msg = $($_.Exception.InnerException.Message) } else { $msg = $($_.Exception.Message) }  	
	    Write-EventLog $global:logName -Source $global:logSourceName -EventId 300 -Message "Error sending Summary-Mail $($mailSubject): $msg " -EntryType Error                  
    }

} 

function Random-Password () {        
    $length = 10
    $punc = 46..46        
    $digits = 48..57        
    $letters = 65..90 + 97..122         
    $password = get-random -count $length -input ($punc + $digits + $letters) | % -begin { $aa = $null } -process {$aa += [char]$_} -end {$aa}
    return $password
}

function Validate-IfisNumeric {    
    [CmdletBinding()]
    [OutputType([bool])]
    Param
    (
        [Parameter(Mandatory=$true,
                   ValueFromPipelineByPropertyName=$true,
                   Position=0)]
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
        [Parameter(Mandatory=$true,
                   ValueFromPipelineByPropertyName=$true,
                   Position=0)]
        $localForestDomainController,
        [Parameter(Mandatory=$true,
                   ValueFromPipelineByPropertyName=$true,
                   Position=0)]
        $employeeType
    )    

    [int[]]$userIds = $null
    $newUserId = $null

    if ($employeeType -eq ([EmployeeType]::INTERNAL)) {
        [string[]]$samAccountNames = (((Get-ADUser -LDAPFilter "(|(samaccountname=us*)(samaccountname=h2ad*))" -Server $localForestDomainController).samaccountname -Replace "us", "") -Replace("vdi", "")  -Replace("h2ad", ""))
    } else {
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

    } else {

        [int]$userId = ($userIds | Sort-Object | select -Last 1)

        if ($userId.ToString().length -eq 1) {
            $userId = "ex0000$($userId + 1)"        
        } elseif ($userId.ToString().length -eq 2) {
            $newUserId = "ex000$($userId + 1)"        
        } elseif ($userId.ToString().length -eq 3) {
            $newUserId = "ex00$($userId + 1)"        
        } elseif ($userId.ToString().length -eq 4) {
            $newUserId = "ex0$($userId + 1)"        
        } elseif ($userId.ToString().length -eq 5) {
            $newUserId = "ex$($userId + 1)"        
        }
    }

    return $newUserId   
   
}

function EnableDisable-Mailbox ($resourceForestUserObject, $workingFileEntry, $enableMailbox) {

    if ($enableMailbox -eq $true) {

        $surName = Replace-IllegalChars -stringToConvert $($resourceForestUserObject.Surname)
        $givenName = Replace-IllegalChars -stringToConvert $($resourceForestUserObject.GivenName)
        $newPrimaryEMail = Validate-EMailAddress -mailDomain $primaryMailDomain -givenName $givenName -surName $surName
        $displayName = "$($surName) $($givenName)"
        Write-Host "Enabling Mailbox $($displayName) with E-Mail $newPrimaryEMail"
                        
        try {
                            
            $mailboxDatabase = $defaultMailboxDbs | Get-Random                            

            Enable-Mailbox `
                    -Identity $($workingFileEntry.AdObjectName) `
                    -Database $mailboxDatabase `
                    -PrimarySmtpAddress $newPrimaryEMail `
                    -DisplayName $displayName `
                    -Alias $($workingFileEntry.AdObjectName) `
                    -DomainController $dc

        } catch [System.Exception] {
            if ($_.Exception.InnerException) { $msg = $($_.Exception.InnerException.Message) } else { $msg = $($_.Exception.Message) }

            Write-EventLog $global:logName -Source $global:logSourceName `
                    -EventId 1000 `
                    -entryType Error `
                    -Message  "An error occurred while enabling Mailbox $($workingFileEntry.AdObjectName): $msg "                        

            $htmlBody += "Während dem aktivieren des Benutzer-Postfaches <b> $($workingFileEntry.AdObjectName) </b> ist folgender Fehler aufgetreten: <b> $($msg) </b><br/><br/>"    
                            
            Send-EMail -smtpHost $smtpHost -mailFrom $mailFrom -mailTo $($workingFileEntry.CurrentUserEMailAddress) -mailCc $mailCc `
                -mailSubject "*** Auftrag - Fehler beim Aktivieren einer 'inaktiven' Personenmailbox ***" `
                -mailBody $htmlBody `
                -attachment $null `
            Exit                                     
        }

    } else {

        Write-Host "Disabling Mailbox $($displayName)"
                        
        try {
                            
            Disable-Mailbox -Identity $($workingFileEntry.AdObjectName) -DomainController $dc -Confirm:$false

        } catch [System.Exception] {
            if ($_.Exception.InnerException) { $msg = $($_.Exception.InnerException.Message) } else { $msg = $($_.Exception.Message) }

            Write-EventLog $global:logName -Source $global:logSourceName `
                    -EventId 1000 `
                    -entryType Error `
                    -Message  "An error occurred while disabling Mailbox $($workingFileEntry.AdObjectName): $msg "                        

            $htmlBody += "Während dem ianktivieren des Benutzer-Postfaches <b> $($workingFileEntry.AdObjectName) </b> ist folgender Fehler aufgetreten: <b> $($msg) </b><br/><br/>"    
                            
            Send-EMail -smtpHost $smtpHost -mailFrom $mailFrom -mailTo $($workingFileEntry.CurrentUserEMailAddress) -mailCc $mailCc `
                -mailSubject "*** Auftrag - Fehler beim Inaktivieren einer 'aktiven' Personenmailbox ***" `
                -mailBody $htmlBody `
                -attachment $null `
            Exit                                     
        }
    }    
}

<#
function RenameDfsPathAndHomeDirectory($resourceForestUserObject, $newUserId) {
    
    try {

        $dfsRootPath = (Get-DfsnRoot -ErrorAction SilentlyContinue | Where-Object { $_.Path -like "*\HomeDrives" }).Path 

        if ($null -ne $($dfsRootPath)) {
            
            # Check if we have an existing Home Directory
            $existingUserHomeDirectoryDrive = $null
            $homeDirectoryDrive = $null
            $existingUserHomeDirectoryDrive = Get-ExistingUserHomeDirectoryDrive -samAccountName $resourceForestUserObject.SamAccountName
            
            if ($null -ne $existingUserHomeDirectoryDrive) {
                # Home Directory exists 
                Write-EventLog $global:logName -Source $global:logSourceName -EventId 337 -Message "User Account $($resourceForestUserObject.SamAccountName) ($($resourceForestUserObject.DisplayName)) has an existing Home Directory: $($existingUserHomeDirectoryDrive)" -EntryType Information
                Rename-Item $existingUserHomeDirectoryDrive $existingUserHomeDirectoryDrive.Replace($($resourceForestUserObject.SamAccountName), $newUserId) 
                # Save the Home Directory Path in a var for later usage
                $homeDirectoryDrive = $existingUserHomeDirectoryDrive.Replace('\' + $($resourceForestUserObject.SamAccountName), '')

            } else {
                # Home Directory doesn't exists, so we create a new one...
                Write-EventLog $global:logName -Source $global:logSourceName -EventId 337 -Message "User Account $($resourceForestUserObject.SamAccountName) ($($resourceForestUserObject.DisplayName)) has no Home Directory hence we'll create a new one" -EntryType Information
                $home_drive = $null
                $home_drive = Get-HomeDrive
                $homeDirectoryDrive = $home_drive.unc_path                
            }

            Set-UserHomeDirPermissions `
                -homeDirectoryPath $($homeDirectoryDrive) `
                -userPrincipalName $($resourceForestUserObject.SamAccountName) `
                -userPrincipalDomain $($env:USERDOMAIN) `
                -localAdminGroup "Administrators)"                                                                

            Write-EventLog $global:logName -Source $global:logSourceName -EventId 337 -Message "User Account $($resourceForestUserObject.SamAccountName) ($($resourceForestUserObject.DisplayName)) Home Directory Drive is: $($homeDirectoryDrive)" -EntryType Information
            
            try { 

                # Check if we have an existing DFS Directory
                $existingUserDfsTarget = $null
                $existingUserDfsTarget = Get-DfsnFolderTarget "$($dfsRootPath)\$($resourceForestUserObject.SamAccountName)" -ErrorAction SilentlyContinue

                if ($existingUserDfsTarget -eq $null) {
                    # DFS Directory doesn't exists, so we create a new one..
                    Write-EventLog $global:logName -Source $global:logSourceName -EventId 337 -Message "DFS Directory doesn't exists, so we create a new one for User Account $($resourceForestUserObject.SamAccountName) ($($resourceForestUserObject.DisplayName))" -EntryType Information
                    
                    try {
                        $dfs_path = Join-Path -Path $($dfsRootPath) -ChildPath $newUserId;
                        $dfs_target = Join-Path -Path $homeDirectoryDrive -ChildPath $newUserId;

                        New-DfsnFolderTarget -Path $dfs_path -TargetPath $dfs_target
                        Write-EventLog $global:logName -Source $global:logSourceName -EventId 337 -Message "New DFS Directory created for User Account $($newUserId) ($($resourceForestUserObject.DisplayName))" -EntryType Information
                    } catch [System.Exception] {
                        if ($_.Exception.InnerException) { $msg = $($_.Exception.InnerException.Message) } else { $msg = $($_.Exception.Message) }  
                        Write-EventLog $global:logName -Source $global:logSourceName -EventId 337 -Message "Failed creating DFS Directory $($dfs_path) for User Account $($newUserId) ($($resourceForestUserObject.DisplayName)): $msg " -EntryType Error                          	
                    }
                } else {
                
                    try { 
                        Remove-DfsnFolderTarget -Path $existingUserDfsTarget.Path -TargetPath $existingUserDfsTarget.TargetPath -Force
                    }
                    catch [System.Exception] {
                        if ($_.Exception.InnerException) { $msg = $($_.Exception.InnerException.Message) } else { $msg = $($_.Exception.Message) }  
                        Write-EventLog $global:logName -Source $global:logSourceName -EventId 337 -Message "Failed removing DFS Directory $($existingUserDfsTarget.Path) for User Account $($resourceForestUserObject.SamAccountName) ($($resourceForestUserObject.DisplayName)): $msg " -EntryType Error                          	
                    }

                    try { 
                        New-DfsnFolderTarget -Path (Join-Path -Path $($dfsRootPath) -ChildPath $newUserId) -TargetPath (Join-Path -Path $homeDirectoryDrive -ChildPath $($newUserId))
                    }
                    catch [System.Exception] {
                        if ($_.Exception.InnerException) { $msg = $($_.Exception.InnerException.Message) } else { $msg = $($_.Exception.Message) }  
                        Write-EventLog $global:logName -Source $global:logSourceName -EventId 337 -Message "Failed re-creating DFS Directory $($existingUserDfsTarget.Path) for User Account $($newUserId) ($($resourceForestUserObject.DisplayName)): $msg " -EntryType Error                          	
                    }
                }
            }
            catch [System.Exception] {
                if ($_.Exception.InnerException) { $msg = $($_.Exception.InnerException.Message) } else { $msg = $($_.Exception.Message) }  
                Write-EventLog $global:logName -Source $global:logSourceName -EventId 337 -Message "Failed getting DFS Folder "$($dfsRootPath)\$($resourceForestUserObject.SamAccountName) for User Account $($resourceForestUserObject.SamAccountName) ($($resourceForestUserObject.DisplayName))" : $msg " -EntryType Error                          	
            }
        }                                                                                            
    }
    catch [System.Exception] {
        if ($_.Exception.InnerException) { $msg = $($_.Exception.InnerException.Message) } else { $msg = $($_.Exception.Message) }  
        Write-EventLog $global:logName -Source $global:logSourceName -EventId 337 -Message "Failed getting DFS Root Domain Name: $msg " -EntryType Error                          	
    }
}
#>

function Get-ExistingUserHomeDirectoryDrive($samAccountName) {

    #------------------------------------
    $fs_server = @(
        'sv01005.ksbl.local'
    );
    #------------------------------------

    $home_targets = @();

    $fs_shares = @{};
    foreach ($server in $fs_server) {

        try {
            $fs_shares += @{ $server = @() };
            Get-WmiObject -class Win32_Share -Computer $server -Filter "Name like 'home[_][a-z]$'" | % {
                $fs_shares[$server] += @{ 'name' = $_.Name; 'path' = $_.Path }; }
        }
        catch {
([Exception])
            if ($_.Exception.InnerException) { $msg = $($_.Exception.InnerException.Message) } else { $msg = $($_.Exception.Message) }  	
            Write-EventLog $global:logName -Source $global:logSourceName -EventId 153 -Message "Error retrieving Get-WmiObject Win32_Share: $msg " -EntryType Error                  
        }                                                                                                
    }

    foreach ($server in $fs_shares.Keys) {

        foreach ($share in $fs_shares[$server]) {

            try {
                $disc = Get-WmiObject Win32_LogicalDisk -Filter "DeviceID='$($share.path.Substring(0, 2))'" -ComputerName $server;
            }
            catch {
([Exception])
                if ($_.Exception.InnerException) { $msg = $($_.Exception.InnerException.Message) } else { $msg = $($_.Exception.Message) }  	
                Write-EventLog $global:logName -Source $global:logSourceName -EventId 154 -Message "Error retrieving Get-WmiObject Win32_LogicalDisk for Device $($($share.path.Substring(0, 2))): $msg " -EntryType Error                  
            }                                                                                                

            $unc_path = Join-Path -Path ('\\' + $server) -ChildPath $share.name
            
            if (Test-Path $unc_path) {

                $existingHomeDrive = $null
                $existingHomeDrive = Get-ChildItem $unc_path | Where-Object { $_.PSIsContainer -eq $true -and $_.Name -match $samAccountName }

                if ($existingHomeDrive -ne $null) {
                    return $existingHomeDrive.FullName
                    break;
                }

            }
        }
    }

    return $null
}

function RenameDfsPathAndHomeDirectory($resourceForestUserObject, $newUserId) {
    
    try {
        $dfsRootPath = (Get-DfsnRoot -ErrorAction SilentlyContinue | Where-Object { $_.Path -like "*\HomeDrives" }).Path 

        if ($null -ne $($dfsRootPath)) {
            Write-EventLog $global:logName -Source $global:logSourceName -EventId 444 -Message "DFS Root Path: $dfsRootPath" -EntryType Information

            try { 

                # Check if we have an existing DFS Directory
                $existingUserDfsTarget = $null
                $existingUserDfsTarget = Get-DfsnFolderTarget "$($dfsRootPath)\$($resourceForestUserObject.SamAccountName)" -ErrorAction SilentlyContinue

                if (-not [string]::IsNullOrEmpty($existingUserDfsTarget)) {   

                    Write-EventLog $global:logName -Source $global:logSourceName -EventId 444 -Message "We have an existing DFS Entry ($($existingUserDfsTarget.Path) $($existingUserDfsTarget.TargetPath)) for User Account $($resourceForestUserObject.DisplayName)" -EntryType Information             

                    try { 
                        Remove-DfsnFolderTarget -Path $existingUserDfsTarget.Path -TargetPath $existingUserDfsTarget.TargetPath -Force
                        Write-EventLog $global:logName -Source $global:logSourceName -EventId 444 -Message "Successfully removed DFS Entry ($($existingUserDfsTarget.Path) $($existingUserDfsTarget.TargetPath)) for User Account $($resourceForestUserObject.DisplayName)" -EntryType Information             
                    } catch [System.Exception] {
                        if ($_.Exception.InnerException) { $msg = $($_.Exception.InnerException.Message) } else { $msg = $($_.Exception.Message) }  
                        Write-EventLog $global:logName -Source $global:logSourceName -EventId 444 -Message "Failed removing DFS Directory $($existingUserDfsTarget.Path) for User Account $($resourceForestUserObject.SamAccountName) ($($resourceForestUserObject.DisplayName)): $msg " -EntryType Error                          	
                    }

                    $newUserDfsTarget = $null
                    try { 
                        $newUserDfsTarget = New-DfsnFolderTarget -Path (Join-Path -Path $($dfsRootPath) -ChildPath $newUserId) -TargetPath $existingUserDfsTarget.TargetPath.Replace($($resourceForestUserObject.SamAccountName), $newUserId)
                        Write-EventLog $global:logName -Source $global:logSourceName -EventId 444 -Message "Successfully created new DFS Entry ($(Join-Path -Path $dfsRootPath -ChildPath $newUserId) $($existingUserDfsTarget.TargetPath.Replace($($resourceForestUserObject.SamAccountName), $newUserId)) for User Account $($resourceForestUserObject.DisplayName)" -EntryType Information             
                    } catch [System.Exception] {
                        if ($_.Exception.InnerException) { $msg = $($_.Exception.InnerException.Message) } else { $msg = $($_.Exception.Message) }  
                        Write-EventLog $global:logName -Source $global:logSourceName -EventId 444 -Message "Failed creating DFS Entry $(Join-Path -Path $dfsRootPath -ChildPath $newUserId) $($existingUserDfsTarget.TargetPath.Replace($($resourceForestUserObject.SamAccountName), $newUserId)) for User Account $($newUserId) ($($resourceForestUserObject.DisplayName)): $msg " -EntryType Error                          	
                    }

                    if (-not [string]::IsNullOrEmpty($newUserDfsTarget)) { 
                        try {
                            Set-ADUser $($resourceForestUserObject.SamAccountName) -HomeDirectory $newUserDfsTarget.Path
	                        Write-EventLog $global:logName -Source $global:logSourceName -EventId 444 -Message "Successfully changed AD HomeDirectory Attribute from $($existingUserDfsTarget.Path) to $($newUserDfsTarget.Path) for User Account $($resourceForestUserObject.DisplayName)" -EntryType Information
                        } catch {([Exception])
	                        if ($_.Exception.InnerException) { $msg = $($_.Exception.InnerException.Message) } else { $msg = $($_.Exception.Message) }  	
	                        Write-EventLog $global:logName -Source $global:logSourceName -EventId 444 -Message "Failed changing AD HomeDirectory Attribute from $($existingUserDfsTarget.Path) to $($newUserDfsTarget.Path) for User Account $($newUserId) ($($resourceForestUserObject.DisplayName)): $msg " -EntryType Error                  
                        } 

                        try {
                            if (Test-path -Path $existingUserDfsTarget.TargetPath) {
                                Rename-Item $existingUserDfsTarget.TargetPath $newUserDfsTarget.TargetPath 
                                Write-EventLog $global:logName -Source $global:logSourceName -EventId 444 -Message "Successfully renamed existing Home-Directory $($existingUserDfsTarget.TargetPath) to $($newUserDfsTarget.TargetPath) for User Account $($resourceForestUserObject.DisplayName)" -EntryType Information
                            }
                        } catch [System.Exception] {
                            if ($_.Exception.InnerException) { $msg = $($_.Exception.InnerException.Message) } else { $msg = $($_.Exception.Message) }  
                            Write-EventLog $global:logName -Source $global:logSourceName -EventId 444 -Message "Failed renaming Home Directory $($existingUserDfsTarget.TargetPath) to $($newUserDfsTarget.TargetPath) for User Account $($resourceForestUserObject.SamAccountName) ($($resourceForestUserObject.DisplayName)): $msg " -EntryType Error                          	
                        }
                    } else {
                        Write-EventLog $global:logName -Source $global:logSourceName -EventId 444 -Message "Failed renaming AD HomeDirectory Attribute $($existingUserDfsTarget.Path) and Home-Directory File-System $($existingUserDfsTarget.TargetPath). While creating the new DFS Entry, newUserDfsTarget returned NULL for User Account$($resourceForestUserObject.SamAccountName) ($($resourceForestUserObject.DisplayName))" -EntryType Error                          	
                    }

                }
            } catch [System.Exception] {
                if ($_.Exception.InnerException) { $msg = $($_.Exception.InnerException.Message) } else { $msg = $($_.Exception.Message) }  
                Write-EventLog $global:logName -Source $global:logSourceName -EventId 444 -Message "Failed getting DFS Folder "$($dfsRootPath)\$($resourceForestUserObject.SamAccountName) for User Account $($resourceForestUserObject.SamAccountName) ($($resourceForestUserObject.DisplayName))" : $msg " -EntryType Error                          	
            }

        }                                                                                            
    } catch [System.Exception] {
        if ($_.Exception.InnerException) { $msg = $($_.Exception.InnerException.Message) } else { $msg = $($_.Exception.Message) }  
        Write-EventLog $global:logName -Source $global:logSourceName -EventId 444 -Message "Failed getting DFS Root Domain Name: $msg " -EntryType Error                          	
    }
}

function Set-TenantState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [Microsoft.ActiveDirectory.Management.ADUser] $User,

        [Parameter(Mandatory=$true)]
        [ValidateSet("TenantEnable","TenantDisable")]
        [string] $Mode,

        [Parameter(Mandatory=$true)]
        [string] $CloudDomain
    )

    # AD Attribute
    $Attr_EntraFlag     = "msDS-cloudExtensionAttribute15"
    $Attr_DisableMarker = "extensionAttribute6"

    $dn   = $User.DistinguishedName
    $mail = $User.mail

    switch ($Mode) {

        "TenantEnable" {

            if (-not ($mail -and $mail -match "@")) {
                throw "User $($User.SamAccountName): Ungueltiges oder fehlendes mail-Attribut."
            }

            # Cloud-Proxyadresse generieren
            $localPart  = $mail.Split("@")[0].ToLower()
            $cloudProxy = "smtp:$localPart@$CloudDomain"

            # Proxy-Adresse hinzufügen
            if ($User.proxyAddresses -notcontains $cloudProxy) {
                Set-ADUser -Identity $dn -Add @{ proxyAddresses = $cloudProxy }
            }

            # Entra-Attribute setzen
            Set-ADUser -Identity $dn -Replace @{
                $Attr_EntraFlag     = "EntraEnabled"
                $Attr_DisableMarker = "EntraDisable"
            }
        }

        "TenantDisable" {

            # Attribute löschen
            Set-ADUser -Identity $dn -Clear $Attr_EntraFlag, $Attr_DisableMarker
        }
    }
}


cls

$ErrorActionPreference = "stop"

$smtpHost = "relay.ksbl.local"
$mailFrom = "informatik@ksbl.ch"
$mailCc = "ksbl.vl.iam-administrators@ksbl.ch"
#$mailCc = "sascha.affolter@ksbl.ch"

$jobsToProcess = $null
$workingPath = "D:\IAM\queue"

$global:exchAdminGroupDn = "CN=Exchange Administrative Group (FYDIBOHF23SPDLT),CN=Administrative Groups,CN=KSBL,CN=Microsoft Exchange,CN=Services,$(([ADSI]”LDAP://rootdse”).ConfigurationNamingContext)"
$global:defaultMailboxDbs = $null
$global:defaultMailboxDbs = (New-Object System.DirectoryServices.DirectorySearcher([ADSI]"LDAP://CN=Databases,$($global:exchAdminGroupDn)", "(&(objectClass=msExchPrivateMDB)(!(name=MAILDB-NODAG))(!name=maildb101)(!name=maildb102)(!name=maildb103)(!name=Mailbox Database*)(!name=maildb*))", @('name'))).FindAll() | ForEach-Object { $_.Path.Split(',')[0].Split('=')[1] } 
#$global:defaultMailboxDbs = @("MAILDB05","MAILDB07","MAILDB06","MAILDB08","MAILDB09","MAILDB11","MAILDB13","MAILDB15","MAILDB10","MAILDB12","MAILDB14","MAILDB16")

$applicationDirectoryShare = "\\sv00213\Appdata$"
$desktopDirectoryShare = "\\sv00213\desktop$"
$UserProfileDirectoryShares =  @('\\sv00701\UserProfiles$', '\\sv00702\UserProfiles$')
$homeDirectory = "\\ksbl.local\HomeDrives"
$homeDirectoryDrive = "Z:"

$global:internalUserOu = "OU=Internal,OU=_Users,DC=ksbl,DC=local"
$global:externalUserOu = "OU=External,OU=_Users,DC=ksbl,DC=local"
$targetDomainOu = "OU=Generics,OU=_Users,DC=ksbl,DC=local"

$pshUser = "ksbl\ServiceIAMJobs10"
$pshSecret = "D:\iam\Secrets\serviceiamjobs10.sec"

$cloudDomain = "kantonsspitalbl.mail.onmicrosoft.com"

$global:logname = "KSBL Helpdesk GUI"
$global:logSourceName = "Process-UserGeneric"
#[System.Diagnostics.EventLog]::CreateEventSource($global:logSourceName, $global:logname)

try {
    $dc = [System.DirectoryServices.ActiveDirectory.Domain]::GetCurrentDomain().RidRoleOwner.Name
} 
catch {([Exception])
	if ($_.Exception.InnerException) { $msg = $($_.Exception.InnerException.Message) } else { $msg = $($_.Exception.Message) }  	
	Write-EventLog $global:logName -Source $global:logSourceName -EventId 400 -Message "Error retrieving RidRoleOwner Domain-Controller from Active-Directory: $msg " -EntryType Error                  
    Exit
}

try {
    if ((Get-PSSession | ? {$_.State -like "Opened" -and $_.Availability -like "Available"}) -eq $null) {
        $cred = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $pshUser , (Get-Content $pshSecret | ConvertTo-SecureString) 
        $PSSession = new-pssession –configurationname Microsoft.Exchange –connectionuri http://sv00516.ksbl.local/PowerShell –credential $Cred -Authentication Kerberos 
        Import-PSSession $PSSession -AllowClobber
    }
} 
catch {([Management.Automation.Remoting.PSRemotingTransportException],[Exception])
	if ($_.Exception.InnerException) { $msg = $($_.Exception.InnerException.Message) } else { $msg = $($_.Exception.Message) }  	
	Write-EventLog $global:logName -Source $global:logSourceName -EventId 500 -Message "Exit Script! Error creating a new Remote Exchange Powershell Connection: $msg " -EntryType Error                  
    Exit
}

try {
    Import-Module DFSN
}
catch {
([Exception])
    if ($_.Exception.InnerException) { $msg = $($_.Exception.InnerException.Message) } else { $msg = $($_.Exception.Message) }  	
    Write-EventLog $global:logName -Source $global:logSourceName -EventId 200 -Message "Error loading DFSN PowerShell Modules: $msg " -EntryType Error                  
}

$filesToProcess = Get-ChildItem $workingPath | Where-Object { ( $_.Name -like "*RenameUserAccount*_pshjob_.csv") }  | Sort-Object LastWriteTime

foreach ($jobToProcess in $filesToProcess) {

    if ($Host.Name -eq "ConsoleHost") {
        $ErrorActionPreference="SilentlyContinue"
        Stop-Transcript | out-null
        $ErrorActionPreference = "Continue"
        Start-Transcript -path "D:\IAM\Transcripts\Transcript_$($jobToProcess.Name).log" -append
    }

    $workingFile = Import-csv $($jobToProcess.FullName) -Delimiter "|" 
    foreach ($workingFileEntry in $workingFile) {

        if ($($workingFileEntry.ActionType) -ne $null -and 
            $($workingFileEntry.AdObjectName) -ne $null -and 
            $($workingFileEntry.GivenName) -ne $null -and 
            $($workingFileEntry.SurName) -ne $null -and 
            $($workingFileEntry.NewPrimaryEMailAddress) -ne $null -and 
            $($workingFileEntry.CurrentUserName) -ne $null -and 
            $($workingFileEntry.CurrentUserDomainName) -ne $null -and
            $($workingFileEntry.CurrentUserEMailAddress) -ne $null) {

            $msg = $null
            $htmlBody  = $null
            $htmlBody = "<p style=""Color:Black;font-weight:normal;Font-Size:smaller;font-family:Tahoma"">"
            $htmlBody += "Lieber Mitarbeiter, <br/><br/>"

            $surName = $($workingFileEntry.SurName)
            $givenName = $($workingFileEntry.GivenName)
            $newUserId = $($workingFileEntry.NewUserId)
            $currentUserId = $($workingFileEntry.AdObjectName)
            $newPrimaryEMail = $($workingFileEntry.NewPrimaryEMailAddress)
            $userGuid = (Get-ADUser $currentUserId).ObjectGUID.Guid
            $msg = $null

            try {
                $renamedUserObject = Get-ADUser $userGuid -Server $dc -Properties mail,displayName,sn,memberof,msExchMailboxGuid,extensionattribute11,homeDirectory
            } 
            catch {([Exception])
	            if ($_.Exception.InnerException) { $msg = $($_.Exception.InnerException.Message) } else { $msg = $($_.Exception.Message) }  
	            Write-EventLog $global:logName -Source $global:logSourceName -EventId 1000 -Message "Error getting User $($workingFileEntry.AdObjectName) from Active-Directory: $msg " -EntryType Error                  
            }

            if ($newUserId -ne $currentUserId -and $newUserId -ne "skip") {
                
                $nextAvailableSamAccountName = $null
                if ($($newUserId).StartsWith("us") -eq $true) {
                    $nextAvailableSamAccountName = Get-NextAvailableSamAccountName -localForestDomainController $dc -employeeType ([EmployeeType]::INTERNAL)
                    if ($nextAvailableSamAccountName -ne $($newUserId)) {
                        try {
                            Invoke-Sqlcmd -Query "UPDATE [KSBL_IAM].[dbo].[Configuration] SET [InternalUserId] = '$nextAvailableSamAccountName' WHERE Id = 1" -ServerInstance $dbServer
                        } 
                        catch {([Exception])
	                        if ($_.Exception.InnerException) { $msg = $($_.Exception.InnerException.Message) } else { $msg = $($_.Exception.Message) }  	
	                        Write-EventLog $global:logName -Source $global:logSourceName -EventId 1000 -Message "Error updating SQL Configuration for User $($workingFileEntry.AdObjectName) from Active-Directory: $msg " -EntryType Error                  
                        }                        
                    }
                } else {
                    $nextAvailableSamAccountName = Get-NextAvailableSamAccountName -localForestDomainController $dc -employeeType ([EmployeeType]::EXTERNAL)
                    if ($nextAvailableSamAccountName -ne $($newUserId)) {
                        try {
                            Invoke-Sqlcmd -Query "UPDATE [KSBL_IAM].[dbo].[Configuration] SET [ExternalUserId] = '$nextAvailableSamAccountName' WHERE Id = 1" -ServerInstance $dbServer
                        } 
                        catch {([Exception])
	                        if ($_.Exception.InnerException) { $msg = $($_.Exception.InnerException.Message) } else { $msg = $($_.Exception.Message) }  	
	                        Write-EventLog $global:logName -Source $global:logSourceName -EventId 1000 -Message "Error updating SQL Configuration for User $($workingFileEntry.AdObjectName) from Active-Directory: $msg " -EntryType Error                  
                        }                        
                    }
                }
                
                if ($nextAvailableSamAccountName -ne $($newUserId)) {
                    $newUserId = $nextAvailableSamAccountName
                }
                
                if(-not [string]::IsNullOrEmpty($renamedUserObject.HomeDirectory)) {    
                    RenameDfsPathAndHomeDirectory -resourceForestUserObject $renamedUserObject -newUserId $newUserId                
                } else {
                    Write-EventLog $global:logName -Source $global:logSourceName -EventId 1000 -Message "$($action.ToString()) für tr $($person.id): $($Person.name), $($Person.vorname), Personalnummer $($person.Personalnummer): HomeDrive nicht gefunden." -EntryType Warning                  
                    Write-Host "$($action.ToString()) für tr $($person.id): $($Person.name), $($Person.vorname), Personalnummer $($person.Personalnummer): HomeDrive nicht gefunden." -ForegroundColor Yellow
                }

                $appShare = "$applicationDirectoryShare\$currentUserId" 
                $deskShare = "$desktopDirectoryShare\$currentUserId"

                try {
                    if((test-path $appShare) -eq $true) {
                        Rename-Item $appShare -NewName $newUserId -Force
                    }
                } catch [System.Exception] {
                    if ($_.Exception.InnerException) { $msg = $($_.Exception.InnerException.Message) } else { $msg = $($_.Exception.Message) }
                    Write-EventLog $global:logName -Source $global:logSourceName -EventId 1000 -Message "Error renaming User $($workingFileEntry.AdObjectName) App-Path: $msg " -EntryType Error
                    $htmlBody += "Während dem Umbenennen des App-Path für den Benutzer <b> $currentUserId </b> ist folgender Fehler aufgetreten: <b> $msg </b><br/><br/>"
                }

                try {
                    if((test-path $deskShare) -eq $true) {
                        Rename-Item $deskShare -NewName $newUserId -Force
                    }
                } catch [System.Exception] {
                    if ($_.Exception.InnerException) { $msg = $($_.Exception.InnerException.Message) } else { $msg = $($_.Exception.Message) }
                    Write-EventLog $global:logName -Source $global:logSourceName -EventId 1000 -Message "Error renaming User $($workingFileEntry.AdObjectName) Desktop-Path: $msg " -EntryType Error
                    $htmlBody += "Während dem Umbenennen des Desktop-Path für den Benutzer <b> $currentUserId </b> ist folgender Fehler aufgetreten: <b> $msg </b><br/><br/>"
                }

                foreach ($userProfileDirectoryShare in $UserProfileDirectoryShares) {                    
                    
                    $profileShare = "$($userProfileDirectoryShare)\$($currentUserId)_$($renamedUserObject.SID.Value)"
                    
                    try {
                        Get-ChildItem $profileShare -Exclude *.lock | Rename-Item -NewName {$_.Name -replace $currentUserId,$newUserId}
                    } catch [System.Exception] {
                        if ($_.Exception.InnerException) { $msg = $($_.Exception.InnerException.Message) } else { $msg = $($_.Exception.Message) }
                        Write-EventLog $global:logName -Source $global:logSourceName -EventId 1000 -Message "Error renaming Users $($workingFileEntry.AdObjectName) Profile-Path Files $((Get-ChildItem $profileShare -Exclude *.lock).Name -join ''): $msg " -EntryType Error
                        $htmlBody += "Während dem Umbenennen der Dateien $((Get-ChildItem $profileShare -Exclude *.lock).Name -join '') im Profile-Pfad $($profileShare) für den Benutzer <b> $currentUserId </b> ist folgender Fehler aufgetreten: <b> $msg </b><br/><br/>"
                    }
                    
                    try {
                        if((test-path $profileShare) -eq $true) {
                            Rename-Item $profileShare -NewName "$($newUserId)_$($renamedUserObject.SID.Value)" -Force
                        }
                    } catch [System.Exception] {
                        if ($_.Exception.InnerException) { $msg = $($_.Exception.InnerException.Message) } else { $msg = $($_.Exception.Message) }
                        Write-EventLog $global:logName -Source $global:logSourceName -EventId 1000 -Message "Error renaming Users $($workingFileEntry.AdObjectName) Profile-Path $($profileShare): $msg " -EntryType Error
                        $htmlBody += "Während dem Umbenennen des Profile-Pfades $($profileShare) für den Benutzer <b> $currentUserId </b> ist folgender Fehler aufgetreten: <b> $msg </b><br/><br/>"
                    }
                }

                try {
                    Rename-ADObject -identity $userGuid -NewName $newUserId -Server $dc
                    Start-Sleep -Seconds 30 

                    $samAccountName = $newUserId     
                              
                    try {
                        Set-ADUser $userGuid -replace @{"kisAccountName"=$($newUserId)} -Server $dc
                        Write-EventLog $global:logName -Source $global:logSourceName -EventId 448 -Message "Successfully set kisAccountName $($newUserId) for User $($workingFileEntry.TargetAdObjectName)" -EntryType Information
                    } catch [System.Exception] {
                        if ($_.Exception.InnerException) { $msg = $($_.Exception.InnerException.Message) } else { $msg = $($_.Exception.Message) }
                        Write-EventLog $global:logName -Source $global:logSourceName -EventId 1000 -Message "Error setting kisAccountName $($newUserId) for User $($workingFileEntry.TargetAdObjectName): $msg " -EntryType Error                  
                    }                               

                    try {
                        Set-ADUser $userGuid -SamAccountName $samAccountName -Server $dc -UserPrincipalName (Get-ADUser $userGuid).UserPrincipalName.Replace($currentUserId,$samAccountName)
                    } 
                    catch {([Exception])
	                    if ($_.Exception.InnerException) { $msg = $($_.Exception.InnerException.Message) } else { $msg = $($_.Exception.Message) }  	
	                    Write-EventLog $global:logName -Source $global:logSourceName -EventId 1000 -Message "Error setting new UserPrincipalName, HomeDirectory and SamAccountName for User $($workingFileEntry.AdObjectName) from Active-Directory: $msg " -EntryType Error                  
                    }                                   

                } catch [System.Exception] {
                    if ($_.Exception.InnerException) { $msg = $($_.Exception.InnerException.Message) } else { $msg = $($_.Exception.Message) }
                    Write-EventLog $global:logName -Source $global:logSourceName -EventId 1000 -Message "Error renaming User $($currentUserId) Desktop-Path: $msg " -EntryType Error
                    Write-Host "While renaming user $currentUserId, the following error occurred: $msg" -ForegroundColor Red
                    $htmlBody += "Während dem Umbenennen des AD Benutzerkontos <b> $currentUserId </b> ist folgender Fehler aufgetreten: <b> $msg </b><br/><br/>"
                }

            } else {
                $samAccountName = $currentUserId
            }

            try {
                $mbx = Get-Mailbox $userGuid -ErrorAction SilentlyContinue
            } 
            catch {([Exception])
	            if ($_.Exception.InnerException) { $msg = $($_.Exception.InnerException.Message) } else { $msg = $($_.Exception.Message) }  	
	            Write-EventLog $global:logName -Source $global:logSourceName -EventId 1000 -Message "Error getting Mailbox for User $userGuid from Exchange: $msg " -EntryType Error                  
            }


            if ($mbx -ne $null) {

                $msg = $null

                if ($newUserId -ne $currentUserId) {
                    try {
                        Set-ADUser $userGuid -Replace @{"MailNickname"=$samAccountName}
                    }
                    catch [System.Exception] {
                        if ($_.Exception.InnerException) { $msg = $($_.Exception.InnerException.Message) } else { $msg = $($_.Exception.Message) }
                        Write-EventLog $global:logName -Source $global:logSourceName -EventId 1000 -Message "Error setting new MailNickname for User $($workingFileEntry.AdObjectName): $msg " -EntryType Error                  
                        $htmlBody += "Während dem Modifizieren des Attributes 'MailNickname' auf dem Postfach <b> $($mbx.DisplayName) </b> ist folgender Fehler aufgetreten: <b> $($msg) </b><br/><br/>"                     
                    }
                }

                if ($surName -ne $renamedUserObject.Surname) {
                    Write-Host "Updating PersonMailbox $($mbx.DisplayName) with new E-Mail $newPrimaryEMail as $samAccountName"

                    $currentAddress = $mbx | select PrimarySmtpAddress
                    $currentAddress = "$($currentAddress.PrimarySmtpAddress.Local)@$($currentAddress.PrimarySmtpAddress.Domain)"

                    if ($currentAddress -ne $null) {
                   
                        try {
                            Set-Mailbox -Identity $userGuid -PrimarySmtpAddress $newPrimaryEMail -EmailAddressPolicyEnabled $false 
                        }
                        catch [System.Exception] {
                            if ($_.Exception.InnerException) { $msg = $($_.Exception.InnerException.Message) } else { $msg = $($_.Exception.Message) }
                            Write-EventLog $global:logName -Source $global:logSourceName -EventId 1000 -Message "Error setting new PrimarySmtpAddress for User $($workingFileEntry.AdObjectName): $msg " -EntryType Error                  
                            $htmlBody += "Während dem Modifizieren des Attributes 'PrimarySmtpAddress' auf dem Postfach <b> $($mbx.DisplayName) </b> ist folgender Fehler aufgetreten: <b> $($msg) </b><br/><br/>"                     
                        }

                        try {
                            Set-Mailbox -Identity $userGuid -DisplayName "$($workingFileEntry.SurName) $($workingFileEntry.GivenName)"
                        }
                        catch [System.Exception] {
                            if ($_.Exception.InnerException) { $msg = $($_.Exception.InnerException.Message) } else { $msg = $($_.Exception.Message) }
                            Write-EventLog $global:logName -Source $global:logSourceName -EventId 1000 -Message "Error setting new DisplayName for User $($workingFileEntry.AdObjectName): $msg " -EntryType Error                  
                            $htmlBody += "Während dem Modifizieren des Attributes 'DisplayName' auf dem Postfach <b> $($mbx.DisplayName) </b> ist folgender Fehler aufgetreten: <b> $($msg) </b><br/><br/>"                     
                        }

                        try {
                            Set-ADUser -Identity $userGuid -Surname $($workingFileEntry.SurName) -GivenName $($workingFileEntry.GivenName)
                        }
                        catch [System.Exception] {
                            if ($_.Exception.InnerException) { $msg = $($_.Exception.InnerException.Message) } else { $msg = $($_.Exception.Message) }
                            Write-EventLog $global:logName -Source $global:logSourceName -EventId 1000 -Message "Error setting new Surname/Givenname for User $($workingFileEntry.AdObjectName): $msg " -EntryType Error                  
                            $htmlBody += "Während dem Modifizieren des Attributes 'Surname GivenName' auf dem Active-Directory Objekt <b> $($mbx.DisplayName) </b> ist folgender Fehler aufgetreten: <b> $($msg) </b><br/><br/>"                     
                        }

                        if ($msg -eq $null) {
                            $htmlBody += "Der Benutzer <b> $($renamedUserObject.DisplayName) </b> wurde erfolgreich umbenennt.<br/><br/>"                
                        }

                    }

                } else {                
                    if ($msg -eq $null) {
                        $htmlBody += "Der Benutzer <b> $($renamedUserObject.DisplayName) </b> wurde erfolgreich umbenennt.<br/><br/>"                
                    }
                }
                                                   
            }
            
            $htmlBody += "Viele Grüsse vom E-Mail Team</p>"
                
            Send-EMail -smtpHost $smtpHost -mailFrom $mailFrom -mailTo $($workingFileEntry.CurrentUserEMailAddress) -mailCc $mailCc -mailSubject "*** Auftrag - Namensänderung eines Benutzerkontos/Personenmailbox ***" -mailBody $htmlBody -attachment $null                            

            if ($currentUserId -eq $newUserId) {

                if ($sendMailToCustomer -eq $true) {

                    $htmlBody = "<html><style type=""text/css"">
                                    body {
                                        background: #FFFFFF none repeat scroll 0 0;
                                        color: #333333;
                                        font-family: Verdana,Arial,Helvetica,sans-serif;
                                        font-size: 0.8em;
                                        margin: 0 10px 10px;
                                        padding: 0;
                                        text-align: left;
                                    }
            
                                    p {
                                        border: 0 none;
                                        font-family: Verdana,Arial,Helvetica,sans-serif;
                                        line-height: 130%;
                                        margin: 0;
                                        padding: 0 0 10px;
                                        font-size: 0.8em;
                                    }

                                    h3 {
                                        color: #634329;
                                        font-family: Verdana,Arial,Helvetica,sans-serif;
                                        font-size: 1.5em;
                                    }
                                </style><body>"

                    $htmlBody += "Geschätzte Mitarbeiterin und Mitarbeiter<br />"
                    $htmlBody += "Sehr geehrte Damen und Herren<br /><br />"
                    $htmlBody += "Aufgrund des Antrages zur Änderung Ihres Nachnamens möchten wir Sie mit diesem E-Mail gerne darüber informieren, dass Ihre E-Mails Adresse auf $($newPrimaryEMail) geändert wurde. "
                    $htmlBody += "Die alte E-Mail Adresse $($currentAddress) bleibt bestehen so dass Sie weiterhin E-Mails darüber empfangen können.<br /><br />"
                    $htmlBody += "Mit freundlichen Grüssen<br />"
                    $htmlBody += "<a href=""mailto:ksbl.it-infrastruktur@ksbl.ch"">IT-Infrastruktur</a>"
                    $htmlBody += "</body></html>"

                    Send-EMail -smtpHost $smtpHost -mailFrom $mailFrom -mailTo $($newPrimaryEMail) -mailCc $mailCc -mailSubject "*** Namensänderung und Änderung E-Mail Adresse ***" -mailBody $htmlBody -attachment $null                            
                    
                }
            
            }

        }
    }

    if ($Host.Name -eq "ConsoleHost") {
        Stop-Transcript
    }

    Move-Item $($jobToProcess.FullName) "D:\IAM\Archive\$($jobToProcess.Name)" -Force -Confirm:$false
}

$filesToProcess = Get-ChildItem -Recurse -Force $workingPath -ErrorAction SilentlyContinue | Where-Object { ( $_.Name -like "*ChangeAccountSurname*_pshjob_.csv") }

foreach ($jobToProcess in $filesToProcess) {

    if ($Host.Name -eq "ConsoleHost") {
        $ErrorActionPreference="SilentlyContinue"
        Stop-Transcript | out-null
        $ErrorActionPreference = "Continue"
        Start-Transcript -path "D:\IAM\Transcripts\Transcript_$($jobToProcess.Name).log" -append
    }

    $workingFile = Import-csv $($jobToProcess.FullName) -Delimiter "|" 
    foreach ($workingFileEntry in $workingFile) {

        if ($($workingFileEntry.ActionType) -ne $null -and 
            $($workingFileEntry.AdObjectName) -ne $null -and 
            $($workingFileEntry.GivenName) -ne $null -and 
            $($workingFileEntry.SurName) -ne $null -and 
            $($workingFileEntry.NewPrimaryEMailAddress) -ne $null -and 
            $($workingFileEntry.CurrentUserName) -ne $null -and 
            $($workingFileEntry.CurrentUserDomainName) -ne $null -and
            $($workingFileEntry.CurrentUserEMailAddress) -ne $null) {
            

            $msg = $null
            $htmlBody  = $null
            $htmlBody = "<p style=""Color:Black;font-weight:normal;Font-Size:smaller;font-family:Tahoma"">"
            $htmlBody += "Lieber Mitarbeiter, <br/><br/>"

            $surName = $($workingFileEntry.SurName)
            $givenName = $($workingFileEntry.GivenName)
            $newPrimaryEMail = $($workingFileEntry.NewPrimaryEMailAddress)

            try {
                $mbx = Get-Mailbox $($workingFileEntry.AdObjectName)
            } 
            catch {([Exception])
	            if ($_.Exception.InnerException) { $msg = $($_.Exception.InnerException.Message) } else { $msg = $($_.Exception.Message) }  	
	            Write-EventLog $global:logName -Source $global:logSourceName -EventId 1000 -Message "Error getting Mailbox for User $($workingFileEntry.AdObjectName) from Exchange: $msg " -EntryType Error                  
            }

            if ($mbx -ne $null) {

                #$Error.Clear()
                $msg = $null

                Write-Host "Updating PersonMailbox $($mbx.DisplayName) with new E-Mail $newPrimaryEMail as $($workingFileEntry.AdObjectName)"

                $currentAddress = $mbx | select PrimarySmtpAddress
                $currentAddress = "$($currentAddress.PrimarySmtpAddress.Local)@$($currentAddress.PrimarySmtpAddress.Domain)"

                if ($currentAddress -ne $null) {

                    try {
                        Set-Mailbox -Identity $($workingFileEntry.AdObjectName) -PrimarySmtpAddress $newPrimaryEMail -EmailAddressPolicyEnabled $false 
                    }
                    catch [System.Exception] {
                        if ($_.Exception.InnerException) { $msg = $($_.Exception.InnerException.Message) } else { $msg = $($_.Exception.Message) }
                        Write-EventLog $global:logName -Source $global:logSourceName -EventId 1000 -Message "Error setting new PrimarySmtpAddress for User $($workingFileEntry.AdObjectName): $msg " -EntryType Error                  
                        $htmlBody += "Während dem Modifizieren des Attributes 'PrimarySmtpAddress' auf dem Postfach <b> $($mbx.DisplayName) </b> ist folgender Fehler aufgetreten: <b> $($msg) </b><br/><br/>"                     
                    }

                    try {
                        Set-Mailbox -Identity $($workingFileEntry.AdObjectName) -DisplayName "$($workingFileEntry.SurName) $($workingFileEntry.GivenName)"
                    }
                    catch [System.Exception] {
                        if ($_.Exception.InnerException) { $msg = $($_.Exception.InnerException.Message) } else { $msg = $($_.Exception.Message) }
                        Write-EventLog $global:logName -Source $global:logSourceName -EventId 1000 -Message "Error setting new DisplayName for User $($workingFileEntry.AdObjectName): $msg " -EntryType Error                  
                        $htmlBody += "Während dem Modifizieren des Attributes 'DisplayName' auf dem Postfach <b> $($mbx.DisplayName) </b> ist folgender Fehler aufgetreten: <b> $($msg) </b><br/><br/>"                     
                    }

                    try {
                        Set-ADUser -Identity $($workingFileEntry.AdObjectName) -Surname $($workingFileEntry.SurName) -GivenName $($workingFileEntry.GivenName)
                    }
                    catch [System.Exception] {
                        if ($_.Exception.InnerException) { $msg = $($_.Exception.InnerException.Message) } else { $msg = $($_.Exception.Message) }
                        Write-EventLog $global:logName -Source $global:logSourceName -EventId 1000 -Message "Error setting new Surname/Givenname for User $($workingFileEntry.AdObjectName): $msg " -EntryType Error                  
                        $htmlBody += "Während dem Modifizieren des Attributes 'Surname GivenName' auf dem Active-Directory Objekt <b> $($mbx.DisplayName) </b> ist folgender Fehler aufgetreten: <b> $($msg) </b><br/><br/>"                     
                    }

                    try {
                        Get-ADUser -Identity $($workingFileEntry.AdObjectName) -Properties employeeType | Set-ADUser -Replace @{employeeType="P"}
                    }
                    catch [System.Exception] {
                        if ($_.Exception.InnerException) { $msg = $($_.Exception.InnerException.Message) } else { $msg = $($_.Exception.Message) }
                        Write-EventLog $global:logName -Source $global:logSourceName -EventId 1000 -Message "Error setting new EmployeeType for User $($workingFileEntry.AdObjectName): $msg " -EntryType Error                  
                        $htmlBody += "Während dem Modifizieren des Attributes 'employeeType' auf dem Active-Directory Objekt <b> $($mbx.DisplayName) </b> ist folgender Fehler aufgetreten: <b> $($msg) </b><br/><br/>"                     
                    }

                    try {
                        $mbx = Get-Mailbox $($workingFileEntry.AdObjectName)
                    } 
                    catch {([Exception])
	                    if ($_.Exception.InnerException) { $msg = $($_.Exception.InnerException.Message) } else { $msg = $($_.Exception.Message) }  	
                        Write-EventLog $global:logName -Source $global:logSourceName -EventId 1000 -Message "Error getting Mailbox for User $($workingFileEntry.AdObjectName) from Exchange: $msg " -EntryType Error                  
                    }

                    if ($msg -eq $null) {

                        Write-Host "Successfully changed mailbox $($mbx.DisplayName) primary SMTP address from $currentAddress to $newPrimaryEMail" -ForegroundColor Green
                        $htmlBody += "Das Postfach <b> $($mbx.DisplayName) </b> mit der E-Mail $newPrimaryEMail und Login Name $($workingFileEntry.AdObjectName) wurde erfolgreich geändert.<br/><br/>"                
                    }
                    
                    $htmlBody += "Viele Grüsse vom E-Mail Team</p>"
                        
                    #$ds = New-Object System.DirectoryServices.DirectorySearcher([ADSI]"LDAP://$dc", "(samaccountname=$($workingFileEntry.CurrentUserName))", @('mail'))
                    #$currentUser = $ds.FindOne()
                        
                    #if ($currentUser -ne $null) {
                    #    if ($currentUser.Properties["mail"][0] -ne $null) {
                            Send-EMail -smtpHost $smtpHost -mailFrom $mailFrom -mailTo $($workingFileEntry.CurrentUserEMailAddress) -mailCc $mailCc -mailSubject "*** Auftrag - Namensänderung einer Personenmailbox ***" -mailBody $htmlBody -attachment $null                            
                    #    }

                    #}

                    if ($sendMailToCustomer -eq $true) {

                        $htmlBody = "<html><style type=""text/css"">
                                        body {
	                                        background: #FFFFFF none repeat scroll 0 0;
	                                        color: #333333;
	                                        font-family: Verdana,Arial,Helvetica,sans-serif;
	                                        font-size: 0.8em;
	                                        margin: 0 10px 10px;
	                                        padding: 0;
	                                        text-align: left;
                                        }
					
                                        p {
	                                        border: 0 none;
	                                        font-family: Verdana,Arial,Helvetica,sans-serif;
	                                        line-height: 130%;
	                                        margin: 0;
	                                        padding: 0 0 10px;
	                                        font-size: 0.8em;
                                        }

                                        h3 {
	                                        color: #634329;
	                                        font-family: Verdana,Arial,Helvetica,sans-serif;
	                                        font-size: 1.5em;
                                        }
                                    </style><body>"

                        $htmlBody += "Geschätzte Mitarbeiterin und Mitarbeiter<br />"
                        $htmlBody += "Sehr geehrte Damen und Herren<br /><br />"
                        $htmlBody += "Aufgrund des Antrages zur Änderung Ihres Nachnamens möchten wir Sie mit diesem E-Mail gerne darüber informieren, dass Ihre E-Mails Adresse auf $($newPrimaryEMail) geändert wurde. "
                        $htmlBody += "Die alte E-Mail Adresse $($currentAddress) bleibt bestehen so dass Sie weiterhin E-Mails darüber empfangen können.<br /><br />"
                        $htmlBody += "Mit freundlichen Grüssen<br />"
                        $htmlBody += "<a href=""mailto:ksbl.it-infrastruktur@ksbl.ch"">IT-Infrastruktur</a>"
                        $htmlBody += "</body></html>"

                        Send-EMail -smtpHost $smtpHost -mailFrom $mailFrom -mailTo $($newPrimaryEMail) -mailCc $mailCc -mailSubject "*** Namensänderung und Änderung E-Mail Adresse ***" -mailBody $htmlBody -attachment $null                            
                            
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

$filesToProcess = Get-ChildItem -Recurse -Force $workingPath -ErrorAction SilentlyContinue | Where-Object { ( $_.Name -like "*DisableNonStdPersonMailbox*_pshjob_.csv" -or $_.Name -like "*EnableNonStdPersonMailbox*_pshjob_.csv") }

foreach ($jobToProcess in $filesToProcess) {

    if ($Host.Name -eq "ConsoleHost") {
        $ErrorActionPreference="SilentlyContinue"
        Stop-Transcript | out-null
        $ErrorActionPreference = "Continue"
        Start-Transcript -path "D:\IAM\Transcripts\Transcript_$($jobToProcess.Name).log" -append
    }

    $workingFile = Import-csv $($jobToProcess.FullName) -Delimiter "|" 
    foreach ($workingFileEntry in $workingFile) {

        if ($($workingFileEntry.ActionType) -ne $null -and 
            $($workingFileEntry.AdObjectName) -ne $null -and 
            $($workingFileEntry.CurrentUserName) -ne $null -and 
            $($workingFileEntry.CurrentUserDomainName) -ne $null -and 
            $($workingFileEntry.CurrentUserEMailAddress)-ne $null) {
            
            $msg = $null
            $htmlBody  = $null
            $htmlBody = "<p style=""Color:Black;font-weight:normal;Font-Size:smaller;font-family:Tahoma"">"
            $htmlBody += "Lieber Mitarbeiter, <br/><br/>"

            try {
                $resourceForestUserObject = Get-ADUser -LDAPFilter "(samaccountname=$($workingFileEntry.AdObjectName))" -Properties mail,proxyAddresses,extensionAttribute6,msDS-cloudExtensionAttribute15,SamAccountName,mailNickname,AccountExpirationDate,mailNickname,homeMdb,extensionAttribute11 -Server $dc
            } catch {([Exception])
	            if ($_.Exception.InnerException) { $msg = $($_.Exception.InnerException.Message) } else { $msg = $($_.Exception.Message) }  	
                Write-EventLog $global:logName -Source $global:logSourceName -EventId 1000 -Message "Error getting User $($workingFileEntry.AdObjectName) from Active-Directory: $msg " -EntryType Error                  
            }

            if ($resourceForestUserObject -ne $null) {

                if ((Get-PSSession | ? {$_.State -like "Opened" -and $_.Availability -like "Available"}) -eq $null) {

                    Get-PSSession | Remove-PSSession
                    $cred = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $pshUser , (Get-Content $pshSecret | ConvertTo-SecureString) 
                    $PSSession = new-pssession –configurationname Microsoft.Exchange –connectionuri http://sv00516.ksbl.local/PowerShell –credential $Cred -Authentication Kerberos 
                    Import-PSSession $PSSession -AllowClobber
                }

                $Error.Clear()

                if ($($workingFileEntry.ActionType) -eq "DisableNonStdPersonMailbox" -and $resourceForestUserObject.Enabled -eq $true) {

                    try {
                        Set-ADUser $resourceForestUserObject.SamAccountName -Enabled $false -Server $dc
                    }
                    catch [System.Exception] {
                        if ($_.Exception.InnerException) { $msg = $($_.Exception.InnerException.Message) } else { $msg = $($_.Exception.Message) }
                        Write-EventLog $global:logName -Source $global:logSourceName -EventId 1000 -Message "Error disabling User $($workingFileEntry.AdObjectName): $msg " -EntryType Error                  
                    }

                    # Disable Account for Entra-Sync
                    Set-TenantState -User $resourceForestUserObject -Mode TenantDisable -CloudDomain $cloudDomain
                    
                    if (-not [string]::IsNullOrEmpty($resourceForestUserObject.homeMdb)) {
                        Change-MailboxFeaturesAndState -mailboxName $resourceForestUserObject.mailNickname -objectState ([ObjectState]::HIDE)
                    }                            

                    try {
                        Set-ADUser $($resourceForestUserObject.SamAccountName) -Description "Inaktiviert am $(get-date -Format "yyyy-MM-dd") von $($workingFileEntry.CurrentUserName)"
                    }
                    catch [System.Exception] {
                        if ($_.Exception.InnerException) { $msg = $($_.Exception.InnerException.Message) } else { $msg = $($_.Exception.Message) }
                        Write-EventLog $global:logName -Source $global:logSourceName -EventId 1000 -Message "Error setting new Description for User $($workingFileEntry.AdObjectName): $msg " -EntryType Error                  
                    }

                    if ([string]::IsNullOrEmpty($Error)) {
                        $htmlBody += "Das Benutzerkonto <b> $($resourceForestUserObject.SamAccountName) </b> wurde erfolgreich inaktiviert.<br/><br/>"                
                    } else {
                        $htmlBody += "Fehler beim inaktivieren des Benutzerkontos <b> $($resourceForestUserObject.SamAccountName) </b>.<br/><br/>$($Error.ToString())<br/><br/>"                                    
                    }
                 
                } elseif ($($workingFileEntry.ActionType) -eq "EnableNonStdPersonMailbox" -and $resourceForestUserObject.Enabled -eq $false) {

                    if ([string]::IsNullOrEmpty($resourceForestUserObject.homeMdb)) {                                                        
                        EnableDisable-Mailbox -resourceForestUserObject $resourceForestUserObject -workingFileEntry $workingFileEntry $true                        
                        Start-Sleep -Seconds 30
                    }                         
                    
                    Change-MailboxFeaturesAndState -mailboxName $($workingFileEntry.AdObjectName) -objectState ([ObjectState]::UNHIDE)

                    if ($resourceForestUserObject.extensionAttribute11 -eq "Hospis2AdDeleted") {
                        Update-DfsShareSettings -samAccountName $workingFileEntry.AdObjectName
                        
                        try {
                            Set-ADUser $($resourceForestUserObject.SamAccountName) -Clear extensionattribute11 -Server $dc     
                        } catch [System.Exception] {
                            if ($_.Exception.InnerException) { $msg = $($_.Exception.InnerException.Message) } else { $msg = $($_.Exception.Message) }
                            Write-EventLog $global:logName -Source $global:logSourceName -EventId 1015 -Message "Error clearing extensionattribute11 for User $($workingFileEntry.AdObjectName): $msg " -EntryType Error                  
                        }

                        if ($($workingFileEntry.AdObjectName).StartsWith("ex") -eq $true) {
                            $targetUserOu = $externalUserOu
                        } else {
                            $targetUserOu = $internalUserOu
                        }

                        try {
                            Move-ADObject (Get-ADUser $($resourceForestUserObject.SamAccountName)).distinguishedName -TargetPath $targetUserOu
                        } catch {([Exception])
	                        if ($_.Exception.InnerException) { $msg = $($_.Exception.InnerException.Message) } else { $msg = $($_.Exception.Message) }  	
	                        Write-EventLog $global:logName -Source $global:logSourceName -EventId 1016 -Message "Error moving User $($resourceForestUserObject.SamAccountName) to OU $($targetUserOu): $msg " -EntryType Error                  
                        }      
                    }

                    try {
                        Set-ADAccountPassword -Identity $($resourceForestUserObject.SamAccountName) -Reset -NewPassword (ConvertTo-SecureString -AsPlainText "P@ssw0rd4You" -Force)                     
                    }
                    catch [System.Exception] {
                        if ($_.Exception.InnerException) { $msg = $($_.Exception.InnerException.Message) } else { $msg = $($_.Exception.Message) }
                        Write-EventLog $global:logName -Source $global:logSourceName -EventId 1017 -Message "Error reseting Password for User $($workingFileEntry.AdObjectName): $msg " -EntryType Error                  
                    }

                    try {
                        Set-ADUser $($resourceForestUserObject.SamAccountName) -Enabled $true -ChangePasswordAtLogon $true -Server $dc
                    }
                    catch [System.Exception] {
                        if ($_.Exception.InnerException) { $msg = $($_.Exception.InnerException.Message) } else { $msg = $($_.Exception.Message) }
                        Write-EventLog $global:logName -Source $global:logSourceName -EventId 1018 -Message "Error setting ChangePasswordAtLogon and enabling User $($workingFileEntry.AdObjectName): $msg " -EntryType Error                  
                    }

                    try {
                        Set-ADUser $($resourceForestUserObject.SamAccountName) -Description "Aktiviert am $(get-date -Format "yyyy-MM-dd") von $($workingFileEntry.CurrentUserName)"
                    }
                    catch [System.Exception] {
                        if ($_.Exception.InnerException) { $msg = $($_.Exception.InnerException.Message) } else { $msg = $($_.Exception.Message) }
                        Write-EventLog $global:logName -Source $global:logSourceName -EventId 1019 -Message "Error setting Description for User $($workingFileEntry.AdObjectName): $msg " -EntryType Error                  
                    }

                    if ([string]::IsNullOrEmpty($Error)) {
                        $htmlBody += "Das Benutzerkonto <b> $($resourceForestUserObject.SamAccountName) </b> wurde erfolgreich aktiviert.<br/><br/>"                
                    } else {
                        $htmlBody += "Fehler beim aktivieren des Benutzerkontos <b> $($resourceForestUserObject.SamAccountName) </b>.<br/><br/>$($Error.ToString())<br/><br/>"                                    
                        Write-EventLog $global:logName -Source $global:logSourceName -EventId 1020 -Message "Error activating User $($workingFileEntry.AdObjectName): $($Error.ToString()) " -EntryType Error                  
                    }

                } elseif ($($workingFileEntry.ActionType) -eq "EnableNonStdPersonMailbox" -and $resourceForestUserObject.Enabled -eq $true) {

                    if ([string]::IsNullOrEmpty($resourceForestUserObject.homeMdb)) {                                                        
                        EnableDisable-Mailbox -resourceForestUserObject $resourceForestUserObject -workingFileEntry $workingFileEntry $true                        
                        Start-Sleep -Seconds 30
                    }                                             
                    Change-MailboxFeaturesAndState -mailboxName $($workingFileEntry.AdObjectName) -objectState ([ObjectState]::UNHIDE)
                    
                    if ($resourceForestUserObject.extensionAttribute11 -eq "Hospis2AdDeleted") {
                        Update-DfsShareSettings -samAccountName $workingFileEntry.AdObjectName
                        
                        try {
                            Set-ADUser $($resourceForestUserObject.SamAccountName) -Clear extensionattribute11 -Server $dc   
                        }
                        catch [System.Exception] {
                            if ($_.Exception.InnerException) { $msg = $($_.Exception.InnerException.Message) } else { $msg = $($_.Exception.Message) }
                            Write-EventLog $global:logName -Source $global:logSourceName -EventId 1021 -Message "Error clearing extensionattribute11 for User $($workingFileEntry.AdObjectName): $msg " -EntryType Error                  
                        }

                        if ($($workingFileEntry.AdObjectName).StartsWith("ex") -eq $true) {
                            try {
                                Move-ADObject (Get-ADUser $($resourceForestUserObject.SamAccountName)).distinguishedName -TargetPath $externalUserOu
                            } 
                            catch {([Exception])
	                            if ($_.Exception.InnerException) { $msg = $($_.Exception.InnerException.Message) } else { $msg = $($_.Exception.Message) }  	
	                            Write-EventLog $global:logName -Source $global:logSourceName -EventId 1022 -Message "Error moving User $($workingFileEntry.AdObjectName) to OU $($externalUserOu): $msg " -EntryType Error                  
                            }

                        } else {
                            try {
                                Move-ADObject (Get-ADUser $($resourceForestUserObject.SamAccountName)).distinguishedName -TargetPath $internalUserOu        
                            } 
                            catch {([Exception])
	                            if ($_.Exception.InnerException) { $msg = $($_.Exception.InnerException.Message) } else { $msg = $($_.Exception.Message) }  	
	                            Write-EventLog $global:logName -Source $global:logSourceName -EventId 1000 -Message "Error moving User $($workingFileEntry.AdObjectName) to OU $($internalUserOu): $msg " -EntryType Error                  
                            }
                        }        
                    }

                    if ([string]::IsNullOrEmpty($Error)) {
                        $htmlBody += "Das Benutzerkonto <b> $($resourceForestUserObject.SamAccountName) </b> war bereits aktiv.<br/><br/>"             
                    } else {
                        $htmlBody += "Fehler beim aktivieren des Benutzerkontos <b> $($resourceForestUserObject.SamAccountName) </b>.<br/><br/>$($Error.ToString())<br/><br/>"                                    
                        Write-EventLog $global:logName -Source $global:logSourceName -EventId 1023 -Message "Error activating User $($resourceForestUserObject.SamAccountName): $($Error.ToString()) " -EntryType Error                  
                    }
       
                } elseif ($($workingFileEntry.ActionType) -eq "DisableNonStdPersonMailbox" -and $resourceForestUserObject.Enabled -eq $false) {
                    
                    if (-not [string]::IsNullOrEmpty($resourceForestUserObject.homeMdb)) {
                        Change-MailboxFeaturesAndState -mailboxName $($workingFileEntry.AdObjectName) -objectState ([ObjectState]::HIDE)
                    }                    

                    if ([string]::IsNullOrEmpty($Error)) {
                        $htmlBody += "Das Benutzerkonto <b> $($resourceForestUserObject.SamAccountName) </b> war bereits inaktiv.<br/><br/>"                    
                    } else {
                        $htmlBody += "Fehler beim inaktivieren des Benutzerkontos <b> $($resourceForestUserObject.SamAccountName) </b>.<br/><br/>$($Error.ToString())<br/><br/>"                                    
                        Write-EventLog $global:logName -Source $global:logSourceName -EventId 1024 -Message "Error inactivating User $($resourceForestUserObject.SamAccountName): $($Error.ToString()) " -EntryType Error                  
                    }
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

$filesToProcess = Get-ChildItem -Recurse -Force $workingPath -ErrorAction SilentlyContinue | Where-Object { ( $_.Name -like "*AddEMailNickName*_pshjob_.csv") }

foreach ($jobToProcess in $filesToProcess) {

    if ($Host.Name -eq "ConsoleHost") {
        $ErrorActionPreference="SilentlyContinue"
        Stop-Transcript | out-null
        $ErrorActionPreference = "Continue"
        Start-Transcript -path "D:\IAM\Transcripts\Transcript_$($jobToProcess.Name).log" -append
    }

    $workingFile = Import-csv $($jobToProcess.FullName) -Delimiter "|" 
    foreach ($workingFileEntry in $workingFile) {

        if ($($workingFileEntry.ActionType) -ne $null -and 
            $($workingFileEntry.AdObjectName) -ne $null -and 
            $($workingFileEntry.NewPrimaryEMailAddress) -ne $null -and 
            $($workingFileEntry.CurrentUserName) -ne $null -and 
            $($workingFileEntry.CurrentUserDomainName) -ne $null -and 
            $($workingFileEntry.CurrentUserEMailAddress)-ne $null) {
            
            $msg = $null
            $htmlBody  = $null
            $htmlBody = "<p style=""Color:Black;font-weight:normal;Font-Size:smaller;font-family:Tahoma"">"
            $htmlBody += "Lieber Mitarbeiter, <br/><br/>"

            #$Error.Clear()

            $newPrimaryEMail = $($workingFileEntry.NewPrimaryEMailAddress)

            try {
                $mbx = Get-Mailbox $($workingFileEntry.AdObjectName)
            } 
            catch {([Exception])
	            if ($_.Exception.InnerException) { $msg = $($_.Exception.InnerException.Message) } else { $msg = $($_.Exception.Message) }  	
                Write-EventLog $global:logName -Source $global:logSourceName -EventId 1000 -Message "Error getting Mailbox for User $($workingFileEntry.AdObjectName) from Exchange: $msg " -EntryType Error                  
            }

            if ($mbx -ne $null) {

                Write-Host "Updating Mailbox $($mbx.DisplayName) with new E-Mail $newPrimaryEMail as $($workingFileEntry.AdObjectName)"

                $currentAddress = $mbx | select PrimarySmtpAddress
                $currentAddress = $($currentAddress.PrimarySmtpAddress)

                if ($currentAddress -ne $null) {

                    $msg = $null

                    try {
                        Set-Mailbox $mbx.Alias -PrimarySmtpAddress $newPrimaryEMail -EmailAddressPolicyEnabled $false 
                    }
                    catch [System.Exception] {
                        if ($_.Exception.InnerException) { $msg = $($_.Exception.InnerException.Message) } else { $msg = $($_.Exception.Message) }
                        Write-EventLog $global:logName -Source $global:logSourceName -EventId 1000 -Message "Error setting new PrimarySmtpAddress for User $($workingFileEntry.AdObjectName): $msg " -EntryType Error                  
                        $htmlBody += "Während dem Modifizieren des Attributes 'PrimarySmtpAddress' auf dem Postfach <b> $($mbx.DisplayName) </b> ist folgender Fehler aufgetreten: <b> $($msg) </b><br/><br/>"                     
                    }

                    try {
                        $mbx = Get-Mailbox $($workingFileEntry.AdObjectName)
                    } 
                    catch {([Exception])
	                    if ($_.Exception.InnerException) { $msg = $($_.Exception.InnerException.Message) } else { $msg = $($_.Exception.Message) }  	
                        Write-EventLog $global:logName -Source $global:logSourceName -EventId 1000 -Message "Error getting Mailbox for User $($workingFileEntry.AdObjectName) from Exchange: $msg " -EntryType Error                  
                    }

                    #if ($Error.Count -gt 0) {
                    if ($msg -eq $null) {

                        Write-Host "Successfully changed mailbox $($mbx.DisplayName) primary SMTP address from $currentAddress to $newPrimaryEMail" -ForegroundColor Green
                        $htmlBody += "Beim Postfach <b> $($mbx.DisplayName) </b> mit der E-Mail $currentAddress wurde erfolgreich der Mail-Alias $newPrimaryEMail hinzugefügt.<br/><br/>"                
                    }
                    
                    $htmlBody += "Viele Grüsse vom E-Mail Team</p>"                        
                    Send-EMail -smtpHost $smtpHost -mailFrom $mailFrom -mailTo $($workingFileEntry.CurrentUserEMailAddress) -mailCc $mailCc -mailSubject "*** Auftrag - Hinzufügen von Mailnickname ***" -mailBody $htmlBody -attachment $null

                }
                                                           
            }
        }
    }

    if ($Host.Name -eq "ConsoleHost") {
        Stop-Transcript
    }

    Move-Item $($jobToProcess.FullName) "D:\IAM\Archive\$($jobToProcess.Name)" -Force -Confirm:$false

}

$filesToProcess = Get-ChildItem $workingPath | Where-Object { ( $_.Name -like "*CreateMultiFunctionGenericUser*_pshjob_.csv") } | Sort-Object LastWriteTime

foreach ($jobToProcess in $filesToProcess) {

    if ($Host.Name -eq "ConsoleHost") {
        $ErrorActionPreference="SilentlyContinue"
        Stop-Transcript | out-null
        $ErrorActionPreference = "Continue"
        Start-Transcript -path "D:\IAM\Transcripts\Transcript_$($jobToProcess.Name).log" -append
    }
        
    $workingFile = Import-csv $($jobToProcess.FullName) -Delimiter "|" 
    foreach ($workingFileEntry in $workingFile) {

         if ($($workingFileEntry.ActionType) -ne $null -and 
            $($workingFileEntry.TargetAdObjectName) -ne $null -and 
            $($workingFileEntry.TargetDomain) -ne $null -and 
            $($workingFileEntry.TargetUserAdDisplayname) -ne $null -and 
            $($workingFileEntry.TargetUserAdEmployeeType) -ne $null -and 
            $($workingFileEntry.CurrentUserName) -ne $null -and 
            $($workingFileEntry.CurrentUserDomainName) -ne $null -and
            $($workingFileEntry.CurrentUserEMailAddress) -ne $null) {
            
            $msg = $null
            $htmlBody  = $null
            $htmlBody = "<p style=""Color:Black;font-weight:normal;Font-Size:smaller;font-family:Tahoma"">"
            $htmlBody += "Lieber Mitarbeiter, <br/><br/>"

            $secret = $null
            $msg = $null

            $ldapFilter = "(samaccountname=$($workingFileEntry.TargetAdObjectName))"
            $ds = New-Object System.DirectoryServices.DirectorySearcher([ADSI]"LDAP://$dc", $ldapFilter, @('distinguishedName'))
            
            try {
                $resourceForestAccount = $ds.FindOne()
            } 
            catch {([Exception])
	            if ($_.Exception.InnerException) { $msg = $($_.Exception.InnerException.Message) } else { $msg = $($_.Exception.Message) }  
	            Write-EventLog $global:logName -Source $global:logSourceName -EventId 1000 -Message "Error getting User $($workingFileEntry.TargetAdObjectName) from Active-Directory: $msg " -EntryType Error
            }
            
            if ($resourceForestAccount -eq $null) {
                
                $usr = $workingFileEntry.TargetAdObjectName
                $newPwd = $usr.Substring(0,1).toupper() + $usr.Substring(1,1) + "@" + $usr.substring($usr.length - 5, 5)
                $Password = ConvertTo-SecureString -string $newPwd -AsPlainText -Force

                try {
                    New-ADUser -name $($workingFileEntry.TargetAdObjectName) -DisplayName $($workingFileEntry.TargetAdObjectName) -Server $dc -path $targetDomainOU -SamAccountName $($workingFileEntry.TargetAdObjectName) -AccountPassword $Password -ChangePasswordAtLogon $true -userprincipalname "$($workingFileEntry.TargetAdObjectName)@$($workingFileEntry.TargetDomain)" -Enabled $true 
                } catch {([Exception])
	                if ($_.Exception.InnerException) { $msg = $($_.Exception.InnerException.Message) } else { $msg = $($_.Exception.Message) }  	
	                Write-EventLog $global:logName -Source $global:logSourceName -EventId 1000 -Message "Error creating new AD User $($workingFileEntry.TargetAdObjectName): $msg " -EntryType Error                  
                    Exit
                }

                Start-Sleep -Seconds 10

                if (-not [string]::IsNullOrEmpty($($workingFileEntry.Manager))) {
                    $manager = $($workingFileEntry.Manager).Split("[]")[0]
                    try {
                        Set-ADUser $($workingFileEntry.TargetAdObjectName) -Manager $manager
                    }
                    catch [System.Exception] {
                        if ($_.Exception.InnerException) { $msg = $($_.Exception.InnerException.Message) } else { $msg = $($_.Exception.Message) }
                        Write-EventLog $global:logName -Source $global:logSourceName -EventId 1000 -Message "Error setting Manager for User $($workingFileEntry.TargetAdObjectName): $msg " -EntryType Error                  
                    }
                }

                try {
                    Set-ADUser $($workingFileEntry.TargetAdObjectName) -replace @{"employeeType"=$($workingFileEntry.TargetUserAdEmployeeType)} -Server $dc
                }
                catch [System.Exception] {
                    if ($_.Exception.InnerException) { $msg = $($_.Exception.InnerException.Message) } else { $msg = $($_.Exception.Message) }
                    Write-EventLog $global:logName -Source $global:logSourceName -EventId 1000 -Message "Error setting Manager for User $($workingFileEntry.TargetAdObjectName): $msg " -EntryType Error                  
                }

                $home_drive = $null
                $home_drive = Get-HomeDrive
                                                   
                if ($home_drive -ne $null) {
                    $dfs_target = Join-Path -Path $home_drive.unc_path -ChildPath $($workingFileEntry.TargetAdObjectName);
                    
                    Set-UserHomeDirPermissions `
                    -homeDirectoryPath $dfs_target `
                    -userPrincipalName $($workingFileEntry.TargetAdObjectName) `
                    -userPrincipalDomain (Get-ADDomain $env:USERDNSDOMAIN).NetBIOSName `

                    $dfs_path = Join-Path -Path $homeDirectory -ChildPath $($workingFileEntry.TargetAdObjectName);
                    $prms = 'link add "' + $dfs_path + '" "' + $dfs_target + '"';
                    Run-DfsUtil -cmdLineArguments $prms 
                } 

                try {
                    Set-ADUser $($workingFileEntry.TargetAdObjectName) -Description "$($workingFileEntry.Description) - Erstellt am $(get-date -Format "yyyy-MM-dd") von $($workingFileEntry.CurrentUserName)" -Server $dc
                }
                catch [System.Exception] {
                    if ($_.Exception.InnerException) { $msg = $($_.Exception.InnerException.Message) } else { $msg = $($_.Exception.Message) }
                    Write-EventLog $global:logName -Source $global:logSourceName -EventId 1000 -Message "Error setting Description for User $($workingFileEntry.TargetAdObjectName): $msg " -EntryType Error                  
                }

                try {
                    Set-ADUser $($workingFileEntry.TargetAdObjectName) -HomeDirectory "$homeDirectory\$($workingFileEntry.TargetAdObjectName)" -Server $dc
                }
                catch [System.Exception] {
                    if ($_.Exception.InnerException) { $msg = $($_.Exception.InnerException.Message) } else { $msg = $($_.Exception.Message) }
                    Write-EventLog $global:logName -Source $global:logSourceName -EventId 1000 -Message "Error setting HomeDirectory for User $($workingFileEntry.TargetAdObjectName): $msg " -EntryType Error                  
                }

                try {
                    Set-ADUser $($workingFileEntry.TargetAdObjectName) -HomeDrive $homeDirectoryDrive -Server $dc
                }
                catch [System.Exception] {
                    if ($_.Exception.InnerException) { $msg = $($_.Exception.InnerException.Message) } else { $msg = $($_.Exception.Message) }
                    Write-EventLog $global:logName -Source $global:logSourceName -EventId 1000 -Message "Error setting homeDirectoryDrive for User $($workingFileEntry.TargetAdObjectName): $msg " -EntryType Error                  
                }
                
                try {
                    Set-ADUser $($workingFileEntry.TargetAdObjectName) -replace @{"kisAccountName" = $($workingFileEntry.TargetAdObjectName) } -Server $dc
                }
                catch [System.Exception] {
                    if ($_.Exception.InnerException) { $msg = $($_.Exception.InnerException.Message) } else { $msg = $($_.Exception.Message) }
                    Write-EventLog $global:logName -Source $global:logSourceName -EventId 1000 -Message "Error setting kisAccountName for User $($workingFileEntry.TargetAdObjectName): $msg " -EntryType Error                  
                }

                Set-UserApplicationDrivePermissions `
                            -applicationDirectoryPath $applicationDirectoryShare `
                            -userPrincipalName $($workingFileEntry.TargetAdObjectName) `
                            -userPrincipalDomain $($env:USERDOMAIN) `

                Set-UserApplicationDrivePermissions `
                            -applicationDirectoryPath $desktopDirectoryShare `
                            -userPrincipalName $($workingFileEntry.TargetAdObjectName) `
                            -userPrincipalDomain $($env:USERDOMAIN) `

                if ($msg -eq $null) {
                    Write-Host "Successfully created Generic User $($workingFileEntry.TargetUserAdDisplayname) with E-Mail $newPrimaryEMail as $($workingFileEntry.TargetAdObjectName) in $targetLinkedContainer" -ForegroundColor Green                
                    $htmlBody += "Der Gemeinschaftbenutzer <b> $($workingFileEntry.TargetUserAdDisplayname) </b> mit dem Login Name $($workingFileEntry.TargetAdObjectName) im AD Container $targetLinkedContainer wurde erfolgreich erstellt.<br/><br/>"                
                }
                    
                $htmlBody += "Viele Grüsse vom E-Mail Team</p>"
                Send-EMail `
                    -smtpHost $smtpHost `
                    -mailFrom $mailFrom `
                    -mailTo $($workingFileEntry.CurrentUserEMailAddress) `
                    -mailCc $mailCc `
                    -mailSubject "*** Auftrag - Erstellen eines Gemeinschaftbenutzers (ohne Postfach)  ***" `
                    -mailBody $htmlBody `
                    -attachment $null `

            }                   
        }
    }

    if ($Host.Name -eq "ConsoleHost") {
        Stop-Transcript
    }

    Move-Item $($jobToProcess.FullName) "D:\IAM\Archive\$($jobToProcess.Name)" -Force -Confirm:$false

}

Get-PSSession | Remove-PSSession