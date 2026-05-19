$modulePath = Join-Path -Path $PSScriptRoot -ChildPath '..\..\core\JobResult.psm1'
Import-Module -Name $modulePath -Force

Describe 'JobResult' {
    It 'accepts valid status values' {
        $result = New-JobResult -Status 'Succeeded' -Message 'ok'
        $result.Status | Should -Be 'Succeeded'
    }

    It 'rejects invalid status values' {
        { New-JobResult -Status 'UnknownStatus' -Message 'no' } | Should -Throw
    }

    It 'sets RetryAfter in retry result' {
        $dt = (Get-Date).AddMinutes(15)
        $result = New-JobRetryResult -RetryAfter $dt
        $result.Status | Should -Be 'Retry'
        $result.RetryAfter | Should -Be $dt
    }

    It 'sets ResumeAfter in paused result' {
        $dt = (Get-Date).AddMinutes(30)
        $result = New-JobPausedResult -ResumeAfter $dt
        $result.Status | Should -Be 'Paused'
        $result.ResumeAfter | Should -Be $dt
    }
}
