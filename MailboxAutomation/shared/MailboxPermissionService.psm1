Set-StrictMode -Version Latest

function New-PermissionOperationResult {
    param(
        [Parameter(Mandatory = $true)][bool]$Success,
        [bool]$Changed             = $false,
        [bool]$RequiresRetry       = $false,
        [int]$RetryAfterMinutes    = 0,
        [string]$Authority         = 'Unknown',
        [string]$Identity          = '',
        [string]$Trustee           = '',
        [string]$Operation         = '',
        [string]$Message           = '',
        [string]$ErrorCode         = $null
    )
    [pscustomobject]@{
        Success           = $Success
        Changed           = $Changed
        RequiresRetry     = $RequiresRetry
        RetryAfterMinutes = $RetryAfterMinutes
        Authority         = $Authority
        Identity          = $Identity
        Trustee           = $Trustee
        Operation         = $Operation
        Message           = $Message
        ErrorCode         = $ErrorCode
    }
}

function Invoke-ResolvedPermissionGateway {
    # Internal routing helper: resolves execution context, then delegates to the correct gateway.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][object]$Context,
        [Parameter(Mandatory = $true)][string]$MailboxIdentity,
        [Parameter(Mandatory = $true)][string]$Trustee,
        [Parameter(Mandatory = $true)][string]$Operation,
        [hashtable]$ExtraParams = @{}
    )

    $exec = Resolve-MailboxExecutionContext -Identity $MailboxIdentity -Config $Context.Config

    # Transient migration state: schedule a retry
    if ($exec.RecommendedAction -eq 'Retry') {
        return New-PermissionOperationResult `
            -Success $false -RequiresRetry $true `
            -RetryAfterMinutes $exec.RetryAfterMinutes `
            -Authority $exec.PermissionAuthority `
            -Identity $MailboxIdentity -Trustee $Trustee -Operation $Operation `
            -Message $exec.Reason -ErrorCode 'MAILBOX_MIGRATION_TRANSIENT'
    }

    # Hard failure: mailbox not found or EXO required but disabled
    if ($exec.RecommendedAction -eq 'Fail') {
        $exoEnabled = (
            $Context.Config.ContainsKey('ExchangeOnline') -and
            $Context.Config['ExchangeOnline'] -is [hashtable] -and
            $Context.Config['ExchangeOnline'].ContainsKey('Enabled') -and
            [bool]$Context.Config['ExchangeOnline']['Enabled']
        )
        $errorCode = if ($exec.PermissionAuthority -eq 'ExchangeOnline' -and -not $exoEnabled) {
            'EXO_REQUIRED_BUT_DISABLED'
        }
        else {
            'MAILBOX_NOT_FOUND'
        }
        return New-PermissionOperationResult `
            -Success $false `
            -Authority $exec.PermissionAuthority `
            -Identity $MailboxIdentity -Trustee $Trustee -Operation $Operation `
            -Message $exec.Reason -ErrorCode $errorCode
    }

    # Execute: route to the correct gateway based on resolved authority
    try {
        switch ($Operation) {
            'FullAccess-Add' {
                $params = @{
                    Identity        = $MailboxIdentity
                    User            = $Trustee
                    AccessRights    = 'FullAccess'
                    InheritanceType = 'All'
                }
                if ($ExtraParams.ContainsKey('AutoMapping')) { $params['AutoMapping'] = $ExtraParams['AutoMapping'] }
                switch ($exec.PermissionAuthority) {
                    'OnPremExchange' { Add-OnPremMailboxPermissionSafe -Parameters $params -WhatIfMode:$Context.WhatIfMode | Out-Null }
                    'ExchangeOnline' { Add-ExoMailboxPermissionSafe -Parameters $params -Config $Context.Config -WhatIfMode:$Context.WhatIfMode | Out-Null }
                    default {
                        return New-PermissionOperationResult -Success $false -Authority $exec.PermissionAuthority -Identity $MailboxIdentity -Trustee $Trustee -Operation $Operation -Message "Unknown PermissionAuthority '$($exec.PermissionAuthority)' for '$MailboxIdentity'." -ErrorCode 'PERMISSION_AUTHORITY_UNKNOWN'
                    }
                }
            }
            'FullAccess-Remove' {
                $params = @{ Identity = $MailboxIdentity; User = $Trustee; AccessRights = 'FullAccess'; Confirm = $false }
                switch ($exec.PermissionAuthority) {
                    'OnPremExchange' { Remove-OnPremMailboxPermissionSafe -Parameters $params -WhatIfMode:$Context.WhatIfMode | Out-Null }
                    'ExchangeOnline' { Remove-ExoMailboxPermissionSafe -Parameters $params -Config $Context.Config -WhatIfMode:$Context.WhatIfMode | Out-Null }
                    default {
                        return New-PermissionOperationResult -Success $false -Authority $exec.PermissionAuthority -Identity $MailboxIdentity -Trustee $Trustee -Operation $Operation -Message "Unknown PermissionAuthority '$($exec.PermissionAuthority)' for '$MailboxIdentity'." -ErrorCode 'PERMISSION_AUTHORITY_UNKNOWN'
                    }
                }
            }
            'SendAs-Add' {
                $params = @{ Identity = $MailboxIdentity; Trustee = $Trustee; AccessRights = 'SendAs'; Confirm = $false }
                switch ($exec.PermissionAuthority) {
                    'OnPremExchange' { Add-OnPremSendAsPermissionSafe -Parameters $params -WhatIfMode:$Context.WhatIfMode | Out-Null }
                    'ExchangeOnline' { Add-ExoSendAsPermissionSafe -Parameters $params -Config $Context.Config -WhatIfMode:$Context.WhatIfMode | Out-Null }
                    default {
                        return New-PermissionOperationResult -Success $false -Authority $exec.PermissionAuthority -Identity $MailboxIdentity -Trustee $Trustee -Operation $Operation -Message "Unknown PermissionAuthority '$($exec.PermissionAuthority)' for '$MailboxIdentity'." -ErrorCode 'PERMISSION_AUTHORITY_UNKNOWN'
                    }
                }
            }
            'SendAs-Remove' {
                $params = @{ Identity = $MailboxIdentity; Trustee = $Trustee; AccessRights = 'SendAs'; Confirm = $false }
                switch ($exec.PermissionAuthority) {
                    'OnPremExchange' { Remove-OnPremSendAsPermissionSafe -Parameters $params -WhatIfMode:$Context.WhatIfMode | Out-Null }
                    'ExchangeOnline' { Remove-ExoSendAsPermissionSafe -Parameters $params -Config $Context.Config -WhatIfMode:$Context.WhatIfMode | Out-Null }
                    default {
                        return New-PermissionOperationResult -Success $false -Authority $exec.PermissionAuthority -Identity $MailboxIdentity -Trustee $Trustee -Operation $Operation -Message "Unknown PermissionAuthority '$($exec.PermissionAuthority)' for '$MailboxIdentity'." -ErrorCode 'PERMISSION_AUTHORITY_UNKNOWN'
                    }
                }
            }
            default {
                return New-PermissionOperationResult -Success $false -Authority 'Unknown' -Identity $MailboxIdentity -Trustee $Trustee -Operation $Operation -Message "Unknown operation '$Operation'." -ErrorCode 'UNKNOWN_OPERATION'
            }
        }

        return New-PermissionOperationResult -Success $true -Changed $true -Authority $exec.PermissionAuthority -Identity $MailboxIdentity -Trustee $Trustee -Operation $Operation -Message "$Operation completed via $($exec.PermissionAuthority)."
    }
    catch {
        return New-PermissionOperationResult -Success $false -Authority $exec.PermissionAuthority -Identity $MailboxIdentity -Trustee $Trustee -Operation $Operation -Message $_.Exception.Message -ErrorCode 'GATEWAY_ERROR'
    }
}

function Add-MailboxFullAccess {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][object]$Context,
        [Parameter(Mandatory = $true)][string]$MailboxIdentity,
        [Parameter(Mandatory = $true)][string]$Trustee,
        [bool]$AutoMapping = $false
    )
    Invoke-ResolvedPermissionGateway -Context $Context -MailboxIdentity $MailboxIdentity -Trustee $Trustee -Operation 'FullAccess-Add' -ExtraParams @{ AutoMapping = $AutoMapping }
}

function Remove-MailboxFullAccess {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][object]$Context,
        [Parameter(Mandatory = $true)][string]$MailboxIdentity,
        [Parameter(Mandatory = $true)][string]$Trustee
    )
    Invoke-ResolvedPermissionGateway -Context $Context -MailboxIdentity $MailboxIdentity -Trustee $Trustee -Operation 'FullAccess-Remove'
}

function Add-MailboxSendAs {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][object]$Context,
        [Parameter(Mandatory = $true)][string]$MailboxIdentity,
        [Parameter(Mandatory = $true)][string]$Trustee
    )
    Invoke-ResolvedPermissionGateway -Context $Context -MailboxIdentity $MailboxIdentity -Trustee $Trustee -Operation 'SendAs-Add'
}

function Remove-MailboxSendAs {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][object]$Context,
        [Parameter(Mandatory = $true)][string]$MailboxIdentity,
        [Parameter(Mandatory = $true)][string]$Trustee
    )
    Invoke-ResolvedPermissionGateway -Context $Context -MailboxIdentity $MailboxIdentity -Trustee $Trustee -Operation 'SendAs-Remove'
}

Export-ModuleMember -Function @('Add-MailboxFullAccess','Remove-MailboxFullAccess','Add-MailboxSendAs','Remove-MailboxSendAs')
