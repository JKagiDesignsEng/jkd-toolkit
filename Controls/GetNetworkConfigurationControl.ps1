<#
Controls\GetNetworkConfigurationControl.ps1

Purpose:
  Adds a grouped pair: a "Show active only" checkbox and a "Get Network Configuration"
  button. The button runs `Get-NetIPConfiguration` and prints results to the console.

Usage:
  . "$PSScriptRoot\Controls\GetNetworkConfigurationControl.ps1"
  Add-GetNetworkConfigurationButton -Parent $grpNet -Location (New-Object System.Drawing.Point(10,105))

Notes:
  - The control prints output to the console (project preference). If you want UI
    results instead, we can add a multiline readonly TextBox and append results there.
  - `Get-NetIPConfiguration` requires the NetTCPIP module (present on modern Windows).
#>

function Add-GetNetworkConfigurationButton {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][System.Windows.Forms.Control]$Parent,
        [Parameter(Mandatory=$false)][System.Drawing.Point]$Location = $(New-Object System.Drawing.Point(10,105)),
        [Parameter(Mandatory=$false)][System.Drawing.Size]$Size = $(New-Object System.Drawing.Size(180,40))
    )

    # Checkbox: Show active only
    $chk = New-Object System.Windows.Forms.CheckBox
    $chk.Text = 'Show active only'
    $chk.AutoSize = $true
    $chk.Location = $Location
    $chk.Checked = $false

    # Button: Get Network Configuration
    $btn = New-Object System.Windows.Forms.Button
    $btn.Text = 'Get Network Configuration'
    $btn.Size = (New-Object System.Drawing.Size(($Size.Width),24))
    $btn.Location = [System.Drawing.Point]::new($Location.X, ($Location.Y + 25))

    $btn.Add_Click({
        try {
            Write-Host 'Retrieving network configuration...'
            if ($chk.Checked) {
                $cfg = Get-NetIPConfiguration | Where-Object { $_.IPv4Address -or $_.IPv6Address } | Where-Object { $_.InterfaceOperationalStatus -eq 'Up' }
            } else {
                $cfg = Get-NetIPConfiguration
            }
            if ($cfg) {
                $cfg | ForEach-Object {
                    Write-Host "Interface: $($_.InterfaceAlias)"
                    if ($_.IPv4Address) { $_.IPv4Address | ForEach-Object { Write-Host "  IPv4: $($_.IPAddress) / $($_.PrefixLength)" } }
                    if ($_.IPv6Address) { $_.IPv6Address | ForEach-Object { Write-Host "  IPv6: $($_.IPAddress) / $($_.PrefixLength)" } }
                    if ($_.IPv4DefaultGateway) { Write-Host "  Gateway: $($_.IPv4DefaultGateway.NextHop)" }
                    if ($_.DNSServer) { $_.DNSServer | ForEach-Object { Write-Host "  DNS: $($_)" } }
                    Write-Host '---------------------------'
                }
            } else { Write-Host 'No network configuration found.' }
        } catch {
            Write-Host "Error retrieving network configuration: $($_.Exception.Message)"
        }
    })

    # Tooltips for the checkbox and the button
    $tt = New-Object System.Windows.Forms.ToolTip
    $tt.AutoPopDelay = 25000
    $tt.InitialDelay = 400
    $tt.ReshowDelay = 100
    $tt.ShowAlways = $true
    $tt.SetToolTip($chk, 'When checked, only interfaces currently up/active are shown. Leave unchecked to list all interfaces.')
    $tt.SetToolTip($btn, 'Click to list IP addresses, gateways, and DNS servers for network interfaces. Results are printed to the console.')

    # Keep ToolTip alive by storing a reference on controls
    $chk.Tag = @{ ToolTip = $tt }
    $btn.Tag = @{ ToolTip = $tt }

    $Parent.Controls.Add($chk)
    $Parent.Controls.Add($btn)

    return @{ CheckBox = $chk; Button = $btn }
}
