<#
Controls\TraceRouteControl.ps1

Purpose:
  Adds a small button that runs `Test-NetConnection -TraceRoute` against a provided
  target (hostname or IP). The control expects the caller to pass a reference to a
  TextBox control that contains the target string.

Usage:
  . "$PSScriptRoot\Controls\TraceRouteControl.ps1"
  Add-TraceRouteButton -Parent $grpNet -TargetTextBox $txtPing -Location (New-Object System.Drawing.Point(10,170))

Notes:
  - Output is printed to the console. For UI display, we can pass an output TextBox
    control to append results instead.
#>

function Add-TraceRouteButton {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][System.Windows.Forms.Control]$Parent,
        [Parameter(Mandatory=$false)][System.Windows.Forms.TextBox]$TargetTextBox,
        [Parameter(Mandatory=$false)][System.Windows.Forms.TextBox]$PortTextBox,
        [Parameter(Mandatory=$false)][System.Windows.Forms.CheckBox]$UsePortCheckBox,
        [Parameter(Mandatory=$false)][System.Windows.Forms.CheckBox]$DetailedCheckBox,
        [Parameter(Mandatory=$false)][System.Drawing.Point]$Location = $(New-Object System.Drawing.Point(10,170)),
        [Parameter(Mandatory=$false)][System.Drawing.Size]$Size = $(New-Object System.Drawing.Size(80,24))
    )

    $btn = New-Object System.Windows.Forms.Button
    $btn.Text = 'TraceRoute'
    $btn.Size = $Size
    $btn.Location = $Location

    # Capture references into local variables to ensure the event handler closes over the correct objects
    $targetBox = $TargetTextBox
    $portBox = $PortTextBox
    $usePortBox = $UsePortCheckBox
    $detailedBox = $DetailedCheckBox
    $parentContainer = $Parent

    # Tooltip
    $tt = New-Object System.Windows.Forms.ToolTip
    $tt.AutoPopDelay = 20000
    $tt.InitialDelay = 400
    $tt.ReshowDelay = 100
    $tt.ShowAlways = $true
    $tt.SetToolTip($btn, 'Run a traceroute to the hostname or IP in the target textbox to see the network path taken. Results print to the console.')
    $btn.Tag = @{ ToolTip = $tt }

    # Helper: toggle enabled state based on whether the authoritative ping textbox contains text
    $toggleButtonState = {
        try {
            $currentText = $null
            if ($targetBox -and $targetBox -is [System.Windows.Forms.TextBox]) { $currentText = $targetBox.Text }
            elseif ($global:txtPing -and ($global:txtPing -is [System.Windows.Forms.TextBox])) { $currentText = $global:txtPing.Text }

            if ($currentText -and -not [string]::IsNullOrWhiteSpace($currentText)) {
                $btn.Enabled = $true
                $tt.SetToolTip($btn, "Run Test-NetConnection -TraceRoute against: $currentText")
            }
            else {
                $btn.Enabled = $false
                $tt.SetToolTip($btn, 'Enter a hostname or IP into the Ping box to enable TraceRoute')
            }
        } catch {
            # On any unexpected error, default to enabled
            $btn.Enabled = $true
        }
    }
    # Persist the toggle ScriptBlock on control Tags so event handlers can reliably invoke it later
    try {
        if ($targetBox -and ($targetBox -is [System.Windows.Forms.TextBox])) {
            if (-not $targetBox.Tag) { $targetBox.Tag = @{} }
            $targetBox.Tag.ToggleButtonState = $toggleButtonState
        }
        if ($global:txtPing -and ($global:txtPing -is [System.Windows.Forms.TextBox])) {
            if (-not $global:txtPing.Tag) { $global:txtPing.Tag = @{} }
            $global:txtPing.Tag.ToggleButtonState = $toggleButtonState
        }
    } catch { }

    # Initialize state by invoking the stored scriptblock if available, else fallback to the local block
    try {
        if ($targetBox -and $targetBox.Tag -and $targetBox.Tag.ToggleButtonState -is [scriptblock]) { & $targetBox.Tag.ToggleButtonState }
        elseif ($toggleButtonState -is [scriptblock]) { & $toggleButtonState }
    } catch { }

    # Attach TextChanged handlers that invoke the stored ScriptBlock from the sender.Tag to avoid closure issues
    if ($targetBox -and ($targetBox -is [System.Windows.Forms.TextBox])) {
        $targetBox.Add_TextChanged({ param($s,$e) if ($s.Tag -and $s.Tag.ToggleButtonState -is [scriptblock]) { & $s.Tag.ToggleButtonState } })
    }
    if (($global:txtPing) -and ($global:txtPing -is [System.Windows.Forms.TextBox]) -and ($global:txtPing -ne $targetBox)) {
        $global:txtPing.Add_TextChanged({ param($s,$e) if ($s.Tag -and $s.Tag.ToggleButtonState -is [scriptblock]) { & $s.Tag.ToggleButtonState } })
    }

    $btn.Add_Click({
        try {
            # Always prefer the global ping textbox as the authoritative source for hostname/IP
            if ($global:txtPing -and -not [string]::IsNullOrWhiteSpace($global:txtPing.Text)) {
                $target = $global:txtPing.Text
                Write-Host "Using target from global txtPing: '$target'"
            } else {
                Write-Host "TraceRoute requires a hostname or IP in the Ping textbox (global: `$global:txtPing`). Please enter a value and try again."
                return
            }

            # Build Test-NetConnection parameters based on provided global UI controls (if any)
            $params = @{ ComputerName = $target; TraceRoute = $true; ErrorAction = 'Stop' }

            # If a detailed checkbox is provided and checked, add InformationLevel
            if ($detailedBox -and $detailedBox.Checked) {
                $params['InformationLevel'] = 'Detailed'
            } elseif ($global:Net_Detailed) {
                $params['InformationLevel'] = 'Detailed'
            }

            # If port usage is enabled (either via provided checkbox or global), validate and include
            $usePort = $false
            if ($usePortBox) { $usePort = $usePortBox.Checked }
            if (-not $UsePortCheckBox -and $global:Net_UsePort) { $usePort = $true }

            if ($usePort) {
                $portVal = $null
                if ($portBox) { $portVal = $portBox.Text }
                if (-not $portBox -and $global:Net_Port) { $portVal = $global:Net_Port }

                if ([string]::IsNullOrWhiteSpace($portVal)) { Write-Host 'Port usage enabled but port textbox is empty. Please enter a numeric port.'; return }
                if (-not ($portVal -as [int])) { Write-Host 'Port must be a valid integer.'; return }
                $params['Port'] = [int]$portVal
            }

            Write-Host "Running TraceRoute to $target (this can take several seconds)..."
            $res = Test-NetConnection @params

            # Print a concise route listing if present
            if ($res.Traceroute) {
                $res.Traceroute | ForEach-Object { Write-Host "Hop $($_.Hop): $($_.Address) - $($_.ResponseTime)ms" }
            } else {
                Write-Host "TraceRoute produced no hop list; full result follows:"; $res | ForEach-Object { Write-Host $_ }
            }
        } catch {
            Write-Host "TraceRoute failed: $($_.Exception.Message)"
        } finally {
            if (Get-Command -Name Write-AsciiDivider -ErrorAction SilentlyContinue) { Write-AsciiDivider }
        }
    })

    $Parent.Controls.Add($btn)
    return $btn
}
