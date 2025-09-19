<#
Controls\ToggleDarkModeControl.ps1

Purpose:
  Adds a button that toggles Windows dark/light mode by flipping the relevant registry
  values for AppsUseLightTheme and SystemUsesLightTheme under HKCU\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize.

Notes:
  - Changing these registry values affects the current user. Some apps may require restart
    to pick up the change. No elevation is required to change HKCU values.
#>

<# Note: This file intentionally uses explicit null checks with $null on the left where
    appropriate to satisfy analyzers. We prefer `Get-ItemPropertyValue` to directly
    obtain the registry value and avoid inline property access which can confuse static
    analysis. #>

function Add-ToggleDarkModeButton {
    param(
        [Parameter(Mandatory=$true)][System.Windows.Forms.Control]$Parent,
        [Parameter(Mandatory=$false)][System.Drawing.Point]$Location = $(New-Object System.Drawing.Point(10,70)),
        [Parameter(Mandatory=$false)][System.Drawing.Size]$Size = $(New-Object System.Drawing.Size(160,40))
    )

    $btn = New-Object System.Windows.Forms.Button
    $btn.Text = 'Toggle Dark Mode'
    $btn.Size = $Size
    $btn.Location = $Location
    # Tooltip: plain-language explanation for non-technical users
    $toolTip = New-Object System.Windows.Forms.ToolTip
    $toolTip.AutoPopDelay = 20000
    $toolTip.InitialDelay = 500
    $toolTip.ReshowDelay = 100
    $toolTip.ShowAlways = $true
    $toolTip.SetToolTip($btn, "Switches between light and dark theme for Windows apps. Some applications may need to be restarted to see the change. This only affects the current user.")
    $btn.Tag = @{ ToolTip = $toolTip }

    $btn.Add_Click({
        try {
            $key = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'

            # Read current AppsUseLightTheme value. Use try/catch to handle missing values
            # and make the flow explicit so static analyzers do not misreport issues.
            $currentValue = $null
            try {
                $currentValue = Get-ItemPropertyValue -Path $key -Name 'AppsUseLightTheme' -ErrorAction Stop
            } catch {
                # Value missing or unreadable; we'll create defaults below.
                $currentValue = $null
            }

            if ($null -eq $currentValue) {
                Write-Host 'Theme keys not found; creating defaults.'
                New-ItemProperty -Path $key -Name 'AppsUseLightTheme' -Value 1 -PropertyType DWord -Force | Out-Null
                New-ItemProperty -Path $key -Name 'SystemUsesLightTheme' -Value 1 -PropertyType DWord -Force | Out-Null
                $current = 1
            } else {
                $current = [int]$currentValue
            }

            # Numeric toggle: if current is 0 -> 1, else -> 0
            $next = 1 - $current
            Set-ItemProperty -Path $key -Name 'AppsUseLightTheme' -Value $next -Force
            Set-ItemProperty -Path $key -Name 'SystemUsesLightTheme' -Value $next -Force
            Write-Host "Set AppsUseLightTheme/SystemUsesLightTheme to $next. Apps may need restart to apply."
        } catch {
            Write-Host "Error toggling dark mode: $($_.Exception.Message)"
        } finally {
            if (Get-Command -Name Write-AsciiDivider -ErrorAction SilentlyContinue) { Write-AsciiDivider }
        }
    })

    $Parent.Controls.Add($btn)
    return $btn
}
