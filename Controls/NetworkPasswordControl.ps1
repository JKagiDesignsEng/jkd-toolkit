<#
Controls\NetworkPasswordControl.ps1

Purpose:
  Encapsulates the Network Password button (UI + logic) so the main script can dot-source
  this file and add the control to any WinForms form. Keeping UI controls in separate files
  improves maintainability and makes testing or reusing the control easier.

Usage:
  Dot-source this file from the main script (or any caller):
    . "$PSScriptRoot\Controls\NetworkPasswordControl.ps1"

  Then call the factory function to add the button to your form:
    Add-NetworkPasswordButton -Form $form -Location (New-Object System.Drawing.Point(20,20)) \
        -Size (New-Object System.Drawing.Size(160,40))

Behavior:
  - The function creates a WinForms Button with a click handler that runs `netsh`
    commands to enumerate stored Wi-Fi profiles and print the SSID and password (if
    stored) to the console using `Write-Host`.
  - This file intentionally does not export module members, because it is intended to
    be dot-sourced (not imported as a module). Removing `Export-ModuleMember` prevents
    the "can only be called from inside a module" error when dot-sourced.

Security / Elevation:
  - Reading Wi-Fi profile keys requires administrative privileges. Ensure the calling
    process is elevated (the main script handles self-elevation). If the process is not
    elevated, `netsh` will produce limited output or fail for protected keys.

Modifying the click handler:
  - The click handler is a self-contained scriptblock. If you want to change the
    output destination (for example write to a file or to a GUI TextBox), replace the
    `Write-Host` calls inside the handler with a function call or UI update.
#>

function Add-NetworkPasswordButton {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory=$true, HelpMessage='The WinForms parent Control (Form or GroupBox) to which the button will be added')]
    [System.Windows.Forms.Control]$Parent,

    [Parameter(Mandatory=$false, HelpMessage='Location to place the button relative to the parent control')]
    [System.Drawing.Point]$Location = $(New-Object System.Drawing.Point(10,20)),

    [Parameter(Mandatory=$false, HelpMessage='Size of the button')]
    [System.Drawing.Size]$Size = $(New-Object System.Drawing.Size(160,40))
  )

    # Create the button control
    $btn = New-Object System.Windows.Forms.Button
    $btn.Text = 'Show Network Passwords'
    $btn.Size = $Size
    $btn.Location = $Location
  # Tooltip: explain what this button does in plain language
  $tt = New-Object System.Windows.Forms.ToolTip
  $tt.AutoPopDelay = 20000
  $tt.InitialDelay = 500
  $tt.ReshowDelay = 100
  $tt.ShowAlways = $true
  $tt.SetToolTip($btn, "Lists saved Wi-Fi networks and the stored passwords (if available). This requires administrator rights and will print results to the console. Do not run on shared machines without permission.")
  $btn.Tag = @{ ToolTip = $tt }

    # Click handler: enumerate Wi-Fi profiles and print SSID/password pairs to the console.
    # Keep the handler minimal and avoid UI-blocking long operations. If this needs to run
    # for a long time, consider running the netsh calls in a background job and updating
    # the UI when complete.
    $btn.Add_Click({
        try {
            # Query stored Wi-Fi profiles. `Select-String 'All User Profile'` filters the
            # standard netsh output line that contains profile names on English systems.
            # If you need localization, change the match string or extract profiles with
            # a different approach.
            $profiles = netsh wlan show profiles 2>$null |
                        Select-String 'All User Profile' |
                        ForEach-Object { ($_.ToString().Split(':')[-1]).Trim() }

            if (-not $profiles -or $profiles.Count -eq 0) {
                # No profiles found: inform the user via console. The main script prefers
                # console-only output to avoid message boxes.
                Write-Host 'No Wi-Fi profiles found.'
                return
            }

            foreach ($name in $profiles) {
                # For each profile, query key material in cleartext. This requires elevation
                # and may not produce a 'Key Content' line if the key is not stored.
                $details = netsh wlan show profile name="$name" key=clear 2>$null
                $keyLine = $details | Select-String 'Key Content'

                if ($keyLine) {
                    # Extract the password from the line 'Key Content : <value>' by splitting
                    # on ':' and trimming whitespace. This is resilient to additional spacing.
                    $password = ($keyLine.ToString().Split(':')[-1]).Trim()
                } else {
                    $password = '(no key found or not stored)'
                }

                # Output: SSID and Password pairs. Replace these with a file write or GUI
                # update if you prefer a different output destination.
                Write-Host "SSID: $name"
                Write-Host "Password: $password"
                Write-Host '---------------------------'
            }
        } catch {
            # Catch unexpected runtime errors and write to console. Avoid throwing to the
            # caller to keep UI responsiveness.
            Write-Host "Error retrieving Wi-Fi passwords: $($_.Exception.Message)"
        }
    })

  # Add the button to the provided parent control (Form or GroupBox) and return it.
  $Parent.Controls.Add($btn)
    return $btn
}


