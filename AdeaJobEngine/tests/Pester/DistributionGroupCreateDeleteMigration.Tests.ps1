BeforeAll {
    $root = (Resolve-Path (Join-Path -Path $PSScriptRoot -ChildPath '..\..')).Path

    Import-Module -Name (Join-Path $root 'core\JobResult.psm1') -Force -DisableNameChecking
    Import-Module -Name (Join-Path $root 'core\Validation.psm1') -Force -DisableNameChecking
    Import-Module -Name (Join-Path $root 'core\Logging.psm1') -Force -DisableNameChecking
    Import-Module -Name (Join-Path $root 'infrastructure\ActiveDirectoryGateway.psm1') -Force -DisableNameChecking
    Import-Module -Name (Join-Path $root 'infrastructure\ExchangeOnPremGateway.psm1') -Force -DisableNameChecking
    Import-Module -Name (Join-Path $root 'shared\DistributionGroupService.psm1') -Force -DisableNameChecking
    Import-Module -Name (Join-Path $root 'usecases\DistributionGroup\CreateDistributionGroup.psm1') -Force -DisableNameChecking
    Import-Module -Name (Join-Path $root 'usecases\DistributionGroup\DeleteDistributionList.psm1') -Force -DisableNameChecking

    function New-TestLogger {
        [pscustomobject]@{
            RunId           = 'test'
            LogFile         = (Join-Path $TestDrive 'test.log')
            ConsoleEnabled  = $false
            FileEnabled     = $false
            EventLogEnabled = $false
            EventLogName    = 'Application'
            EventSource     = 'AdeaJobEngine.Tests'
            VerboseLogging  = $false
        }
    }

    function New-CreateDistributionGroupRow {
        [pscustomobject]@{
            ActionType              = 'CreateDistributionList'
            DisplayName             = 'Test Verteilerliste'
            PrimarySmtpAddress      = 'testvl@ksbl.ch'
            AdObjectName            = 'vl-test'
            OrgUnit                 = 'OU=Verteilerlisten,DC=ksbl,DC=local'
            HideInAb                = 'true'
            Manager                 = 'us-manager[ADD]'
            CurrentUserName         = 'Requester'
            CurrentUserDomainName   = 'KSBL'
            CurrentUserEMailAddress = 'requester@ksbl.ch'
        }
    }

    function New-DeleteDistributionGroupRow {
        [pscustomobject]@{
            ActionType              = 'DeleteDistribList'
            AdObjectName            = 'vl-test'
            CurrentUserName         = 'Requester'
            CurrentUserDomainName   = 'KSBL'
            CurrentUserEMailAddress = 'requester@ksbl.ch'
        }
    }
}

Describe 'DistributionGroup.Create handler' {
    It 'Returns Succeeded when service succeeds' {
        $context = [pscustomobject]@{
            Payload    = @(New-CreateDistributionGroupRow)
            Logger     = New-TestLogger
            WhatIfMode = $true
            Services   = @{
                DistributionGroup = [pscustomobject]@{
                    Create = { param($Context, $Data) [pscustomobject]@{ Success = $true; Changed = $true; Message = 'created'; ErrorCode = $null } }
                }
            }
        }

        $result = Invoke-CreateDistributionGroup -Context $context
        $result.Status | Should -Be 'Succeeded'
        $result.Output.Count | Should -Be 1
    }

    It 'Returns Failed when service fails for one row' {
        $context = [pscustomobject]@{
            Payload    = @(New-CreateDistributionGroupRow)
            Logger     = New-TestLogger
            WhatIfMode = $true
            Services   = @{
                DistributionGroup = [pscustomobject]@{
                    Create = { param($Context, $Data) [pscustomobject]@{ Success = $false; Changed = $false; Message = 'exchange error'; ErrorCode = 'DISTRIBUTION_GROUP_CREATE_FAILED' } }
                }
            }
        }

        $result = Invoke-CreateDistributionGroup -Context $context
        $result.Status | Should -Be 'Failed'
        $result.ErrorCode | Should -Be 'DISTRIBUTION_GROUP_CREATE_FAILED'
        $result.Output.Count | Should -Be 1
    }

    It 'Throws on missing required field and returns Failed' {
        $incompleteRow = [pscustomobject]@{
            ActionType    = 'CreateDistributionList'
            DisplayName   = ''
            AdObjectName  = 'vl-test'
        }
        $context = [pscustomobject]@{
            Payload    = @($incompleteRow)
            Logger     = New-TestLogger
            WhatIfMode = $true
            Services   = @{ DistributionGroup = [pscustomobject]@{ Create = { } } }
        }

        $result = Invoke-CreateDistributionGroup -Context $context
        $result.Status | Should -Be 'Failed'
        $result.ErrorCode | Should -Be 'USECASE_ERROR'
    }

    It 'Accumulates results for multiple rows' {
        $row1 = New-CreateDistributionGroupRow
        $row2 = New-CreateDistributionGroupRow
        $row2.AdObjectName = 'vl-test-2'
        $row2.DisplayName = 'Test VL 2'
        $context = [pscustomobject]@{
            Payload    = @($row1, $row2)
            Logger     = New-TestLogger
            WhatIfMode = $true
            Services   = @{
                DistributionGroup = [pscustomobject]@{
                    Create = { param($Context, $Data) [pscustomobject]@{ Success = $true; Changed = $true; Message = 'created'; ErrorCode = $null } }
                }
            }
        }

        $result = Invoke-CreateDistributionGroup -Context $context
        $result.Status | Should -Be 'Succeeded'
        $result.Output.Count | Should -Be 2
    }
}

Describe 'DistributionGroup.Delete handler' {
    It 'Returns Succeeded when service succeeds' {
        $context = [pscustomobject]@{
            Payload    = @(New-DeleteDistributionGroupRow)
            Logger     = New-TestLogger
            WhatIfMode = $true
            Services   = @{
                DistributionGroup = [pscustomobject]@{
                    Delete = { param($Context, $Data) [pscustomobject]@{ Success = $true; Changed = $true; Message = 'deleted'; ErrorCode = $null } }
                }
            }
        }

        $result = Invoke-DeleteDistributionList -Context $context
        $result.Status | Should -Be 'Succeeded'
        $result.Output.Count | Should -Be 1
    }

    It 'Returns Failed when service fails' {
        $context = [pscustomobject]@{
            Payload    = @(New-DeleteDistributionGroupRow)
            Logger     = New-TestLogger
            WhatIfMode = $true
            Services   = @{
                DistributionGroup = [pscustomobject]@{
                    Delete = { param($Context, $Data) [pscustomobject]@{ Success = $false; Changed = $false; Message = 'not found'; ErrorCode = 'DISTRIBUTION_GROUP_NOT_FOUND' } }
                }
            }
        }

        $result = Invoke-DeleteDistributionList -Context $context
        $result.Status | Should -Be 'Failed'
        $result.ErrorCode | Should -Be 'DISTRIBUTION_GROUP_DELETE_FAILED'
    }

    It 'Throws on missing required field and returns Failed' {
        $incompleteRow = [pscustomobject]@{
            ActionType   = 'DeleteDistribList'
            AdObjectName = ''
        }
        $context = [pscustomobject]@{
            Payload    = @($incompleteRow)
            Logger     = New-TestLogger
            WhatIfMode = $true
            Services   = @{ DistributionGroup = [pscustomobject]@{ Delete = { } } }
        }

        $result = Invoke-DeleteDistributionList -Context $context
        $result.Status | Should -Be 'Failed'
        $result.ErrorCode | Should -Be 'USECASE_ERROR'
    }
}

Describe 'New-DistributionGroupFromRequest service (WhatIfMode)' {
    It 'Returns simulated result with all expected operations' {
        $context = [pscustomobject]@{ Logger = New-TestLogger; WhatIfMode = $true }
        $result = New-DistributionGroupFromRequest -Context $context -Data (New-CreateDistributionGroupRow)

        $result.Success   | Should -Be $true
        $result.Simulated | Should -Be $true
        $result.Changed   | Should -Be $true
        $result.AdObjectName | Should -Be 'vl-test'
        $result.DisplayName  | Should -Be 'Test Verteilerliste'
        $result.Operations | Should -Not -BeNullOrEmpty
        @($result.Operations | Where-Object Action -eq 'New-DistributionGroup').Count | Should -Be 1
    }

    It 'Strips action token from Manager field' {
        $context = [pscustomobject]@{ Logger = New-TestLogger; WhatIfMode = $true }
        $row = New-CreateDistributionGroupRow
        $row.Manager = 'us-boss[ADD]'
        $result = New-DistributionGroupFromRequest -Context $context -Data $row

        $managerOp = $result.Operations | Where-Object Action -eq 'Set-DistributionGroup-ManagedBy'
        $managerOp.Manager | Should -Be 'us-boss'
    }

    It 'Returns Success=true in WhatIfMode even when Exchange is unavailable' {
        $context = [pscustomobject]@{ Logger = New-TestLogger; WhatIfMode = $true }
        $result = New-DistributionGroupFromRequest -Context $context -Data (New-CreateDistributionGroupRow)

        $result.Success | Should -Be $true
    }
}

Describe 'Remove-DistributionGroupFromRequest service (WhatIfMode)' {
    It 'Returns simulated result with expected operations' {
        $context = [pscustomobject]@{ Logger = New-TestLogger; WhatIfMode = $true }
        $result = Remove-DistributionGroupFromRequest -Context $context -Data (New-DeleteDistributionGroupRow)

        $result.Success      | Should -Be $true
        $result.Simulated    | Should -Be $true
        $result.Changed      | Should -Be $true
        $result.AdObjectName | Should -Be 'vl-test'
        $result.Operations | Should -Not -BeNullOrEmpty
        @($result.Operations | Where-Object Action -eq 'Remove-DistributionGroup').Count | Should -Be 1
    }

    It 'Returns Success=true in WhatIfMode even when Exchange is unavailable' {
        $context = [pscustomobject]@{ Logger = New-TestLogger; WhatIfMode = $true }
        $result = Remove-DistributionGroupFromRequest -Context $context -Data (New-DeleteDistributionGroupRow)

        $result.Success | Should -Be $true
    }
}

Describe 'New-OnPremDistributionGroupSafe gateway (WhatIfMode)' {
    It 'Returns simulated result without calling Exchange' {
        $params = @{ Name = 'TestVL'; Alias = 'vl-test'; Type = 'Security' }
        $result = New-OnPremDistributionGroupSafe -Parameters $params -WhatIfMode:$true

        $result.Simulated | Should -Be $true
        $result.Action    | Should -Be 'New-DistributionGroup'
    }
}

Describe 'Remove-OnPremDistributionGroupSafe gateway (WhatIfMode)' {
    It 'Returns simulated result without calling Exchange' {
        $params = @{ Identity = 'vl-test'; Confirm = $false }
        $result = Remove-OnPremDistributionGroupSafe -Parameters $params -WhatIfMode:$true

        $result.Simulated | Should -Be $true
        $result.Action    | Should -Be 'Remove-DistributionGroup'
    }
}
