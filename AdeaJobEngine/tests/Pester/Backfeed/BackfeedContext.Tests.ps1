Describe 'Backfeed context run id behavior' {
    BeforeAll {
        $root = (Resolve-Path (Join-Path -Path $PSScriptRoot -ChildPath '..\..\..')).Path
        $script:contextModulePath = Join-Path -Path $root -ChildPath 'shared\Backfeed\BackfeedContext.psm1'
        Import-Module -Name $script:contextModulePath -Force -DisableNameChecking
    }

    It 'context contains BackfeedRunId' {
        $context = New-BackfeedContext -Environment 'Test' -Config ([pscustomobject]@{}) -Logger ([pscustomobject]@{}) -StartedAt (Get-Date) -CorrelationId 'corr-ctx-1' -BackfeedType 'MailboxPermission' -Mode 'Full'
        @($context.PSObject.Properties.Name) | Should -Contain 'BackfeedRunId'
    }

    It 'explicit valid BackfeedRunId is used as-is' {
        $expected = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
        $context = New-BackfeedContext -Environment 'Test' -Config ([pscustomobject]@{}) -Logger ([pscustomobject]@{}) -StartedAt (Get-Date) -CorrelationId 'corr-ctx-2' -BackfeedType 'MailboxPermission' -Mode 'Full' -BackfeedRunId $expected
        $context.BackfeedRunId | Should -Be $expected
    }

    It 'uses CorrelationId as BackfeedRunId when BackfeedRunId is missing and CorrelationId is a guid' {
        $correlationId = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'
        $context = New-BackfeedContext -Environment 'Test' -Config ([pscustomobject]@{}) -Logger ([pscustomobject]@{}) -StartedAt (Get-Date) -CorrelationId $correlationId -BackfeedType 'MailboxPermission' -Mode 'Full'
        $context.BackfeedRunId | Should -Be $correlationId
    }

    It 'generates new guid BackfeedRunId when neither BackfeedRunId nor CorrelationId is guid' {
        $context = New-BackfeedContext -Environment 'Test' -Config ([pscustomobject]@{}) -Logger ([pscustomobject]@{}) -StartedAt (Get-Date) -CorrelationId 'not-a-guid' -BackfeedType 'MailboxPermission' -Mode 'Full'
        [guid]::Parse([string]$context.BackfeedRunId).ToString() | Should -Be ([string]$context.BackfeedRunId)
    }

    It 'keeps CorrelationId unchanged' {
        $context = New-BackfeedContext -Environment 'Test' -Config ([pscustomobject]@{}) -Logger ([pscustomobject]@{}) -StartedAt (Get-Date) -CorrelationId 'corr-keep-1' -BackfeedType 'MailboxPermission' -Mode 'Full' -BackfeedRunId 'cccccccc-cccc-cccc-cccc-cccccccccccc'
        $context.CorrelationId | Should -Be 'corr-keep-1'
    }
}
