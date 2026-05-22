Set-StrictMode -Version Latest

function Get-ObjectPropertyValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][object]$InputObject,
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $false)][object]$DefaultValue = $null
    )

    $property = $InputObject.PSObject.Properties[$Name]
    if ($null -eq $property) {
        return $DefaultValue
    }

    $property.Value
}

function ConvertTo-NormalizedMailboxPermissionType {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][object]$RawPermission)

    $permissionType = [string](Get-ObjectPropertyValue -InputObject $RawPermission -Name 'PermissionType' -DefaultValue '')
    if (-not [string]::IsNullOrWhiteSpace($permissionType)) {
        switch -Regex ($permissionType) {
            '^FullAccess$' { return 'FullAccess' }
            '^SendAs$' { return 'SendAs' }
        }
    }

    $accessRightsText = Resolve-AccessRightsText -RawPermission $RawPermission
    if ([string]::IsNullOrWhiteSpace($accessRightsText)) {
        return $null
    }

    if ($accessRightsText -match 'SendAs') { return 'SendAs' }
    if ($accessRightsText -match 'FullAccess') { return 'FullAccess' }
    return $null
}

function Resolve-AccessRightsText {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][object]$RawPermission)

    $accessRights = Get-ObjectPropertyValue -InputObject $RawPermission -Name 'AccessRights'
    if ($null -eq $accessRights) {
        return ''
    }

    if ($accessRights -is [string]) {
        return [string]$accessRights
    }

    if ($accessRights -is [System.Collections.IEnumerable]) {
        return (@($accessRights) | ForEach-Object { [string]$_ }) -join ','
    }

    [string]$accessRights
}

function Resolve-MailboxName {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][object]$RawPermission)

    $mailboxName = [string](Get-ObjectPropertyValue -InputObject $RawPermission -Name 'MailboxName' -DefaultValue '')
    if (-not [string]::IsNullOrWhiteSpace($mailboxName)) { return $mailboxName }
    [string](Get-ObjectPropertyValue -InputObject $RawPermission -Name 'MailboxIdentity' -DefaultValue '')
}

function Resolve-TrusteeName {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][object]$RawPermission)

    $trusteeName = [string](Get-ObjectPropertyValue -InputObject $RawPermission -Name 'TrusteeName' -DefaultValue '')
    if (-not [string]::IsNullOrWhiteSpace($trusteeName)) { return $trusteeName }
    [string](Get-ObjectPropertyValue -InputObject $RawPermission -Name 'TrusteeIdentity' -DefaultValue '')
}

function ConvertTo-NullableBoolean {
    [CmdletBinding()]
    param([Parameter(Mandatory = $false)][object]$Value)

    if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)) {
        return $null
    }

    [bool]$Value
}

function Get-MailboxPermissionRowHash {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][object]$Row)

    $payload = @(
        "SourceSystem=$($Row.SourceSystem)",
        "PermissionType=$($Row.PermissionType)",
        "MailboxKey=$($Row.MailboxKey)",
        "TrusteeKey=$($Row.TrusteeKey)",
        "AcePermissions=$($Row.AcePermissions)",
        "IsInherited=$($Row.IsInherited)",
        "Deny=$($Row.Deny)"
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

    $mailboxGuid = [string](Get-ObjectPropertyValue -InputObject $RawPermission -Name 'MailboxGuid' -DefaultValue '')
    $mailboxDn = [string](Get-ObjectPropertyValue -InputObject $RawPermission -Name 'MailboxDistinguishedName' -DefaultValue '')
    $mailboxIdentity = [string](Get-ObjectPropertyValue -InputObject $RawPermission -Name 'MailboxIdentity' -DefaultValue '')

    if (-not [string]::IsNullOrWhiteSpace($mailboxGuid)) { return $mailboxGuid }
    if (-not [string]::IsNullOrWhiteSpace($mailboxDn)) { return $mailboxDn }
    if (-not [string]::IsNullOrWhiteSpace($mailboxIdentity)) { return $mailboxIdentity }
    return ''
}

function Resolve-MailboxPermissionTrusteeKey {
    param([object]$RawPermission)

    $trusteeSid = [string](Get-ObjectPropertyValue -InputObject $RawPermission -Name 'TrusteeSid' -DefaultValue '')
    $trusteeDn = [string](Get-ObjectPropertyValue -InputObject $RawPermission -Name 'TrusteeDistinguishedName' -DefaultValue '')
    $trusteeDomain = [string](Get-ObjectPropertyValue -InputObject $RawPermission -Name 'TrusteeDomain' -DefaultValue '')
    $trusteeName = Resolve-TrusteeName -RawPermission $RawPermission

    if (-not [string]::IsNullOrWhiteSpace($trusteeSid)) { return $trusteeSid }
    if (-not [string]::IsNullOrWhiteSpace($trusteeDn)) { return $trusteeDn }
    if (-not [string]::IsNullOrWhiteSpace($trusteeDomain) -and -not [string]::IsNullOrWhiteSpace($trusteeName)) {
        return "$trusteeDomain\$trusteeName"
    }
    $trusteeName
}

function ConvertTo-MailboxPermissionBackfeedRows {
    [CmdletBinding()]
    param([Parameter(Mandatory = $false)][AllowEmptyCollection()][object[]]$RawPermissions)

    if (@($RawPermissions).Count -eq 0) {
        return @()
    }

    $mapped = foreach ($raw in @($RawPermissions)) {
        if ($null -eq $raw) { continue }

        $permissionType = ConvertTo-NormalizedMailboxPermissionType -RawPermission $raw
        if ([string]::IsNullOrWhiteSpace($permissionType)) { continue }

        $sourceSystem = [string](Get-ObjectPropertyValue -InputObject $raw -Name 'SourceSystem' -DefaultValue '')
        if ([string]::IsNullOrWhiteSpace($sourceSystem)) { $sourceSystem = 'TODO' }

        $acePermissions = [string](Get-ObjectPropertyValue -InputObject $raw -Name 'AcePermissions' -DefaultValue '')
        if ([string]::IsNullOrWhiteSpace($acePermissions)) {
            $accessRightsText = Resolve-AccessRightsText -RawPermission $raw
            $acePermissions = if (-not [string]::IsNullOrWhiteSpace($accessRightsText)) { $accessRightsText } else { $permissionType }
        }

        $accessRightsText = Resolve-AccessRightsText -RawPermission $raw

        $row = [pscustomobject]@{
            SourceSystem              = $sourceSystem
            PermissionType            = $permissionType
            MailboxKey                = Resolve-MailboxPermissionKey -RawPermission $raw
            MailboxName               = Resolve-MailboxName -RawPermission $raw
            TrusteeKey                = Resolve-MailboxPermissionTrusteeKey -RawPermission $raw
            TrusteeName               = Resolve-TrusteeName -RawPermission $raw
            TrusteeDomain             = [string](Get-ObjectPropertyValue -InputObject $raw -Name 'TrusteeDomain' -DefaultValue '')
            ObjectClass               = [string](Get-ObjectPropertyValue -InputObject $raw -Name 'TrusteeObjectClass' -DefaultValue '')
            AcePermissions            = $acePermissions
            DistinguishedName         = [string](Get-ObjectPropertyValue -InputObject $raw -Name 'MailboxDistinguishedName' -DefaultValue '')
            ExchHideFromAddressLists  = ConvertTo-NullableBoolean -Value (Get-ObjectPropertyValue -InputObject $raw -Name 'MailboxHiddenFromAddressListsEnabled')
            AdReferenceObjectGuid     = [string](Get-ObjectPropertyValue -InputObject $raw -Name 'MailboxGuid' -DefaultValue '')
            IsInherited               = [bool](Get-ObjectPropertyValue -InputObject $raw -Name 'IsInherited' -DefaultValue $false)
            Deny                      = [bool](Get-ObjectPropertyValue -InputObject $raw -Name 'Deny' -DefaultValue $false)
            AccessRights              = $accessRightsText
        }

        $existingRowHash = [string](Get-ObjectPropertyValue -InputObject $raw -Name 'RowHash' -DefaultValue '')
        $rowHash = if ([string]::IsNullOrWhiteSpace($existingRowHash)) {
            Get-MailboxPermissionRowHash -Row $row
        }
        else {
            $existingRowHash
        }

        $row | Add-Member -NotePropertyName RowHash -NotePropertyValue $rowHash -Force
        $row
    }

    @($mapped)
}

Export-ModuleMember -Function @('ConvertTo-MailboxPermissionBackfeedRows')