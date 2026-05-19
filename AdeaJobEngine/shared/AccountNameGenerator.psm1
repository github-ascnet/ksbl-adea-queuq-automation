Set-StrictMode -Version Latest

function New-AccountNameCandidate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$GivenName,
        [Parameter(Mandatory = $true)][string]$Surname
    )

    $base = ('{0}.{1}' -f $GivenName, $Surname).ToLowerInvariant()
    ConvertTo-SafeAccountName -InputValue $base
}

function Get-NextAvailableAccountName {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$BaseName)

    # TODO: Migrate legacy logic here
    # Placeholder strategy: return base name as-is.
    ConvertTo-SafeAccountName -InputValue $BaseName
}

Export-ModuleMember -Function @('New-AccountNameCandidate','Get-NextAvailableAccountName')
