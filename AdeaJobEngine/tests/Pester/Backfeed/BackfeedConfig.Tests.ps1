Describe 'Backfeed config' {
    BeforeAll {
        $root = (Resolve-Path (Join-Path -Path $PSScriptRoot -ChildPath '..\..\..')).Path
        $script:backfeedConfigPath = Join-Path -Path $root -ChildPath 'config\backfeed.json'
        $script:config = Get-Content -Path $script:backfeedConfigPath -Raw | ConvertFrom-Json
    }

    It 'exists and is parseable' {
        Test-Path -Path $script:backfeedConfigPath | Should -Be $true
        $script:config | Should -Not -BeNullOrEmpty
    }

    It 'contains User, Group and MailboxPermission sections' {
        ($script:config.BackfeedTypes.PSObject.Properties.Name -contains 'User') | Should -Be $true
        ($script:config.BackfeedTypes.PSObject.Properties.Name -contains 'Group') | Should -Be $true
        ($script:config.BackfeedTypes.PSObject.Properties.Name -contains 'MailboxPermission') | Should -Be $true
    }

    It 'contains the required top level settings' {
        $script:config.Enabled | Should -Be $true
        $script:config.DefaultMode | Should -Be 'Delta'
        $script:config.DefaultEnvironment | Should -Be 'TODO'
        $script:config.BatchSize | Should -Be 1000
        $script:config.UseHashComparison | Should -Be $false
        $script:config.UseWatermark | Should -Be $false
        $script:config.WriteHistory | Should -Be $false
    }

    It 'only uses confirmed table and key values where known' {
        $script:config.BackfeedTypes.User.StagingTable | Should -Be 'stg_UsersBackfeed_AccountsDelta'
        $script:config.BackfeedTypes.User.DeletedStagingTable | Should -Be 'stg_UsersBackfeed_Deleted'
        $script:config.BackfeedTypes.User.TargetTable | Should -Be 'Accounts'
        $script:config.BackfeedTypes.Group.StagingTables.Groups | Should -Be 'stg_Groups'
        $script:config.BackfeedTypes.Group.StagingTables.Members | Should -Be 'stg_GroupMembers'
        $script:config.BackfeedTypes.Group.StagingTables.Managers | Should -Be 'stg_GroupManagers'
        $script:config.BackfeedTypes.Group.TargetTables.Groups | Should -Be 'Groups'
        $script:config.BackfeedTypes.Group.TargetTables.AccountsToGroups | Should -Be 'AccountsToGroups'
        $script:config.BackfeedTypes.Group.TargetTables.ManagersToGroups | Should -Be 'ManagersToGroups'
        $script:config.BackfeedTypes.MailboxPermission.StagingTable | Should -Be 'stg_MailboxPermissions'
        $script:config.BackfeedTypes.MailboxPermission.TargetTable | Should -Be 'MailboxPermissions'
        $script:config.BackfeedTypes.User.Key.Primary | Should -Be 'AdReferenceObjectGuid'
        $script:config.BackfeedTypes.Group.Key.Primary | Should -Be 'AdReferenceObjectGuid'
        $script:config.BackfeedTypes.MailboxPermission.Key.Primary | Should -Be 'AdReferenceObjectGuid'
    }
}