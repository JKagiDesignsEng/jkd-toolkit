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
    # Create a persistent, descriptive ToolTip and keep a reference on the control Tag
    $tt = New-Object System.Windows.Forms.ToolTip
    $tt.AutoPopDelay = 20000
    $tt.InitialDelay = 300
    $tt.ReshowDelay = 100
    $tt.ShowAlways = $true
    $tt.SetToolTip($btn, "Open Disk Management so you can partition, format, or prepare drives manually. This launcher does not perform any destructive formatting directly. Use Disk Management or a dedicated imaging tool for destructive operations. Always double-check the target disk before formatting.")
    $btn.Tag = @{ ToolTip = $tt }

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
