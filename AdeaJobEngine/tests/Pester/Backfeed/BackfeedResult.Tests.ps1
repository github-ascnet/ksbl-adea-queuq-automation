Describe 'Backfeed result run id behavior' {
    BeforeAll {
        $root = (Resolve-Path (Join-Path -Path $PSScriptRoot -ChildPath '..\..\..')).Path
        $script:resultModulePath = Join-Path -Path $root -ChildPath 'shared\Backfeed\BackfeedResult.psm1'
        Import-Module -Name $script:resultModulePath -Force -DisableNameChecking
    }

    It 'result contains BackfeedRunId' {
        $result = New-BackfeedResult -BackfeedType 'MailboxPermission' -Mode 'Full' -Status 'Succeeded'
        @($result.PSObject.Properties.Name) | Should -Contain 'BackfeedRunId'
    }

    It 'result uses explicit BackfeedRunId' {
        $expected = 'dddddddd-dddd-dddd-dddd-dddddddddddd'
        $result = New-BackfeedResult -BackfeedRunId $expected -BackfeedType 'MailboxPermission' -Mode 'Delta' -Status 'Succeeded'
        $result.BackfeedRunId | Should -Be $expected
    }

    It 'result output json contains BackfeedRunId' {
        $expected = 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee'
        $result = New-BackfeedResult -BackfeedRunId $expected -BackfeedType 'MailboxPermission' -Mode 'Full' -Status 'Failed'
        $json = $result | ConvertTo-Json -Depth 20 -Compress
        { $json | ConvertFrom-Json | Out-Null } | Should -Not -Throw
        ($json | ConvertFrom-Json).BackfeedRunId | Should -Be $expected
    }
}
