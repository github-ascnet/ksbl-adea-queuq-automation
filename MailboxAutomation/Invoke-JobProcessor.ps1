[CmdletBinding()]
param(
    [string]$ConfigPath = '.\config\appsettings.json',
    [string]$UseCaseRegistryPath = '.\config\usecases.json',
    [string]$EnvironmentPath = '.\config\environments.onprem.json',
    [ValidateSet('standard','urgent','person-mailbox-longrunning')]
    [string]$Queue = 'standard',
    [bool]$IncludePaused = $false,
    [bool]$ResumePaused = $false,
    [bool]$WhatIfMode = $true,
    [bool]$VerboseLogging = $false
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

try {
    $rootPath = Split-Path -Parent $MyInvocation.MyCommand.Path

    $coreModules = Get-ChildItem -Path (Join-Path $rootPath 'core') -Filter '*.psm1' -File | Sort-Object Name
    foreach ($module in $coreModules) {
        Import-Module -Name $module.FullName -Force -ErrorAction Stop
    }

    $infraModules = Get-ChildItem -Path (Join-Path $rootPath 'infrastructure') -Filter '*.psm1' -File | Sort-Object Name
    foreach ($module in $infraModules) {
        Import-Module -Name $module.FullName -Force -ErrorAction Stop
    }

    $sharedModules = Get-ChildItem -Path (Join-Path $rootPath 'shared') -Filter '*.psm1' -File | Sort-Object Name
    foreach ($module in $sharedModules) {
        Import-Module -Name $module.FullName -Force -ErrorAction Stop
    }

    $resolvedConfigPath = Join-Path -Path $rootPath -ChildPath $ConfigPath
    $resolvedUseCaseRegistryPath = Join-Path -Path $rootPath -ChildPath $UseCaseRegistryPath
    $resolvedEnvironmentPath = Join-Path -Path $rootPath -ChildPath $EnvironmentPath

    Invoke-JobEngine -ConfigPath $resolvedConfigPath -UseCaseRegistryPath $resolvedUseCaseRegistryPath -EnvironmentPath $resolvedEnvironmentPath -Queue $Queue -RootPath $rootPath -IncludePaused:$IncludePaused -ResumePaused:$ResumePaused -WhatIfMode:$WhatIfMode -VerboseLogging:$VerboseLogging
}
catch {
    Write-Error "Invoke-JobProcessor failed: $($_.Exception.Message)"
    throw
}
