Set-StrictMode -Version Latest

function New-RandomPassword {
    [CmdletBinding()]
    param(
        [int]$Length = 20,
        [int]$MinSpecial = 2
    )

    if ($Length -lt 8) { throw 'Password length must be at least 8.' }

    $letters = 'abcdefghijkmnopqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789'.ToCharArray()
    $special = '!$%&*+-=?@#'.ToCharArray()
    $chars = New-Object System.Collections.Generic.List[char]

    1..($Length - $MinSpecial) | ForEach-Object { $chars.Add($letters[(Get-Random -Minimum 0 -Maximum $letters.Length)]) }
    1..$MinSpecial | ForEach-Object { $chars.Add($special[(Get-Random -Minimum 0 -Maximum $special.Length)]) }

    $shuffled = $chars | Sort-Object { Get-Random }
    -join $shuffled
}

Export-ModuleMember -Function @('New-RandomPassword')
