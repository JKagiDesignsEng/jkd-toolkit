<#
Controls\BackupFilesToDiskControl.ps1

Purpose:
  Adds a WinForms button that allows users to backup files from a source directory 
  to a destination directory. Features include:
  - Sets power setting to not sleep when plugged in during backup
  - File browser dialogs for source and destination selection
  - GUI labels showing selected directories (clickable to change)
  - Progress bar integration using the shared status bar
  - Full recursive backup of directories and subdirectories

Behavior:
  - Opens file browser dialogs to select source and destination
  - Updates GUI labels with selected paths
  - Performs complete backup using robocopy for reliability
  - Shows progress in the shared status bar
  - Restores original power settings after completion
#>

function Add-BackupFilesToDiskButton {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][System.Windows.Forms.Control]$Parent,
        [Parameter(Mandatory=$false)][System.Drawing.Point]$Location = $(New-Object System.Drawing.Point(10,15)),
        [Parameter(Mandatory=$false)][System.Drawing.Size]$Size = $(New-Object System.Drawing.Size(160,32))
    )

    # Create a panel to hold all backup-related controls
    $backupPanel = New-Object System.Windows.Forms.Panel
    $backupPanel.Size = New-Object System.Drawing.Size(320,120)
    $backupPanel.Location = New-Object System.Drawing.Point(0,0)
    $backupPanel.BorderStyle = 'FixedSingle'
    $backupPanel.Margin = New-Object System.Windows.Forms.Padding(3,3,3,3)

    # Create the main backup button
    $btn = New-Object System.Windows.Forms.Button
    $btn.Text = 'Backup Files to Disk'
    $btn.Size = $Size
    $btn.Location = New-Object System.Drawing.Point(10,85)
    
    # Create tooltip
    $tt = New-Object System.Windows.Forms.ToolTip
    $tt.AutoPopDelay = 25000
    $tt.InitialDelay = 500
    $tt.ReshowDelay = 100
    $tt.ShowAlways = $true
    $tt.SetToolTip($btn, 'Select source and destination directories to perform a complete file backup. The system will not sleep during the backup operation. Click the directory labels above to change the selected paths.')
    $btn.Tag = @{ ToolTip = $tt }

    # Create labels for showing selected directories
    $lblSourceTitle = New-Object System.Windows.Forms.Label
    $lblSourceTitle.Text = 'Source:'
    $lblSourceTitle.Location = New-Object System.Drawing.Point(10,10)
    $lblSourceTitle.Size = New-Object System.Drawing.Size(50,20)
    $lblSourceTitle.Font = New-Object System.Drawing.Font('Microsoft Sans Serif', 8, [System.Drawing.FontStyle]::Bold)

    $lblSource = New-Object System.Windows.Forms.Label
    $lblSource.Text = 'Click to select source directory...'
    $lblSource.Location = New-Object System.Drawing.Point(70,10)
    $lblSource.Size = New-Object System.Drawing.Size(240,20)
    $lblSource.ForeColor = [System.Drawing.Color]::Blue
    $lblSource.Cursor = [System.Windows.Forms.Cursors]::Hand
    $lblSource.BorderStyle = 'FixedSingle'
    $lblSource.Tag = $null  # Will store the selected path

    $lblDestTitle = New-Object System.Windows.Forms.Label
    $lblDestTitle.Text = 'Destination:'
    $lblDestTitle.Location = New-Object System.Drawing.Point(10,40)
    $lblDestTitle.Size = New-Object System.Drawing.Size(70,20)
    $lblDestTitle.Font = New-Object System.Drawing.Font('Microsoft Sans Serif', 8, [System.Drawing.FontStyle]::Bold)

    $lblDest = New-Object System.Windows.Forms.Label
    $lblDest.Text = 'Click to select destination directory...'
    $lblDest.Location = New-Object System.Drawing.Point(90,40)
    $lblDest.Size = New-Object System.Drawing.Size(220,20)
    $lblDest.ForeColor = [System.Drawing.Color]::Blue
    $lblDest.Cursor = [System.Windows.Forms.Cursors]::Hand
    $lblDest.BorderStyle = 'FixedSingle'
    $lblDest.Tag = $null  # Will store the selected path

    # Add click handlers for directory selection
    $lblSource.Add_Click({
        $folderDialog = New-Object System.Windows.Forms.FolderBrowserDialog
        $folderDialog.Description = 'Select the source directory to backup'
        $folderDialog.ShowNewFolderButton = $false
        
        if ($lblSource.Tag) {
            $folderDialog.SelectedPath = $lblSource.Tag
        }
        
        if ($folderDialog.ShowDialog() -eq 'OK') {
            $lblSource.Tag = $folderDialog.SelectedPath
            $displayPath = $folderDialog.SelectedPath
            if ($displayPath.Length -gt 35) {
                $displayPath = '...' + $displayPath.Substring($displayPath.Length - 32)
            }
            $lblSource.Text = $displayPath
            $lblSource.ForeColor = [System.Drawing.Color]::DarkGreen
            Write-Host "Source directory selected: $($folderDialog.SelectedPath)"
        }
    })

    $lblDest.Add_Click({
        $folderDialog = New-Object System.Windows.Forms.FolderBrowserDialog
        $folderDialog.Description = 'Select the destination directory for backup'
        $folderDialog.ShowNewFolderButton = $true
        
        if ($lblDest.Tag) {
            $folderDialog.SelectedPath = $lblDest.Tag
        }
        
        if ($folderDialog.ShowDialog() -eq 'OK') {
            $lblDest.Tag = $folderDialog.SelectedPath
            $displayPath = $folderDialog.SelectedPath
            if ($displayPath.Length -gt 32) {
                $displayPath = '...' + $displayPath.Substring($displayPath.Length - 29)
            }
            $lblDest.Text = $displayPath
            $lblDest.ForeColor = [System.Drawing.Color]::DarkGreen
            Write-Host "Destination directory selected: $($folderDialog.SelectedPath)"
        }
    })

    # Add tooltips for the directory labels
    $tt.SetToolTip($lblSource, 'Click to browse and select the source directory to backup')
    $tt.SetToolTip($lblDest, 'Click to browse and select the destination directory for the backup')

    # Main backup operation
    $btn.Add_Click({
        try {
            # Validate that both directories are selected
            if (-not $lblSource.Tag -or -not $lblDest.Tag) {
                [System.Windows.Forms.MessageBox]::Show(
                    'Please select both source and destination directories before starting the backup.',
                    'Missing Directory Selection',
                    'OK',
                    'Warning'
                ) | Out-Null
                return
            }

            $sourcePath = $lblSource.Tag
            $destPath = $lblDest.Tag

            # Validate that source directory exists
            if (-not (Test-Path -Path $sourcePath -PathType Container)) {
                [System.Windows.Forms.MessageBox]::Show(
                    "Source directory does not exist or is not accessible: $sourcePath",
                    'Source Directory Error',
                    'OK',
                    'Error'
                ) | Out-Null
                return
            }

            # Create destination directory if it doesn't exist
            if (-not (Test-Path -Path $destPath -PathType Container)) {
                try {
                    New-Item -Path $destPath -ItemType Directory -Force | Out-Null
                    Write-Host "Created destination directory: $destPath"
                } catch {
                    [System.Windows.Forms.MessageBox]::Show(
                        "Failed to create destination directory: $destPath`n$($_.Exception.Message)",
                        'Destination Directory Error',
                        'OK',
                        'Error'
                    ) | Out-Null
                    return
                }
            }

            # Confirm the backup operation
            $result = [System.Windows.Forms.MessageBox]::Show(
                "Ready to backup all files and subdirectories from:`n$sourcePath`n`nTo:`n$destPath`n`nThis operation may take a long time depending on the amount of data. Continue?",
                'Confirm Backup Operation',
                'YesNo',
                'Question'
            )
            
            if ($result -ne 'Yes') {
                Write-Host 'Backup operation cancelled by user.'
                return
            }

            # Set status bar to show backup starting
            if (Get-Command -Name Set-StatusBar -ErrorAction SilentlyContinue) {
                Set-StatusBar -Text 'Starting backup operation...'
            }

            Write-Host "Starting backup operation..."
            Write-Host "Source: $sourcePath"
            Write-Host "Destination: $destPath"

            # Store original power settings and set to not sleep when plugged in
            Write-Host "Configuring power settings to prevent sleep during backup..."
            try {
                # Get current AC power timeout setting
                $currentAcTimeout = & powercfg.exe /query SCHEME_CURRENT SUB_SLEEP STANDBYIDLE | Select-String "Current AC Power Setting Index:" | ForEach-Object { ($_ -split ": ")[1].Trim() }
                Write-Host "Current AC power timeout: $currentAcTimeout"
                
                # Set AC power to never sleep (0x00000000)
                & powercfg.exe /change standby-timeout-ac 0
                Write-Host "Set AC power to never sleep during backup."
            } catch {
                Write-Host "Warning: Could not modify power settings: $($_.Exception.Message)"
                $currentAcTimeout = $null
            }

            try {
                # Update status bar
                if (Get-Command -Name Set-StatusBar -ErrorAction SilentlyContinue) {
                    Set-StatusBar -Text 'Backup in progress - analyzing source directory...'
                }

                # Calculate total size for progress tracking (optional, but informative)
                Write-Host "Analyzing source directory for backup planning..."
                $totalSize = 0
                $fileCount = 0
                try {
                    Get-ChildItem -Path $sourcePath -Recurse -File -ErrorAction SilentlyContinue | ForEach-Object {
                        $totalSize += $_.Length
                        $fileCount++
                    }
                    Write-Host "Found $fileCount files totaling $([math]::Round($totalSize / 1GB, 2)) GB"
                } catch {
                    Write-Host "Could not calculate total size: $($_.Exception.Message)"
                }

                # Update status bar with backup progress
                if (Get-Command -Name Set-StatusBar -ErrorAction SilentlyContinue) {
                    Set-StatusBar -Text "Backup in progress - copying $fileCount files ($([math]::Round($totalSize / 1GB, 2)) GB)..."
                }

                # Use robocopy for reliable file copying with progress
                Write-Host "Starting file copy operation using robocopy..."
                $robocopyArgs = @(
                    "`"$sourcePath`"",
                    "`"$destPath`"",
                    '/E',           # Copy subdirectories, including empty ones
                    '/R:3',         # Retry 3 times on failed copies
                    '/W:5',         # Wait 5 seconds between retries
                    '/MT:8',        # Multi-threaded copying (8 threads)
                    '/ETA',         # Show estimated time of arrival
                    '/TEE',         # Output to console and log file
                    '/V'            # Verbose output
                )

                $robocopyProcess = Start-Process -FilePath 'robocopy.exe' -ArgumentList $robocopyArgs -NoNewWindow -PassThru -Wait
                
                # Check robocopy exit code (0-7 are success codes)
                if ($robocopyProcess.ExitCode -le 7) {
                    Write-Host "Backup completed successfully!"
                    
                    # Update status bar with success
                    if (Get-Command -Name Set-StatusBar -ErrorAction SilentlyContinue) {
                        Set-StatusBar -Text 'Backup completed successfully!' -TimeoutSeconds 10
                    }

                    [System.Windows.Forms.MessageBox]::Show(
                        "Backup completed successfully!`n`nSource: $sourcePath`nDestination: $destPath",
                        'Backup Complete',
                        'OK',
                        'Information'
                    ) | Out-Null
                } else {
                    Write-Host "Backup completed with warnings or errors. Robocopy exit code: $($robocopyProcess.ExitCode)"
                    
                    if (Get-Command -Name Set-StatusBar -ErrorAction SilentlyContinue) {
                        Set-StatusBar -Text 'Backup completed with warnings - check console for details' -TimeoutSeconds 15
                    }

                    [System.Windows.Forms.MessageBox]::Show(
                        "Backup completed with warnings or errors.`nRobocopy exit code: $($robocopyProcess.ExitCode)`n`nPlease check the console output for details.",
                        'Backup Complete with Warnings',
                        'OK',
                        'Warning'
                    ) | Out-Null
                }

            } catch {
                Write-Host "Backup operation failed: $($_.Exception.Message)"
                
                if (Get-Command -Name Set-StatusBar -ErrorAction SilentlyContinue) {
                    Set-StatusBar -Text 'Backup operation failed - check console for details' -TimeoutSeconds 10
                }

                [System.Windows.Forms.MessageBox]::Show(
                    "Backup operation failed:`n$($_.Exception.Message)",
                    'Backup Error',
                    'OK',
                    'Error'
                ) | Out-Null
            } finally {
                # Restore original power settings
                if ($currentAcTimeout -ne $null) {
                    try {
                        Write-Host "Restoring original power settings..."
                        if ($currentAcTimeout -eq "0x00000000") {
                            & powercfg.exe /change standby-timeout-ac 0
                        } else {
                            # Convert hex to decimal minutes for powercfg
                            $timeoutMinutes = [Convert]::ToInt32($currentAcTimeout, 16) / 60
                            & powercfg.exe /change standby-timeout-ac $timeoutMinutes
                        }
                        Write-Host "Power settings restored."
                    } catch {
                        Write-Host "Warning: Could not restore original power settings: $($_.Exception.Message)"
                    }
                } else {
                    Write-Host "No original power settings to restore."
                }
            }

        } catch {
            Write-Host "Unexpected error in Backup Files control: $($_.Exception.Message)"
            
            if (Get-Command -Name Set-StatusBar -ErrorAction SilentlyContinue) {
                Set-StatusBar -Text 'Backup operation error - check console for details' -TimeoutSeconds 10
            }
        }
    })

    # Add all controls to the panel
    $backupPanel.Controls.Add($lblSourceTitle)
    $backupPanel.Controls.Add($lblSource)
    $backupPanel.Controls.Add($lblDestTitle)
    $backupPanel.Controls.Add($lblDest)
    $backupPanel.Controls.Add($btn)

    # Add the panel to the parent (FlowLayoutPanel will handle positioning automatically)
    $Parent.Controls.Add($backupPanel)
    
    return $btn
}