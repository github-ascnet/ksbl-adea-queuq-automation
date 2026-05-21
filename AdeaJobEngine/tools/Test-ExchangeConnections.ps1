[CmdletBinding()]
param(
    [ValidateSet('onprem', 'hybrid')][string]$Environment = 'hybrid',
    [ValidateSet('OnPrem', 'ExchangeOnline', 'All')][string]$Target = 'All',
    [switch]$EnsureConnected,
    [switch]$ValidateCommand,
    [switch]$OutputJson
)

$root = (Resolve-Path (Join-Path -Path $PSScriptRoot -ChildPath '..')).Path

function ConvertTo-ToolHashtableDeep {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][object]$InputObject)

    if ($null -eq $InputObject) { return $null }

    if ($InputObject -is [System.Collections.IDictionary]) {
        $hash = @{}
        foreach ($key in $InputObject.Keys) {
            $hash[$key] = ConvertTo-ToolHashtableDeep -InputObject $InputObject[$key]
        }
        return $hash
    }

    if ($InputObject -is [System.Collections.IEnumerable] -and -not ($InputObject -is [string])) {
        $list = @()
        foreach ($item in $InputObject) {
            $list += , (ConvertTo-ToolHashtableDeep -InputObject $item)
        }
        return $list
    }

    if ($InputObject -is [psobject]) {
        $props = @($InputObject.PSObject.Properties)
        if ($props.Count -gt 0) {
            $hash = @{}
            foreach ($prop in $props) {
                $hash[$prop.Name] = ConvertTo-ToolHashtableDeep -InputObject $prop.Value
            }
            return $hash
        }
    }

    return $InputObject
}

function Read-ToolJsonAsHashtable {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -Path $Path -PathType Leaf)) {
        throw "JSON file not found: $Path"
    }

    $raw = Get-Content -Path $Path -Raw -ErrorAction Stop
    if ([string]::IsNullOrWhiteSpace($raw)) {
        return @{}
    }

    $obj = $raw | ConvertFrom-Json -ErrorAction Stop
    ConvertTo-ToolHashtableDeep -InputObject $obj
}

function Merge-ToolHashtable {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][hashtable]$Base,
        [Parameter(Mandatory = $true)][hashtable]$Override
    )

    $result = @{}
    foreach ($key in $Base.Keys) {
        $result[$key] = $Base[$key]
    }

    foreach ($key in $Override.Keys) {
        if ($result.ContainsKey($key) -and ($result[$key] -is [hashtable]) -and ($Override[$key] -is [hashtable])) {
            $result[$key] = Merge-ToolHashtable -Base $result[$key] -Override $Override[$key]
        }
        else {
            $result[$key] = $Override[$key]
        }
    }

    $result
}

Import-Module -Name (Join-Path -Path $root -ChildPath 'infrastructure\ExchangeConnectionHealth.psm1') -Force
Import-Module -Name (Join-Path -Path $root -ChildPath 'infrastructure\ExchangeOnPremGateway.psm1') -Force
Import-Module -Name (Join-Path -Path $root -ChildPath 'infrastructure\ExchangeOnlineGateway.psm1') -Force

$basePath = Join-Path -Path $root -ChildPath 'config\appsettings.json'
$envPath = Join-Path -Path $root -ChildPath ("config\environments.{0}.json" -f $Environment)

$baseConfig = Read-ToolJsonAsHashtable -Path $basePath
$environmentConfig = Read-ToolJsonAsHashtable -Path $envPath
$mergedConfig = Merge-ToolHashtable -Base $baseConfig -Override $environmentConfig
$mergedConfig['RootPath'] = $root

$results = @()
if ($Target -eq 'OnPrem' -or $Target -eq 'All') {
    $results += Test-ExchangeOnPremConnectionHealth -Config $mergedConfig -EnsureConnected:$EnsureConnected -ValidateCommand:$ValidateCommand
}
if ($Target -eq 'ExchangeOnline' -or $Target -eq 'All') {
    $results += Test-ExchangeOnlineConnectionHealth -Config $mergedConfig -EnsureConnected:$EnsureConnected -ValidateCommand:$ValidateCommand
}

if ($OutputJson.IsPresent) {
    ConvertTo-ExchangeConnectionHealthJson -HealthResult $results -Depth 8 | Write-Output
}
else {
    $results
}
