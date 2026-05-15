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
                UebertrittM2,
                UebertrittM1,
                Unbekannt
        }
"@
if (-not ([System.Management.Automation.PSTypeName]'UseCaseType').Type) { Add-Type -TypeDefinition $cSharpEnum }


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
        $cn.ConnectionString = "Server=SV02037.ksbl.local;Database=KSBL_Hospis_Staging;User ID=ksblhospis2ad;Password=L3tmein!;Connection Timeout=30"

		$cm = New-Object System.Data.SqlClient.SqlCommand
		$cm.Connection = $cn
        $cm.CommandTimeout = 60
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
    	Write-EventLog $global:logName -Source $global:logSourceName -EventId 4000 -Message "Failed executing SQL-Stmt $($sqlStatement): $msg " -EntryType Error                          	
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

cls

$ErrorActionPreference = "stop"

$smtpHost = "relay.ksbl.local"
$mailFrom = "informatik@ksbl.ch"
$mailCc = "ksbl.vl.iam-administrators@ksbl.ch"

$jobsToProcess = $null
$primaryMailDomain = "ksbl.ch"
$workingPath = "d:\IAM\Queue"

$sendMailToCustomer = $false

$global:logname = "KSBL Helpdesk GUI"
$global:logSourceName = "Process-UserPerson"
#[System.Diagnostics.EventLog]::CreateEventSource($global:logSourceName, $global:logname)

try {
    $dc = [System.DirectoryServices.ActiveDirectory.Domain]::GetCurrentDomain().RidRoleOwner.Name
} 
catch {([Exception])
	if ($_.Exception.InnerException) { $msg = $($_.Exception.InnerException.Message) } else { $msg = $($_.Exception.Message) }  	
	Write-EventLog $global:logName -Source $global:logSourceName -EventId 400 -Message "Error retrieving RidRoleOwner Domain-Controller from Active-Directory: $msg " -EntryType Error                  
    Exit
}

$filesToProcess = Get-ChildItem $workingPath | Where-Object { ( $_.Name -like "*HospisPersonUseCase*_pshjob_.csv") } | Sort-Object LastWriteTime

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
            $($workingFileEntry.PersId) -ne $null -and 
            #$($workingFileEntry.AdObjectName) -ne $null -and
            $($workingFileEntry.DisplayName) -ne $null -and
            #$($workingFileEntry.RefUserId) -ne $null -and 
            #$($workingFileEntry.RefUserDomain) -ne $null -and 
            #$($workingFileEntry.LocationName) -ne $null -and 
            $($workingFileEntry.MigrateUser) -ne $null -and 
            $($workingFileEntry.CurrentUserName) -ne $null -and 
            $($workingFileEntry.CurrentUserDomainName) -ne $null -and 
            $($workingFileEntry.CurrentUserEMailAddress)-ne $null) {

            $msg = $null
            $htmlBody  = $null
            $htmlBody = "<p style=""Color:Black;font-weight:normal;Font-Size:smaller;font-family:Tahoma"">"
            $htmlBody += "Lieber Mitarbeiter, <br/><br/>"
            
            $errorMsg = $null

            if ($($workingFileEntry.ActionType) -eq [UseCaseType]::Erstellen) {
                $sql = "EXEC KSBL_Hospis_Staging.dbo.usp_create_erstellen_transaction '$($workingFileEntry.PersId)','$($workingFileEntry.RefUserId)','$($workingFileEntry.RefUserDomain)','$($workingFileEntry.CurrentUserDomainName)\$($workingFileEntry.CurrentUserName)','D:\IAM\Archive\$($jobToProcess.Name)'"
                $errorMsg = Write-SQL $sql
            }

            if ($($workingFileEntry.ActionType) -eq [UseCaseType]::Aktivieren ) {
                $sql = "EXEC KSBL_Hospis_Staging.dbo.usp_create_aktivieren_transaction '$($workingFileEntry.PersId)','$($workingFileEntry.RefUserId)','$($workingFileEntry.RefUserDomain)','$($workingFileEntry.MigrateUser)','$($workingFileEntry.CurrentUserDomainName)\$($workingFileEntry.CurrentUserName)','D:\IAM\Archive\$($jobToProcess.Name)'"
                $errorMsg = Write-SQL $sql 
            }

            if ($($workingFileEntry.ActionType) -eq [UseCaseType]::Inaktivieren) {
                #$sql = "EXEC KSBL_Hospis_Staging.dbo.usp_create_inaktivieren_transaction '$($workingFileEntry.PersId)','$($workingFileEntry.CurrentUserDomainName)\$($workingFileEntry.CurrentUserName)'"
                $sql = "EXEC KSBL_Hospis_Staging.dbo.usp_create_terminieren_transaction '$($workingFileEntry.PersId)','$($workingFileEntry.CurrentUserDomainName)\$($workingFileEntry.CurrentUserName)','D:\IAM\Archive\$($jobToProcess.Name)'"
                $errorMsg = Write-SQL $sql
            }

            if ($($workingFileEntry.ActionType) -eq [UseCaseType]::Standortwechsel) {
                $sql = "EXEC KSBL_Hospis_Staging.dbo.usp_create_standortwechsel_transaction '$($workingFileEntry.PersId)','$($workingFileEntry.RefUserId)','$($workingFileEntry.RefUserDomain)','$($workingFileEntry.LocationName)','$($workingFileEntry.MigrateUser)','$($workingFileEntry.CurrentUserDomainName)\$($workingFileEntry.CurrentUserName)'"
                $errorMsg = Write-SQL $sql 
            }

            if ($($workingFileEntry.ActionType) -eq [UseCaseType]::UebertrittM2) {
                $sql = "EXEC KSBL_Hospis_Staging.dbo.usp_create_uebertritt_m1_to_m2_transaction '$($workingFileEntry.PersId)','$($workingFileEntry.RefUserId)','$($workingFileEntry.RefUserDomain)','$("D:\IAM\Archive\$($jobToProcess.Name)")','$($workingFileEntry.CurrentUserDomainName)\$($workingFileEntry.CurrentUserName)'"
                $errorMsg = Write-SQL $sql
            }
            
            if ($($workingFileEntry.ActionType) -eq [UseCaseType]::UebertrittM1) {
                $sql = "EXEC KSBL_Hospis_Staging.dbo.usp_create_uebertritt_m2_to_m1_transaction '$($workingFileEntry.PersId)','$($workingFileEntry.RefUserId)','$($workingFileEntry.RefUserDomain)','$("D:\IAM\Archive\$($jobToProcess.Name)")','$($workingFileEntry.CurrentUserDomainName)\$($workingFileEntry.CurrentUserName)'"
                $errorMsg = Write-SQL $sql
            }
            
            if ($errorMsg -eq "Success") {
                $htmlBody += "Die Hospis Active-Directory Transaktion $($workingFileEntry.ActionType) für <b> $($workingFileEntry.DisplayName) </b> wurde erfolgreich übermittelt und wird in den nachsten 30 Minuten ausgeführt. Nach dem Abschluss erhalten Sie im Postfach GMB-KSBL-Hospis-AD-Import-Helpdesk eine entsprechende E-Mail mit den Details.<br/><br/>"                
            } else {
    	        Write-EventLog $global:logName -Source $global:logSourceName -EventId 4000 -Message "Failed submitting Job for $($workingFileEntry.PersId) ($($workingFileEntry.DisplayName)) into SQL: $msg " -EntryType Error                          	
                $htmlBody += "Während dem übermitteln der Hospis Active-Directory Transaktion $($workingFileEntry.ActionType) für <b> $($workingFileEntry.DisplayName) </b> ist folgender Fehler aufgetreten: <b> $($errorMsg) </b><br/><br/>"                                 
            }
                                       
            $htmlBody += "Viele Grüsse vom E-Mail Team</p>"                        
            Send-EMail -smtpHost $smtpHost -mailFrom $mailFrom -mailTo $($workingFileEntry.CurrentUserEMailAddress) -mailCc $mailCc -mailSubject "*** Auftrag - Hospis Person mit Benutzerkonto Erstellen, Aktivieren oder Terminieren ***" -mailBody $htmlBody -attachment $null


        }
    }

    if ($Host.Name -eq "ConsoleHost") {
        Stop-Transcript
    }


    Move-Item $($jobToProcess.FullName) "D:\IAM\Archive\$($jobToProcess.Name)" -Force -Confirm:$false

}



#endregion
