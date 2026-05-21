$modulePath = Join-Path -Path $PSScriptRoot -ChildPath '..\..\core\JobState.psm1'
Import-Module -Name $modulePath -Force -DisableNameChecking

Describe 'PersonMailbox state machine persistence' {
    BeforeAll {
        $script:testRoot = Join-Path -Path $PSScriptRoot -ChildPath '..\state-test'
        if (-not (Test-Path -Path $script:testRoot)) { New-Item -Path $script:testRoot -ItemType Directory -Force | Out-Null }
        $script:jobId = 'testjob001'
        $script:stateFile = Get-JobStatePath -RootPath $script:testRoot -StatePath '.' -JobId $script:jobId
    }

    AfterAll {
        if (Test-Path -Path $script:testRoot) { Remove-Item -Path $script:testRoot -Recurse -Force }
    }

    It 'initializes state' {
        $state = Initialize-JobState -JobId 'testjob001' -UseCase 'PersonMailbox.CreateNonStandard'
        $state.CurrentStep | Should -Be 10
        $state.Status | Should -Be 'Active'
    }

    It 'initializes state with CurrentStepAttempts = 0' {
        $state = Initialize-JobState -JobId 'testjob001' -UseCase 'PersonMailbox.CreateNonStandard'
        $state.CurrentStepAttempts | Should -Be 0
        $state.PreviousStep | Should -Be $null
    }

    It 'saves and loads state' {
        $state = Initialize-JobState -JobId 'testjob001' -UseCase 'PersonMailbox.CreateNonStandard'
        Save-JobState -StateFilePath $script:stateFile -State $state | Out-Null

        $loaded = Get-JobState -StateFilePath $script:stateFile
        $loaded.JobId | Should -Be 'testjob001'
    }

    It 'updates step' {
        $state = Initialize-JobState -JobId 'testjob001' -UseCase 'PersonMailbox.CreateNonStandard'
        $state = Set-JobStateStep -State $state -Step 40 -Message 'waiting'
        $state.CurrentStep | Should -Be 40
    }

    It 'Set-JobStateStep resets CurrentStepAttempts on step change' {
        $state = Initialize-JobState -JobId 'testjob002' -UseCase 'PersonMailbox.CreateNonStandard'
        Increment-JobStateStepAttempt -State $state | Out-Null
        Increment-JobStateStepAttempt -State $state | Out-Null
        $state.CurrentStepAttempts | Should -Be 2

        Set-JobStateStep -State $state -Step 20 -Message 'next' | Out-Null
        $state.CurrentStepAttempts | Should -Be 0
        $state.PreviousStep | Should -Be 10
    }

    It 'Set-JobStateStep does not reset attempts when step is unchanged' {
        $state = Initialize-JobState -JobId 'testjob003' -UseCase 'PersonMailbox.CreateNonStandard'
        Increment-JobStateStepAttempt -State $state | Out-Null
        $state.CurrentStepAttempts | Should -Be 1

        Set-JobStateStep -State $state -Step 10 -Message 'same step' | Out-Null
        $state.CurrentStepAttempts | Should -Be 1
    }

    It 'Increment-JobStateStepAttempt increments CurrentStepAttempts and global Attempts' {
        $state = Initialize-JobState -JobId 'testjob004' -UseCase 'PersonMailbox.CreateNonStandard'
        Increment-JobStateStepAttempt -State $state -Message 'try 1' | Out-Null
        $state.CurrentStepAttempts | Should -Be 1
        $state.Attempts | Should -Be 1
        $state.LastMessage | Should -Be 'try 1'

        Increment-JobStateStepAttempt -State $state -Message 'try 2' | Out-Null
        $state.CurrentStepAttempts | Should -Be 2
        $state.Attempts | Should -Be 2
    }

    It 'GlobalAttempts accumulate across steps while CurrentStepAttempts resets' {
        $state = Initialize-JobState -JobId 'testjob005' -UseCase 'PersonMailbox.CreateNonStandard'
        Increment-JobStateStepAttempt -State $state | Out-Null
        Increment-JobStateStepAttempt -State $state | Out-Null
        $state.Attempts | Should -Be 2

        Set-JobStateStep -State $state -Step 20 | Out-Null
        Increment-JobStateStepAttempt -State $state | Out-Null
        $state.CurrentStepAttempts | Should -Be 1
        $state.Attempts | Should -Be 3
    }

    It 'Complete-JobState sets Status to Completed and sets CompletedAt' {
        $state = Initialize-JobState -JobId 'testjob006' -UseCase 'PersonMailbox.CreateNonStandard'
        Complete-JobState -State $state -Message 'All done.' | Out-Null
        $state.Status | Should -Be 'Completed'
        $state.LastMessage | Should -Be 'All done.'
        $state.CompletedAt | Should -Not -Be $null
    }

    It 'State file path stays identical for same StableJobKey across retries' {
        $path1 = Get-JobStatePath -RootPath $script:testRoot -StatePath '.' -StableJobKey 'CreateNonStdPersonMailbox_myfile_pshjob_'
        $path2 = Get-JobStatePath -RootPath $script:testRoot -StatePath '.' -StableJobKey 'CreateNonStdPersonMailbox_myfile_pshjob_'
        $path1 | Should -Be $path2
    }
}
