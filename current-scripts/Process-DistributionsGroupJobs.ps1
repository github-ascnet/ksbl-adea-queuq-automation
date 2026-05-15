<#
function Enumerate-NextAvailableAdObjectName {
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

function Enumerate-NextAvailableAdObjectName {
    param (
        [string]$objectType,
        [string]$dc
    )

    # Prefix definieren und Filter/Attribut abhängig vom Typ wählen
    switch ($objectType.ToUpper()) {
        "VL" {
            $prefix    = "vl"
            $filter    = "(&(objectClass=group)(mail=*)($([string]::Format("mailNickname={0}*", $prefix))))"
            $attribute = "mailNickname"
        }
        "GMB" {
            $prefix    = "gmb"
            $filter    = "(&(sAMAccountType=805306368)(sAMAccountName=$prefix*))"
            $attribute = "sAMAccountName"
        }
        default {
            Write-Warning "Ungültiger objectType: $objectType"
            return $null
        }
    }

    # LDAP-Abfrage
    $searcher = New-Object System.DirectoryServices.DirectorySearcher(([ADSI]"LDAP://$dc"),$filter,@($attribute))

    $items = $searcher.FindAll()
    if ($items.Count -eq 0) {
        return "$prefix0001"
    }

    # Höchsten vorhandenen numerischen Wert extrahieren
    $maxIndex = 0
    foreach ($item in $items) {
        $val = $item.Properties[$attribute]
        if ($val -and $val.Count -gt 0) {
            $raw = $val[0].ToString().ToLower()
            if ($raw.StartsWith($prefix)) {
                $suffix = $raw.Substring($prefix.Length)
                if ([int]::TryParse($suffix, [ref]$null)) {
                    $num = [int]$suffix
                    if ($num -gt $maxIndex) { $maxIndex = $num }
                }
            }
        }
    }

    # Nächsten Namen generieren (z. B. gmb0012)
    $nextIndex = $maxIndex + 1
    return "{0}{1:D4}" -f $prefix, $nextIndex
}


function AddRemove-DistributionGroupPermissions {
    Param (
        [string]$distributionGroup,
        [string]$trustee,
        [bool]$writeMembers,
        [string]$action,
        [string]$dc
    )

    if ($writeMembers -eq $true) {

        try {
            $isMember = $null
            $isMember = Get-ADPermission $distributionGroup | ? {$_.User -like "$([Environment]::UserDomainName)\$trustee"} 
        } 
        catch {([Exception])
	        if ($_.Exception.InnerException) { $msg = $($_.Exception.InnerException.Message) } else { $msg = $($_.Exception.Message) }  	
	        Write-EventLog $global:logName -Source $global:logSourceName -EventId 3000 -Message "Error getting AD Permissions from DistributionGroup $($distributionGroup): $msg " -EntryType Error                  
        }

        if ($action -eq "ADD") {
            if ($isMember.Count -eq 0) {
                try {
                    Add-ADPermission -Identity $distributionGroup -User "$([Environment]::UserDomainName)\$trustee" -AccessRights WriteProperty -Properties “Member” -DomainController $dc | Out-Null        
                } 
                catch {([Exception])
	                if ($_.Exception.InnerException) { $msg = $($_.Exception.InnerException.Message) } else { $msg = $($_.Exception.Message) }  	
	                Write-EventLog $global:logName -Source $global:logSourceName -EventId 3000 -Message "Error adding WriteProperty Permissions for Trustee $trustee on DistributionGroup $($distributionGroup): $msg " -EntryType Error                  
                }
            }                       
        } else {
            if ($isMember.Count -gt 0) {
                try {
                    Remove-ADPermission -Identity $distributionGroup -User "$([Environment]::UserDomainName)\$trustee" -AccessRights WriteProperty -Properties "Member" -Confirm:$false | Out-Null
                } 
                catch {([Exception])
	                if ($_.Exception.InnerException) { $msg = $($_.Exception.InnerException.Message) } else { $msg = $($_.Exception.Message) }  	
	                Write-EventLog $global:logName -Source $global:logSourceName -EventId 3000 -Message "Error removing WriteProperty Permissions for Trustee $trustee on DistributionGroup $($distributionGroup): $msg " -EntryType Error                  
                }
            }                       
        }

        <#
        if ([string]::IsNullOrEmpty((Get-Mailbox $trustee).LinkedMasterAccount) -ne $true) {

            $legacyMasterAccount = (Get-Mailbox $trustee).LinkedMasterAccount
            
            if ($legacyMasterAccount -ne $null) {
                $isMember = $null
                $isMember = Get-ADPermission $distributionGroup | ? {$_.User -like "$legacyMasterAccount"} 

                if ($action -eq "ADD") {
                    if ($isMember -eq $null) {
                        Add-ADPermission -Identity $distributionGroup -User $legacyMasterAccount -AccessRights WriteProperty -Properties “Member” -DomainController $dc | Out-Null      
                    }                       
                } else {
                    if ($isMember -ne $null) {
                        Remove-ADPermission -Identity $distributionGroup -User $legacyMasterAccount -AccessRights WriteProperty -Properties "Member" -Confirm:$false | Out-Null
                    }                       
                }            
            
            }
        }
        #>
    }

} 

Function Send-EMail {
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

function Set-DlTenantState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [Microsoft.ActiveDirectory.Management.ADGroup] $Group,

        [Parameter(Mandatory = $true)]
        [ValidateSet("TenantEnable","TenantDisable")]
        [string] $Mode,

        [Parameter(Mandatory = $true)]
        [string] $CloudDomain
    )

    # AD Attribute
    $Attr_EntraFlag = "extensionAttribute15"

    $dn   = $Group.DistinguishedName
    $mail = $Group.mail

    switch ($Mode) {

        "TenantEnable" {

            if (-not ($mail -and $mail -match "@")) {
                Write-Host "User $($User.SamAccountName): Ungueltiges oder fehlendes mail-Attribut."
                return;    
            }

            # Local-Part aus Primary SMTP ableiten
            $localPart = $mail.Split("@")[0].ToLower()

            # Tenant-interne Cloud-Proxy-Adresse
            $cloudProxy = "smtp:$localPart@$CloudDomain"

            # ProxyAddresses sicher laden
            $currentProxies = @()
            if ($Group.proxyAddresses) {
                $currentProxies = $Group.proxyAddresses
            }

            # Cloud-Proxy hinzufügen (nur wenn nicht vorhanden)
            if ($currentProxies -notcontains $cloudProxy) {
                Set-ADGroup -Identity $dn -Add @{
                    proxyAddresses = $cloudProxy
                }
            }

            # extensionAttribute15 setzen
            Set-ADGroup -Identity $dn -Replace @{
                $Attr_EntraFlag = "EntraEnabled"
            }
        }

        "TenantDisable" {

            # extensionAttribute15 entfernen
            Set-ADGroup -Identity $dn -Clear $Attr_EntraFlag
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

$pshUser = "ksbl\ServiceIAMJobs10"
$pshSecret = "D:\iam\Secrets\serviceiamjobs10.sec"

$cloudDomain = "kantonsspitalbl.mail.onmicrosoft.com"

$global:logname = "KSBL Helpdesk GUI"
$global:logSourceName = "Process-DistributionsGroup"
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

$filesToProcess = Get-ChildItem -Recurse -Force $workingPath -ErrorAction SilentlyContinue | Where-Object { ( $_.Name -like "*AddDistributionListResponsibles*_pshjob_.csv") }

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
            $($workingFileEntry.ManagedByMembers) -ne $null -and 
            $($workingFileEntry.CurrentUserName) -ne $null -and 
            $($workingFileEntry.CurrentUserDomainName) -ne $null -and 
            $($workingFileEntry.CurrentUserEMailAddress)) {
        
            $msg = $null
            $htmlBody  = $null
            $htmlBody = "<p style=""Color:Black;font-weight:normal;Font-Size:smaller;font-family:Tahoma"">"
            $htmlBody += "Lieber Mitarbeiter, <br/><br/>"

            try {
                $distList = Get-DistributionGroup -Identity $($workingFileEntry.AdObjectName) -DomainController $dc
            } 
            catch {([Exception])
	            if ($_.Exception.InnerException) { $msg = $($_.Exception.InnerException.Message) } else { $msg = $($_.Exception.Message) }  	
	            Write-EventLog $global:logName -Source $global:logSourceName -EventId 3000 -Message "Error retrieving DistributionGroup $($workingFileEntry.AdObjectName): $msg " -EntryType Error                  
                Exit
            }

            if ($distList -ne $null) {

                #$Error.Clear()
                $msg = $null

                $primaryEMailAddress = "$(($distList.WindowsEmailAddress).Local)@$(($distList.WindowsEmailAddress).Domain)"

                try {
                    $existingManagers = (Get-DistributionGroup –identity $($workingFileEntry.AdObjectName)).ManagedBy
                    [string[]]$managedByMembers = $($workingFileEntry.ManagedByMembers).Split("!")
                } 
                catch {([Exception])
	                if ($_.Exception.InnerException) { $msg = $($_.Exception.InnerException.Message) } else { $msg = $($_.Exception.Message) }  	
	                Write-EventLog $global:logName -Source $global:logSourceName -EventId 3000 -Message "Error retrieving ManagedBy from DistributionGroup $($workingFileEntry.AdObjectName): $msg " -EntryType Error                  
                }
                

                foreach ($managedByMember in $managedByMembers) {
                    
                    if ($managedByMember.EndsWith("[DEL]")) {
                        $memberToAddRemove = $managedByMember.Split("[]")[0]
                        try {
                            Set-DistributionGroup –identity $($workingFileEntry.AdObjectName) -ManagedBy @{Remove=$($memberToAddRemove)} -BypassSecurityGroupManagerCheck -DomainController $dc -ErrorAction Ignore
                        } catch [System.Exception] {
                            if ($_.Exception.InnerException) { $msg = $($_.Exception.InnerException.Message) } else { $msg = $($_.Exception.Message) }
	                        Write-EventLog $global:logName -Source $global:logSourceName -EventId 3000 -Message "Error removing $memberToAddRemove from DistributionGroup $($workingFileEntry.AdObjectName): $msg " -EntryType Error                  
                            $htmlBody += "Während dem entferenen des Verantwortlichen $memberToAddRemove von der Verteilerliste <b> $($distList.DisplayName) </b> mit dem Login Name $($workingFileEntry.AdObjectName) ist folgender Fehler aufgetreten: <b> $($msg) </b><br/><br/>"                     
                        }                                    
                    }

                    if ($managedByMember.EndsWith("[ADD]")) {
                        $memberToAddRemove = $managedByMember.Split("[]")[0]
                        try {
                            Set-DistributionGroup –identity $($workingFileEntry.AdObjectName) -ManagedBy @{Add=$($memberToAddRemove)} -BypassSecurityGroupManagerCheck -DomainController $dc -ErrorAction Ignore
                        } catch [System.Exception] {
                            if ($_.Exception.InnerException) { $msg = $($_.Exception.InnerException.Message) } else { $msg = $($_.Exception.Message) }
	                        Write-EventLog $global:logName -Source $global:logSourceName -EventId 3000 -Message "Error adding $memberToAddRemove to DistributionGroup $($workingFileEntry.AdObjectName): $msg " -EntryType Error                  
                            $htmlBody += "Während dem hinzufügen des Verantwortlichen $memberToAddRemove auf der Verteilerliste <b> $($distList.DisplayName) </b> mit dem Login Name $($workingFileEntry.AdObjectName) ist folgender Fehler aufgetreten: <b> $($msg) </b><br/><br/>"                     
                        }                                    
                    }
                }

                <#
                $ownerList = @()
                foreach ($existingManager in $existingManagers) {

                    $existingManagerUserId = $existingManager.Split('/')[$existingManager.Split('/').Count - 1] 
                    if (-not $managedByMembers.Contains("$($existingManagerUserId)[DEL]")) {
                        $ownerList += $($existingManagerUserId)
                    }

                    foreach ($managedByMember in $managedByMembers)
                    {
                        if ($managedByMember.Contains("ADD")) {
                            if (-not $ownerList.Contains($($managedByMember.Split("[]")[0]))) {
                                $ownerList += $managedByMember.Split("[]")[0]
                            }
                        }                    
                    }
                    
                }

                try {
                    Set-DistributionGroup –identity $($workingFileEntry.AdObjectName) -ManagedBy $ownerList -BypassSecurityGroupManagerCheck -DomainController $dc -ErrorAction Ignore
                } catch [System.Exception] {
                    if ($_.Exception.InnerException) { $msg = $($_.Exception.InnerException.Message) } else { $msg = $($_.Exception.Message) }
	                Write-EventLog $global:logName -Source $global:logSourceName -EventId 3000 -Message "Error setting ManagedBy on DistributionGroup $($workingFileEntry.AdObjectName): $msg " -EntryType Error                  
                    $htmlBody += "Während dem Modifizieren des Verantwortlichen auf der Verteilerliste <b> $($distList.DisplayName) </b> mit dem Login Name $($workingFileEntry.AdObjectName) ist folgender Fehler aufgetreten: <b> $($msg) </b><br/><br/>"                     
                }                                    
                #>

                foreach ($item in $managedByMembers) {
                    
                    $managedByMember = $item.Split("[]")[0]
                    $permissionAction = $item.Split("[]")[1]

                    AddRemove-DistributionGroupPermissions -distributionGroup $($distList.Name) -trustee $managedByMember -action $permissionAction -writeMembers $true -dc $dc
                }

                #if ($Error.Count -gt 0) {
                if ($msg -eq $null) {

                    Write-Host "Die Berechtigungen auf der Verteilerliste $($distList.DisplayName) mit der E-Mail $($distList.PrimarySmtpAddress) as $($workingFileEntry.AdObjectName) wurde erfolgreich modifiziert." -ForegroundColor Green                
                    $htmlBody += "Die Berechtigungen auf der Verteilerliste <b> $($distList.DisplayName) </b> mit der E-Mail $($distList.PrimarySmtpAddress) und Alias Name $($workingFileEntry.AdObjectName) wurde erfolgreich modifiziert.<br/><br/>"                
                }
                    
                $htmlBody += "Viele Grüsse vom E-Mail Team</p>"
                Send-EMail -smtpHost $smtpHost -mailFrom $mailFrom -mailTo $($workingFileEntry.CurrentUserEMailAddress) -mailCc $mailCc -mailSubject "*** Auftrag - Berechtigungen einer Verteilerliste mutieren ***" -mailBody $htmlBody -attachment $null -user "ksbl\ServiceMailboxMove" -pwd "Basel1893"
            
            } else {
            
                Write-Host "Beim Modifizieren der der Verantwortlichen bei der Verteilerliste <b> $($distList.DisplayName) </b> mit dem Alias Name $($workingFileEntry.AdObjectName) ist folgender Fehler aufgetreten: Unable to find Distribution Group $($workingFileEntry.AdObjectName)" -ForegroundColor Red
                Write-EventLog $global:logName -Source $global:logSourceName -EventId 3000 -Message "Failed getting DistributionGroup $($workingFileEntry.AdObjectName) from Exchange: $msg " -EntryType Error                  
                $htmlBody += "Beim Modifizieren der der Verantwortlichen bei der Verteilerliste <b> $($distList.DisplayName) </b> mit dem Alias Name $($workingFileEntry.AdObjectName) ist folgender Fehler aufgetreten: <b> Unable to find Distribution Group $($workingFileEntry.AdObjectName) </b><br/><br/>"                     

                $htmlBody += "Viele Grüsse vom E-Mail Team</p>"
                Send-EMail -smtpHost $smtpHost -mailFrom $mailFrom -mailTo $($workingFileEntry.CurrentUserEMailAddress) -mailCc $mailCc -mailSubject "*** Auftrag - Berechtigungen einer Verteilerliste mutieren ***" -mailBody $htmlBody -attachment $null -user "ksbl\ServiceMailboxMove" -pwd "Basel1893"
            
            }
        }
    }

    if ($Host.Name -eq "ConsoleHost") {
        Stop-Transcript
    }

    Move-Item $($jobToProcess.FullName) ("D:\IAM\Archive\$($jobToProcess.Name)_{0:yyyyMMddhhmmss}.csv" -f (get-date))

}

$filesToProcess = Get-ChildItem $workingPath | Where-Object { ( $_.Name -like "*CreateDistributionList*_pshjob_.csv") } | Sort-Object LastWriteTime

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

            if ($($workingFileEntry.AdObjectName) -ne $null) {

                $workingFileEntry.AdObjectName = Enumerate-NextAvailableAdObjectName -objectType "vl" -dc $dc
            
                Write-Host "Creating DistributionGroup $($workingFileEntry.DisplayName) with E-Mail $($workingFileEntry.PrimarySmtpAddress) as $($workingFileEntry.AdObjectName) in $($workingFileEntry.OrgUnit)"                
                $msg = $null
                $distList = $null
                try {
                    $distList = New-DistributionGroup -Name $($workingFileEntry.DisplayName) -PrimarySmtpAddress $($workingFileEntry.PrimarySmtpAddress) -Alias $($workingFileEntry.AdObjectName) -SAMAccountName $($workingFileEntry.AdObjectName) -DisplayName $($workingFileEntry.DisplayName) -OrganizationalUnit $($workingFileEntry.OrgUnit) -Type "Security" -DomainController $dc
                } catch [System.Exception] {
                    if ($_.Exception.InnerException) { $msg = $($_.Exception.InnerException.Message) } else { $msg = $($_.Exception.Message) }
	                Write-EventLog $global:logName -Source $global:logSourceName -EventId 3000 -Message "Failed creating new DistributionGroup $($workingFileEntry.DisplayName) with E-Mail Address $($workingFileEntry.PrimarySmtpAddress): $msg " -EntryType Error                  
                    $htmlBody += "Während dem neu erstellen der Verteilerliste <b> $($distList.DisplayName) </b> mit dem Login Name $($workingFileEntry.AdObjectName) ist folgender Fehler aufgetreten: <b> $($msg) </b><br/><br/>"                     
                    Exit
                }

                Start-Sleep -Seconds 10

                <#
                try {
                    $distList = Get-DistributionGroup -Identity $($workingFileEntry.DisplayName) -DomainController $dc
                } 
                catch {([Exception])
	                if ($_.Exception.InnerException) { $msg = $($_.Exception.InnerException.Message) } else { $msg = $($_.Exception.Message) }  	
	                Write-EventLog $global:logName -Source $global:logSourceName -EventId 3000 -Message "Error retrieving DistributionGroup $($workingFileEntry.DisplayName) from Exchange: $msg " -EntryType Error                  
                }
                #>

                if ($distList -ne $null) {
                
                    #$Error.Clear()

                    if ($($workingFileEntry.HideInAb) -eq $true) {
                        
                        try {
                            Set-DistributionGroup –identity $($workingFileEntry.AdObjectName) -HiddenFromAddressListsEnabled $false -DomainController $dc                    
                        } catch [System.Exception] {
                            if ($_.Exception.InnerException) { $msg = $($_.Exception.InnerException.Message) } else { $msg = $($_.Exception.Message) }
	                        Write-EventLog $global:logName -Source $global:logSourceName -EventId 3000 -Message "Error setting HiddenFromAddressListsEnabled on DistributionGroup $($workingFileEntry.AdObjectName): $msg " -EntryType Error                  
                            $htmlBody += "Während dem Modifizieren des Attributes 'HiddenFromAddressListsEnabled' auf der Verteilerliste <b> $($distList.DisplayName) </b> mit dem Login Name $($workingFileEntry.AdObjectName) ist folgender Fehler aufgetreten: <b> $($msg) </b><br/><br/>"                     
                        }

                    }
                    
                    if ($($workingFileEntry.Manager) -ne $null) {
                    
                        $managedByMember = $($workingFileEntry.Manager).Split("[]")[0]
                        $permissionAction = "ADD"

                        try {
                            Set-DistributionGroup –identity $($workingFileEntry.AdObjectName) -ManagedBy $managedByMember -BypassSecurityGroupManagerCheck -DomainController $dc 
                        } catch [System.Exception] {
                            if ($_.Exception.InnerException) { $msg = $($_.Exception.InnerException.Message) } else { $msg = $($_.Exception.Message) }
	                        Write-EventLog $global:logName -Source $global:logSourceName -EventId 3000 -Message "Error setting ManagedBy on DistributionGroup $($workingFileEntry.AdObjectName): $msg " -EntryType Error                  
                            $htmlBody += "Während dem Modifizieren des Attributes 'ManagedBy' auf der Verteilerliste <b> $($distList.DisplayName) </b> mit dem Login Name $($workingFileEntry.AdObjectName) ist folgender Fehler aufgetreten: <b> $($msg) </b><br/><br/>"                     
                        }

                        AddRemove-DistributionGroupPermissions -distributionGroup $($distList.Name) -trustee $managedByMember -action $permissionAction -writeMembers $true -dc $dc
                    }

                    try
                    {
                        Set-ADGroup $($workingFileEntry.AdObjectName) -Description "Created on $(get-date) by $($workingFileEntry.CurrentUserName)" -Server $dc
                    } catch [System.Exception] {
                        if ($_.Exception.InnerException) { $msg = $($_.Exception.InnerException.Message) } else { $msg = $($_.Exception.Message) }
                        Write-EventLog $global:logName -Source $global:logSourceName -EventId 3000 -Message "Error setting Description on DistributionGroup $($workingFileEntry.AdObjectName): $msg " -EntryType Error                  
                        $htmlBody += "Während dem Modifizieren des Attributes 'Description' auf dem Active-Directory Object <b> $($distList.DisplayName) </b> mit dem Login Name $($workingFileEntry.AdObjectName) ist folgender Fehler aufgetreten: <b> $($msg) </b><br/><br/>"                     
                    }
                    
                    try {
                        Set-DistributionGroup –identity $($workingFileEntry.AdObjectName) -RequireSenderAuthenticationEnabled $false -DomainController $dc
                    } catch [System.Exception] {
                        if ($_.Exception.InnerException) { $msg = $($_.Exception.InnerException.Message) } else { $msg = $($_.Exception.Message) }
	                    Write-EventLog $global:logName -Source $global:logSourceName -EventId 3000 -Message "Error setting RequireSenderAuthenticationEnabled on DistributionGroup $($workingFileEntry.AdObjectName): $msg " -EntryType Error                  
                        $htmlBody += "Während dem Modifizieren des Attributes 'RequireSenderAuthenticationEnabled' auf der Verteilerliste <b> $($distList.DisplayName) </b> mit dem Login Name $($workingFileEntry.AdObjectName) ist folgender Fehler aufgetreten: <b> $($msg) </b><br/><br/>"                     
                    }

                    try {
                        Set-DistributionGroup $($workingFileEntry.AdObjectName) -AcceptMessagesOnlyFromSendersOrMembers((Get-DistributionGroup $($workingFileEntry.AdObjectName)).AcceptMessagesOnlyFromSendersOrMembers + "vl0286")
                    } catch [System.Exception] {
                        if ($_.Exception.InnerException) { $msg = $($_.Exception.InnerException.Message) } else { $msg = $($_.Exception.Message) }
	                    Write-EventLog $global:logName -Source $global:logSourceName -EventId 3000 -Message "Error setting AcceptMessagesOnlyFromSendersOrMembers on DistributionGroup $($workingFileEntry.AdObjectName): $msg " -EntryType Error                  
                        $htmlBody += "Während dem Modifizieren des Attributes 'AcceptMessagesOnlyFromSendersOrMembers' auf der Verteilerliste <b> $($distList.DisplayName) </b> mit dem Login Name $($workingFileEntry.AdObjectName) ist folgender Fehler aufgetreten: <b> $($msg) </b><br/><br/>"                     
                    }

                    Set-DlTenantState -Group $distList -Mode TenantEnable -CloudDomain $cloudDomain

                    #if ($Error.Count -gt 0) {
                    if ($msg -eq $null) {

                        Write-Host "Successfully created DistributionGroup $($workingFileEntry.DisplayName) with E-Mail $($workingFileEntry.PrimarySmtpAddress) as $($workingFileEntry.AdObjectName) in $($workingFileEntry.OrgUnit)" -ForegroundColor Green                
                        $htmlBody += "Die Verteilerliste <b> $($workingFileEntry.DisplayName) </b> mit der E-Mail $($workingFileEntry.PrimarySmtpAddress) und Alias Name $($workingFileEntry.AdObjectName) im AD Container $($workingFileEntry.OrgUnit) wurde erfolgreich erstellt.<br/><br/>"                

                    }
                    
                    $htmlBody += "Viele Grüsse vom E-Mail Team</p>"
                    Send-EMail -smtpHost $smtpHost -mailFrom $mailFrom -mailTo $($workingFileEntry.CurrentUserEMailAddress) -mailCc $mailCc -mailSubject "*** Auftrag - Erstellen einer Verteilerliste ***" -mailBody $htmlBody -attachment $null -user "ksbl\ServiceMailboxMove" -pwd "Basel1893"

                } else {

                    Write-Host "Nach dem Erstellen der Verteilerliste <b> $($workingFileEntry.DisplayName) </b> mit der E-Mail $($workingFileEntry.PrimarySmtpAddress) und Alias Name $($workingFileEntry.AdObjectName) im AD Container $($workingFileEntry.OrgUnit) ist folgender Fehler aufgetreten: Unable to find newly created Distribution Group $($workingFileEntry.DisplayName)" -ForegroundColor Red
                    Write-EventLog $global:logName -Source $global:logSourceName -EventId 3000 -Message "Unable to find newly created DistributionGroup $($workingFileEntry.DisplayName): $msg " -EntryType Error                  
                    $htmlBody += "Nach dem Erstellen der Verteilerliste <b> $($workingFileEntry.DisplayName) </b> mit der E-Mail $($workingFileEntry.PrimarySmtpAddress) und Alias Name $($workingFileEntry.AdObjectName) im AD Container $($workingFileEntry.OrgUnit) ist folgender Fehler aufgetreten: <b> Unable to find newly created Distribution Group $($workingFileEntry.DisplayName) </b><br/><br/>"                     

                    $htmlBody += "Viele Grüsse vom E-Mail Team</p>"
                    Send-EMail -smtpHost $smtpHost -mailFrom $mailFrom -mailTo $($workingFileEntry.CurrentUserEMailAddress) -mailCc $mailCc -mailSubject "*** Auftrag - Erstellen einer Verteilerliste ***" -mailBody $htmlBody -attachment $null -user "ksbl\ServiceMailboxMove" -pwd "Basel1893"
            
                }                                                 
            }
        }
    }

    if ($Host.Name -eq "ConsoleHost") {
        Stop-Transcript
    }

    Move-Item $($jobToProcess.FullName) ("D:\IAM\Archive\$($jobToProcess.Name)_{0:yyyyMMddhhmmss}.csv" -f (get-date))

}

$filesToProcess = Get-ChildItem -Recurse -Force $workingPath -ErrorAction SilentlyContinue | Where-Object { ( $_.Name -like "*ChangeManagerDistribList*_pshjob_.csv") }

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
                $distList = $null
                $distList = Get-DistributionGroup -Identity $($workingFileEntry.AdObjectName) -DomainController $dc
            } catch {([Exception])
	            if ($_.Exception.InnerException) { $msg = $($_.Exception.InnerException.Message) } else { $msg = $($_.Exception.Message) }  	
	            Write-EventLog $global:logName -Source $global:logSourceName -EventId 3000 -Message "Error retrieving DistributionGroup $($workingFileEntry.AdObjectName): $msg " -EntryType Error                  
                Exit
            }
                
            if ($distList -ne $null) {

                $msg = $null

                if ($($workingFileEntry.ManagerAdObjectName) -ne $null) {

                    try {
                        $existingManagers = (Get-DistributionGroup –identity $($workingFileEntry.AdObjectName)).ManagedBy
                    } catch {([Exception])
	                    if ($_.Exception.InnerException) { $msg = $($_.Exception.InnerException.Message) } else { $msg = $($_.Exception.Message) }  	
	                    Write-EventLog $global:logName -Source $global:logSourceName -EventId 3000 -Message "Error retrieving ManagedBy from DistributionGroup $($workingFileEntry.AdObjectName): $msg " -EntryType Error                  
                    }

                    [string[]]$managedByMembers = $($workingFileEntry.ManagerAdObjectName) #.Split("!")

                    $ownerList = @()
                    foreach ($existingManager in $existingManagers)
                    {
                        $ownerList += (Get-Mailbox $($existingManager)).SamAccountName 
                    }

                    foreach ($managedByMember in $managedByMembers)
                    {
                        if (-not $ownerList.Contains($($managedByMember)) ) {
                            $ownerList += $managedByMember #.Split("[]")[0]
                        }
                    }
                                        
                    try {
                        Set-DistributionGroup –identity $($distList.Name) -ManagedBy $ownerList -BypassSecurityGroupManagerCheck -DomainController $dc -ErrorAction Ignore
                    } catch {([Exception])
                        if ($_.Exception.InnerException) { $msg = $($_.Exception.InnerException.Message) } else { $msg = $($_.Exception.Message) }
                        Write-EventLog $global:logName -Source $global:logSourceName -EventId 3000 -Message "Error setting ManagedBy on DistributionGroup $($distList.Name): $msg " -EntryType Error                  
                        $htmlBody += "Während dem Modifizieren des Verantwortlichen auf der Verteilerliste <b> $($distList.DisplayName) </b> mit dem Login Name $($workingFileEntry.AdObjectName) ist folgender Fehler aufgetreten: <b> $($msg) </b><br/><br/>"                     
                    }

                    try {
                        Set-ADGroup –identity $($workingFileEntry.AdObjectName) -ManagedBy $($workingFileEntry.ManagerAdObjectName) -Server $dc
                    } catch {([Exception])
                        if ($_.Exception.InnerException) { $msg = $($_.Exception.InnerException.Message) } else { $msg = $($_.Exception.Message) }
                        Write-EventLog $global:logName -Source $global:logSourceName -EventId 3000 -Message "Error setting ManagedBy on DistributionGroup $($workingFileEntry.AdObjectName): $msg " -EntryType Error                  
                        $htmlBody += "Während dem Modifizieren des Verantwortlichen auf dem Active-Directory Object <b> $($distList.DisplayName) </b> mit dem Login Name $($workingFileEntry.AdObjectName) ist folgender Fehler aufgetreten: <b> $($msg) </b><br/><br/>"                     
                    }

                    AddRemove-DistributionGroupPermissions -distributionGroup $($distList.Name) -trustee $($workingFileEntry.ManagerAdObjectName) -action "ADD" -writeMembers $true -dc $dc

                }

                #if ($Error.Count -gt 0) {
                if ($msg -eq $null) {

                    Write-Host "Der Verantwortliche auf der Verteilerliste $($distList.DisplayName) wurde erfolgreich modifiziert" -ForegroundColor Green                
                    $htmlBody += "Der Verantwortliche auf der Verteilerliste <b> $($distList.DisplayName) </b> wurde erfolgreich modifiziert.<br/><br/>"                
                }
                    
                $htmlBody += "Viele Grüsse vom E-Mail Team</p>"
                Send-EMail -smtpHost $smtpHost -mailFrom $mailFrom -mailTo $($workingFileEntry.CurrentUserEMailAddress) -mailCc $mailCc -mailSubject "*** Auftrag - Verantwortlicher bei Verteilerliste mutieren ***" -mailBody $htmlBody -attachment $null -user "ksbl\ServiceMailboxMove" -pwd "Basel1893"


            } else {

                Write-Host "Während dem Modifizieren des Verantwortlichen auf dem Verteilerliste <b> $($distList.DisplayName) </b> ist folgender Fehler aufgetreten: Unable to find DistributionGroup $($workingFileEntry.AdObjectName)" -ForegroundColor Red
                Write-EventLog $global:logName -Source $global:logSourceName -EventId 3000 -Message "Unable to find DistributionGroup $($workingFileEntry.AdObjectName): $msg " -EntryType Error                  
                $htmlBody += "Während dem Modifizieren des Verantwortlichen auf dem Verteilerliste <b> $($distList.DisplayName) </b> ist folgender Fehler aufgetreten: <b> Unable to find DistributionGroup $($workingFileEntry.AdObjectName) </b><br/><br/>"                     

                $htmlBody += "Viele Grüsse vom E-Mail Team</p>"
                Send-EMail -smtpHost $smtpHost -mailFrom $mailFrom -mailTo $($workingFileEntry.CurrentUserEMailAddress) -mailCc $mailCc -mailSubject "*** Auftrag - Verantwortlicher bei Verteilerliste mutieren ***" -mailBody $htmlBody -attachment $null -user "ksbl\ServiceMailboxMove" -pwd "Basel1893"

            }
        }
    }

    if ($Host.Name -eq "ConsoleHost") {
        Stop-Transcript
    }

    Move-Item $($jobToProcess.FullName) "D:\IAM\Archive\$($jobToProcess.Name)" -Force -Confirm:$false

}

$filesToProcess = Get-ChildItem -Recurse -Force $workingPath -ErrorAction SilentlyContinue | Where-Object { ( $_.Name -like "*DeleteDistribList*_pshjob_.csv") }

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
            $($workingFileEntry.CurrentUserEMailAddress) -ne $null) {

            $msg = $null
            $htmlBody  = $null
            $htmlBody = "<p style=""Color:Black;font-weight:normal;Font-Size:smaller;font-family:Tahoma"">"
            $htmlBody += "Lieber Mitarbeiter, <br/><br/>"

            try {
                $distList = $null
                $distList = Get-DistributionGroup -Identity $($workingFileEntry.AdObjectName) -DomainController $dc
            } catch {([Exception])
	            if ($_.Exception.InnerException) { $msg = $($_.Exception.InnerException.Message) } else { $msg = $($_.Exception.Message) }  	
	            Write-EventLog $global:logName -Source $global:logSourceName -EventId 3000 -Message "Error retrieving DistributionGroup $($workingFileEntry.AdObjectName): $msg " -EntryType Error                  
                Exit
            }
                
            if ($distList -ne $null) {

                $msg = $null

                $ownerList = @()
                $ownerList += "$env:USERDOMAIN\$env:UserName"

                try {
                    Set-DistributionGroup –identity $($workingFileEntry.AdObjectName) -ManagedBy $ownerList -BypassSecurityGroupManagerCheck -DomainController $dc -ErrorAction Ignore
                } catch [System.Exception] {
                    if ($_.Exception.InnerException) { $msg = $($_.Exception.InnerException.Message) } else { $msg = $($_.Exception.Message) }
                    Write-EventLog $global:logName -Source $global:logSourceName -EventId 3000 -Message "Error setting ManagedBy on DistributionGroup $($workingFileEntry.AdObjectName): $msg " -EntryType Error                  
                    $htmlBody += "Während dem Modifizieren des Verantwortlichen auf der Verteilerliste <b> $($distList.DisplayName) </b> ist folgender Fehler aufgetreten: <b> $($msg) </b><br/><br/>"                     
                }
                
                Start-Sleep -Seconds 5

                #Set-DlTenantState -Group $distList -Mode TenantEnable -CloudDomain $cloudDomain

                try {
                    Remove-DistributionGroup -Identity $($workingFileEntry.AdObjectName) -DomainController $dc -Confirm:$false
                } catch [System.Exception] {
                    if ($_.Exception.InnerException) { $msg = $($_.Exception.InnerException.Message) } else { $msg = $($_.Exception.Message) }
                    Write-EventLog $global:logName -Source $global:logSourceName -EventId 3000 -Message "Error removing DistributionGroup $($workingFileEntry.AdObjectName) from Exchange: $msg " -EntryType Error                  
                    $htmlBody += "Während dem löschen der Verteilerliste <b> $($distList.DisplayName) </b> ist folgender Fehler aufgetreten: <b> $($msg) </b><br/><br/>"                     
                }

                if ($msg -eq $null) {

                    Write-Host "Die Verteilerliste $($distList.DisplayName) wurde erfolgreich gelöscht" -ForegroundColor Green                
                    $htmlBody += "Die Verteilerliste <b> $($distList.DisplayName) </b> wurde erfolgreich gelöscht.<br/><br/>"                
                }
                    
                $htmlBody += "Viele Grüsse vom E-Mail Team</p>"
                Send-EMail -smtpHost $smtpHost -mailFrom $mailFrom -mailTo $($workingFileEntry.CurrentUserEMailAddress) -mailCc $mailCc -mailSubject "*** Auftrag - Löschung einer Verteilerliste ***" -mailBody $htmlBody -attachment $null -user "ksbl\ServiceMailboxMove" -pwd "Basel1893"


            } else {

                Write-Host "Während dem löschen der Verteilerliste <b> $($distList.DisplayName) </b> ist folgender Fehler aufgetreten: Unable to find DL $($workingFileEntry.AdObjectName)" -ForegroundColor Red
                Write-EventLog $global:logName -Source $global:logSourceName -EventId 3000 -Message "Unable to find DistributionGroup $($workingFileEntry.AdObjectName): $msg " -EntryType Error                  
                $htmlBody += "Während dem löschen der Verteilerliste <b> $($distList.DisplayName) </b> ist folgender Fehler aufgetreten: Unable to find DL <b> $($workingFileEntry.AdObjectName) </b><br/><br/>"                     

                $htmlBody += "Viele Grüsse vom E-Mail Team</p>"
                Send-EMail -smtpHost $smtpHost -mailFrom $mailFrom -mailTo $($workingFileEntry.CurrentUserEMailAddress) -mailCc $mailCc -mailSubject "*** Auftrag - Löschung einer Verteilerliste mutieren ***" -mailBody $htmlBody -attachment $null -user "ksbl\ServiceMailboxMove" -pwd "Basel1893"

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