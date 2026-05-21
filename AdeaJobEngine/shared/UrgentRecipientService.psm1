Set-StrictMode -Version Latest

function Get-UrgentRecipientAllowedAttributes {
    @{
        'extensionattribute6'            = 'extensionAttribute6'
        'msds-cloudextensionattribute15' = 'msDS-cloudExtensionAttribute15'
        'description'                    = 'Description'
        'targetaddress'                  = 'targetAddress'
        'mail'                           = 'mail'
        'msexchhidefromaddresslists'     = 'msExchHideFromAddressLists'
    }
}

function Resolve-UrgentRecipientOperation {
    [CmdletBinding()]
    param(
        [string]$Operation,
        [string]$AttributeValue
    )

    if (-not [string]::IsNullOrWhiteSpace($Operation)) {
        switch ($Operation.Trim().ToUpperInvariant()) {
            'SET' { return 'Set' }
            'CLEAR' { return 'Clear' }
            default { throw "Unsupported operation '$Operation'. Use Set or Clear." }
        }
    }

    if ([string]::IsNullOrWhiteSpace($AttributeValue)) { return 'Clear' }
    'Set'
}

function Set-UrgentRecipientAttribute {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][object]$Context,
        [Parameter(Mandatory = $true)][string]$Identity,
        [Parameter(Mandatory = $true)][string]$AttributeName,
        [AllowNull()][AllowEmptyString()][string]$AttributeValue,
        [string]$Operation
    )

    if ([string]::IsNullOrWhiteSpace($Identity)) {
        return [pscustomobject]@{ Success = $false; Changed = $false; Identity = $Identity; AttributeName = $AttributeName; Operation = $Operation; Message = 'Identity is required.'; ErrorCode = 'URGENT_RECIPIENT_ATTRIBUTE_INVALID_INPUT' }
    }

    if ([string]::IsNullOrWhiteSpace($AttributeName)) {
        return [pscustomobject]@{ Success = $false; Changed = $false; Identity = $Identity; AttributeName = $AttributeName; Operation = $Operation; Message = 'AttributeName is required.'; ErrorCode = 'URGENT_RECIPIENT_ATTRIBUTE_INVALID_INPUT' }
    }

    $allowed = Get-UrgentRecipientAllowedAttributes
    $key = $AttributeName.Trim().ToLowerInvariant()
    if (-not $allowed.ContainsKey($key)) {
        return [pscustomobject]@{ Success = $false; Changed = $false; Identity = $Identity; AttributeName = $AttributeName; Operation = $Operation; Message = "Attribute '$AttributeName' is not supported."; ErrorCode = 'UNSUPPORTED_ATTRIBUTE' }
    }

    $canonicalName = $allowed[$key]
    try {
        $resolvedOperation = Resolve-UrgentRecipientOperation -Operation $Operation -AttributeValue $AttributeValue
    }
    catch {
        return [pscustomobject]@{ Success = $false; Changed = $false; Identity = $Identity; AttributeName = $canonicalName; Operation = $Operation; Message = $_.Exception.Message; ErrorCode = 'URGENT_RECIPIENT_ATTRIBUTE_INVALID_OPERATION' }
    }

    try {
        if ($resolvedOperation -eq 'Clear') {
            $params = @{ Identity = $Identity; Clear = @($canonicalName) }
            Set-AdUserSafe -Parameters $params -WhatIfMode:$Context.WhatIfMode | Out-Null
        }
        else {
            $params = @{ Identity = $Identity }
            $params[$canonicalName] = $AttributeValue
            Set-AdUserSafe -Parameters $params -WhatIfMode:$Context.WhatIfMode | Out-Null
        }
    }
    catch {
        $message = if ($_.Exception.InnerException) { $_.Exception.InnerException.Message } else { $_.Exception.Message }
        return [pscustomobject]@{ Success = $false; Changed = $false; Identity = $Identity; AttributeName = $canonicalName; Operation = $resolvedOperation; Message = $message; ErrorCode = 'URGENT_RECIPIENT_ATTRIBUTE_CHANGE_FAILED' }
    }

    [pscustomobject]@{ Success = $true; Changed = $true; Identity = $Identity; AttributeName = $canonicalName; Operation = $resolvedOperation; Message = "Attribute '$canonicalName' $resolvedOperation for '$Identity'."; ErrorCode = $null }
}

Export-ModuleMember -Function @(
    'Get-UrgentRecipientAllowedAttributes',
    'Resolve-UrgentRecipientOperation',
    'Set-UrgentRecipientAttribute'
)
