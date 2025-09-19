function Add-FormatDisksButton {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][System.Windows.Forms.Control]$Parent,
        [Parameter(Mandatory=$false)][System.Drawing.Point]$Location = $(New-Object System.Drawing.Point(10,15)),
        [Parameter(Mandatory=$false)][System.Drawing.Size]$Size = $(New-Object System.Drawing.Size(160,32))
    )

    $btn = New-Object System.Windows.Forms.Button
    $btn.Text = 'Format Disks'
    $btn.Size = $Size
    $btn.Location = $Location
    $tt = New-Object System.Windows.Forms.ToolTip
    $tt.SetToolTip($btn, 'Format selected disks. This is a placeholder and will not perform destructive actions.')

    $btn.Add_Click({
        try {
            # Open Disk Management (MMC) so the user can manage/format partitions manually
            Write-Host "Opening Disk Management..."
            Start-Process -FilePath 'diskmgmt.msc'
        } catch {
            Write-Host "Failed to open Disk Management: $_"
            [System.Windows.Forms.MessageBox]::Show("Failed to open Disk Management: $($_.Exception.Message)", 'Error', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
        }
    })

    $Parent.Controls.Add($btn)
    return $btn
}
