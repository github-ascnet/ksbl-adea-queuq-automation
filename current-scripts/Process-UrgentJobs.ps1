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

$cSharpEnum = @"
        public enum UseCaseType {
                Aktivieren,
                Inaktivieren,
                Terminieren,
                Erstellen,
                Standortwechsel,
                Unbekannt
        }
"@
if (-not ([System.Management.Automation.PSTypeName]'UseCaseType').Type) { Add-Type -TypeDefinition $cSharpEnum }

$cSharpEnum = @"
        public enum GroupMembership {
                ADDMEMBER,
                REMOVEMEMBER,
                UNKNOWN
        }
"@
if (-not ([System.Management.Automation.PSTypeName]'GroupMembership').Type) { Add-Type -TypeDefinition $cSharpEnum }

function Write-SQL {
	[CmdletBinding()]
	[OutputType([System.Boolean])]
	param(
		[Parameter(Position=0, Mandatory=$true)]
		[ValidateNotNullOrEmpty()]
		[System.String]
		$sqlStatement
	)
	try {

        $cn = New-Object System.Data.SqlClient.SqlConnection		
        $cn.ConnectionString = "Server=SV02037.ksbl.local;Database=KSBL_Hospis_Staging;User ID=ksblhospis2ad;Password=L3tmein!"

		$cm = New-Object System.Data.SqlClient.SqlCommand
		$cm.Connection = $cn
		$cm.CommandText = $sqlStatement
		
		if (-not ($cn.State -like "Open")) {
			$cn.Open()
        }
		
        $dr = $cm.ExecuteScalar()
		
        $cm.Dispose()
		$cn.Close()
        return "Success"
		
	} catch { ([System.Data.SqlClient.SqlException])
	    if ($_.Exception.InnerException) { $msg = $($_.Exception.InnerException.Message) } else { $msg = $($_.Exception.Message) }  
    	Write-EventLog $global:logName -Source $global:logSourceName -EventId 7000 -Message "Failed executing SQL-Stmt $($sqlStatement): $msg " -EntryType Error                          	
        return $msg
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

function Update-GroupMemberships {
    [CmdletBinding()]
    [OutputType([int])]
    Param
    (
        [Parameter(Mandatory=$true,
                    ValueFromPipelineByPropertyName=$true,
                    Position=0)]
        $forestDomainController,
        [Parameter(Mandatory=$true,
                    ValueFromPipelineByPropertyName=$true,
                    Position=1)]
        $memberSamAccount,
        [Parameter(Mandatory=$true,
                    ValueFromPipelineByPropertyName=$true,
                    Position=2)]
        $groupName,
        [Parameter(Mandatory=$true,
                   ValueFromPipelineByPropertyName=$true,
                   Position=3)]
        $groupMembershipAction
    )


    if (-not [string]::IsNullOrEmpty($groupName)) {

        #$targetMemberships = Get-ADUser $memberSamAccount -Properties memberOf -Server $forestDomainController   

        try {
            $targetMemberships = Get-ADUser -LDAPFilter "(samaccountname=$memberSamAccount)" -Server $forestDomainController -Properties memberOf
        } catch {([Exception])
	        if ($_.Exception.InnerException) { $msg = $($_.Exception.InnerException.Message) } else { $msg = $($_.Exception.Message) }  	
	        Write-EventLog $global:logName -Source $global:logSourceName -EventId 7000 -Message "Error getting User $($memberSamAccount) from Active-Directory: $msg " -EntryType Error                  
        }

        $isMember = $false
        foreach ($membership in $($targetMemberships.MemberOf)) {
            if ($membership.Contains($groupName) -eq $true) {
                $isMember = $true
                break
            }
        }

        if ($isMember -eq $false -and $groupMembershipAction -eq [GroupMembership]::ADDMEMBER ) {
            try {
                Add-ADGroupMember -Identity $groupName -Members $memberSamAccount -Server $forestDomainController
                Write-Host "Successfully added $($memberSamAccount) into group $groupName on $forestDomainController" -ForegroundColor Green
                Write-EventLog $global:logName -Source $global:logSourceName -EventId 7000 -Message "Successfully added $($memberSamAccount) into group $groupName on $forestDomainController" -EntryType Information
            } catch {([Exception])
                if ($_.Exception.InnerException) { $msg = $($_.Exception.InnerException.Message) } else { $msg = $($_.Exception.Message) }  
        	    Write-Host "Failed adding $($memberSamAccount) into group $groupName on $forestDomainController. Error: $msg" -ForegroundColor Red
                Write-EventLog $global:logName -Source $global:logSourceName -EventId 7000 -Message "Failed adding $($memberSamAccount) into group $groupName on $forestDomainController. Error: $msg" -EntryType Error
                $global:ApplicationErrorCounter ++
            }    
        }

        if ($isMember -eq $true -and $groupMembershipAction -eq [GroupMembership]::REMOVEMEMBER ) {
            try {
                Remove-ADGroupMember -Identity $groupName -member $memberSamAccount -Server $forestDomainController -confirm:$false 
                Write-Host "Successfully removed $($memberSamAccount) from group $groupName on $forestDomainController" -ForegroundColor Green
                Write-EventLog $global:logName -Source $global:logSourceName -EventId 7000 -Message "Successfully removed $($memberSamAccount) from group $groupName on $forestDomainController" -EntryType Information
            } catch {([Exception])
                if ($_.Exception.InnerException) { $msg = $($_.Exception.InnerException.Message) } else { $msg = $($_.Exception.Message) }  
        	    Write-Host "Failed removing $($memberSamAccount) from group $groupName on $forestDomainController. Error: $msg" -ForegroundColor Red
                Write-EventLog $global:logName -Source $global:logSourceName -EventId 7000 -Message "Failed removing $($memberSamAccount) from group $groupName on $forestDomainController. Error: $msg" -EntryType Error
                $global:ApplicationErrorCounter ++
            }    
        }

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
	        Write-EventLog $global:logName -Source $global:logSourceName -EventId 7000 -Message "Failed enabling OWA and EAS for Exchange Mailbox $($mailboxName). Error: $msg" -EntryType Error                  
            Write-Host "Failed enabling OWA and EAS for Exchange Mailbox $($mailboxName). Error: $msg" -ForegroundColor Red
        }        

        try {
            Set-Mailbox $($mailboxName) -HiddenFromAddressListsEnabled $false
            Write-Host "Successfully enabled Addressbook view for Exchange Mailbox $($mailboxName)" -ForegroundColor Green
        } catch [System.Exception] {
            if ($_.Exception.InnerException) { $msg = $($_.Exception.InnerException.Message) } else { $msg = $($_.Exception.Message) }  
	        Write-EventLog $global:logName -Source $global:logSourceName -EventId 7000 -Message "Failed enabling Addressbook view for Exchange Mailbox $($mailboxName). Error: $msg" -EntryType Error                  
            Write-Host "Failed enabling Addressbook view for Exchange Mailbox $($mailboxName). Error: $msg" -ForegroundColor Red
        }
    }

    if ((Get-Mailbox $mailboxName).HiddenFromAddressListsEnabled -eq $false -and $objectState -eq [ObjectState]::HIDE ) {
        try {
            Set-CASMailbox -Identity $mailboxName -OWAEnabled $false -ActiveSyncEnabled $false
            Write-Host "Successfully disabled OWA and EAS for Exchange Mailbox $($mailboxName)" -ForegroundColor Green
        } catch [System.Exception] {
            if ($_.Exception.InnerException) { $msg = $($_.Exception.InnerException.Message) } else { $msg = $($_.Exception.Message) }  
	        Write-EventLog $global:logName -Source $global:logSourceName -EventId 7000 -Message "Failed disabling OWA and EAS for Exchange Mailbox $($mailboxName). Error: $msg" -EntryType Error                  
            Write-Host "Failed disabling OWA and EAS for Exchange Mailbox $($mailboxName). Error: $msg" -ForegroundColor Red
        }        

        try {
            Set-Mailbox $($mailboxName) -HiddenFromAddressListsEnabled $true
            Write-Host "Successfully disabled Addressbook view for Exchange Mailbox $($mailboxName)" -ForegroundColor Green
        } catch [System.Exception] {
            if ($_.Exception.InnerException) { $msg = $($_.Exception.InnerException.Message) } else { $msg = $($_.Exception.Message) }  
	        Write-EventLog $global:logName -Source $global:logSourceName -EventId 7000 -Message "Failed disabling Addressbook view for Exchange Mailbox $($mailboxName). Error: $msg" -EntryType Error                  
            Write-Host "Failed disabling Addressbook view for Exchange Mailbox $($mailboxName). Error: $msg" -ForegroundColor Red
        }
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

$logFilePath = "d:\IAM\Logs\$(($MyInvocation.MyCommand).Definition.Split("\")[2]).logs"

$jobsToProcess = $null
$primaryMailDomain = "ksbl.ch"
$workingPath = "d:\IAM\Queue"

$dc = [System.DirectoryServices.ActiveDirectory.Domain]::GetCurrentDomain().RidRoleOwner.Name
$dbServer = "SV02037.ksbl.local"
$db = "KSBL_IAM"

$pshUser = "ksbl\ServiceIAMJobs10"
$pshSecret = "D:\iam\Secrets\serviceiamjobs10.sec"

$global:AustrittOOOInternalMessage = "Sehr geehrte Damen und Herren </br></br> Dies ist eine automatische Abwesenheitsmeldung durch ein inaktives Postfach. Ihre E-Mail wird nicht gelesen oder weitergeleitet. </br></br> MfG </br> Kantonsspital Baselland"
$global:AustrittOOOExternalMessage = "Sehr geehrte Damen und Herren </br></br> Dies ist eine automatische Abwesenheitsmeldung durch ein inaktives Postfach. Ihre E-Mail wird nicht gelesen oder weitergeleitet. </br></br> MfG </br> Kantonsspital Baselland"

$cloudDomain = "kantonsspitalbl.mail.onmicrosoft.com"

$global:logname = "KSBL Helpdesk GUI"
$global:logSourceName = "Process-Urgent"
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

$filesToProcess = Get-ChildItem $workingPath | Where-Object { ( $_.Name -like "*Inaktivieren_HospisPersonUrgentUseCase*_pshjob_.csv") } | Sort-Object LastWriteTime

foreach ($jobToProcess in $filesToProcess) {

   if ($Host.Name -eq "ConsoleHost") {
        $ErrorActionPreference="SilentlyContinue"
        Stop-Transcript | out-null
        $ErrorActionPreference = "Continue"
        Start-Transcript -path "D:\IAM\Transcripts\Transcript_$($jobToProcess.Name).log" -append
    }

    Import-csv $($jobToProcess.FullName) | Out-File $logFilePath -Append

    $workingFile = Import-csv $($jobToProcess.FullName) -Delimiter "|" 
    foreach ($workingFileEntry in $workingFile) {

        if ($($workingFileEntry.ActionType) -ne $null -and 
            $($workingFileEntry.PersId) -ne $null -and 
            $($workingFileEntry.DisplayName) -ne $null -and
            $($workingFileEntry.MigrateUser) -ne $null -and 
            $($workingFileEntry.CurrentUserName) -ne $null -and 
            $($workingFileEntry.CurrentUserDomainName) -ne $null -and 
            $($workingFileEntry.CurrentUserEMailAddress)-ne $null) {

            $msg = $null
            $htmlBody  = $null
            $htmlBody = "<p style=""Color:Black;font-weight:normal;Font-Size:smaller;font-family:Tahoma"">"
            $htmlBody += "Lieber Mitarbeiter, <br/><br/>"
            
            $errorMsg = $null

            try {
                $resourceForestUserObjects = Get-ADUser -LDAPFilter "(employeeid=$($workingFileEntry.PersId))" -Properties mail,proxyAddresses,extensionAttribute6,msDS-cloudExtensionAttribute15,SamAccountName,mailNickname,AccountExpirationDate,mailNickname,homeMdb,memberof,extensionAttribute11 -Server $dc
            } catch {([Exception])
	            if ($_.Exception.InnerException) { $msg = $($_.Exception.InnerException.Message) } else { $msg = $($_.Exception.Message) }  	
	            Write-EventLog $global:logName -Source $global:logSourceName -EventId 7000 -Message "Error getting User $($workingFileEntry.PersId) from Active-Directory: $msg " -EntryType Error                  
            }

            if ($resourceForestUserObjects -ne $null) {

                foreach ($resourceForestUserObject in $resourceForestUserObjects) {
                
                    try {
                        Set-ADUser $resourceForestUserObject.SamAccountName -Enabled $false -Server $dc
                    } catch {([Exception])
	                    if ($_.Exception.InnerException) { $msg = $($_.Exception.InnerException.Message) } else { $msg = $($_.Exception.Message) }  	
	                    Write-EventLog $global:logName -Source $global:logSourceName -EventId 7000 -Message "Error disabling User $($resourceForestUserObject.SamAccountName): $msg " -EntryType Error                  
                    }

                    if (-not [string]::IsNullOrEmpty($resourceForestUserObject.homeMdb)) {

                        Change-MailboxFeaturesAndState -mailboxName $resourceForestUserObject.mailNickname -objectState ([ObjectState]::HIDE)
                        
                        try {
                            Set-MailboxAutoReplyConfiguration -Identity $resourceForestUserObject.SamAccountName -AutoReplyState Enabled -ExternalMessage $AustrittOOOExternalMessage -InternalMessage $AustrittOOOInternalMessage
                        } catch {([Exception])
	                        if ($_.Exception.InnerException) { $msg = $($_.Exception.InnerException.Message) } else { $msg = $($_.Exception.Message) }  	
	                        Write-EventLog $global:logName -Source $global:logSourceName -EventId 7000 -Message "Error setting MailboxAutoReplyConfiguration for Mailbox $($resourceForestUserObject.SamAccountName): $msg " -EntryType Error                  
                        }

					    try {
                            $sql = "UPDATE [KSBL_Hospis_Staging].[dbo].[EMailRevocations] SET [ValidTo] = GetDate() WHERE [Personalnummer] = '$($workingFileEntry.PersId)'"
                            Invoke-Sqlcmd -ServerInstance $dbServer -Query $sql -QueryTimeout 120
	                    } catch { ([System.Exception])
	                        if ($_.Exception.InnerException) { $msg = $($_.Exception.InnerException.Message) } else { $msg = $($_.Exception.Message) }  
    	                    Write-EventLog $global:logName -Source $global:logSourceName -EventId 6000 -Message "Failed executing SQL-Stmt $($sql): $msg " -EntryType Error                          	
	                    }                                        
                    }                            

                    foreach ($resourceForestUserObjectGroup in $resourceForestUserObject.memberof) {

                        if ($resourceForestUserObjectGroup.StartsWith("CN=TPL-") -eq $true) {                                                
                            Update-GroupMemberships `
                                    -memberSamAccount $resourceForestUserObject.SamAccountName `
                                    -groupName $resourceForestUserObjectGroup `
                                    -forestDomainController $dc `
                                    -groupMembershipAction ([GroupMembership]::REMOVEMEMBER)                                 
                        }

                        if ($resourceForestUserObjectGroup.StartsWith("CN=GG-KSBL-VDI-Remote") -eq $true) {                                            
                            Update-GroupMemberships `
                                    -memberSamAccount $resourceForestUserObject.SamAccountName `
                                    -groupName $resourceForestUserObjectGroup `
                                    -forestDomainController $dc `
                                    -groupMembershipAction ([GroupMembership]::REMOVEMEMBER)                                 
                        }

                        if ($resourceForestUserObjectGroup.StartsWith("CN=GG-OneSign") -eq $true) {                                            
                            Update-GroupMemberships `
                                -memberSamAccount $resourceForestUserObject.SamAccountName `
                                -groupName $resourceForestUserObjectGroup `
                                -forestDomainController $dc `
                                -groupMembershipAction ([GroupMembership]::REMOVEMEMBER)
                        }
                    }

                    # Disable Account for Entra-Sync
                    Set-TenantState -User $resourceForestUserObject -Mode TenantDisable -CloudDomain $cloudDomain

                    try {
                        Set-ADUser $($resourceForestUserObject.SamAccountName) -Clear extensionAttribute6 -ErrorAction Stop
                    } catch {([Exception])
                        if ($_.Exception.InnerException) { $msg = $($_.Exception.InnerException.Message) } else { $msg = $($_.Exception.Message) }  	
                        Write-EventLog $global:logName -Source $global:logSourceName -EventId 6500 -Message "Error clearing Attribute extensionAttribute6 for User $($resourceForestUserObject.SamAccountName): $msg " -EntryType Error                  
                    }

                    try {
                        Set-ADUser $($resourceForestUserObject.SamAccountName) -Clear msDS-cloudExtensionAttribute15 -ErrorAction Stop
                    } catch {([Exception])
                        if ($_.Exception.InnerException) { $msg = $($_.Exception.InnerException.Message) } else { $msg = $($_.Exception.Message) }  	
                        Write-EventLog $global:logName -Source $global:logSourceName -EventId 6600 -Message "Error clearing Attribute msDS-cloudExtensionAttribute15 for User $($resourceForestUserObject.SamAccountName): $msg " -EntryType Error                  
                    }

                    try {
                        Set-ADUser $($resourceForestUserObject.SamAccountName) -Description "Inaktiviert (Urgent) am $(get-date -Format "yyyy-MM-dd") von $($workingFileEntry.CurrentUserName)"
                    } catch {([Exception])
	                    if ($_.Exception.InnerException) { $msg = $($_.Exception.InnerException.Message) } else { $msg = $($_.Exception.Message) }  	
	                    Write-EventLog $global:logName -Source $global:logSourceName -EventId 7000 -Message "Error setting Description User $($resourceForestUserObject.SamAccountName): $msg " -EntryType Error                  
                    }

                    $htmlBody += "Das Benutzerkonto <b> $($resourceForestUserObject.SamAccountName) </b> wurde erfolgreich inaktiviert.<br/><br/>"
                    "Successfully completed job for $($resourceForestUserObject.SamAccountName) " | Out-File $logFilePath -Append              

                }

            }

            if ($($workingFileEntry.ActionType) -eq [UseCaseType]::Inaktivieren) {

				try {
                    $sql = "EXEC KSBL_Hospis_Staging.dbo.usp_create_urgent_inaktivieren_transaction '$($workingFileEntry.PersId)','$($workingFileEntry.CurrentUserDomainName)\$($workingFileEntry.CurrentUserName)'"
                    Invoke-Sqlcmd -ServerInstance $dbServer -Query $sql -QueryTimeout 120
	            } catch { ([System.Exception])
	                if ($_.Exception.InnerException) { $msg = $($_.Exception.InnerException.Message) } else { $msg = $($_.Exception.Message) }  
    	            Write-EventLog $global:logName -Source $global:logSourceName -EventId 6000 -Message "Failed executing SQL-Stmt $($sql): $msg " -EntryType Error                          	
	            }                                        
            }
                                       
            $htmlBody += "Viele Grüsse vom E-Mail Team</p>"                        
            Send-EMail -smtpHost $smtpHost -mailFrom $mailFrom -mailTo $($workingFileEntry.CurrentUserEMailAddress) -mailCc $mailCc -mailSubject "*** Auftrag - Hospis Person mit Benutzerkonto - Dringend Inaktivieren ***" -mailBody $htmlBody -attachment $null
    
        }
    }

    if ($Host.Name -eq "ConsoleHost") {
        Stop-Transcript
    }


    Move-Item $($jobToProcess.FullName) "D:\IAM\Archive\$($jobToProcess.Name)" -Force -Confirm:$false
}

Get-PSSession | Remove-PSSession