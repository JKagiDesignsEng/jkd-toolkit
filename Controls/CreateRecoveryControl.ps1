function Add-CreateRecoveryButton {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][System.Windows.Forms.Control]$Parent,
        [Parameter(Mandatory=$false)][System.Drawing.Point]$Location = $(New-Object System.Drawing.Point(10,15)),
        [Parameter(Mandatory=$false)][System.Drawing.Size]$Size = $(New-Object System.Drawing.Size(160,32))
    )

    $btn = New-Object System.Windows.Forms.Button
    $btn.Text = 'Create Recovery'
    $btn.Size = $Size
    $btn.Location = $Location
    $tt = New-Object System.Windows.Forms.ToolTip
    $tt.SetToolTip($btn, 'Create a recovery drive (placeholder - no drive will be created).')

    $btn.Add_Click({
        try {
            # Try to launch recoverydrive.exe which creates a recovery drive
            $exe = Join-Path $env:SystemRoot 'System32\recimg.exe'
            if (Test-Path "$env:SystemRoot\System32\recimg.exe") {
                Start-Process -FilePath "$env:SystemRoot\System32\recimg.exe"
            } elseif (Test-Path "$env:SystemRoot\System32\recoverydrive.exe") {
                Start-Process -FilePath "$env:SystemRoot\System32\recoverydrive.exe"
            } else {
                # Fallback: open Settings Recovery page
                Start-Process ms-settings:recovery
            }
        } catch { Write-Host "Create Recovery handler error: $_" }
    })

    $Parent.Controls.Add($btn)
    return $btn
}
