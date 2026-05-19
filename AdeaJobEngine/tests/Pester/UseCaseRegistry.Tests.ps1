Describe 'UseCase registry integrity' {
    BeforeAll {
        $root = (Resolve-Path (Join-Path -Path $PSScriptRoot -ChildPath '..\..')).Path
        $registryPath = Join-Path -Path $root -ChildPath 'config\usecases.json'
        $registry = Get-Content -Path $registryPath -Raw | ConvertFrom-Json
        $enabled = @($registry.UseCases | Where-Object { $_.Enabled })
        $disabled = @($registry.UseCases | Where-Object { -not $_.Enabled })
    }

    It 'has exactly 19 active use cases' {
        $enabled.Count | Should -Be 19
    }

    It 'has exactly 9 disabled invented use cases' {
        $disabled.Count | Should -Be 9
    }

    It 'has no active use case on invalid queue longrunning' {
        (@($enabled | Where-Object { $_.Queue -eq 'longrunning' }).Count) | Should -Be 0
    }

    It 'has exactly one active SupportsPause use case' {
        $pauseEnabled = @($enabled | Where-Object { $_.SupportsPause })
        $pauseEnabled.Count | Should -Be 1
        $pauseEnabled[0].Name | Should -Be 'PersonMailbox.CreateNonStandard'
    }

    It 'PersonMailbox.CreateNonStandard uses person-mailbox-longrunning queue' {
        $uc = $registry.UseCases | Where-Object { $_.Name -eq 'PersonMailbox.CreateNonStandard' }
        $uc.Queue | Should -Be 'person-mailbox-longrunning'
    }

    It 'Urgent.InactivateHospisPerson uses urgent queue' {
        $uc = $registry.UseCases | Where-Object { $_.Name -eq 'Urgent.InactivateHospisPerson' }
        $uc.Queue | Should -Be 'urgent'
    }

    It 'UserPerson.HospisPersonUseCase does not require AdObjectName in base fields' {
        $uc = $registry.UseCases | Where-Object { $_.Name -eq 'UserPerson.HospisPersonUseCase' }
        (($uc.RequiredFields -contains 'AdObjectName')) | Should -Be $false
    }
}
