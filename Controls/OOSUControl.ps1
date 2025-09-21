<#
Controls\OOSUControl.ps1

Purpose:
  Adds a button to run O&O ShutUp2 (if present) or notify the user where to place the
  executable. This control does not bundle third-party software; it looks for
  Tools\OOSU2.exe relative to the script root.
#>

function Add-OOSUButton {
    param(
        [Parameter(Mandatory=$true)][System.Windows.Forms.Control]$Parent,
        [Parameter(Mandatory=$false)][System.Drawing.Point]$Location = $(New-Object System.Drawing.Point(10,170)),
        [Parameter(Mandatory=$false)][System.Drawing.Size]$Size = $(New-Object System.Drawing.Size(160,40))
    )

    $btn = New-Object System.Windows.Forms.Button
    $btn.Text = 'Run O&O ShutUp2'
    $btn.Size = $Size
    $btn.Location = $Location
    # Tooltip explaining purpose and install attempts
    $tt = New-Object System.Windows.Forms.ToolTip
    $tt.AutoPopDelay = 20000
    $tt.InitialDelay = 500
    $tt.ReshowDelay = 100
    $tt.ShowAlways = $true
    $tt.SetToolTip($btn, "Opens O&O ShutUp, a privacy settings tool. If the program is not present, this button will try to install it automatically using common package managers, or tell you where to download it. No changes are made without you opening the tool and choosing them.")
    $btn.Tag = @{ ToolTip = $tt }

    $btn.Add_Click({
        try {
            $exePath = Join-Path -Path $PSScriptRoot -ChildPath '..\Tools\OOSU2.exe'
            $exePath = [System.IO.Path]::GetFullPath($exePath)

            if (Test-Path -Path $exePath) {
                Write-Host "Launching O&O ShutUp2 from $exePath"
                Start-Process -FilePath $exePath -ArgumentList '/S' -NoNewWindow -WindowStyle Normal
                return
            }

            Write-Host "O&O ShutUp2 not found at $exePath. Attempting to install using available package manager..."

            # Try winget first
            $winget = Get-Command winget -ErrorAction SilentlyContinue
            if ($winget) {
                try {
                    Write-Host 'Attempting to install via winget (searching by name "O&O ShutUp!")...'
                    $args = 'install --name "O&O ShutUp!" --accept-package-agreements --accept-source-agreements'
                    $proc = Start-Process -FilePath 'winget' -ArgumentList $args -NoNewWindow -Wait -PassThru -ErrorAction Stop
                    Write-Host 'winget finished. Checking for executable...'
                } catch {
                    Write-Host "winget install failed: $($_.Exception.Message)"
                }
            } else {
                Write-Host 'winget not available on this system.'
            }

            # If still not present, try chocolatey
            if (-not (Test-Path -Path $exePath)) {
                $choco = Get-Command choco -ErrorAction SilentlyContinue
                if ($choco) {
                    try {
                        Write-Host 'Attempting to install via Chocolatey (package id: ooshutup)...'
                        Start-Process -FilePath 'choco' -ArgumentList 'install ooshutup -y' -NoNewWindow -Wait -PassThru -ErrorAction Stop
                        Write-Host 'choco finished. Checking for executable...'
                    } catch {
                        Write-Host "choco install failed: $($_.Exception.Message)"
                    }
                } else {
                    Write-Host 'Chocolatey not available on this system.'
                }
            }

            # Final check: if executable now exists, launch it
            if (Test-Path -Path $exePath) {
                Write-Host "Launching O&O ShutUp2 from $exePath"
                Start-Process -FilePath $exePath -ArgumentList '/S' -NoNewWindow -WindowStyle Normal
            } else {
                Write-Host "Automatic install failed or package not available.\nPlease download O&O ShutUp! manually from https://www.oo-software.com/en/oo-shutup10 and place OOSU2.exe into the Tools folder: $exePath"
            }
        } catch {
            Write-Host "Error launching or installing O&O ShutUp2: $($_.Exception.Message)"
        } finally {
            if (Get-Command -Name Write-AsciiDivider -ErrorAction SilentlyContinue) { Write-AsciiDivider }
        }
    })

    $Parent.Controls.Add($btn)
    return $btn
}
