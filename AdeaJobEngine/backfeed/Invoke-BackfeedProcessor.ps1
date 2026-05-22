param(
    [ValidateSet('User', 'Group', 'MailboxPermission')][string]$BackfeedType = 'User',
    [ValidateSet('Full', 'Delta')][string]$Mode = 'Delta',
    [string]$Environment = 'TODO',
    [switch]$OutputJson,
    [string]$CorrelationId = ([guid]::NewGuid().ToString()),
    [string]$BackfeedRunId = $null
)

Set-StrictMode -Version Latest

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$engineRoot = Split-Path -Parent $scriptRoot

$configPath = Join-Path -Path $engineRoot -ChildPath 'config\backfeed.json'
$contextModulePath = Join-Path -Path $engineRoot -ChildPath 'shared\Backfeed\BackfeedContext.psm1'
$resultModulePath = Join-Path -Path $engineRoot -ChildPath 'shared\Backfeed\BackfeedResult.psm1'

Import-Module -Name $contextModulePath -Force -DisableNameChecking
Import-Module -Name $resultModulePath -Force -DisableNameChecking

$config = Get-Content -Path $configPath -Raw | ConvertFrom-Json
$logger = [pscustomobject]@{ Enabled = $false }
$context = New-BackfeedContext -Environment $Environment -Config $config -Logger $logger -StartedAt (Get-Date) -CorrelationId $CorrelationId -BackfeedType $BackfeedType -Mode $Mode -BackfeedRunId $BackfeedRunId

switch ($BackfeedType) {
    'User' {
        Import-Module -Name (Join-Path -Path $engineRoot -ChildPath 'backfeed\User\UserBackfeedService.psm1') -Force -DisableNameChecking
        $result = Invoke-UserBackfeed -Context $context
    }
    'Group' {
        Import-Module -Name (Join-Path -Path $engineRoot -ChildPath 'backfeed\Group\GroupBackfeedService.psm1') -Force -DisableNameChecking
        $result = Invoke-GroupBackfeed -Context $context
    }
    'MailboxPermission' {
        Import-Module -Name (Join-Path -Path $engineRoot -ChildPath 'backfeed\MailboxPermission\MailboxPermissionBackfeedService.psm1') -Force -DisableNameChecking
        $result = Invoke-MailboxPermissionBackfeed -Context $context
    }
}

if ($null -ne $result) {
    $result | Add-Member -NotePropertyName BackfeedRunId -NotePropertyValue ([string]$context.BackfeedRunId) -Force
}

if ($OutputJson) {
    $result | ConvertTo-Json -Depth 20 -Compress
    return
}

$result