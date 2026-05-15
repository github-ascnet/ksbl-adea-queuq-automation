
<#
function Enumerate-NextAvailableAdObjectName
{
    Param
    (
        [string]$objectType,
        [string]$dc
    )

    if ($objectType -eq "VL") {
        $ds = New-Object System.DirectoryServices.DirectorySearcher([ADSI]"LDAP://$dc", "(&(objectClass=group)(mail=*)(mailNickname=vl0*))", @('mailnickname'))
    } else {
        $ds = New-Object System.DirectoryServices.DirectorySearcher([ADSI]"LDAP://$dc", "(&(sAMAccountType=805306368)(sAMAccountName=gmb0*))", @('samaccountname'))
    }

    $collectionItems = $ds.FindAll()

    $results = @()

    foreach ($item in $collectionItems)
    {

        $result = "" | Select-Object AdObjectName    
        if ($objectType -eq "VL") {
            $result.AdObjectName = $item.Properties["mailnickname"]
        } else {
            $result.AdObjectName = $item.Properties["samaccountname"]
        }
        $results = $results + $result
    }

    if ($results.Count -gt 0) {

        $mostRecentAdObjectName = $results | Sort-Object AdObjectName -Descending | select -First 1

        if ($mostRecentAdObjectName -ne $null) {

            if ($objectType -eq "VL") {

                [int]$i = $($mostRecentAdObjectName.AdObjectName).Replace("vl", "")

                $i++
                $newAdObjectName = $null

                if ($i.ToString().Length -eq 1) {
                    $newAdObjectName = "vl000$i"
                } elseif ($i.ToString().Length -eq 2) {
                    $newAdObjectName = "vl00$i"
                } elseif ($i.ToString().Length -eq 2) {
                    $newAdObjectName = "vl0$i"
                } else {
                    $newAdObjectName = "vl$i"
                }

            } else {

                [int]$i = $($mostRecentAdObjectName.AdObjectName).Replace("gmb", "")

                $i++
                $newAdObjectName = $null

                if ($i.ToString().Length -eq 1) {
                    $newAdObjectName = "gmb000$i"
                } elseif ($i.ToString().Length -eq 2) {
                    $newAdObjectName = "gmb00$i"
                } elseif ($i.ToString().Length -eq 2) {
                    $newAdObjectName = "gmb0$i"
                } else {
                    $newAdObjectName = "gmb$i"
                }

            }


            return $newAdObjectName

        } else {
            return $null
        }

    } else {
        return $null
    }


}
#>

function AddRemove-MailboxPermissions {
    Param (
        [string]$mailbox,
        [string]$trustee,
        [bool]$fullMailbox,
        [string]$action,
        [bool]$sendAs,
        [string]$dc
    )

    if ($fullMailbox -eq $true) {

        try {
            $isMember = $null
            $isMember = Get-MailboxPermission $mailbox |  ? {$_.User -like "$([Environment]::UserDomainName)\$trustee"} 
        } 
        catch {([Exception])
	        if ($_.Exception.InnerException) { $msg = $($_.Exception.InnerException.Message) } else { $msg = $($_.Exception.Message) }  	
	        Write-EventLog $global:logName -Source $global:logSourceName -EventId 2000 -Message "Error getting FullMailbox Permissions from Mailbox $($mailbox): $msg " -EntryType Error                  
        }

        if ($action -eq "ADD") {
            if ($isMember -eq $null) {
                try {
                    Add-MailboxPermission -Identity $mailbox -User "$([Environment]::UserDomainName)\$trustee" -AccessRights FullAccess -InheritanceType All -Automapping $true -DomainController $dc | Out-Null
                } catch {([Exception])
	                if ($_.Exception.InnerException) { $msg = $($_.Exception.InnerException.Message) } else { $msg = $($_.Exception.Message) }  	
	                Write-EventLog $global:logName -Source $global:logSourceName -EventId 2000 -Message "Error adding Mailbox Permissions FullAccess for Trustee $trustee on Mailbox $($mailbox): $msg " -EntryType Error                  
                }
            }                       
        } else {
            if ($isMember -ne $null) {
                try {
                    Remove-MailboxPermission -Identity $mailbox -User "$([Environment]::UserDomainName)\$trustee" -AccessRights FullAccess -InheritanceType All -DomainController $dc -Confirm:$false | Out-Null
                } catch {([Exception])
	                if ($_.Exception.InnerException) { $msg = $($_.Exception.InnerException.Message) } else { $msg = $($_.Exception.Message) }  	
	                Write-EventLog $global:logName -Source $global:logSourceName -EventId 2000 -Message "Error removing Mailbox Permissions FullAccess for Trustee $trustee on Mailbox $($mailbox): $msg " -EntryType Error                  
                }
            }                       
        }
        
        <#
        if ([string]::IsNullOrEmpty((Get-Mailbox $trustee).LinkedMasterAccount) -ne $true) {

            $legacyMasterAccount = (Get-Mailbox $trustee).LinkedMasterAccount

            $isMember = Get-MailboxPermission $mailbox |  ? {$_.User -like $legacyMasterAccount} 

            if ($action -eq "ADD") {
                if ($isMember.Count -eq 0) {
                    Add-MailboxPermission -Identity $mailbox -User $legacyMasterAccount -AccessRights FullAccess -InheritanceType All -Automapping $true -DomainController $dc | Out-Null
                }                       
            } else {
                if ($isMember.Count -gt 0) {
                    Remove-MailboxPermission -Identity $mailbox -User $legacyMasterAccount -AccessRights FullAccess -InheritanceType All -DomainController $dc -Confirm:$false | Out-Null
                }                       
            }
        }
        #>   
    } 


    if ($sendAs -eq $true) {

        try {
            $isMember = $null
            $isMember = Get-ADPermission $mailbox |  ? {$_.User -like "$([Environment]::UserDomainName)\$trustee"}
        } 
        catch {([Exception])
	        if ($_.Exception.InnerException) { $msg = $($_.Exception.InnerException.Message) } else { $msg = $($_.Exception.Message) }  	
	        Write-EventLog $global:logName -Source $global:logSourceName -EventId 2000 -Message "Error getting AD Permissions from Mailbox $($mailbox): $msg " -EntryType Error                  
        }
        
        if ($action -eq "ADD") {
            if ($isMember -eq $null) {
                try {
                    Add-ADPermission $mailbox -User "$([Environment]::UserDomainName)\$trustee" -ExtendedRights "Send As" -DomainController $dc | Out-Null
                } 
                catch {([Exception])
	                if ($_.Exception.InnerException) { $msg = $($_.Exception.InnerException.Message) } else { $msg = $($_.Exception.Message) }  	
	                Write-EventLog $global:logName -Source $global:logSourceName -EventId 2000 -Message "Error adding Mailbox Permissions SendAs for Trustee $trustee on Mailbox $($mailbox): $msg " -EntryType Error                  
                }
            }
        } else {
            if ($isMember -ne $null) {
                try {
                    Remove-ADPermission -Identity $mailbox -User "$([Environment]::UserDomainName)\$trustee" -ExtendedRights "Send As" -Confirm:$false | Out-Null
                } 
                catch {([Exception])
	                if ($_.Exception.InnerException) { $msg = $($_.Exception.InnerException.Message) } else { $msg = $($_.Exception.Message) }  	
	                Write-EventLog $global:logName -Source $global:logSourceName -EventId 2000 -Message "Error removing Mailbox Permissions SendAs for Trustee $trustee on Mailbox $($mailbox): $msg " -EntryType Error                  
                }
            }
        }

        <#
        if ([string]::IsNullOrEmpty((Get-Mailbox $trustee).LinkedMasterAccount) -ne $true) {

            $legacyMasterAccount = (Get-Mailbox $trustee).LinkedMasterAccount
            
            if ($legacyMasterAccount -ne $null) {

                $isMember = $null
                $isMember = Get-ADPermission $mailbox |  ? {$_.User -like "$legacyMasterAccount"}

                if ($action -eq "ADD") {
                    if ($isMember -eq $null) {
                        Add-ADPermission $mailbox -User $legacyMasterAccount -ExtendedRights "Send As" -DomainController $dc | Out-Null
                    }
                } else {
                    if ($isMember -ne $null) {
                        Remove-ADPermission -Identity $mailbox -User $legacyMasterAccount -ExtendedRights "Send As" -Confirm:$false | Out-Null
                    }
                }

            }
        }
        #>
    }
} 

function Send-EMail {
    Param (
        [string]$smtpHost,
        [string]$mailFrom,
        [string]$mailTo,
        [string]$mailCc,
        [string]$mailSubject,
        [string]$mailBody,
        [String]$attachment,
        [String]$user,
        [String]$pwd
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
        $SMTPClient.Credentials = New-Object System.Net.NetworkCredential($user, $pwd); 
        $SMTPClient.Send($mailMessage)
        
        Remove-Variable -Name SMTPClient
        Remove-Variable -Name pwd
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
    $password = get-random -count $length -input ($punc + $digits + $letters + $digits) | % -begin { $aa = $null } -process {$aa += [char]$_} -end {$aa}
    return $password
}

function Get-NextAvailableSamAccountName {
    [CmdletBinding()]
    [OutputType([string])]
    Param
    (
        [Parameter(Mandatory=$true,
                   ValueFromPipelineByPropertyName=$true,
                   Position=0)]
        $localForestDomainController
    )    

    [int[]]$userIds = $null
    $newUserId = $null
    [string[]]$samAccountNames = (((Get-ADUser -LDAPFilter "(samaccountname=gmb0*)" -Server $localForestDomainController).samaccountname -Replace "gmb", ""))       
    
    [int]$userId = ($samAccountNames | Sort-Object | select -Last 1)

    if ($userId.ToString().length -eq 1) {
        $userId = "gmb000$($userId + 1)"        
    } elseif ($userId.ToString().length -eq 2) {
        $newUserId = "gmb00$($userId + 1)"        
    } elseif ($userId.ToString().length -eq 3) {
        $newUserId = "gmb0$($userId + 1)"        
    } elseif ($userId.ToString().length -eq 4) {
        $newUserId = "gmb$($userId + 1)"        
    }

    return $newUserId   
   
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
                Write-Host "User $($User.SamAccountName): Ungueltiges oder fehlendes mail-Attribut."
                return;    
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

$jobsToProcess = $null
$workingPath = "D:\IAM\Queue"
$global:exchAdminGroupDn = "CN=Exchange Administrative Group (FYDIBOHF23SPDLT),CN=Administrative Groups,CN=KSBL,CN=Microsoft Exchange,CN=Services,$(([ADSI]”LDAP://rootdse”).ConfigurationNamingContext)"
$mailboxDbLdapFilter = "(&(objectClass=msExchPrivateMDB)(!(name=MAILDB-NODAG))(!name=maildb101)(!name=maildb102)(!name=maildb103)(!name=Mailbox Database*)(!name=maildb*))"

$global:defaultMailboxDbs = $null
$global:defaultMailboxDbs = (New-Object System.DirectoryServices.DirectorySearcher([ADSI]"LDAP://CN=Databases,$($global:exchAdminGroupDn)", $mailboxDbLdapFilter, @('name'))).FindAll() | % {$_.Path.Split(',')[0].Split('=')[1]} 
#$global:defaultMailboxDbs = @("MAILDB02","MAILDB01","MAILDB03","MAILDB04","MAILDB05","MAILDB07","MAILDB06","MAILDB08","MAILDB09","MAILDB11","MAILDB13","MAILDB15","MAILDB10","MAILDB12","MAILDB14","MAILDB16")

$pshUser = "ksbl\ServiceIAMJobs10"
$pshSecret = "D:\iam\Secrets\serviceiamjobs10.sec"

$cloudDomain = "kantonsspitalbl.mail.onmicrosoft.com"

$global:logname = "KSBL Helpdesk GUI"
$global:logSourceName = "Process-GroupMailbox"
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


$filesToProcess = Get-ChildItem $workingPath | Where-Object { ( $_.Name -like "*AddGroupMailboxFmaMembers*_pshjob_.csv") } | Sort-Object LastWriteTime

foreach ($jobToProcess in $filesToProcess) {

    if ($Host.Name -eq "ConsoleHost") {
        $ErrorActionPreference="SilentlyContinue"
        Stop-Transcript | out-null
        $ErrorActionPreference = "Continue"
        Start-Transcript -path "D:\IAM\Transcripts\Transcript_$($jobToProcess.Name).log" -append
    }

    $workingFile = Import-csv $($jobToProcess.FullName) -Delimiter "|" 
    foreach ($workingFileEntry in $workingFile) {

        #ActionType|AdObjectName|FullAccessMembers|EnableSendAs|CurrentUserName|CurrentUserDomainName|CurrentUserEMailAddress
        #AddGroupMailboxFmaMembers|ambichir|us333[ADD]!us600[ADD]!us10886[DEL]|True|ex00013|NT_D_KSL|Sascha.Affolter@ksbl.ch

        if ($($workingFileEntry.ActionType) -ne $null -and 
            $($workingFileEntry.AdObjectName) -ne $null -and
            $($workingFileEntry.FullAccessMembers) -ne $null -and
            $($workingFileEntry.EnableSendAs) -ne $null -and
            $($workingFileEntry.CurrentUserName) -ne $null -and 
            $($workingFileEntry.CurrentUserDomainName) -ne $null) {

            $msg = $null
            $htmlBody  = $null
            $htmlBody = "<p style=""Color:Black;font-weight:normal;Font-Size:smaller;font-family:Tahoma"">"
            $htmlBody += "Lieber Mitarbeiter, <br/><br/>"
            
            try {
                $mbx = $null
                $mbx = Get-Mailbox $($workingFileEntry.AdObjectName) -ErrorAction SilentlyContinue
            } catch {([Exception])
	            if ($_.Exception.InnerException) { $msg = $($_.Exception.InnerException.Message) } else { $msg = $($_.Exception.Message) }  	
	            Write-EventLog $global:logName -Source $global:logSourceName -EventId 2000 -Message "Error getting Mailbox $($workingFileEntry.AdObjectName) from Exchange: $msg " -EntryType Error                  
                Exit
            }
                                    
            if ($mbx -ne $null) {

                #if ($mbx.Count -lt 2) {

                    #$Error.Clear()
                    $msg = $null

                    $primaryEMailAddress = "$(($mbx.WindowsEmailAddress).Local)@$(($mbx.WindowsEmailAddress).Domain)"
                
                    if ($($workingFileEntry.FullAccessMembers) -ne $null) {

                        [string[]]$fullAccessMembers = $($workingFileEntry.FullAccessMembers).Split("!")
                    
                        foreach ($item in $fullAccessMembers) {
                        
                            $fullAccessMember = $item.Split("[]")[0]
                            $fmaAction = $item.Split("[]")[1]

                            if ($($workingFileEntry.EnableSendAs) -eq "True") {
                                
                                AddRemove-MailboxPermissions -mailbox $($mbx.DistinguishedName) -trustee $fullAccessMember -fullMailbox $true -action $fmaAction -sendAs $true -dc $dc

                            } else {
                                
                                AddRemove-MailboxPermissions -mailbox $($mbx.DistinguishedName) -trustee $fullAccessMember -fullMailbox $true -action $fmaAction -sendAs $false -dc $dc

                            }                        
                        }
                    }

                    #Get-MailboxPermission $($mbx.DistinguishedName) | where {$_.user.tostring() -ne "NT AUTHORITY\SELF" -and $_.IsInherited -eq $false} | Select Identity,User,@{Name='Access Rights';Expression={[string]::join(', ', $_.AccessRights)}}
                    #Get-ADPermission $($mbx.DistinguishedName) | ? {$_.IsInherited -eq $false -and $_.User -notlike "NT AUTHORITY*" -and $_.User -notlike "S-1-5-*"}

                    #if ($Error.Count -gt 0) {
                    if ($msg -eq $null) {

                        Write-Host "Die Berechtigungen auf der Gruppenmailbox $($mbx.DisplayName) mit der E-Mail $($mbx.PrimarySmtpAddress) und Login Name $($workingFileEntry.AdObjectName) wurden erfolgreich modifiziert" -ForegroundColor Green                
                        $htmlBody += "Die Berechtigungen auf der Gruppenmailbox <b> $($mbx.DisplayName) </b> mit der E-Mail $($mbx.PrimarySmtpAddress) und Login Name $($workingFileEntry.AdObjectName) wurden erfolgreich modifiziert.<br/><br/>"                

                    }
                    
                    $htmlBody += "Viele Grüsse vom E-Mail Team</p>"
                    Send-EMail -smtpHost $smtpHost -mailFrom $mailFrom -mailTo $($workingFileEntry.CurrentUserEMailAddress) -mailCc $mailCc -mailSubject "*** Auftrag - Berechtigungen bei Gruppenmailbox mutieren ***" -mailBody $htmlBody -attachment $null -user "ksbl\ServiceMailboxMove" -pwd "Basel1893"
                <#                    
                } else {
                    
                    Write-Host "Während dem Modifizieren der Berechtigungen auf dem Postfach <b> $($mbx.DisplayName) </b> mit der E-Mail $primaryEMailAddress und Login Name $($workingFileEntry.AdObjectName) ist folgender Fehler aufgetreten: There is more than one object having the same alias  $($workingFileEntry.AdObjectName)" -ForegroundColor Red
                    $htmlBody += "Während dem Modifizieren der Berechtigungen auf dem Postfach <b> $($mbx.DisplayName) </b> mit der E-Mail $primaryEMailAddress und Login Name $($workingFileEntry.AdObjectName) ist folgender Fehler aufgetreten: <b> There is more than one object having the same alias $($workingFileEntry.AdObjectName) </b><br/><br/>"                     

                    $htmlBody += "Viele Grüsse vom E-Mail Team</p>"
                    Send-EMail -smtpHost $smtpHost -mailFrom $mailFrom -mailTo $($workingFileEntry.CurrentUserEMailAddress) -mailCc $mailCc -mailSubject "*** Auftrag - Berechtigungen bei Gruppenmailbox mutieren ***" -mailBody $htmlBody -attachment $null -user "ksbl\ServiceMailboxMove" -pwd "Basel1893"

                }
                #>
            } else {

                Write-EventLog $global:logName -Source $global:logSourceName -EventId 2000 -Message "Failed getting Mailbox $($workingFileEntry.AdObjectName): $msg " -EntryType Error                  
                $htmlBody += "Während dem Modifizieren der Berechtigungen auf dem Postfach <b> $($mbx.DisplayName) </b> mit dem Login Name $($workingFileEntry.AdObjectName) ist folgender Fehler aufgetreten: <b> Unable to find Mailbox $($workingFileEntry.AdObjectName) </b><br/><br/>"                     

                $htmlBody += "Viele Grüsse vom E-Mail Team</p>"
                Send-EMail -smtpHost $smtpHost -mailFrom $mailFrom -mailTo $($workingFileEntry.CurrentUserEMailAddress) -mailCc $mailCc -mailSubject "*** Auftrag - Berechtigungen bei Gruppenmailbox mutieren ***" -mailBody $htmlBody -attachment $null -user "ksbl\ServiceMailboxMove" -pwd "Basel1893"

            }
        }

    }

    if ($Host.Name -eq "ConsoleHost") {
        Stop-Transcript
    }

    Move-Item $($jobToProcess.FullName) ("D:\IAM\Archive\$($jobToProcess.Name)_{0:yyyyMMddhhmmss}.csv" -f (get-date))

}


$filesToProcess = Get-ChildItem $workingPath | Where-Object { ( $_.Name -like "*CreateGroupMailbox*_pshjob_.csv") } | Sort-Object LastWriteTime

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
            $($workingFileEntry.DisplayName) -ne $null -and 
            $($workingFileEntry.PrimarySmtpAddress) -ne $null -and 
            $($workingFileEntry.FirstName) -ne $null -and 
            $($workingFileEntry.LastName) -ne $null -and 
            $($workingFileEntry.AdObjectName) -ne $null -and 
            $($workingFileEntry.OrgUnit) -ne $null -and 
            $($workingFileEntry.HideInAb) -ne $null -and 
            $($workingFileEntry.Manager) -ne $null -and 
            $($workingFileEntry.CurrentUserName) -ne $null -and 
            $($workingFileEntry.CurrentUserDomainName) -ne $null -and 
            $($workingFileEntry.CurrentUserEMailAddress)) {

            $msg = $null
            $htmlBody  = $null
            $htmlBody = "<p style=""Color:Black;font-weight:normal;Font-Size:smaller;font-family:Tahoma"">"
            $htmlBody += "Lieber Mitarbeiter, <br/><br/>"

            $secret = $null
            $secret = Random-Password
            if ($secret -eq $null) {
                $secret = "LFAVmB2jlq"
            } else {

                if ($($workingFileEntry.PrimarySmtpAddress) -ne $null) {

                    try {
                        $mbx = $null
                        $mbx = Get-Mailbox $($workingFileEntry.PrimarySmtpAddress) -DomainController $dc -ErrorAction SilentlyContinue
                    } catch {([Exception])
	                    if ($_.Exception.InnerException) { $msg = $($_.Exception.InnerException.Message) } else { $msg = $($_.Exception.Message) }  	
	                    Write-EventLog $global:logName -Source $global:logSourceName -EventId 2000 -Message "Error getting Mailbox for User $($workingFileEntry.AdObjectName) from Exchange: $msg " -EntryType Error                  
                    }

                    if ($mbx -eq $null) {

                        Write-Host "Creating GroupMailbox $($workingFileEntry.DisplayName) with E-Mail $($workingFileEntry.PrimarySmtpAddress) as $($workingFileEntry.AdObjectName) in $($workingFileEntry.OrgUnit)"
                        $msg = $null

                        $workingFileEntry.AdObjectName = Get-NextAvailableSamAccountName -localForestDomainController $dc 

                        try {
                            # Changed by S. Affolter 11.08.2016
                            $mailboxDatabase = $defaultMailboxDbs | Get-Random                            
                            New-Mailbox -Database $mailboxDatabase -SamAccountName $($workingFileEntry.AdObjectName) -Shared -Firstname $($workingFileEntry.FirstName) -LastName $($workingFileEntry.LastName) -DisplayName $($workingFileEntry.DisplayName) -UserPrincipalName "$($workingFileEntry.AdObjectName)@ksbl.local" -Alias $($workingFileEntry.AdObjectName) -Name $($workingFileEntry.AdObjectName) -PrimarySmtpAddress $($workingFileEntry.PrimarySmtpAddress) -OrganizationalUnit $($workingFileEntry.OrgUnit) -Password (ConvertTo-SecureString $secret -AsPlainText -Force) -DomainController $dc
                        } catch [System.Exception] {
                            if ($_.Exception.InnerException) { $msg = $($_.Exception.InnerException.Message) } else { $msg = $($_.Exception.Message) }
	                        Write-EventLog $global:logName -Source $global:logSourceName -EventId 2000 -Message "Error creating new Group-Mailbox $($workingFileEntry.AdObjectName) in Exchange: $msg " -EntryType Error                  
                            $htmlBody += "Während dem neu erstellen des Postfaches <b> $($workingFileEntry.DisplayName) </b> mit der E-Mail Adresse $($workingFileEntry.PrimarySmtpAddress) ist folgender Fehler aufgetreten: <b> $($msg) </b><br/><br/>"                     
                            Exit
                        }

                        start-sleep -Seconds 10
                        
                        try {
                            $mbx = $null
                            $mbx = Get-Mailbox $($workingFileEntry.AdObjectName) -DomainController $dc
                        } 
                        catch {([Exception])
	                        if ($_.Exception.InnerException) { $msg = $($_.Exception.InnerException.Message) } else { $msg = $($_.Exception.Message) }  	
	                        Write-EventLog $global:logName -Source $global:logSourceName -EventId 2000 -Message "Error getting Mailbox for User $($workingFileEntry.AdObjectName) from Exchange: $msg " -EntryType Error                  
                        }
            
                        if ($mbx -ne $null) {

                            try {
                                Set-MailboxJunkEmailConfiguration $($workingFileEntry.AdObjectName) -Enabled $false
                            } catch [System.Exception] {
                                if ($_.Exception.InnerException) { $msg = $($_.Exception.InnerException.Message) } else { $msg = $($_.Exception.Message) }
	                            Write-EventLog $global:logName -Source $global:logSourceName -EventId 2000 -Message "Error setting MailboxJunkEmailConfiguration on Mailbox $($workingFileEntry.AdObjectName): $msg " -EntryType Error                  
                                $htmlBody += "Während dem Modifizieren des Attributes 'MailboxJunkEmailConfiguration' auf dem Postfach <b> $($workingFileEntry.DisplayName) </b> ist folgender Fehler aufgetreten: <b> $($msg) </b><br/><br/>"                     
                            }

                            if ($($workingFileEntry.HideInAb) -eq $true) {
                                try {
                                    Set-Mailbox $($workingFileEntry.AdObjectName) -HiddenFromAddressListsEnabled $true -DomainController $dc
                                } catch [System.Exception] {
                                    if ($_.Exception.InnerException) { $msg = $($_.Exception.InnerException.Message) } else { $msg = $($_.Exception.Message) }
	                                Write-EventLog $global:logName -Source $global:logSourceName -EventId 2000 -Message "Error setting HiddenFromAddressListsEnabled on Mailbox $($workingFileEntry.AdObjectName): $msg " -EntryType Error                  
                                    $htmlBody += "Während dem Modifizieren des Attributes 'HiddenFromAddressListsEnabled' auf dem Postfach <b> $($workingFileEntry.DisplayName) </b> ist folgender Fehler aufgetreten: <b> $($msg) </b><br/><br/>"                     
                                }
                            }
                    
                            if ($($workingFileEntry.Manager) -ne $null) {

                                $fullAccessMember = $($workingFileEntry.Manager).Split("[]")[0]
                                $fmaAction = "ADD"

                                AddRemove-MailboxPermissions -mailbox $($mbx.DistinguishedName) -trustee $fullAccessMember -fullMailbox $true -action $fmaAction -sendAs $true -dc $dc                        
                
                                try {
                                    Set-ADUser $($workingFileEntry.AdObjectName) -Description "Created on $(get-date) by $($workingFileEntry.CurrentUserName) - $secret" -Manager $fullAccessMember
                                } catch [System.Exception] {
                                    if ($_.Exception.InnerException) { $msg = $($_.Exception.InnerException.Message) } else { $msg = $($_.Exception.Message) }
	                                Write-EventLog $global:logName -Source $global:logSourceName -EventId 2000 -Message "Error setting Description on User $($workingFileEntry.AdObjectName): $msg " -EntryType Error                  
                                    $htmlBody += "Während dem Modifizieren des Attributes 'Description' auf dem Active-Directory Objekt <b> $($workingFileEntry.DisplayName) </b> ist folgender Fehler aufgetreten: <b> $($msg) </b><br/><br/>"                     
                                }
                        
                            } else {
                    
                                try {
                                    Set-ADUser $($workingFileEntry.AdObjectName) -Description "Created on $(get-date) by $($workingFileEntry.CurrentUserName) - $secret" 
                                } catch [System.Exception] {
                                    if ($_.Exception.InnerException) { $msg = $($_.Exception.InnerException.Message) } else { $msg = $($_.Exception.Message) }
	                                Write-EventLog $global:logName -Source $global:logSourceName -EventId 2000 -Message "Error setting Description on User $($workingFileEntry.AdObjectName): $msg " -EntryType Error                  
                                    $htmlBody += "Während dem Modifizieren des Attributes 'Description' auf dem Active-Directory Objekt <b> $($workingFileEntry.DisplayName) </b> ist folgender Fehler aufgetreten: <b> $($msg) </b><br/><br/>"                     
                                }

                            }
                    

                            try {
                                Get-ADUser -Identity $($workingFileEntry.AdObjectName) -Properties employeeType | Set-ADUser -Replace @{employeeType="G"}
                            } catch [System.Exception] {
                                if ($_.Exception.InnerException) { $msg = $($_.Exception.InnerException.Message) } else { $msg = $($_.Exception.Message) }
                                Write-EventLog $global:logName -Source $global:logSourceName -EventId 2000 -Message "Error setting employeeType on User $($workingFileEntry.AdObjectName): $msg " -EntryType Error                  
                                $htmlBody += "Während dem Modifizieren des Attributes 'employeeType' auf dem Active-Directory Objekt <b> $($workingFileEntry.DisplayName) </b> ist folgender Fehler aufgetreten: <b> $($msg) </b><br/><br/>"                     
                            }                

                            if ($($workingFileEntry.FullAccessMembers) -ne $null) {
                
                                [string[]]$fullAccessMembers = $($workingFileEntry.FullAccessMembers).Split("!")
                    
                                foreach ($item in $fullAccessMembers) {

                                    $fullAccessMember = $item.Split("[]")[0]
                                    #$fmaAction = $item.Split("[]")[1]
                                    $fmaAction = "ADD"

                                    AddRemove-MailboxPermissions -mailbox $($mbx.DistinguishedName) -trustee $fullAccessMember -fullMailbox $true -action $fmaAction -sendAs $true -dc $dc                        

                                }
                            }

                            if (-not [string]::IsNullOrEmpty($workingFileEntry.NewPrimaryEMailAddress)) {
                            
                                $newPrimaryEMail = $($workingFileEntry.NewPrimaryEMailAddress)
                                $currentAddress = $mbx | select PrimarySmtpAddress
                                $currentAddress = $($currentAddress.PrimarySmtpAddress)

                                if ($currentAddress -ne $null) {

                                    $msg = $null

                                    try {
                                        Set-Mailbox -Identity $mbx.Alias -PrimarySmtpAddress $newPrimaryEMail -EmailAddressPolicyEnabled $false 
                                    } catch [System.Exception] {
                                        if ($_.Exception.InnerException) { $msg = $($_.Exception.InnerException.Message) } else { $msg = $($_.Exception.Message) }
	                                    Write-EventLog $global:logName -Source $global:logSourceName -EventId 2000 -Message "Error setting PrimarySmtpAddress on Mailbox $($workingFileEntry.AdObjectName): $msg " -EntryType Error                  
                                        $htmlBody += "Während dem Modifizieren des Attributes 'PrimarySmtpAddress' auf dem Postfach <b> $($mbx.DisplayName) </b> ist folgender Fehler aufgetreten: <b> $($msg) </b><br/><br/>"                     
                                    }
                                }
                            }

                            try { 
                                Add-ADGroupMember "GG-EV-Users" -Members $($workingFileEntry.AdObjectName) -Server $dc
    	                    } catch [System.Exception] {
                                if ($_.Exception.InnerException) { $msg = $($_.Exception.InnerException.Message) } else { $msg = $($_.Exception.Message) }
                                Write-EventLog $global:logName -Source $global:logSourceName -EventId 2000 -Message "Error adding User $($workingFileEntry.AdObjectName) to Group GG-EV-Users: $msg " -EntryType Error                  
                                $htmlBody += "Während dem hinzufügen der Gruppe GG-EV-Users auf dem Active-Directory Objekt <b> $($workingFileEntry.DisplayName) </b> ist folgender Fehler aufgetreten: <b> $($msg) </b><br/><br/>"                     
    	                    }                                                                                                         

                            $user = Get-ADUser -Identity $($workingFileEntry.AdObjectName) -Properties *
                            Set-TenantState -User $user -Mode TenantEnable -CloudDomain $cloudDomain                            

                            if ($msg -eq $null) {

                                Write-Host "Successfully created GroupMailbox $($workingFileEntry.DisplayName) with E-Mail $($workingFileEntry.PrimarySmtpAddress) as $($workingFileEntry.AdObjectName) in $($workingFileEntry.OrgUnit)" -ForegroundColor Green                
                                $htmlBody += "Die Gruppenmailbox <b> $($workingFileEntry.DisplayName) </b> mit der E-Mail $($workingFileEntry.PrimarySmtpAddress) und Login Name $($workingFileEntry.AdObjectName) im AD Container $($workingFileEntry.OrgUnit) wurde erfolgreich erstellt.<br/><br/>"                

                            }
                                                
                            $htmlBody += "Viele Grüsse vom E-Mail Team</p>"
                            Send-EMail -smtpHost $smtpHost -mailFrom $mailFrom -mailTo $($workingFileEntry.CurrentUserEMailAddress) -mailCc $mailCc -mailSubject "*** Auftrag - Erstellen einer Gruppenmailbox ***" -mailBody $htmlBody -attachment $null -user "ksbl\ServiceMailboxMove" -pwd "Basel1893"

                        } else {

                            Write-Host "Nach dem Erstellen des Postfaches <b> $($workingFileEntry.DisplayName) </b> mit der E-Mail $($workingFileEntry.PrimarySmtpAddress) und Login Name $($workingFileEntry.AdObjectName) im AD Container $($workingFileEntry.OrgUnit) ist folgender Fehler aufgetreten: Unable to find newly created Mailbox $($workingFileEntry.DisplayName)" -ForegroundColor Red
                            $htmlBody += "Nach dem Erstellen des Postfaches <b> $($workingFileEntry.DisplayName) </b> mit der E-Mail $($workingFileEntry.PrimarySmtpAddress) und Login Name $($workingFileEntry.AdObjectName) im AD Container $($workingFileEntry.OrgUnit) ist folgender Fehler aufgetreten: <b> Unable to find newly created Mailbox $($workingFileEntry.DisplayName) </b><br/><br/>"                     

                            $htmlBody += "Viele Grüsse vom E-Mail Team</p>"
                            Send-EMail -smtpHost $smtpHost -mailFrom $mailFrom -mailTo $($workingFileEntry.CurrentUserEMailAddress) -mailCc $mailCc -mailSubject "*** Auftrag - Erstellen einer Gruppenmailbox ***" -mailBody $htmlBody -attachment $null -user "ksbl\ServiceMailboxMove" -pwd "Basel1893"
                
                        }

                    } else {

                        Write-Host "Beim Erstellen des Postfaches <b> $($workingFileEntry.DisplayName) </b> mit der E-Mail $($workingFileEntry.PrimarySmtpAddress) und Login Name $($workingFileEntry.AdObjectName) im AD Container $($workingFileEntry.OrgUnit) ist folgender Fehler aufgetreten: Mailbox with primary E-Mail $($workingFileEntry.PrimarySmtpAddress) exists already. There seems to be a conflict which must be solved first." -ForegroundColor Red
                        Write-EventLog $global:logName -Source $global:logSourceName -EventId 2000 -Message "Failed getting Mailbox $($workingFileEntry.PrimarySmtpAddress) from Exchange: $msg " -EntryType Error                  
                        $htmlBody += "Beim Erstellen des Postfaches <b> $($workingFileEntry.DisplayName) </b> mit der E-Mail $($workingFileEntry.PrimarySmtpAddress) und Login Name $($workingFileEntry.AdObjectName) im AD Container $($workingFileEntry.OrgUnit) ist folgender Fehler aufgetreten: <b> Mailbox with primary E-Mail $($workingFileEntry.PrimarySmtpAddress) exists already. There seems to be a conflict which must be solved first. </b><br/><br/>"                     

                        $htmlBody += "Viele Grüsse vom E-Mail Team</p>"
                        Send-EMail -smtpHost $smtpHost -mailFrom $mailFrom -mailTo $($workingFileEntry.CurrentUserEMailAddress) -mailCc $mailCc -mailSubject "*** Auftrag - Erstellen einer Gruppenmailbox ***" -mailBody $htmlBody -attachment $null -user "ksbl\ServiceMailboxMove" -pwd "Basel1893"

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


$filesToProcess = Get-ChildItem -Recurse -Force $workingPath -ErrorAction SilentlyContinue | Where-Object { ( $_.Name -like "*ChangeManagerGroupMailbox*_pshjob_.csv") }

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
            $($workingFileEntry.ManagerAdObjectName) -ne $null -and
            $($workingFileEntry.CurrentUserName) -ne $null -and 
            $($workingFileEntry.CurrentUserDomainName) -ne $null -and
            $($workingFileEntry.CurrentUserEMailAddress) -ne $null) {

            $msg = $null
            $htmlBody  = $null
            $htmlBody = "<p style=""Color:Black;font-weight:normal;Font-Size:smaller;font-family:Tahoma"">"
            $htmlBody += "Lieber Mitarbeiter, <br/><br/>"
                
            try {
                $mbx = $null
                $mbx = Get-Mailbox $($workingFileEntry.AdObjectName) -ErrorAction SilentlyContinue -DomainController $dc
            } catch {([Exception])
	            if ($_.Exception.InnerException) { $msg = $($_.Exception.InnerException.Message) } else { $msg = $($_.Exception.Message) }  	
	            Write-EventLog $global:logName -Source $global:logSourceName -EventId 2000 -Message "Error getting Mailbox $($workingFileEntry.AdObjectName) from Exchange: $msg " -EntryType Error                  
                Exit
            }
            
            if ($mbx -ne $null) {

                #$Error.Clear()
                $msg = $null

                if ($($workingFileEntry.ManagerAdObjectName) -ne $null) {

                    $fullAccessMember = $($workingFileEntry.ManagerAdObjectName) 
                    $fmaAction = "ADD"

                    AddRemove-MailboxPermissions -mailbox $($mbx.DistinguishedName) -trustee $fullAccessMember -fullMailbox $true -action $fmaAction -sendAs $true -dc $dc                    

                    try {
                        Set-ADUser -Identity $($workingFileEntry.AdObjectName) -Manager $($workingFileEntry.ManagerAdObjectName) -Server $dc
                    } catch [System.Exception] {
                        if ($_.Exception.InnerException) { $msg = $($_.Exception.InnerException.Message) } else { $msg = $($_.Exception.Message) }
                        Write-EventLog $global:logName -Source $global:logSourceName -EventId 2000 -Message "Error setting Manager on User $($workingFileEntry.AdObjectName): $msg " -EntryType Error                  
                        $htmlBody += "Während dem Modifizieren des Attributes 'Manager' auf dem Active-Directory Objekt <b> $($workingFileEntry.AdObjectName) </b> ist folgender Fehler aufgetreten: <b> $($msg) </b><br/><br/>"                     
                    }                
                
                }

                #if ($Error.Count -gt 0) {
                if ($msg -eq $null) {

                    Write-Host "Der Verantwortliche auf der Gruppenmailbox $($mbx.DisplayName) wurden erfolgreich modifiziert" -ForegroundColor Green                
                    $htmlBody += "Der Verantwortliche auf der Gruppenmailbox <b> $($mbx.DisplayName) </b> wurden erfolgreich modifiziert.<br/><br/>"                
                }
                    
                $htmlBody += "Viele Grüsse vom E-Mail Team</p>"
                Send-EMail -smtpHost $smtpHost -mailFrom $mailFrom -mailTo $($workingFileEntry.CurrentUserEMailAddress) -mailCc $mailCc -mailSubject "*** Auftrag - Verantwortlicher bei Gruppenmailbox mutieren ***" -mailBody $htmlBody -attachment $null -user "ksbl\ServiceMailboxMove" -pwd "Basel1893"


            } else {

                Write-Host "Während dem Modifizieren des Verantwortlichen auf dem Postfach <b> $($mbx.DisplayName) </b> ist folgender Fehler aufgetreten: Unable to find Mailbox $($workingFileEntry.AdObjectName)" -ForegroundColor Red
                Write-EventLog $global:logName -Source $global:logSourceName -EventId 2000 -Message "Failed getting Mailbox $($workingFileEntry.AdObjectName) from Exchange: $msg " -EntryType Error                  
                $htmlBody += "Während dem Modifizieren des Verantwortlichen auf dem Postfach <b> $($mbx.DisplayName) </b> ist folgender Fehler aufgetreten: <b> Unable to find Mailbox $($workingFileEntry.AdObjectName) </b><br/><br/>"                     

                $htmlBody += "Viele Grüsse vom E-Mail Team</p>"
                Send-EMail -smtpHost $smtpHost -mailFrom $mailFrom -mailTo $($workingFileEntry.CurrentUserEMailAddress) -mailCc $mailCc -mailSubject "*** Auftrag - Verantwortlicher bei Gruppenmailbox mutieren ***" -mailBody $htmlBody -attachment $null -user "ksbl\ServiceMailboxMove" -pwd "Basel1893"

            }
        }
    }

    if ($Host.Name -eq "ConsoleHost") {
        Stop-Transcript
    }

    Move-Item $($jobToProcess.FullName) "D:\IAM\Archive\$($jobToProcess.Name)" -Force -Confirm:$false

}

Get-PSSession | Remove-PSSession
Exit