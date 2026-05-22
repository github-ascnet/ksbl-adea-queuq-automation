Describe 'Backfeed structure' {
    BeforeAll {
        $root = (Resolve-Path (Join-Path -Path $PSScriptRoot -ChildPath '..\..\..')).Path
        $script:backfeedProcessorPath = Join-Path -Path $root -ChildPath 'backfeed\Invoke-BackfeedProcessor.ps1'
        $script:backfeedConfigPath = Join-Path -Path $root -ChildPath 'config\backfeed.json'
        $script:userServicePath = Join-Path -Path $root -ChildPath 'backfeed\User\UserBackfeedService.psm1'
        $script:groupServicePath = Join-Path -Path $root -ChildPath 'backfeed\Group\GroupBackfeedService.psm1'
        $script:mailboxServicePath = Join-Path -Path $root -ChildPath 'backfeed\MailboxPermission\MailboxPermissionBackfeedService.psm1'
        $script:contextModulePath = Join-Path -Path $root -ChildPath 'shared\Backfeed\BackfeedContext.psm1'
        $script:resultModulePath = Join-Path -Path $root -ChildPath 'shared\Backfeed\BackfeedResult.psm1'
        $script:usecasesPath = Join-Path -Path $root -ChildPath 'config\usecases.json'
        $script:usecasesBackfeedPath = Join-Path -Path $root -ChildPath 'usecases\Backfeed'
        $script:jobEnginePath = Join-Path -Path $root -ChildPath 'core\JobEngine.psm1'
        $script:jobFileQueuePath = Join-Path -Path $root -ChildPath 'core\JobFileQueue.psm1'
    }

    It 'creates the Backfeed processor file' {
        Test-Path -Path $script:backfeedProcessorPath | Should -Be $true
    }

    It 'creates the Backfeed context module' {
        Test-Path -Path $script:contextModulePath | Should -Be $true
    }

    It 'creates the Backfeed result module' {
        Test-Path -Path $script:resultModulePath | Should -Be $true
    }

    It 'creates the user service file' {
        Test-Path -Path $script:userServicePath | Should -Be $true
    }

    It 'creates the group service file' {
        Test-Path -Path $script:groupServicePath | Should -Be $true
    }

    It 'creates the mailbox permission service file' {
        Test-Path -Path $script:mailboxServicePath | Should -Be $true
    }

    It 'does not create a Backfeed usecase folder' {
        Test-Path -Path $script:usecasesBackfeedPath | Should -Be $false
    }

    It 'does not add Backfeed to usecases json' {
        $content = Get-Content -Path $script:usecasesPath -Raw
        $content -match 'Backfeed' | Should -Be $false
    }

    It 'does not add Backfeed logic to JobEngine' {
        $content = Get-Content -Path $script:jobEnginePath -Raw
        $content -match 'Backfeed' | Should -Be $false
    }

    It 'does not use JobFileQueue for Backfeed' {
        $content = Get-Content -Path $script:jobFileQueuePath -Raw
        $content -match 'Backfeed' | Should -Be $false
    }
}