<#
Controls\CheckDiskControl.ps1

Purpose:
  Adds a WinForms button that runs `chkdsk C: /f` and streams output to the console.
  The control prompts the user for confirmation because the command may schedule a
  disk check on reboot if the volume is in use.
#>

function Add-CheckDiskButton {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory=$true)] [System.Windows.Forms.Control]$Parent,
    [Parameter(Mandatory=$false)] [System.Drawing.Point]$Location = $(New-Object System.Drawing.Point(10,120)),
    [Parameter(Mandatory=$false)] [System.Drawing.Size]$Size = $(New-Object System.Drawing.Size(160,40))
  )

  $btn = New-Object System.Windows.Forms.Button
  $btn.Text = 'Check Disk For Errors'
  $btn.Size = $Size
  $btn.Location = $Location
  # Create and attach tooltip, plain-language explanation
  $tt = New-Object System.Windows.Forms.ToolTip
  $tt.AutoPopDelay = 20000
  $tt.InitialDelay = 500
  $tt.ReshowDelay = 100
  $tt.ShowAlways = $true
  $tt.SetToolTip($btn, "Scans the main drive (C:) for file system errors and attempts to fix them. If the drive is in use, the tool may schedule the check to run at next reboot. Results are printed to the console.")
  $btn.Tag = @{ ToolTip = $tt }

  $btn.Add_Click({
    try {
      try {
        Write-Host "About to run: chkdsk C: /f"
        $confirm = Read-Host 'Continue? This may schedule a check on next reboot if the volume is locked. (Y/N)'
        if ($confirm -ne 'Y' -and $confirm -ne 'y') { Write-Host 'Aborted by user.'; return }

        # Inform about elevation requirement
        $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
        if (-not $isAdmin) { Write-Host 'Warning: chkdsk may require administrative privileges to run; running anyway.' }

        Write-Host 'Running: chkdsk C: /f'
        try {
          $output = & chkdsk.exe 'C:' '/f' 2>&1
          if ($output) { $output | ForEach-Object { Write-Host $_ } } else { Write-Host 'chkdsk returned no output.' }
        } catch {
          Write-Host "Error running chkdsk: $($_.Exception.Message)"
        }
      } catch {
        Write-Host "Unexpected error in Check Disk control: $($_.Exception.Message)"
      }
    } finally {
      if (Get-Command -Name Write-AsciiDivider -ErrorAction SilentlyContinue) { Write-AsciiDivider }
    }
  })
  # Divider will run from the finally block above to ensure it always executes.

  $Parent.Controls.Add($btn)
  return $btn
}
