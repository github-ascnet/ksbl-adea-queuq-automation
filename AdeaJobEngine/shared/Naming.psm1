Set-StrictMode -Version Latest

function Remove-InvalidNameCharacters {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$InputValue)

    ($InputValue -replace '[^a-zA-Z0-9._-]', '')
}

function ConvertTo-SafeAccountName {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$InputValue)

    Remove-InvalidNameCharacters -InputValue $InputValue | ForEach-Object { $_.ToLowerInvariant() }
}

function ConvertTo-SafeAlias {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$InputValue)

    Remove-InvalidNameCharacters -InputValue $InputValue | ForEach-Object { $_.ToLowerInvariant() }
}

Export-ModuleMember -Function @('ConvertTo-SafeAccountName','ConvertTo-SafeAlias','Remove-InvalidNameCharacters')
