Set-StrictMode -Version Latest

function New-FileLock {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$TargetPath,
        [int]$StaleLockMinutes = 60
    )

    $lockPath = "$TargetPath.lock"

    if (Test-Path -Path $lockPath -PathType Leaf) {
        $lockInfo = Get-Item -Path $lockPath -ErrorAction SilentlyContinue
        if ($lockInfo) {
            $ageMinutes = ((Get-Date) - $lockInfo.LastWriteTime).TotalMinutes
            if ($ageMinutes -ge $StaleLockMinutes) {
                Remove-Item -Path $lockPath -Force -ErrorAction SilentlyContinue
            }
        }
    }

    try {
        $stream = [System.IO.File]::Open(
            $lockPath,
            [System.IO.FileMode]::CreateNew,
            [System.IO.FileAccess]::Write,
            [System.IO.FileShare]::None
        )
        try {
            $content = "Pid=$PID;CreatedAt=$((Get-Date).ToString('o'))"
            $bytes = [System.Text.Encoding]::UTF8.GetBytes($content)
            $stream.Write($bytes, 0, $bytes.Length)
        }
        finally {
            $stream.Dispose()
        }
        return $lockPath
    }
    catch [System.IO.IOException] {
        # Normal lock conflict — another runner already holds this file.
        return $null
    }
    catch {
        # Unexpected error (access denied, invalid path, unhandled IO error).
        # Do not silently swallow; propagate so the engine can log the real cause.
        throw
    }
}

function Remove-FileLock {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$TargetPath)

    $lockPath = "$TargetPath.lock"
    if (Test-Path -Path $lockPath) {
        Remove-Item -Path $lockPath -Force -ErrorAction SilentlyContinue
    }
}

function Test-FileLocked {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$TargetPath)

    Test-Path -Path "$TargetPath.lock"
}

Export-ModuleMember -Function @('New-FileLock','Remove-FileLock','Test-FileLocked')
