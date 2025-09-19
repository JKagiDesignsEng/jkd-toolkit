<#
Controls\CheckHealthControl.ps1

Purpose:
  Adds a small WinForms Button to run the DISM 'CheckHealth' command and print the
  output to the console. This control follows the same pattern as other Controls in
  this project: dot-source the file and call the factory function with the form.

Usage:
  . "$PSScriptRoot\Controls\CheckHealthControl.ps1"
  Add-CheckHealthButton -Form $form -Location (New-Object System.Drawing.Point(200,20)) -Size (New-Object System.Drawing.Size(160,40))

Notes:
  - DISM `CheckHealth` requires administrative privileges. Ensure the calling process
    is elevated. The main script attempts to self-elevate on start.
  - The control writes DISM output to the console using `Write-Host`. If you prefer a
    different output sink (file or UI control), replace the `Write-Host` calls in the
    click handler.
#>

function Add-CheckHealthButton {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory=$true, HelpMessage='The WinForms parent Control (Form or GroupBox) to which the button will be added')]
    [System.Windows.Forms.Control]$Parent,

    [Parameter(Mandatory=$false, HelpMessage='Location to place the button relative to the parent control')]
    [System.Drawing.Point]$Location = $(New-Object System.Drawing.Point(10,20)),

    [Parameter(Mandatory=$false, HelpMessage='Size of the button')]
    [System.Drawing.Size]$Size = $(New-Object System.Drawing.Size(160,40))
  )

    # Create button UI
    $btn = New-Object System.Windows.Forms.Button
    $btn.Text = 'Check Health (DISM)'
    $btn.Size = $Size
    $btn.Location = $Location
  # Create and attach tooltip (plain-language explanation)
  $tt = New-Object System.Windows.Forms.ToolTip
  $tt.AutoPopDelay = 20000
  $tt.InitialDelay = 500
  $tt.ReshowDelay = 100
  $tt.ShowAlways = $true
  $tt.SetToolTip($btn, "Quickly checks Windows system files for known corruption. It only reports problems and does not change anything. Runs a system tool and prints results to the console.")
  # Keep tooltip alive by storing a reference on the button
  $btn.Tag = @{ ToolTip = $tt }

    # Click handler: run DISM checkhealth and stream output to the console.
    $btn.Add_Click({
        try {
            Write-Host 'Running: DISM /online /Cleanup-image /CheckHealth'
            $args = @('/online','/Cleanup-image','/CheckHealth')
            if ($global:LimitAccess) { $args += '/LimitAccess' }
            $output = & dism.exe @args 2>&1
            if ($output) {
                $output | ForEach-Object { Write-Host $_ }
            } else {
                Write-Host 'DISM returned no output.'
            }
        } catch {
            Write-Host "Error running DISM: $($_.Exception.Message)"
        }
    })

  $Parent.Controls.Add($btn)
  return $btn
}
