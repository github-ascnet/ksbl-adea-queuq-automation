$lockingModule = Join-Path -Path $PSScriptRoot -ChildPath '..\..\core\Locking.psm1'
$queueModule = Join-Path -Path $PSScriptRoot -ChildPath '..\..\core\JobFileQueue.psm1'
Import-Module -Name $lockingModule -Force -DisableNameChecking
Import-Module -Name $queueModule -Force -DisableNameChecking

Describe 'JobFileQueue lifecycle and metadata' {
    BeforeAll {
        $script:testRoot = Join-Path -Path $PSScriptRoot -ChildPath '..\queue-test'
        $script:queueRoot = 'queues'

        if (Test-Path -Path $script:testRoot) {
            Remove-Item -Path $script:testRoot -Recurse -Force
        }
        New-Item -Path $script:testRoot -ItemType Directory -Force | Out-Null

        Ensure-QueueFolders -RootPath $script:testRoot -QueueRoot $script:queueRoot
    }

    AfterAll {
        if (Test-Path -Path $script:testRoot) {
            Remove-Item -Path $script:testRoot -Recurse -Force
        }
    }

    It 'contains each core function only once in module source' {
        $moduleFile = Join-Path -Path $PSScriptRoot -ChildPath '..\..\core\JobFileQueue.psm1'
        $content = Get-Content -Path $moduleFile -Raw
        foreach ($name in @(
            'New-JobId','Get-QueuePath','Ensure-QueueFolders','Get-JobMetadataPath','Get-StableJobKey',
            'Read-JobMetadata','Save-JobMetadata','Get-OrCreateJobMetadata','Remove-JobMetadata','Test-JobDue',
            'Find-UseCaseJobFiles','Claim-JobFile','Move-JobFileToStatus','Get-UseCaseLockPath','Enter-UseCaseLock','Exit-UseCaseLock'
        )) {
            $hits = ([regex]::Matches($content, "(?m)^function\s+$([regex]::Escape($name))\s*\{" )).Count
            $hits | Should -Be 1
        }
    }

    It 'contains Get-NonConflictingPath defined exactly once' {
        $moduleFile = Join-Path -Path $PSScriptRoot -ChildPath '..\..\core\JobFileQueue.psm1'
        $content = Get-Content -Path $moduleFile -Raw
        $hits = ([regex]::Matches($content, '(?m)^function\s+Get-NonConflictingPath\s*\{')).Count
        $hits | Should -Be 1
    }

    It 'keeps the same JobId and StableJobKey across retry reclaim' {
        $incoming = Get-QueuePath -RootPath $script:testRoot -QueueRoot $script:queueRoot -Status 'incoming'
        $jobFile = Join-Path -Path $incoming -ChildPath 'CreateNonStdPersonMailbox_retrycheck_pshjob_.csv'
        Set-Content -Path $jobFile -Value "ActionType;TargetAdObjectName`nCreate;user01" -Encoding UTF8

        $firstClaim = Claim-JobFile -FilePath $jobFile -RootPath $script:testRoot -QueueRoot $script:queueRoot -UseCaseName 'PersonMailbox.CreateNonStandard' -Queue 'person-mailbox-longrunning'
        [string]::IsNullOrWhiteSpace([string]$firstClaim.JobId) | Should -Be $false
        [string]::IsNullOrWhiteSpace([string]$firstClaim.StableJobKey) | Should -Be $false
        (Test-Path -Path $firstClaim.MetadataPath) | Should -Be $true

        $retryPath = Move-JobFileToStatus -WorkingFile $firstClaim.WorkingFile -RootPath $script:testRoot -QueueRoot $script:queueRoot -Status 'retry' -RetryAfter ((Get-Date).AddMinutes(-1)) -Message 'retry now'
        (Test-Path -Path $retryPath) | Should -Be $true

        $retryCandidates = Find-UseCaseJobFiles -RootPath $script:testRoot -QueueRoot $script:queueRoot -Pattern '*CreateNonStdPersonMailbox*_pshjob_.csv'
        (@($retryCandidates).Count) | Should -BeGreaterThan 0

        $secondClaim = Claim-JobFile -FilePath $retryPath -RootPath $script:testRoot -QueueRoot $script:queueRoot -UseCaseName 'PersonMailbox.CreateNonStandard' -Queue 'person-mailbox-longrunning'
        $secondClaim.JobId | Should -Be $firstClaim.JobId
        $secondClaim.StableJobKey | Should -Be $firstClaim.StableJobKey
    }

    It 'skips retry files until RetryAfter is due' {
        $incoming = Get-QueuePath -RootPath $script:testRoot -QueueRoot $script:queueRoot -Status 'incoming'
        $jobFile = Join-Path -Path $incoming -ChildPath 'EnableNonStdPersonMailbox_retrywait_pshjob_.csv'
        Set-Content -Path $jobFile -Value "ActionType;AdObjectName`nEnable;u01" -Encoding UTF8

        $claim = Claim-JobFile -FilePath $jobFile -RootPath $script:testRoot -QueueRoot $script:queueRoot -UseCaseName 'GenericUser.Enable' -Queue 'standard'
        Move-JobFileToStatus -WorkingFile $claim.WorkingFile -RootPath $script:testRoot -QueueRoot $script:queueRoot -Status 'retry' -RetryAfter ((Get-Date).AddMinutes(10)) | Out-Null

        $files = Find-UseCaseJobFiles -RootPath $script:testRoot -QueueRoot $script:queueRoot -Pattern '*EnableNonStdPersonMailbox*_pshjob_.csv'
        (@($files).Count) | Should -Be 0
    }

    It 'does not process paused files by default but includes due paused when IncludePaused set' {
        $incoming = Get-QueuePath -RootPath $script:testRoot -QueueRoot $script:queueRoot -Status 'incoming'
        $jobFile = Join-Path -Path $incoming -ChildPath 'CreateNonStdPersonMailbox_pausedue_pshjob_.csv'
        Set-Content -Path $jobFile -Value "ActionType;TargetAdObjectName`nCreate;user02" -Encoding UTF8

        $claim = Claim-JobFile -FilePath $jobFile -RootPath $script:testRoot -QueueRoot $script:queueRoot -UseCaseName 'PersonMailbox.CreateNonStandard' -Queue 'person-mailbox-longrunning'
        $pausedPath = Move-JobFileToStatus -WorkingFile $claim.WorkingFile -RootPath $script:testRoot -QueueRoot $script:queueRoot -Status 'paused' -ResumeAfter ((Get-Date).AddMinutes(-30)) -PauseReason 'test'
        (Test-JobDue -FilePath $pausedPath -Status 'paused') | Should -Be $true

        $defaultFiles = Find-UseCaseJobFiles -RootPath $script:testRoot -QueueRoot $script:queueRoot -Pattern '*CreateNonStdPersonMailbox*_pshjob_.csv'
        (@($defaultFiles | Where-Object { $_.FullName -eq $pausedPath }).Count) | Should -Be 0

        $pausedFiles = Find-UseCaseJobFiles -RootPath $script:testRoot -QueueRoot $script:queueRoot -Pattern '*CreateNonStdPersonMailbox*_pshjob_.csv' -IncludePaused
        (@($pausedFiles | Where-Object { $_.Name -eq 'CreateNonStdPersonMailbox_pausedue_pshjob_.csv' }).Count) | Should -Be 1
    }

    It 'writes status, queue and use case metadata from claim and move operations' {
        $incoming = Get-QueuePath -RootPath $script:testRoot -QueueRoot $script:queueRoot -Status 'incoming'
        $jobFile = Join-Path -Path $incoming -ChildPath 'CreateNonStdPersonMailbox_meta_pshjob_.csv'
        Set-Content -Path $jobFile -Value "ActionType;TargetAdObjectName`nCreate;user03" -Encoding UTF8

        $claim = Claim-JobFile -FilePath $jobFile -RootPath $script:testRoot -QueueRoot $script:queueRoot -UseCaseName 'PersonMailbox.CreateNonStandard' -Queue 'person-mailbox-longrunning'
        $claim.Metadata.UseCaseName | Should -Be 'PersonMailbox.CreateNonStandard'
        $claim.Metadata.Queue | Should -Be 'person-mailbox-longrunning'
        $claim.Metadata.Status | Should -Be 'processing'

        $resumeAt = (Get-Date).AddMinutes(5)
        $pausedPath = Move-JobFileToStatus -WorkingFile $claim.WorkingFile -RootPath $script:testRoot -QueueRoot $script:queueRoot -Status 'paused' -ResumeAfter $resumeAt -PauseReason 'ManualPause' -Message 'waiting' -ErrorCode 'PAUSED' -JobResult ([pscustomobject]@{ Status = 'Paused'; Message = 'waiting'; ErrorCode = 'PAUSED' })

        $meta = Read-JobMetadata -FilePath $pausedPath
        $meta.PauseReason | Should -Be 'ManualPause'
        $meta.LastMessage | Should -Be 'waiting'
        $meta.LastErrorCode | Should -Be 'PAUSED'
        $meta.Status | Should -Be 'paused'
        [string]::IsNullOrWhiteSpace([string]$meta.ResumeAfter) | Should -Be $false
        [string]::IsNullOrWhiteSpace([string]$meta.JobId) | Should -Be $false
    }

    It 'keeps metadata when moving to done and failed' {
        $incoming = Get-QueuePath -RootPath $script:testRoot -QueueRoot $script:queueRoot -Status 'incoming'

        $doneCsv = Join-Path -Path $incoming -ChildPath 'CreateNonStdPersonMailbox_done_pshjob_.csv'
        Set-Content -Path $doneCsv -Value "ActionType;TargetAdObjectName`nCreate;user04" -Encoding UTF8
        $doneClaim = Claim-JobFile -FilePath $doneCsv -RootPath $script:testRoot -QueueRoot $script:queueRoot -UseCaseName 'PersonMailbox.CreateNonStandard' -Queue 'person-mailbox-longrunning'
        $donePath = Move-JobFileToStatus -WorkingFile $doneClaim.WorkingFile -RootPath $script:testRoot -QueueRoot $script:queueRoot -Status 'done' -JobResult ([pscustomobject]@{ Status = 'Succeeded'; Message = 'ok' })
        (Test-Path -Path "$donePath.meta.json") | Should -Be $true
        (Read-JobMetadata -FilePath $donePath).Status | Should -Be 'done'

        $failedCsv = Join-Path -Path $incoming -ChildPath 'CreateNonStdPersonMailbox_failed_pshjob_.csv'
        Set-Content -Path $failedCsv -Value "ActionType;TargetAdObjectName`nCreate;user05" -Encoding UTF8
        $failedClaim = Claim-JobFile -FilePath $failedCsv -RootPath $script:testRoot -QueueRoot $script:queueRoot -UseCaseName 'PersonMailbox.CreateNonStandard' -Queue 'person-mailbox-longrunning'
        $failedPath = Move-JobFileToStatus -WorkingFile $failedClaim.WorkingFile -RootPath $script:testRoot -QueueRoot $script:queueRoot -Status 'failed' -JobResult ([pscustomobject]@{ Status = 'Failed'; Message = 'boom'; ErrorCode = 'E1' })
        (Test-Path -Path "$failedPath.meta.json") | Should -Be $true
        $failedMeta = Read-JobMetadata -FilePath $failedPath
        $failedMeta.Status | Should -Be 'failed'
        $failedMeta.LastErrorCode | Should -Be 'E1'
    }

    It 'increments attempts on each claim' {
        $incoming = Get-QueuePath -RootPath $script:testRoot -QueueRoot $script:queueRoot -Status 'incoming'
        $csv = Join-Path -Path $incoming -ChildPath 'CreateNonStdPersonMailbox_attempts_pshjob_.csv'
        Set-Content -Path $csv -Value "ActionType;TargetAdObjectName`nCreate;user06" -Encoding UTF8

        $c1 = Claim-JobFile -FilePath $csv -RootPath $script:testRoot -QueueRoot $script:queueRoot -UseCaseName 'PersonMailbox.CreateNonStandard' -Queue 'person-mailbox-longrunning'
        $m1 = Read-JobMetadata -FilePath $c1.WorkingFile
        $m1.Attempts | Should -Be 1

        $r = Move-JobFileToStatus -WorkingFile $c1.WorkingFile -RootPath $script:testRoot -QueueRoot $script:queueRoot -Status 'retry' -RetryAfter ((Get-Date).AddMinutes(-1))
        $c2 = Claim-JobFile -FilePath $r -RootPath $script:testRoot -QueueRoot $script:queueRoot -UseCaseName 'PersonMailbox.CreateNonStandard' -Queue 'person-mailbox-longrunning'
        $m2 = Read-JobMetadata -FilePath $c2.WorkingFile
        $m2.Attempts | Should -Be 2
    }

    It 'ignores csv files with existing lock files' {
        $incoming = Get-QueuePath -RootPath $script:testRoot -QueueRoot $script:queueRoot -Status 'incoming'
        $csv = Join-Path -Path $incoming -ChildPath 'EnableNonStdPersonMailbox_locked_pshjob_.csv'
        Set-Content -Path $csv -Value "ActionType;AdObjectName`nEnable;u99" -Encoding UTF8
        Set-Content -Path "$csv.lock" -Value 'lock' -Encoding UTF8

        $files = Find-UseCaseJobFiles -RootPath $script:testRoot -QueueRoot $script:queueRoot -Pattern '*EnableNonStdPersonMailbox*_pshjob_.csv'
        (@($files | Where-Object { $_.Name -eq 'EnableNonStdPersonMailbox_locked_pshjob_.csv' }).Count) | Should -Be 0
    }

    It 'acquires and releases use case lock' {
        $lockPath = Enter-UseCaseLock -RootPath $script:testRoot -QueueRoot $script:queueRoot -UseCaseName 'PersonMailbox.CreateNonStandard'
        (Test-Path -Path $lockPath) | Should -Be $true

        $secondTry = Enter-UseCaseLock -RootPath $script:testRoot -QueueRoot $script:queueRoot -UseCaseName 'PersonMailbox.CreateNonStandard'
        $secondTry | Should -Be $null

        Exit-UseCaseLock -LockPath $lockPath
        (Test-Path -Path $lockPath) | Should -Be $false
    }

    It 'removes stale use case locks older than threshold' {
        $lockPath = Enter-UseCaseLock -RootPath $script:testRoot -QueueRoot $script:queueRoot -UseCaseName 'GenericUser.Enable'
        (Test-Path -Path $lockPath) | Should -Be $true

        (Get-Item $lockPath).LastWriteTime = (Get-Date).AddMinutes(-120)
        $reclaimed = Enter-UseCaseLock -RootPath $script:testRoot -QueueRoot $script:queueRoot -UseCaseName 'GenericUser.Enable' -StaleLockMinutes 60
        [string]::IsNullOrWhiteSpace([string]$reclaimed) | Should -Be $false
        Exit-UseCaseLock -LockPath $reclaimed
    }

    It 'New-FileLock is atomic - second concurrent lock attempt returns null' {
        $incoming = Get-QueuePath -RootPath $script:testRoot -QueueRoot $script:queueRoot -Status 'incoming'
        $target = Join-Path -Path $incoming -ChildPath 'atomic_lock_target.tmp'
        Set-Content -Path $target -Value 'x' -Encoding UTF8

        $lock1 = New-FileLock -TargetPath $target
        $lock1 | Should -Not -Be $null

        $lock2 = New-FileLock -TargetPath $target
        $lock2 | Should -Be $null

        Remove-FileLock -TargetPath $target
        Remove-Item -Path $target -Force -ErrorAction SilentlyContinue
    }

    It 'New-FileLock removes stale file lock and creates a new one' {
        $incoming = Get-QueuePath -RootPath $script:testRoot -QueueRoot $script:queueRoot -Status 'incoming'
        $target = Join-Path -Path $incoming -ChildPath 'stale_lock_target.tmp'
        Set-Content -Path $target -Value 'x' -Encoding UTF8

        $stale = New-FileLock -TargetPath $target
        $stale | Should -Not -Be $null
        (Get-Item $stale).LastWriteTime = (Get-Date).AddMinutes(-90)

        $fresh = New-FileLock -TargetPath $target -StaleLockMinutes 60
        $fresh | Should -Not -Be $null

        Remove-FileLock -TargetPath $target
        Remove-Item -Path $target -Force -ErrorAction SilentlyContinue
    }

    It 'Read-JobMetadata throws when meta.json is corrupt' {
        $incoming = Get-QueuePath -RootPath $script:testRoot -QueueRoot $script:queueRoot -Status 'incoming'
        $csv = Join-Path -Path $incoming -ChildPath 'corrupt_meta_pshjob_.csv'
        Set-Content -Path $csv -Value 'ActionType;x' -Encoding UTF8
        Set-Content -Path "$csv.meta.json" -Value '{ INVALID JSON !!!' -Encoding UTF8

        { Read-JobMetadata -FilePath $csv } | Should -Throw
        Remove-Item -Path $csv -Force -ErrorAction SilentlyContinue
        Remove-Item -Path "$csv.meta.json" -Force -ErrorAction SilentlyContinue
    }

    It 'Move-JobFileToStatus throws when metadata missing and AllowMetadataFallback not set' {
        $processing = Get-QueuePath -RootPath $script:testRoot -QueueRoot $script:queueRoot -Status 'processing'
        $orphan = Join-Path -Path $processing -ChildPath 'orphan_nometa_pshjob_.csv'
        Set-Content -Path $orphan -Value 'ActionType;x' -Encoding UTF8

        { Move-JobFileToStatus -WorkingFile $orphan -RootPath $script:testRoot -QueueRoot $script:queueRoot -Status 'failed' -Message 'test' } | Should -Throw
        Remove-Item -Path $orphan -Force -ErrorAction SilentlyContinue
    }

    It 'Move-JobFileToStatus does not overwrite existing destination file' {
        $incoming = Get-QueuePath -RootPath $script:testRoot -QueueRoot $script:queueRoot -Status 'incoming'
        $done = Get-QueuePath -RootPath $script:testRoot -QueueRoot $script:queueRoot -Status 'done'

        $csv1 = Join-Path -Path $incoming -ChildPath 'CreateNonStdPersonMailbox_coll1_pshjob_.csv'
        Set-Content -Path $csv1 -Value "ActionType;TargetAdObjectName`nCreate;coll1" -Encoding UTF8
        $c1 = Claim-JobFile -FilePath $csv1 -RootPath $script:testRoot -QueueRoot $script:queueRoot -UseCaseName 'PersonMailbox.CreateNonStandard' -Queue 'person-mailbox-longrunning'
        $dest1 = Move-JobFileToStatus -WorkingFile $c1.WorkingFile -RootPath $script:testRoot -QueueRoot $script:queueRoot -Status 'done' -Message 'first'
        (Test-Path -Path $dest1) | Should -Be $true

        $csv2 = Join-Path -Path $incoming -ChildPath 'CreateNonStdPersonMailbox_coll1_pshjob_.csv'
        Set-Content -Path $csv2 -Value "ActionType;TargetAdObjectName`nCreate;coll2" -Encoding UTF8
        $c2 = Claim-JobFile -FilePath $csv2 -RootPath $script:testRoot -QueueRoot $script:queueRoot -UseCaseName 'PersonMailbox.CreateNonStandard' -Queue 'person-mailbox-longrunning'
        $dest2 = Move-JobFileToStatus -WorkingFile $c2.WorkingFile -RootPath $script:testRoot -QueueRoot $script:queueRoot -Status 'done' -Message 'second'
        (Test-Path -Path $dest2) | Should -Be $true

        $dest1 | Should -Not -Be $dest2
    }

    It 'Claim-JobFile does not overwrite existing processing file' {
        $incoming = Get-QueuePath -RootPath $script:testRoot -QueueRoot $script:queueRoot -Status 'incoming'
        $processing = Get-QueuePath -RootPath $script:testRoot -QueueRoot $script:queueRoot -Status 'processing'

        $csv = Join-Path -Path $incoming -ChildPath 'CreateNonStdPersonMailbox_proc_coll_pshjob_.csv'
        Set-Content -Path $csv -Value "ActionType;TargetAdObjectName`nCreate;proccoll" -Encoding UTF8

        $existing = Join-Path -Path $processing -ChildPath 'CreateNonStdPersonMailbox_proc_coll_pshjob_.csv'
        Set-Content -Path $existing -Value 'prior' -Encoding UTF8
        Set-Content -Path "$existing.meta.json" -Value '{"JobId":"prior","StableJobKey":"prior","OriginalFileName":"x","CurrentFileName":"x","UseCaseName":"x","Queue":"standard","Status":"processing","RetryAfter":null,"ResumeAfter":null,"PauseReason":null,"Attempts":1,"CreatedAt":"2026-01-01","UpdatedAt":"2026-01-01","ClaimedAt":null,"CompletedAt":null,"FailedAt":null,"LastMessage":null,"LastErrorCode":null}' -Encoding UTF8

        $claimed = Claim-JobFile -FilePath $csv -RootPath $script:testRoot -QueueRoot $script:queueRoot -UseCaseName 'PersonMailbox.CreateNonStandard' -Queue 'person-mailbox-longrunning'
        $claimed | Should -Not -Be $null
        $claimed.WorkingFile | Should -Not -Be $existing
        (Get-Content -Path $existing -Raw).Trim() | Should -Be 'prior'

        Remove-Item -Path $existing -Force -ErrorAction SilentlyContinue
        Remove-Item -Path "$existing.meta.json" -Force -ErrorAction SilentlyContinue
    }

    # -- New tests: Get-NonConflictingPath checks .meta.json sidecar --------------

    It 'Get-NonConflictingPath returns new path when target CSV already exists' {
        $done = Get-QueuePath -RootPath $script:testRoot -QueueRoot $script:queueRoot -Status 'done'
        $existing = Join-Path -Path $done -ChildPath 'SomeFile_conflict_pshjob_.csv'
        Set-Content -Path $existing -Value 'x' -Encoding UTF8

        $result = Get-NonConflictingPath -Path $existing
        $result | Should -Not -Be $existing
        (Test-Path -Path $result) | Should -Be $false

        Remove-Item -Path $existing -Force -ErrorAction SilentlyContinue
    }

    It 'Get-NonConflictingPath returns new path when only target .meta.json exists' {
        $done = Get-QueuePath -RootPath $script:testRoot -QueueRoot $script:queueRoot -Status 'done'
        $csvPath  = Join-Path -Path $done -ChildPath 'SomeFile_metaonly_pshjob_.csv'
        $metaPath = "$csvPath.meta.json"
        # Only the .meta.json exists - the CSV does not
        Set-Content -Path $metaPath -Value '{}' -Encoding UTF8

        $result = Get-NonConflictingPath -Path $csvPath
        $result | Should -Not -Be $csvPath

        Remove-Item -Path $metaPath -Force -ErrorAction SilentlyContinue
    }

    # -- New tests: Move-JobFileToStatus does not overwrite existing .meta.json ---

    It 'Move-JobFileToStatus does not overwrite existing .meta.json in destination' {
        $incoming = Get-QueuePath -RootPath $script:testRoot -QueueRoot $script:queueRoot -Status 'incoming'
        $done     = Get-QueuePath -RootPath $script:testRoot -QueueRoot $script:queueRoot -Status 'done'

        # Create first job and move to done
        $csv1 = Join-Path -Path $incoming -ChildPath 'CreateNonStdPersonMailbox_metaoverwrite_pshjob_.csv'
        Set-Content -Path $csv1 -Value "ActionType;TargetAdObjectName`nCreate;metaow1" -Encoding UTF8
        $cl1   = Claim-JobFile -FilePath $csv1 -RootPath $script:testRoot -QueueRoot $script:queueRoot -UseCaseName 'PersonMailbox.CreateNonStandard' -Queue 'person-mailbox-longrunning'
        $dest1 = Move-JobFileToStatus -WorkingFile $cl1.WorkingFile -RootPath $script:testRoot -QueueRoot $script:queueRoot -Status 'done' -Message 'first'
        $meta1before = (Read-JobMetadata -FilePath $dest1).LastMessage

        # Create second job with same filename and move to done
        $csv2 = Join-Path -Path $incoming -ChildPath 'CreateNonStdPersonMailbox_metaoverwrite_pshjob_.csv'
        Set-Content -Path $csv2 -Value "ActionType;TargetAdObjectName`nCreate;metaow2" -Encoding UTF8
        $cl2   = Claim-JobFile -FilePath $csv2 -RootPath $script:testRoot -QueueRoot $script:queueRoot -UseCaseName 'PersonMailbox.CreateNonStandard' -Queue 'person-mailbox-longrunning'
        $dest2 = Move-JobFileToStatus -WorkingFile $cl2.WorkingFile -RootPath $script:testRoot -QueueRoot $script:queueRoot -Status 'done' -Message 'second'

        # Both destinations must differ and both .meta.json must exist with correct data
        $dest1 | Should -Not -Be $dest2
        (Read-JobMetadata -FilePath $dest1).LastMessage | Should -Be $meta1before
        (Read-JobMetadata -FilePath $dest2).LastMessage | Should -Be 'second'
    }

    # -- New tests: Find-UseCaseJobFiles paused semantics -------------------------

    It 'Find-UseCaseJobFiles does not return paused files without explicit parameter' {
        $incoming = Get-QueuePath -RootPath $script:testRoot -QueueRoot $script:queueRoot -Status 'incoming'
        $csv = Join-Path -Path $incoming -ChildPath 'CreateNonStdPersonMailbox_pausenoparam_pshjob_.csv'
        Set-Content -Path $csv -Value "ActionType;TargetAdObjectName`nCreate;noparam" -Encoding UTF8
        $cl = Claim-JobFile -FilePath $csv -RootPath $script:testRoot -QueueRoot $script:queueRoot -UseCaseName 'PersonMailbox.CreateNonStandard' -Queue 'person-mailbox-longrunning'
        Move-JobFileToStatus -WorkingFile $cl.WorkingFile -RootPath $script:testRoot -QueueRoot $script:queueRoot -Status 'paused' -ResumeAfter ((Get-Date).AddMinutes(-5)) | Out-Null

        $result = Find-UseCaseJobFiles -RootPath $script:testRoot -QueueRoot $script:queueRoot -Pattern '*CreateNonStdPersonMailbox*_pshjob_.csv'
        ($result | Where-Object { $_.Name -like '*pausenoparam*' }).Count | Should -Be 0
    }

    It 'Find-UseCaseJobFiles returns due paused file when ResumePaused is set' {
        $incoming = Get-QueuePath -RootPath $script:testRoot -QueueRoot $script:queueRoot -Status 'incoming'
        $csv = Join-Path -Path $incoming -ChildPath 'CreateNonStdPersonMailbox_resumeparam_pshjob_.csv'
        Set-Content -Path $csv -Value "ActionType;TargetAdObjectName`nCreate;resumeparam" -Encoding UTF8
        $cl = Claim-JobFile -FilePath $csv -RootPath $script:testRoot -QueueRoot $script:queueRoot -UseCaseName 'PersonMailbox.CreateNonStandard' -Queue 'person-mailbox-longrunning'
        Move-JobFileToStatus -WorkingFile $cl.WorkingFile -RootPath $script:testRoot -QueueRoot $script:queueRoot -Status 'paused' -ResumeAfter ((Get-Date).AddMinutes(-10)) | Out-Null

        $result = Find-UseCaseJobFiles -RootPath $script:testRoot -QueueRoot $script:queueRoot -Pattern '*CreateNonStdPersonMailbox*_pshjob_.csv' -ResumePaused
        ($result | Where-Object { $_.Name -like '*resumeparam*' }).Count | Should -Be 1
    }

    It 'Find-UseCaseJobFiles does not return paused file when ResumeAfter is in the future' {
        $incoming = Get-QueuePath -RootPath $script:testRoot -QueueRoot $script:queueRoot -Status 'incoming'
        $csv = Join-Path -Path $incoming -ChildPath 'CreateNonStdPersonMailbox_pausefuture_pshjob_.csv'
        Set-Content -Path $csv -Value "ActionType;TargetAdObjectName`nCreate;pausefuture" -Encoding UTF8
        $cl = Claim-JobFile -FilePath $csv -RootPath $script:testRoot -QueueRoot $script:queueRoot -UseCaseName 'PersonMailbox.CreateNonStandard' -Queue 'person-mailbox-longrunning'
        Move-JobFileToStatus -WorkingFile $cl.WorkingFile -RootPath $script:testRoot -QueueRoot $script:queueRoot -Status 'paused' -ResumeAfter ((Get-Date).AddMinutes(30)) | Out-Null

        $result = Find-UseCaseJobFiles -RootPath $script:testRoot -QueueRoot $script:queueRoot -Pattern '*CreateNonStdPersonMailbox*_pshjob_.csv' -IncludePaused
        ($result | Where-Object { $_.Name -like '*pausefuture*' }).Count | Should -Be 0
    }

    It 'Find-UseCaseJobFiles returns paused file when ResumeAfter is in the past' {
        $incoming = Get-QueuePath -RootPath $script:testRoot -QueueRoot $script:queueRoot -Status 'incoming'
        $csv = Join-Path -Path $incoming -ChildPath 'CreateNonStdPersonMailbox_pausepast_pshjob_.csv'
        Set-Content -Path $csv -Value "ActionType;TargetAdObjectName`nCreate;pausepast" -Encoding UTF8
        $cl = Claim-JobFile -FilePath $csv -RootPath $script:testRoot -QueueRoot $script:queueRoot -UseCaseName 'PersonMailbox.CreateNonStandard' -Queue 'person-mailbox-longrunning'
        Move-JobFileToStatus -WorkingFile $cl.WorkingFile -RootPath $script:testRoot -QueueRoot $script:queueRoot -Status 'paused' -ResumeAfter ((Get-Date).AddMinutes(-60)) | Out-Null

        $result = Find-UseCaseJobFiles -RootPath $script:testRoot -QueueRoot $script:queueRoot -Pattern '*CreateNonStdPersonMailbox*_pshjob_.csv' -IncludePaused
        ($result | Where-Object { $_.Name -like '*pausepast*' }).Count | Should -Be 1
    }

    It 'stores ExternalCorrelationId in metadata when CorrelationId is provided' {
        $incoming = Get-QueuePath -RootPath $script:testRoot -QueueRoot $script:queueRoot -Status 'incoming'
        $csv = Join-Path -Path $incoming -ChildPath 'CreateNonStdPersonMailbox_corrset_pshjob_.csv'
        Set-Content -Path $csv -Value "ActionType;TargetAdObjectName`nCreate;corrset" -Encoding UTF8

        $claim = Claim-JobFile -FilePath $csv -RootPath $script:testRoot -QueueRoot $script:queueRoot -UseCaseName 'PersonMailbox.CreateNonStandard' -Queue 'person-mailbox-longrunning' -ExternalCorrelationId '4c7f8ff7-b96c-4f94-bbc2-fd9cfbd8401e'
        $meta = Read-JobMetadata -FilePath $claim.WorkingFile

        ($meta.PSObject.Properties.Name -contains 'ExternalCorrelationId') | Should -Be $true
        $meta.ExternalCorrelationId | Should -Be '4c7f8ff7-b96c-4f94-bbc2-fd9cfbd8401e'
    }

    It 'does not overwrite an existing different ExternalCorrelationId' {
        $incoming = Get-QueuePath -RootPath $script:testRoot -QueueRoot $script:queueRoot -Status 'incoming'
        $csv = Join-Path -Path $incoming -ChildPath 'CreateNonStdPersonMailbox_correxisting_pshjob_.csv'
        Set-Content -Path $csv -Value "ActionType;TargetAdObjectName`nCreate;correxisting" -Encoding UTF8

        Get-OrCreateJobMetadata -FilePath $csv -UseCaseName 'PersonMailbox.CreateNonStandard' -Queue 'person-mailbox-longrunning' -ExternalCorrelationId 'existing-correlation' | Out-Null
        $meta = Get-OrCreateJobMetadata -FilePath $csv -UseCaseName 'PersonMailbox.CreateNonStandard' -Queue 'person-mailbox-longrunning' -ExternalCorrelationId 'new-correlation'

        $meta.ExternalCorrelationId | Should -Be 'existing-correlation'
    }

    It 'does not force ExternalCorrelationId when CorrelationId is not provided' {
        $incoming = Get-QueuePath -RootPath $script:testRoot -QueueRoot $script:queueRoot -Status 'incoming'
        $csv = Join-Path -Path $incoming -ChildPath 'CreateNonStdPersonMailbox_corrnone_pshjob_.csv'
        Set-Content -Path $csv -Value "ActionType;TargetAdObjectName`nCreate;corrnone" -Encoding UTF8

        $meta = Get-OrCreateJobMetadata -FilePath $csv -UseCaseName 'PersonMailbox.CreateNonStandard' -Queue 'person-mailbox-longrunning'
        ($meta.PSObject.Properties.Name -contains 'ExternalCorrelationId') | Should -Be $false
    }
}
