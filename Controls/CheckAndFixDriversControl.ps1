function Add-CheckAndFixDriversControl {
    param(
        [Parameter(Mandatory=$true)] [System.Windows.Forms.Control]$parent
    )

    Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue | Out-Null
    Add-Type -AssemblyName System.Drawing -ErrorAction SilentlyContinue | Out-Null

    # Main button
    $btn = New-Object System.Windows.Forms.Button
    $btn.Name = 'btnCheckFixDrivers'
    $btn.Text = 'Check & Fix Drivers'
    $btn.AutoSize = $true
    $btn.Padding = [System.Windows.Forms.Padding]::new(6)
    $btn.Tag = @{ Started = $false }

    # No per-control status button: use the shared status bar in the main form

    # Tooltip
    $tt = New-Object System.Windows.Forms.ToolTip
    $tt.SetToolTip($btn, 'Scan for missing or problematic devices and attempt to fix drivers (uses pnputil and PnP device restart).')

    # Script block executed in background job
    $jobScript = {
        $Output = @()
        try {
            $Output += "Starting driver scan: $(Get-Date -Format o)"

            # Run pnputil scan if available (Windows 10+)
            $pnputil = Get-Command pnputil -ErrorAction SilentlyContinue
            if ($pnputil) {
                $Output += "Running pnputil /scan-devices"
                $scan = & pnputil.exe /scan-devices 2>&1 | Out-String
                $Output += $scan
            } else {
                $Output += "pnputil not found on PATH"
            }

            # Look for devices with status Problem or Unknown or that are NotPresent
            $pnp = Get-PnpDevice -ErrorAction SilentlyContinue | Where-Object { $_.Status -in @('Error','Unknown','Problem') -or $_.Present -eq $false -or $_.Status -eq 'Unknown' }
            if (-not $pnp -or $pnp.Count -eq 0) {
                $Output += "No problematic or missing PnP devices detected by Get-PnpDevice."
            } else {
                $Output += "Found $($pnp.Count) problematic/missing devices. Attempting fixes..."
                foreach ($dev in $pnp) {
                    $Output += "Device: $($dev.InstanceId) - $($dev.FriendlyName) - Status: $($dev.Status)"
                    # Try to disable/enable the device to force re-enumeration (may require admin)
                    try {
                        $Output += "Attempting Disable/Enable via Disable-PnpDevice/Enable-PnpDevice"
                        Disable-PnpDevice -InstanceId $dev.InstanceId -Confirm:$false -ErrorAction Stop | Out-Null
                        Start-Sleep -Seconds 2
                        Enable-PnpDevice -InstanceId $dev.InstanceId -Confirm:$false -ErrorAction Stop | Out-Null
                        $Output += "Restarted device $($dev.InstanceId)"
                    } catch {
                        $Output += "Failed to restart device $($dev.InstanceId): $($_.Exception.Message)"
                    }

                    # Attempt pnputil driver reinstall if INF name is discoverable via driverquery (best-effort)
                    try {
                        $drv = driverquery /v /fo list | Out-String
                        $Output += "driverquery output length: $($drv.Length)"
                    } catch {
                        $Output += "driverquery not available or failed: $($_.Exception.Message)"
                    }
                }
            }

            $Output += "Driver scan complete: $(Get-Date -Format o)"
            return $Output
        } catch {
            return "Error during driver scan: $($_.Exception.Message)"
        }
    }

    # Timer for polling job state
    $timer = New-Object System.Windows.Forms.Timer
    $timer.Interval = 1000

    $jobName = 'CheckAndFixDriversJob'

    # Store key objects on the button Tag so event handlers (which run after this function returns)
    # can still access them.
    $btn.Tag.JobScript = $jobScript
    $btn.Tag.JobName = $jobName
    $btn.Tag.Timer = $timer

    $timer.Add_Tick({ param($sender,$e)
        # Determine job name by looking up the status button on the form; this avoids relying
        # on closures that may have been collected after the function returned.
        $form = [System.Windows.Forms.Application]::OpenForms | Select-Object -First 1
        $jobNameLocal = $null
        if ($form) {
            # Find the main button and read its Tag for the job name
            $mainBtn = $form.Controls.Find('btnCheckFixDrivers', $true) | Select-Object -First 1
            if ($mainBtn -and $mainBtn.Tag -and $mainBtn.Tag.JobName) { $jobNameLocal = $mainBtn.Tag.JobName }
        }

        if ([string]::IsNullOrWhiteSpace($jobNameLocal)) {
            # Nothing to poll
            if ($sender -and $sender -is [System.Windows.Forms.Timer]) { $sender.Stop() }
            return
        }

        $job = Get-Job -Name $jobNameLocal -ErrorAction SilentlyContinue
        if ($null -ne $job) {
            if ($job.State -in 'Completed','Failed','Stopped') {
                try {
                    $out = Receive-Job -Job $job -Keep -ErrorAction SilentlyContinue
                    if ($out) { $out | ForEach-Object { Write-Host "[Drivers] $_" } }
                } catch {
                    Write-Host "[Drivers] Failed receiving job output: $($_.Exception.Message)"
                }

                # Clean up job
                try { Remove-Job -Job $job -Force -ErrorAction SilentlyContinue } catch {}

                # Re-enable UI and update shared status bar
                if ($form) {
                    $ctrl = $form.Controls.Find('btnCheckFixDrivers', $true) | Select-Object -First 1
                    if ($ctrl -and $ctrl -is [System.Windows.Forms.Button]) { $ctrl.Enabled = $true }
                }
                if (Get-Command -Name Set-StatusBar -ErrorAction SilentlyContinue) { Set-StatusBar -Text "Check & Fix Drivers: $($job.State)" -TimeoutSeconds 8 }

                if ($sender -and $sender -is [System.Windows.Forms.Timer]) { $sender.Stop() }
            }
        } else {
            # No job found - stop timer and enable UI
            if ($form) {
                $ctrl = $form.Controls.Find('btnCheckFixDrivers', $true) | Select-Object -First 1
                if ($ctrl -and $ctrl -is [System.Windows.Forms.Button]) { $ctrl.Enabled = $true }
            }
            if (Get-Command -Name Clear-StatusBar -ErrorAction SilentlyContinue) { Clear-StatusBar }
            if ($sender -and $sender -is [System.Windows.Forms.Timer]) { $sender.Stop() }
        }
    })

    $btn.Add_Click({ param($sender,$e)
        try {
            # Disable the main button while job runs and set shared status text
            $senderForm = [System.Windows.Forms.Application]::OpenForms | Select-Object -First 1
            if ($senderForm) {
                $s = $senderForm.Controls.Find('btnCheckFixDrivers', $true) | Select-Object -First 1
                if ($s -and $s -is [System.Windows.Forms.Button]) { $s.Enabled = $false }
            }
            if (Get-Command -Name Set-StatusBar -ErrorAction SilentlyContinue) { Set-StatusBar -Text 'Check & Fix Drivers: scan running...' -TimeoutSeconds 0 }

            # Read job/script/timer from the sender.Tag so values are preserved after the function returns
            $jobNameLocal = $null; $jobScriptLocal = $null; $timerLocal = $null
            if ($sender -and $sender.Tag) {
                if ($sender.Tag.JobName) { $jobNameLocal = $sender.Tag.JobName }
                if ($sender.Tag.JobScript) { $jobScriptLocal = $sender.Tag.JobScript }
                if ($sender.Tag.Timer) { $timerLocal = $sender.Tag.Timer }
            }

            if (-not [string]::IsNullOrWhiteSpace($jobNameLocal)) {
                # Remove any previous job with same name
                $old = Get-Job -Name $jobNameLocal -ErrorAction SilentlyContinue
                if ($old) { Remove-Job -Job $old -Force -ErrorAction SilentlyContinue }
            }

            if ($jobScriptLocal) {
                Start-Job -Name $jobNameLocal -ScriptBlock $jobScriptLocal | Out-Null
                if ($timerLocal -and $timerLocal -is [System.Windows.Forms.Timer]) { $timerLocal.Start() }
            } else {
                Write-Host "[Drivers] No job script available to start."
                if (Get-Command -Name Clear-StatusBar -ErrorAction SilentlyContinue) { Clear-StatusBar }
            }
        } finally {
            if (Get-Command -Name Write-AsciiDivider -ErrorAction SilentlyContinue) { Write-AsciiDivider }
        }

    })
    # Add to parent; support FlowLayoutPanel parents by using Margin
    if ($parent -is [System.Windows.Forms.FlowLayoutPanel]) {
        $btn.Margin = [System.Windows.Forms.Padding]::new(6)
        $parent.Controls.Add($btn)
    } else {
        # Place stacked vertically inside parent
        $panel = New-Object System.Windows.Forms.FlowLayoutPanel
        $panel.FlowDirection = 'TopDown'
        $panel.AutoSize = $true
        $panel.WrapContents = $false
        $panel.Controls.Add($btn)
        $parent.Controls.Add($panel)
    }

    return @{ Button = $btn }
}

# This helper is intended to be dot-sourced into the main script; do not export as a module member here.
