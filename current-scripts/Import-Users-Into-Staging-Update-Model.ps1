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
        
        $SMTPClient = New-Object Net.Mail.SmtpClient($smtpHost, 25) 
        $SMTPClient.Credentials = New-Object System.Net.NetworkCredential("ksbl\serviceiamjobs10", $(Get-Content D:\IAM\Secrets\serviceiamjobs10.sec | ConvertTo-SecureString)); 
        $SMTPClient.Send($mailMessage)
        
        Remove-Variable -Name SMTPClient
    } catch {([Exception])
	    if ($_.Exception.InnerException) { $msg = $($_.Exception.InnerException.Message) } else { $msg = $($_.Exception.Message) }  	
	    Write-EventLog $global:logName -Source $global:logSourceName -EventId 300 -Message "Error sending Summary-Mail $($mailSubject): $msg " -EntryType Error                  
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
            Write-Host "Failed enabling OWA and EAS for Exchange Mailbox $($mailboxName). Error: $msg" -ForegroundColor Red
	        Write-EventLog $global:logName -Source $global:logSourceName -EventId 230 -Message "Failed enabling OWA and EAS for Exchange Mailbox $($mailboxName). Error: $msg" -EntryType Error                  
        }        

        try {
            Set-Mailbox $($mailboxName) -HiddenFromAddressListsEnabled $false
            Write-Host "Successfully enabled Addressbook view for Exchange Mailbox $($mailboxName)" -ForegroundColor Green
        } catch [System.Exception] {
            if ($_.Exception.InnerException) { $msg = $($_.Exception.InnerException.Message) } else { $msg = $($_.Exception.Message) }  
            Write-Host "Failed enabling Addressbook view for Exchange Mailbox $($mailboxName). Error: $msg" -ForegroundColor Red
	        Write-EventLog $global:logName -Source $global:logSourceName -EventId 250 -Message "Failed enabling Addressbook view for Exchange Mailbox $($mailboxName). Error: $msg" -EntryType Error                  
        }
    }

    if ((Get-Mailbox $mailboxName).HiddenFromAddressListsEnabled -eq $false -and $objectState -eq [ObjectState]::HIDE ) {
        try {
            Set-CASMailbox -Identity $mailboxName -OWAEnabled $false -ActiveSyncEnabled $false
            Write-Host "Successfully disabled OWA and EAS for Exchange Mailbox $($mailboxName)" -ForegroundColor Green
        } catch [System.Exception] {
            if ($_.Exception.InnerException) { $msg = $($_.Exception.InnerException.Message) } else { $msg = $($_.Exception.Message) }  
            Write-Host "Failed disabling OWA and EAS for Exchange Mailbox $($mailboxName). Error: $msg" -ForegroundColor Red
	        Write-EventLog $global:logName -Source $global:logSourceName -EventId 240 -Message "Failed disabling OWA and EAS for Exchange Mailbox $($mailboxName). Error: $msg" -EntryType Error                  
        }        

        try {
            Set-Mailbox $($mailboxName) -HiddenFromAddressListsEnabled $true
            Write-Host "Successfully disabled Addressbook view for Exchange Mailbox $($mailboxName)" -ForegroundColor Green
        } catch [System.Exception] {
            if ($_.Exception.InnerException) { $msg = $($_.Exception.InnerException.Message) } else { $msg = $($_.Exception.Message) }  
            Write-Host "Failed disabling Addressbook view for Exchange Mailbox $($mailboxName). Error: $msg" -ForegroundColor Red
	        Write-EventLog $global:logName -Source $global:logSourceName -EventId 270 -Message "Failed disabling Addressbook view for Exchange Mailbox $($mailboxName). Error: $msg" -EntryType Error                  
        }
    }
}

function Test-EventLog([String]$EventlogName,[String]$EventlogSource)  {

    if (![System.Diagnostics.Eventlog]::SourceExists($EventlogName))  { 

		New-EventLog $EventlogName -Source $EventlogSource
		Write-EventLog $EventlogName -Source $EventlogSource -EventId 1 -Message "Event log $global:logName created on local machine." -EntryType Information
    } 
}

function Transform-MultivalueArrayList([Array]$multivalueArrayList) { 
    [String]$itemList = $null
    ForEach($item In $multivalueArrayList) {            
        $itemList = $itemList + $item + "|"        
    }
    #remove the last character
    $itemList = $itemList.Substring(0, $itemList.Length - 1)
    return $itemList
}

function Transpose-GUID([Object]$dsObject) { 
   [String]$tranposedGUId = $null
   $_nativGUID = $dsObject.psbase.nativeGUID
	   
   $tranposedGUId = "{" + $_nativGUID.SubString(6,2) + $_nativGUID.SubString(4,2) + $_nativGUID.SubString(2,2) `
	            + $_nativGUID.SubString(0,2) + "-" + $_nativGUID.SubString(10,2) + $_nativGUID.SubString(8,2) + "-" `
	            + $_nativGUID.SubString(14,2) + $_nativGUID.SubString(12,2) + "-" + $_nativGUID.SubString(16,2) `
	            + $_nativGUID.SubString(18,2) + "-" + $_nativGUID.SubString(20,12) + "}"
    return $tranposedGUId
}

function Translate-ExchRecipientTypeDetails {
	[CmdletBinding()]
	[OutputType([System.String])]
	param(
		[Parameter(Position=0, Mandatory=$true)]
		[ValidateNotNullOrEmpty()]
		[System.UInt32]
		$exchRecipientTypeDetails
	)
	try {

		switch ($exchRecipientTypeDetails) {
			1 {
				return "User Mailbox"				
				break
			}
			2 {
				return "Linked Mailbox"					
				break
			}
			4 {
				return "Shared Mailbox"					
				break
			}
			8 {
				return "Legacy Mailbox"
				break
			}
			16 {
				return "Room Mailbox"
				break
			}
			32 {
				return "Equipment Mailbox"
				break
			}
			64 {
				return "Mail Contact"
				break
			}
			128 {
				return "Mail-enabled User"
				break
			}
			4096 {
				return "Mail-enabled Public Folder"
				break
			}
			8192 {
				return "System Attendant Mailbox"
				break
			}
			16384 {
				return "Mailbox Database Mailbox"
				break
			}
			32768 {
				return "Across-Forest Mail Contact"
				break
			}
			65536 {
				return "User"
				break
			}
			131072 {
				return "Contact"
				break
			}
			2097152 {
				return "Disabled User"
				break
			}
			4194304 {
				return "Microsoft Exchange"
				break
			}
			2147483648 {
				return "Remote User Mailbox"
				break
			}

			default {
				return "Unknown: $exchRecipientTypeDetails"
				break
			}
		}

	}
	catch {
	}
}

function Translate-ExchRecipientDisplayType {
	[CmdletBinding()]
	[OutputType([System.String])]
	param(
		[Parameter(Position=0, Mandatory=$true)]
		[ValidateNotNullOrEmpty()]
		[System.Int32]
		$exchRecipientDisplayType
	)
	try {

		switch ($exchRecipientDisplayType) {
			-2147483642 {
				return "Remote Linked User Mailbox"				
				break
			}
			1073741824 {
				return "Linked Mailbox, Shared Mailbox, or User Mailbox"				
				break
			}
			7 {
				return "Room Mailbox"					
				break
			}
			8 {
				return "Equipment Mailbox"					
				break
			}
			6 {
				return "Mail User, Mail Contact"
				break
			}
			2 {
				return "Public Folder"
				break
			}
			0 {
				return "Unknown"
				break
			}
			default {
				return "Unknown: $exchRecipientDisplayType"
				break
			}
		}

	}
	catch {
	}
}

function Translate-UserAccountControlFlag {
	[CmdletBinding()]
	[OutputType([System.String])]
	param(
		[Parameter(Position=0, Mandatory=$true)]
		[ValidateNotNullOrEmpty()]
		[System.Int32]
		$userAccountControlFlag
	)
	try {

        $uacFlags = @("","ACCOUNTDISABLE","", "HOMEDIR_REQUIRED", "LOCKOUT", 
						"PASSWD_NOTREQD","PASSWD_CANT_CHANGE", "ENCRYPTED_TEXT_PWD_ALLOWED",
					 	"TEMP_DUPLICATE_ACCOUNT", "NORMAL_ACCOUNT", "","INTERDOMAIN_TRUST_ACCOUNT", 
					 	"WORKSTATION_TRUST_ACCOUNT", "SERVER_TRUST_ACCOUNT", "", "", "DONT_EXPIRE_PASSWORD", 
					 	"MNS_LOGON_ACCOUNT", "SMARTCARD_REQUIRED", "TRUSTED_FOR_DELEGATION", 
					 	"NOT_DELEGATED","USE_DES_KEY_ONLY", "DONT_REQ_PREAUTH",
					 	"PASSWORD_EXPIRED", "TRUSTED_TO_AUTH_FOR_DELEGATION")
		 	
		1..($uacFlags.length) | ? {$userAccountControlFlag -band [math]::Pow(2,$_)} | % { $userAccountControlText += $uacFlags[$_] + " " }
		return $userAccountControlText.Trim()

	}
	catch {
	}
}

function ConvertADSLargeInteger([object] $adsLargeInteger) {

	try {
		if ($adsLargeInteger -ne $null) {
	    
	   	$highPart = $adsLargeInteger.GetType().InvokeMember("HighPart", [System.Reflection.BindingFlags]::GetProperty, $null, $adsLargeInteger, $null)
	      $lowPart  = $adsLargeInteger.GetType().InvokeMember("LowPart",  [System.Reflection.BindingFlags]::GetProperty, $null, $adsLargeInteger, $null)

	      $bytes = [System.BitConverter]::GetBytes($highPart)
	      $tmp   = [System.Byte[]]@(0,0,0,0,0,0,0,0)
	      [System.Array]::Copy($bytes, 0, $tmp, 4, 4)
	      $highPart = [System.BitConverter]::ToInt64($tmp, 0)

	      $bytes = [System.BitConverter]::GetBytes($lowPart)
	      $lowPart = [System.BitConverter]::ToUInt32($bytes, 0)
	     
	      return $lowPart + $highPart
	    
	    } else {
	    
	      return $null
	    
	    }		
	} catch [System.Exception] {
#        if ($VerboseEnable -eq $true) {		
            if ($_.Exception.InnerException) {
    			Write-Host $_.Exception.InnerException.Message
            } else {
    			Write-Host $_.Exception.Message
    		}
#        }
		return $null
	}

}

function InsertUsersIntoStaging {
    #region Update staging table for user accounts with or without mailboxes

    $exchangeServerDomain = "ksbl.local"

    #[System.Object[]]$DomainNames = @("ksli.hbl","ksb.hbl","ksbl.local","ksla.local") 
    #foreach ($DomainName in $DomainNames) {

        try {
            $DomainName = [System.DirectoryServices.ActiveDirectory.Domain]::GetCurrentDomain().Name
        } 
        catch {([Exception])
	        if ($_.Exception.InnerException) { $msg = $($_.Exception.InnerException.Message) } else { $msg = $($_.Exception.Message) }  	
	        Write-EventLog $global:logName -Source $global:logSourceName -EventId 400 -Message "Error retrieving primary User Domain from Active-Directory: $msg " -EntryType Error                  
            Exit
        }

        [System.String]$LDAPPath = "LDAP://$DomainName"
        
        #if ($DomainName -eq $exchangeServerDomain) {
            #[System.String]$LDAPFilter = "(&(sAMAccountType=805306368) (!(description=Gelöscht mit Sync-Hospis2AD*)) (|(employeeType=P)(employeeType=G)(employeeType=GU)(employeeType=E)(employeeType=S)) )" 
            [System.String]$LDAPFilter = "(&(sAMAccountType=805306368) (|(employeeType=P)(employeeType=G)(employeeType=GU)(employeeType=E)(employeeType=S)(employeeType=HNP)(employeeType=A)) )" 
            #[System.String]$LDAPFilter = "(|(anr=us600)(anr=us23579)(anr=ex01224))" 
        #} else {
            #[System.String]$LDAPFilter = "(&(sAMAccountType=805306368)(!(userAccountControl:1.2.840.113556.1.4.803:=2))(extensionAttribute15=*))" 
            #[System.String]$LDAPFilter = "(|(&(sAMAccountType=805306368)(!(userAccountControl:1.2.840.113556.1.4.803:=2))(extensionAttribute15=*))(&(sAMAccountType=805306368)(extensionattribute11=User migrated:*)))"
        #}

        $Results = @()
        $currentObject = 0

        Write-Host "Searching objects matching the LDAP filter $($LDAPPath)/$($LDAPFilter)"
	        
        try {
	        $ds = New-Object System.DirectoryServices.DirectorySearcher([ADSI]$LDAPPath, $LDAPFilter, @('name','cn','sAMAccountName','sn','userPrincipalName','givenName','displayName','employeeType','employeeId','smsPasscodeMobile','smsPasscodeMobile','mailNickname','manager','streetAddress','PostalCode','st','l','telephoneNumber','mobile','facsimileTelephoneNumber','WwwHomePage','co','company','department','division','pwdLastSet','userAccountControl','lastLogonTimestamp','accountExpires','distinguishedName','objectGuid','description','extensionAttribute3','extensionAttribute6','extensionAttribute7','extensionAttribute11','extensionAttribute12','extensionAttribute14','targetAddress','ProxyAddresses','mail','msExchMailboxGuid','msExchRecipientTypeDetails','msExchRecipientDisplayType','legacyExchangeDN','msExchHideFromAddressLists','AltRecipient','hrmsBadgeFirstName','hrmsBadgeLastName','hrmsBirthdate','hrmsCostCenter','hrmsFunction','hrmsFunctionCategory','hrmsGender','hrmsJoinerDate','hrmsLeaverDate','hrmsMgmtLevelNumber','hrmsMgmtLevelNumberAdditive','hrmsOrgId','hrmsPhoneLocation','hrmsSKATDescription','hrmsSKATNumber','whenCreated','whenChanged','adspath'))
            $ds.Asynchronous = $true
	        $ds.CacheResults = $false
	        $ds.SearchScope = "SubTree" 
	        $ds.SizeLimit = 0
            $ds.PageSize = 100000    
            $itemsCounter = $ds.FindAll().Count
            Write-Host "For LDAP filter $($LDAPPath)/$($LDAPFilter) we have $($itemsCounter) objects"
	        $searchResult = $ds.FindAll().GetEnumerator() 
        } catch {([Exception])
	        if ($_.Exception.InnerException) { $msg = $($_.Exception.InnerException.Message) } else { $msg = $($_.Exception.Message) }  	
	        Write-EventLog $global:logName -Source $global:logSourceName -EventId 201 -Message "Error retrieving Active-Directory Users using LDAP-Filter $($LDAPFilter): $msg " -EntryType Error                  
            Exit
        }                

        foreach ($user in $searchResult) {
    
            try {
                if (-not $user.Path.Contains(",CN=Users,") -and -not $user.Path.Contains(",CN=Builtin,")) {

                    $currentObject = $currentObject + 1    	            
                    if ($currentObject.ToString().length -ge 4 -and $currentObject.ToString().Substring($currentObject.ToString().Length -3, 3) -eq "000") {
                        Write-EventLog $global:logName -Source $global:logSourceName -EventId 288 -Message "Active-Directory Users Completed: $($currentObject) - Percent Completed: $([Math]::Round(($currentObject / $($itemsCounter) * 100),1))%" -EntryType Information
                    }

                    Write-Progress -Activity "Enumerating $itemsCounter objects according to the LDAP filter $($LDAPFilter)" -status "Processing object $($currentObject) {$($user.Properties["name"][0])} ..." -PercentComplete ($currentObject / $itemsCounter * 100)        

                    $Result = "" | Select-Object Name,Cn,SAMAccountName,DisplayName,mailNickname,Title,Surname,UserPrincipalName,Givenname,Manager,EmployeeType,EmployeeId,SmsPasscodeMobile,StreetAddress,PostalCode,CountryState,City,TelephoneNumber,Mobile,FacsimileTelephoneNumber,HomePage,Country,Company,Department,Division,PwdLastSet,LastLogonTimestamp,AccountExpires,UserAccountControl,DistinguishedName,ObjectGuid,Description,ExtensionAttribute3,ExtensionAttribute6,ExtensionAttribute7,ExtensionAttribute8,ExtensionAttribute11,ExtensionAttribute12,ExtensionAttribute14,TargetAddress,ExchMailboxGuid,ExchRecipientTypeDetails,ExchRecipientDisplayType,LegacyExchangeDN,ExchHideFromAddressLists,Mail,ProxyAddresses,AltRecipient,HrmsBadgeFirstName,HrmsBadgeLastName,HrmsBirthdate,HrmsCostCenter,HrmsFunction,HrmsFunctionCategory,HrmsGender,HrmsJoinerDate,HrmsLeaverDate,HrmsMgmtLevelNumber,HrmsMgmtLevelNumberAdditive,HrmsOrgId,HrmsPhoneLocation,HrmsSKATDescription,HrmsSKATNumber,WhenCreated,WhenChanged,ADSPath
            
    	            $_nativGUID = $null
    	            $_tranposedGUId = $null
    	            $_pwdlastset = $null
                    $_pwdlastset = $null
    	            $_lastLogonTimestamp = $null
    	            $_lastLogonTimestamp = $null
    	            $_accountExpires = $null
    	            $_accountExpires = $null
    	            $_msExchRecipientTypeDetails = $null
                    $directoryInfofrom = $null
    	    		
    	            if ($user.Properties["adspath"][0].StartsWith("GC://")) {
                        $dsObject = [ADSI]($user.Properties["adspath"][0] -replace "GC://", "LDAP://")		
                    } else {
    		            $dsObject = [ADSI]$user.Properties["adspath"][0]
    	            }

                    $Result.ADSPath = $dsObject.Path
                    $Result.Name = $dsObject.Properties["name"][0]
                    $Result.Cn = $dsObject.Properties["cn"][0]
                    $Result.SAMAccountName = $dsObject.Properties["samaccountname"][0]
                    $Result.DisplayName = $dsObject.Properties["displayname"][0]
                    $Result.mailNickname = $dsObject.Properties["mailnickname"][0]
                    $Result.Title = $dsObject.Properties["title"][0]
                    $Result.Surname = $dsObject.Properties["sn"][0]
                    $Result.UserPrincipalName = $dsObject.Properties["userprincipalname"][0]
                    $Result.Givenname = $dsObject.Properties["givenname"][0]
                    $Result.Manager = $dsObject.Properties["manager"][0]
                    $Result.EmployeeType = $dsObject.Properties["employeetype"][0]
                    $Result.EmployeeId = $dsObject.Properties["employeeid"][0]                    
                    $Result.SmsPasscodeMobile = $dsObject.Properties["smsPasscodeMobile"][0]
                    $Result.StreetAddress = $dsObject.Properties["streetaddress"][0]
                    $Result.PostalCode = $dsObject.Properties["postalcode"][0]
                    $Result.CountryState = $dsObject.Properties["st"][0]
                    $Result.City = $dsObject.Properties["l"][0]
                    $Result.TelephoneNumber = $dsObject.Properties["telephonenumber"][0]
                    $Result.Mobile = $dsObject.Properties["mobile"][0]
                    $Result.FacsimileTelephoneNumber = $dsObject.Properties["facsimiletelephonenumber"][0]
                    $Result.HomePage = $dsObject.Properties["wwwhomepage"][0]
                    $Result.Country = $dsObject.Properties["co"][0]
                    $Result.Company = $dsObject.Properties["company"][0]
                    $Result.Department = $dsObject.Properties["department"][0]
                    $Result.Division = $dsObject.Properties["division"][0]
                    $Result.ExtensionAttribute3 = $dsObject.Properties["extensionattribute3"][0]
                    $Result.ExtensionAttribute6 = $dsObject.Properties["extensionattribute6"][0]
                    $Result.ExtensionAttribute7 = $dsObject.Properties["extensionattribute7"][0]
                    $Result.ExtensionAttribute8 = $dsObject.Properties["extensionattribute8"][0]
                    $Result.ExtensionAttribute11 = $dsObject.Properties["extensionattribute11"][0]
                    $Result.ExtensionAttribute12 = $dsObject.Properties["extensionattribute12"][0]
                    $Result.ExtensionAttribute14 = $dsObject.Properties["extensionattribute14"][0]
                    $Result.Mail = $dsObject.Properties["mail"][0]
                    $Result.TargetAddress = $dsObject.Properties["targetAddress"][0]
                    $Result.LegacyExchangeDN = $dsObject.Properties["legacyexchangedn"][0]
                    $Result.DistinguishedName = $dsObject.Properties["distinguishedname"][0]
                    $Result.WhenCreated = [DateTime]$dsObject.Properties["whencreated"][0]
                    $Result.WhenChanged = [DateTime]$dsObject.Properties["whenchanged"][0]                            

                    $Result.HrmsBadgeFirstName = $dsObject.Properties["HrmsBadgeFirstName"][0]
                    $Result.HrmsBadgeLastName = $dsObject.Properties["HrmsBadgeLastName"][0]
                    $Result.HrmsBirthdate = $dsObject.Properties["HrmsBirthdate"][0]
                    $Result.HrmsCostCenter = $dsObject.Properties["HrmsCostCenter"][0]
                    $Result.HrmsFunction = $dsObject.Properties["HrmsFunction"][0]
                    $Result.HrmsFunctionCategory = $dsObject.Properties["HrmsFunctionCategory"][0]
                    $Result.HrmsGender = $dsObject.Properties["HrmsGender"][0]
                    $Result.HrmsJoinerDate = $dsObject.Properties["HrmsJoinerDate"][0]
                    $Result.HrmsLeaverDate = $dsObject.Properties["HrmsLeaverDate"][0]
                    $Result.HrmsMgmtLevelNumber = $dsObject.Properties["HrmsMgmtLevelNumber"][0]
                    $Result.HrmsMgmtLevelNumberAdditive = $dsObject.Properties["HrmsMgmtLevelNumberAdditive"][0]
                    $Result.HrmsOrgId = $dsObject.Properties["HrmsOrgId"][0]
                    $Result.HrmsPhoneLocation = $dsObject.Properties["HrmsPhoneLocation"][0]
                    $Result.HrmsSKATDescription = $dsObject.Properties["HrmsSKATDescription"][0]
                    $Result.HrmsSKATNumber = $dsObject.Properties["HrmsSKATNumber"][0]

                    if ($Result.DisplayName -eq "Pamplaniyil Ilsamaria" -or $Result.DisplayName -eq "Ersoy Fulya") {
                        $Result
                    }

    	            if ($dsObject.userAccountControl[0] -ne $null) {
    		            $Result.UserAccountControl = Translate-UserAccountControlFlag -userAccountControlFlag $dsObject.userAccountControl[0]		
    	            } else {
    		            $Result.UserAccountControl = $null
    	            }
		    	    
    	            if ($dsObject.objectGuid -ne $null) {
    		            $_nativGUID = $dsObject.psbase.nativeGUID
    	                $_tranposedGUId = "{" + $_nativGUID.SubString(6,2) + $_nativGUID.SubString(4,2) + $_nativGUID.SubString(2,2) `
    	                        + $_nativGUID.SubString(0,2) + "-" + $_nativGUID.SubString(10,2) + $_nativGUID.SubString(8,2) + "-" `
    	                        + $_nativGUID.SubString(14,2) + $_nativGUID.SubString(12,2) + "-" + $_nativGUID.SubString(16,2) `
    	                        + $_nativGUID.SubString(18,2) + "-" + $_nativGUID.SubString(20,12) + "}"
    		            $Result.ObjectGuid = $_tranposedGUId		
    	            } else {
    		            $Result.ObjectGuid = $null
    	            }

    	            if ($dsObject.pwdlastset.value -ne $null) {
    		            $_pwdlastset = ConvertADSLargeInteger($dsObject.pwdlastset.value)
    	                $_pwdlastset = [DateTime]::FromFiletime([Int64]::Parse($_pwdlastset))
    	                if ($_pwdlastset -ne $null) {
    	   	            $Result.PwdLastSet = $_pwdlastset -f "ddmmyyyy"
    		            } else {
    	   	            $Result.PwdLastSet = $null
    		            }
    	    
    	            } else {
    		            $Result.PwdLastSet = $null    
    	            }
    		
    	            if ($dsObject.lastLogonTimestamp.value -ne $null) {
    		            $_lastLogonTimestamp = ConvertADSLargeInteger($dsObject.lastLogonTimestamp.value)
    	                $_lastLogonTimestamp = [DateTime]::FromFiletime([Int64]::Parse($_lastLogonTimestamp))    		
    	                if ($_lastLogonTimestamp -ne $null) {
    	   	            $Result.LastLogonTimestamp = $_lastLogonTimestamp -f "ddmmyyyy"
    		            } else {
    	   	            $Result.LastLogonTimestamp = $null
    		            }    
    	            } else {
    		            $Result.LastLogonTimestamp = $null    
    	            }

    	            if ($dsObject.accountExpires.value -ne $null) {
    	                    $_accountExpires = ConvertADSLargeInteger($dsObject.accountExpires.value)
    	    	            if ($_accountExpires -eq 9223372036854775807 -or $_accountExpires -eq 0) {
    				            $Result.AccountExpires = "01/01/9999 01:00:00"
    			            } else {
    				            $_accountExpires = [DateTime]::FromFiletime([Int64]::Parse($_accountExpires))    		
    		    	            if ($_accountExpires -ne $null) {
    		    		            $Result.AccountExpires = $_accountExpires -f "ddmmyyyy"
    				            } else {
    					            $Result.AccountExpires = $null
    		    	            }    
    			            }
    	            } else {
    		            $Result.AccountExpires = $null    
    	            }

                    if ($($dsObject.Properties["description"]) -ne $null) {
                        [System.Array]$arrayDescriptions = $($dsObject.Properties["description"])
                        $Result.Description = Transform-MultivalueArrayList $arrayDescriptions 
                    } else {
                        $Result.Description = [System.DBNull]::Value
                    }
        
                    if ($($dsObject.Properties["proxyaddresses"]) -ne $null) {
                        [System.Array]$arrayProxyAddresses = $($dsObject.Properties["proxyaddresses"])
                        $Result.ProxyAddresses = Transform-MultivalueArrayList $arrayProxyAddresses 
                    } else {
                        $Result.ProxyAddresses = [System.DBNull]::Value
                    }

    	            if ($dsObject.altRecipient -ne $null) {
    		            $Result.AltRecipient = $dsObject.altRecipient.ToString().split("=,")[1]
    	            } else {
    		            $Result.AltRecipient = $null
    	            }
    		    	
                    if ($DomainName -eq $exchangeServerDomain) {

    	                if ($dsObject.msExchMailboxGuid -ne $null) {
    			                
    		                $Result.ExchMailboxGuid = "{" + [guid]$dsObject.msExchMailboxGuid.psbase.value + "}"
    				
                            if ($dsObject.msExchRecipientTypeDetails.value -ne $null) {
    	    	                $_msExchRecipientTypeDetails = $dsObject.ConvertLargeIntegerToInt64($dsObject.msExchRecipientTypeDetails.value)
    	    	                if ($_msExchRecipientTypeDetails -ne $null) {
    	    		                $Result.ExchRecipientTypeDetails = Translate-ExchRecipientTypeDetails -exchRecipientTypeDetails $_msExchRecipientTypeDetails
    	    	                } else {
    	    		                $Result.ExchRecipientTypeDetails = $null
    	    	                }        
    	                    } else {
    	                        $Result.ExchRecipientTypeDetails = $null
    	                    }

    		                if ($dsObject.msExchRecipientDisplayType[0] -ne $null) {
    			                $Result.ExchRecipientDisplayType = Translate-ExchRecipientDisplayType -exchRecipientDisplayType $dsObject.msExchRecipientDisplayType[0]
    		                } else {
    			                $Result.ExchRecipientDisplayType = $null
    		                }

    			    			
    		                if ($dsObject.msExchHideFromAddressLists -ne $null) {
    			                $Result.ExchHideFromAddressLists = [bool]$dsObject.msExchHideFromAddressLists
    		                } 
    		                else {
    			                $Result.ExchHideFromAddressLists = $false
    		                }	
    					
    	                } else {

    		                $Result.ExchMailboxGuid = $null
    		                $Result.ExchRecipientTypeDetails = $null
    		                $Result.ExchRecipientDisplayType = $null
    		                $Result.ExchHideFromAddressLists = $null
    	                }

                    }


                    $Results = $Results + $Result
        
                    if ($dsObject -ne $null) {
                        if ($dsObject.psbase -eq $null) {
    	                    $dsObject.Dispose()
                        } else {
    	                    $dsObject.psbase.Dispose()
                        }
                    }        

	                if ($ds -ne $null) {
		                if ($ds.psbase -eq $null) {
			                $ds.Dispose()
		                } else {
			                $ds.psbase.Dispose()
		                }
	                }
    
                }
            } catch [System.DirectoryServices.DirectoryServicesCOMException] {

                if ($_.Exception.InnerException) { $msg = $($_.Exception.InnerException.Message) } else { $msg = $($_.Exception.Message) }  	
                Write-EventLog $global:logName -Source $global:logSourceName -EventId 100 -Message "Error getting Attributes for User $($user.Path) from Active-Directory: $msg " -EntryType Error                        

            } catch [System.Exception] {

                if ($_.Exception.InnerException) { $msg = $($_.Exception.InnerException.Message) } else { $msg = $($_.Exception.Message) }  	
                Write-EventLog $global:logName -Source $global:logSourceName -EventId 101 -Message "Error getting Attributes for User $($user.Path) from Active-Directory: $msg " -EntryType Error                        
            }

        }
    	
    #endregion

    #region Inserting Account and Mailbox data into the staging table

        $currentObject = 0

        foreach ($item in $Results) {
	    
            $currentObject = $currentObject + 1    	            
            if ($currentObject.ToString().length -ge 4 -and $currentObject.ToString().Substring($currentObject.ToString().Length -3, 3) -eq "000") {
                Write-EventLog $global:logName -Source $global:logSourceName -EventId 299 -Message "SQL Users Completed: $($currentObject) - Percent Completed: $([Math]::Round(($currentObject / $($results.length) * 100),1))%" -EntryType Information
            }

            Write-Progress -Activity "Updating/Inserting $($results.length) records into SQL Database" -status "Processing object $($currentObject) {$($item.Name)} ..." -PercentComplete ($currentObject / $($results.length) * 100)        
    	
	        if ($item.ObjectGuid -ne $null) {
	
    	        $itemGuid = $item.ObjectGuid        
                [DateTime]$itemWhenChanged = $item.WhenChanged 
    	        [DateTime]$itemWhenCreated = $item.WhenCreated 

    	        if ($item.PwdLastSet -ne $null) {
                    if ($item.PwdLastSet -eq "01/01/1601 01:00:00") {
       		           [DateTime]$itemPwdLastSet = "01/01/1900 01:00:00"        
                    } else {
    		          [DateTime]$itemPwdLastSet = $item.PwdLastSet
                    }
                } else {
                    [DateTime]$itemPwdLastSet = "01/01/1900 01:00:00"
                }

    	        if ($item.PwdLastSet -ne $null) {
                    if ($item.PwdLastSet -eq "01/01/1601 01:00:00") {
       		           [DateTime]$itemPwdLastSet = "01/01/1900 01:00:00"        
                    } else {
    		          [DateTime]$itemPwdLastSet = $item.PwdLastSet
                    }
                } else {
                    [DateTime]$itemPwdLastSet = "01/01/1900 01:00:00"
                }

    	        if ($item.LastLogonTimestamp -ne $null) {
    		        if ($item.LastLogonTimestamp -eq "01/01/1601 01:00:00") {
       		          [DateTime]$itemLastLogonTimestamp = "01/01/1900 01:00:00"        
                    } else {
    		          [DateTime]$itemLastLogonTimestamp = $item.LastLogonTimestamp
                    }
    	        } else {
       	            [DateTime]$itemLastLogonTimestamp = "01/01/1900 01:00:00"        
    	        }

                if ($item.AccountExpires -ne $null) {
                    if ($item.AccountExpires -eq "01/01/1601 01:00:00") {
       		           [DateTime]$itemAccountExpires = "01/01/1900 01:00:00"        
                    } else {
    		           [DateTime]$itemAccountExpires = $item.AccountExpires
                    }
    	        } else {
       	            [DateTime]$itemAccountExpires = "01/01/2099 01:00:00"        
    	        }

                if ($item.ExchHideFromAddressLists -eq $true) {
       	            $itemExchHideFromAddressLists = $true
    	        } elseif ($item.ExchHideFromAddressLists -eq $false) {
       	            $itemExchHideFromAddressLists = $false
    	        } else {
       	            $itemExchHideFromAddressLists = $null	
    	        }
        		      	
                $Error.Clear()	
                $sqlQuery = "SET DATEFORMAT dmy 
                            INSERT INTO [KSBL_IAM].[dbo].[stg_Accounts]
                               ([Name]
                               ,[Cn]
                               ,[SamAccountName]
                               ,[Title]
                               ,[SurName]
                               ,[GivenName]
                               ,[UserPrincipalName]
                               ,[DisplayName]
                               ,[Manager]
                               ,[EmployeeId]
                               ,[EmployeeType]
                               ,[SmsPasscodeMobile]
                               ,[Department]
                               ,[Division]
                               ,[Company]
                               ,[Description]
                               ,[StreetAddress]
                               ,[PostalCode]
                               ,[CountryState]
                               ,[City]
                               ,[Country]
                               ,[HomePage]
                               ,[telephoneNumber]
                               ,[facsimileTelephoneNumber]
                               ,[MobilephoneNumber]
                               ,[UserAccountControl]
                               ,[PwdLastSet]
                               ,[LastLogonTimestamp]
                               ,[AccountExpires]
                               ,[MailNickname]
                               ,[TargetAddress]
                               ,[ExchMailboxGuid]
                               ,[ExchRecipientTypeDetails]
                               ,[ExchRecipientDisplayType]
                               ,[LegacyExchangeDN]
                               ,[ExchHideFromAddressLists]
                               ,[Mail]
                               ,[ProxyAddresses]
                               ,[AltRecipient]
                               ,[DistinguishedName]
                               ,[AdReferenceObjectGuid]
                               ,[ExtensionAttribute1]
                               ,[ExtensionAttribute2]
                               ,[ExtensionAttribute3]
                               ,[ExtensionAttribute4]
                               ,[ExtensionAttribute5]
                               ,[ExtensionAttribute6]
                               ,[ExtensionAttribute7]
                               ,[ExtensionAttribute8]
                               ,[ExtensionAttribute9]
                               ,[ExtensionAttribute10]
                               ,[ExtensionAttribute11]
                               ,[ExtensionAttribute12]
                               ,[ExtensionAttribute13]
                               ,[ExtensionAttribute14]
                               ,[ExtensionAttribute15]
                               ,[hrmsBadgeFirstName]
                               ,[hrmsBadgeLastName]
                               ,[hrmsBirthdate]
                               ,[hrmsCostCenter]
                               ,[hrmsFunction]
                               ,[hrmsFunctionCategory]
                               ,[hrmsGender]
                               ,[hrmsJoinerDate]
                               ,[hrmsLeaverDate]
                               ,[hrmsMgmtLevelNumber]
                               ,[hrmsMgmtLevelNumberAdditive]
                               ,[hrmsOrgId]
                               ,[hrmsPhoneLocation]
                               ,[hrmsSKATDescription]
                               ,[hrmsSKATNumber]
                               ,[WhenCreated]
                               ,[WhenChanged]
                               ,[StagingInserted])
                        VALUES ('$($item.Name)',
                                '$($item.Cn)',
                                '$($item.SamAccountName)',
                                '$($item.Title  -replace "'", "''")',
                                '$($item.SurName  -replace "'", "''")',
                                '$($item.GivenName -replace "'", "''")',
                                '$($item.UserPrincipalName)',
                                '$($item.DisplayName -replace "'", "''")',
                                '$($item.Manager)',
                                '$($item.EmployeeId)',
                                '$($item.EmployeeType)',
                                '$($item.SmsPasscodeMobile)',
                                '$($item.Department -replace "'", "''")',
                                '$($item.Division)',
                                '$($item.Company -replace "'", "''")',
                                '$($item.Description -replace "'", "''")',
                                '$($item.StreetAddress -replace "'", "''")',
                                '$($item.PostalCode)',
                                '$($item.CountryState)',
                                '$($item.City -replace "'", "''")',
                                '$($item.Country -replace "'", "''")',
                                '$($item.HomePage)',
                                '$($item.telephoneNumber)',
                                '$($item.facsimileTelephoneNumber)',
                                '$($item.Mobile)',
                                '$($item.UserAccountControl)',
                                Convert(DateTime, '" + ($itemPwdLastSet -f "dd.mm.yyyy hh:mm:ss") + "', 120), 
                                Convert(DateTime, '" + ($itemLastLogonTimestamp -f "dd.mm.yyyy hh:mm:ss") + "', 120), 
                                Convert(DateTime, '" + ($itemAccountExpires -f "dd.mm.yyyy hh:mm:ss") + "', 120), 
                                '$($item.MailNickname)',
                                '$($item.TargetAddress -replace "'", "''")',
                                '$($item.ExchMailboxGuid)',
                                '$($item.ExchRecipientTypeDetails)',
                                '$($item.ExchRecipientDisplayType)',
                                '$($item.LegacyExchangeDN -replace "'", "''")',
                                '$itemExchHideFromAddressLists',
                                '$($item.Mail)',
                                '$($item.ProxyAddresses -replace "'", "''")',
                                '$($item.AltRecipient -replace "'", "''")',
                                '$($item.DistinguishedName -replace "'", "''")',
                                '$itemGuid',
                                '$($item.ExtensionAttribute1 -replace "'", "''")',
                                '$($item.ExtensionAttribute2 -replace "'", "''")',
                                '$($item.ExtensionAttribute3 -replace "'", "''")',
                                '$($item.ExtensionAttribute4 -replace "'", "''")',
                                '$($item.ExtensionAttribute5 -replace "'", "''")',
                                '$($item.ExtensionAttribute6 -replace "'", "''")',
                                '$($item.ExtensionAttribute7 -replace "'", "''")',
                                '$($item.ExtensionAttribute8 -replace "'", "''")',
                                '$($item.ExtensionAttribute9 -replace "'", "''")',
                                '$($item.ExtensionAttribute10 -replace "'", "''")',
                                '$($item.ExtensionAttribute11 -replace "'", "''")',
                                '$($item.ExtensionAttribute12 -replace "'", "''")',
                                '$($item.ExtensionAttribute13 -replace "'", "''")',
                                '$($item.ExtensionAttribute14 -replace "'", "''")',
                                '$($item.ExtensionAttribute15 -replace "'", "''")',
                                '$($item.HrmsBadgeFirstName -replace "'", "''")',
                                '$($item.HrmsBadgeLastName -replace "'", "''")',
                                '$($item.HrmsBirthdate)',
                                '$($item.HrmsCostCenter -replace "'", "''")',
                                '$($item.HrmsFunction -replace "'", "''")',
                                '$($item.HrmsFunctionCategory -replace "'", "''")',
                                '$($item.HrmsGender)',
                                '$($item.HrmsJoinerDate)',
                                '$($item.HrmsLeaverDate)',
                                '$($item.HrmsMgmtLevelNumber)',
                                '$($item.HrmsMgmtLevelNumberAdditive)',
                                '$($item.HrmsOrgId)',
                                '$($item.HrmsPhoneLocation)',
                                '$($item.HrmsSKATDescription -replace "'", "''")',
                                '$($item.HrmsSKATNumber)',
                                Convert(DateTime, '" + ($itemWhenCreated -f "dd.mm.yyyy hh:mm:ss") + "', 120), 
                                Convert(DateTime, '" + ($itemWhenChanged -f "dd.mm.yyyy hh:mm:ss") + "', 120), 
                                SYSDATETIME())"
    			
                try {
                    Invoke-Sqlcmd -Query $sqlquery -ServerInstance $iamServer
                } catch [System.Exception] {
                    if ($_.Exception.InnerException) { $errorMsg = $($_.Exception.InnerException.Message) } else { $errorMsg = $($_.Exception.Message) }
                    Write-EventLog $global:logName -Source $global:logSourceName -EventId 200 -Message "Query: $sqlQuery \r\n\r\nError: $errorMsg" -EntryType Error
                }
    		        
	        }    
        }

    #}

    #endregion

    Write-Host "Done. We have processed $($results.length) objects" -ForegroundColor Green
}

function MergeUsersIntoModel {

    $sqlQuery = "USE [KSBL_IAM]
                GO
				DECLARE @recordCount int 

				SET @recordCount = (SELECT COUNT(*) FROM stg_Accounts)
			
				IF (@recordCount > 9000)
				BEGIN

                    MERGE Accounts AS TARGET USING stg_Accounts AS SOURCE ON (TARGET.AdReferenceObjectGuid = SOURCE.AdReferenceObjectGuid) 
                    WHEN MATCHED 
	                    AND TARGET.[Name] <> SOURCE.[Name]
	                    OR TARGET.[Cn] <> SOURCE.[Cn]
	                    OR TARGET.[SamAccountName] <> SOURCE.[SamAccountName] 
	                    OR TARGET.[Title] <> SOURCE.[Title] 
	                    OR TARGET.[SurName] <> SOURCE.[SurName] 
	                    OR TARGET.[GivenName] <> SOURCE.[GivenName]  
	                    OR TARGET.[UserPrincipalName] <> SOURCE.[UserPrincipalName]
	                    OR TARGET.[DisplayName] <> SOURCE.[DisplayName]
	                    OR TARGET.[Manager] <> SOURCE.[Manager]
	                    OR TARGET.[EmployeeId] <> SOURCE.[EmployeeId]
	                    OR TARGET.[EmployeeType] <> SOURCE.[EmployeeType]
	                    OR TARGET.[SmsPasscodeMobile] <> SOURCE.[SmsPasscodeMobile]
	                    OR TARGET.[Department] <> SOURCE.[Department]
	                    OR TARGET.[Division] <> SOURCE.[Division]
	                    OR TARGET.[Company] <> SOURCE.[Company]
	                    OR TARGET.[Description] <> SOURCE.[Description]	                    
						OR TARGET.[StreetAddress] <> SOURCE.[StreetAddress] 
	                    OR TARGET.[PostalCode] <> SOURCE.[PostalCode] 
	                    OR TARGET.[CountryState] <> SOURCE.[CountryState]
	                    OR TARGET.[City] <> SOURCE.[City]
	                    OR TARGET.[Country] <> SOURCE.[Country]
	                    OR TARGET.[HomePage] <> SOURCE.[HomePage]
	                    OR TARGET.[telephoneNumber] <> SOURCE.[telephoneNumber] 
	                    OR TARGET.[facsimileTelephoneNumber] <> SOURCE.[facsimileTelephoneNumber]
	                    OR TARGET.[MobilephoneNumber] <> SOURCE.[MobilephoneNumber]
	                    OR TARGET.[UserAccountControl] <> SOURCE.[UserAccountControl]
	                    OR TARGET.[PwdLastSet] <> SOURCE.[PwdLastSet] 
	                    OR TARGET.[LastLogonTimestamp] <> SOURCE.[LastLogonTimestamp]
	                    OR TARGET.[AccountExpires] <> SOURCE.[AccountExpires] 
	                    OR TARGET.[MailNickname] <> SOURCE.[MailNickname] 
	                    OR TARGET.[TargetAddress] <> SOURCE.[TargetAddress] 
	                    OR TARGET.[ExchMailboxGuid] <> SOURCE.[ExchMailboxGuid]
	                    OR TARGET.[ExchRecipientTypeDetails] <> SOURCE.[ExchRecipientTypeDetails]
	                    OR TARGET.[ExchRecipientDisplayType] <> SOURCE.[ExchRecipientDisplayType]
	                    OR TARGET.[ExchHideFromAddressLists] <> SOURCE.[ExchHideFromAddressLists]
	                    OR TARGET.[Mail] <> SOURCE.[Mail]
	                    OR TARGET.[MailName] <> SOURCE.[MailName]
	                    OR TARGET.[MailDomainName] <> SOURCE.[MailDomainName]
	                    OR TARGET.[ProxyAddresses] <> SOURCE.[ProxyAddresses]
	                    OR TARGET.[AltRecipient] <> SOURCE.[AltRecipient]
	                    OR TARGET.[DistinguishedName] <> SOURCE.[DistinguishedName]
	                    OR TARGET.[ExtensionAttribute1] <> SOURCE.[ExtensionAttribute1]
	                    OR TARGET.[ExtensionAttribute2] <> SOURCE.[ExtensionAttribute2]
	                    OR TARGET.[ExtensionAttribute3] <> SOURCE.[ExtensionAttribute3]
	                    OR TARGET.[ExtensionAttribute4] <> SOURCE.[ExtensionAttribute4]
	                    OR TARGET.[ExtensionAttribute5] <> SOURCE.[ExtensionAttribute5]
	                    OR TARGET.[ExtensionAttribute6] <> SOURCE.[ExtensionAttribute6]
	                    OR TARGET.[ExtensionAttribute7] <> SOURCE.[ExtensionAttribute7]
	                    OR TARGET.[ExtensionAttribute8] <> SOURCE.[ExtensionAttribute8]
	                    OR TARGET.[ExtensionAttribute9] <> SOURCE.[ExtensionAttribute9]
	                    OR TARGET.[ExtensionAttribute10] <> SOURCE.[ExtensionAttribute10]
	                    OR TARGET.[ExtensionAttribute11] <> SOURCE.[ExtensionAttribute11]
	                    OR TARGET.[ExtensionAttribute12] <> SOURCE.[ExtensionAttribute12]
	                    OR TARGET.[ExtensionAttribute13] <> SOURCE.[ExtensionAttribute13]
	                    OR TARGET.[ExtensionAttribute14] <> SOURCE.[ExtensionAttribute14]
	                    OR TARGET.[ExtensionAttribute15] <> SOURCE.[ExtensionAttribute15]
                        OR TARGET.[HrmsBadgeFirstName] <> SOURCE.[HrmsBadgeFirstName]
                        OR TARGET.[HrmsBadgeLastName] <> SOURCE.[HrmsBadgeLastName]
                        OR TARGET.[HrmsBirthdate] <> SOURCE.[HrmsBirthdate]
                        OR TARGET.[HrmsCostCenter] <> SOURCE.[HrmsCostCenter]
                        OR TARGET.[HrmsFunction] <> SOURCE.[HrmsFunction]
                        OR TARGET.[HrmsFunctionCategory] <> SOURCE.[HrmsFunctionCategory]
                        OR TARGET.[HrmsGender] <> SOURCE.[HrmsGender]
                        OR TARGET.[HrmsJoinerDate] <> SOURCE.[HrmsJoinerDate]
                        OR TARGET.[HrmsLeaverDate] <> SOURCE.[HrmsLeaverDate]
                        OR TARGET.[HrmsMgmtLevelNumber] <> SOURCE.[HrmsMgmtLevelNumber]
                        OR TARGET.[HrmsMgmtLevelNumberAdditive] <> SOURCE.[HrmsMgmtLevelNumberAdditive]
                        OR TARGET.[HrmsOrgId] <> SOURCE.[HrmsOrgId]
                        OR TARGET.[HrmsPhoneLocation] <> SOURCE.[HrmsPhoneLocation]
                        OR TARGET.[HrmsSKATDescription] <> SOURCE.[HrmsSKATDescription]
                        OR TARGET.[HrmsSKATNumber] <> SOURCE.[HrmsSKATNumber]
	                    OR TARGET.[WhenCreated] <> SOURCE.[WhenCreated]
	                    OR TARGET.[WhenChanged] <> SOURCE.[WhenChanged]
                    THEN 
	                    UPDATE SET TARGET.[Name] = SOURCE.[Name]
		                    ,TARGET.[Cn] = SOURCE.[Cn]
		                    ,TARGET.[SamAccountName] = SOURCE.[SamAccountName] 
		                    ,TARGET.[Title] = SOURCE.[Title] 
		                    ,TARGET.[SurName] = SOURCE.[SurName] 
		                    ,TARGET.[GivenName] = SOURCE.[GivenName]  
		                    ,TARGET.[UserPrincipalName] = SOURCE.[UserPrincipalName]
		                    ,TARGET.[DisplayName] = SOURCE.[DisplayName]
		                    ,TARGET.[Manager] = SOURCE.[Manager]
		                    ,TARGET.[EmployeeId] = SOURCE.[EmployeeId]
		                    ,TARGET.[EmployeeType] = SOURCE.[EmployeeType]
		                    ,TARGET.[SmsPasscodeMobile] = SOURCE.[SmsPasscodeMobile]
		                    ,TARGET.[Department] = SOURCE.[Department]
		                    ,TARGET.[Division] = SOURCE.[Division]
		                    ,TARGET.[Company] = SOURCE.[Company]
		                    ,TARGET.[Description] = SOURCE.[Description]
		                    ,TARGET.[StreetAddress] = SOURCE.[StreetAddress] 
		                    ,TARGET.[PostalCode] = SOURCE.[PostalCode] 
		                    ,TARGET.[CountryState] = SOURCE.[CountryState]
		                    ,TARGET.[City] = SOURCE.[City]
		                    ,TARGET.[Country] = SOURCE.[Country]
		                    ,TARGET.[HomePage] = SOURCE.[HomePage]
		                    ,TARGET.[telephoneNumber] = SOURCE.[telephoneNumber] 
		                    ,TARGET.[facsimileTelephoneNumber] = SOURCE.[facsimileTelephoneNumber]
		                    ,TARGET.[MobilephoneNumber] = SOURCE.[MobilephoneNumber]
		                    ,TARGET.[UserAccountControl] = SOURCE.[UserAccountControl]
		                    ,TARGET.[PwdLastSet] = SOURCE.[PwdLastSet] 
		                    ,TARGET.[LastLogonTimestamp] = SOURCE.[LastLogonTimestamp]
		                    ,TARGET.[AccountExpires] = SOURCE.[AccountExpires] 
		                    ,TARGET.[MailNickname] = SOURCE.[MailNickname] 
		                    ,TARGET.[TargetAddress] = SOURCE.[TargetAddress] 
		                    ,TARGET.[ExchMailboxGuid] = SOURCE.[ExchMailboxGuid]
		                    ,TARGET.[ExchRecipientTypeDetails] = SOURCE.[ExchRecipientTypeDetails]
		                    ,TARGET.[ExchRecipientDisplayType] = SOURCE.[ExchRecipientDisplayType]
		                    ,TARGET.[ExchHideFromAddressLists] = SOURCE.[ExchHideFromAddressLists]
		                    ,TARGET.[Mail] = SOURCE.[Mail]
		                    ,TARGET.[ProxyAddresses] = SOURCE.[ProxyAddresses]
		                    ,TARGET.[AltRecipient] = SOURCE.[AltRecipient]
		                    ,TARGET.[DistinguishedName] = SOURCE.[DistinguishedName]
		                    ,TARGET.[ExtensionAttribute1] = SOURCE.[ExtensionAttribute1]
		                    ,TARGET.[ExtensionAttribute2] = SOURCE.[ExtensionAttribute2]
		                    ,TARGET.[ExtensionAttribute3] = SOURCE.[ExtensionAttribute3]
		                    ,TARGET.[ExtensionAttribute4] = SOURCE.[ExtensionAttribute4]
		                    ,TARGET.[ExtensionAttribute5] = SOURCE.[ExtensionAttribute5]
		                    ,TARGET.[ExtensionAttribute6] = SOURCE.[ExtensionAttribute6]
		                    ,TARGET.[ExtensionAttribute7] = SOURCE.[ExtensionAttribute7]
		                    ,TARGET.[ExtensionAttribute8] = SOURCE.[ExtensionAttribute8]
		                    ,TARGET.[ExtensionAttribute9] = SOURCE.[ExtensionAttribute9]
		                    ,TARGET.[ExtensionAttribute10] = SOURCE.[ExtensionAttribute10]
		                    ,TARGET.[ExtensionAttribute11] = SOURCE.[ExtensionAttribute11]
		                    ,TARGET.[ExtensionAttribute12] = SOURCE.[ExtensionAttribute12]
		                    ,TARGET.[ExtensionAttribute13] = SOURCE.[ExtensionAttribute13]
		                    ,TARGET.[ExtensionAttribute14] = SOURCE.[ExtensionAttribute14]
		                    ,TARGET.[ExtensionAttribute15] = SOURCE.[ExtensionAttribute15]
                            ,TARGET.[HrmsBadgeFirstName] = SOURCE.[HrmsBadgeFirstName]
                            ,TARGET.[HrmsBadgeLastName] = SOURCE.[HrmsBadgeLastName]
                            ,TARGET.[HrmsBirthdate] = SOURCE.[HrmsBirthdate]
                            ,TARGET.[HrmsCostCenter] = SOURCE.[HrmsCostCenter]
                            ,TARGET.[HrmsFunction] = SOURCE.[HrmsFunction]
                            ,TARGET.[HrmsFunctionCategory] = SOURCE.[HrmsFunctionCategory]
                            ,TARGET.[HrmsGender] = SOURCE.[HrmsGender]
                            ,TARGET.[HrmsJoinerDate] = SOURCE.[HrmsJoinerDate]
                            ,TARGET.[HrmsLeaverDate] = SOURCE.[HrmsLeaverDate]
                            ,TARGET.[HrmsMgmtLevelNumber] = SOURCE.[HrmsMgmtLevelNumber]
                            ,TARGET.[HrmsMgmtLevelNumberAdditive] = SOURCE.[HrmsMgmtLevelNumberAdditive]
                            ,TARGET.[HrmsOrgId] = SOURCE.[HrmsOrgId]
                            ,TARGET.[HrmsPhoneLocation] = SOURCE.[HrmsPhoneLocation]
                            ,TARGET.[HrmsSKATDescription] = SOURCE.[HrmsSKATDescription]
                            ,TARGET.[HrmsSKATNumber] = SOURCE.[HrmsSKATNumber]
		                    ,TARGET.[WhenCreated] = SOURCE.[WhenCreated]
		                    ,TARGET.[WhenChanged] = SOURCE.[WhenChanged]
		                    ,TARGET.[ModifiedBy] = SYSTEM_USER 
		                    ,TARGET.[ModifiedOn] = GETDATE()
                    WHEN NOT MATCHED BY TARGET THEN 
	                    INSERT (
		                    [Name]
		                    ,[Cn]
		                    ,[SamAccountName]
		                    ,[Title]
                            ,[SurName]
		                    ,[GivenName]
		                    ,[UserPrincipalName]
		                    ,[DisplayName]
		                    ,[Manager]
		                    ,[EmployeeId]
		                    ,[EmployeeType]
                            ,[SmsPasscodeMobile]
		                    ,[Department]
		                    ,[Division]
		                    ,[Company]
		                    ,[Description]
		                    ,[StreetAddress]
		                    ,[PostalCode]
		                    ,[CountryState]
		                    ,[City]
		                    ,[Country]
		                    ,[HomePage]
		                    ,[telephoneNumber]
		                    ,[facsimileTelephoneNumber]
		                    ,[MobilephoneNumber]
		                    ,[UserAccountControl]
		                    ,[PwdLastSet]
		                    ,[LastLogonTimestamp]
		                    ,[AccountExpires]
		                    ,[MailNickname]
		                    ,[TargetAddress]
		                    ,[ExchMailboxGuid]
		                    ,[ExchRecipientTypeDetails]
		                    ,[ExchRecipientDisplayType]
		                    ,[LegacyExchangeDN]
		                    ,[ExchHideFromAddressLists]
		                    ,[Mail]
		                    ,[ProxyAddresses]
		                    ,[AltRecipient]
		                    ,[DistinguishedName]
		                    ,[AdReferenceObjectGuid]
		                    ,[ExtensionAttribute1]
		                    ,[ExtensionAttribute2]
		                    ,[ExtensionAttribute3]
		                    ,[ExtensionAttribute4]
		                    ,[ExtensionAttribute5]
		                    ,[ExtensionAttribute6]
		                    ,[ExtensionAttribute7]
		                    ,[ExtensionAttribute8]
		                    ,[ExtensionAttribute9]
		                    ,[ExtensionAttribute10]
		                    ,[ExtensionAttribute11]
		                    ,[ExtensionAttribute12]
		                    ,[ExtensionAttribute13]
		                    ,[ExtensionAttribute14]
		                    ,[ExtensionAttribute15]
                            ,[HrmsBadgeFirstName]
                            ,[HrmsBadgeLastName]
                            ,[HrmsBirthdate]
                            ,[HrmsCostCenter]
                            ,[HrmsFunction]
                            ,[HrmsFunctionCategory]
                            ,[HrmsGender]
                            ,[HrmsJoinerDate]
                            ,[HrmsLeaverDate]
                            ,[HrmsMgmtLevelNumber]
                            ,[HrmsMgmtLevelNumberAdditive]
                            ,[HrmsOrgId]
                            ,[HrmsPhoneLocation]
                            ,[HrmsSKATDescription]
                            ,[HrmsSKATNumber]
		                    ,[WhenCreated]
		                    ,[WhenChanged]
		                    ,[ModifiedBy]
		                    ,[ModifiedOn]
	                    ) 
	                    VALUES (
		                    SOURCE.[Name]
		                    ,SOURCE.[Cn]
		                    ,SOURCE.[SamAccountName]
		                    ,SOURCE.[Title]
		                    ,SOURCE.[SurName]
		                    ,SOURCE.[GivenName]
		                    ,SOURCE.[UserPrincipalName]
		                    ,SOURCE.[DisplayName]
		                    ,SOURCE.[Manager]
		                    ,SOURCE.[EmployeeId]
		                    ,SOURCE.[EmployeeType]
		                    ,SOURCE.[SmsPasscodeMobile]
		                    ,SOURCE.[Department]
		                    ,SOURCE.[Division]
		                    ,SOURCE.[Company]
		                    ,SOURCE.[Description]
		                    ,SOURCE.[StreetAddress]
		                    ,SOURCE.[PostalCode]
		                    ,SOURCE.[CountryState]
		                    ,SOURCE.[City]
		                    ,SOURCE.[Country]
		                    ,SOURCE.[HomePage]
		                    ,SOURCE.[telephoneNumber]
		                    ,SOURCE.[facsimileTelephoneNumber]
		                    ,SOURCE.[MobilephoneNumber]
		                    ,SOURCE.[UserAccountControl]
		                    ,SOURCE.[PwdLastSet]
		                    ,SOURCE.[LastLogonTimestamp]
		                    ,SOURCE.[AccountExpires]
		                    ,SOURCE.[MailNickname]
		                    ,SOURCE.[TargetAddress]
		                    ,SOURCE.[ExchMailboxGuid]
		                    ,SOURCE.[ExchRecipientTypeDetails]
		                    ,SOURCE.[ExchRecipientDisplayType]
		                    ,SOURCE.[LegacyExchangeDN]
		                    ,SOURCE.[ExchHideFromAddressLists]
		                    ,SOURCE.[Mail]
		                    ,SOURCE.[ProxyAddresses]
		                    ,SOURCE.[AltRecipient]
		                    ,SOURCE.[DistinguishedName]
		                    ,SOURCE.[AdReferenceObjectGuid]
		                    ,SOURCE.[ExtensionAttribute1]
		                    ,SOURCE.[ExtensionAttribute2]
		                    ,SOURCE.[ExtensionAttribute3]
		                    ,SOURCE.[ExtensionAttribute4]
		                    ,SOURCE.[ExtensionAttribute5]
		                    ,SOURCE.[ExtensionAttribute6]
		                    ,SOURCE.[ExtensionAttribute7]
		                    ,SOURCE.[ExtensionAttribute8]
		                    ,SOURCE.[ExtensionAttribute9]
		                    ,SOURCE.[ExtensionAttribute10]
		                    ,SOURCE.[ExtensionAttribute11]
		                    ,SOURCE.[ExtensionAttribute12]
		                    ,SOURCE.[ExtensionAttribute13]
		                    ,SOURCE.[ExtensionAttribute14]
		                    ,SOURCE.[ExtensionAttribute15]
                            ,SOURCE.[HrmsBadgeFirstName]
                            ,SOURCE.[HrmsBadgeLastName]
                            ,SOURCE.[HrmsBirthdate]
                            ,SOURCE.[HrmsCostCenter]
                            ,SOURCE.[HrmsFunction]
                            ,SOURCE.[HrmsFunctionCategory]
                            ,SOURCE.[HrmsGender]
                            ,SOURCE.[HrmsJoinerDate]
                            ,SOURCE.[HrmsLeaverDate]
                            ,SOURCE.[HrmsMgmtLevelNumber]
                            ,SOURCE.[HrmsMgmtLevelNumberAdditive]
                            ,SOURCE.[HrmsOrgId]
                            ,SOURCE.[HrmsPhoneLocation]
                            ,SOURCE.[HrmsSKATDescription]
                            ,SOURCE.[HrmsSKATNumber]
		                    ,SOURCE.[WhenCreated]
		                    ,SOURCE.[WhenChanged]
		                    ,SYSTEM_USER
		                    ,GETDATE()
	                    )
                    WHEN NOT MATCHED BY SOURCE THEN 
	                    DELETE;
                    SELECT @@ROWCOUNT;
                    
                    END

                    GO"

    try {
        Invoke-Sqlcmd -Query $sqlquery -ServerInstance $iamServer
    } catch { ([System.Exception])
	    if ($_.Exception.InnerException) { $msg = $($_.Exception.InnerException.Message) } else { $msg = $($_.Exception.Message) }  
        Write-EventLog $global:logName -Source $global:logSourceName -EventId 201 -Message "Failed executing SQL-Stmt $($sqlQuery): $msg " -EntryType Error                          	
    }

}


function UpdateHospisPersonsHistory {

    try {
        $sqlQuery = "TRUNCATE TABLE [KSBL_IAM].[dbo].[PersonsHistory]"
        Invoke-Sqlcmd -Query $sqlQuery -ServerInstance $iamServer
    } catch { ([System.Exception])
	    if ($_.Exception.InnerException) { $msg = $($_.Exception.InnerException.Message) } else { $msg = $($_.Exception.Message) }  
        Write-EventLog $global:logName -Source $global:logSourceName -EventId 202 -Message "Failed executing SQL-Stmt $($sqlQuery): $msg " -EntryType Error                          	
    }
    
    $sqlQuery = "WITH CTE AS (
	                SELECT rn = ROW_NUMBER() OVER (PARTITION BY Personalnummer,Eintrittsdatum, Austrittsdatum ORDER BY Eintrittsdatum DESC) 
		                ,ImportDate
		                ,Personalnummer
		                ,Mitarbeiterstatus
		                ,Ganzer_Name
		                ,Convert(date, Eintrittsdatum) Eintrittsdatum
		                ,Convert(date, Austrittsdatum) Austrittsdatum
	                FROM [KSBL_Hospis_Staging].[dbo].[ImportData] 
	                WHERE Personalnummer != ''
                )
                INSERT INTO [KSBL_IAM].[dbo].[PersonsHistory]
		                   ([ImportDate]
                           ,[Personalnummer]
                           ,[Mitarbeiterstatus]
                           ,[Ganzer_Name]
                           ,[Eintrittsdatum]
                           ,[Austrittsdatum])
                SELECT ImportDate
		                ,Personalnummer
		                ,Mitarbeiterstatus
		                ,Ganzer_Name
		                ,Eintrittsdatum
		                ,Austrittsdatum 
                FROM CTE WHERE rn = 1
                ORDER BY Personalnummer, ImportDate DESC"

    try {
        Invoke-Sqlcmd -Query $sqlQuery -ServerInstance $iamServer
    } catch { ([System.Exception])
	    if ($_.Exception.InnerException) { $msg = $($_.Exception.InnerException.Message) } else { $msg = $($_.Exception.Message) }  
        Write-EventLog $global:logName -Source $global:logSourceName -EventId 203 -Message "Failed executing SQL-Stmt $($sqlQuery): $msg " -EntryType Error                          	
    }

}

function UpdateHospisPersonsDuplicates {

    try {
        $sqlQuery = "TRUNCATE TABLE [KSBL_IAM].[dbo].[PersonsDuplicates]"
        Invoke-Sqlcmd -Query $sqlQuery -ServerInstance $iamServer
    } catch { ([System.Exception])
	    if ($_.Exception.InnerException) { $msg = $($_.Exception.InnerException.Message) } else { $msg = $($_.Exception.Message) }  
        Write-EventLog $global:logName -Source $global:logSourceName -EventId 202 -Message "Failed executing SQL-Stmt $($sqlQuery): $msg " -EntryType Error                          	
    }
    
    $sqlQuery = "WITH CTE AS (
                      SELECT rn = ROW_NUMBER() OVER (PARTITION BY U1.Vorname, U1. Nachname ORDER BY U1.Nachname ASC)
		                    ,U1.Personalnummer
		                    ,U2.Personalnummer Personalnummer_M2
		                    ,U1.WindowsLogin AD_Benutzer
		                    ,U2.WindowsLogin AD_Benutzer_M2
		                    ,U1.WindowsAccountStateTranslated Benutzer_Status
		                    ,U2.WindowsAccountStateTranslated Benutzer_Status_M2
		                    ,[KSBL_Hospis_Staging].dbo.ReplaceIllegalChars(U1.[Nachname]) + ' ' + [KSBL_Hospis_Staging].dbo.ReplaceIllegalChars(U1.Vorname) Ganzer_Name
		                    ,[KSBL_Hospis_Staging].dbo.ReplaceIllegalChars(U2.[Nachname]) + ' ' + [KSBL_Hospis_Staging].dbo.ReplaceIllegalChars(U2.Vorname) Ganzer_Name_M2
		                    ,U1.Geburtsdatum
		                    ,U2.Geburtsdatum Geburtsdatum_M2
		                    ,U1.Organisationseinheit
		                    ,U2.Organisationseinheit Organisationseinheit_M2
		                    ,U1.[Eintrittsdatum]
		                    ,U2.Eintrittsdatum Eintrittsdatum_M2
		                    ,U1.[Austrittsdatum]
		                    ,U2.Austrittsdatum Austrittsdatum_M2
  	                    FROM [KSBL_IAM].[dbo].[Persons] U1 INNER JOIN [KSBL_IAM].[dbo].[Persons] U2 
		                    ON [KSBL_Hospis_Staging].dbo.TruncateString([KSBL_Hospis_Staging].dbo.ReplaceIllegalChars(U1.Vorname)) 
			                    LIKE [KSBL_Hospis_Staging].dbo.TruncateString([KSBL_Hospis_Staging].dbo.ReplaceIllegalChars(U2.Vorname)) 
		                    AND [KSBL_Hospis_Staging].dbo.TruncateString([KSBL_Hospis_Staging].dbo.ReplaceIllegalChars(U1.Nachname)) 
			                    LIKE [KSBL_Hospis_Staging].dbo.TruncateString([KSBL_Hospis_Staging].dbo.ReplaceIllegalChars(U2.Nachname)) 
		                    AND U2.Geburtsdatum = U1.Geburtsdatum
                      WHERE U1.WindowsEmployeeType not in ('G','GU','HNP','A')
                      AND U2.WindowsEmployeeType not in ('G','GU','HNP','A')
                      AND U1.WindowsLogin != U2.WindowsLogin
                    )
                    INSERT INTO [KSBL_IAM].[dbo].[PersonsDuplicates]
                            ([Personalnummer]
                            ,[Personalnummer_M2]
                            ,[AD_Benutzer]
                            ,[AD_Benutzer_M2]
                            ,[Benutzer_Status]
                            ,[Benutzer_Status_M2]
                            ,[Ganzer_Name]
                            ,[Ganzer_Name_M2]
                            ,[Geburtsdatum]
                            ,[Geburtsdatum_M2]
                            ,[Organisationseinheit]
                            ,[Organisationseinheit_M2]
                            ,[Eintrittsdatum]
                            ,[Eintrittsdatum_M2]
                            ,[Austrittsdatum]
                            ,[Austrittsdatum_M2])
                    SELECT Personalnummer
		                    ,Personalnummer_M2
		                    ,AD_Benutzer
		                    ,AD_Benutzer_M2
		                    ,Benutzer_Status
		                    ,Benutzer_Status_M2
		                    ,Ganzer_Name
		                    ,Ganzer_Name_M2
		                    ,Geburtsdatum
		                    ,Geburtsdatum_M2
		                    ,Organisationseinheit
		                    ,Organisationseinheit_M2
		                    ,Eintrittsdatum
		                    ,Eintrittsdatum_M2
		                    ,Austrittsdatum
		                    ,Austrittsdatum_M2
                    FROM CTE WHERE rn = 1
                    ORDER BY Ganzer_Name ASC"

    <#
    $sqlQuery = "INSERT INTO [KSBL_IAM].[dbo].[PersonsDuplicates]
                           ([Personalnummer]
                           ,[Personalnummer_M2]
                           ,[AD_Benutzer]
                           ,[AD_Benutzer_M2]
                           ,[Benutzer_Status]
                           ,[Benutzer_Status_M2]
                           ,[Ganzer_Name]
                           ,[Ganzer_Name_M2]
                           ,[Geburtsdatum]
                           ,[Geburtsdatum_M2]
                           ,[Organisationseinheit]
                           ,[Organisationseinheit_M2]
                           ,[Eintrittsdatum]
                           ,[Eintrittsdatum_M2]
                           ,[Austrittsdatum]
                           ,[Austrittsdatum_M2])
	                SELECT M1.[Personalnummer]
		                  ,M2.Personalnummer Personalnummer_M2
		                  ,U1.SAMAccountName AD_Benutzer
		                  ,U2.SAMAccountName AD_Benutzer_M2
		                  ,CASE WHEN U1.UserAccountControl LIKE '%ACCOUNTDISABLE%' THEN 'Disabled' ELSE null END Benutzer_Status
		                  ,CASE WHEN U2.UserAccountControl LIKE '%ACCOUNTDISABLE%' THEN 'Disabled' ELSE null END Benutzer_Status_M2
		                  ,[KSBL_Hospis_Staging].dbo.ReplaceIllegalChars(M1.[Name]) + ' ' + [KSBL_Hospis_Staging].dbo.ReplaceIllegalChars(M1.Vorname) Ganzer_Name
		                  ,[KSBL_Hospis_Staging].dbo.ReplaceIllegalChars(M2.[Name]) + ' ' + [KSBL_Hospis_Staging].dbo.ReplaceIllegalChars(M2.Vorname) Ganzer_Name_M2
		                  ,M1.Geburtsdatum
		                  ,M2.Geburtsdatum Geburtsdatum_M2
		                  ,M1.Organisationseinheit
		                  ,M2.Organisationseinheit Organisationseinheit_M2
		                  ,M1.[Eintrittsdatum]
		                  ,M2.Eintrittsdatum Eintrittsdatum_M2
		                  ,M1.[Austrittsdatum]
		                  ,M2.Austrittsdatum Austrittsdatum_M2
	                FROM [KSBL_Hospis_Staging].[dbo].[vwViewHospis2AdImportTodaysEmployeeListM2] M2
	                INNER JOIN [KSBL_Hospis_Staging].[dbo].[vwViewHospis2AdImportTodaysEmployeeList] M1 
	                ON [KSBL_Hospis_Staging].dbo.TruncateString([KSBL_Hospis_Staging].dbo.ReplaceIllegalChars(M2.Vorname)) LIKE [KSBL_Hospis_Staging].dbo.TruncateString([KSBL_Hospis_Staging].dbo.ReplaceIllegalChars(M1.Vorname)) 
		                AND [KSBL_Hospis_Staging].dbo.TruncateString([KSBL_Hospis_Staging].dbo.ReplaceIllegalChars(M2.Name)) LIKE [KSBL_Hospis_Staging].dbo.TruncateString([KSBL_Hospis_Staging].dbo.ReplaceIllegalChars(M1.Name)) 
			                AND M2.Geburtsdatum = M1.Geburtsdatum
	                LEFT OUTER JOIN [KSBL_Hospis_Staging].[dbo].ImportADUsers U1 ON M1.Personalnummer = U1.EmployeeId 
	                LEFT OUTER JOIN [KSBL_Hospis_Staging].[dbo].ImportADUsers U2 ON M2.Personalnummer = U2.EmployeeId 	
	                WHERE M1.Eintrittsdatum  <= GETDATE()"
    #>
    try {
        Invoke-Sqlcmd -Query $sqlQuery -ServerInstance $iamServer -QueryTimeout 300
    } catch { ([System.Exception])
	    if ($_.Exception.InnerException) { $msg = $($_.Exception.InnerException.Message) } else { $msg = $($_.Exception.Message) }  
        Write-EventLog $global:logName -Source $global:logSourceName -EventId 203 -Message "Failed executing SQL-Stmt $($sqlQuery): $msg " -EntryType Error                          	
    }

}


function UpdateHospisPersonsIntoModel {
      
    try {
        $sqlQuery = "TRUNCATE TABLE [KSBL_IAM].[dbo].[stg_Persons]"
        Invoke-Sqlcmd -Query $sqlQuery -ServerInstance $iamServer
    } catch { ([System.Exception])
	    if ($_.Exception.InnerException) { $msg = $($_.Exception.InnerException.Message) } else { $msg = $($_.Exception.Message) }  
        Write-EventLog $global:logName -Source $global:logSourceName -EventId 204 -Message "Failed executing SQL-Stmt $($sqlQuery): $msg " -EntryType Error                          	
    }

    $sqlQuery = "INSERT INTO [KSBL_IAM].[dbo].[stg_Persons]
                                ([Personalnummer]
                                ,[WindowsLogin]
                                ,WindowsAccountState
							    ,WindowsLastLogin
							    ,WindowsPwdLastChanged
							    ,WindowsAccountExpires
                                ,WindowsExtAttrib11
                                ,WindowsEmployeeType
							    ,[Status]
                                ,[Vorname]
                                ,[Nachname]
                                ,[Vor/Nachname]
                                ,[Standort]
                                ,[Kostenstelle]
                                ,[Organisationseinheit]
                                ,[Tätigkeit]
                                ,[Eintrittsdatum]
                                ,[Austrittsdatum]
                                ,[Geburtsdatum]
                                ,[MitarbeiterTyp])
                SELECT [HOSPIS].[Personalnummer]
                                , [AD].[SamAccountName]
                                , [AD].[UserAccountControl]
                                , [AD].[LastLogonTimestamp]
                                , [AD].[PwdLastSet]
                                , [AD].[AccountExpires]
                                , [AD].[ExtensionAttribute11]
                                , [AD].[EmployeeType]
                                , [HOSPIS].[Status]
                                , [HOSPIS].[Vorname]
                                , [HOSPIS].[Name]
                                , [HOSPIS].[Ganzer_Name]
                                , [HOSPIS].[Standort]
                                , [HOSPIS].[Kostenstelle]
                                , [HOSPIS].[Organisationseinheit]
                                , [HOSPIS].[Tätigkeit]
                                , [HOSPIS].[Eintrittsdatum]
                                , [HOSPIS].[Austrittsdatum]
                                , [HOSPIS].[Geburtsdatum]
                                , [HOSPIS].[MitarbeiterTyp]
                        FROM [KSBL_Hospis_Staging].[dbo].[vwViewHospis2AdImportEmployeeListByLatestPersonRecord] HOSPIS
                        LEFT OUTER JOIN [KSBL_IAM].[dbo].[Accounts] AD ON [HOSPIS].[Personalnummer] = [AD].[EmployeeId] AND [AD].[LegacySourceDomain] = 'KSBL.LOCAL' AND AD.EmployeeId != ''"

                
    try {
        Invoke-Sqlcmd -Query $sqlQuery -ServerInstance $iamServer -QueryTimeout 300
    } catch { ([System.Exception])
	    if ($_.Exception.InnerException) { $msg = $($_.Exception.InnerException.Message) } else { $msg = $($_.Exception.Message) }  
        Write-EventLog $global:logName -Source $global:logSourceName -EventId 205 -Message "Failed executing SQL-Stmt $($sqlQuery): $msg " -EntryType Error                          	
    }

    $sqlQuery = "SELECT [HOSPIS].[Personalnummer], COUNT([HOSPIS].[Personalnummer]) AmountOf
                    FROM [KSBL_Hospis_Staging].[dbo].[vwViewHospis2AdImportEmployeeListByLatestPersonRecord] HOSPIS
                    LEFT OUTER JOIN [KSBL_IAM].[dbo].[Accounts] AD ON [HOSPIS].[Personalnummer] = [AD].[EmployeeId] AND AD.EmployeeId != ''
                    GROUP BY [HOSPIS].[Personalnummer]
                    HAVING COUNT([HOSPIS].[Personalnummer]) > 1"

    try {
        $queryResult = $null
        $queryResult = Invoke-Sqlcmd -Query $sqlQuery -ServerInstance $iamServer
    } catch { ([System.Exception])
	    if ($_.Exception.InnerException) { $msg = $($_.Exception.InnerException.Message) } else { $msg = $($_.Exception.Message) }  
        Write-EventLog $global:logName -Source $global:logSourceName -EventId 206 -Message "Failed executing SQL-Stmt $($sqlQuery): $msg " -EntryType Error                          	
    }

    if (-not [string]::IsNullOrEmpty($queryResult)) {

        try {
            $ds = New-Object System.DirectoryServices.DirectorySearcher([ADSI]"LDAP://$([System.DirectoryServices.ActiveDirectory.Domain]::GetCurrentDomain().Name)", "(employeeId=$($queryResult.Personalnummer))", @('sAMAccountName'))
            $searchResult = $ds.FindAll()
        } catch {([Exception])
	        if ($_.Exception.InnerException) { $msg = $($_.Exception.InnerException.Message) } else { $msg = $($_.Exception.Message) }  	
	        Write-EventLog $global:logName -Source $global:logSourceName -EventId 201 -Message "Error retrieving Active-Directory Users using LDAP-Filter (employeeId=$($queryResult.Personalnummer)): $msg " -EntryType Error                  
        }                

        if (-not [string]::IsNullOrEmpty($searchResult)) {

            $samAccountNames = $null
            $samAccountNames = "("
            foreach ($user in $searchResult) {
                $samAccountNames += "$($user.Properties["samaccountname"]),"
            }
            $samAccountNames = $samAccountNames.Substring(0,$samAccountNames.Length-1)
            $samAccountNames += ")"

            $htmlBody = $null
            $htmlBody = "Hospis employee Id $($queryResult.Personalnummer) appears on multiple accounts in Active Directory $samAccountNames. <br/><br/>Please take the following actions: <br/><br/> - Check which account has been last used by the end user <br/> - Disable the account which hasn't been or isn't used <br/> - Remove the Mailbox from the obsolete account <br/><br/> Krgds <br/> RoboInfra"   
        
            Send-EMail -smtpHost $smtpHost -mailFrom $mailFrom -mailTo "ksbl.servicedesk@ksbl.ch" -mailCc "ksbl.it-infrastruktur@ksbl.ch" `
                        -mailSubject "*** GUI Tool Active-Directory Data Backfeed - A duplicate EmployeeId ($($queryResult.Personalnummer)) exists in Active Directory ***" `
                        -mailBody $htmlBody `
                        -attachment $null `
        }
    
    } 

    $sqlQuery = "MERGE [KSBL_IAM].[dbo].[Persons] AS TARGET USING [KSBL_IAM].[dbo].[stg_Persons] AS SOURCE 
						ON (TARGET.[Personalnummer] = SOURCE.[Personalnummer] AND TARGET.[WindowsLogin] = SOURCE.[WindowsLogin]) 
                    WHEN MATCHED 	                    
	                    AND (TARGET.[WindowsAccountState] <> SOURCE.[WindowsAccountState] OR TARGET.[WindowsAccountState] IS NULL)
	                    OR (TARGET.[WindowsAccountState] <> SOURCE.[WindowsAccountState] OR TARGET.[WindowsAccountState] IS NULL)
	                    OR (TARGET.[WindowsLastLogin] <> SOURCE.[WindowsLastLogin] OR TARGET.[WindowsLastLogin] IS NULL)
	                    OR (TARGET.[WindowsPwdLastChanged] <> SOURCE.[WindowsPwdLastChanged] OR TARGET.[WindowsPwdLastChanged] IS NULL)
	                    OR (TARGET.[WindowsAccountExpires] <> SOURCE.[WindowsAccountExpires] OR TARGET.[WindowsAccountExpires] IS NULL)
	                    OR (TARGET.[WindowsExtAttrib11] <> SOURCE.[WindowsExtAttrib11] OR TARGET.[WindowsExtAttrib11] IS NULL)
                        OR (TARGET.[WindowsEmployeeType] <> SOURCE.[WindowsEmployeeType] OR TARGET.[WindowsEmployeeType] IS NULL)
	                    OR (TARGET.[Vorname] <> SOURCE.[Vorname] OR TARGET.[Vorname] IS NULL)
	                    OR (TARGET.[Nachname] <> SOURCE.[Nachname] OR TARGET.[Nachname] IS NULL)
	                    OR (TARGET.[Vor/Nachname] <> SOURCE.[Vor/Nachname] OR TARGET.[Vor/Nachname] IS NULL)
	                    OR (TARGET.[Standort] <> SOURCE.[Standort] OR TARGET.[Standort] IS NULL)
	                    OR (TARGET.[Kst Standort] <> SOURCE.[Kst Standort] OR TARGET.[Kst Standort] IS NULL)
	                    OR (TARGET.[Kostenstelle] <> SOURCE.[Kostenstelle] OR TARGET.[Kostenstelle] IS NULL)
	                    OR (TARGET.[Organisationseinheit] <> SOURCE.[Organisationseinheit] OR TARGET.[Organisationseinheit] IS NULL)
	                    OR (TARGET.[Tätigkeit] <> SOURCE.[Tätigkeit] OR TARGET.[Tätigkeit] IS NULL)
	                    OR (TARGET.[Eintrittsdatum] <> SOURCE.[Eintrittsdatum] OR TARGET.[Eintrittsdatum] IS NULL)
	                    OR (TARGET.[Austrittsdatum] <> SOURCE.[Austrittsdatum] OR TARGET.[Austrittsdatum] IS NULL)
	                    OR (TARGET.[Geburtsdatum] <> SOURCE.[Geburtsdatum] OR TARGET.[Geburtsdatum] IS NULL)
                        OR (TARGET.[MitarbeiterTyp] <> SOURCE.[MitarbeiterTyp] OR TARGET.[MitarbeiterTyp] IS NULL)
                    THEN 
	                    UPDATE SET TARGET.[WindowsLogin] = SOURCE.[WindowsLogin]
							,TARGET.[WindowsAccountState] = SOURCE.[WindowsAccountState]
							,TARGET.[WindowsLastLogin] = SOURCE.[WindowsLastLogin]
							,TARGET.[WindowsPwdLastChanged] = SOURCE.[WindowsPwdLastChanged]
							,TARGET.[WindowsAccountExpires] = SOURCE.[WindowsAccountExpires]
							,TARGET.[WindowsExtAttrib11] = SOURCE.[WindowsExtAttrib11] 
							,TARGET.[WindowsEmployeeType] = SOURCE.[WindowsEmployeeType] 
							,TARGET.[Vorname] = SOURCE.[Vorname]
							,TARGET.[Nachname] = SOURCE.[Nachname]
							,TARGET.[Vor/Nachname] = SOURCE.[Vor/Nachname]
							,TARGET.[Standort] = SOURCE.[Standort]
							,TARGET.[Kst Standort] = SOURCE.[Kst Standort]
							,TARGET.[Kostenstelle] = SOURCE.[Kostenstelle]
							,TARGET.[Organisationseinheit] = SOURCE.[Organisationseinheit]
							,TARGET.[Tätigkeit] = SOURCE.[Tätigkeit]
							,TARGET.[Eintrittsdatum] = SOURCE.[Eintrittsdatum]
							,TARGET.[Austrittsdatum] = SOURCE.[Austrittsdatum]
							,TARGET.[Geburtsdatum] = SOURCE.[Geburtsdatum]
							,TARGET.[MitarbeiterTyp] = SOURCE.[MitarbeiterTyp]
                    WHEN NOT MATCHED BY TARGET THEN 
	                    INSERT ([Personalnummer]
							    ,[WindowsLogin]
							    ,[WindowsAccountState]
							    ,[WindowsLastLogin]
							    ,[WindowsPwdLastChanged]
							    ,[WindowsAccountExpires]
							    ,WindowsExtAttrib11
                                ,WindowsEmployeeType
                                ,[Status]
                                ,[Vorname]
                                ,[Nachname]
							    ,[Vor/Nachname]
							    ,[Kst Standort]
							    ,[Standort]
							    ,[Kostenstelle]
							    ,[Organisationseinheit]
							    ,[Tätigkeit]
							    ,[Eintrittsdatum]
							    ,[Austrittsdatum]
                                ,[Geburtsdatum]
                                ,[MitarbeiterTyp]) 
	                    VALUES (
							    SOURCE.[Personalnummer]
							    ,SOURCE.[WindowsLogin]
							    ,SOURCE.[WindowsAccountState]
							    ,SOURCE.[WindowsLastLogin]
							    ,SOURCE.[WindowsPwdLastChanged]
							    ,SOURCE.[WindowsAccountExpires]
                                ,SOURCE.WindowsExtAttrib11
                                ,SOURCE.WindowsEmployeeType
							    ,SOURCE.[Status]
							    ,SOURCE.[Vorname]
							    ,SOURCE.[Nachname]
							    ,SOURCE.[Vor/Nachname]
							    ,SOURCE.[Kst Standort]
							    ,SOURCE.[Standort]
							    ,SOURCE.[Kostenstelle]
							    ,SOURCE.[Organisationseinheit]
							    ,SOURCE.[Tätigkeit]
							    ,SOURCE.[Eintrittsdatum]
							    ,SOURCE.[Austrittsdatum]
                                ,SOURCE.[Geburtsdatum]
                                ,SOURCE.[MitarbeiterTyp])
                    WHEN NOT MATCHED BY SOURCE THEN 
	                    DELETE;
                    SELECT @@ROWCOUNT;"

    try {
        Invoke-Sqlcmd -Query $sqlQuery -ServerInstance $iamServer
    } catch { ([System.Exception])
	    if ($_.Exception.InnerException) { $msg = $($_.Exception.InnerException.Message) } else { $msg = $($_.Exception.Message) }  
        Write-EventLog $global:logName -Source $global:logSourceName -EventId 207 -Message "Failed executing SQL-Stmt $($sqlQuery): $msg " -EntryType Error                          	
    }
}

function DisableAccountsExceededGracePeriod {

    $sqlQuery = "SELECT [Id]
                      ,[SamAccountName]
                      ,[AccountState]
                      ,[EnabledUntil]
                      ,[IgnoreEnabledUntil]
                      ,[ModifiedBy]
                      ,[ModifiedOn]
	                  ,CompletedOn
                  FROM [KSBL_IAM].[dbo].[AccountControlState]
                  WHERE [EnabledUntil] < GETDATE() 
                  AND IgnoreEnabledUntil IS NULL
                  AND CompletedOn IS NULL"

    try {
        $accounts = Invoke-Sqlcmd -Query $sqlquery -ServerInstance $iamServer
    } catch { ([System.Exception])
	    if ($_.Exception.InnerException) { $msg = $($_.Exception.InnerException.Message) } else { $msg = $($_.Exception.Message) }  
        Write-EventLog $global:logName -Source $global:logSourceName -EventId 208 -Message "Failed executing SQL-Stmt $($sqlQuery): $msg " -EntryType Error                          	
    }
    
    foreach ($account in $accounts) {
        
        try {
            $resourceForestUserObject = $null
            $resourceForestUserObject = Get-ADUser -LDAPFilter "(samaccountname=$($account.SamAccountName))" -Properties mail,SamAccountName,extensionattribute8,AccountExpirationDate,mailNickname
        } catch {([Exception])
	        if ($_.Exception.InnerException) { $msg = $($_.Exception.InnerException.Message) } else { $msg = $($_.Exception.Message) }  	
	        Write-EventLog $global:logName -Source $global:logSourceName -EventId 213 -Message "Error getting User $($account.SamAccountName) from Active-Directory : $msg " -EntryType Error                  
        }

        if ($resourceForestUserObject -ne $null) {

            $sql = $null
            $sql = "SELECT Personalnummer,Eintrittsdatum,Austrittsdatum,WindowsLogin 
                    FROM [KSBL_Hospis_Staging].[dbo].[vwViewHospis2AdImportPersonsJoinedAdAccounts]
                    WHERE WindowsLogin = '$($account.SamAccountName)'"
    
            try {
                $res = $null
                $res = Invoke-Sqlcmd -Query $sql -ServerInstance $iamServer
            } catch { ([System.Exception])
	            if ($_.Exception.InnerException) { $msg = $($_.Exception.InnerException.Message) } else { $msg = $($_.Exception.Message) }  
                Write-EventLog $global:logName -Source $global:logSourceName -EventId 209 -Message "Failed executing SQL-Stmt $($sql): $msg " -EntryType Error                          	
            }
                
            $disableAccount = $true

            if ($res -ne $null) {
                if ($res.Austrittsdatum -gt $(Get-Date)) {
                    $disableAccount = $false
                } else {
                    $disableAccount = $true
                }
            } else {
                $disableAccount = $true                
            }

            if ($disableAccount -eq $true) {

                try {
                    if ((Get-PSSession | ? {$_.State -like "Opened" -and $_.Availability -like "Available"}) -eq $null) {
                        Get-PSSession | Remove-PSSession
					    $cred = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList "ksbl\serviceiamjobs10" , (Get-Content "D:\iam\Secrets\serviceiamjobs10.sec" | ConvertTo-SecureString) 
					    $PSSession = new-pssession –configurationname Microsoft.Exchange –connectionuri http://sv01250.ksbl.local/PowerShell –credential $cred -Authentication Kerberos 
					    Import-PSSession $PSSession -AllowClobber
                    }
                } catch {([Management.Automation.Remoting.PSRemotingTransportException],[Exception])
	                if ($_.Exception.InnerException) { $msg = $($_.Exception.InnerException.Message) } else { $msg = $($_.Exception.Message) }  	
	                Write-EventLog $global:logName -Source $global:logSourceName -EventId 500 -Message "Error creating a new Remote Exchange Powershell Connection: $msg " -EntryType Error                  
                }

                if ($resourceForestUserObject.Enabled -eq $true) {

                    try {
                        Set-ADUser $resourceForestUserObject.SamAccountName -Enabled $false -Server $ldapServer
                    } catch {([Exception])
	                    if ($_.Exception.InnerException) { $msg = $($_.Exception.InnerException.Message) } else { $msg = $($_.Exception.Message) }  	
	                    Write-EventLog $global:logName -Source $global:logSourceName -EventId 220 -Message "Error enabling User $($resourceForestUserObject.SamAccountName): $msg " -EntryType Error                  
                    }

                    Change-MailboxFeaturesAndState -mailboxName $resourceForestUserObject.mailNickname -objectState ([ObjectState]::HIDE)

                    try {
                        $sql = "UPDATE [KSBL_IAM].[dbo].[AccountControlState] SET CompletedOn = GETDATE() WHERE Id = $($account.Id)"
                        Invoke-Sqlcmd -Query $sql -ServerInstance $iamServer
                    } catch { ([System.Exception])
	                    if ($_.Exception.InnerException) { $msg = $($_.Exception.InnerException.Message) } else { $msg = $($_.Exception.Message) }  
                        Write-EventLog $global:logName -Source $global:logSourceName -EventId 210 -Message "Failed executing SQL-Stmt $($sql): $msg " -EntryType Error                          	
                    }
                }
                Get-PSSession | Remove-PSSession                
            }               
        }            
    }
}

Clear-Host

$global:logname = "KSBL IAM"
$global:logSourceName = "Import-Users-Into-Staging-Update-Model"
#[System.Diagnostics.EventLog]::CreateEventSource($global:logSourceName, $global:logname)
#Write-EventLog $global:logName -Source $global:logSourceName -EventId 1 -Message "EventSource created." -EntryType Information

try {
    if ((Get-Module | ? {$_.Name -eq "SqlServer"}) -eq $null) {
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

#DisableAccountsExceededGracePeriod

Write-EventLog $global:logName -Source $global:logSourceName -EventId 1 -Message "IAM user staging job started at $(Get-Date)" -EntryType Information

Write-Host "Starting Job at $(get-date)" -ForegroundColor Green
[System.Diagnostics.Stopwatch] $global:stopWatch; $global:stopWatch = New-Object System.Diagnostics.StopWatch 
$global:iamServer = "SV02037.ksbl.local"
$global:smtpHost = "sv00516.ksbl.local"
$global:mailFrom = "informatik@ksbl.ch"

try {
    $sqlQuery = "TRUNCATE TABLE [KSBL_IAM].[dbo].[stg_Accounts]"			
    Invoke-Sqlcmd -Query $sqlquery -ServerInstance $iamServer
} catch { ([System.Exception])
	if ($_.Exception.InnerException) { $msg = $($_.Exception.InnerException.Message) } else { $msg = $($_.Exception.Message) }  
    Write-EventLog $global:logName -Source $global:logSourceName -EventId 211 -Message "Failed executing SQL-Stmt $($sqlQuery): $msg " -EntryType Error                          	
}

InsertUsersIntoStaging

$global:stopWatch.Stop()$timeSpan = $global:stopWatch.Elapsed.ToString()Write-EventLog $global:logName -Source $global:logSourceName -EventId 88 -Message "Time elapsed to gather all users from domain $($DomainName): $timeSpan" -EntryType Information
Write-Host "Time elapsed to gather all users: $timeSpan" -ForegroundColor Cyan

Write-Host "Finished Job at $(get-date)" -ForegroundColor Green

MergeUsersIntoModel

UpdateHospisPersonsIntoModel

UpdateHospisPersonsHistory

UpdateHospisPersonsDuplicates

Write-EventLog $global:logName -Source $global:logSourceName -EventId 1 -Message "IAM user staging job finished at $(Get-Date)" -EntryType Information
