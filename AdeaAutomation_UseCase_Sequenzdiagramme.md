# AdeaAutomation / MailboxAutomation - Mermaid Sequenzdiagramme je UseCase

Diese Datei beschreibt für jeden aktiven UseCase, wo der UseCase im Code beginnt, welche zentralen Skripte, Handler, Services und Gateways durchlaufen werden und wo der UseCase im Datei-Lifecycle endet.

Die Diagramme basieren auf der aktuellen Projektstruktur mit `Invoke-JobProcessor.ps1`, `JobEngine.psm1`, `JobFileQueue.psm1`, `usecases.json`, den UseCase-Handlern, Services und Gateways.

## Gemeinsame Laufzeitlogik

Alle nicht-longRunning UseCases folgen demselben technischen Rahmen: Datei in `queues/incoming` oder fällige Datei in `retry`, Registry-Matching über `config/usecases.json`, Claim nach `processing`, CSV-Import, Context-Erstellung, Handler-Aufruf, Service-Aufruf, Gateway-Aufruf, `JobResult`, danach `Move-JobFileToStatus(done|failed|retry|paused)`.

### DistributionGroup.AddResponsibles

Pattern: `*AddDistributionListResponsibles*_pshjob_.csv`  
Queue: `standard`  
Start im Code: `config/usecases.json` -> `usecases/DistributionGroup/AddDistributionListResponsibles.psm1` -> `Invoke-AddDistributionListResponsibles`  
Ende im Code: `JobFileQueue.Move-JobFileToStatus()` -> `done bei Succeeded, failed bei New-JobFailedResult`

```mermaid
sequenceDiagram
    autonumber
    participant Job as CSV-Jobdatei<br/>*AddDistributionListResponsibles*_pshjob_.csv
    participant Runner as Invoke-JobProcessor.ps1
    participant Engine as JobEngine.psm1<br/>Invoke-JobEngine
    participant Queue as JobFileQueue.psm1
    participant Csv as Csv.psm1<br/>Import-JobCsv
    participant Ctx as JobContext.psm1<br/>New-JobContext
    participant Handler as AddDistributionListResponsibles.psm1<br/>Invoke-AddDistributionListResponsibles
    participant Val as Validation.psm1<br/>Assert-RequiredCsvFields
    participant Svc as Add-DistributionListResponsibles<br/>$Context.Services.DistributionGroup.AddResponsibles
    participant Gw as ExchangeOnPremGateway.psm1 + DistributionGroupService helper
    participant Result as JobResult.psm1

    Job->>Runner: Datei liegt in queues/incoming<br/>oder fällig in retry/paused
    Runner->>Engine: Invoke-JobEngine -Queue standard
    Engine->>Queue: Find-UseCaseJobFiles(pattern)
    Queue-->>Engine: passende Jobdatei
    Engine->>Queue: Claim-JobFile(UseCaseName, Queue)
    Queue-->>Engine: WorkingFile + JobId + StableJobKey + Metadata
    Engine->>Csv: Import-JobCsv(WorkingFile)
    Csv-->>Engine: Payload rows
    Engine->>Ctx: New-JobContext(... Services, Logger, WhatIfMode ...)
    Engine->>Handler: Invoke-AddDistributionListResponsibles(Context)
    Handler->>Val: Pflichtfelder validieren
    loop pro CSV-Zeile
        Handler->>Svc: Service-Aufruf mit Context + Row
        Svc->>Gw: Get-OnPremDistributionGroupSafe<br/>Set-OnPremDistributionGroupSafe ManagedBy Add/Remove<br/>Add/Remove-OnPremAdPermissionSafe für WriteMembers
        Gw-->>Svc: Ergebnis / simuliertes WhatIf-Ergebnis
        Svc-->>Handler: Success/Changed/Message/ErrorCode
    end
    alt alle Zeilen erfolgreich
        Handler->>Result: New-JobSucceededResult
        Handler-->>Engine: Status = Succeeded
        Engine->>Queue: Move-JobFileToStatus(done)
    else mindestens eine Zeile fehlerhaft
        Handler->>Result: New-JobFailedResult
        Handler-->>Engine: Status = Failed
        Engine->>Queue: Move-JobFileToStatus(failed)
    end
```

### DistributionGroup.Create

Pattern: `*CreateDistributionList*_pshjob_.csv`  
Queue: `standard`  
Start im Code: `config/usecases.json` -> `usecases/DistributionGroup/CreateDistributionGroup.psm1` -> `Invoke-CreateDistributionGroup`  
Ende im Code: `JobFileQueue.Move-JobFileToStatus()` -> `done bei Succeeded, failed bei New-JobFailedResult`

```mermaid
sequenceDiagram
    autonumber
    participant Job as CSV-Jobdatei<br/>*CreateDistributionList*_pshjob_.csv
    participant Runner as Invoke-JobProcessor.ps1
    participant Engine as JobEngine.psm1<br/>Invoke-JobEngine
    participant Queue as JobFileQueue.psm1
    participant Csv as Csv.psm1<br/>Import-JobCsv
    participant Ctx as JobContext.psm1<br/>New-JobContext
    participant Handler as CreateDistributionGroup.psm1<br/>Invoke-CreateDistributionGroup
    participant Val as Validation.psm1<br/>Assert-RequiredCsvFields
    participant Svc as New-DistributionGroupFromRequest<br/>$Context.Services.DistributionGroup.Create
    participant Gw as ExchangeOnPremGateway.psm1 + ActiveDirectoryGateway.psm1
    participant Result as JobResult.psm1

    Job->>Runner: Datei liegt in queues/incoming<br/>oder fällig in retry/paused
    Runner->>Engine: Invoke-JobEngine -Queue standard
    Engine->>Queue: Find-UseCaseJobFiles(pattern)
    Queue-->>Engine: passende Jobdatei
    Engine->>Queue: Claim-JobFile(UseCaseName, Queue)
    Queue-->>Engine: WorkingFile + JobId + StableJobKey + Metadata
    Engine->>Csv: Import-JobCsv(WorkingFile)
    Csv-->>Engine: Payload rows
    Engine->>Ctx: New-JobContext(... Services, Logger, WhatIfMode ...)
    Engine->>Handler: Invoke-CreateDistributionGroup(Context)
    Handler->>Val: Pflichtfelder validieren
    loop pro CSV-Zeile
        Handler->>Svc: Service-Aufruf mit Context + Row
        Svc->>Gw: New-OnPremDistributionGroupSafe<br/>Set-OnPremDistributionGroupSafe HiddenFromAddressListsEnabled<br/>Set-OnPremDistributionGroupSafe ManagedBy<br/>Set-AdGroupSafe Description<br/>Set-OnPremDistributionGroupSafe RequireSenderAuthenticationEnabled<br/>TODO: AcceptMessagesOnlyFromSendersOrMembers / TenantState
        Gw-->>Svc: Ergebnis / simuliertes WhatIf-Ergebnis
        Svc-->>Handler: Success/Changed/Message/ErrorCode
    end
    alt alle Zeilen erfolgreich
        Handler->>Result: New-JobSucceededResult
        Handler-->>Engine: Status = Succeeded
        Engine->>Queue: Move-JobFileToStatus(done)
    else mindestens eine Zeile fehlerhaft
        Handler->>Result: New-JobFailedResult
        Handler-->>Engine: Status = Failed
        Engine->>Queue: Move-JobFileToStatus(failed)
    end
```

### DistributionGroup.ChangeManager

Pattern: `*ChangeManagerDistribList*_pshjob_.csv`  
Queue: `standard`  
Start im Code: `config/usecases.json` -> `usecases/DistributionGroup/ChangeManagerDistribList.psm1` -> `Invoke-ChangeManagerDistribList`  
Ende im Code: `JobFileQueue.Move-JobFileToStatus()` -> `done bei Succeeded, failed bei New-JobFailedResult`

```mermaid
sequenceDiagram
    autonumber
    participant Job as CSV-Jobdatei<br/>*ChangeManagerDistribList*_pshjob_.csv
    participant Runner as Invoke-JobProcessor.ps1
    participant Engine as JobEngine.psm1<br/>Invoke-JobEngine
    participant Queue as JobFileQueue.psm1
    participant Csv as Csv.psm1<br/>Import-JobCsv
    participant Ctx as JobContext.psm1<br/>New-JobContext
    participant Handler as ChangeManagerDistribList.psm1<br/>Invoke-ChangeManagerDistribList
    participant Val as Validation.psm1<br/>Assert-RequiredCsvFields
    participant Svc as Set-DistributionGroupManager<br/>$Context.Services.DistributionGroup.ChangeManager
    participant Gw as ExchangeOnPremGateway.psm1 + ActiveDirectoryGateway.psm1
    participant Result as JobResult.psm1

    Job->>Runner: Datei liegt in queues/incoming<br/>oder fällig in retry/paused
    Runner->>Engine: Invoke-JobEngine -Queue standard
    Engine->>Queue: Find-UseCaseJobFiles(pattern)
    Queue-->>Engine: passende Jobdatei
    Engine->>Queue: Claim-JobFile(UseCaseName, Queue)
    Queue-->>Engine: WorkingFile + JobId + StableJobKey + Metadata
    Engine->>Csv: Import-JobCsv(WorkingFile)
    Csv-->>Engine: Payload rows
    Engine->>Ctx: New-JobContext(... Services, Logger, WhatIfMode ...)
    Engine->>Handler: Invoke-ChangeManagerDistribList(Context)
    Handler->>Val: Pflichtfelder validieren
    loop pro CSV-Zeile
        Handler->>Svc: Service-Aufruf mit Context + Row
        Svc->>Gw: Get-OnPremDistributionGroupSafe<br/>Set-OnPremDistributionGroupSafe ManagedBy<br/>Set-AdGroupSafe ManagedBy
        Gw-->>Svc: Ergebnis / simuliertes WhatIf-Ergebnis
        Svc-->>Handler: Success/Changed/Message/ErrorCode
    end
    alt alle Zeilen erfolgreich
        Handler->>Result: New-JobSucceededResult
        Handler-->>Engine: Status = Succeeded
        Engine->>Queue: Move-JobFileToStatus(done)
    else mindestens eine Zeile fehlerhaft
        Handler->>Result: New-JobFailedResult
        Handler-->>Engine: Status = Failed
        Engine->>Queue: Move-JobFileToStatus(failed)
    end
```

### DistributionGroup.Delete

Pattern: `*DeleteDistribList*_pshjob_.csv`  
Queue: `standard`  
Start im Code: `config/usecases.json` -> `usecases/DistributionGroup/DeleteDistributionList.psm1` -> `Invoke-DeleteDistributionList`  
Ende im Code: `JobFileQueue.Move-JobFileToStatus()` -> `done bei Succeeded, failed bei New-JobFailedResult`

```mermaid
sequenceDiagram
    autonumber
    participant Job as CSV-Jobdatei<br/>*DeleteDistribList*_pshjob_.csv
    participant Runner as Invoke-JobProcessor.ps1
    participant Engine as JobEngine.psm1<br/>Invoke-JobEngine
    participant Queue as JobFileQueue.psm1
    participant Csv as Csv.psm1<br/>Import-JobCsv
    participant Ctx as JobContext.psm1<br/>New-JobContext
    participant Handler as DeleteDistributionList.psm1<br/>Invoke-DeleteDistributionList
    participant Val as Validation.psm1<br/>Assert-RequiredCsvFields
    participant Svc as Remove-DistributionGroupFromRequest<br/>$Context.Services.DistributionGroup.Delete
    participant Gw as ExchangeOnPremGateway.psm1
    participant Result as JobResult.psm1

    Job->>Runner: Datei liegt in queues/incoming<br/>oder fällig in retry/paused
    Runner->>Engine: Invoke-JobEngine -Queue standard
    Engine->>Queue: Find-UseCaseJobFiles(pattern)
    Queue-->>Engine: passende Jobdatei
    Engine->>Queue: Claim-JobFile(UseCaseName, Queue)
    Queue-->>Engine: WorkingFile + JobId + StableJobKey + Metadata
    Engine->>Csv: Import-JobCsv(WorkingFile)
    Csv-->>Engine: Payload rows
    Engine->>Ctx: New-JobContext(... Services, Logger, WhatIfMode ...)
    Engine->>Handler: Invoke-DeleteDistributionList(Context)
    Handler->>Val: Pflichtfelder validieren
    loop pro CSV-Zeile
        Handler->>Svc: Service-Aufruf mit Context + Row
        Svc->>Gw: Get-OnPremDistributionGroupSafe<br/>Set-OnPremDistributionGroupSafe ManagedBy Service-Account<br/>Remove-OnPremDistributionGroupSafe
        Gw-->>Svc: Ergebnis / simuliertes WhatIf-Ergebnis
        Svc-->>Handler: Success/Changed/Message/ErrorCode
    end
    alt alle Zeilen erfolgreich
        Handler->>Result: New-JobSucceededResult
        Handler-->>Engine: Status = Succeeded
        Engine->>Queue: Move-JobFileToStatus(done)
    else mindestens eine Zeile fehlerhaft
        Handler->>Result: New-JobFailedResult
        Handler-->>Engine: Status = Failed
        Engine->>Queue: Move-JobFileToStatus(failed)
    end
```

### GroupMailbox.AddFmaMembers

Pattern: `*AddGroupMailboxFmaMembers*_pshjob_.csv`  
Queue: `standard`  
Start im Code: `config/usecases.json` -> `usecases/GroupMailbox/AddGroupMailboxFmaMembers.psm1` -> `Invoke-AddGroupMailboxFmaMembers`  
Ende im Code: `JobFileQueue.Move-JobFileToStatus()` -> `done bei Succeeded, failed bei New-JobFailedResult`

```mermaid
sequenceDiagram
    autonumber
    participant Job as CSV-Jobdatei<br/>*AddGroupMailboxFmaMembers*_pshjob_.csv
    participant Runner as Invoke-JobProcessor.ps1
    participant Engine as JobEngine.psm1<br/>Invoke-JobEngine
    participant Queue as JobFileQueue.psm1
    participant Csv as Csv.psm1<br/>Import-JobCsv
    participant Ctx as JobContext.psm1<br/>New-JobContext
    participant Handler as AddGroupMailboxFmaMembers.psm1<br/>Invoke-AddGroupMailboxFmaMembers
    participant Val as Validation.psm1<br/>Assert-RequiredCsvFields
    participant Svc as Add-GroupMailboxFmaMembers<br/>$Context.Services.GroupMailbox.AddFmaMembers
    participant Gw as ExchangeOnPremGateway.psm1
    participant Result as JobResult.psm1

    Job->>Runner: Datei liegt in queues/incoming<br/>oder fällig in retry/paused
    Runner->>Engine: Invoke-JobEngine -Queue standard
    Engine->>Queue: Find-UseCaseJobFiles(pattern)
    Queue-->>Engine: passende Jobdatei
    Engine->>Queue: Claim-JobFile(UseCaseName, Queue)
    Queue-->>Engine: WorkingFile + JobId + StableJobKey + Metadata
    Engine->>Csv: Import-JobCsv(WorkingFile)
    Csv-->>Engine: Payload rows
    Engine->>Ctx: New-JobContext(... Services, Logger, WhatIfMode ...)
    Engine->>Handler: Invoke-AddGroupMailboxFmaMembers(Context)
    Handler->>Val: Pflichtfelder validieren
    loop pro CSV-Zeile
        Handler->>Svc: Service-Aufruf mit Context + Row
        Svc->>Gw: Get-OnPremMailboxSafe<br/>Add/Remove-OnPremMailboxPermissionSafe FullAccess<br/>Add/Remove-OnPremAdPermissionSafe SendAs, wenn EnableSendAs=True
        Gw-->>Svc: Ergebnis / simuliertes WhatIf-Ergebnis
        Svc-->>Handler: Success/Changed/Message/ErrorCode
    end
    alt alle Zeilen erfolgreich
        Handler->>Result: New-JobSucceededResult
        Handler-->>Engine: Status = Succeeded
        Engine->>Queue: Move-JobFileToStatus(done)
    else mindestens eine Zeile fehlerhaft
        Handler->>Result: New-JobFailedResult
        Handler-->>Engine: Status = Failed
        Engine->>Queue: Move-JobFileToStatus(failed)
    end
```

### GroupMailbox.Create

Pattern: `*CreateGroupMailbox*_pshjob_.csv`  
Queue: `standard`  
Start im Code: `config/usecases.json` -> `usecases/GroupMailbox/CreateGroupMailbox.psm1` -> `Invoke-CreateGroupMailbox`  
Ende im Code: `JobFileQueue.Move-JobFileToStatus()` -> `done bei Succeeded, failed bei New-JobFailedResult`

```mermaid
sequenceDiagram
    autonumber
    participant Job as CSV-Jobdatei<br/>*CreateGroupMailbox*_pshjob_.csv
    participant Runner as Invoke-JobProcessor.ps1
    participant Engine as JobEngine.psm1<br/>Invoke-JobEngine
    participant Queue as JobFileQueue.psm1
    participant Csv as Csv.psm1<br/>Import-JobCsv
    participant Ctx as JobContext.psm1<br/>New-JobContext
    participant Handler as CreateGroupMailbox.psm1<br/>Invoke-CreateGroupMailbox
    participant Val as Validation.psm1<br/>Assert-RequiredCsvFields
    participant Svc as New-GroupMailbox<br/>$Context.Services.GroupMailbox.Create
    participant Gw as ExchangeOnPremGateway.psm1 + ActiveDirectoryGateway.psm1
    participant Result as JobResult.psm1

    Job->>Runner: Datei liegt in queues/incoming<br/>oder fällig in retry/paused
    Runner->>Engine: Invoke-JobEngine -Queue standard
    Engine->>Queue: Find-UseCaseJobFiles(pattern)
    Queue-->>Engine: passende Jobdatei
    Engine->>Queue: Claim-JobFile(UseCaseName, Queue)
    Queue-->>Engine: WorkingFile + JobId + StableJobKey + Metadata
    Engine->>Csv: Import-JobCsv(WorkingFile)
    Csv-->>Engine: Payload rows
    Engine->>Ctx: New-JobContext(... Services, Logger, WhatIfMode ...)
    Engine->>Handler: Invoke-CreateGroupMailbox(Context)
    Handler->>Val: Pflichtfelder validieren
    loop pro CSV-Zeile
        Handler->>Svc: Service-Aufruf mit Context + Row
        Svc->>Gw: Get-OnPremMailboxSafe Existenzprüfung<br/>New-OnPremMailboxSafe Shared Mailbox<br/>Set-OnPremMailboxJunkEmailConfigurationSafe<br/>Set-OnPremMailboxSafe Hidden/PrimarySMTP<br/>Set-AdUserSafe Description/Manager/employeeType<br/>Add/Remove Permissions via Invoke-LegacyMailboxPermissionMutation<br/>Add-AdGroupMemberSafe GG-EV-Users<br/>TODO: TenantState
        Gw-->>Svc: Ergebnis / simuliertes WhatIf-Ergebnis
        Svc-->>Handler: Success/Changed/Message/ErrorCode
    end
    alt alle Zeilen erfolgreich
        Handler->>Result: New-JobSucceededResult
        Handler-->>Engine: Status = Succeeded
        Engine->>Queue: Move-JobFileToStatus(done)
    else mindestens eine Zeile fehlerhaft
        Handler->>Result: New-JobFailedResult
        Handler-->>Engine: Status = Failed
        Engine->>Queue: Move-JobFileToStatus(failed)
    end
```

### GroupMailbox.ChangeManager

Pattern: `*ChangeManagerGroupMailbox*_pshjob_.csv`  
Queue: `standard`  
Start im Code: `config/usecases.json` -> `usecases/GroupMailbox/ChangeManagerGroupMailbox.psm1` -> `Invoke-ChangeManagerGroupMailbox`  
Ende im Code: `JobFileQueue.Move-JobFileToStatus()` -> `done bei Succeeded, failed bei New-JobFailedResult`

```mermaid
sequenceDiagram
    autonumber
    participant Job as CSV-Jobdatei<br/>*ChangeManagerGroupMailbox*_pshjob_.csv
    participant Runner as Invoke-JobProcessor.ps1
    participant Engine as JobEngine.psm1<br/>Invoke-JobEngine
    participant Queue as JobFileQueue.psm1
    participant Csv as Csv.psm1<br/>Import-JobCsv
    participant Ctx as JobContext.psm1<br/>New-JobContext
    participant Handler as ChangeManagerGroupMailbox.psm1<br/>Invoke-ChangeManagerGroupMailbox
    participant Val as Validation.psm1<br/>Assert-RequiredCsvFields
    participant Svc as Set-GroupMailboxManager<br/>$Context.Services.GroupMailbox.ChangeManager
    participant Gw as ExchangeOnPremGateway.psm1 + ActiveDirectoryGateway.psm1
    participant Result as JobResult.psm1

    Job->>Runner: Datei liegt in queues/incoming<br/>oder fällig in retry/paused
    Runner->>Engine: Invoke-JobEngine -Queue standard
    Engine->>Queue: Find-UseCaseJobFiles(pattern)
    Queue-->>Engine: passende Jobdatei
    Engine->>Queue: Claim-JobFile(UseCaseName, Queue)
    Queue-->>Engine: WorkingFile + JobId + StableJobKey + Metadata
    Engine->>Csv: Import-JobCsv(WorkingFile)
    Csv-->>Engine: Payload rows
    Engine->>Ctx: New-JobContext(... Services, Logger, WhatIfMode ...)
    Engine->>Handler: Invoke-ChangeManagerGroupMailbox(Context)
    Handler->>Val: Pflichtfelder validieren
    loop pro CSV-Zeile
        Handler->>Svc: Service-Aufruf mit Context + Row
        Svc->>Gw: Get-OnPremMailboxSafe<br/>Add-OnPremMailboxPermissionSafe FullAccess<br/>Add-OnPremAdPermissionSafe SendAs<br/>Set-AdUserSafe Manager
        Gw-->>Svc: Ergebnis / simuliertes WhatIf-Ergebnis
        Svc-->>Handler: Success/Changed/Message/ErrorCode
    end
    alt alle Zeilen erfolgreich
        Handler->>Result: New-JobSucceededResult
        Handler-->>Engine: Status = Succeeded
        Engine->>Queue: Move-JobFileToStatus(done)
    else mindestens eine Zeile fehlerhaft
        Handler->>Result: New-JobFailedResult
        Handler-->>Engine: Status = Failed
        Engine->>Queue: Move-JobFileToStatus(failed)
    end
```

### GenericUser.RenameAccount

Pattern: `*RenameUserAccount*_pshjob_.csv`  
Queue: `standard`  
Start im Code: `config/usecases.json` -> `usecases/GenericUser/RenameUserAccount.psm1` -> `Invoke-RenameUserAccount`  
Ende im Code: `JobFileQueue.Move-JobFileToStatus()` -> `done bei Succeeded, failed bei New-JobFailedResult / PARTIAL_FAILURE`

```mermaid
sequenceDiagram
    autonumber
    participant Job as CSV-Jobdatei<br/>*RenameUserAccount*_pshjob_.csv
    participant Runner as Invoke-JobProcessor.ps1
    participant Engine as JobEngine.psm1<br/>Invoke-JobEngine
    participant Queue as JobFileQueue.psm1
    participant Csv as Csv.psm1<br/>Import-JobCsv
    participant Ctx as JobContext.psm1<br/>New-JobContext
    participant Handler as RenameUserAccount.psm1<br/>Invoke-RenameUserAccount
    participant Val as Validation.psm1<br/>Assert-RequiredCsvFields
    participant Svc as Rename-GenericUser<br/>$Context.Services.UserProvisioning.RenameUser
    participant Gw as ActiveDirectoryGateway.psm1 + ExchangeOnPremGateway.psm1
    participant Result as JobResult.psm1

    Job->>Runner: Datei liegt in queues/incoming<br/>oder fällig in retry/paused
    Runner->>Engine: Invoke-JobEngine -Queue standard
    Engine->>Queue: Find-UseCaseJobFiles(pattern)
    Queue-->>Engine: passende Jobdatei
    Engine->>Queue: Claim-JobFile(UseCaseName, Queue)
    Queue-->>Engine: WorkingFile + JobId + StableJobKey + Metadata
    Engine->>Csv: Import-JobCsv(WorkingFile)
    Csv-->>Engine: Payload rows
    Engine->>Ctx: New-JobContext(... Services, Logger, WhatIfMode ...)
    Engine->>Handler: Invoke-RenameUserAccount(Context)
    Handler->>Val: Pflichtfelder validieren
    loop pro CSV-Zeile
        Handler->>Svc: Service-Aufruf mit Context + Row
        Svc->>Gw: Get-AdUserBySamAccountNameSafe<br/>Rename-AdObjectSafe<br/>Set-AdUserSafe Names/Mail/UPN/SAM<br/>Set-OnPremMailboxSafe PrimarySmtpAddress / Policy
        Gw-->>Svc: Ergebnis / simuliertes WhatIf-Ergebnis
        Svc-->>Handler: Success/Changed/Message/ErrorCode
    end
    alt alle Zeilen erfolgreich
        Handler->>Result: New-JobSucceededResult
        Handler-->>Engine: Status = Succeeded
        Engine->>Queue: Move-JobFileToStatus(done)
    else mindestens eine Zeile fehlerhaft
        Handler->>Result: New-JobFailedResult
        Handler-->>Engine: Status = Failed
        Engine->>Queue: Move-JobFileToStatus(failed)
    end
```

### GenericUser.ChangeSurname

Pattern: `*ChangeAccountSurname*_pshjob_.csv`  
Queue: `standard`  
Start im Code: `config/usecases.json` -> `usecases/GenericUser/ChangeAccountSurname.psm1` -> `Invoke-ChangeAccountSurname`  
Ende im Code: `JobFileQueue.Move-JobFileToStatus()` -> `done bei Succeeded, failed bei New-JobFailedResult / PARTIAL_FAILURE`

```mermaid
sequenceDiagram
    autonumber
    participant Job as CSV-Jobdatei<br/>*ChangeAccountSurname*_pshjob_.csv
    participant Runner as Invoke-JobProcessor.ps1
    participant Engine as JobEngine.psm1<br/>Invoke-JobEngine
    participant Queue as JobFileQueue.psm1
    participant Csv as Csv.psm1<br/>Import-JobCsv
    participant Ctx as JobContext.psm1<br/>New-JobContext
    participant Handler as ChangeAccountSurname.psm1<br/>Invoke-ChangeAccountSurname
    participant Val as Validation.psm1<br/>Assert-RequiredCsvFields
    participant Svc as Set-GenericUserSurname<br/>$Context.Services.UserProvisioning.SetSurname
    participant Gw as ActiveDirectoryGateway.psm1 + ExchangeOnPremGateway.psm1
    participant Result as JobResult.psm1

    Job->>Runner: Datei liegt in queues/incoming<br/>oder fällig in retry/paused
    Runner->>Engine: Invoke-JobEngine -Queue standard
    Engine->>Queue: Find-UseCaseJobFiles(pattern)
    Queue-->>Engine: passende Jobdatei
    Engine->>Queue: Claim-JobFile(UseCaseName, Queue)
    Queue-->>Engine: WorkingFile + JobId + StableJobKey + Metadata
    Engine->>Csv: Import-JobCsv(WorkingFile)
    Csv-->>Engine: Payload rows
    Engine->>Ctx: New-JobContext(... Services, Logger, WhatIfMode ...)
    Engine->>Handler: Invoke-ChangeAccountSurname(Context)
    Handler->>Val: Pflichtfelder validieren
    loop pro CSV-Zeile
        Handler->>Svc: Service-Aufruf mit Context + Row
        Svc->>Gw: Get-AdUserBySamAccountNameSafe<br/>Set-AdUserSafe GivenName/Surname/DisplayName/Mail<br/>Set-OnPremMailboxSafe PrimarySmtpAddress / Policy
        Gw-->>Svc: Ergebnis / simuliertes WhatIf-Ergebnis
        Svc-->>Handler: Success/Changed/Message/ErrorCode
    end
    alt alle Zeilen erfolgreich
        Handler->>Result: New-JobSucceededResult
        Handler-->>Engine: Status = Succeeded
        Engine->>Queue: Move-JobFileToStatus(done)
    else mindestens eine Zeile fehlerhaft
        Handler->>Result: New-JobFailedResult
        Handler-->>Engine: Status = Failed
        Engine->>Queue: Move-JobFileToStatus(failed)
    end
```

### GenericUser.Enable

Pattern: `*EnableNonStdPersonMailbox*_pshjob_.csv`  
Queue: `standard`  
Start im Code: `config/usecases.json` -> `usecases/GenericUser/EnableGenericUser.psm1` -> `Invoke-EnableGenericUser`  
Ende im Code: `JobFileQueue.Move-JobFileToStatus()` -> `done bei Succeeded, failed bei New-JobFailedResult`

```mermaid
sequenceDiagram
    autonumber
    participant Job as CSV-Jobdatei<br/>*EnableNonStdPersonMailbox*_pshjob_.csv
    participant Runner as Invoke-JobProcessor.ps1
    participant Engine as JobEngine.psm1<br/>Invoke-JobEngine
    participant Queue as JobFileQueue.psm1
    participant Csv as Csv.psm1<br/>Import-JobCsv
    participant Ctx as JobContext.psm1<br/>New-JobContext
    participant Handler as EnableGenericUser.psm1<br/>Invoke-EnableGenericUser
    participant Val as Validation.psm1<br/>Assert-RequiredCsvFields
    participant Svc as Enable-GenericUser<br/>$Context.Services.UserProvisioning.EnableUser
    participant Gw as ActiveDirectoryGateway.psm1 + MailboxFeatureService.psm1 + DfsGateway.psm1
    participant Result as JobResult.psm1

    Job->>Runner: Datei liegt in queues/incoming<br/>oder fällig in retry/paused
    Runner->>Engine: Invoke-JobEngine -Queue standard
    Engine->>Queue: Find-UseCaseJobFiles(pattern)
    Queue-->>Engine: passende Jobdatei
    Engine->>Queue: Claim-JobFile(UseCaseName, Queue)
    Queue-->>Engine: WorkingFile + JobId + StableJobKey + Metadata
    Engine->>Csv: Import-JobCsv(WorkingFile)
    Csv-->>Engine: Payload rows
    Engine->>Ctx: New-JobContext(... Services, Logger, WhatIfMode ...)
    Engine->>Handler: Invoke-EnableGenericUser(Context)
    Handler->>Val: Pflichtfelder validieren
    loop pro CSV-Zeile
        Handler->>Svc: Service-Aufruf mit Context + Row
        Svc->>Gw: Get-AdUserBySamAccountNameSafe<br/>Set-AdAccountPasswordSafe<br/>Enable-AdAccountSafe<br/>Set-AdUserSafe ChangePasswordAtLogon/Description/Clear extensionAttribute11<br/>Set-MailboxVisibility Unhide<br/>Update-DfsShareSettingsSafe<br/>Move-AdObjectSafe optional
        Gw-->>Svc: Ergebnis / simuliertes WhatIf-Ergebnis
        Svc-->>Handler: Success/Changed/Message/ErrorCode
    end
    alt alle Zeilen erfolgreich
        Handler->>Result: New-JobSucceededResult
        Handler-->>Engine: Status = Succeeded
        Engine->>Queue: Move-JobFileToStatus(done)
    else mindestens eine Zeile fehlerhaft
        Handler->>Result: New-JobFailedResult
        Handler-->>Engine: Status = Failed
        Engine->>Queue: Move-JobFileToStatus(failed)
    end
```

### GenericUser.Disable

Pattern: `*DisableNonStdPersonMailbox*_pshjob_.csv`  
Queue: `standard`  
Start im Code: `config/usecases.json` -> `usecases/GenericUser/DisableGenericUser.psm1` -> `Invoke-DisableGenericUser`  
Ende im Code: `JobFileQueue.Move-JobFileToStatus()` -> `done bei Succeeded, failed bei New-JobFailedResult`

```mermaid
sequenceDiagram
    autonumber
    participant Job as CSV-Jobdatei<br/>*DisableNonStdPersonMailbox*_pshjob_.csv
    participant Runner as Invoke-JobProcessor.ps1
    participant Engine as JobEngine.psm1<br/>Invoke-JobEngine
    participant Queue as JobFileQueue.psm1
    participant Csv as Csv.psm1<br/>Import-JobCsv
    participant Ctx as JobContext.psm1<br/>New-JobContext
    participant Handler as DisableGenericUser.psm1<br/>Invoke-DisableGenericUser
    participant Val as Validation.psm1<br/>Assert-RequiredCsvFields
    participant Svc as Disable-GenericUser<br/>$Context.Services.UserProvisioning.DisableUser
    participant Gw as ActiveDirectoryGateway.psm1 + MailboxFeatureService.psm1
    participant Result as JobResult.psm1

    Job->>Runner: Datei liegt in queues/incoming<br/>oder fällig in retry/paused
    Runner->>Engine: Invoke-JobEngine -Queue standard
    Engine->>Queue: Find-UseCaseJobFiles(pattern)
    Queue-->>Engine: passende Jobdatei
    Engine->>Queue: Claim-JobFile(UseCaseName, Queue)
    Queue-->>Engine: WorkingFile + JobId + StableJobKey + Metadata
    Engine->>Csv: Import-JobCsv(WorkingFile)
    Csv-->>Engine: Payload rows
    Engine->>Ctx: New-JobContext(... Services, Logger, WhatIfMode ...)
    Engine->>Handler: Invoke-DisableGenericUser(Context)
    Handler->>Val: Pflichtfelder validieren
    loop pro CSV-Zeile
        Handler->>Svc: Service-Aufruf mit Context + Row
        Svc->>Gw: Get-AdUserBySamAccountNameSafe<br/>Disable-AdAccountSafe<br/>Set-AdUserSafe Description<br/>TODO: Set-TenantState TenantDisable<br/>Set-MailboxVisibility Hide
        Gw-->>Svc: Ergebnis / simuliertes WhatIf-Ergebnis
        Svc-->>Handler: Success/Changed/Message/ErrorCode
    end
    alt alle Zeilen erfolgreich
        Handler->>Result: New-JobSucceededResult
        Handler-->>Engine: Status = Succeeded
        Engine->>Queue: Move-JobFileToStatus(done)
    else mindestens eine Zeile fehlerhaft
        Handler->>Result: New-JobFailedResult
        Handler-->>Engine: Status = Failed
        Engine->>Queue: Move-JobFileToStatus(failed)
    end
```

### GenericUser.AddEmailNickname

Pattern: `*AddEMailNickName*_pshjob_.csv`  
Queue: `standard`  
Start im Code: `config/usecases.json` -> `usecases/GenericUser/AddEmailNickname.psm1` -> `Invoke-AddEmailNickname`  
Ende im Code: `JobFileQueue.Move-JobFileToStatus()` -> `done bei Succeeded, failed bei New-JobFailedResult`

```mermaid
sequenceDiagram
    autonumber
    participant Job as CSV-Jobdatei<br/>*AddEMailNickName*_pshjob_.csv
    participant Runner as Invoke-JobProcessor.ps1
    participant Engine as JobEngine.psm1<br/>Invoke-JobEngine
    participant Queue as JobFileQueue.psm1
    participant Csv as Csv.psm1<br/>Import-JobCsv
    participant Ctx as JobContext.psm1<br/>New-JobContext
    participant Handler as AddEmailNickname.psm1<br/>Invoke-AddEmailNickname
    participant Val as Validation.psm1<br/>Assert-RequiredCsvFields
    participant Svc as Add-GenericUserEmailNickname<br/>$Context.Services.UserProvisioning.AddEmailNickname
    participant Gw as ExchangeOnPremGateway.psm1
    participant Result as JobResult.psm1

    Job->>Runner: Datei liegt in queues/incoming<br/>oder fällig in retry/paused
    Runner->>Engine: Invoke-JobEngine -Queue standard
    Engine->>Queue: Find-UseCaseJobFiles(pattern)
    Queue-->>Engine: passende Jobdatei
    Engine->>Queue: Claim-JobFile(UseCaseName, Queue)
    Queue-->>Engine: WorkingFile + JobId + StableJobKey + Metadata
    Engine->>Csv: Import-JobCsv(WorkingFile)
    Csv-->>Engine: Payload rows
    Engine->>Ctx: New-JobContext(... Services, Logger, WhatIfMode ...)
    Engine->>Handler: Invoke-AddEmailNickname(Context)
    Handler->>Val: Pflichtfelder validieren
    loop pro CSV-Zeile
        Handler->>Svc: Service-Aufruf mit Context + Row
        Svc->>Gw: Get-OnPremMailboxSafe<br/>Set-OnPremMailboxSafe PrimarySmtpAddress / EmailAddressPolicyEnabled=false
        Gw-->>Svc: Ergebnis / simuliertes WhatIf-Ergebnis
        Svc-->>Handler: Success/Changed/Message/ErrorCode
    end
    alt alle Zeilen erfolgreich
        Handler->>Result: New-JobSucceededResult
        Handler-->>Engine: Status = Succeeded
        Engine->>Queue: Move-JobFileToStatus(done)
    else mindestens eine Zeile fehlerhaft
        Handler->>Result: New-JobFailedResult
        Handler-->>Engine: Status = Failed
        Engine->>Queue: Move-JobFileToStatus(failed)
    end
```

### GenericUser.CreateMultiFunction

Pattern: `*CreateMultiFunctionGenericUser*_pshjob_.csv`  
Queue: `standard`  
Start im Code: `config/usecases.json` -> `usecases/GenericUser/CreateMultiFunctionGenericUser.psm1` -> `Invoke-CreateMultiFunctionGenericUser`  
Ende im Code: `JobFileQueue.Move-JobFileToStatus()` -> `done bei Succeeded, failed bei New-JobFailedResult`

```mermaid
sequenceDiagram
    autonumber
    participant Job as CSV-Jobdatei<br/>*CreateMultiFunctionGenericUser*_pshjob_.csv
    participant Runner as Invoke-JobProcessor.ps1
    participant Engine as JobEngine.psm1<br/>Invoke-JobEngine
    participant Queue as JobFileQueue.psm1
    participant Csv as Csv.psm1<br/>Import-JobCsv
    participant Ctx as JobContext.psm1<br/>New-JobContext
    participant Handler as CreateMultiFunctionGenericUser.psm1<br/>Invoke-CreateMultiFunctionGenericUser
    participant Val as Validation.psm1<br/>Assert-RequiredCsvFields
    participant Svc as New-GenericUser<br/>$Context.Services.UserProvisioning.NewUser
    participant Gw as ActiveDirectoryGateway.psm1 + UserHomeDirectoryService/DfsGateway TODO
    participant Result as JobResult.psm1

    Job->>Runner: Datei liegt in queues/incoming<br/>oder fällig in retry/paused
    Runner->>Engine: Invoke-JobEngine -Queue standard
    Engine->>Queue: Find-UseCaseJobFiles(pattern)
    Queue-->>Engine: passende Jobdatei
    Engine->>Queue: Claim-JobFile(UseCaseName, Queue)
    Queue-->>Engine: WorkingFile + JobId + StableJobKey + Metadata
    Engine->>Csv: Import-JobCsv(WorkingFile)
    Csv-->>Engine: Payload rows
    Engine->>Ctx: New-JobContext(... Services, Logger, WhatIfMode ...)
    Engine->>Handler: Invoke-CreateMultiFunctionGenericUser(Context)
    Handler->>Val: Pflichtfelder validieren
    loop pro CSV-Zeile
        Handler->>Svc: Service-Aufruf mit Context + Row
        Svc->>Gw: Get-AdUserBySamAccountNameSafe Existenzprüfung<br/>New-AdUserSafe<br/>Set-AdUserSafe Manager/employeeType/Description/HomeDirectory/HomeDrive/kisAccountName<br/>TODO: HomeDrive/DFS/Application/Desktop Permissions
        Gw-->>Svc: Ergebnis / simuliertes WhatIf-Ergebnis
        Svc-->>Handler: Success/Changed/Message/ErrorCode
    end
    alt alle Zeilen erfolgreich
        Handler->>Result: New-JobSucceededResult
        Handler-->>Engine: Status = Succeeded
        Engine->>Queue: Move-JobFileToStatus(done)
    else mindestens eine Zeile fehlerhaft
        Handler->>Result: New-JobFailedResult
        Handler-->>Engine: Status = Failed
        Engine->>Queue: Move-JobFileToStatus(failed)
    end
```

### GenericUser.EnableAdAccountWithGracePeriod

Pattern: `*EnableAdAccountWithGracePeriod*_pshjob_.csv`  
Queue: `standard`  
Start im Code: `config/usecases.json` -> `usecases/GenericUser/EnableAdAccountWithGracePeriod.psm1` -> `Invoke-EnableAdAccountWithGracePeriod`  
Ende im Code: `JobFileQueue.Move-JobFileToStatus()` -> `done bei Succeeded, failed bei New-JobFailedResult`

```mermaid
sequenceDiagram
    autonumber
    participant Job as CSV-Jobdatei<br/>*EnableAdAccountWithGracePeriod*_pshjob_.csv
    participant Runner as Invoke-JobProcessor.ps1
    participant Engine as JobEngine.psm1<br/>Invoke-JobEngine
    participant Queue as JobFileQueue.psm1
    participant Csv as Csv.psm1<br/>Import-JobCsv
    participant Ctx as JobContext.psm1<br/>New-JobContext
    participant Handler as EnableAdAccountWithGracePeriod.psm1<br/>Invoke-EnableAdAccountWithGracePeriod
    participant Val as Validation.psm1<br/>Assert-RequiredCsvFields
    participant Svc as Enable-GenericUserWithGracePeriod<br/>$Context.Services.UserProvisioning.EnableWithGracePeriod
    participant Gw as ActiveDirectoryGateway.psm1 + MailboxFeatureService.psm1
    participant Result as JobResult.psm1

    Job->>Runner: Datei liegt in queues/incoming<br/>oder fällig in retry/paused
    Runner->>Engine: Invoke-JobEngine -Queue standard
    Engine->>Queue: Find-UseCaseJobFiles(pattern)
    Queue-->>Engine: passende Jobdatei
    Engine->>Queue: Claim-JobFile(UseCaseName, Queue)
    Queue-->>Engine: WorkingFile + JobId + StableJobKey + Metadata
    Engine->>Csv: Import-JobCsv(WorkingFile)
    Csv-->>Engine: Payload rows
    Engine->>Ctx: New-JobContext(... Services, Logger, WhatIfMode ...)
    Engine->>Handler: Invoke-EnableAdAccountWithGracePeriod(Context)
    Handler->>Val: Pflichtfelder validieren
    loop pro CSV-Zeile
        Handler->>Svc: Service-Aufruf mit Context + Row
        Svc->>Gw: Get-AdUserBySamAccountNameSafe<br/>Set-AdAccountPasswordSafe optional<br/>Enable-AdAccountSafe optional<br/>Set-AdUserSafe AccountExpirationDate / ChangePasswordAtLogon / hrmsIsExpired<br/>Set-MailboxVisibility Unhide
        Gw-->>Svc: Ergebnis / simuliertes WhatIf-Ergebnis
        Svc-->>Handler: Success/Changed/Message/ErrorCode
    end
    alt alle Zeilen erfolgreich
        Handler->>Result: New-JobSucceededResult
        Handler-->>Engine: Status = Succeeded
        Engine->>Queue: Move-JobFileToStatus(done)
    else mindestens eine Zeile fehlerhaft
        Handler->>Result: New-JobFailedResult
        Handler-->>Engine: Status = Failed
        Engine->>Queue: Move-JobFileToStatus(failed)
    end
```

### GenericUser.ModifyMobilePhoneNumber

Pattern: `*ModifyMobilePhoneNumber*_pshjob_.csv`  
Queue: `standard`  
Start im Code: `config/usecases.json` -> `usecases/GenericUser/ModifyMobilePhoneNumber.psm1` -> `Invoke-ModifyMobilePhoneNumber`  
Ende im Code: `JobFileQueue.Move-JobFileToStatus()` -> `done bei Succeeded, failed bei New-JobFailedResult`

```mermaid
sequenceDiagram
    autonumber
    participant Job as CSV-Jobdatei<br/>*ModifyMobilePhoneNumber*_pshjob_.csv
    participant Runner as Invoke-JobProcessor.ps1
    participant Engine as JobEngine.psm1<br/>Invoke-JobEngine
    participant Queue as JobFileQueue.psm1
    participant Csv as Csv.psm1<br/>Import-JobCsv
    participant Ctx as JobContext.psm1<br/>New-JobContext
    participant Handler as ModifyMobilePhoneNumber.psm1<br/>Invoke-ModifyMobilePhoneNumber
    participant Val as Validation.psm1<br/>Assert-RequiredCsvFields
    participant Svc as Set-GenericUserMobilePhoneNumber<br/>$Context.Services.UserProvisioning.SetMobilePhoneNumber
    participant Gw as ActiveDirectoryGateway.psm1
    participant Result as JobResult.psm1

    Job->>Runner: Datei liegt in queues/incoming<br/>oder fällig in retry/paused
    Runner->>Engine: Invoke-JobEngine -Queue standard
    Engine->>Queue: Find-UseCaseJobFiles(pattern)
    Queue-->>Engine: passende Jobdatei
    Engine->>Queue: Claim-JobFile(UseCaseName, Queue)
    Queue-->>Engine: WorkingFile + JobId + StableJobKey + Metadata
    Engine->>Csv: Import-JobCsv(WorkingFile)
    Csv-->>Engine: Payload rows
    Engine->>Ctx: New-JobContext(... Services, Logger, WhatIfMode ...)
    Engine->>Handler: Invoke-ModifyMobilePhoneNumber(Context)
    Handler->>Val: Pflichtfelder validieren
    loop pro CSV-Zeile
        Handler->>Svc: Service-Aufruf mit Context + Row
        Svc->>Gw: Get-AdUserBySamAccountNameSafe<br/>Set-AdUserSafe smsPasscodeMobile / extensionAttribute3
        Gw-->>Svc: Ergebnis / simuliertes WhatIf-Ergebnis
        Svc-->>Handler: Success/Changed/Message/ErrorCode
    end
    alt alle Zeilen erfolgreich
        Handler->>Result: New-JobSucceededResult
        Handler-->>Engine: Status = Succeeded
        Engine->>Queue: Move-JobFileToStatus(done)
    else mindestens eine Zeile fehlerhaft
        Handler->>Result: New-JobFailedResult
        Handler-->>Engine: Status = Failed
        Engine->>Queue: Move-JobFileToStatus(failed)
    end
```

### GenericUser.ModifyMailboxFolderAce

Pattern: `*ModifyMailboxFolderAce*_pshjob_.csv`  
Queue: `standard`  
Start im Code: `config/usecases.json` -> `usecases/GenericUser/ModifyMailboxFolderAce.psm1` -> `Invoke-ModifyMailboxFolderAce`  
Ende im Code: `JobFileQueue.Move-JobFileToStatus()` -> `done bei Succeeded, failed bei New-JobFailedResult / PARTIAL_FAILURE`

```mermaid
sequenceDiagram
    autonumber
    participant Job as CSV-Jobdatei<br/>*ModifyMailboxFolderAce*_pshjob_.csv
    participant Runner as Invoke-JobProcessor.ps1
    participant Engine as JobEngine.psm1<br/>Invoke-JobEngine
    participant Queue as JobFileQueue.psm1
    participant Csv as Csv.psm1<br/>Import-JobCsv
    participant Ctx as JobContext.psm1<br/>New-JobContext
    participant Handler as ModifyMailboxFolderAce.psm1<br/>Invoke-ModifyMailboxFolderAce
    participant Val as Validation.psm1<br/>Assert-RequiredCsvFields
    participant Svc as Set-GenericUserMailboxFolderAce<br/>$Context.Services.UserProvisioning.SetMailboxFolderAce
    participant Gw as ActiveDirectoryGateway.psm1 + ExchangeOnPremGateway.psm1
    participant Result as JobResult.psm1

    Job->>Runner: Datei liegt in queues/incoming<br/>oder fällig in retry/paused
    Runner->>Engine: Invoke-JobEngine -Queue standard
    Engine->>Queue: Find-UseCaseJobFiles(pattern)
    Queue-->>Engine: passende Jobdatei
    Engine->>Queue: Claim-JobFile(UseCaseName, Queue)
    Queue-->>Engine: WorkingFile + JobId + StableJobKey + Metadata
    Engine->>Csv: Import-JobCsv(WorkingFile)
    Csv-->>Engine: Payload rows
    Engine->>Ctx: New-JobContext(... Services, Logger, WhatIfMode ...)
    Engine->>Handler: Invoke-ModifyMailboxFolderAce(Context)
    Handler->>Val: Pflichtfelder validieren
    loop pro CSV-Zeile
        Handler->>Svc: Service-Aufruf mit Context + Row
        Svc->>Gw: Search-AdUserByLdapFilterSafe delegated/delegating users<br/>Get-OnPremMailboxSafe<br/>Get-OnPremMailboxFolderStatisticsSafe Calendar<br/>Remove-OnPremMailboxFolderPermissionSafe wenn AclActionType=Remove<br/>Add-OnPremMailboxFolderPermissionSafe wenn Add
        Gw-->>Svc: Ergebnis / simuliertes WhatIf-Ergebnis
        Svc-->>Handler: Success/Changed/Message/ErrorCode
    end
    alt alle Zeilen erfolgreich
        Handler->>Result: New-JobSucceededResult
        Handler-->>Engine: Status = Succeeded
        Engine->>Queue: Move-JobFileToStatus(done)
    else mindestens eine Zeile fehlerhaft
        Handler->>Result: New-JobFailedResult
        Handler-->>Engine: Status = Failed
        Engine->>Queue: Move-JobFileToStatus(failed)
    end
```

### UserPerson.HospisPersonUseCase

Pattern: `*HospisPersonUseCase*_pshjob_.csv`  
Queue: `standard`  
Start im Code: `config/usecases.json` -> `usecases/UserPerson/HospisPersonUseCase.psm1` -> `Invoke-HospisPersonUseCase`  
Ende im Code: `JobFileQueue.Move-JobFileToStatus()` -> `done bei Succeeded, failed bei New-JobFailedResult`

```mermaid
sequenceDiagram
    autonumber
    participant Job as CSV-Jobdatei<br/>*HospisPersonUseCase*_pshjob_.csv
    participant Runner as Invoke-JobProcessor.ps1
    participant Engine as JobEngine.psm1<br/>Invoke-JobEngine
    participant Queue as JobFileQueue.psm1
    participant Csv as Csv.psm1<br/>Import-JobCsv
    participant Ctx as JobContext.psm1<br/>New-JobContext
    participant Handler as HospisPersonUseCase.psm1<br/>Invoke-HospisPersonUseCase
    participant Val as Validation.psm1<br/>Assert-RequiredCsvFields
    participant Svc as Submit-HospisPersonTransaction<br/>$Context.Services.HospisPerson.SubmitTransaction
    participant Gw as SqlGateway.psm1
    participant Result as JobResult.psm1

    Job->>Runner: Datei liegt in queues/incoming<br/>oder fällig in retry/paused
    Runner->>Engine: Invoke-JobEngine -Queue standard
    Engine->>Queue: Find-UseCaseJobFiles(pattern)
    Queue-->>Engine: passende Jobdatei
    Engine->>Queue: Claim-JobFile(UseCaseName, Queue)
    Queue-->>Engine: WorkingFile + JobId + StableJobKey + Metadata
    Engine->>Csv: Import-JobCsv(WorkingFile)
    Csv-->>Engine: Payload rows
    Engine->>Ctx: New-JobContext(... Services, Logger, WhatIfMode ...)
    Engine->>Handler: Invoke-HospisPersonUseCase(Context)
    Handler->>Val: Pflichtfelder validieren
    loop pro CSV-Zeile
        Handler->>Svc: Service-Aufruf mit Context + Row
        Svc->>Gw: New-HospisPersonTransactionSql<br/>Invoke-SqlNonQuerySafe<br/>Archiv-/Reporting-Hilfsfunktionen im HospisPersonService
        Gw-->>Svc: Ergebnis / simuliertes WhatIf-Ergebnis
        Svc-->>Handler: Success/Changed/Message/ErrorCode
    end
    alt alle Zeilen erfolgreich
        Handler->>Result: New-JobSucceededResult
        Handler-->>Engine: Status = Succeeded
        Engine->>Queue: Move-JobFileToStatus(done)
    else mindestens eine Zeile fehlerhaft
        Handler->>Result: New-JobFailedResult
        Handler-->>Engine: Status = Failed
        Engine->>Queue: Move-JobFileToStatus(failed)
    end
```

### Urgent.InactivateHospisPerson

Pattern: `*Inaktivieren_HospisPersonUrgentUseCase*_pshjob_.csv`  
Queue: `urgent`  
Start im Code: `config/usecases.json` -> `usecases/Urgent/InactivateHospisPerson.psm1` -> `Invoke-InactivateHospisPerson`  
Ende im Code: `JobFileQueue.Move-JobFileToStatus()` -> `done bei Succeeded, failed bei New-JobFailedResult`

```mermaid
sequenceDiagram
    autonumber
    participant Job as CSV-Jobdatei<br/>*Inaktivieren_HospisPersonUrgentUseCase*_pshjob_.csv
    participant Runner as Invoke-JobProcessor.ps1
    participant Engine as JobEngine.psm1<br/>Invoke-JobEngine
    participant Queue as JobFileQueue.psm1
    participant Csv as Csv.psm1<br/>Import-JobCsv
    participant Ctx as JobContext.psm1<br/>New-JobContext
    participant Handler as InactivateHospisPerson.psm1<br/>Invoke-InactivateHospisPerson
    participant Val as Validation.psm1<br/>Assert-RequiredCsvFields
    participant Svc as Invoke-UrgentHospisPersonInactivation<br/>$Context.Services.HospisPerson.UrgentInactivation
    participant Gw as SqlGateway.psm1 + ActiveDirectoryGateway.psm1 + ExchangeOnPremGateway.psm1
    participant Result as JobResult.psm1

    Job->>Runner: Datei liegt in queues/incoming<br/>oder fällig in retry/paused
    Runner->>Engine: Invoke-JobEngine -Queue urgent
    Engine->>Queue: Find-UseCaseJobFiles(pattern)
    Queue-->>Engine: passende Jobdatei
    Engine->>Queue: Claim-JobFile(UseCaseName, Queue)
    Queue-->>Engine: WorkingFile + JobId + StableJobKey + Metadata
    Engine->>Csv: Import-JobCsv(WorkingFile)
    Csv-->>Engine: Payload rows
    Engine->>Ctx: New-JobContext(... Services, Logger, WhatIfMode ...)
    Engine->>Handler: Invoke-InactivateHospisPerson(Context)
    Handler->>Val: Pflichtfelder validieren
    loop pro CSV-Zeile
        Handler->>Svc: Service-Aufruf mit Context + Row
        Svc->>Gw: New-UrgentHospisInactivationSql / Invoke-SqlNonQuerySafe<br/>Get-AdUsersByEmployeeIdSafe<br/>Disable-AdAccountSafe<br/>Set-OnPremMailboxAutoReplyConfigurationSafe<br/>Remove-AdGroupMemberSafe<br/>Set-AdUserSafe Clear extensionAttribute6/msDS-cloudExtensionAttribute15 + Description
        Gw-->>Svc: Ergebnis / simuliertes WhatIf-Ergebnis
        Svc-->>Handler: Success/Changed/Message/ErrorCode
    end
    alt alle Zeilen erfolgreich
        Handler->>Result: New-JobSucceededResult
        Handler-->>Engine: Status = Succeeded
        Engine->>Queue: Move-JobFileToStatus(done)
    else mindestens eine Zeile fehlerhaft
        Handler->>Result: New-JobFailedResult
        Handler-->>Engine: Status = Failed
        Engine->>Queue: Move-JobFileToStatus(failed)
    end
```

### PersonMailbox.CreateNonStandard

Pattern: `*CreateNonStdPersonMailbox*_pshjob_.csv`  
Queue: `person-mailbox-longrunning`  
Start im Code: `config/usecases.json` -> `usecases/PersonMailbox/CreateNonStdPersonMailbox.psm1` -> `Invoke-CreateNonStdPersonMailbox`  
Ende im Code: pro Zwischenschritt `Move-JobFileToStatus(retry)`, final `Move-JobFileToStatus(done)`


```mermaid
sequenceDiagram
    autonumber
    participant Job as CSV-Jobdatei<br/>*CreateNonStdPersonMailbox*_pshjob_.csv
    participant Runner as Invoke-JobProcessor.ps1<br/>Queue person-mailbox-longrunning
    participant Engine as JobEngine.psm1<br/>Invoke-JobEngine
    participant Queue as JobFileQueue.psm1
    participant Csv as Csv.psm1<br/>Import-JobCsv
    participant Ctx as JobContext.psm1<br/>New-JobContext
    participant Handler as CreateNonStdPersonMailbox.psm1<br/>Invoke-CreateNonStdPersonMailbox
    participant State as JobState.psm1<br/>state/&lt;StableJobKey&gt;.state.json
    participant Svc as PersonMailboxService.psm1
    participant AD as ActiveDirectoryGateway.psm1
    participant EX as ExchangeOnPremGateway.psm1
    participant DFS as DfsGateway.psm1
    participant Result as JobResult.psm1

    Job->>Runner: Datei liegt in queues/incoming oder retry<br/>Pattern erkannt
    Runner->>Engine: Invoke-JobEngine -Queue person-mailbox-longrunning
    Engine->>Queue: Find-UseCaseJobFiles(pattern, retry, optional paused)
    Queue-->>Engine: fällige Datei
    Engine->>Queue: Claim-JobFile(UseCaseName, Queue)
    Queue-->>Engine: WorkingFile + JobId + StableJobKey + Metadata
    Engine->>Csv: Import-JobCsv(WorkingFile)
    Csv-->>Engine: Payload
    Engine->>Ctx: New-JobContext(... StableJobKey, Metadata ...)
    Engine->>Handler: Invoke-CreateNonStdPersonMailbox(Context)
    Handler->>Handler: Assert-RequiredCsvFields<br/>genau 1 Zeile erwartet
    Handler->>State: Get/Initialize State über StableJobKey

    alt Step 10 ValidateInput
        Handler->>Svc: New-NonStandardPersonMailboxPlan(Context, Row)
        Svc-->>Handler: Plan
        Handler->>State: Set-JobStateStep(20)
        Handler->>Result: New-JobRetryResult(RetryAfter +1s)
        Handler-->>Engine: Retry
        Engine->>Queue: Move-JobFileToStatus(retry)
    else Step 20 PrepareAdAccount
        Handler->>Svc: Invoke-PrepareNonStandardPersonMailboxAdAccount(Context, Plan)
        Svc->>AD: Search/Get/New/Set AD User je Plan
        Svc-->>Handler: Result
        Handler->>State: Set-JobStateStep(30)
        Handler->>Result: New-JobRetryResult(RetryAfter +1s)
        Handler-->>Engine: Retry
        Engine->>Queue: Move-JobFileToStatus(retry)
    else Step 30 PrepareMailbox
        Handler->>Svc: Invoke-PrepareNonStandardPersonMailboxMailbox(Context, Plan)
        Svc->>EX: Enable-OnPremMailboxSafe
        Svc-->>Handler: Result
        Handler->>State: Set-JobStateStep(40)
        Handler->>Result: New-JobRetryResult(RetryAfter +1s)
        Handler-->>Engine: Retry
        Engine->>Queue: Move-JobFileToStatus(retry)
    else Step 40 WaitForMailboxVisibility
        Handler->>Svc: Test-NonStandardPersonMailboxVisibility(Context, Plan)
        Svc->>EX: Get-OnPremMailboxSafe
        alt Mailbox noch nicht sichtbar
            Handler->>Result: New-JobRetryResult(RetryAfter +5min)
            Handler-->>Engine: Retry
            Engine->>Queue: Move-JobFileToStatus(retry)
        else Mailbox sichtbar
            Handler->>State: Set-JobStateStep(50)
            Handler->>Result: New-JobRetryResult(RetryAfter +1s)
            Handler-->>Engine: Retry
            Engine->>Queue: Move-JobFileToStatus(retry)
        end
    else Step 50 ApplyAttributes
        Handler->>Svc: Invoke-ApplyNonStandardPersonMailboxAttributes(Context, Plan)
        Svc->>AD: Enable-AdAccountSafe / Set-AdUserSafe
        Svc->>EX: Set-OnPremMailboxSafe / Set-OnPremCASMailboxSafe
        Handler->>State: Set-JobStateStep(60)
        Handler->>Result: New-JobRetryResult(RetryAfter +1s)
        Handler-->>Engine: Retry
        Engine->>Queue: Move-JobFileToStatus(retry)
    else Step 60 Finalize
        Handler->>Svc: Complete-NonStandardPersonMailboxProvisioning(Context, Plan)
        Svc->>DFS: Update-DfsShareSettingsSafe<br/>TODO Details
        Handler->>State: Set-JobStateStep(90)
        Handler->>Result: New-JobRetryResult(RetryAfter +1s)
        Handler-->>Engine: Retry
        Engine->>Queue: Move-JobFileToStatus(retry)
    else Step 90 Done
        Handler->>State: Complete-JobState(Status Completed)
        Handler->>Result: New-JobSucceededResult
        Handler-->>Engine: Succeeded
        Engine->>Queue: Move-JobFileToStatus(done)
    end
```
