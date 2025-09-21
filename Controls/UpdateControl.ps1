function Add-UpdateButton {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][System.Windows.Forms.Control]$Parent,
        [Parameter(Mandatory=$false)][System.Drawing.Point]$Location = $(New-Object System.Drawing.Point(10,15)),
        [Parameter(Mandatory=$false)][System.Drawing.Size]$Size = $(New-Object System.Drawing.Size(160,40))
    )

    $btn = New-Object System.Windows.Forms.Button
    $btn.Text = 'Update Toolkit'
    $btn.Size = $Size
    $btn.Location = $Location
    
    # Create a detailed, persistent ToolTip
    $tt = New-Object System.Windows.Forms.ToolTip
    $tt.AutoPopDelay = 20000
    $tt.InitialDelay = 300
    $tt.ReshowDelay = 100
    $tt.ShowAlways = $true
    $tt.SetToolTip($btn, 'Check for updates and download the latest version of JKD Toolkit from GitHub. This will download and install the latest main branch release, preserving your current installation directory.')
    $btn.Tag = @{ ToolTip = $tt }

    $btn.Add_Click({
        try {
            Write-Host "Checking for updates..."
            
            # Show progress dialog
            Add-Type -AssemblyName System.Windows.Forms
            $updateForm = New-Object System.Windows.Forms.Form
            $updateForm.Text = 'Update JKD Toolkit'
            $updateForm.Size = New-Object System.Drawing.Size(400,200)
            $updateForm.StartPosition = 'CenterParent'
            $updateForm.FormBorderStyle = 'FixedDialog'
            $updateForm.MaximizeBox = $false
            $updateForm.MinimizeBox = $false

            $lblStatus = New-Object System.Windows.Forms.Label
            $lblStatus.Text = 'Checking for updates...'
            $lblStatus.Location = New-Object System.Drawing.Point(20,20)
            $lblStatus.Size = New-Object System.Drawing.Size(350,40)
            $lblStatus.TextAlign = 'MiddleLeft'
            $updateForm.Controls.Add($lblStatus)

            $progressBar = New-Object System.Windows.Forms.ProgressBar
            $progressBar.Location = New-Object System.Drawing.Point(20,70)
            $progressBar.Size = New-Object System.Drawing.Size(350,20)
            $progressBar.Style = 'Marquee'
            $progressBar.MarqueeAnimationSpeed = 50
            $updateForm.Controls.Add($progressBar)

            $btnCancel = New-Object System.Windows.Forms.Button
            $btnCancel.Text = 'Cancel'
            $btnCancel.Location = New-Object System.Drawing.Point(300,120)
            $btnCancel.Size = New-Object System.Drawing.Size(70,30)
            $btnCancel.Add_Click({ $updateForm.Tag = 'cancel'; $updateForm.Close() })
            $updateForm.Controls.Add($btnCancel)

            # Show the form non-blocking
            $updateForm.Show()
            $updateForm.Refresh()

            # Determine current installation directory
            $currentDir = $PSScriptRoot
            if ($currentDir.EndsWith('\Controls')) {
                $currentDir = Split-Path $currentDir -Parent
            }

            $lblStatus.Text = 'Downloading latest version...'
            $lblStatus.Refresh()

            # Download and extract update
            $zipUrl = 'https://github.com/JKagiDesignsEng/jkd-toolkit/archive/refs/heads/main.zip'
            $tmpZip = Join-Path $env:TEMP ("jkd-toolkit-update-" + [guid]::NewGuid().ToString() + ".zip")
            
            try {
                Invoke-WebRequest -Uri $zipUrl -OutFile $tmpZip -UseBasicParsing -ErrorAction Stop
            } catch {
                $updateForm.Close()
                [System.Windows.Forms.MessageBox]::Show("Failed to download update: $($_.Exception.Message)", 'Update Error', 'OK', 'Error') | Out-Null
                return
            }

            if ($updateForm.Tag -eq 'cancel') { $updateForm.Close(); return }

            $lblStatus.Text = 'Extracting files...'
            $lblStatus.Refresh()

            $extractDir = Join-Path $env:TEMP ("jkd-toolkit-extract-" + [guid]::NewGuid().ToString())
            try {
                Expand-Archive -Path $tmpZip -DestinationPath $extractDir -Force
            } catch {
                $updateForm.Close()
                [System.Windows.Forms.MessageBox]::Show("Failed to extract update: $($_.Exception.Message)", 'Update Error', 'OK', 'Error') | Out-Null
                return
            }

            if ($updateForm.Tag -eq 'cancel') { $updateForm.Close(); return }

            $rootFolder = Get-ChildItem -Path $extractDir | Where-Object { $_.PSIsContainer } | Select-Object -First 1
            if (-not $rootFolder) {
                $updateForm.Close()
                [System.Windows.Forms.MessageBox]::Show('Update archive has unexpected layout', 'Update Error', 'OK', 'Error') | Out-Null
                return
            }

            $lblStatus.Text = 'Installing update...'
            $lblStatus.Refresh()

            # Copy new files
            try {
                Copy-Item -Path (Join-Path $rootFolder.FullName '*') -Destination $currentDir -Recurse -Force
                
                $updateForm.Close()
                
                $result = [System.Windows.Forms.MessageBox]::Show("Update completed successfully!`n`nWould you like to restart the toolkit now?", 'Update Complete', 'YesNo', 'Information')
                if ($result -eq [System.Windows.Forms.DialogResult]::Yes) {
                    # Restart the application
                    $mainScript = Join-Path $currentDir 'jkd-toolkit-main.ps1'
                    Start-Process -FilePath 'powershell.exe' -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-NoExit', '-File', "`"$mainScript`"") -Verb RunAs
                    # Close current instance
                    $btn.FindForm().Close()
                }
            } catch {
                $updateForm.Close()
                [System.Windows.Forms.MessageBox]::Show("Failed to install update: $($_.Exception.Message)", 'Update Error', 'OK', 'Error') | Out-Null
            }

        } catch {
            Write-Host "Update error: $($_.Exception.Message)"
            [System.Windows.Forms.MessageBox]::Show("Update failed: $($_.Exception.Message)", 'Error', 'OK', 'Error') | Out-Null
        } finally {
            try { 
                if ($updateForm -and -not $updateForm.IsDisposed) { $updateForm.Close() }
                Remove-Item -Path $tmpZip -ErrorAction SilentlyContinue 
                Remove-Item -Path $extractDir -Recurse -Force -ErrorAction SilentlyContinue 
            } catch { }
            
            # Call divider helper if available
            try {
                if (Get-Command -Name Invoke-WithDivider -ErrorAction SilentlyContinue) {
                    Invoke-WithDivider -Action { Write-Host "Update check completed." }
                } else {
                    Write-Host "Update check completed."
                }
            } catch { }
        }
    })

    $Parent.Controls.Add($btn)
    return $btn
}