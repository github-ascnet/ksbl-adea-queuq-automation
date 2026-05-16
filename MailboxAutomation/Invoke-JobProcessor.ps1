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
    [bool]$VerboseLogging = $false,
    [switch]$OutputJson,
    [string]$CorrelationId
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

    $engineParams = @{
        ConfigPath          = $resolvedConfigPath
        UseCaseRegistryPath = $resolvedUseCaseRegistryPath
        EnvironmentPath     = $resolvedEnvironmentPath
        Queue               = $Queue
        RootPath            = $rootPath
        IncludePaused       = $IncludePaused
        ResumePaused        = $ResumePaused
        CorrelationId       = $CorrelationId
        ReturnSummary       = $OutputJson
        SuppressConsoleOutput = $OutputJson
        WhatIfMode          = $WhatIfMode
        VerboseLogging      = $VerboseLogging
    }

    $engineResult = Invoke-JobEngine @engineParams

    if ($OutputJson) {
        $engineResult | ConvertTo-Json -Depth 6
    }
}
catch {
    if ($OutputJson) {
        $errorRecord = $_
        $errorMessage = if ($errorRecord.Exception -and $errorRecord.Exception.Message) { [string]$errorRecord.Exception.Message } else { 'Unhandled error.' }
        $errorCategory = if ($errorRecord.CategoryInfo -and $errorRecord.CategoryInfo.Category) { [string]$errorRecord.CategoryInfo.Category } else { 'NotSpecified' }
        $errorId = if ($errorRecord.FullyQualifiedErrorId) { [string]$errorRecord.FullyQualifiedErrorId } else { 'InvokeJobProcessorFailed' }

        [pscustomobject]@{
            queue     = $Queue
            status    = 'Failed'
            processed = 0
            succeeded = 0
            failed    = 1
            retry     = 0
            paused    = 0
            jobIds    = @()
            error     = [pscustomobject]@{
                message               = $errorMessage
                category              = $errorCategory
                fullyQualifiedErrorId = $errorId
            }
        } | ConvertTo-Json -Depth 6

        [Console]::Error.WriteLine("Invoke-JobProcessor failed: $errorMessage")
        return
    }

    Write-Error "Invoke-JobProcessor failed: $($_.Exception.Message)"
    throw
}
