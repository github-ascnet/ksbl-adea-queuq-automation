Set-StrictMode -Version Latest

function Test-NonEmptyString {
    [CmdletBinding()]
    param([AllowNull()][AllowEmptyString()][string]$Value)

    -not [string]::IsNullOrWhiteSpace($Value)
}

function Assert-NonEmptyString {
    [CmdletBinding()]
    param(
        [AllowNull()][AllowEmptyString()][string]$Value,
        [Parameter(Mandatory = $true)][string]$FieldName
    )

    if (-not (Test-NonEmptyString -Value $Value)) {
        throw "Field '$FieldName' is required and must not be empty."
    }
}

function Test-EmailAddressFormat {
    [CmdletBinding()]
    param([string]$Email)

    if ([string]::IsNullOrWhiteSpace($Email)) {
        return $false
    }

    $pattern = '^[^@\s]+@[^@\s]+\.[^@\s]+$'
    [bool]($Email -match $pattern)
}

function Test-RequiredCsvFields {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][object[]]$Rows,
        [Parameter(Mandatory = $true)][string[]]$RequiredFields,
        [switch]$AllowEmptyValues
    )

    if (-not $Rows -or $Rows.Count -eq 0) {
        return $false
    }

    $first = $Rows[0]
    $props = @($first.PSObject.Properties.Name)
    foreach ($field in $RequiredFields) {
        if ($props -notcontains $field) {
            return $false
        }
    }

    if (-not $AllowEmptyValues) {
        foreach ($row in $Rows) {
            foreach ($field in $RequiredFields) {
                $value = $row.$field
                if ($null -eq $value -or [string]::IsNullOrWhiteSpace([string]$value)) {
                    return $false
                }
            }
        }
    }

    return $true
}

function Assert-RequiredCsvFields {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][object[]]$Rows,
        [Parameter(Mandatory = $true)][string[]]$RequiredFields,
        [switch]$AllowEmptyValues
    )

    if (-not $Rows -or $Rows.Count -eq 0) {
        throw 'CSV payload is empty.'
    }

    $first = $Rows[0]
    $props = @($first.PSObject.Properties.Name)

    $missing = @()
    foreach ($field in $RequiredFields) {
        if ($props -notcontains $field) {
            $missing += $field
        }
    }

    if ($missing.Count -gt 0) {
        throw "CSV missing required field(s): $($missing -join ', ')."
    }

    if (-not $AllowEmptyValues) {
        for ($i = 0; $i -lt $Rows.Count; $i++) {
            $row = $Rows[$i]
            foreach ($field in $RequiredFields) {
                $value = $row.$field
                if ($null -eq $value -or [string]::IsNullOrWhiteSpace([string]$value)) {
                    $rowNumber = $i + 1
                    throw "CSV row $rowNumber missing required value for field '$field'."
                }
            }
        }
    }
}

Export-ModuleMember -Function @(
    'Assert-RequiredCsvFields',
    'Test-RequiredCsvFields',
    'Test-EmailAddressFormat',
    'Test-NonEmptyString',
    'Assert-NonEmptyString'
)
