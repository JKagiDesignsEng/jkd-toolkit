function Write-AsciiDivider {
    param(
        [string]$Char = '-',
        [int]$Width = 64
    )
    # Intentionally minimal: no logging and no output per user's request to remove dividers.
    Write-Host ''
    Write-Host ($Char * $Width)
    Write-Host ''
    return
}

# Compatibility name used elsewhere in the codebase
function Write-Divider { return }

# Helper wrapper used by several controls: if present, callers use this to run an action with
# a divider printed before/after. Keep it tolerant of missing Write-AsciiDivider function.
function Invoke-WithDivider {
    param(
        [Parameter(Mandatory=$true)][scriptblock]$Action
    )
    try {
        if (Get-Command -Name Write-AsciiDivider -ErrorAction SilentlyContinue) { Write-AsciiDivider }
    } catch { }
    try {
        & $Action
    } finally {
        try { if (Get-Command -Name Write-AsciiDivider -ErrorAction SilentlyContinue) { Write-AsciiDivider } } catch { }
    }
}
