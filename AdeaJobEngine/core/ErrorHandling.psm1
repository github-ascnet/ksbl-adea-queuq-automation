Set-StrictMode -Version Latest

function New-TechnicalJobException {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Message,
        [System.Exception]$InnerException
    )

    if ($InnerException) {
        return New-Object System.Exception($Message, $InnerException)
    }

    return New-Object System.Exception($Message)
}

function New-BusinessJobException {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Message,
        [string]$Code = 'BUSINESS_RULE'
    )

    $ex = New-Object System.Exception($Message)
    $ex.Data['Type'] = 'Business'
    $ex.Data['Code'] = $Code
    $ex
}

function ConvertTo-JobError {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][System.Exception]$Exception)

    [pscustomobject]@{
        Type      = if ($Exception.Data['Type']) { $Exception.Data['Type'] } else { 'Technical' }
        Code      = if ($Exception.Data['Code']) { $Exception.Data['Code'] } else { 'TECHNICAL_ERROR' }
        Message   = $Exception.Message
        Exception = $Exception
    }
}

Export-ModuleMember -Function @('ConvertTo-JobError','New-TechnicalJobException','New-BusinessJobException')
