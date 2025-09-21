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
    $tt.AutoPopDelay = 20000
    $tt.InitialDelay = 300
    $tt.ReshowDelay = 100
    $tt.ShowAlways = $true
    $tt.SetToolTip($btn, 'Open Windows Recovery options (Settings > Recovery) so you can boot from or use existing recovery media. This control does not modify disks directly; follow on-screen instructions in the system interface to apply recovery media.')
    $btn.Tag = @{ ToolTip = $tt }

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
