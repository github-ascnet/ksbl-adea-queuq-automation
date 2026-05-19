Set-StrictMode -Version Latest

function Test-CsvFileNotEmpty {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -Path $Path -PathType Leaf)) {
        return $false
    }

    $item = Get-Item -Path $Path -ErrorAction Stop
    return ($item.Length -gt 0)
}

function Import-JobCsv {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Delimiter
    )

    if (-not (Test-CsvFileNotEmpty -Path $Path)) {
        throw "CSV file '$Path' is empty or missing."
    }

    try {
        $rows = @(Import-Csv -Path $Path -Delimiter $Delimiter -ErrorAction Stop)
    }
    catch {
        throw "Failed to import CSV '$Path' with delimiter '$Delimiter'. $($_.Exception.Message)"
    }

    if ($rows.Count -eq 0) {
        throw "CSV file '$Path' does not contain data rows."
    }

    ,$rows
}

Export-ModuleMember -Function @('Import-JobCsv','Test-CsvFileNotEmpty')
