function Add-UseRecoveryButton {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][System.Windows.Forms.Control]$Parent,
        [Parameter(Mandatory=$false)][System.Drawing.Point]$Location = $(New-Object System.Drawing.Point(10,15)),
        [Parameter(Mandatory=$false)][System.Drawing.Size]$Size = $(New-Object System.Drawing.Size(160,32))
    )

    $btn = New-Object System.Windows.Forms.Button
    $btn.Text = 'Use Recovery'
    $btn.Size = $Size
    $btn.Location = $Location
    $tt = New-Object System.Windows.Forms.ToolTip
    $tt.SetToolTip($btn, 'Use an existing recovery drive (placeholder - action is non-destructive).')

    $btn.Add_Click({
        try {
            # Open recovery options (Settings > Recovery) so the user can use recovery media
            try {
                Start-Process ms-settings:recovery
            } catch {
                [System.Windows.Forms.MessageBox]::Show('Unable to open Settings. You can access recovery options via Windows Settings > Update & Security > Recovery.', 'Info') | Out-Null
            }
        } catch { Write-Host "Use Recovery handler error: $_" }
    })

    $Parent.Controls.Add($btn)
    return $btn
}
