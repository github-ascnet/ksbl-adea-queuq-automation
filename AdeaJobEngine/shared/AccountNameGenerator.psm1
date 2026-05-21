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

function Get-NextAvailableSamAccountName {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][ValidateSet('gmb', 'us', 'ex')][string]$Prefix,
        [switch]$UseHighestPlusOne
    )

    $normalizedPrefix = $Prefix.ToLowerInvariant()
    $prefixConfig = @{
        gmb = @{ StartValue = 1; Width = 4; MaxValue = 9999 }
        us  = @{ StartValue = 10000; Width = 5; MaxValue = 99999 }
        ex  = @{ StartValue = 100; Width = 5; MaxValue = 99999 }
    }

    $config = $prefixConfig[$normalizedPrefix]
    $existingNames = @(Get-AdSamAccountNamesByPrefix -Prefix $normalizedPrefix)

    $regex = '^' + [regex]::Escape($normalizedPrefix) + '(\d+)$'
    $numbers = @()
    foreach ($name in $existingNames) {
        if ([string]::IsNullOrWhiteSpace($name)) { continue }
        $match = [regex]::Match($name.ToLowerInvariant(), $regex)
        if (-not $match.Success) { continue }

        $value = [int]$match.Groups[1].Value
        if ($value -lt $config.StartValue -or $value -gt $config.MaxValue) { continue }
        $numbers += $value
    }

    $numbers = @($numbers | Sort-Object -Unique)

    if ($UseHighestPlusOne.IsPresent) {
        $nextNumber = if ($numbers.Count -gt 0) { ($numbers | Measure-Object -Maximum).Maximum + 1 } else { $config.StartValue }
    }
    else {
        $nextNumber = $config.StartValue
        foreach ($value in $numbers) {
            if ($value -eq $nextNumber) {
                $nextNumber++
                continue
            }
            if ($value -gt $nextNumber) { break }
        }
    }

    if ($nextNumber -gt $config.MaxValue) {
        throw "Der Nummernkreis fuer Prefix '$normalizedPrefix' ist ausgeschoepft. Maximalwert: $($config.MaxValue)."
    }

    $nextNumber = [int]$nextNumber
    $numberText = $nextNumber.ToString(('D{0}' -f $config.Width))
    ('{0}{1}' -f $normalizedPrefix, $numberText)
}

function Get-NextAvailableAccountName {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$BaseName)

    $trimmed = $BaseName.Trim()
    if ([string]::IsNullOrWhiteSpace($trimmed)) {
        throw 'BaseName must not be empty.'
    }

    $lower = $trimmed.ToLowerInvariant()
    if ($lower -match '^(gmb|us|ex)') {
        return Get-NextAvailableSamAccountName -Prefix $matches[1]
    }

    throw "Unknown prefix in BaseName '$BaseName'. Expected gmb, us, or ex."
}

Export-ModuleMember -Function @(
    'New-AccountNameCandidate',
    'Get-NextAvailableSamAccountName',
    'Get-NextAvailableAccountName'
)
