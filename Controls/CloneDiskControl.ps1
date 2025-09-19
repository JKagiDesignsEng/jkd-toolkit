function Add-CloneDiskButton {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][System.Windows.Forms.Control]$Parent,
        [Parameter(Mandatory=$false)][System.Drawing.Point]$Location = $(New-Object System.Drawing.Point(10,15)),
        [Parameter(Mandatory=$false)][System.Drawing.Size]$Size = $(New-Object System.Drawing.Size(160,32))
    )

    $btn = New-Object System.Windows.Forms.Button
    $btn.Text = 'Clone Disk'
    $btn.Size = $Size
    $btn.Location = $Location
    # Provide a clear, persistent tooltip describing the clone workflow and safety
    $tt = New-Object System.Windows.Forms.ToolTip
    $tt.AutoPopDelay = 30000
    $tt.InitialDelay = 300
    $tt.ReshowDelay = 100
    $tt.ShowAlways = $true
    $tt.SetToolTip($btn, "Clone a disk to a file or another disk. If 'disk2vhd' (Sysinternals) is installed the tool will offer to create a VHD/VHDX image of the selected volume(s) (non-destructive). For full device-to-device block cloning you should use Clonezilla from bootable media. This button will prompt for destination and ask for confirmation before running any elevated operations.")
    $btn.Tag = @{ ToolTip = $tt }

    $btn.Add_Click({
        try {
            # Basic cloning UI: show a dialog to choose destination drive (non-destructive until confirmed)
            Add-Type -AssemblyName System.Windows.Forms
            $form = New-Object System.Windows.Forms.Form
            $form.Text = 'Clone Disk - Select Destination'
            $form.Size = New-Object System.Drawing.Size(400,200)

            $lbl = New-Object System.Windows.Forms.Label
            $lbl.Text = 'Destination drive letter (e.g., F:)'
            $lbl.Location = New-Object System.Drawing.Point(10,20)
            $lbl.AutoSize = $true
            $form.Controls.Add($lbl)

            $txt = New-Object System.Windows.Forms.TextBox
            $txt.Location = New-Object System.Drawing.Point(10,50)
            $txt.Size = New-Object System.Drawing.Size(240,20)
            $form.Controls.Add($txt)

            $btnOk = New-Object System.Windows.Forms.Button
            $btnOk.Text = 'Clone'
            $btnOk.Location = New-Object System.Drawing.Point(260,45)
            $btnOk.Add_Click({ $form.Tag = 'ok'; $form.Close() })
            $form.Controls.Add($btnOk)

            $btnCancel = New-Object System.Windows.Forms.Button
            $btnCancel.Text = 'Cancel'
            $btnCancel.Location = New-Object System.Drawing.Point(260,75)
            $btnCancel.Add_Click({ $form.Tag = 'cancel'; $form.Close() })
            $form.Controls.Add($btnCancel)

            $form.ShowDialog() | Out-Null
            if ($form.Tag -eq 'ok') {
                $dest = $txt.Text.Trim()
                if (-not $dest) { [System.Windows.Forms.MessageBox]::Show('Please enter a destination drive (e.g., F:)','Validation', 'OK','Warning') | Out-Null; return }

                # Prefer disk2vhd for non-destructive imaging to a VHD(X). If available, prompt for a file path.
                $disk2vhdPath = Get-Command -Name disk2vhd -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source -ErrorAction SilentlyContinue
                if ($disk2vhdPath) {
                    $sfd = New-Object System.Windows.Forms.SaveFileDialog
                    $sfd.Filter = 'VHDX files (*.vhdx)|*.vhdx|VHD files (*.vhd)|*.vhd|All files (*.*)|*.*'
                    $sfd.FileName = "WindowsImage_$((Get-Date).ToString('yyyyMMdd_HHmmss')).vhdx"
                    if ($sfd.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
                        $targetFile = $sfd.FileName
                        $cmd = "`"$disk2vhdPath`" C: `"$targetFile`""
                        $confirm = [System.Windows.Forms.MessageBox]::Show("This will run: $cmd`nRun as administrator?","Confirm Clone", [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Warning)
                        if ($confirm -ne [System.Windows.Forms.DialogResult]::Yes) { return }

                        try {
                            Start-Process -FilePath $disk2vhdPath -ArgumentList 'C:', $targetFile -Verb RunAs
                        } catch {
                            [System.Windows.Forms.MessageBox]::Show("Failed to start disk2vhd: $($_.Exception.Message)", 'Error') | Out-Null
                        }
                    }
                } else {
                    # If disk2vhd not available, advise Clonezilla bootable media
                    [System.Windows.Forms.MessageBox]::Show('disk2vhd was not found. To perform a full disk clone, create a Clonezilla bootable USB and boot the machine from it. Alternatively install disk2vhd from Sysinternals for VHD creation.', 'Info') | Out-Null
                }
            }
        } catch { Write-Host "Clone Disk handler error: $_" }
    })

    $Parent.Controls.Add($btn)
    return $btn
}
