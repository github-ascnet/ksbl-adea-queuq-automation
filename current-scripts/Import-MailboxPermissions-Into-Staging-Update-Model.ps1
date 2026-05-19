
function Test-EventLog([String]$EventlogName, [String]$EventlogSource) {
    if (![System.Diagnostics.Eventlog]::SourceExists($EventlogName)) { 

        New-EventLog $EventlogName -Source $EventlogSource
        Write-EventLog $EventlogName -Source $EventlogSource -EventId 1 -Message "Event log $global:logName created on local machine." -EntryType Information
    } 
}

function InsertMailboxPermissionsIntoStaging {
    $currentObject = 0 
    $Results = @() 

    try {
        if ((Get-PSSession | ? { $_.State -like "Opened" -and $_.Availability -like "Available" }) -eq $null) {
            Get-PSSession | Remove-PSSession
            $cred = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList "ksbl\serviceiamjobs10" , (Get-Content "D:\iam\Secrets\serviceiamjobs10.sec" | ConvertTo-SecureString) 
            $PSSession = new-pssession –configurationname Microsoft.Exchange –connectionuri http://sv01250.ksbl.local/PowerShell –credential $cred -Authentication Kerberos 
            Import-PSSession $PSSession -AllowClobber
        }
    } catch {([Management.Automation.Remoting.PSRemotingTransportException], [Exception])
        if ($_.Exception.InnerException) { $msg = $($_.Exception.InnerException.Message) } else { $msg = $($_.Exception.Message) }  	
        Write-EventLog $global:logName -Source $global:logSourceName -EventId 500 -Message "Error creating a new Remote Exchange Powershell Connection: $msg " -EntryType Error                  
    }

    try {
        $sharedMailboxes = Get-AdUser -LdapFilter "(&(sAMAccountType=805306368)(msExchMailboxGuid=*)(employeeType=G))" -Properties *
        #$sharedMailboxes = Get-AdUser -LdapFilter "(&(sAMAccountType=805306368)(msExchMailboxGuid=*)(employeeType=G)(displayName=GMB-LI-Kardiologie))" -Properties *
    } catch { ([Exception])
        if ($_.Exception.InnerException) { $msg = $($_.Exception.InnerException.Message) } else { $msg = $($_.Exception.Message) }  	
        Write-EventLog $global:logName -Source $global:logSourceName -EventId 310 -Message "Error getting all Group Mailboxes from Exchange: $msg " -EntryType Error                        
        Exit
    }        

    $itemsCounter = $sharedMailboxes.Count
    foreach ($mailbox in $sharedMailboxes) {
            
        $currentObject += 1
        if ($currentObject.ToString().length -ge 3 -and $currentObject.ToString().Substring($currentObject.ToString().Length - 2, 2) -eq "00") {
            Write-EventLog $global:logName -Source $global:logSourceName -EventId 399 -Message "Group Mailboxes Completed: $($currentObject) - Percent Completed: $([Math]::Round(($currentObject / $($itemsCounter) * 100),1))%" -EntryType Information
        }        
        Write-Progress -Activity "Enumerating $itemsCounter Mailboxes with their Full Mailbox Permissions" -status "Processing Number $currentObject - Mailbox $($mailbox.DisplayName)" -PercentComplete ($currentObject / $itemsCounter * 100)        

        try {
            $permissions = $null
            $permissions = (Get-Acl -Path "AD:$($mailbox.DistinguishedName)").Access | 
                Where-Object {$_.ActiveDirectoryRights -eq "ExtendedRight" -and 
                $_.objectType -eq "ab721a54-1e2f-11d0-9819-00aa0040529b" -and 
                $_.IdentityReference.ToString().StartsWith("KSBL\") -and 
                ($_.IdentityReference.ToString() -notlike "NT AUTHORITY*" -or $_.IdentityReference.ToString() -notlike "S-1-5-*") -and 
                $_.IsInherited -eq $false}
        } catch {([Exception])
            if ($_.Exception.InnerException) { $msg = $($_.Exception.InnerException.Message) } else { $msg = $($_.Exception.Message) }  	
            Write-EventLog $global:logName -Source $global:logSourceName -EventId 311 -Message "Error getting AD Permissions from Mailbox $($mailbox.DisplayName): $msg " -EntryType Error                  
        }

        if ($permissions.Count -gt 0) {

            $Result = "" | Select-Object MailboxName, TrusteeName, TrusteeDomain, ObjectClass, AccessRight, AdReferenceObjectGuid, DistinguishedName, ExchHideFromAddressLists

            try {
                $Result.AdReferenceObjectGuid = "{$((Get-ADUser $mailbox.DistinguishedName).ObjectGUID)}"
            } catch {([Exception])
                if ($_.Exception.InnerException) { $msg = $($_.Exception.InnerException.Message) } else { $msg = $($_.Exception.Message) }  	
                Write-EventLog $global:logName -Source $global:logSourceName -EventId 312 -Message "Error getting Attribute ObjectGUID for User $($mailbox.DistinguishedName) from Active-Directory : $msg " -EntryType Error                  
            }

            try {
                $Result.DistinguishedName = "{$((Get-ADUser $mailbox.DistinguishedName).DistinguishedName)}"
            } catch {([Exception])
                if ($_.Exception.InnerException) { $msg = $($_.Exception.InnerException.Message) } else { $msg = $($_.Exception.Message) }  	
                Write-EventLog $global:logName -Source $global:logSourceName -EventId 313 -Message "Error getting Attribute DistinguishedName for User $($mailbox.DistinguishedName) from Active-Directory : $msg " -EntryType Error                  
            }

    		if ($mailbox.msExchHideFromAddressLists -ne $null) {
    			$Result.ExchHideFromAddressLists = [bool]$mailbox.msExchHideFromAddressLists
    		} 
    		else {
    			$Result.ExchHideFromAddressLists = $false
    		}	

            foreach ($item in $permissions) {            

                $Result.MailboxName = $mailbox.SamAccountName #$mailbox.Alias
                $Result.TrusteeName = if ($item.IdentityReference.Value -match "\\") { $item.IdentityReference.Value.Split("\\")[1] } else { $item.IdentityReference.Value }
                $Result.TrusteeDomain = if ($item.IdentityReference.Value -match "\\") { $item.IdentityReference.Value.Split("\\")[0] } 
                $Result.AccessRight = "SendAs" #($($item.ExtendedRights) -replace "-", "")

                if ([string]::IsNullOrEmpty($Result.TrusteeName)) {
                    $Result.ObjectClass = "unknown"
                } else {
                    try {
                        $Result.ObjectClass = (Get-AdObject -LDAPFilter "(name=$($Result.trusteeName))" -Server $Result.TrusteeDomain).ObjectClass
                        #$Result.ObjectClass = (New-Object System.DirectoryServices.DirectorySearcher([ADSI]"LDAP://$($env:userdnsdomain)", "(samaccountname=$($Result.trusteeName))", @('objectClass'))).FindOne().Properties['objectClass'] | select -Last 1
                    } catch {([Exception])
                        if ($_.Exception.InnerException) { $msg = $($_.Exception.InnerException.Message) } else { $msg = $($_.Exception.Message) }  	
                        Write-EventLog $global:logName -Source $global:logSourceName -EventId 314 -Message "Error Object Class by LDAP Filter (name=$($Result.trusteeName)) from Active-Directory : $msg " -EntryType Error                  
                    }
                }

                $Error.Clear()
                $sqlQuery = "INSERT INTO [KSBL_IAM].[dbo].[stg_MailboxPermissions]
                                    ([Name]
                                    ,[TrusteeName]
                                    ,[TrusteeDomain]
                                    ,[ObjectClass]
                                    ,[AcePermissions]
                                    ,[DistinguishedName]
                                    ,[ExchHideFromAddressLists]
                                    ,[AdReferenceObjectGuid]
                                    ,[StagingInserted])
                                VALUES
                                    (
                                    '$($Result.MailboxName)',
                                    '$($Result.TrusteeName)',
                                    '$($Result.TrusteeDomain)',
                                    '$($Result.ObjectClass)',
                                    '$($Result.AccessRight)',
                                    '$($Result.DistinguishedName)',
                                    '$($Result.ExchHideFromAddressLists)',
                                    '$($Result.AdReferenceObjectGuid)',
                                    GETDATE()
                                    )"            
                try {
                    Invoke-Sqlcmd -Query $sqlquery -ServerInstance "SV02037.ksbl.local"
                } catch {([System.Exception])
                    if ($_.Exception.InnerException) { $msg = $($_.Exception.InnerException.Message) } else { $msg = $($_.Exception.Message) }  
                    Write-EventLog $global:logName -Source $global:logSourceName -EventId 301 -Message "Failed executing SQL-Stmt $($sqlQuery): $msg " -EntryType Error                          	
                }
            }
        }
        
        try {
            $permissions = $null
            $permissions = Get-MailboxPermission -Identity $mailbox.mail | 
            where {
                $_.AccessRights -match "FullAccess" -and
                $_.user.tostring().StartsWith("KSBL\") -and
                $_.user.tostring() -ne "NT AUTHORITY\SELF" -and 
                $_.user.tostring() -notlike "S-1-5-21*" -and 
                $_.IsInherited -eq $false
            } #| Select Identity,User,@{Name='Access Rights';Expression={[string]::join(', ', $_.AccessRights)}} 
        } catch {([Exception])
            if ($_.Exception.InnerException) { $msg = $($_.Exception.InnerException.Message) } else { $msg = $($_.Exception.Message) }  	
            Write-EventLog $global:logName -Source $global:logSourceName -EventId 315 -Message "Error getting FullMailbox Permissions from Mailbox $($mailbox.DisplayName): $msg " -EntryType Error                  
        }

        if ($permissions.Count -gt 0) {
    
            $Result = "" | Select-Object MailboxName, TrusteeName, TrusteeDomain, ObjectClass, AccessRight, AdReferenceObjectGuid, DistinguishedName

            try {
                $Result.AdReferenceObjectGuid = "{$((Get-ADUser $mailbox.DistinguishedName).ObjectGUID)}"
            } catch {([Exception])
                if ($_.Exception.InnerException) { $msg = $($_.Exception.InnerException.Message) } else { $msg = $($_.Exception.Message) }  	
                Write-EventLog $global:logName -Source $global:logSourceName -EventId 316 -Message "Error getting Attribute ObjectGUID for User $($mailbox.DistinguishedName) from Active-Directory : $msg " -EntryType Error                  
            }

            try {
                $Result.DistinguishedName = "{$((Get-ADUser $mailbox.DistinguishedName).DistinguishedName)}"
            } catch {([Exception])
                if ($_.Exception.InnerException) { $msg = $($_.Exception.InnerException.Message) } else { $msg = $($_.Exception.Message) }  	
                Write-EventLog $global:logName -Source $global:logSourceName -EventId 317 -Message "Error getting Attribute DistinguishedName for User $($mailbox.DistinguishedName) from Active-Directory : $msg " -EntryType Error                  
            }

            foreach ($item in $permissions) {            
                $Result.MailboxName = $mailbox.SamAccountName #$mailbox.Alias
                $Result.TrusteeName = if ($item.User -match "\\") { $item.User.Split("\\")[1] } else { $item.User }
                $Result.TrusteeDomain = if ($item.User -match "\\") { $item.User.Split("\\")[0] } 
                $Result.AccessRight = ($($item.AccessRights) -replace ", ", "|")

                if ([string]::IsNullOrEmpty($Result.TrusteeName)) {
                    $Result.ObjectClass = "unknown"
                } else {
                    try {
                        $Result.ObjectClass = (Get-AdObject -LDAPFilter "(name=$($Result.trusteeName))" -Server $Result.TrusteeDomain).ObjectClass
                    } catch {([Exception])
                        if ($_.Exception.InnerException) { $msg = $($_.Exception.InnerException.Message) } else { $msg = $($_.Exception.Message) }  	
                        Write-EventLog $global:logName -Source $global:logSourceName -EventId 314 -Message "Error Object Class by LDAP Filter (name=$($Result.trusteeName)) from Active-Directory : $msg " -EntryType Error                  
                    }
                }

                $Error.Clear()
                $sqlQuery = "INSERT INTO [KSBL_IAM].[dbo].[stg_MailboxPermissions]
                                    ([Name]
                                    ,[TrusteeName]
                                    ,[TrusteeDomain]
                                    ,[ObjectClass]
                                    ,[AcePermissions]
                                    ,[DistinguishedName]
                                    ,[ExchHideFromAddressLists]
                                    ,[AdReferenceObjectGuid]
                                    ,[StagingInserted])
                                VALUES
                                    (
                                    '$($Result.MailboxName)',
                                    '$($Result.TrusteeName)',
                                    '$($Result.TrusteeDomain)',
                                    '$($Result.ObjectClass)',
                                    '$($Result.AccessRight)',
                                    '$($Result.DistinguishedName)',
                                    '$($Result.ExchHideFromAddressLists)',
                                    '$($Result.AdReferenceObjectGuid)',
                                    GETDATE()
                                    )"
                try {
                    Invoke-Sqlcmd -Query $sqlquery -ServerInstance "SV02037.ksbl.local"
                } catch {([System.Exception])
                    if ($_.Exception.InnerException) { $msg = $($_.Exception.InnerException.Message) } else { $msg = $($_.Exception.Message) }  
                    Write-EventLog $global:logName -Source $global:logSourceName -EventId 301 -Message "Failed executing SQL-Stmt $($sqlQuery): $msg " -EntryType Error                          	
                }
            }
        }
    }

    Get-PSSession | Remove-PSSession
    Write-Host "Done. We have processed $itemsCounter objects" -ForegroundColor Green
}

function MergeMailboxPermissionsIntoModel {

    $sqlQuery = "USE [KSBL_IAM]
                GO
				DECLARE @recordCount int 

				SET @recordCount = (SELECT COUNT(*) FROM [KSBL_IAM].[dbo].[stg_MailboxPermissions])
			
				IF (@recordCount > 1000)
				BEGIN
                    TRUNCATE TABLE [KSBL_IAM].[dbo].[MailboxPermissions]
                    INSERT INTO [KSBL_IAM].[dbo].[MailboxPermissions]
                               ([Name]
                               ,[TrusteeName]
                               ,[TrusteeDomain]
                               ,[AcePermissions]
                               ,[DistinguishedName]
                               ,[ExchHideFromAddressLists]
                               ,[AdReferenceObjectGuid]
                               ,[ModifiedBy]
                               ,[ModifiedOn])
                    SELECT [Name]
                          ,[TrusteeName]
                          ,[TrusteeDomain]
                          ,[AcePermissions]
                          ,[DistinguishedName]
                          ,[ExchHideFromAddressLists]
                          ,[AdReferenceObjectGuid]
	                      ,SYSTEM_USER
	                      ,GETDATE()
                    FROM [KSBL_IAM].[dbo].[stg_MailboxPermissions]
				END"

    try {
        Invoke-Sqlcmd -Query $sqlquery -ServerInstance "SV02037.ksbl.local"
    }
    catch {
 ([System.Exception])
        if ($_.Exception.InnerException) { $msg = $($_.Exception.InnerException.Message) } else { $msg = $($_.Exception.Message) }  
        Write-EventLog $global:logName -Source $global:logSourceName -EventId 301 -Message "Failed executing SQL-Stmt $($sqlQuery): $msg " -EntryType Error                          	
    }
}

Clear-Host

$global:logname = "KSBL IAM"
$global:logSourceName = "Import-MailboxPermissions-Into-Staging-Update-Model"
#[System.Diagnostics.EventLog]::CreateEventSource($global:logSourceName, $global:logname)
#Write-EventLog $global:logName -Source $global:logSourceName -EventId 1 -Message "EventSource created." -EntryType Information

try {
    if ((Get-Module | ? { $_.Name -eq "SqlServer" }) -eq $null) {
        Import-Module SqlServer
        c:
    }
} catch {([Exception])
    if ($_.Exception.InnerException) { $msg = $($_.Exception.InnerException.Message) } else { $msg = $($_.Exception.Message) }  	
    Write-EventLog $global:logName -Source $global:logSourceName -EventId 100 -Message "Error loading SqlServer PowerShell Modules: $msg " -EntryType Error                  
}

try {
    Import-Module ActiveDirectory
} catch {([Exception])
    if ($_.Exception.InnerException) { $msg = $($_.Exception.InnerException.Message) } else { $msg = $($_.Exception.Message) }  	
    Write-EventLog $global:logName -Source $global:logSourceName -EventId 200 -Message "Error loading ActiveDirectory PowerShell Modules: $msg " -EntryType Error                  
}

Write-EventLog $global:logname -Source $global:logSourceName -EventId 1 -Message "IAM group mailboxes staging job started at $(Get-Date)" -EntryType Information

$timeTakenToComplete = Measure-Command {

    try {
        $sqlQuery = "TRUNCATE TABLE [KSBL_IAM].[dbo].[stg_MailboxPermissions]"			
        Invoke-Sqlcmd -Query $sqlquery -ServerInstance "SV02037.ksbl.local"
    } catch {([System.Exception])
        if ($_.Exception.InnerException) { $msg = $($_.Exception.InnerException.Message) } else { $msg = $($_.Exception.Message) }  
        Write-EventLog $global:logName -Source $global:logSourceName -EventId 311 -Message "Failed executing SQL-Stmt $($sqlQuery): $msg " -EntryType Error                          	
    }

    InsertMailboxPermissionsIntoStaging

    MergeMailboxPermissionsIntoModel
}

Write-Host "IAM group mailboxes staging job finished after $([Math]::Round($timeTakenToComplete.TotalMinutes,0)) Minutes" -ForegroundColor Green
Write-EventLog $global:logname -Source $global:logSourceName -EventId 2 -Message "IAM group mailboxes staging job finished after $([Math]::Round($timeTakenToComplete.TotalMinutes,0)) Minutes" -EntryType Information
Write-EventLog $global:logname -Source $global:logSourceName -EventId 1 -Message "IAM group mailboxes staging job finished at $(Get-Date)" -EntryType Information
