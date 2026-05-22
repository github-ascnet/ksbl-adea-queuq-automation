Set-StrictMode -Version Latest

function Get-MailboxPermissionRowHash {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][object]$Row)

    $payload = @(
        $Row.SourceSystem,
        $Row.PermissionType,
        $Row.MailboxKey,
        $Row.MailboxName,
        $Row.TrusteeKey,
        $Row.TrusteeName,
        $Row.TrusteeDomain,
        $Row.ObjectClass,
        $Row.AcePermissions,
        $Row.DistinguishedName,
        $Row.ExchHideFromAddressLists,
        $Row.AdReferenceObjectGuid,
        $Row.IsInherited,
        $Row.Deny,
        $Row.AccessRights
    ) -join '|'

    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($payload)
        ($sha.ComputeHash($bytes) | ForEach-Object { $_.ToString('x2') }) -join ''
    }
    finally {
        $sha.Dispose()
    }
}

function Resolve-MailboxPermissionKey {
    param([object]$RawPermission)

    if (-not [string]::IsNullOrWhiteSpace([string]$RawPermission.MailboxGuid)) { return [string]$RawPermission.MailboxGuid }
    if (-not [string]::IsNullOrWhiteSpace([string]$RawPermission.MailboxDistinguishedName)) { return [string]$RawPermission.MailboxDistinguishedName }
    if (-not [string]::IsNullOrWhiteSpace([string]$RawPermission.MailboxIdentity)) { return [string]$RawPermission.MailboxIdentity }
    return ''
}

function Resolve-MailboxPermissionTrusteeKey {
    param([object]$RawPermission)

    if (-not [string]::IsNullOrWhiteSpace([string]$RawPermission.TrusteeSid)) { return [string]$RawPermission.TrusteeSid }
    if (-not [string]::IsNullOrWhiteSpace([string]$RawPermission.TrusteeDistinguishedName)) { return [string]$RawPermission.TrusteeDistinguishedName }
    if (-not [string]::IsNullOrWhiteSpace([string]($RawPermission.TrusteeDomain))) {
        return "$($RawPermission.TrusteeDomain)\$($RawPermission.TrusteeName)"
    }
    return [string]$RawPermission.TrusteeName
}

function ConvertTo-MailboxPermissionBackfeedRows {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][object[]]$RawPermissions)

    $mapped = foreach ($raw in @($RawPermissions)) {
        if ($null -eq $raw) { continue }

        $permissionType = [string]$raw.PermissionType
        if ([string]::IsNullOrWhiteSpace($permissionType)) {
            $permissionType = if (-not [string]::IsNullOrWhiteSpace([string]$raw.AccessRights) -and [string]$raw.AccessRights -match 'SendAs') { 'SendAs' } else { 'FullAccess' }
        }

        $sourceSystem = [string]$raw.SourceSystem
        if ([string]::IsNullOrWhiteSpace($sourceSystem)) { $sourceSystem = 'TODO' }

        $acePermissions = [string]$raw.AcePermissions
        if ([string]::IsNullOrWhiteSpace($acePermissions)) {
            $acePermissions = if ($permissionType -eq 'SendAs') { 'SendAs' } else { 'FullAccess' }
        }

        $row = [pscustomobject]@{
            SourceSystem              = $sourceSystem
            PermissionType            = $permissionType
            MailboxKey                = Resolve-MailboxPermissionKey -RawPermission $raw
            MailboxName               = [string]$raw.MailboxName
            TrusteeKey                = Resolve-MailboxPermissionTrusteeKey -RawPermission $raw
            TrusteeName               = [string]$raw.TrusteeName
            TrusteeDomain             = [string]$raw.TrusteeDomain
            ObjectClass               = [string]$raw.ObjectClass
            AcePermissions            = $acePermissions
            DistinguishedName         = [string]$raw.MailboxDistinguishedName
            ExchHideFromAddressLists  = $raw.ExchHideFromAddressLists
            AdReferenceObjectGuid      = [string]$raw.MailboxGuid
            IsInherited               = [bool]$raw.IsInherited
            Deny                      = [bool]$raw.Deny
            AccessRights              = [string]$raw.AccessRights
        }

        $row | Add-Member -NotePropertyName RowHash -NotePropertyValue (if ([string]::IsNullOrWhiteSpace([string]$raw.RowHash)) { Get-MailboxPermissionRowHash -Row $row } else { [string]$raw.RowHash }) -Force
        $row
    }

    @($mapped)
}

Export-ModuleMember -Function @('ConvertTo-MailboxPermissionBackfeedRows')