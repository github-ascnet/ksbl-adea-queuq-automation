Set-StrictMode -Version Latest

function Ensure-Folder {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -Path $Path)) {
        New-Item -Path $Path -ItemType Directory -Force | Out-Null
    }

    $Path
}

function Move-FileSafe {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Source,
        [Parameter(Mandatory = $true)][string]$Destination,
        [bool]$WhatIfMode = $true
    )

    if ($WhatIfMode) {
        return [pscustomobject]@{ Simulated = $true; Source = $Source; Destination = $Destination }
    }

    Move-Item -Path $Source -Destination $Destination -Force -ErrorAction Stop
}

function Copy-FileSafe {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Source,
        [Parameter(Mandatory = $true)][string]$Destination,
        [bool]$WhatIfMode = $true
    )

    if ($WhatIfMode) {
        return [pscustomobject]@{ Simulated = $true; Source = $Source; Destination = $Destination }
    }

    Copy-Item -Path $Source -Destination $Destination -Force -ErrorAction Stop
}

Export-ModuleMember -Function @('Ensure-Folder','Move-FileSafe','Copy-FileSafe')
