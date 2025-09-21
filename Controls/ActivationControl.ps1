<#
Controls\ActivationControl.ps1

Purpose:
  Provides a button that checks Windows activation status and attempts a minimal,
  non-destructive action to reduce visible overlays. Note: there is no supported
  registry key to reliably hide the activation watermark; this control performs a
  best-effort check and optionally toggles a harmless desktop flag.

Behavior:
  - Runs `slmgr /xpr` to check activation state and prints the result to the console.
  - If not activated, the control can set `HKCU:\Control Panel\Desktop\PaintDesktopVersion`
    to 0 (this may not remove the activation watermark but is harmless).
#>

function Add-ActivationButton {
    param(
        [Parameter(Mandatory=$true)][System.Windows.Forms.Control]$Parent,
        [Parameter(Mandatory=$false)][System.Drawing.Point]$Location = $(New-Object System.Drawing.Point(10,120)),
        [Parameter(Mandatory=$false)][System.Drawing.Size]$Size = $(New-Object System.Drawing.Size(160,40))
    )

    $btn = New-Object System.Windows.Forms.Button
    $btn.Text = 'Check/Hide Activation'
    $btn.Size = $Size
    $btn.Location = $Location
    # Tooltip: plain-language explanation
    $tt = New-Object System.Windows.Forms.ToolTip
    $tt.AutoPopDelay = 20000
    $tt.InitialDelay = 500
    $tt.ReshowDelay = 100
    $tt.ShowAlways = $true
    $tt.SetToolTip($btn, "Checks whether Windows is activated and prints the result. If possible, the button will apply a harmless setting that may reduce some on-screen version messages; it will not attempt to change or bypass activation.")
    $btn.Tag = @{ ToolTip = $tt }

    $btn.Add_Click({
        try {
            try {
                Write-Host 'Checking activation status (slmgr /xpr)...'
                $output = & cscript.exe //nologo "$env:windir\system32\slmgr.vbs" /xpr 2>&1
                if ($output) { $output | ForEach-Object { Write-Host $_ } }

                # Best-effort: if not activated, offer a harmless desktop flag change
                if ($output -match 'is in an extended evaluation' -or $output -match 'Notification') {
                    Write-Host 'System appears not activated. Setting PaintDesktopVersion to 0 (harmless) as a best-effort.'
                    try {
                        Set-ItemProperty -Path 'HKCU:\Control Panel\Desktop' -Name 'PaintDesktopVersion' -Value 0 -ErrorAction Stop
                        # Ask explorer to refresh desktop settings
                        RUNDLL32.EXE user32.dll,UpdatePerUserSystemParameters 1, True
                        Write-Host 'Set PaintDesktopVersion=0; desktop refresh requested.'
                    } catch {
                        Write-Host "Failed to set PaintDesktopVersion: $($_.Exception.Message)"
                    }
                }
            } catch {
                Write-Host "Error checking activation: $($_.Exception.Message)"
            }
        } finally {
            if (Get-Command -Name Write-AsciiDivider -ErrorAction SilentlyContinue) { Write-AsciiDivider }
        }
    })

    $Parent.Controls.Add($btn)
    return $btn
}
