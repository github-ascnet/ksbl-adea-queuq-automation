function BulkInsertFile ($sqlserver, $database, $table, $fileName, $group) {

    #$sqlserver = "SV02037.ksbl.local"
    #$database = "KSBL_IAM"
    #$table = "stg_GroupMembers"

    # CSV variables; 
    $csvfile = $fileName
    $csvdelimiter = "`;"
    $firstrowcolumnnames = $true

    # 100k worked fastest and kept memory usage to a minimum
    $batchsize = 100000

    # Build the sqlbulkcopy connection, and set the timeout to infinite
    $connectionstring = "Data Source=$sqlserver;Integrated Security=true;Initial Catalog=$database;"
    $bulkcopy = new-object ("Data.SqlClient.Sqlbulkcopy") $connectionstring
    $bulkcopy.DestinationTableName = $table
    $bulkcopy.bulkcopyTimeout = 0
    $bulkcopy.batchsize = $batchsize
    $bulkcopy.EnableStreaming = 1
 
    # Create the datatable, and autogenerate the columns.
    $datatable = New-Object "System.Data.DataTable"

    # Open the text file from disk
    $reader = new-object System.IO.StreamReader($csvfile)
    $line = $reader.ReadLine()
    $columns =  $line.Split($csvdelimiter)

	if ($firstrowcolumnnames -eq $false) {
		foreach ($column in $columns) {
			$null = $datatable.Columns.Add()
        }
		# start reader over
		$reader.DiscardBufferedData(); 
		$reader.BaseStream.Position = 0;
    } else {
		foreach ($column in $columns) {
			$null = $datatable.Columns.Add($column)
		}
	}
    $i = 0
    # Read in the data, line by line
	while (($line = $reader.ReadLine()) -ne $null)  {
		$row = $datatable.NewRow()
		$row.itemarray = $line.Split($csvdelimiter)
		$datatable.Rows.Add($row)  

		# Once you reach your batch size, write to the db, 
		# then clear the datatable from memory
		$i++ 
        if (($i % $batchsize) -eq 0) {
		    $bulkcopy.WriteToServer($datatable)
		    $datatable.Clear()
		}
	} 

    # Close the CSV file
    $reader.Close()

	# Add in all the remaining rows since the last clear
	if($datatable.Rows.Count -gt 0) {

        try {            
		    $bulkcopy.WriteToServer($datatable)
	    } catch [System.Exception] {
            if ($_.Exception.InnerException) { $msg = $($_.Exception.InnerException.Message) } else { $msg = $($_.Exception.Message) }
            Write-EventLog $EventlogName -Source $EventlogSource -EventId 88 -Message "Failed bulk inserting members for group $($group.Properties["distinguishedname"]). Error: $msg" -EntryType Error
            Write-Host "Failed bulk inserting members for group $($group.Properties["distinguishedname"]). Error: $msg" -ForegroundColor red
	    }
		$datatable.Clear()
	}

    #Write-Output "`n"
    Write-Output "$i members have been inserted into the database for group $($group.Properties["distinguishedname"])."
    
}


function Test-EventLog([String]$EventlogName,[String]$EventlogSource) 
{
    if (![System.Diagnostics.Eventlog]::SourceExists($EventlogName))  { 

		New-EventLog $EventlogName -Source $EventlogSource
		Write-EventLog $EventlogName -Source $EventlogSource -EventId 1 -Message "Event log $global:logName created on local machine." -EntryType Information
    } 
}

function Transform-MultivalueArrayList([Array]$multivalueArrayList)
{ 
    [String]$itemList = $null
    ForEach($item In $multivalueArrayList) {            
        $itemList = $itemList + $item + "|"        
    }
    #remove the last character
    $itemList = $itemList.Substring(0, $itemList.Length - 1)
    return $itemList
}

function Transpose-GUID([Object]$dsObject)
{ 
   [String]$tranposedGUId = $null
   $_nativGUID = $dsObject.psbase.nativeGUID
	   
   $tranposedGUId = "{" + $_nativGUID.SubString(6,2) + $_nativGUID.SubString(4,2) + $_nativGUID.SubString(2,2) `
	            + $_nativGUID.SubString(0,2) + "-" + $_nativGUID.SubString(10,2) + $_nativGUID.SubString(8,2) + "-" `
	            + $_nativGUID.SubString(14,2) + $_nativGUID.SubString(12,2) + "-" + $_nativGUID.SubString(16,2) `
	            + $_nativGUID.SubString(18,2) + "-" + $_nativGUID.SubString(20,12) + "}"
    return $tranposedGUId
}

function InsertGroupsAndMembersIntoStaging
{
    [System.Diagnostics.Stopwatch] $global:stopWatch;     $global:stopWatch = New-Object System.Diagnostics.StopWatch 
    #$ldapFilter = "(&(objectClass=group) (| (&(samaccounttype=536870912)(member=*)) (&(grouptype:1.2.840.113556.1.4.803:=-2147483646)(member=*)) (&(grouptype:1.2.840.113556.1.4.803:=-2147483640)(mail=*)) ) )"
    $ldapFilter = "(&(objectClass=group) (| (&(grouptype:1.2.840.113556.1.4.803:=-2147483646)(member=*)) (&(grouptype:1.2.840.113556.1.4.803:=-2147483640)(mail=*)) ) )"
    #$ldapFilter = "(&(objectClass=group)(mail=ksbl.vl.ssp-vertilerliste-oq*))"

    try {
        $DomainName = [System.DirectoryServices.ActiveDirectory.Domain]::GetCurrentDomain().Name
    } catch {([Exception])
	    if ($_.Exception.InnerException) { $msg = $($_.Exception.InnerException.Message) } else { $msg = $($_.Exception.Message) }  	
	    Write-EventLog $global:logName -Source $global:logSourceName -EventId 400 -Message "Error retrieving primary User Domain from Active-Directory: $msg " -EntryType Error                  
        Exit
    }

    try {
        if ((Get-PSSession | ? {$_.State -like "Opened" -and $_.Availability -like "Available"}) -eq $null) {
            Get-PSSession | Remove-PSSession
			$cred = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList "ksbl\serviceiamjobs10" , (Get-Content "D:\iam\Secrets\serviceiamjobs10.sec" | ConvertTo-SecureString) 
			$PSSession = new-pssession –configurationname Microsoft.Exchange –connectionuri http://sv01250.ksbl.local/PowerShell –credential $cred -Authentication Kerberos 
			Import-PSSession $PSSession -AllowClobber
        }
    } catch {([Management.Automation.Remoting.PSRemotingTransportException],[Exception])
	    if ($_.Exception.InnerException) { $msg = $_.Exception.InnerException.Message } else { $msg = $_.Exception.Message }
        Write-EventLog $global:logName -Source $global:logSourceName -EventId 1000 -Message "Failed establishing a remote Powershell session to Exchange.\r\n\r\nError: $msg" -EntryType Error
        Exit
    }

    try {

        $distributionGroups = Get-DistributionGroup -ResultSize unlimited 
        $distributionGroupReport = [System.Collections.Generic.List[Object]]::new()

        foreach ($distributionGroup in $distributionGroups) {

            $managerList = [System.Collections.Generic.List[Object]]::new()
            ForEach ($manager in $distributionGroup.ManagedBy) {
                $recipient = Get-User $manager | Select-Object DistinguishedName,SamAccountName
                $managerLine = [PSCustomObject][Ordered] @{  
                     DistinguishedName = $recipient.DistinguishedName
                     SamAccountName = $recipient.SamAccountName}
                $managerList.Add($managerLine) 
            }

            for ($i = 0; $i -lt $managerList.Count; $i++) { 
                $distributionGroupLine = [PSCustomObject][Ordered] @{    
                     DistinguishedName = $distributionGroup.DistinguishedName     
                     ManagersDn = $managerList[$i].DistinguishedName
                     ManagersUser = $managerList[$i].SamAccountName}
                $distributionGroupReport.Add($distributionGroupLine)    
            }
        }

    } catch {([Management.Automation.Remoting.PSRemotingTransportException],[Exception])
	    if ($_.Exception.InnerException) { $msg = $_.Exception.InnerException.Message } else { $msg = $_.Exception.Message }
        Write-EventLog $global:logName -Source $global:logSourceName -EventId 1000 -Message "Failed getting Distribution Groups from Exchange.\r\n\r\nError: $msg" -EntryType Error
        Exit
    }   

    $PrincipalContext = New-Object System.DirectoryServices.AccountManagement.PrincipalContext([System.DirectoryServices.AccountManagement.ContextType]::Domain, $DomainName)
    $DomainContext = New-Object System.DirectoryServices.ActiveDirectory.DirectoryContext("Domain", $DomainName) #, "ksbl\administrator", "***********")
    $Domain = [System.DirectoryServices.ActiveDirectory.Domain]::GetDomain($DomainContext)
    $Root = $Domain.GetDirectoryEntry()
    $DomainContext = $Root.distinguishedName
    $domainContext = "LDAP://$Domain/$DomainContext"                
    $dn = New-Object System.DirectoryServices.DirectoryEntry($domainContext)
    $dsSearcher = new-object System.DirectoryServices.DirectorySearcher($dn)
    $dsSearcher.Filter = $ldapFilter; 
    $dsSearcher.SearchScope = "subtree"; 
    $dsSearcher.PageSize = 20000
    $dsSearcher.CacheResults = $false
    $dsSearcher.Asynchronous = $true
    $n = $dsSearcher.PropertiesToLoad.Add("cn"); 
    $n = $dsSearcher.PropertiesToLoad.Add("samaccountname");
    $n = $dsSearcher.PropertiesToLoad.Add("displayName");
    $n = $dsSearcher.PropertiesToLoad.Add("managedBy");
    $n = $dsSearcher.PropertiesToLoad.Add("msExchCoManagedByLink");        
    $n = $dsSearcher.PropertiesToLoad.Add("mailNickname");
    $n = $dsSearcher.PropertiesToLoad.Add("targetAddress");
    $n = $dsSearcher.PropertiesToLoad.Add("groupType");
    $n = $dsSearcher.PropertiesToLoad.Add("msExchHideFromAddressLists");
    $n = $dsSearcher.PropertiesToLoad.Add("mail");
    $n = $dsSearcher.PropertiesToLoad.Add("legacyExchangeDN");
    $n = $dsSearcher.PropertiesToLoad.Add("proxyAddresses");
    $n = $dsSearcher.PropertiesToLoad.Add("distinguishedName");
    $n = $dsSearcher.PropertiesToLoad.Add("objectGuid");
    $n = $dsSearcher.PropertiesToLoad.Add("adspath");
    $n = $dsSearcher.PropertiesToLoad.Add("extensionAttribute1");
    $n = $dsSearcher.PropertiesToLoad.Add("extensionAttribute2");
    $n = $dsSearcher.PropertiesToLoad.Add("extensionAttribute3");
    $n = $dsSearcher.PropertiesToLoad.Add("extensionAttribute4");
    $n = $dsSearcher.PropertiesToLoad.Add("extensionAttribute5");
    $n = $dsSearcher.PropertiesToLoad.Add("extensionAttribute6");
    $n = $dsSearcher.PropertiesToLoad.Add("extensionAttribute7");
    $n = $dsSearcher.PropertiesToLoad.Add("extensionAttribute8");
    $n = $dsSearcher.PropertiesToLoad.Add("extensionAttribute9");
    $n = $dsSearcher.PropertiesToLoad.Add("extensionAttribute10");
    $n = $dsSearcher.PropertiesToLoad.Add("extensionAttribute11");
    $n = $dsSearcher.PropertiesToLoad.Add("extensionAttribute12");
    $n = $dsSearcher.PropertiesToLoad.Add("extensionAttribute13");
    $n = $dsSearcher.PropertiesToLoad.Add("extensionAttribute14");
    $n = $dsSearcher.PropertiesToLoad.Add("extensionAttribute15");
    $n = $dsSearcher.PropertiesToLoad.Add("info");
    $n = $dsSearcher.PropertiesToLoad.Add("whenCreated");
    $n = $dsSearcher.PropertiesToLoad.Add("whenChanged");

    $global:stopWatch.Reset()    $global:stopWatch.Start()            

    $lstGroups = $dsSearcher.findall()
    $groupCount = $dsSearcher.findall().Count

    #Write-Host "For LDAP filter $($DomainName)/$($ldapFilter) we have $groupCount groups"

    $currentObject = 0    
                
    $forestDomainController = (($Domain.DomainControllers).Name | select -First 1)
    $forestDomainController = $Domain.InfrastructureRoleOwner.Name
                
    foreach ($group in $($dsSearcher.findall())) {

        if (-not $group.Path.Contains(",CN=Users,") -and -not $group.Path.Contains(",CN=Builtin,")) {

            #[Console]::Write(".")

            $currentObject = $currentObject + 1
            Write-Progress -Activity "Enumerating $groupCount objects according to the LDAP filter $($ldapFilter)" -status "Processing group $($currentObject) {$($group.Properties["cn"][0])} ..." -PercentComplete ($currentObject / $groupCount * 100)        

	        try {

                $dsObject = [ADSI]$($group.Properties["adspath"])

                #Get-MembersFromGroup $Domain $Protocol $($group.Properties["distinguishedname"]) 

                if (-not [System.String]::IsNullOrEmpty($($group.Properties["proxyaddresses"]))) {
                    [System.Array]$arrayProxyAddresses = $($group.Properties["proxyaddresses"])
                    $proxyAddresses = Transform-MultivalueArrayList $arrayProxyAddresses 
                } else {
                    $proxyAddresses = [System.DBNull]::Value
                }

                if (-not [System.String]::IsNullOrEmpty($dsObject.msExchHideFromAddressLists)) {
    		        if ($dsObject.msExchHideFromAddressLists -eq 'true') {
                        [bool]$ExchHideFromAddressLists = $true
                    } else {
                        [bool]$ExchHideFromAddressLists = $false
                    }
                } else {
    		        [bool]$ExchHideFromAddressLists = $false
    	        }	

                if ($($group.Properties["objectguid"]) -ne $null) {
        	        $tranposedGUId = Transpose-GUID $dsObject
                } else {
        	        $tranposedGUId = [System.DBNull]::Value
                }

                if ($($group.Properties["displayname"]) -ne $null) {
        	        [string]$displayName = $group.Properties["displayname"]               
                } else {
        	        [string]$displayName = [System.DBNull]::Value
                }

                if ($($group.Properties["mailnickname"]) -ne $null) {
        	        [string]$mailNickname = $group.Properties["mailnickname"]
                } else {
        	        [string]$mailNickname = [System.DBNull]::Value
                }

                if ($($group.Properties["info"]) -ne $null) {
        	        [string]$info = $group.Properties["info"]
                } else {
        	        [string]$info = [System.DBNull]::Value
                }

    	        if ($($group.Properties["extensionAttribute1"]) -ne $null) { $extensionAttribute1 = $($group.Properties["extensionAttribute1"])} else { $extensionAttribute1 = $null }
    	        if ($($group.Properties["extensionAttribute2"]) -ne $null) { $extensionAttribute2 = $($group.Properties["extensionAttribute2"])} else { $extensionAttribute2 = $null }
    	        if ($($group.Properties["extensionAttribute3"]) -ne $null) { $extensionAttribute3 = $($group.Properties["extensionAttribute3"])} else { $extensionAttribute3 = $null }
    	        if ($($group.Properties["extensionAttribute4"]) -ne $null) { $extensionAttribute4 = $($group.Properties["extensionAttribute4"])} else { $extensionAttribute4 = $null }
    	        if ($($group.Properties["extensionAttribute5"]) -ne $null) { $extensionAttribute5 = $($group.Properties["extensionAttribute5"])} else { $extensionAttribute5 = $null }
    	        if ($($group.Properties["extensionAttribute6"]) -ne $null) { $extensionAttribute6 = $($group.Properties["extensionAttribute6"])} else { $extensionAttribute6 = $null }
    	        if ($($group.Properties["extensionAttribute7"]) -ne $null) { $extensionAttribute7 = $($group.Properties["extensionAttribute7"])} else { $extensionAttribute7 = $null }
    	        if ($($group.Properties["extensionAttribute8"]) -ne $null) { $extensionAttribute8 = $($group.Properties["extensionAttribute8"])} else { $extensionAttribute8 = $null }
    	        if ($($group.Properties["extensionAttribute9"]) -ne $null) { $extensionAttribute9 = $($group.Properties["extensionAttribute9"])} else { $extensionAttribute9 = $null }
    	        if ($($group.Properties["extensionAttribute10"]) -ne $null) { $extensionAttribute10 = $($group.Properties["extensionAttribute10"])} else { $extensionAttribute10 = $null }
    	        if ($($group.Properties["extensionAttribute11"]) -ne $null) { $extensionAttribute11 = $($group.Properties["extensionAttribute11"])} else { $extensionAttribute11 = $null }
    	        if ($($group.Properties["extensionAttribute12"]) -ne $null) { $extensionAttribute12 = $($group.Properties["extensionAttribute12"])} else { $extensionAttribute12 = $null }
    	        if ($($group.Properties["extensionAttribute13"]) -ne $null) { $extensionAttribute13 = $($group.Properties["extensionAttribute13"])} else { $extensionAttribute13 = $null }
    	        if ($($group.Properties["extensionAttribute14"]) -ne $null) { $extensionAttribute14 = $($group.Properties["extensionAttribute14"])} else { $extensionAttribute14 = $null }
    	        if ($($group.Properties["extensionAttribute15"]) -ne $null) { $extensionAttribute15 = $($group.Properties["extensionAttribute15"])} else { $extensionAttribute15 = $null }
        
                [DateTime]$itemWhenChanged = [DateTime]$dsObject.Properties["whencreated"][0]
    	        [DateTime]$itemWhenCreated = [DateTime]$dsObject.Properties["whenchanged"][0]
        
                $Error.Clear()

                $sqlQuery = "SET DATEFORMAT dmy INSERT INTO [KSBL_IAM].[dbo].[stg_Groups]
                                ([Name]
                                ,[Cn]
                                ,[SamAccountName]
                                ,[DisplayName]
                                --,[LegacySourceDomain]
                                ,[Manager]
                                ,[GroupType]
                                ,[Info]
                                ,[MailNickname]
                                ,[TargetAddress]
                                ,[LegacyExchangeDN]
                                ,[ExchHideFromAddressLists]
                                ,[Mail]
                                ,[ProxyAddresses]
                                ,[AuthOrig]
                                ,[UnauthOrig]
                                ,[MemSubmitPerms]
                                ,[MemRejectPerms]
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
                                ,[WhenCreated]
                                ,[WhenChanged]
                                ,[StagingInserted])
                            VALUES
                                ('$($group.Properties["cn"])'
                                ,'$($group.Properties["cn"])'
                                ,'$($group.Properties["samaccountname"])'
                                ,'$($displayName.Replace("'", "''"))'
                                --,null
                                ,'$($group.Properties["managedby"])'
                                ,'$($group.Properties["grouptype"])'
                                ,'$info'                        
                                ,'$mailNickname'
                                ,'$($group.Properties["targetaddress"])'
                                ,'$($group.Properties["legacyexchangedn"])'
                                ,'$ExchHideFromAddressLists'
                                ,'$($group.Properties["mail"])'
                                ,'$proxyAddresses'
                                ,null
                                ,null
                                ,null
                                ,null
                                ,'$($group.Properties["distinguishedname"])'
                                ,'$tranposedGUId'
                                ,'$extensionAttribute1' 
                                ,'$extensionAttribute2' 
                                ,'$extensionAttribute3' 
                                ,'$extensionAttribute4' 
                                ,'$extensionAttribute5' 
                                ,'$extensionAttribute6' 
                                ,'$extensionAttribute7' 
                                ,'$extensionAttribute8' 
                                ,'$extensionAttribute9' 
                                ,'$extensionAttribute10'
                                ,'$extensionAttribute11'
                                ,'$extensionAttribute12'
                                ,'$extensionAttribute13'
                                ,'$extensionAttribute14'
                                ,'$extensionAttribute15'    
                                ,Convert(DateTime, '" + ($itemWhenCreated -f "dd.mm.yyyy hh:mm:ss") + "', 120) 
                                ,Convert(DateTime, '" + ($itemWhenChanged -f "dd.mm.yyyy hh:mm:ss") + "', 120) 
                                ,SYSDATETIME())"
        
                Invoke-Sqlcmd -Query $sqlquery -ServerInstance $iamServer
    		        
                if ($Error.Count -gt 0) {
                    $Error
                    Write-EventLog $global:logName -Source $global:logSourceName -EventId 300 -Message "Query: $sqlQuery \r\n\r\nError: $Error" -EntryType Error
                }    

                # Getting members from an AD Group
                $lstMembers = $null
                $lstMembers = ([System.DirectoryServices.AccountManagement.GroupPrincipal]::FindByIdentity($PrincipalContext, [System.DirectoryServices.AccountManagement.IdentityType]::Name, $($group.Properties["samaccountname"][0]))).Members
            
                # Preparing an SQL Bulk Import based on file Input
                try {
                    $file = "c:\temp\stg_GroupMember_bi.csv"

                    if ((Test-Path $file) -eq $true) {
                        Remove-Item $file -Confirm:$false
                    }

                    $streamWriter = [System.IO.StreamWriter]::new($file)
                    $streamWriter.WriteLine("GroupDistinguishedName;GroupSamAccountName;MemberDistinguishedName;MemberSamAccountName;MemberCategory;StagingInserted")
                    foreach ($member in $lstMembers) {
                        $streamWriter.WriteLine("$($group.Properties["distinguishedname"][0]);$($group.Properties["samaccountname"]);$($member.distinguishedName);$($member.SamAccountName);$($member.StructuralObjectClass);$((get-date).ToString('dd.MM.yyyy hh:mm:ss'))")
                    }
                    $streamWriter.Dispose()
                    $streamWriter.Close()
                } catch { ([System.Exception])
	                if ($_.Exception.InnerException) { $msg = $($_.Exception.InnerException.Message) } else { $msg = $($_.Exception.Message) }  
                    Write-Host "We have an error: $msg " -EntryType Error                          	
                }    
                BulkInsertFile "SV02037.ksbl.local" "KSBL_IAM" "stg_GroupMembers" $file $group

                if ($($group.Properties["managedby"]) -ne $null) {
        	    
                    [string]$managedby = $group.Properties["managedby"]
                    $managedByObject = [ADSI]"LDAP://$($group.Properties["managedby"])"
                
                    if ($managedByObject -ne $null) {

                        $sqlQuery = "IF NOT EXISTS (SELECT * FROM [KSBL_IAM].[dbo].stg_GroupManagers 
	                                    WHERE [GroupDistinguishedName] = '$($group.Properties["distinguishedname"][0])'
	                                    AND [ManagerDistinguishedName] = '$($managedByObject.distinguishedName)')
                                    BEGIN
                                        INSERT INTO [KSBL_IAM].[dbo].[stg_GroupManagers]
                                            ([GroupDistinguishedName]
                                            ,[GroupSamAccountName]
                                            ,[ManagerDistinguishedName]
                                            ,[ManagerSamAccountName]
                                            ,[ManagerCategory]
                                            ,[StagingInserted])
                                        VALUES
                                            ('$($group.Properties["distinguishedname"])'
                                            ,'$($group.Properties["samaccountname"])'
                                            ,'$($managedByObject.DistinguishedName)'
                                            ,'$($managedByObject.SamAccountName)'
                                            ,'$(($managedByObject.objectClass | select -Last 1))'
                                            ,SYSDATETIME())
                                    END"

                        $Error.Clear()
                        Invoke-Sqlcmd -Query $sqlquery -ServerInstance $iamServer

                        if ($Error.Count -gt 0) {
                            $Error
                            Write-EventLog $global:logName -Source $global:logSourceName -EventId 400 -Message "Query: $sqlQuery Error: $Error" -EntryType Error
                        }                    
                    }
        	    }
                
                
                if (-not [System.String]::IsNullOrEmpty($($group.Properties["legacyExchangeDN"]))) {                            

                    if ($($group.Properties["legacyExchangeDN"]).StartsWith("/o=KSBL/ou=Exchange Administrative Group") -eq $true) {

                        $WriteMembersPermissions = $null                        
                        #$WriteMembersPermissions = (Get-DistributionGroup $($group.Properties["distinguishedname"][0])).ManagedBy | ? {$_ -notlike "*/Administrator"}
                        $WriteMembersPermissions = ($distributionGroupReport | ? {$_.DistinguishedName -eq $($group.Properties["DistinguishedName"])})

                        if ($WriteMembersPermissions -ne $null) {                                                            
                
                            ForEach ($writeMember In $WriteMembersPermissions) {            
                    
                                #$writeMemberProps = $null
                                #$writeMemberProps = Get-User $writeMember | Select-Object DistinguishedName,SamAccountName

                                #if (-not [System.String]::IsNullOrEmpty($writeMemberProps)) {
                                    $writeMember.ManagersDn
                                    $writeMember.ManagersUser
                                    $sqlQuery = "IF NOT EXISTS (SELECT * FROM [KSBL_IAM].[dbo].stg_GroupManagers 
	                                                WHERE [GroupDistinguishedName] = '$($group.Properties["distinguishedname"][0])'
	                                                AND [ManagerDistinguishedName] = '$($writeMember.ManagersDn)')
                                                BEGIN
                                                    INSERT INTO [KSBL_IAM].[dbo].[stg_GroupManagers]
                                                        ([GroupDistinguishedName]
                                                        ,[GroupSamAccountName]
                                                        ,[ManagerDistinguishedName]
                                                        ,[ManagerSamAccountName]
                                                        ,[ManagerCategory]
                                                        ,[StagingInserted])
                                                    VALUES
                                                        ('$($group.Properties["distinguishedname"])'
                                                        ,'$($group.Properties["samaccountname"])'
                                                        ,'$($writeMember.ManagersDn)'
                                                        ,'$($writeMember.ManagersUser)'
                                                        ,'user'
                                                        ,SYSDATETIME())
                                                END"
                            
                                    $error.Clear()
                                    Invoke-Sqlcmd -Query $sqlquery -ServerInstance $iamServer
                                    if ($Error.Count -gt 0) {
                                        $Error
                                        Write-EventLog $global:logName -Source $global:logSourceName -EventId 401 -Message "Query: $sqlQuery Error: $Error" -EntryType Error
                                    }    
                                #}
                            }                    
                        }
                    }
                }
                

                if (-not [System.String]::IsNullOrEmpty($($group.Properties["msExchCoManagedByLink"]))) {

                    [System.Array]$arrayExchCoManagedByLink = $($group.Properties["msExchCoManagedByLink"])
                        
                    foreach ($item in $arrayExchCoManagedByLink) {

                        $managedByObject = [ADSI]"LDAP://$item"
                
                        if ($managedByObject -ne $null) {

                            $sqlQuery = "IF NOT EXISTS (SELECT * FROM [KSBL_IAM].[dbo].stg_GroupManagers 
	                                        WHERE [GroupDistinguishedName] = '$($group.Properties["distinguishedname"][0])'
	                                        AND [ManagerDistinguishedName] = '$($managedByObject.distinguishedName)')
                                        BEGIN
                                            INSERT INTO [KSBL_IAM].[dbo].[stg_GroupManagers]
                                                ([GroupDistinguishedName]
                                                ,[GroupSamAccountName]
                                                ,[ManagerDistinguishedName]
                                                ,[ManagerSamAccountName]
                                                ,[ManagerCategory]
                                                ,[StagingInserted])
                                            VALUES
                                                ('$($group.Properties["distinguishedname"])'
                                                ,'$($group.Properties["samaccountname"])'
                                                ,'$($managedByObject.DistinguishedName)'
                                                ,'$($managedByObject.SamAccountName)'
                                                ,'$(($managedByObject.objectClass | select -Last 1))'
                                                ,SYSDATETIME())
                                        END"
                            $Error.Clear()
                            Invoke-Sqlcmd -Query $sqlquery -ServerInstance $iamServer
                            if ($Error.Count -gt 0) {
                                $Error
                                Write-EventLog $global:logName -Source $global:logSourceName -EventId 403 -Message "Query: $sqlQuery Error: $Error" -EntryType Error
                            }                    
                        }
                    }                        
                }            
                
            } catch [System.Exception] {
                if ($_.Exception.InnerException) {
                    Write-EventLog $global:logName -Source $global:logSourceName -EventId 901 -Message "While processing $($group.Properties["adspath"]), the following error occurred. Error: $($_.Exception.InnerException)" -EntryType Error
                } else {
                    Write-EventLog $global:logName -Source $global:logSourceName -EventId 901 -Message "While processing $($group.Properties["adspath"]), the following error occurred. Error: $($_.Exception.Message)" -EntryType Error
        	    }                
    	    }

        }                                   
        
    }

    Get-PSSession | Remove-PSSession

    $global:stopWatch.Stop()    $timeSpan = $global:stopWatch.Elapsed.ToString()    Write-Host "Time elapsed to gather all groups, members and managers from domain $($DomainName): $timeSpan" -ForegroundColor Cyan

}

function MergeGroupsIntoModel
{

    $sqlQuery = "USE [KSBL_IAM]
                GO
				    DECLARE @recordCount int 

				    SET @recordCount = (SELECT COUNT(*) FROM stg_Groups)
			
				    IF (@recordCount > 3000)
				    BEGIN

                        MERGE Groups AS TARGET USING stg_Groups AS SOURCE ON (TARGET.AdReferenceObjectGuid = SOURCE.AdReferenceObjectGuid) 
                        WHEN MATCHED 
                                AND TARGET.[Name] <> SOURCE.[Name]
                                OR TARGET.[Cn] <> SOURCE.[Cn]
                                OR TARGET.[SamAccountName] <> SOURCE.[SamAccountName]
                                OR TARGET.[DisplayName] <> SOURCE.[DisplayName]
                                OR TARGET.[LegacySourceDomain] <> SOURCE.[LegacySourceDomain]
                                OR TARGET.[Manager] <> SOURCE.[Manager]
                                OR TARGET.[GroupType] <> SOURCE.[GroupType]
                                OR TARGET.[Info] <> SOURCE.[Info]
                                OR TARGET.[MailNickname] <> SOURCE.[MailNickname]
                                OR TARGET.[TargetAddress] <> SOURCE.[TargetAddress]
                                OR TARGET.[LegacyExchangeDN] <> SOURCE.[LegacyExchangeDN]
                                OR TARGET.[ExchHideFromAddressLists] <> SOURCE.[ExchHideFromAddressLists]
                                OR TARGET.[Mail] <> SOURCE.[Mail]
                                OR TARGET.[ProxyAddresses] <> SOURCE.[ProxyAddresses]
                                OR TARGET.[AuthOrig] <> SOURCE.[AuthOrig]
                                OR TARGET.[UnauthOrig] <> SOURCE.[UnauthOrig]
                                OR TARGET.[MemSubmitPerms] <> SOURCE.[MemSubmitPerms]
                                OR TARGET.[MemRejectPerms] <> SOURCE.[MemRejectPerms]
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
                                OR TARGET.[WhenCreated] <> SOURCE.[WhenCreated]
                                OR TARGET.[WhenChanged] <> SOURCE.[WhenChanged]
                        THEN 
	                        UPDATE SET TARGET.[Name] = SOURCE.[Name]
                                ,TARGET.[Cn] = SOURCE.[Cn]
                                ,TARGET.[SamAccountName] = SOURCE.[SamAccountName]
                                ,TARGET.[DisplayName] = SOURCE.[DisplayName]
                                ,TARGET.[LegacySourceDomain] = SOURCE.[LegacySourceDomain]
                                ,TARGET.[Manager] = SOURCE.[Manager]
                                ,TARGET.[GroupType] = SOURCE.[GroupType]
                                ,TARGET.[Info] = SOURCE.[Info]
                                ,TARGET.[MailNickname] = SOURCE.[MailNickname]
                                ,TARGET.[TargetAddress] = SOURCE.[TargetAddress]
                                ,TARGET.[LegacyExchangeDN] = SOURCE.[LegacyExchangeDN]
                                ,TARGET.[ExchHideFromAddressLists] = SOURCE.[ExchHideFromAddressLists]
                                ,TARGET.[Mail] = SOURCE.[Mail]
                                ,TARGET.[ProxyAddresses] = SOURCE.[ProxyAddresses]
                                ,TARGET.[AuthOrig] = SOURCE.[AuthOrig]
                                ,TARGET.[UnauthOrig] = SOURCE.[UnauthOrig]
                                ,TARGET.[MemSubmitPerms] = SOURCE.[MemSubmitPerms]
                                ,TARGET.[MemRejectPerms] = SOURCE.[MemRejectPerms]
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
                                ,TARGET.[WhenCreated] = SOURCE.[WhenCreated]
                                ,TARGET.[WhenChanged] = SOURCE.[WhenChanged]
		                        ,TARGET.[ModifiedBy] = SYSTEM_USER 
		                        ,TARGET.[ModifiedOn] = GETDATE()
                        WHEN NOT MATCHED BY TARGET THEN 
	                        INSERT (
		                        [Name]
                                ,[Cn]
                                ,[SamAccountName]
                                ,[DisplayName]
                                ,[LegacySourceDomain]
                                ,[Manager]
                                ,[GroupType]
                                ,[Info]
                                ,[MailNickname]
                                ,[TargetAddress]
                                ,[LegacyExchangeDN]
                                ,[ExchHideFromAddressLists]
                                ,[Mail]
                                ,[ProxyAddresses]
                                ,[AuthOrig]
                                ,[UnauthOrig]
                                ,[MemSubmitPerms]
                                ,[MemRejectPerms]
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
                                ,[WhenCreated]
                                ,[WhenChanged]
                                ,[ModifiedBy]
                                ,[ModifiedOn])
                        VALUES (
                                SOURCE.[Name]
                                ,SOURCE.[Cn]
                                ,SOURCE.[SamAccountName]
                                ,SOURCE.[DisplayName]
                                ,SOURCE.[LegacySourceDomain]
                                ,SOURCE.[Manager]
                                ,SOURCE.[GroupType]
                                ,SOURCE.[Info]
                                ,SOURCE.[MailNickname]
                                ,SOURCE.[TargetAddress]
                                ,SOURCE.[LegacyExchangeDN]
                                ,SOURCE.[ExchHideFromAddressLists]
                                ,SOURCE.[Mail]
                                ,SOURCE.[ProxyAddresses]
                                ,SOURCE.[AuthOrig]
                                ,SOURCE.[UnauthOrig]
                                ,SOURCE.[MemSubmitPerms]
                                ,SOURCE.[MemRejectPerms]
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

    $Error.Clear()
    Invoke-Sqlcmd -Query $sqlquery -ServerInstance $iamServer
    if ($Error.Count -gt 0) {
        $Error
        Write-EventLog $global:logName -Source $global:logSourceName -EventId 501 -Message "Query: $sqlQuery Error: $Error" -EntryType Error
    }    
}

function MergeGroupMembershipsIntoModel
{

    $sqlQuery = "USE [KSBL_IAM]
                GO
				DECLARE @recordCount int 

				SET @recordCount = (
                    SELECT COUNT(*) FROM groups grp 
		                    INNER JOIN stg_GroupMembers mbr ON grp.DistinguishedName = mbr.GroupDistinguishedName
		                    INNER JOIN Accounts acc ON mbr.MemberDistinguishedName = acc.DistinguishedName
                    --ORDER BY grp.SamAccountName ASC
					)
			
				IF (@recordCount > 3000)
				BEGIN

                    TRUNCATE TABLE [AccountsToGroups] 
                    INSERT INTO [dbo].[AccountsToGroups]
                               ([AccountsId]
                               ,[GroupsId]
                               ,[MemberName]
                               ,[MemberCategory]
                               ,[GroupName]
                               ,[ModifiedBy]
                               ,[ModifiedOn])
                    SELECT TOP 100 PERCENT acc.Id
		                    ,grp.Id
		                    ,acc.DisplayName
		                    ,mbr.MemberCategory 
		                    ,case when grp.DisplayName != '' then grp.DisplayName else grp.Name end DisplayName 
	                        ,SYSTEM_USER
	                        ,GETDATE()
                    FROM groups grp 
		                    INNER JOIN stg_GroupMembers mbr ON grp.DistinguishedName = mbr.GroupDistinguishedName
		                    INNER JOIN Accounts acc ON mbr.MemberDistinguishedName = acc.DistinguishedName
                    ORDER BY grp.SamAccountName ASC
				END
				GO"

    $Error.Clear()
    Invoke-Sqlcmd -Query $sqlquery -ServerInstance $iamServer
    if ($Error.Count -gt 0) {
        $Error
        Write-EventLog $global:logName -Source $global:logSourceName -EventId 503 -Message "Query: $sqlQuery Error: $Error" -EntryType Error
    }    
}

function MergeGroupManagersIntoModel
{

    $sqlQuery = "USE [KSBL_IAM]
                GO
				DECLARE @recordCount int 

				SET @recordCount = (
                    SELECT COUNT(*) FROM groups grp 
                            INNER JOIN stg_GroupManagers mgr ON grp.DistinguishedName = mgr.GroupDistinguishedName
                            INNER JOIN Accounts acc ON mgr.ManagerDistinguishedName = acc.DistinguishedName
                    --ORDER BY grp.SamAccountName ASC
				)
			
				IF (@recordCount > 1000)
				BEGIN

                    TRUNCATE TABLE ManagersToGroups 
                    INSERT INTO [dbo].ManagersToGroups
                               ([AccountsId]
                               ,[GroupsId]
                               ,[ManagerName]
                               ,[GroupName]
                               ,[ModifiedBy]
                               ,[ModifiedOn])
                    SELECT TOP 100 PERCENT acc.Id
                            ,grp.Id
                            ,acc.DisplayName 
                            ,grp.DisplayName
	                        ,SYSTEM_USER
	                        ,GETDATE()
                    FROM groups grp 
                            INNER JOIN stg_GroupManagers mgr ON grp.DistinguishedName = mgr.GroupDistinguishedName
                            INNER JOIN Accounts acc ON mgr.ManagerDistinguishedName = acc.DistinguishedName
                    ORDER BY grp.SamAccountName ASC
				END
				GO"

    $Error.Clear()
    Invoke-Sqlcmd -Query $sqlquery -ServerInstance $iamServer
    if ($Error.Count -gt 0) {
        $Error
        Write-EventLog $global:logName -Source $global:logSourceName -EventId 504 -Message "Query: $sqlQuery Error: $Error" -EntryType Error
    }    
}

function MergeRoleTemplatesFromHospisDbIntoModel
{

    $sqlQuery = "USE [KSBL_IAM]
                GO
                TRUNCATE TABLE [KSBL_IAM].[dbo].[RoleTemplates]
                GO
                INSERT INTO [KSBL_IAM].[dbo].[RoleTemplates]
                           ([Standort]
                           ,[Abteilung]
                           ,[Funktion]
                           ,[Template])
                SELECT [Standort]
                      ,[Abteilung]
                      ,[Funktion]
                      ,[Template]
                  FROM [KSBL_Hospis_Staging].[dbo].[RoleTemplates]"

    $Error.Clear()
    Invoke-Sqlcmd -Query $sqlquery -ServerInstance $iamServer
    if ($Error.Count -gt 0) {
        $Error
        Write-EventLog $global:logName -Source $global:logSourceName -EventId 520 -Message "Query: $sqlQuery Error: $Error" -EntryType Error
    }    
}

function UpdateVlSSPGroupsAndMembers {


    Write-EventLog -LogName $global:logName -Source $global:logSourceName -EventId 600 -EntryType Information -Message "=== VLSSP Sync gestartet === Startzeit: $(Get-Date)"

    $iamConnectionString = "Server=SV02037.ksbl.local;Database=KSBL_IAM;Integrated Security=True;"
    $sspConnectionString = "Server=SV02105\SQL02105P;Database=KSBL_SSP;Integrated Security=True;"

    Write-EventLog -LogName $global:logName -Source $global:logSourceName -EventId 601 -EntryType Information -Message "Leere Staging-Tabellen..."
    Invoke-Sqlcmd -ConnectionString $sspConnectionString `
        -Query "TRUNCATE TABLE vlssp_stg_DirectoryUsers; TRUNCATE TABLE vlssp_stg_DistributionGroups; TRUNCATE TABLE vlssp_Stg_DistributionGroupMembers; TRUNCATE TABLE vlssp_Stg_DistributionGroupOwners;"

    $groups = Invoke-Sqlcmd -ConnectionString $iamConnectionString -Query "
            SELECT
                AdReferenceObjectGuid AS GroupId,
                SamAccountName,
                DisplayName,
                Mail,
                CAST(1 AS bit) AS IsMailEnabled
            FROM Groups
            WHERE Mail IS NOT NULL AND Mail <> '' AND AdReferenceObjectGuid IS NOT NULL"

    $accounts = Invoke-Sqlcmd -ConnectionString $iamConnectionString -Query "
            SELECT
                AdReferenceObjectGuid AS UserId,
                SamAccountName,
                DisplayName,
                Mail,
                Department,
                ISNULL(
                    CASE 
                        WHEN UserAccountControl LIKE '%ACCOUNTDISABLE%' 
                            THEN 'Inaktiv'
                        ELSE 'Aktiv'
                    END,
                'Aktiv') AS AccountState,
                hrmsFunctionCategory
            FROM Accounts
            WHERE ExchMailboxGuid <> '' AND EmployeeType IN ('P','E') AND Mail IS NOT NULL"

    $dtGroups = New-Object System.Data.DataTable
    $dtGroups.Columns.Add("GroupId",[Guid]) | Out-Null
    $dtGroups.Columns.Add("SamAccountName",[string]) | Out-Null
    $dtGroups.Columns.Add("DisplayName",[string]) | Out-Null
    $dtGroups.Columns.Add("Mail",[string]) | Out-Null
    $dtGroups.Columns.Add("IsMailEnabled",[bool]) | Out-Null

    foreach($g in $groups){
        $dtGroups.Rows.Add(
            $g.GroupId,
            $g.SamAccountName,
            $g.DisplayName,
            $g.Mail,
            $g.IsMailEnabled
        ) | Out-Null
    }

    $dtUsers = New-Object System.Data.DataTable
    $dtUsers.Columns.Add("UserId",[Guid]) | Out-Null
    $dtUsers.Columns.Add("SamAccountName",[string]) | Out-Null
    $dtUsers.Columns.Add("DisplayName",[string]) | Out-Null
    $dtUsers.Columns.Add("Mail",[string]) | Out-Null
    $dtUsers.Columns.Add("Department",[string]) | Out-Null
    $dtUsers.Columns.Add("hrmsFunctionCategory",[string]) | Out-Null
    $dtUsers.Columns.Add("AccountState",[string]) | Out-Null
    $dtUsers.Columns.Add("Title",[string]) | Out-Null
    $dtUsers.Columns.Add("Company",[string]) | Out-Null
    $dtUsers.Columns.Add("Zip",[string]) | Out-Null
    $dtUsers.Columns.Add("City",[string]) | Out-Null
    $dtUsers.Columns.Add("HnpLocation",[string]) | Out-Null
    $dtUsers.Columns.Add("UpdatedAtUtc",[datetime]) | Out-Null
    $dtUsers.Columns.Add("CreatedAtUtc",[datetime]) | Out-Null


    foreach($a in $accounts){
        $dtUsers.Rows.Add(
            $a.UserId,
            $a.SamAccountName,
            $a.DisplayName,
            $a.Mail,
            $a.Department,
            $a.hrmsFunctionCategory,
            $a.AccountState,
            $null,   # Title
            $null,   # Company
            $null,   # Zip
            $null,   # City
            $null,   # HnpLocation
            $null,   # UpdatedAtUtc
            $null    # CreatedAtUtc
        ) | Out-Null
    }

    Write-EventLog -LogName $global:logName -Source $global:logSourceName -EventId 605 -EntryType Information -Message "Lese AD Kontakte aus OU..."

    $contactsOu = "LDAP://OU=HIN-Contacts,OU=_Users,DC=ksbl,DC=local"
    $de = New-Object System.DirectoryServices.DirectoryEntry($contactsOu)

    $ds = New-Object System.DirectoryServices.DirectorySearcher($de)
    $ds.Filter = "(objectClass=contact)"
    $ds.PageSize = 10000
    $ds.PropertiesToLoad.AddRange(@("objectGUID","cn","displayName","mail","title","company","postalCode","l","department","msExchHideFromAddressLists","whenCreated","whenChanged")) | Out-Null
    $contactResults = $ds.FindAll()

    foreach($c in $contactResults){

        $guid = New-Object Guid (,$c.Properties["objectguid"][0])

        $sam     = ($c.Properties["cn"] | Select-Object -First 1)
        $display = ($c.Properties["displayname"] | Select-Object -First 1)
        $mail    = ($c.Properties["mail"] | Select-Object -First 1)
        if ([string]::IsNullOrWhiteSpace($sam) -or [string]::IsNullOrWhiteSpace($display)) { continue }


        $title = $c.Properties["title"] | Select-Object -First 1
        $company = $c.Properties["company"] | Select-Object -First 1
        $zip = $c.Properties["postalcode"] | Select-Object -First 1
        $city = $c.Properties["l"] | Select-Object -First 1
        $department = $c.Properties["department"] | Select-Object -First 1

        $hidden = $c.Properties["msexchhidefromaddresslists"] | Select-Object -First 1

        # Mapping gemäss Logik
        $accountState = if($hidden -eq $true) { "Inaktiv" } else { "Aktiv" }

        $created = $c.Properties["whencreated"] | Select-Object -First 1
        $changed = $c.Properties["whenchanged"] | Select-Object -First 1

        $dtUsers.Rows.Add(
            $guid,
            $sam,
            $display,
            $mail,
            $department,                 # Department
            $null,                 # hrmsFunctionCategory
            $accountState,
            $title,
            $company,
            $zip,
            $city,
            $null,
            $changed,
            $created
        ) | Out-Null
    }


    Write-EventLog -LogName $global:logName -Source $global:logSourceName -EventId 610 -EntryType Information -Message "BulkCopy Groups → Staging..."
    $bulk = New-Object System.Data.SqlClient.SqlBulkCopy($sspConnectionString)
    $bulk.DestinationTableName = "vlssp_stg_DistributionGroups"
    $bulk.WriteToServer($dtGroups)
    Write-EventLog -LogName $global:logName -Source $global:logSourceName -EventId 611 -EntryType Information -Message "Groups erfolgreich in Staging geschrieben."

    Write-EventLog -LogName $global:logName -Source $global:logSourceName -EventId 615 -EntryType Information -Message "BulkCopy Users → Staging..."
    $bulkUsers = New-Object System.Data.SqlClient.SqlBulkCopy($sspConnectionString)
    $bulkUsers.DestinationTableName = "vlssp_stg_DirectoryUsers"
    $bulkUsers.WriteToServer($dtUsers)
    Write-EventLog -LogName $global:logName -Source $global:logSourceName -EventId 616 -EntryType Information -Message "Users erfolgreich in Staging geschrieben."


    Write-EventLog -LogName $global:logName -Source $global:logSourceName -EventId 620 -EntryType Information -Message "Merge von vlssp_stg_DistributionGroups in die Tabelle vlssp_DistributionGroups..."
    Invoke-Sqlcmd -ConnectionString $sspConnectionString -Query "
    MERGE vlssp_DistributionGroups AS tgt
    USING
    (
        SELECT
            g.GroupId AS GroupId,
            g.SamAccountName,
            g.DisplayName,
            g.Mail,
            CAST(1 AS bit) AS IsMailEnabled
        FROM vlssp_stg_DistributionGroups g
        WHERE g.Mail IS NOT NULL AND g.Mail <> '' AND g.GroupId IS NOT NULL
    ) AS src
    ON tgt.Mail = src.Mail
    WHEN MATCHED AND
    (
           tgt.GroupId         <> src.GroupId
        OR tgt.SamAccountName  <> src.SamAccountName
        OR tgt.DisplayName     <> src.DisplayName
        OR tgt.IsMailEnabled   <> src.IsMailEnabled
    )
    THEN UPDATE SET
        tgt.GroupId        = src.GroupId,
        tgt.SamAccountName = src.SamAccountName,
        tgt.DisplayName    = src.DisplayName,
        tgt.IsMailEnabled  = src.IsMailEnabled,
        tgt.UpdatedAtUtc   = SYSUTCDATETIME()
    WHEN NOT MATCHED BY TARGET
    THEN INSERT
    (
        GroupId,
        SamAccountName,
        DisplayName,
        Mail,
        IsMailEnabled,
        CreatedAtUtc
    )
    VALUES
    (
        src.GroupId,
        src.SamAccountName,
        src.DisplayName,
        src.Mail,
        src.IsMailEnabled,
        SYSUTCDATETIME()
    )
    WHEN NOT MATCHED BY SOURCE
    THEN DELETE;
    "

    Write-EventLog -LogName $global:logName -Source $global:logSourceName -EventId 625 -EntryType Information -Message "Merge von vlssp_Stg_DirectoryUsers in die Tabelle vlssp_DirectoryUsers..."
    Invoke-Sqlcmd -ConnectionString $sspConnectionString -Query "
    MERGE vlssp_DirectoryUsers AS tgt
    USING
    (
        SELECT
            UserId,
            SamAccountName,
            DisplayName,
            Mail,
            Department,
            AccountState
        FROM vlssp_Stg_DirectoryUsers
    ) AS src
    ON tgt.Mail = src.Mail
    WHEN MATCHED AND
    (
           tgt.UserId         <> src.UserId
        OR tgt.SamAccountName <> src.SamAccountName
        OR tgt.DisplayName    <> src.DisplayName
        OR ISNULL(tgt.Department,'') <> ISNULL(src.Department,'')
        OR tgt.AccountState   <> src.AccountState
    )
    THEN UPDATE SET
        tgt.UserId         = src.UserId,
        tgt.SamAccountName = src.SamAccountName,
        tgt.DisplayName    = src.DisplayName,
        tgt.Department     = src.Department,
        tgt.AccountState   = src.AccountState,
        tgt.UpdatedAtUtc   = SYSUTCDATETIME()
    WHEN NOT MATCHED BY TARGET
    THEN INSERT
    (
        UserId,
        SamAccountName,
        DisplayName,
        Mail,
        Department,
        AccountState,
        CreatedAtUtc
    )
    VALUES
    (
        src.UserId,
        src.SamAccountName,
        src.DisplayName,
        src.Mail,
        src.Department,
        src.AccountState,
        SYSUTCDATETIME()
    )
    WHEN NOT MATCHED BY SOURCE
    THEN DELETE;
    "

    Write-EventLog -LogName $global:logName -Source $global:logSourceName -EventId 630 -EntryType Information -Message "Lade Verteilerlisten aus Exchange..."

    try {
        if ((Get-PSSession | ? {$_.State -like "Opened" -and $_.Availability -like "Available"}) -eq $null) {
            Get-PSSession | Remove-PSSession
            $cred = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList "ksbl\serviceiamjobs10" , (Get-Content "D:\iam\Secrets\serviceiamjobs10.sec" | ConvertTo-SecureString) 
            $PSSession = new-pssession –configurationname Microsoft.Exchange –connectionuri http://sv01248.ksbl.local/PowerShell –credential $cred -Authentication Kerberos 
            Import-PSSession $PSSession -AllowClobber
        }
    } catch {
        if ($_.Exception.InnerException) { $msg = $_.Exception.InnerException.Message } else { $msg = $_.Exception.Message }
        Write-EventLog -LogName $global:logName -Source $global:logSourceName -EventId 700 -Message "Failed establishing a remote Powershell session to Exchange.`r`n`r`nError: $msg" -EntryType Error
        Exit
    }


    $distGroups = Get-DistributionGroup -ResultSize Unlimited | Select-Object Name,SamAccountName,DistinguishedName,Guid,ManagedBy
    $totalGroups = $distGroups.Count
    Write-EventLog -LogName $global:logName -Source $global:logSourceName -EventId 635 -EntryType Information -Message "Gefundene Verteilerlisten: $totalGroups"

    $ownerRows  = New-Object System.Collections.Generic.List[object]
    $memberRows = New-Object System.Collections.Generic.List[object]

    $groupIndex = 0

    foreach ($dg in $distGroups) {

        $groupIndex++
        Write-Progress -Activity "Verarbeite Verteilerlisten" -Status "$groupIndex / $totalGroups : $($dg.Name)" -PercentComplete (($groupIndex / $totalGroups) * 100)

        # Members
        try {
            $members = Get-ADGroupMember $dg.DistinguishedName -ErrorAction Stop
        } catch {
            Write-EventLog -LogName $global:logName -Source $global:logSourceName -EventId 640 -EntryType Warning -Message "Mitglieder konnten nicht gelesen werden: $($dg.Name)"
            $members = @()
        }

        foreach ($memberRef in $members) {

            $memberType = switch ($memberRef.objectClass) {
                'user'  { 'User' }
                'group' { 'Group' }
                default { $null }
            }

            if (-not $memberType) {
                continue
            }

            $memberRows.Add([pscustomobject]@{
                GroupId        = $dg.Guid.Guid
                MemberObjectId = $memberRef.ObjectGUID.Guid
                MemberType     = $memberType
            })
        }   

        # Owners
        foreach ($ownerRef in $dg.ManagedBy) {

            # Technische Owner ausschliessen
            if ($ownerRef -match '/Users/Administrator$') {
                continue
            }

            try {
                $exUser = Get-User -Identity $ownerRef -ErrorAction Stop

                if ($exUser.RecipientTypeDetails -notlike '*User*') {
                    continue
                }

                $adUser = Get-ADUser -Identity $exUser.SamAccountName -Properties ObjectGUID -ErrorAction Stop

                $ownerRows.Add([pscustomobject]@{
                    GroupId     = $dg.Guid.Guid
                    OwnerUserId = $adUser.ObjectGUID.Guid
                })
            } catch {
                Write-EventLog -LogName $global:logName -Source $global:logSourceName -EventId 645 -EntryType Warning -Message "Owner konnte nicht aufgelöst werden: $ownerRef (Group: $($dg.Name))"
            }
        }
    }

    Write-Progress -Activity "Verarbeite Verteilerlisten" -Completed
    Write-EventLog -LogName $global:logName -Source $global:logSourceName -EventId 650 -EntryType Information -Message "Sammlung abgeschlossen: Roh-Members: $($memberRows.Count), Roh-Owners: $($ownerRows.Count)"

    Write-EventLog -LogName $global:logName -Source $global:logSourceName -EventId 655 -EntryType Information -Message "Duplikate entfernen..."
    $memberRows = $memberRows | Sort-Object GroupId, MemberObjectId, MemberType -Unique
    $ownerRows = $ownerRows | Sort-Object GroupId, OwnerUserId -Unique
    Write-EventLog -LogName $global:logName -Source $global:logSourceName -EventId 656 -EntryType Information -Message "Eindeutige Members: $($memberRows.Count), Eindeutige Owners: $($ownerRows.Count)"


    # DataTable Members
    $dtMembers = New-Object System.Data.DataTable
    $dtMembers.Columns.Add("GroupId",[Guid]) | Out-Null
    $dtMembers.Columns.Add("MemberObjectId",[Guid]) | Out-Null
    $dtMembers.Columns.Add("MemberType",[string]) | Out-Null

    foreach ($r in $memberRows) {
        $dtMembers.Rows.Add($r.GroupId, $r.MemberObjectId, $r.MemberType) | Out-Null
    }

    Write-EventLog -LogName $global:logName -Source $global:logSourceName -EventId 660 -EntryType Information -Message "BulkCopy Members → Staging ($($memberRows.Count) Einträge)..."
    $bulkMembers = New-Object System.Data.SqlClient.SqlBulkCopy($sspConnectionString)
    $bulkMembers.DestinationTableName = "vlssp_Stg_DistributionGroupMembers"
    $bulkMembers.WriteToServer($dtMembers)
    Write-EventLog -LogName $global:logName -Source $global:logSourceName -EventId 661 -EntryType Information -Message "Members erfolgreich geschrieben."

    # DataTable Owners
    $dtOwners = New-Object System.Data.DataTable
    $dtOwners.Columns.Add("GroupId",[Guid]) | Out-Null
    $dtOwners.Columns.Add("OwnerUserId",[Guid]) | Out-Null

    foreach ($r in $ownerRows) {
        $dtOwners.Rows.Add($r.GroupId, $r.OwnerUserId) | Out-Null
    }

    Write-EventLog -LogName $global:logName -Source $global:logSourceName -EventId 665 -EntryType Information -Message "BulkCopy Owners → Staging ($($ownerRows.Count) Einträge)..."
    $bulkOwners = New-Object System.Data.SqlClient.SqlBulkCopy($sspConnectionString)
    $bulkOwners.DestinationTableName = "vlssp_Stg_DistributionGroupOwners"
    $bulkOwners.WriteToServer($dtOwners)
    Write-EventLog -LogName $global:logName -Source $global:logSourceName -EventId 666 -EntryType Information -Message "Owners erfolgreich geschrieben."

    Write-EventLog -LogName $global:logName -Source $global:logSourceName -EventId 670 -EntryType Information -Message "MERGE DistributionGroupMembers..."
    Invoke-Sqlcmd -ConnectionString $sspConnectionString -Query "
    MERGE vlssp_DistributionGroupMembers AS tgt
    USING
    (
        SELECT DISTINCT
            s.GroupId,
            s.MemberObjectId,
            s.MemberType
        FROM vlssp_Stg_DistributionGroupMembers s
        JOIN vlssp_DistributionGroups g
            ON g.GroupId = s.GroupId
        LEFT JOIN vlssp_DirectoryUsers u
            ON s.MemberType = 'User'
           AND u.UserId = s.MemberObjectId
        LEFT JOIN vlssp_DistributionGroups g2
            ON s.MemberType = 'Group'
           AND g2.GroupId = s.MemberObjectId
        WHERE
            (s.MemberType = 'User'  AND u.UserId IS NOT NULL)
         OR (s.MemberType = 'Group' AND g2.GroupId IS NOT NULL)
    ) AS src
    ON  tgt.GroupId        = src.GroupId
    AND tgt.MemberObjectId = src.MemberObjectId
    AND tgt.MemberType     = src.MemberType

    WHEN NOT MATCHED BY TARGET THEN
        INSERT (GroupId, MemberObjectId, MemberType, CreatedAtUtc)
        VALUES (src.GroupId, src.MemberObjectId, src.MemberType, SYSUTCDATETIME())

    WHEN NOT MATCHED BY SOURCE
        AND tgt.GroupId IN (SELECT DISTINCT GroupId FROM vlssp_Stg_DistributionGroupMembers)
    THEN DELETE;
    "

    Write-EventLog -LogName $global:logName -Source $global:logSourceName -EventId 675 -EntryType Information -Message "MERGE DistributionGroupOwners..."
    Invoke-Sqlcmd -ConnectionString $sspConnectionString -Query "
    MERGE vlssp_DistributionGroupOwners AS tgt
    USING
    (
        SELECT DISTINCT
            s.GroupId,
            s.OwnerUserId
        FROM vlssp_Stg_DistributionGroupOwners s
        JOIN vlssp_DistributionGroups g
            ON g.GroupId = s.GroupId
        JOIN vlssp_DirectoryUsers u
            ON u.UserId = s.OwnerUserId
    ) AS src
    ON  tgt.GroupId     = src.GroupId
    AND tgt.OwnerUserId = src.OwnerUserId

    WHEN NOT MATCHED BY TARGET THEN
        INSERT (GroupId, OwnerUserId, OwnerRole, CreatedAtUtc)
        VALUES (src.GroupId, src.OwnerUserId, 'Owner', SYSUTCDATETIME())

    WHEN NOT MATCHED BY SOURCE
        AND tgt.GroupId IN (SELECT DISTINCT GroupId FROM vlssp_Stg_DistributionGroupOwners)
    THEN DELETE;
    "

    Write-EventLog -LogName $global:logName -Source $global:logSourceName -EventId 699 -EntryType Information -Message "=== VLSSP Sync abgeschlossen === Endzeit: $(Get-Date)"

    <#
    Write-Host "=== VLSSP Sync gestartet ===" -ForegroundColor Cyan
    Write-Host "Startzeit: $(Get-Date)" -ForegroundColor DarkGray

    $iamConnectionString = "Server=SV02037.ksbl.local;Database=KSBL_IAM;Integrated Security=True;"
    $sspConnectionString = "Server=SV02105\SQL02105P;Database=KSBL_SSP;Integrated Security=True;"

    Write-Host "Leere Staging-Tabellen..." -ForegroundColor Cyan
    Invoke-Sqlcmd -ConnectionString $sspConnectionString `
        -Query "TRUNCATE TABLE vlssp_stg_DirectoryUsers; TRUNCATE TABLE vlssp_stg_DistributionGroups; TRUNCATE TABLE vlssp_Stg_DistributionGroupMembers; TRUNCATE TABLE vlssp_Stg_DistributionGroupOwners;"

    $groups = Invoke-Sqlcmd -ConnectionString $iamConnectionString -Query "
            SELECT
                AdReferenceObjectGuid AS GroupId,
                SamAccountName,
                DisplayName,
                Mail,
                CAST(1 AS bit) AS IsMailEnabled
            FROM Groups
            WHERE Mail IS NOT NULL AND Mail <> '' AND AdReferenceObjectGuid IS NOT NULL"

    $accounts = Invoke-Sqlcmd -ConnectionString $iamConnectionString -Query "
            SELECT
                AdReferenceObjectGuid AS UserId,
                SamAccountName,
                DisplayName,
                Mail,
                Department,
                ISNULL(
                    CASE 
                        WHEN UserAccountControl LIKE '%ACCOUNTDISABLE%' 
                            THEN 'Inaktiv'
                        ELSE 'Aktiv'
                    END,
                'Aktiv') AS AccountState,
                hrmsFunctionCategory
            FROM Accounts
            WHERE ExchMailboxGuid <> '' AND EmployeeType IN ('P','E') AND Mail IS NOT NULL"

    $dtGroups = New-Object System.Data.DataTable
    $dtGroups.Columns.Add("GroupId",[Guid]) | Out-Null
    $dtGroups.Columns.Add("SamAccountName",[string]) | Out-Null
    $dtGroups.Columns.Add("DisplayName",[string]) | Out-Null
    $dtGroups.Columns.Add("Mail",[string]) | Out-Null
    $dtGroups.Columns.Add("IsMailEnabled",[bool]) | Out-Null

    foreach($g in $groups){
        $dtGroups.Rows.Add(
            $g.GroupId,
            $g.SamAccountName,
            $g.DisplayName,
            $g.Mail,
            $g.IsMailEnabled
        ) | Out-Null
    }

    $dtUsers = New-Object System.Data.DataTable
    $dtUsers.Columns.Add("UserId",[Guid]) | Out-Null
    $dtUsers.Columns.Add("SamAccountName",[string]) | Out-Null
    $dtUsers.Columns.Add("DisplayName",[string]) | Out-Null
    $dtUsers.Columns.Add("Mail",[string]) | Out-Null
    $dtUsers.Columns.Add("Department",[string]) | Out-Null
    $dtUsers.Columns.Add("hrmsFunctionCategory",[string]) | Out-Null
    $dtUsers.Columns.Add("AccountState",[string]) | Out-Null
    $dtUsers.Columns.Add("Title",[string]) | Out-Null
    $dtUsers.Columns.Add("Company",[string]) | Out-Null
    $dtUsers.Columns.Add("Zip",[string]) | Out-Null
    $dtUsers.Columns.Add("City",[string]) | Out-Null
    $dtUsers.Columns.Add("HnpLocation",[string]) | Out-Null
    $dtUsers.Columns.Add("UpdatedAtUtc",[datetime]) | Out-Null
    $dtUsers.Columns.Add("CreatedAtUtc",[datetime]) | Out-Null


    foreach($a in $accounts){
        $dtUsers.Rows.Add(
            $a.UserId,
            $a.SamAccountName,
            $a.DisplayName,
            $a.Mail,
            $a.Department,
            $a.hrmsFunctionCategory,
            $a.AccountState,
            $null,   # Title
            $null,   # Company
            $null,   # Zip
            $null,   # City
            $null,   # HnpLocation
            $null,   # UpdatedAtUtc
            $null    # CreatedAtUtc
        ) | Out-Null
    }

    Write-Host "Lese AD Kontakte aus OU..." -ForegroundColor Cyan

    $contactsOu = "LDAP://OU=HIN-Contacts,OU=_Users,DC=ksbl,DC=local"
    $de = New-Object System.DirectoryServices.DirectoryEntry($contactsOu)

    $ds = New-Object System.DirectoryServices.DirectorySearcher($de)
    $ds.Filter = "(objectClass=contact)"
    $ds.PageSize = 10000
    $ds.PropertiesToLoad.AddRange(@("objectGUID","cn","displayName","mail","title","company","postalCode","l","department","msExchHideFromAddressLists","whenCreated","whenChanged")) | Out-Null
    $contactResults = $ds.FindAll()

    foreach($c in $contactResults){

        $guid = New-Object Guid (,$c.Properties["objectguid"][0])

        $sam     = ($c.Properties["cn"] | Select-Object -First 1)
        $display = ($c.Properties["displayname"] | Select-Object -First 1)
        $mail    = ($c.Properties["mail"] | Select-Object -First 1)
        if ([string]::IsNullOrWhiteSpace($sam) -or [string]::IsNullOrWhiteSpace($display)) { continue }


        $title = $c.Properties["title"] | Select-Object -First 1
        $company = $c.Properties["company"] | Select-Object -First 1
        $zip = $c.Properties["postalcode"] | Select-Object -First 1
        $city = $c.Properties["l"] | Select-Object -First 1
        $department = $c.Properties["department"] | Select-Object -First 1

        $hidden = $c.Properties["msexchhidefromaddresslists"] | Select-Object -First 1

        # Mapping gemäss deiner Logik
        $accountState = if($hidden -eq $true) { "Inaktiv" } else { "Aktiv" }

        $created = $c.Properties["whencreated"] | Select-Object -First 1
        $changed = $c.Properties["whenchanged"] | Select-Object -First 1

        $dtUsers.Rows.Add(
            $guid,
            $sam,
            $display,
            $mail,
            $department,                 # Department
            $null,                 # hrmsFunctionCategory
            $accountState,
            $title,
            $company,
            $zip,
            $city,
            $null,
            $changed,
            $created
        ) | Out-Null
    }


    Write-Host "BulkCopy Groups → Staging..." -ForegroundColor Cyan
    $bulk = New-Object System.Data.SqlClient.SqlBulkCopy($sspConnectionString)
    $bulk.DestinationTableName = "vlssp_stg_DistributionGroups"
    $bulk.WriteToServer($dtGroups)
    Write-Host "Groups erfolgreich in Staging geschrieben." -ForegroundColor Green

    Write-Host "BulkCopy Users → Staging..." -ForegroundColor Cyan
    $bulkUsers = New-Object System.Data.SqlClient.SqlBulkCopy($sspConnectionString)
    $bulkUsers.DestinationTableName = "vlssp_stg_DirectoryUsers"
    $bulkUsers.WriteToServer($dtUsers)
    Write-Host "Users erfolgreich in Staging geschrieben." -ForegroundColor Green


    Write-Host "Merge von vlssp_stg_DistributionGroups in die Tabelle vlssp_DistributionGroups..." -ForegroundColor Cyan
    Invoke-Sqlcmd -ConnectionString $sspConnectionString -Query "
    MERGE vlssp_DistributionGroups AS tgt
    USING
    (
        SELECT
            g.GroupId AS GroupId,
            g.SamAccountName,
            g.DisplayName,
            g.Mail,
            CAST(1 AS bit) AS IsMailEnabled
        FROM vlssp_stg_DistributionGroups g
        WHERE g.Mail IS NOT NULL AND g.Mail <> '' AND g.GroupId IS NOT NULL
    ) AS src
    ON tgt.Mail = src.Mail
    WHEN MATCHED AND
    (
           tgt.GroupId         <> src.GroupId
        OR tgt.SamAccountName  <> src.SamAccountName
        OR tgt.DisplayName     <> src.DisplayName
        OR tgt.IsMailEnabled   <> src.IsMailEnabled
    )
    THEN UPDATE SET
        tgt.GroupId        = src.GroupId,
        tgt.SamAccountName = src.SamAccountName,
        tgt.DisplayName    = src.DisplayName,
        tgt.IsMailEnabled  = src.IsMailEnabled,
        tgt.UpdatedAtUtc   = SYSUTCDATETIME()
    WHEN NOT MATCHED BY TARGET
    THEN INSERT
    (
        GroupId,
        SamAccountName,
        DisplayName,
        Mail,
        IsMailEnabled,
        CreatedAtUtc
    )
    VALUES
    (
        src.GroupId,
        src.SamAccountName,
        src.DisplayName,
        src.Mail,
        src.IsMailEnabled,
        SYSUTCDATETIME()
    )
    WHEN NOT MATCHED BY SOURCE
    THEN DELETE;
    "

    Write-Host "Merge von vlssp_Stg_DirectoryUsers in die Tabelle vlssp_DirectoryUsers..." -ForegroundColor Cyan
    Invoke-Sqlcmd -ConnectionString $sspConnectionString -Query "
    MERGE vlssp_DirectoryUsers AS tgt
    USING
    (
        SELECT
            UserId,
            SamAccountName,
            DisplayName,
            Mail,
            Department,
            AccountState
        FROM vlssp_Stg_DirectoryUsers
    ) AS src
    ON tgt.Mail = src.Mail
    WHEN MATCHED AND
    (
           tgt.UserId        <> src.UserId
        OR tgt.SamAccountName<> src.SamAccountName
        OR tgt.DisplayName   <> src.DisplayName
        OR ISNULL(tgt.Department,'') <> ISNULL(src.Department,'')
        OR tgt.AccountState  <> src.AccountState
    )
    THEN UPDATE SET
        tgt.UserId         = src.UserId,
        tgt.SamAccountName = src.SamAccountName,
        tgt.DisplayName    = src.DisplayName,
        tgt.Department     = src.Department,
        tgt.AccountState   = src.AccountState,
        tgt.UpdatedAtUtc   = SYSUTCDATETIME()
    WHEN NOT MATCHED BY TARGET
    THEN INSERT
    (
        UserId,
        SamAccountName,
        DisplayName,
        Mail,
        Department,
        AccountState,
        CreatedAtUtc
    )
    VALUES
    (
        src.UserId,
        src.SamAccountName,
        src.DisplayName,
        src.Mail,
        src.Department,
        src.AccountState,
        SYSUTCDATETIME()
    )
    WHEN NOT MATCHED BY SOURCE
    THEN DELETE;
    "

    Write-Host "Lade Verteilerlisten aus Exchange..." -ForegroundColor Cyan

    try {
        if ((Get-PSSession | ? {$_.State -like "Opened" -and $_.Availability -like "Available"}) -eq $null) {
            Get-PSSession | Remove-PSSession
			$cred = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList "ksbl\serviceiamjobs10" , (Get-Content "D:\iam\Secrets\serviceiamjobs10.sec" | ConvertTo-SecureString) 
			$PSSession = new-pssession –configurationname Microsoft.Exchange –connectionuri http://sv01248.ksbl.local/PowerShell –credential $cred -Authentication Kerberos 
			Import-PSSession $PSSession -AllowClobber
        }
    } catch {([Management.Automation.Remoting.PSRemotingTransportException],[Exception])
	    if ($_.Exception.InnerException) { $msg = $_.Exception.InnerException.Message } else { $msg = $_.Exception.Message }
        Write-EventLog $global:logName -Source $global:logSourceName -EventId 1000 -Message "Failed establishing a remote Powershell session to Exchange.\r\n\r\nError: $msg" -EntryType Error
        Exit
    }


    $distGroups = Get-DistributionGroup -ResultSize Unlimited | Select-Object Name,SamAccountName,DistinguishedName,Guid,ManagedBy
    $totalGroups = $distGroups.Count
    Write-Host "Gefundene Verteilerlisten: $totalGroups" -ForegroundColor Green

    $ownerRows  = New-Object System.Collections.Generic.List[object]
    $memberRows = New-Object System.Collections.Generic.List[object]

    $groupIndex = 0

    foreach ($dg in $distGroups) {

        $groupIndex++
        Write-Progress -Activity "Verarbeite Verteilerlisten" -Status "$groupIndex / $totalGroups : $($dg.Name)" -PercentComplete (($groupIndex / $totalGroups) * 100)

        # Members
        try {
            $members = Get-ADGroupMember $dg.DistinguishedName -ErrorAction Stop
        } catch {
            Write-Warning "Mitglieder konnten nicht gelesen werden: $($dg.Name)"
            $members = @()
        }

        foreach ($memberRef in $members) {

            $memberType = switch ($memberRef.objectClass) {
                'user'  { 'User' }
                'group' { 'Group' }
                default { $null }
            }

            if (-not $memberType) {
                continue
            }

            $memberRows.Add([pscustomobject]@{
                GroupId        = $dg.Guid.Guid
                MemberObjectId = $memberRef.ObjectGUID.Guid
                MemberType     = $memberType
            })
        }   

        # Owners
        foreach ($ownerRef in $dg.ManagedBy) {

            # Technische Owner ausschliessen
            if ($ownerRef -match '/Users/Administrator$') {
                Write-Verbose "Technischer Owner uebersprungen: $ownerRef (Group: $($dg.Name))"
                continue
            }

            try {
                $exUser = Get-User -Identity $ownerRef -ErrorAction Stop

                if ($exUser.RecipientTypeDetails -notlike '*User*') {
                    Write-Verbose "Owner ist kein User: $ownerRef ($($exUser.RecipientTypeDetails))"
                    continue
                }

                $adUser = Get-ADUser -Identity $exUser.SamAccountName -Properties ObjectGUID -ErrorAction Stop

                $ownerRows.Add([pscustomobject]@{
                    GroupId     = $dg.Guid.Guid
                    OwnerUserId = $adUser.ObjectGUID.Guid
                })
            } catch {
                Write-Warning "Owner konnte nicht aufgeloest werden: $ownerRef (Group: $($dg.Name))"
            }
        }
    }

    Write-Progress -Activity "Verarbeite Verteilerlisten" -Completed
    Write-Host "Sammlung abgeschlossen:" -ForegroundColor Cyan
    Write-Host " Roh-Members : $($memberRows.Count)" -ForegroundColor Gray
    Write-Host " Roh-Owners : $($ownerRows.Count)" -ForegroundColor Gray

    Write-Host "Duplikate entfernen..." -ForegroundColor Cyan
    $memberRows = $memberRows | Sort-Object GroupId, MemberObjectId, MemberType -Unique
    $ownerRows = $ownerRows | Sort-Object GroupId, OwnerUserId -Unique
    Write-Host " Eindeutige Members: $($memberRows.Count)" -ForegroundColor Green
    Write-Host " Eindeutige Owners : $($ownerRows.Count)" -ForegroundColor Green


    # DataTable Members
    $dtMembers = New-Object System.Data.DataTable
    $dtMembers.Columns.Add("GroupId",[Guid]) | Out-Null
    $dtMembers.Columns.Add("MemberObjectId",[Guid]) | Out-Null
    $dtMembers.Columns.Add("MemberType",[string]) | Out-Null

    foreach ($r in $memberRows) {
        $dtMembers.Rows.Add($r.GroupId, $r.MemberObjectId, $r.MemberType) | Out-Null
    }

    Write-Host "BulkCopy Members → Staging ($($memberRows.Count) Einträge)..." -ForegroundColor Cyan
    $bulkMembers = New-Object System.Data.SqlClient.SqlBulkCopy($sspConnectionString)
    $bulkMembers.DestinationTableName = "vlssp_Stg_DistributionGroupMembers"
    $bulkMembers.WriteToServer($dtMembers)
    Write-Host "Members erfolgreich geschrieben." -ForegroundColor Green

    # DataTable Owners
    $dtOwners = New-Object System.Data.DataTable
    $dtOwners.Columns.Add("GroupId",[Guid]) | Out-Null
    $dtOwners.Columns.Add("OwnerUserId",[Guid]) | Out-Null

    foreach ($r in $ownerRows) {
        $dtOwners.Rows.Add($r.GroupId, $r.OwnerUserId) | Out-Null
    }

    Write-Host "BulkCopy Owners → Staging ($($ownerRows.Count) Einträge)..." -ForegroundColor Cyan
    $bulkOwners = New-Object System.Data.SqlClient.SqlBulkCopy($sspConnectionString)
    $bulkOwners.DestinationTableName = "vlssp_Stg_DistributionGroupOwners"
    $bulkOwners.WriteToServer($dtOwners)
    Write-Host "Owners erfolgreich geschrieben." -ForegroundColor Green

    Write-Host "MERGE DistributionGroupMembers..." -ForegroundColor Cyan
    Invoke-Sqlcmd -ConnectionString $sspConnectionString -Query "
    MERGE vlssp_DistributionGroupMembers AS tgt
    USING
    (
        SELECT DISTINCT
            s.GroupId,
            s.MemberObjectId,
            s.MemberType
        FROM vlssp_Stg_DistributionGroupMembers s
        JOIN vlssp_DistributionGroups g
            ON g.GroupId = s.GroupId
        LEFT JOIN vlssp_DirectoryUsers u
            ON s.MemberType = 'User'
           AND u.UserId = s.MemberObjectId
        LEFT JOIN vlssp_DistributionGroups g2
            ON s.MemberType = 'Group'
           AND g2.GroupId = s.MemberObjectId
        WHERE
            (s.MemberType = 'User'  AND u.UserId IS NOT NULL)
         OR (s.MemberType = 'Group' AND g2.GroupId IS NOT NULL)
    ) AS src
    ON  tgt.GroupId        = src.GroupId
    AND tgt.MemberObjectId = src.MemberObjectId
    AND tgt.MemberType     = src.MemberType

    WHEN NOT MATCHED BY TARGET THEN
        INSERT (GroupId, MemberObjectId, MemberType, CreatedAtUtc)
        VALUES (src.GroupId, src.MemberObjectId, src.MemberType, SYSUTCDATETIME())

    WHEN NOT MATCHED BY SOURCE
        AND tgt.GroupId IN (SELECT DISTINCT GroupId FROM vlssp_Stg_DistributionGroupMembers)
    THEN DELETE;
    "

    Write-Host "MERGE DistributionGroupOwners..." -ForegroundColor Cyan
    Invoke-Sqlcmd -ConnectionString $sspConnectionString -Query "
    MERGE vlssp_DistributionGroupOwners AS tgt
    USING
    (
        SELECT DISTINCT
            s.GroupId,
            s.OwnerUserId
        FROM vlssp_Stg_DistributionGroupOwners s
        JOIN vlssp_DistributionGroups g
            ON g.GroupId = s.GroupId
        JOIN vlssp_DirectoryUsers u
            ON u.UserId = s.OwnerUserId
    ) AS src
    ON  tgt.GroupId     = src.GroupId
    AND tgt.OwnerUserId = src.OwnerUserId

    WHEN NOT MATCHED BY TARGET THEN
        INSERT (GroupId, OwnerUserId, OwnerRole, CreatedAtUtc)
        VALUES (src.GroupId, src.OwnerUserId, 'Owner', SYSUTCDATETIME())

    WHEN NOT MATCHED BY SOURCE
        AND tgt.GroupId IN (SELECT DISTINCT GroupId FROM vlssp_Stg_DistributionGroupOwners)
    THEN DELETE;
    "

    Write-Host "=== VLSSP Sync abgeschlossen ===" -ForegroundColor Cyan
    Write-Host "Endzeit: $(Get-Date)" -ForegroundColor DarkGray
    #>
}


Clear-Host
Add-Type -AssemblyName System.DirectoryServices.AccountManagement

$global:logName = "KSBL IAM"
$global:logSourceName = "Staging"

$global:iamServer = "SV02037.ksbl.local"
$global:smtpHost = "sv01250.ksbl.local"
$global:mailFrom = "informatik@ksbl.ch"

Test-EventLog $global:logName $global:logSourceName
Write-EventLog $global:logName -Source $global:logSourceName -EventId 1 -Message "IAM staging job started at $(Get-Date)" -EntryType Information


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


$timeTakenToComplete = Measure-Command { 

    try {
        $sqlQuery = "TRUNCATE TABLE [KSBL_IAM].[dbo].[stg_Groups]"			
        Invoke-Sqlcmd -Query $sqlquery -ServerInstance $iamServer
    } catch { ([System.Exception])
	    if ($_.Exception.InnerException) { $msg = $($_.Exception.InnerException.Message) } else { $msg = $($_.Exception.Message) }  
        Write-EventLog $global:logName -Source $global:logSourceName -EventId 211 -Message "Failed executing SQL-Stmt $($sqlQuery): $msg " -EntryType Error                          	
    }

    try {
        $sqlQuery = "TRUNCATE TABLE [KSBL_IAM].[dbo].[stg_GroupMembers]"			
        Invoke-Sqlcmd -Query $sqlquery -ServerInstance $iamServer
    } catch { ([System.Exception])
	    if ($_.Exception.InnerException) { $msg = $($_.Exception.InnerException.Message) } else { $msg = $($_.Exception.Message) }  
        Write-EventLog $global:logName -Source $global:logSourceName -EventId 211 -Message "Failed executing SQL-Stmt $($sqlQuery): $msg " -EntryType Error                          	
    }

    try {
        $sqlQuery = "TRUNCATE TABLE [KSBL_IAM].[dbo].[stg_GroupManagers]"			
        Invoke-Sqlcmd -Query $sqlquery -ServerInstance $iamServer
    } catch { ([System.Exception])
	    if ($_.Exception.InnerException) { $msg = $($_.Exception.InnerException.Message) } else { $msg = $($_.Exception.Message) }  
        Write-EventLog $global:logName -Source $global:logSourceName -EventId 211 -Message "Failed executing SQL-Stmt $($sqlQuery): $msg " -EntryType Error                          	
    }

    InsertGroupsAndMembersIntoStaging

    MergeGroupsIntoModel

    MergeGroupMembershipsIntoModel

    MergeGroupManagersIntoModel

    MergeRoleTemplatesFromHospisDbIntoModel

    UpdateVlSSPGroupsAndMembers

}

Get-PSSession | Remove-PSSession -ErrorAction SilentlyContinue


Write-EventLog $global:logName -Source $global:logSourceName -EventId 1 -Message "IAM staging job finished after $([Math]::Round($timeTakenToComplete.TotalMinutes,0)) Minutes" -EntryType Information
Write-Host "IAM staging job finished after $([Math]::Round($timeTakenToComplete.TotalMinutes,0)) Minutes" -ForegroundColor Green


