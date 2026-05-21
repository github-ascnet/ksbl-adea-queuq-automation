Describe 'Invoke-JobProcessor API output compatibility' {
  BeforeAll {
    $script:root = (Resolve-Path (Join-Path -Path $PSScriptRoot -ChildPath '..\..')).Path
    $script:processorPath = Join-Path -Path $script:root -ChildPath 'Invoke-JobProcessor.ps1'
    $script:engineModulePath = Join-Path -Path $script:root -ChildPath 'core\JobEngine.psm1'
    Import-Module -Name $script:engineModulePath -Force -DisableNameChecking

    $script:testBase = Join-Path -Path $script:root -ChildPath 'tests\processor-api-test'
    if (Test-Path -Path $script:testBase) {
      Remove-Item -Path $script:testBase -Recurse -Force
    }

    New-Item -Path (Join-Path -Path $script:testBase -ChildPath 'config') -ItemType Directory -Force | Out-Null
    New-Item -Path (Join-Path -Path $script:testBase -ChildPath 'handlers') -ItemType Directory -Force | Out-Null
    New-Item -Path (Join-Path -Path $script:testBase -ChildPath 'queues\incoming') -ItemType Directory -Force | Out-Null
  }

  AfterAll {
    if ($script:testBase -and (Test-Path -Path $script:testBase)) {
      Remove-Item -Path $script:testBase -Recurse -Force
    }
  }

  It 'accepts parameter OutputJson' {
    $command = Get-Command -Name $script:processorPath -ErrorAction Stop
    ($command.Parameters.ContainsKey('OutputJson')) | Should -Be $true
  }

  It 'accepts parameter CorrelationId' {
    $command = Get-Command -Name $script:processorPath -ErrorAction Stop
    ($command.Parameters.ContainsKey('CorrelationId')) | Should -Be $true
  }

  It 'returns structured JSON with expected properties when OutputJson is set' {
    $handlerFile = Join-Path -Path $script:testBase -ChildPath 'handlers\InvokeApiTestHandler.psm1'
    @'
function Invoke-ApiTestHandler {
    param([Parameter(Mandatory = $true)][object]$Context)
    [pscustomobject]@{ Status = 'Succeeded'; Message = 'ok' }
}
Export-ModuleMember -Function @('Invoke-ApiTestHandler')
'@ | Set-Content -Path $handlerFile -Encoding UTF8

    @'
{
  "Paths": {
    "QueueRoot": "tests/processor-api-test/queues",
    "StatePath": "tests/processor-api-test/state",
    "LogPath": "tests/processor-api-test/logs"
  },
  "Queue": {
    "StaleLockMinutes": 60
  },
  "CsvDelimiter": ";",
  "Logging": {
    "ConsoleEnabled": true,
    "FileEnabled": false,
    "EventLogEnabled": false,
    "VerboseLogging": false,
    "LogFileName": "jobprocessor.log"
  },
  "EventLog": {
    "LogName": "Application",
    "Source": "AdeaJobEngine"
  },
  "Notifications": {
    "Enabled": false
  },
  "ExchangeOnline": {
    "Enabled": false
  }
}
'@ | Set-Content -Path (Join-Path -Path $script:testBase -ChildPath 'config\appsettings.json') -Encoding UTF8

    '{}' | Set-Content -Path (Join-Path -Path $script:testBase -ChildPath 'config\env.json') -Encoding UTF8

    @'
{
  "UseCases": [
    {
      "Name": "Test.ApiOutput",
      "Pattern": "ApiOutputTest*_pshjob_.csv",
      "Module": "tests/processor-api-test/handlers/InvokeApiTestHandler.psm1",
      "Handler": "Invoke-ApiTestHandler",
      "Queue": "standard",
      "Priority": 10,
      "SupportsPause": false,
      "MaxParallelism": 1,
      "Enabled": true,
      "RequiredFields": []
    }
  ]
}
'@ | Set-Content -Path (Join-Path -Path $script:testBase -ChildPath 'config\usecases.json') -Encoding UTF8

    $incoming = Join-Path -Path $script:testBase -ChildPath 'queues\incoming\ApiOutputTest_run001_pshjob_.csv'
    "ActionType;Name`nRun;Sample" | Set-Content -Path $incoming -Encoding UTF8

    $jsonOutput = & $script:processorPath `
      -ConfigPath 'tests\processor-api-test\config\appsettings.json' `
      -UseCaseRegistryPath 'tests\processor-api-test\config\usecases.json' `
      -EnvironmentPath 'tests\processor-api-test\config\env.json' `
      -Queue 'standard' `
      -WhatIfMode:$true `
      -OutputJson

    $result = $jsonOutput | ConvertFrom-Json

    ($result.PSObject.Properties.Name -contains 'queue') | Should -Be $true
    ($result.PSObject.Properties.Name -contains 'status') | Should -Be $true
    ($result.PSObject.Properties.Name -contains 'processed') | Should -Be $true
    ($result.PSObject.Properties.Name -contains 'succeeded') | Should -Be $true
    ($result.PSObject.Properties.Name -contains 'failed') | Should -Be $true
    ($result.PSObject.Properties.Name -contains 'retry') | Should -Be $true
    ($result.PSObject.Properties.Name -contains 'paused') | Should -Be $true
    ($result.PSObject.Properties.Name -contains 'jobIds') | Should -Be $true

    $result.queue | Should -Be 'standard'
    $result.processed | Should -Be 1
    $result.succeeded | Should -Be 1
    $result.failed | Should -Be 0
    $result.retry | Should -Be 0
    $result.paused | Should -Be 0
    $result.status | Should -Be 'Succeeded'
    @($result.jobIds).Count | Should -Be 1
  }

  It 'maps aggregate counters to API status values' {
    (Get-JobProcessingAggregateStatus -Processed 5 -Succeeded 4 -Failed 1 -Retry 0 -Paused 0) | Should -Be 'Failed'
    (Get-JobProcessingAggregateStatus -Processed 5 -Succeeded 3 -Failed 0 -Retry 0 -Paused 1) | Should -Be 'Paused'
    (Get-JobProcessingAggregateStatus -Processed 5 -Succeeded 3 -Failed 0 -Retry 1 -Paused 0) | Should -Be 'WaitingForRetry'
    (Get-JobProcessingAggregateStatus -Processed 3 -Succeeded 3 -Failed 0 -Retry 0 -Paused 0) | Should -Be 'Succeeded'
    (Get-JobProcessingAggregateStatus -Processed 0 -Succeeded 0 -Failed 0 -Retry 0 -Paused 0) | Should -Be 'NoWork'
    (Get-JobProcessingAggregateStatus -Processed 3 -Succeeded 2 -Failed 0 -Retry 0 -Paused 0) | Should -Be 'CompletedWithWarnings'
  }

  It 'returns valid failed JSON on early error when OutputJson is set' {
    $jsonOutput = & $script:processorPath `
      -ConfigPath 'tests\processor-api-test\config\missing-appsettings.json' `
      -UseCaseRegistryPath 'tests\processor-api-test\config\usecases.json' `
      -EnvironmentPath 'tests\processor-api-test\config\env.json' `
      -Queue 'standard' `
      -WhatIfMode:$true `
      -OutputJson 2>$null

    $result = $jsonOutput | ConvertFrom-Json

    $result.queue | Should -Be 'standard'
    $result.status | Should -Be 'Failed'
    $result.processed | Should -Be 0
    $result.succeeded | Should -Be 0
    $result.failed | Should -Be 1
    $result.retry | Should -Be 0
    $result.paused | Should -Be 0
    @($result.jobIds).Count | Should -Be 0
    ($result.PSObject.Properties.Name -contains 'error') | Should -Be $true
    ($result.error.PSObject.Properties.Name -contains 'message') | Should -Be $true
    ($result.error.PSObject.Properties.Name -contains 'category') | Should -Be $true
    ($result.error.PSObject.Properties.Name -contains 'fullyQualifiedErrorId') | Should -Be $true
  }
}
