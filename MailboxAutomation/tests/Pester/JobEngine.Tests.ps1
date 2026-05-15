Describe 'JobEngine configuration and mapping' {
    BeforeAll {
        $root = (Resolve-Path (Join-Path -Path $PSScriptRoot -ChildPath '..\..')).Path
        $registryPath = Join-Path -Path $root -ChildPath 'config\usecases.json'
        $registry = Get-Content -Path $registryPath -Raw | ConvertFrom-Json
    }

    It 'loads use case registry' {
        $registry.UseCases.Count | Should -BeGreaterThan 0
    }

    It 'has exactly 19 enabled and 9 disabled use cases' {
        (@($registry.UseCases | Where-Object { $_.Enabled }).Count) | Should -Be 19
        (@($registry.UseCases | Where-Object { -not $_.Enabled }).Count) | Should -Be 9
    }

    It 'has no enabled use case on invalid queue name longrunning' {
        (@($registry.UseCases | Where-Object { $_.Enabled -and $_.Queue -eq 'longrunning' }).Count) | Should -Be 0
    }

    It 'maps sample file to AddEmailNickname use case by pattern' {
        $sample = 'AddEMailNickName_sample_pshjob_.csv'
        $uc = $registry.UseCases | Where-Object { $sample -like $_.Pattern }
        (($uc | ForEach-Object Name) -contains 'GenericUser.AddEmailNickname') | Should -Be $true
    }

    It 'PersonMailbox.CreateNonStandard is in person-mailbox-longrunning queue' {
        $uc = $registry.UseCases | Where-Object { $_.Name -eq 'PersonMailbox.CreateNonStandard' }
        $uc.Queue | Should -Be 'person-mailbox-longrunning'
    }

    It 'GenericUser.Enable uses pattern matching EnableNonStdPersonMailbox files' {
        $sample = 'EnableNonStdPersonMailbox_test_pshjob_.csv'
        $uc = $registry.UseCases | Where-Object { $sample -like $_.Pattern -and $_.Enabled }
        (($uc | ForEach-Object Name) -contains 'GenericUser.Enable') | Should -Be $true
    }

    It 'filters urgent queue use cases correctly - only real use cases enabled' {
        $urgent = $registry.UseCases | Where-Object { $_.Queue -eq 'urgent' -and $_.Enabled }
        (($urgent | ForEach-Object Name) -contains 'Urgent.InactivateHospisPerson') | Should -Be $true
        (($urgent | ForEach-Object Name) -contains 'Urgent.MailboxPermissionChange') | Should -Be $false
        (($urgent | ForEach-Object Name) -contains 'Urgent.RecipientAttributeChange') | Should -Be $false
    }

    It 'DistributionGroup.Create uses correct legacy pattern CreateDistributionList' {
        $sample = 'CreateDistributionList_test_pshjob_.csv'
        $uc = $registry.UseCases | Where-Object { $sample -like $_.Pattern -and $_.Enabled }
        (($uc | ForEach-Object Name) -contains 'DistributionGroup.Create') | Should -Be $true
    }

    It 'UserPerson.HospisPersonUseCase keeps AdObjectName optional in base required fields' {
        $uc = $registry.UseCases | Where-Object { $_.Name -eq 'UserPerson.HospisPersonUseCase' }
        (($uc.RequiredFields -contains 'AdObjectName')) | Should -Be $false
    }
}

Describe 'JobEngine End-to-End (WhatIf, temporary test root)' {
    BeforeAll {
        $coreDir = (Resolve-Path (Join-Path -Path $PSScriptRoot -ChildPath '..\..\core')).Path
        foreach ($m in (Get-ChildItem -Path $coreDir -Filter '*.psm1' | Sort-Object Name)) {
            Import-Module -Name $m.FullName -Force -ErrorAction Stop
        }

        $infraDir = (Resolve-Path (Join-Path -Path $PSScriptRoot -ChildPath '..\..\infrastructure')).Path
        foreach ($m in (Get-ChildItem -Path $infraDir -Filter '*.psm1' | Sort-Object Name)) {
            Import-Module -Name $m.FullName -Force -ErrorAction Stop
        }

        $script:e2eRoot = Join-Path -Path $PSScriptRoot -ChildPath '..\engine-e2e-test'
        if (Test-Path -Path $script:e2eRoot) { Remove-Item -Path $script:e2eRoot -Recurse -Force }
        New-Item -Path $script:e2eRoot -ItemType Directory -Force | Out-Null

        # handler module
        $handlerDir = Join-Path -Path $script:e2eRoot -ChildPath 'test-handler'
        New-Item -Path $handlerDir -ItemType Directory -Force | Out-Null
        $handlerFile = Join-Path -Path $handlerDir -ChildPath 'TestE2EHandler.psm1'
        Set-Content -Path $handlerFile -Encoding UTF8 -Value @'
function Invoke-TestE2EHandler {
    param([Parameter(Mandatory = $true)][object]$Context)
    [pscustomobject]@{ Status = 'Succeeded'; Message = 'E2E test OK.' }
}
Export-ModuleMember -Function 'Invoke-TestE2EHandler'
'@

        # appsettings.json (literal JSON to avoid PS5.1 serialization quirks)
        $configDir = Join-Path -Path $script:e2eRoot -ChildPath 'config'
        New-Item -Path $configDir -ItemType Directory -Force | Out-Null
        @'
{
  "Paths":         { "QueueRoot": "queues", "LogPath": "logs", "StatePath": "state" },
  "CsvDelimiter":  ";",
  "Queue":         { "StaleLockMinutes": 60 },
  "Logging":       { "ConsoleEnabled": false, "FileEnabled": false, "EventLogEnabled": false, "VerboseLogging": false, "LogFileName": "test.log" },
  "EventLog":      { "LogName": "Application", "Source": "MailboxAutomation" },
  "Notifications": { "Enabled": false },
  "ExchangeOnline":{ "Enabled": false }
}
'@ | Set-Content -Path (Join-Path $configDir 'appsettings.json') -Encoding UTF8

        # environment config (empty override)
        '{}' | Set-Content -Path (Join-Path $configDir 'env.json') -Encoding UTF8

        # usecases.json with single test usecase (literal JSON)
        @'
{
  "UseCases": [
    {
      "Name":           "Test.E2ESimple",
      "Pattern":        "*TestE2ESimple*_pshjob_.csv",
      "Module":         "test-handler/TestE2EHandler.psm1",
      "Handler":        "Invoke-TestE2EHandler",
      "Queue":          "standard",
      "Priority":       100,
      "SupportsPause":  false,
      "MaxParallelism": 1,
      "Enabled":        true,
      "RequiredFields": []
    }
  ]
}
'@ | Set-Content -Path (Join-Path $configDir 'usecases.json') -Encoding UTF8

        # queue folders
        Ensure-QueueFolders -RootPath $script:e2eRoot -QueueRoot 'queues'

        # CSV in incoming
        $incoming = Get-QueuePath -RootPath $script:e2eRoot -QueueRoot 'queues' -Status 'incoming'
        $script:e2eCsv = Join-Path -Path $incoming -ChildPath 'TestE2ESimple_run001_pshjob_.csv'
        Set-Content -Path $script:e2eCsv -Value "ActionType;Name`nTest;sample" -Encoding UTF8

        # Run engine
        Invoke-JobEngine `
            -ConfigPath          (Join-Path $configDir 'appsettings.json') `
            -UseCaseRegistryPath (Join-Path $configDir 'usecases.json') `
            -EnvironmentPath     (Join-Path $configDir 'env.json') `
            -Queue               'standard' `
            -RootPath            $script:e2eRoot `
            -WhatIfMode          $true `
            -VerboseLogging      $false
    }

    AfterAll {
        if ($script:e2eRoot -and (Test-Path -Path $script:e2eRoot)) { Remove-Item -Path $script:e2eRoot -Recurse -Force }
    }

    It 'moves CSV from incoming to done after successful handler' {
        $done = Get-QueuePath -RootPath $script:e2eRoot -QueueRoot 'queues' -Status 'done'
        $doneFiles = @(Get-ChildItem -Path $done -Filter '*.csv' -File)
        $doneFiles.Count | Should -BeGreaterThan 0
    }

    It 'no CSV file remains in incoming after processing' {
        $incoming = Get-QueuePath -RootPath $script:e2eRoot -QueueRoot 'queues' -Status 'incoming'
        (@(Get-ChildItem -Path $incoming -Filter '*TestE2ESimple*_pshjob_.csv' -File).Count) | Should -Be 0
    }

    It 'meta.json exists alongside done CSV' {
        $done = Get-QueuePath -RootPath $script:e2eRoot -QueueRoot 'queues' -Status 'done'
        $csv = @(Get-ChildItem -Path $done -Filter '*.csv' -File) | Select-Object -First 1
        (Test-Path -Path "$($csv.FullName).meta.json") | Should -Be $true
    }

    It 'metadata has correct Status, UseCaseName, Queue, JobId and StableJobKey' {
        $done = Get-QueuePath -RootPath $script:e2eRoot -QueueRoot 'queues' -Status 'done'
        $csv = @(Get-ChildItem -Path $done -Filter '*.csv' -File) | Select-Object -First 1
        $meta = Read-JobMetadata -FilePath $csv.FullName
        $meta.Status | Should -Be 'done'
        $meta.UseCaseName | Should -Be 'Test.E2ESimple'
        $meta.Queue | Should -Be 'standard'
        [string]::IsNullOrWhiteSpace([string]$meta.JobId) | Should -Be $false
        [string]::IsNullOrWhiteSpace([string]$meta.StableJobKey) | Should -Be $false
    }
}
