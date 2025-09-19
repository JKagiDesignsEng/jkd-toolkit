<#
Controls\RunMicrosoftUpdateControl.ps1

Purpose:
  Adds a WinForms button that runs Windows Update and searches for driver updates.

Behavior:
  - Provides a single `Add-RunMicrosoftUpdateButton` function which builds a button
    and attaches a click handler that performs a best-effort update workflow:
      1) Use the PSWindowsUpdate module if available to search/install updates.
      2) Fallback to `UsoClient StartScan` / `UsoClient StartInstall` on supported systems.
      3) Attempt driver scan via `pnputil /scan-devices` and `Get-WindowsUpdate -MicrosoftUpdate` where appropriate.
      4) When `winget` or `choco` packages for drivers are available (rare), it will not auto-install them but will print findings.

Notes:
  - This control prints progress to the console. It performs non-interactive operations and will not attempt UI-driven installers.
  - Most update operations require administrative privileges; the main app already attempts to self-elevate.
  - Long-running operations are executed in background runspaces to keep the UI responsive.
#>

function Add-RunMicrosoftUpdateButton {
    param(
        [Parameter(Mandatory=$true)][System.Windows.Forms.Control]$Parent,
        [Parameter(Mandatory=$false)][System.Drawing.Point]$Location = $(New-Object System.Drawing.Point(10,20)),
        [Parameter(Mandatory=$false)][System.Drawing.Size]$Size = $(New-Object System.Drawing.Size(160,40))
    )

    $btn = New-Object System.Windows.Forms.Button
    $btn.Text = 'Run Microsoft Update'
    $btn.Size = $Size
    # If parent is a FlowLayoutPanel, the panel will position children. Use Margin to control spacing.
    if ($Parent -is [System.Windows.Forms.FlowLayoutPanel]) {
        $btn.Margin = New-Object System.Windows.Forms.Padding(0,0,0,8)
    } else {
        $btn.Location = $Location
    }
    # Give the button a predictable name so closures can find it reliably
    $btn.Name = 'btnRunMicrosoftUpdate'

    # Detailed tooltip explaining behavior and best-effort driver checks
    $tt = New-Object System.Windows.Forms.ToolTip
    $tt.AutoPopDelay = 30000
    $tt.InitialDelay = 500
    $tt.ReshowDelay = 100
    $tt.ShowAlways = $true
    $ttText = @"
Run Windows Update and attempt a driver update scan (best-effort).

What this button does (best-effort):
 - Tries to use the PSWindowsUpdate PowerShell module (preferred) to list and install Microsoft Updates.
 - If PSWindowsUpdate is not present, attempts `UsoClient` commands on supported Windows builds to trigger scan/install.
 - Runs a device driver scan using `pnputil /scan-devices` and reports results; when additional driver update commands are available they are printed so an administrator can act.
 - All output is printed to the console. This operation may be long-running and requires admin rights.

Notes:
 - This control will not forcibly reboot your machine; it will print if a reboot is recommended.
 - If you need interactive driver installers or vendor-specific packages, run them manually after reviewing the console output.
"@
    $tt.SetToolTip($btn, $ttText)
    $btn.Tag = @{ ToolTip = $tt }

    # Click handler: perform update workflow in background runspace to keep UI responsive
    $btn.Add_Click({
        try {
            Write-Host 'Starting Microsoft Update workflow...'
            # Disable the button via its Name to avoid closure scope issues
            try {
                $found = $null
                [System.Windows.Forms.Application]::OpenForms | ForEach-Object {
                    $c = $_.Controls.Find('btnRunMicrosoftUpdate', $true)
                    if ($c -and $c.Count -gt 0) { $found = $c[0]; return }
                }
                if ($found -and $found.GetType().GetProperty('Enabled')) { $found.Enabled = $false }
            } catch { }

            # Start the update workflow in a background job so UI remains responsive.
            $jobScript = {
                try {
                    # 1) Try PSWindowsUpdate module
                    $mod = Get-Module -ListAvailable -Name PSWindowsUpdate -ErrorAction SilentlyContinue
                    if (-not $mod) {
                        Write-Host 'PSWindowsUpdate module not found. Attempting to install from PSGallery (if online)...'
                        try {
                            Install-PackageProvider -Name NuGet -Force -ErrorAction SilentlyContinue | Out-Null
                            Install-Module -Name PSWindowsUpdate -Force -Scope AllUsers -ErrorAction Stop
                            Import-Module PSWindowsUpdate -ErrorAction Stop
                            $mod = Get-Module -Name PSWindowsUpdate -ListAvailable
                        } catch {
                            Write-Host "Failed to install PSWindowsUpdate: $($_.Exception.Message)"
                        }
                    } else {
                        Import-Module PSWindowsUpdate -ErrorAction SilentlyContinue
                    }

                    if (Get-Module -Name PSWindowsUpdate) {
                        Write-Host 'Using PSWindowsUpdate to check for and install updates (this may take a while)...'
                        try {
                            $avail = Get-WindowsUpdate -AcceptAll -IgnoreReboot -ListOnly -ErrorAction SilentlyContinue
                            if ($avail -and $avail.Count -gt 0) {
                                Write-Host "Found $($avail.Count) updates. Installing..."
                                Install-WindowsUpdate -AcceptAll -IgnoreReboot -AutoReboot:$false -Confirm:$false -ErrorAction SilentlyContinue | ForEach-Object { Write-Host $_ }
                            } else {
                                Write-Host 'No applicable Microsoft updates found via PSWindowsUpdate.'
                            }
                        } catch {
                            Write-Host "PSWindowsUpdate operation failed: $($_.Exception.Message)"
                        }
                    } else {
                        # 2) Fallback to UsoClient if available
                        $uso = Get-Command UsoClient -ErrorAction SilentlyContinue
                        if ($uso) {
                            Write-Host 'Triggering Windows Update scan via UsoClient...'
                            try {
                                & UsoClient StartScan 2>&1 | ForEach-Object { Write-Host $_ }
                                Start-Sleep -Seconds 2
                                & UsoClient StartDownload 2>&1 | ForEach-Object { Write-Host $_ }
                                Start-Sleep -Seconds 2
                                & UsoClient StartInstall 2>&1 | ForEach-Object { Write-Host $_ }
                                Write-Host 'UsoClient triggered. Windows Update may continue in the background.'
                            } catch {
                                Write-Host "UsoClient operations failed: $($_.Exception.Message)"
                            }
                        } else {
                            Write-Host 'PSWindowsUpdate module and UsoClient are unavailable. Cannot run automatic Windows Update from here.'
                        }
                    }

                    # 3) Driver scan using pnputil (best-effort)
                    $pnputil = Get-Command pnputil.exe -ErrorAction SilentlyContinue
                    if ($pnputil) {
                        Write-Host 'Running pnputil /scan-devices to check for driver updates (best-effort)...'
                        try {
                            & pnputil.exe /scan-devices 2>&1 | ForEach-Object { Write-Host $_ }
                        } catch {
                            Write-Host "pnputil scan-devices failed: $($_.Exception.Message)"
                        }
                    } else {
                        Write-Host 'pnputil not found on PATH; skipping pnputil driver scan.'
                    }

                    # 4) Report on Windows Update service status and pending reboot
                    try {
                        $svc = Get-Service -Name wuauserv -ErrorAction SilentlyContinue
                        if ($svc) { Write-Host "Windows Update service state: $($svc.Status)" }
                    } catch { }
                    try {
                        $pending = $false
                        $keys = @(
                            'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired',
                            'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager'
                        )
                        foreach ($k in $keys) { if (Test-Path $k) { Write-Host "Pending reboot indication: $k"; $pending = $true } }
                        if ($pending) { Write-Host 'One or more indicators suggest a reboot may be required to complete updates.' }
                    } catch { }

                    Write-Host 'Microsoft Update workflow complete.'
                } catch {
                    Write-Host "Error in update workflow: $($_.Exception.Message)"
                }
            }

            # Start the background job with a stable name so the status button can find it
            $job = Start-Job -Name 'RunMicrosoftUpdate' -ScriptBlock $jobScript
            Write-Host "Started background job (Id: $($job.Id)) to run updates. Use Get-Job/Receive-Job to inspect output if needed."
            if (Get-Command -Name Write-Divider -ErrorAction SilentlyContinue) { Write-Divider }
            # Poll job in background and re-enable button when done
            $timer = New-Object System.Windows.Forms.Timer
            $timer.Interval = 2000
            $timer.Add_Tick({
                try {
                    if ($job -and (Get-Job -Id $job.Id -ErrorAction SilentlyContinue)) {
                        $st = (Get-Job -Id $job.Id).State
                        if ($st -eq 'Completed' -or $st -eq 'Failed' -or $st -eq 'Stopped') {
                            try { Receive-Job -Id $job.Id -Keep | ForEach-Object { Write-Host $_ } } catch { }
                            if (Get-Command -Name Write-Divider -ErrorAction SilentlyContinue) { Write-Divider }
                            try { Remove-Job -Id $job.Id -Force -ErrorAction SilentlyContinue } catch { }
                            if ($timer) { $timer.Stop() }
                            try {
                                $found = $null
                                [System.Windows.Forms.Application]::OpenForms | ForEach-Object {
                                    $c = $_.Controls.Find('btnRunMicrosoftUpdate', $true)
                                    if ($c -and $c.Count -gt 0) { $found = $c[0]; return }
                                }
                                if ($found -and $found.GetType().GetProperty('Enabled')) { $found.Enabled = $true }
                            } catch { }
                        }
                    } else {
                        if ($timer) { $timer.Stop() }
                        try {
                            $found = $null
                            [System.Windows.Forms.Application]::OpenForms | ForEach-Object {
                                $c = $_.Controls.Find('btnRunMicrosoftUpdate', $true)
                                if ($c -and $c.Count -gt 0) { $found = $c[0]; return }
                            }
                            if ($found -and $found.GetType().GetProperty('Enabled')) { $found.Enabled = $true }
                        } catch { }
                    }
                } catch { if ($timer) { $timer.Stop() }; try { $found = $null; [System.Windows.Forms.Application]::OpenForms | ForEach-Object { $c = $_.Controls.Find('btnRunMicrosoftUpdate', $true); if ($c -and $c.Count -gt 0) { $found = $c[0]; return } }; if ($found -and $found.GetType().GetProperty('Enabled')) { $found.Enabled = $true } } catch { } }
            })
            $timer.Start()

        } catch {
            Write-Host "Failed to start Microsoft Update workflow: $($_.Exception.Message)"
            try {
                $found = $null
                [System.Windows.Forms.Application]::OpenForms | ForEach-Object {
                    $c = $_.Controls.Find('btnRunMicrosoftUpdate', $true)
                    if ($c -and $c.Count -gt 0) { $found = $c[0]; return }
                }
                if ($found -and $found.GetType().GetProperty('Enabled')) { $found.Enabled = $true }
            } catch { }
        }
    })

    $Parent.Controls.Add($btn)
    # --- Add 'Get Update Status' button under the main button ---
    $statusBtn = New-Object System.Windows.Forms.Button
    $statusBtn.Text = 'Get Update Status'
    $statusBtn.Size = (New-Object System.Drawing.Size(160,24))
    # If parent is FlowLayoutPanel, use Margin; otherwise compute Location as before
    if ($Parent -is [System.Windows.Forms.FlowLayoutPanel]) {
        $statusBtn.Margin = New-Object System.Windows.Forms.Padding(0,0,0,8)
        $statusY = 0
    } else {
        $statusX = $btn.Location.X
        $statusY = $btn.Location.Y + $btn.Size.Height + 8
        $statusBtn.Location = New-Object System.Drawing.Point -ArgumentList $statusX, $statusY
    }
    $statusBtn.Name = 'btnGetUpdateStatus'
    $tt.SetToolTip($statusBtn, "Query the background update job started by 'Run Microsoft Update' and show its state and recent output.")

    $statusBtn.Add_Click({
        try {
            # Find the most recent job started by the RunMicrosoftUpdate button
            $job = Get-Job -Name 'RunMicrosoftUpdate' -ErrorAction SilentlyContinue | Sort-Object Id -Descending | Select-Object -First 1
            if (-not $job) {
                [System.Windows.Forms.MessageBox]::Show('No RunMicrosoftUpdate job found in this session. Start the update workflow first.','Update Status',[System.Windows.Forms.MessageBoxButtons]::OK,[System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
                return
            }

            $state = $job.State
            $hasMore = $job.HasMoreData
            $msg = "Job Id: $($job.Id)`nState: $state`nHasMoreData: $hasMore"

            if ($state -in @('Completed','Failed','Stopped')) {
                # Try to get the output (keep it so multiple inspections are possible)
                try {
                    $out = Receive-Job -Id $job.Id -Keep -ErrorAction SilentlyContinue | Out-String
                    if ($out) { $msg += "`n`nOutput:`n$out" }
                } catch {
                    $msg += "`n`n(Output could not be retrieved: $($_.Exception.Message))"
                }
            } else {
                $msg += "`n`nNote: Job is still running. Use Receive-Job -Id $($job.Id) -Wait -Keep in a console to capture output when it completes."
            }

            [System.Windows.Forms.MessageBox]::Show($msg,'Update Status',[System.Windows.Forms.MessageBoxButtons]::OK,[System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
        } catch {
            [System.Windows.Forms.MessageBox]::Show("Error querying update job: $($_.Exception.Message)") | Out-Null
        }
    })

    $Parent.Controls.Add($statusBtn)
    # Shift other controls that sit below the new status button so they don't overlap
    try {
        $shiftHeight = $statusBtn.Size.Height + 8
        foreach ($ctrl in $Parent.Controls) {
            if ($null -eq $ctrl) { continue }
            # Skip the two buttons we just added
            if ($ctrl.Name -in @('btnRunMicrosoftUpdate','btnGetUpdateStatus')) { continue }
            try {
                $loc = $ctrl.Location
                if ($loc.Y -ge $statusY) {
                    $newY = $loc.Y + $shiftHeight
                    $newX = $loc.X
                    $ctrl.Location = New-Object System.Drawing.Point -ArgumentList $newX, $newY
                }
            } catch { }
        }
    } catch { }

    # Also handle controls added later (for example, Toggle Dark Mode is added by the main script after this control)
    try {
        $onAdded = {
            param($sender, $e)
            try {
                $added = $e.Control
                if ($null -eq $added) { return }
                if ($added.Name -in @('btnRunMicrosoftUpdate','btnGetUpdateStatus')) { return }
                # If the newly added control would overlap the status button, shift it down
                $aLoc = $added.Location
                if ($aLoc.Y -ge $statusY) {
                    $newY = $aLoc.Y + $shiftHeight
                    $added.Location = New-Object System.Drawing.Point -ArgumentList $aLoc.X, $newY
                }
            } catch { }
        }
        $Parent.add_ControlAdded($onAdded)
    } catch { }

    return $btn
}
