# Legacy Variable Migration Report

Diese Version migriert die produktiven Werte aus den Legacy-Skripten in die aktive JSON-Konfiguration der modularen MailboxAutomation.

## Konfiguration

Geänderte JSON-Dateien:

- config/appsettings.json
- config/environments.hybrid.json
- config/environments.onprem.json

Wichtige Zielwerte:

- HomeDirectory.NamespaceRoot = \\ksbl.local\HomeDrives
- HomeDirectory.DefaultHomeDrive = Z:
- HomeDirectory.ApplicationDirectoryShare = \\sv00213\Appdata$
- HomeDirectory.DesktopDirectoryShare = \\sv00213\desktop$
- HomeDirectory.UserProfileDirectoryShares = \\sv00701\UserProfiles$, \\sv00702\UserProfiles$
- ActiveDirectory.InternalUserOu = OU=Internal,OU=_Users,DC=ksbl,DC=local
- ActiveDirectory.ExternalUserOu = OU=External,OU=_Users,DC=ksbl,DC=local
- ActiveDirectory.ServiceUserOu = OU=ServiceAccounts,OU=_Users,DC=ksbl,DC=local
- ActiveDirectory.ManagedServiceUserOu = CN=Managed Service Accounts,DC=ksbl,DC=local
- ActiveDirectory.AdminUserOu = OU=Admins,OU=_Users,DC=ksbl,DC=local
- ActiveDirectory.GenericUserOu = OU=Generics,OU=_Users,DC=ksbl,DC=local
- EventLog.LogName = KSBL Helpdesk GUI
- EventLog.Source = Process-PersonMailbox
- ExchangeOnPrem.PrimaryMailDomain = ksbl.ch
- ExchangeOnPrem.CloudDomain = kantonsspitalbl.mail.onmicrosoft.com
- ExchangeOnPrem.RemotePowerShell.ConnectionUri = http://sv01250.ksbl.local/PowerShell
- ExchangeOnPrem.MailboxDatabaseLdapFilter wurde aus der Legacy-Logik übernommen
- PersonMailbox.UpnDomainName = ksbl.ch
- PersonMailbox.ScheduledTaskName = Hospis Sync to Active Directory
- PersonMailbox.PrincipalsAllowedToRetrieveManagedPassword = LG-ADS_GMSA_Domain_Servers
- Hospis.SqlServerInstance = SV02037.ksbl.local
- Hospis.Database = KSBL_IAM
- Hospis.AustrittOOOInternalMessage und AustrittOOOExternalMessage wurden übernommen

## Code-Anpassungen

Geänderte PowerShell-Module:

- shared/PersonMailboxService.psm1
- shared/UserProvisioningService.psm1
- shared/GroupMailboxService.psm1

Umgesetzte Anpassungen:

- PersonMailbox.CreateNonStandard kann Ziel-OU und Ziel-UPN-Domain nun aus ActiveDirectory und PersonMailbox Config ableiten, wenn CSV-Felder leer sind.
- PersonMailbox-Plan enthält nun ScheduledTaskName, PrincipalsAllowedToRetrieveManagedPassword, CloudDomain und UserProfileDirectoryShares aus der Config.
- Mailbox-Datenbanken können über ExchangeOnPrem.DefaultMailboxDatabases oder dynamisch über ExchangeOnPrem.ExchangeAdministrativeGroupDnTemplate und ExchangeOnPrem.MailboxDatabaseLdapFilter ermittelt werden.
- GenericUser.CreateMultiFunction verwendet nun bevorzugt ActiveDirectory.GenericUserOu und liest HomeDirectory-/Application-/Desktop-Werte aus der zentralen HomeDirectory Config.
- GroupMailbox.Create kann ebenfalls die dynamische Mailboxdatenbank-Ermittlung über die migrierte ExchangeOnPrem Config verwenden.

## Tests

Ergänzt:

- tests/Pester/PersonMailboxCreateMigration.Tests.ps1

Neuer Test:

- Ziel-OU und TargetDomain werden aus der migrierten Config aufgelöst, wenn CSV-Werte fehlen.

## Validierung in dieser Umgebung

Durchgeführt:

- JSON-Parsing für appsettings.json, environments.hybrid.json und environments.onprem.json erfolgreich.
- Statische Prüfung auf Merge-Konfliktmarker ohne Treffer.

Nicht durchgeführt:

- Invoke-Pester, weil in dieser Ausführungsumgebung kein PowerShell Runtime verfügbar ist.
