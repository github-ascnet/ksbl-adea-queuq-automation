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

$target = Join-Path -Path $PSScriptRoot -ChildPath 'MailboxAutomation\Invoke-JobProcessor.ps1'
if (-not (Test-Path -Path $target -PathType Leaf)) {
    throw "Target script not found: $target"
}

& $target -ConfigPath $ConfigPath -UseCaseRegistryPath $UseCaseRegistryPath -EnvironmentPath $EnvironmentPath -Queue $Queue -IncludePaused:$IncludePaused -ResumePaused:$ResumePaused -WhatIfMode:$WhatIfMode -VerboseLogging:$VerboseLogging -OutputJson:$OutputJson -CorrelationId $CorrelationId
