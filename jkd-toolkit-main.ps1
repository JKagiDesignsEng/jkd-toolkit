<#
jkd-toolkit-main.ps1

Purpose:
    Minimal, modular PowerShell WinForms launcher for JKD Toolkit controls. The goal is to
    keep the main script small and to load UI controls from the `Controls\` directory by
    dot-sourcing individual scripts. This makes individual controls (buttons, panels)
    easier to maintain and test.

Elevation behavior:
    Some control actions (for example reading Wi-Fi profile keys) require administrative
    privileges. This script attempts to self-elevate early by re-launching PowerShell with
    the RunAs verb. The relaunch uses `-NoExit` so console output remains visible when
    elevated. If you prefer a non-console GUI-only run, remove `-NoExit`.

Console-only output policy:
    Per project preference, the Network Password control writes SSID/password results to
    the console (using `Write-Host`) rather than showing message boxes. If you run the
    script by double-clicking, ensure you keep `-NoExit` during elevation or run from an
    elevated console to see output.

Controls pattern:
    Place small control scripts under `Controls\`, each exposing a function that accepts
    a `[System.Windows.Forms.Form]` and adds UI elements to it. Example:
        . "$PSScriptRoot\Controls\NetworkPasswordControl.ps1"
        Add-NetworkPasswordButton -Form $form

Notes about PSScriptAnalyzer:
    Some analyzer warnings about approved verbs were produced during iterative edits; the
    elevation helper uses an approved verb (`Start-...`) to avoid most complaints. You can
    further adjust analyzer rules via in-file suppression comments if desired.
#>

[CmdletBinding()]
param()

# Suppress PSScriptAnalyzer rule for approved verb names here (false positive from prior edits)
# PSScriptAnalyzer disable=PSUseApprovedVerbs

# Ensure running as Administrator (UAC elevation)
function Start-Elevated {
    try {
        $wi = [Security.Principal.WindowsIdentity]::GetCurrent()
        $wp = New-Object Security.Principal.WindowsPrincipal($wi)
        if (-not $wp.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
            $scriptPath = $PSCommandPath
            $argList = @('-NoProfile','-ExecutionPolicy','Bypass','-NoExit','-STA','-File',"`"$scriptPath`"")
            Start-Process -FilePath 'powershell.exe' -ArgumentList ($argList -join ' ') -Verb RunAs | Out-Null
            exit
        }
    } catch {
        Write-Warning "Failed to self-elevate: $($_.Exception.Message)"
    }
}

Start-Elevated

# Load required assemblies
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
[void][System.Windows.Forms.Application]::EnableVisualStyles()
[System.Windows.Forms.Application]::SetCompatibleTextRenderingDefault($false)

# Wrapper for Write-Host that prints a divider after likely command-completion messages.
# This is a heuristic: it looks for keywords like 'complete','finished','started background job','triggered','failed','error'.
function Write-Divider {
    param(
        [string]$Color = 'DarkGray'
    )
    & Microsoft.PowerShell.Utility\Write-Host '----------------------------------------------------------------' -ForegroundColor $Color
}

# Create form
$form = New-Object System.Windows.Forms.Form
$form.Text = 'JKD Toolkit'
$form.Size = New-Object System.Drawing.Size(1040, 500)
$form.StartPosition = 'CenterScreen'
$iconPath = Join-Path -Path $PSScriptRoot -ChildPath 'Resources\jkd-icon.ico'
if (Test-Path -Path $iconPath) {
    try {
        $form.Icon = New-Object System.Drawing.Icon($iconPath)
    } catch {
        Write-Host "Warning: Failed to load icon $($_.Exception.Message)"
    }
} else {
    Write-Host "Info: Icon not found at $iconPath - continuing without a form icon."
}

# Create two group boxes: Tools and Maintenance
$tabLeft = New-Object System.Windows.Forms.TabControl
$tabLeft.Location = New-Object System.Drawing.Point(10,10)
$tabLeft.Size = New-Object System.Drawing.Size(980,420)
$tabLeft.Anchor = ([System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right -bor [System.Windows.Forms.AnchorStyles]::Bottom)

$tabTools = New-Object System.Windows.Forms.TabPage 'Tools'
$tabApps = New-Object System.Windows.Forms.TabPage 'Applications'
$tabLeft.Controls.Add($tabTools)
$tabLeft.Controls.Add($tabApps)
$form.Controls.Add($tabLeft)

# Create the Tools groupbox and put it inside the Tools tab so existing Add-* calls continue to work
$grpTools = New-Object System.Windows.Forms.GroupBox
$grpTools.Text = 'Quick Tools'
$grpTools.Size = New-Object System.Drawing.Size(200,360)
$grpTools.Location = New-Object System.Drawing.Point(10,10)
$grpTools.Anchor = ([System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left)
$tabTools.Controls.Add($grpTools)

# Use a FlowLayoutPanel inside Quick Tools so buttons automatically stack vertically
$flowTools = New-Object System.Windows.Forms.FlowLayoutPanel
$flowTools.FlowDirection = [System.Windows.Forms.FlowDirection]::TopDown
$flowTools.WrapContents = $false
$flowTools.AutoSize = $false
$flowTools.AutoScroll = $true
$flowTools.Dock = 'Fill'
$flowTools.Padding = [System.Windows.Forms.Padding]::new(6)
$grpTools.Controls.Add($flowTools)

$grpMaint = New-Object System.Windows.Forms.GroupBox
$grpMaint.Text = 'Maintenance'
$grpMaint.Size = New-Object System.Drawing.Size(360,280)
$grpMaint.Location = New-Object System.Drawing.Point(220,10)
$tabTools.Controls.Add($grpMaint)

# Create Networking group next to Maintenance
$grpNet = New-Object System.Windows.Forms.GroupBox
$grpNet.Text = 'Networking'
$grpNet.Size = New-Object System.Drawing.Size(360,360)
$grpNet.Location = New-Object System.Drawing.Point(590,10)
$tabTools.Controls.Add($grpNet)

# Flow layout panel for networking controls (keeps GroupBox but uses flow for children)
$flowNet = New-Object System.Windows.Forms.FlowLayoutPanel
$flowNet.FlowDirection = [System.Windows.Forms.FlowDirection]::TopDown
$flowNet.WrapContents = $false
$flowNet.AutoSize = $false
$flowNet.AutoScroll = $true
$flowNet.Dock = 'Fill'
$flowNet.Padding = [System.Windows.Forms.Padding]::new(6)
$grpNet.Controls.Add($flowNet)

# Global toggle for whether DISM should use /LimitAccess. The checkbox is placed inside the
# Maintenance group so related controls are grouped together. By default we allow online
# access so DISM can fetch replacement files when needed.
$global:LimitAccess = $false

# Add network-password control to the Tools group
. "$PSScriptRoot\Controls\NetworkPasswordControl.ps1"
Add-NetworkPasswordButton -Parent $flowNet -Location (New-Object System.Drawing.Point(10,20)) -Size (New-Object System.Drawing.Size(160,40)) | Out-Null

# Networking: Ping control (textbox + button)
$txtPing = New-Object System.Windows.Forms.TextBox
$txtPing.Text = 'google.com'
$txtPing.Size = New-Object System.Drawing.Size(240,24)
$txtPing.Margin = New-Object System.Windows.Forms.Padding(0,0,0,0)
$flowNet.Controls.Add($txtPing)

# Ensure the ping textbox has a stable name so other controls can reference it reliably
$txtPing.Name = 'txtPing'
# Expose the ping textbox globally for controls that need a stable reference
$global:txtPing = $txtPing

# Global networking options: Detailed information toggle and optional port
$global:Net_Detailed = $false
$global:Net_UsePort = $false
$global:Net_Port = ''

$chkDetailed = New-Object System.Windows.Forms.CheckBox
$chkDetailed.Text = 'Detailed output'
$chkDetailed.AutoSize = $true
$chkDetailed.Margin = New-Object System.Windows.Forms.Padding(0,6,0,0)
$chkDetailed.Checked = $global:Net_Detailed
$chkDetailed.Add_CheckedChanged({ $global:Net_Detailed = $chkDetailed.Checked; Write-Host "Net_Detailed set to $global:Net_Detailed" })
$flowNet.Controls.Add($chkDetailed)

$chkUsePort = New-Object System.Windows.Forms.CheckBox
$chkUsePort.Text = 'Use Port'
$chkUsePort.AutoSize = $true
$chkUsePort.Margin = New-Object System.Windows.Forms.Padding(0,6,0,0)
$chkUsePort.Checked = $global:Net_UsePort
$chkUsePort.Add_CheckedChanged({ $global:Net_UsePort = $chkUsePort.Checked; Write-Host "Net_UsePort set to $global:Net_UsePort" })
$flowNet.Controls.Add($chkUsePort)

$portRow = New-Object System.Windows.Forms.Panel
$portRow.Size = New-Object System.Drawing.Size(240,28)
$lblPort = New-Object System.Windows.Forms.Label
$lblPort.Text = 'Port:'
$lblPort.AutoSize = $true
$lblPort.Location = New-Object System.Drawing.Point(0,6)
$txtPort = New-Object System.Windows.Forms.TextBox
$txtPort.Text = ''
$txtPort.Size = New-Object System.Drawing.Size(60,20)
$txtPort.Location = New-Object System.Drawing.Point(40,2)
$portRow.Controls.Add($lblPort)
$portRow.Controls.Add($txtPort)
$flowNet.Controls.Add($portRow)

$btnPing = New-Object System.Windows.Forms.Button
$btnPing.Text = 'Ping'
$btnPing.Size = New-Object System.Drawing.Size(80,24)
$btnPing.Margin = New-Object System.Windows.Forms.Padding(0,6,0,0)
$btnPing.Add_Click({
    try {
        $target = $txtPing.Text
        if ([string]::IsNullOrWhiteSpace($target)) { Write-Host 'Please enter a hostname or IP in the target textbox.'; return }
        Write-Host "Pinging $target using Test-Connection..."
        $res = Test-Connection -ComputerName $target -Count 4 -ErrorAction Stop
        $res | ForEach-Object { Write-Host "Reply from $($_.Address): Status=$($_.StatusCode) Time=$($_.ResponseTime)ms" }
    # Divider after ping results
    Write-Divider
    } catch {
        Write-Host "Ping failed: $($_.Exception.Message)"
    }
})
$flowNet.Controls.Add($btnPing)

# Tooltip for Ping textbox and button
$netTT = New-Object System.Windows.Forms.ToolTip
$netTT.AutoPopDelay = 20000
$netTT.InitialDelay = 400
$netTT.ReshowDelay = 100
$netTT.ShowAlways = $true
$netTT.SetToolTip($txtPing, 'Enter a hostname or IP address here (for example: google.com or 8.8.8.8).')
$netTT.SetToolTip($btnPing, 'Click to check network reachability to the address entered on the left. Results are printed to the console.')
$txtPing.Tag = @{ ToolTip = $netTT }
$btnPing.Tag = @{ ToolTip = $netTT }

. "$PSScriptRoot\Controls\TraceRouteControl.ps1"
Add-TraceRouteButton -Parent $flowNet -TargetTextBox $txtPing -PortTextBox $txtPort -UsePortCheckBox $chkUsePort -DetailedCheckBox $chkDetailed -Location (New-Object System.Drawing.Point(10,235)) -Size (New-Object System.Drawing.Size(80,24)) | Out-Null

# Get Network Configuration button and active-only checkbox
. "$PSScriptRoot\Controls\GetNetworkConfigurationControl.ps1"
Add-GetNetworkConfigurationButton -Parent $flowNet -Location (New-Object System.Drawing.Point(10,200)) -Size (New-Object System.Drawing.Size(180,40)) | Out-Null

# Additional tools: Toggle Dark Mode, Activation check/hide, O&O ShutUp, Wallpaper
. "$PSScriptRoot\Controls\RunMicrosoftUpdateControl.ps1"
Add-RunMicrosoftUpdateButton -Parent $flowTools -Location (New-Object System.Drawing.Point(10,20)) -Size (New-Object System.Drawing.Size(160,40)) | Out-Null
. "$PSScriptRoot\Controls\ToggleDarkModeControl.ps1"
Add-ToggleDarkModeButton -Parent $flowTools -Location (New-Object System.Drawing.Point(10,70)) -Size (New-Object System.Drawing.Size(160,40)) | Out-Null
. "$PSScriptRoot\Controls\ActivationControl.ps1"
Add-ActivationButton -Parent $flowTools -Location (New-Object System.Drawing.Point(10,120)) -Size (New-Object System.Drawing.Size(160,40)) | Out-Null
. "$PSScriptRoot\Controls\OOSUControl.ps1"
Add-OOSUButton -Parent $flowTools -Location (New-Object System.Drawing.Point(10,170)) -Size (New-Object System.Drawing.Size(160,40)) | Out-Null
. "$PSScriptRoot\Controls\WallpaperControl.ps1"
Add-WallpaperButton -Parent $flowTools -Location (New-Object System.Drawing.Point(10,220)) -Size (New-Object System.Drawing.Size(160,40)) | Out-Null

# Add CheckHealth and RestoreHealth controls to the Maintenance group
. "$PSScriptRoot\Controls\CheckHealthControl.ps1"
. "$PSScriptRoot\Controls\RestoreHealthControl.ps1"
. "$PSScriptRoot\Controls\RestoreHealthFromISOControl.ps1"
. "$PSScriptRoot\Controls\CheckDiskControl.ps1"

# Create nested 'Image' group inside Maintenance for DISM/image related controls
$grpImage = New-Object System.Windows.Forms.GroupBox
$grpImage.Text = 'Image'
$grpImage.Size = New-Object System.Drawing.Size(340,180)
$grpImage.Location = New-Object System.Drawing.Point(10,20)
$grpMaint.Controls.Add($grpImage)

# Add DISM / image-related buttons into the Image group
Add-CheckHealthButton -Parent $grpImage -Location (New-Object System.Drawing.Point(10,20)) -Size (New-Object System.Drawing.Size(160,32)) | Out-Null
Add-RestoreHealthButton -Parent $grpImage -Location (New-Object System.Drawing.Point(180,20)) -Size (New-Object System.Drawing.Size(150,32)) | Out-Null
Add-RestoreHealthFromISOButton -Parent $grpImage -Location (New-Object System.Drawing.Point(10,60)) -Size (New-Object System.Drawing.Size(320,40)) | Out-Null

# Checkbox inside Image group: toggle /LimitAccess for DISM operations
$chkLimit = New-Object System.Windows.Forms.CheckBox
$chkLimit.Text = 'Use /LimitAccess for DISM'
$chkLimit.AutoSize = $true
$chkLimit.Location = New-Object System.Drawing.Point(10,135)
$chkLimit.Checked = $global:LimitAccess
$chkLimit.Add_CheckedChanged({ $global:LimitAccess = $chkLimit.Checked; Write-Host "LimitAccess set to $global:LimitAccess" })
$grpImage.Controls.Add($chkLimit)
    # Tooltip for LimitAccess checkbox (plain-language)
    $chkTT = New-Object System.Windows.Forms.ToolTip
    $chkTT.AutoPopDelay = 20000
    $chkTT.InitialDelay = 400
    $chkTT.ReshowDelay = 100
    $chkTT.ShowAlways = $true
    $chkTT.SetToolTip($chkLimit, "When checked, DISM will avoid contacting Windows Update or online sources while repairing files. We recommend leaving this unchecked so DISM can download replacement files from the internet if needed.")
    # Keep tooltip alive by storing reference on the checkbox
    $chkLimit.Tag = @{ ToolTip = $chkTT }

# Create nested 'Disk' group inside Maintenance for disk tools like chkdsk
$grpDisk = New-Object System.Windows.Forms.GroupBox
$grpDisk.Text = 'Disk'
$grpDisk.Size = New-Object System.Drawing.Size(340,60)
$grpDisk.Location = New-Object System.Drawing.Point(10,210)
$grpMaint.Controls.Add($grpDisk)

# Add Check Disk button into Disk group
Add-CheckDiskButton -Parent $grpDisk -Location (New-Object System.Drawing.Point(10,15)) -Size (New-Object System.Drawing.Size(160,32)) | Out-Null


# Applications tab: Get Installed Applications control
. { Remove-Item Function:\Add-GetInstalledApplicationsControl -ErrorAction SilentlyContinue }
. "$PSScriptRoot\Controls\GetInstalledApplicationsControl.ps1"
Add-GetInstalledApplicationsControl -Parent $tabApps -Location (New-Object System.Drawing.Point(10,10)) -Size (New-Object System.Drawing.Size(920,380)) | Out-Null

# Run the form
[System.Windows.Forms.Application]::Run($form)

