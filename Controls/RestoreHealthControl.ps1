<#
Controls\RestoreHealthControl.ps1

Purpose:
  Adds a WinForms Button that runs the DISM 'RestoreHealth' command and prints output
  to the console. Follows the same pattern as other Controls: dot-source and call the
  factory function with the form.

Usage:
  . "$PSScriptRoot\Controls\RestoreHealthControl.ps1"
  Add-RestoreHealthButton -Form $form -Location (New-Object System.Drawing.Point(380,20)) -Size (New-Object System.Drawing.Size(160,40))

Notes:
  - DISM `RestoreHealth` requires administrative privileges. Ensure the calling
    process is elevated. The main script attempts to self-elevate on start.
  - The control writes DISM output to the console using `Write-Host`. Replace with
    file or UI updates if you prefer a different output destination.
#>

function Add-RestoreHealthButton {
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
    $btn.Text = 'Restore Health (DISM)'
    $btn.Size = $Size
    $btn.Location = $Location
  # Create and attach tooltip (plain-language explanation)
  $tt = New-Object System.Windows.Forms.ToolTip
  $tt.AutoPopDelay = 20000
  $tt.InitialDelay = 500
  $tt.ReshowDelay = 100
  $tt.ShowAlways = $true
  $tt.SetToolTip($btn, "Attempts to repair Windows system files using a trusted system tool. This may download or use local system files and can take some time. Results are printed to the console.")
  $btn.Tag = @{ ToolTip = $tt }

    # Click handler: run DISM RestoreHealth and stream output to the console.
    $btn.Add_Click({
        try {
            Write-Host 'Running: DISM /online /Cleanup-image /RestoreHealth'
            $args = @('/online','/Cleanup-image','/RestoreHealth')
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
