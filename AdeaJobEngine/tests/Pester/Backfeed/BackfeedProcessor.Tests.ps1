Describe 'Backfeed processor' {
    BeforeAll {
        $root = (Resolve-Path (Join-Path -Path $PSScriptRoot -ChildPath '..\..\..')).Path
        $script:root = $root
        $script:processorPath = Join-Path -Path $root -ChildPath 'backfeed\Invoke-BackfeedProcessor.ps1'
        $script:contextModulePath = Join-Path -Path $root -ChildPath 'shared\Backfeed\BackfeedContext.psm1'
        $script:resultModulePath = Join-Path -Path $root -ChildPath 'shared\Backfeed\BackfeedResult.psm1'
        Import-Module -Name $script:contextModulePath -Force -DisableNameChecking
        Import-Module -Name $script:resultModulePath -Force -DisableNameChecking
    }

    It 'accepts BackfeedType values User, Group and MailboxPermission' {
        $command = Get-Command -Name $script:processorPath -ErrorAction Stop
        $values = @($command.Parameters['BackfeedType'].Attributes | Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] } | Select-Object -First 1).ValidValues
        $values | Should -Contain 'User'
        $values | Should -Contain 'Group'
        $values | Should -Contain 'MailboxPermission'
    }

    It 'accepts Mode values Full and Delta' {
        $command = Get-Command -Name $script:processorPath -ErrorAction Stop
        $values = @($command.Parameters['Mode'].Attributes | Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] } | Select-Object -First 1).ValidValues
        $values | Should -Contain 'Full'
        $values | Should -Contain 'Delta'
    }

    It 'returns valid JSON when OutputJson is used' {
        $json = & $script:processorPath -BackfeedType User -Mode Delta -Environment Test -OutputJson -CorrelationId 'test-correlation'
        { $json | ConvertFrom-Json | Out-Null } | Should -Not -Throw
        $result = $json | ConvertFrom-Json
        $result.BackfeedType | Should -Be 'User'
        $result.Mode | Should -Be 'Delta'
        $result.Status | Should -Be 'NotImplemented'
        $result.CorrelationId | Should -BeNullOrEmpty
    }

    It 'invokes the user service and keeps result shaping minimal' {
        Import-Module -Name (Join-Path -Path $script:root -ChildPath 'backfeed\User\UserBackfeedService.psm1') -Force -DisableNameChecking
        $context = New-BackfeedContext -Environment 'Test' -Config ([pscustomobject]@{}) -Logger ([pscustomobject]@{}) -StartedAt (Get-Date) -CorrelationId 'corr-1' -BackfeedType 'User' -Mode 'Full'
        $result = Invoke-UserBackfeed -Context $context
        $result.BackfeedType | Should -Be 'User'
        $result.Mode | Should -Be 'Full'
        $result.Status | Should -Be 'NotImplemented'
        $result.ReadCount | Should -Be 0
        $result.FailedCount | Should -Be 0
    }
}