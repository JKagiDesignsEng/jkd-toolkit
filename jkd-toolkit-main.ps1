<#
Win11 Tech Toolkit — Portable PowerShell GUI
Author: ChatGPT for Josh (JKagiDesigns / Cultivatronics)
Purpose: A single-file, USB‑friendly GUI to troubleshoot and set up Windows 11 clients.

Highlights
- Self‑elevates to admin
- Tabbed WinForms UI
- One‑click repairs: SFC, DISM, WU cache reset, Print Spooler, Winsock/IP reset
- Network tools: flush DNS, renew IP, quick connectivity test, ping
- Maintenance: clear temp, create restore point, clean up update leftovers
- Exports: system report, installed programs list, driver inventory
- Launchers for common consoles (Device Manager, Event Viewer, Services, Task Manager, Windows Update)
- All actions logged to \Logs next to this script (on the USB)

Usage
- Right‑click the .ps1 → “Run with PowerShell”
- Or from an elevated prompt: powershell -ExecutionPolicy Bypass -File .\Win11_TechToolkit.ps1

Note: Some actions require an internet connection and/or may prompt for reboot.
#>

#region ----- Initialization & Helpers -----
[CmdletBinding()]
param()

# Load helper functions and actions
. "$PSScriptRoot\Toolkit.Helpers.ps1"
. "$PSScriptRoot\Toolkit.Actions.ps1"

# Ensure we're running as admin - pass the main script path
Test-AdminAndElevate -MainScriptPath $MyInvocation.MyCommand.Path

#endregion

#region ----- UI (WinForms) -----
$form                 = New-Object System.Windows.Forms.Form
$form.Text            = 'JKagiDesigns LLC Win11 Tech Toolkit'
$form.Size            = New-Object System.Drawing.Size(900, 650)
$form.MinimumSize     = New-Object System.Drawing.Size(900, 650)
$form.StartPosition   = 'CenterScreen'
$form.TopMost         = $false

# Set form icon if it exists
$iconPath = "$PSScriptRoot\JKD-icon.ico"
if (Test-Path $iconPath) {
    try {
        $form.Icon = [System.Drawing.Icon]::ExtractAssociatedIcon($iconPath)
    } catch {
        # Silently continue if icon fails to load
    }
}

$tabs = New-Object System.Windows.Forms.TabControl
$tabs.Dock = 'Fill'
$form.Controls.Add($tabs)

# Create tooltip component for helpful button explanations
$tooltip = New-Object System.Windows.Forms.ToolTip
$tooltip.AutoPopDelay = 10000
$tooltip.InitialDelay = 500
$tooltip.ReshowDelay = 500
$tooltip.ShowAlways = $true

# Status bar
$status = New-Object System.Windows.Forms.StatusStrip
$statusLabel = New-Object System.Windows.Forms.ToolStripStatusLabel
$statusLabel.Text = 'Ready.'
$status.Items.Add($statusLabel) | Out-Null
$form.Controls.Add($status)

function Set-Status([string]$t){ $statusLabel.Text = $t }

# --- Overview Tab ---
$tabOverview = New-Object System.Windows.Forms.TabPage
$tabOverview.Text = 'Overview'
$tabs.TabPages.Add($tabOverview) | Out-Null

$btnRefresh = New-Object System.Windows.Forms.Button
$btnRefresh.Text = 'Refresh System Info'
$btnRefresh.Size = New-Object System.Drawing.Size(160,30)
$btnRefresh.Location = New-Object System.Drawing.Point(10,10)
$tooltip.SetToolTip($btnRefresh, 'Collects and displays basic information about your computer like CPU, RAM, and operating system')

$btnExportReport = New-Object System.Windows.Forms.Button
$btnExportReport.Text = 'Export System Report'
$btnExportReport.Size = New-Object System.Drawing.Size(160,30)
$btnExportReport.Location = New-Object System.Drawing.Point(180,10)
$tooltip.SetToolTip($btnExportReport, 'Saves your computer information to a file that you can share with tech support or keep for records')

$panelInfo = New-Object System.Windows.Forms.Panel
$panelInfo.Dock = [System.Windows.Forms.DockStyle]::Fill
$panelInfo.Padding = New-Object System.Windows.Forms.Padding(0)
$panelInfo.Margin = New-Object System.Windows.Forms.Padding(0)

# Inner padded panel enforces a consistent 10px inset while keeping outer panel docked/responsive
$panelInfoInner = New-Object System.Windows.Forms.Panel
$panelInfoInner.Dock = [System.Windows.Forms.DockStyle]::Fill
$panelInfoInner.Padding = New-Object System.Windows.Forms.Padding(10)
$panelInfoInner.Margin = New-Object System.Windows.Forms.Padding(0)

$gridInfo = New-Object System.Windows.Forms.DataGridView
$gridInfo.Dock = [System.Windows.Forms.DockStyle]::Fill
$gridInfo.ReadOnly = $true
$gridInfo.AutoSizeColumnsMode = 'Fill'
$gridInfo.RowHeadersVisible = $false
$gridInfo.AllowUserToAddRows = $false
$gridInfo.SelectionMode = 'FullRowSelect'
$gridInfo.MultiSelect = $false
$gridInfo.BackgroundColor = [System.Drawing.Color]::White
$gridInfo.BorderStyle = 'Fixed3D'
$gridInfo.ScrollBars = 'Both'
$gridInfo.AutoSizeRowsMode = 'None'
$gridInfo.ColumnHeadersHeightSizeMode = 'AutoSize'

$panelInfoInner.Controls.Add($gridInfo)
$panelInfo.Controls.Add($panelInfoInner)

# Overview top panel (buttons area) - dock to top so it never overlaps the grid
$panelInfoTop = New-Object System.Windows.Forms.Panel
$panelInfoTop.Dock = [System.Windows.Forms.DockStyle]::Top
$panelInfoTop.Height = 50
$panelInfoTop.Padding = New-Object System.Windows.Forms.Padding(6)
$panelInfoTop.Margin = New-Object System.Windows.Forms.Padding(0)

# Move the overview buttons into the top panel
$panelInfoTop.Controls.Add($btnRefresh)
$panelInfoTop.Controls.Add($btnExportReport)

# Add controls in order: top panel first, then fill panel so the grid sits below
$tblOverview = New-Object System.Windows.Forms.TableLayoutPanel
$tblOverview.Dock = [System.Windows.Forms.DockStyle]::Fill
$tblOverview.RowCount = 2
$tblOverview.ColumnCount = 1
$tblOverview.AutoSize = $false
$tblOverview.Margin = New-Object System.Windows.Forms.Padding(0)
$null = $tblOverview.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::AutoSize)))
$null = $tblOverview.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent,100)))
$tblOverview.Controls.Add($panelInfoTop,0,0)
$tblOverview.Controls.Add($panelInfo,0,1)
$tabOverview.Controls.Add($tblOverview)

$btnRefresh.Add_Click({
  Set-Status 'Collecting system info...'
  try {
    $obj = Get-SystemInfo
    
    # Clear existing data and setup columns
    $gridInfo.DataSource = $null
    $gridInfo.Columns.Clear()
    $gridInfo.Rows.Clear()
    
    # Add columns manually
    $colProperty = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
    $colProperty.Name = 'Property'
    $colProperty.HeaderText = 'Property'
    $colProperty.Width = 200
    $gridInfo.Columns.Add($colProperty) | Out-Null
    
    $colValue = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
    $colValue.Name = 'Value'
    $colValue.HeaderText = 'Value'
    $colValue.AutoSizeMode = 'Fill'
    $gridInfo.Columns.Add($colValue) | Out-Null
    
    # Add data rows manually
    $obj.PSObject.Properties | ForEach-Object {
      $row = $gridInfo.Rows.Add()
      $gridInfo.Rows[$row].Cells['Property'].Value = $_.Name
      $gridInfo.Rows[$row].Cells['Value'].Value = $_.Value
    }
    
    Set-Status "System info loaded - $($obj.PSObject.Properties.Count) properties displayed"
  } catch {
    Set-Status "Error: $($_.Exception.Message)"
    # Show error in grid
    $gridInfo.Columns.Clear()
    $gridInfo.Rows.Clear()
    $colError = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
    $colError.Name = 'Error'
    $colError.HeaderText = 'Error'
    $colError.AutoSizeMode = 'Fill'
    $gridInfo.Columns.Add($colError) | Out-Null
    $row = $gridInfo.Rows.Add()
    $gridInfo.Rows[$row].Cells['Error'].Value = $_.Exception.Message
  }
})
$btnExportReport.Add_Click({
  $p = Export-SystemReport
  Show-ToolkitToast "Saved: `n$p" 'Export Complete'
})

# --- Network Tab ---
$tabNet = New-Object System.Windows.Forms.TabPage
$tabNet.Text = 'Network'
$tabs.TabPages.Add($tabNet) | Out-Null

$btnFlush = New-Object System.Windows.Forms.Button; $btnFlush.Text='Flush DNS'; $btnFlush.Size=New-Object System.Drawing.Size(120,30); $btnFlush.Location=New-Object System.Drawing.Point(10,10)
$btnRenew = New-Object System.Windows.Forms.Button; $btnRenew.Text='Release/Renew IP'; $btnRenew.Size=New-Object System.Drawing.Size(120,30); $btnRenew.Location=New-Object System.Drawing.Point(140,10)
$btnNetR  = New-Object System.Windows.Forms.Button; $btnNetR.Text='Winsock/IP Reset'; $btnNetR.Size=New-Object System.Drawing.Size(140,30); $btnNetR.Location=New-Object System.Drawing.Point(270,10)
$btnTest  = New-Object System.Windows.Forms.Button; $btnTest.Text='Connectivity Test'; $btnTest.Size=New-Object System.Drawing.Size(140,30); $btnTest.Location=New-Object System.Drawing.Point(420,10)

$lblHost  = New-Object System.Windows.Forms.Label;  $lblHost.Text='Ping host:'; $lblHost.Location=New-Object System.Drawing.Point(10,52); $lblHost.Size=New-Object System.Drawing.Size(70,20)
$txtHost  = New-Object System.Windows.Forms.TextBox; $txtHost.Text='google.com'; $txtHost.Location=New-Object System.Drawing.Point(80,52); $txtHost.Size=New-Object System.Drawing.Size(200,20)
$btnPing  = New-Object System.Windows.Forms.Button; $btnPing.Text='Ping'; $btnPing.Size=New-Object System.Drawing.Size(80,30); $btnPing.Location=New-Object System.Drawing.Point(290,50)

# Add tooltips for network buttons
$tooltip.SetToolTip($btnFlush, 'Clears your computer DNS cache - helps fix website loading problems')
$tooltip.SetToolTip($btnRenew, 'Gets a fresh IP address from your router - fixes many connection issues')
$tooltip.SetToolTip($btnNetR, 'Resets your network settings to defaults - fixes stubborn connection problems')
$tooltip.SetToolTip($btnTest, 'Tests if your internet connection is working by checking several websites')
$tooltip.SetToolTip($btnPing, 'Tests connection speed and response time to a specific website or server')
$tooltip.SetToolTip($txtHost, 'Enter a website name (like google.com) or IP address to test connection to')

$panelNet = New-Object System.Windows.Forms.Panel
$panelNet.Dock = [System.Windows.Forms.DockStyle]::Fill
$panelNet.Padding = New-Object System.Windows.Forms.Padding(0)
$panelNet.Margin = New-Object System.Windows.Forms.Padding(0)

# Inner padded panel enforces a consistent 10px inset while keeping outer panel docked/responsive
$panelNetInner = New-Object System.Windows.Forms.Panel
$panelNetInner.Dock = [System.Windows.Forms.DockStyle]::Fill
$panelNetInner.Padding = New-Object System.Windows.Forms.Padding(10)
$panelNetInner.Margin = New-Object System.Windows.Forms.Padding(0)

$gridNet  = New-Object System.Windows.Forms.DataGridView
$gridNet.Dock = [System.Windows.Forms.DockStyle]::Fill
$gridNet.ReadOnly = $true
$gridNet.AutoSizeColumnsMode = 'Fill'
$gridNet.RowHeadersVisible = $false
$gridNet.AllowUserToAddRows = $false
$gridNet.SelectionMode = 'FullRowSelect'
$gridNet.MultiSelect = $false
$gridNet.BackgroundColor = [System.Drawing.Color]::White
$gridNet.BorderStyle = 'Fixed3D'
$gridNet.ScrollBars = 'Both'
$gridNet.AutoSizeRowsMode = 'None'
$gridNet.ColumnHeadersHeightSizeMode = 'AutoSize'

$panelNetInner.Controls.Add($gridNet)
$panelNet.Controls.Add($panelNetInner)

# Network top panel - dock to top so network buttons sit above the grid and never overlap
$panelNetTop = New-Object System.Windows.Forms.Panel
$panelNetTop.Dock = [System.Windows.Forms.DockStyle]::Top
$panelNetTop.Height = 80
$panelNetTop.Padding = New-Object System.Windows.Forms.Padding(6)
$panelNetTop.Margin = New-Object System.Windows.Forms.Padding(0)

# Move the network controls into the top panel
$panelNetTop.Controls.Add($btnFlush)
$panelNetTop.Controls.Add($btnRenew)
$panelNetTop.Controls.Add($btnNetR)
$panelNetTop.Controls.Add($btnTest)
$panelNetTop.Controls.Add($lblHost)
$panelNetTop.Controls.Add($txtHost)
$panelNetTop.Controls.Add($btnPing)

# Add in order: top panel then fill panel
$tblNet = New-Object System.Windows.Forms.TableLayoutPanel
$tblNet.Dock = [System.Windows.Forms.DockStyle]::Fill
$tblNet.RowCount = 2
$tblNet.ColumnCount = 1
$tblNet.AutoSize = $false
$tblNet.Margin = New-Object System.Windows.Forms.Padding(0)
$null = $tblNet.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::AutoSize)))
$null = $tblNet.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent,100)))
$tblNet.Controls.Add($panelNetTop,0,0)
$tblNet.Controls.Add($panelNet,0,1)
$tabNet.Controls.Add($tblNet)

$btnFlush.Add_Click({ Set-Status 'Flushing DNS...'; Clear-DnsCache | Out-Null; Set-Status 'Ready.'; Show-ToolkitToast 'DNS cache flushed.' })
$btnRenew.Add_Click({ Set-Status 'Renewing IP...'; Update-IpAddress | Out-Null; Set-Status 'Ready.'; Show-ToolkitToast 'IP renewed.' })
$btnNetR.Add_Click({ Set-Status 'Resetting network...'; Reset-NetworkStack; Set-Status 'Ready.' })
$btnTest.Add_Click({
  Set-Status 'Running connectivity test...'
  try {
    $r = Test-Connectivity
    
    # Clear existing data and setup columns
    $gridNet.DataSource = $null
    $gridNet.Columns.Clear()
    $gridNet.Rows.Clear()
    
    # Add columns
    $colTest = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
    $colTest.Name = 'Test'
    $colTest.HeaderText = 'Test'
    $colTest.Width = 200
    $gridNet.Columns.Add($colTest) | Out-Null
    
    $colResult = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
    $colResult.Name = 'Result'
    $colResult.HeaderText = 'Result'
    $colResult.AutoSizeMode = 'Fill'
    $gridNet.Columns.Add($colResult) | Out-Null
    
    # Add data rows
    $r.PSObject.Properties | ForEach-Object {
      $rowIndex = $gridNet.Rows.Add()
      $gridNet.Rows[$rowIndex].Cells['Test'].Value = $_.Name
      $gridNet.Rows[$rowIndex].Cells['Result'].Value = $_.Value
    }
    
    Set-Status 'Connectivity test complete'
  } catch {
    Set-Status "Connectivity test error: $($_.Exception.Message)"
    $gridNet.Columns.Clear()
    $gridNet.Rows.Clear()
    $col = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
    $col.Name = 'Error'
    $col.HeaderText = 'Error'
    $col.AutoSizeMode = 'Fill'
    $gridNet.Columns.Add($col) | Out-Null
    $rowIndex = $gridNet.Rows.Add()
    $gridNet.Rows[$rowIndex].Cells['Error'].Value = $_.Exception.Message
  }
})
$btnPing.Add_Click({
  $h = $txtHost.Text.Trim(); if (-not $h) { return }
  Set-Status "Pinging $h..."
  try {
    $rows = Test-HostPing -TargetHost $h
    
    # Clear existing data and setup columns
    $gridNet.DataSource = $null
    $gridNet.Columns.Clear()
    $gridNet.Rows.Clear()
    
    if ($rows -and $rows.Count -gt 0) {
      # Add columns based on first row properties
      $firstRow = $rows[0]
      $firstRow.PSObject.Properties | ForEach-Object {
        $col = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
        $col.Name = $_.Name
        $col.HeaderText = $_.Name
        if ($_.Name -eq 'Target') { $col.Width = 150 }
        elseif ($_.Name -eq 'Status') { $col.Width = 100 }
        elseif ($_.Name -eq 'ResponseTime') { $col.Width = 120 }
        else { $col.AutoSizeMode = 'Fill' }
        $gridNet.Columns.Add($col) | Out-Null
      }
      
      # Add data rows
      $rows | ForEach-Object {
        $rowIndex = $gridNet.Rows.Add()
        $currentRow = $gridNet.Rows[$rowIndex]
        $_.PSObject.Properties | ForEach-Object {
          $currentRow.Cells[$_.Name].Value = $_.Value
        }
      }
      Set-Status "Ping complete - $($rows.Count) results for $h"
    } else {
      # No results - show message
      $col = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
      $col.Name = 'Message'
      $col.HeaderText = 'Result'
      $col.AutoSizeMode = 'Fill'
      $gridNet.Columns.Add($col) | Out-Null
      $rowIndex = $gridNet.Rows.Add()
      $gridNet.Rows[$rowIndex].Cells['Message'].Value = "No ping response from $h"
      Set-Status "No ping response from $h"
    }
  } catch {
    Set-Status "Ping error: $($_.Exception.Message)"
    $gridNet.Columns.Clear()
    $gridNet.Rows.Clear()
    $col = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
    $col.Name = 'Error'
    $col.HeaderText = 'Error'
    $col.AutoSizeMode = 'Fill'
    $gridNet.Columns.Add($col) | Out-Null
    $rowIndex = $gridNet.Rows.Add()
    $gridNet.Rows[$rowIndex].Cells['Error'].Value = $_.Exception.Message
  }
})

# --- Repairs Tab ---
$tabRep = New-Object System.Windows.Forms.TabPage
$tabRep.Text = 'Repairs'
$tabs.TabPages.Add($tabRep) | Out-Null

$btnSFC   = New-Object System.Windows.Forms.Button; $btnSFC.Text='Run SFC'; $btnSFC.Size=New-Object System.Drawing.Size(150,40); $btnSFC.Location=New-Object System.Drawing.Point(10,10)
$btnDISM  = New-Object System.Windows.Forms.Button; $btnDISM.Text='Run DISM RestoreHealth'; $btnDISM.Size=New-Object System.Drawing.Size(200,40); $btnDISM.Location=New-Object System.Drawing.Point(170,10)
$btnWU    = New-Object System.Windows.Forms.Button; $btnWU.Text='Reset Windows Update Cache'; $btnWU.Size=New-Object System.Drawing.Size(230,40); $btnWU.Location=New-Object System.Drawing.Point(380,10)
$btnSpool = New-Object System.Windows.Forms.Button; $btnSpool.Text='Restart Print Spooler'; $btnSpool.Size=New-Object System.Drawing.Size(180,40); $btnSpool.Location=New-Object System.Drawing.Point(620,10)

$btnFW    = New-Object System.Windows.Forms.Button; $btnFW.Text='Reset Firewall'; $btnFW.Size=New-Object System.Drawing.Size(150,40); $btnFW.Location=New-Object System.Drawing.Point(10,60)

# Add tooltips for repair buttons
$tooltip.SetToolTip($btnSFC, 'Scans and repairs corrupted Windows system files - fixes many Windows problems')
$tooltip.SetToolTip($btnDISM, 'Repairs the Windows image and system health - fixes deeper system corruption')
$tooltip.SetToolTip($btnWU, 'Clears Windows Update cache - fixes stuck or failing updates')
$tooltip.SetToolTip($btnSpool, 'Restarts the print service - fixes printing problems')
$tooltip.SetToolTip($btnFW, 'Resets Windows Firewall to default settings - fixes firewall-related issues')

$tabRep.Controls.AddRange(@($btnSFC,$btnDISM,$btnWU,$btnSpool,$btnFW))

$btnSFC.Add_Click({ Set-Status 'Running SFC...'; Invoke-SFC | Out-Null; Set-Status 'Ready.'; Show-ToolkitToast 'SFC completed. Review log if issues persist.' })
$btnDISM.Add_Click({ Set-Status 'Running DISM...'; Invoke-DISM | Out-Null; Set-Status 'Ready.'; Show-ToolkitToast 'DISM completed. A reboot may be needed.' })
$btnWU.Add_Click({ Set-Status 'Resetting WU cache...'; Reset-WindowsUpdateCache | Out-Null; Set-Status 'Ready.'; Show-ToolkitToast 'Windows Update cache reset.' })
$btnSpool.Add_Click({ Set-Status 'Restarting Print Spooler...'; Restart-PrintSpooler | Out-Null; Set-Status 'Ready.'; Show-ToolkitToast 'Print Spooler restarted.' })
$btnFW.Add_Click({ Set-Status 'Resetting Firewall...'; Reset-WindowsFirewall | Out-Null; Set-Status 'Ready.'; Show-ToolkitToast 'Firewall reset to defaults.' })

# --- Maintenance Tab ---
$tabMaint = New-Object System.Windows.Forms.TabPage
$tabMaint.Text = 'Maintenance'
$tabs.TabPages.Add($tabMaint) | Out-Null

$btnTemp   = New-Object System.Windows.Forms.Button; $btnTemp.Text='Clear Temp Files'; $btnTemp.Size=New-Object System.Drawing.Size(160,40); $btnTemp.Location=New-Object System.Drawing.Point(10,10)
$btnRP     = New-Object System.Windows.Forms.Button; $btnRP.Text='Create Restore Point'; $btnRP.Size=New-Object System.Drawing.Size(180,40); $btnRP.Location=New-Object System.Drawing.Point(180,10)
$btnExpApps= New-Object System.Windows.Forms.Button; $btnExpApps.Text='Export Installed Programs'; $btnExpApps.Size=New-Object System.Drawing.Size(210,40); $btnExpApps.Location=New-Object System.Drawing.Point(370,10)
$btnDrv    = New-Object System.Windows.Forms.Button; $btnDrv.Text='Export Driver Inventory'; $btnDrv.Size=New-Object System.Drawing.Size(200,40); $btnDrv.Location=New-Object System.Drawing.Point(590,10)

# Privacy & Debloating section
$lblPrivacy = New-Object System.Windows.Forms.Label; $lblPrivacy.Text='Privacy & Debloating Tools:'; $lblPrivacy.Location=New-Object System.Drawing.Point(10,70); $lblPrivacy.Font=New-Object System.Drawing.Font("Arial",9,[System.Drawing.FontStyle]::Bold); $lblPrivacy.Size=New-Object System.Drawing.Size(180,20)
$btnShutUp = New-Object System.Windows.Forms.Button; $btnShutUp.Text='O&O ShutUp10++'; $btnShutUp.Size=New-Object System.Drawing.Size(160,40); $btnShutUp.Location=New-Object System.Drawing.Point(10,90)
$btnPrivacyFix = New-Object System.Windows.Forms.Button; $btnPrivacyFix.Text='Windows Privacy Fix'; $btnPrivacyFix.Size=New-Object System.Drawing.Size(180,40); $btnPrivacyFix.Location=New-Object System.Drawing.Point(180,90)
$btnDebloat = New-Object System.Windows.Forms.Button; $btnDebloat.Text='Windows Debloater'; $btnDebloat.Size=New-Object System.Drawing.Size(180,40); $btnDebloat.Location=New-Object System.Drawing.Point(370,90)

# Customization section
$lblCustomization = New-Object System.Windows.Forms.Label; $lblCustomization.Text='Windows Customization:'; $lblCustomization.Location=New-Object System.Drawing.Point(10,150); $lblCustomization.Font=New-Object System.Drawing.Font("Arial",9,[System.Drawing.FontStyle]::Bold); $lblCustomization.Size=New-Object System.Drawing.Size(180,20)
$btnDarkMode = New-Object System.Windows.Forms.Button; $btnDarkMode.Text='Toggle Dark Mode'; $btnDarkMode.Size=New-Object System.Drawing.Size(160,40); $btnDarkMode.Location=New-Object System.Drawing.Point(10,170)
$btnWSL = New-Object System.Windows.Forms.Button; $btnWSL.Text='Install WSL'; $btnWSL.Size=New-Object System.Drawing.Size(120,40); $btnWSL.Location=New-Object System.Drawing.Point(180,170)
$btnWallpaper = New-Object System.Windows.Forms.Button; $btnWallpaper.Text='Set Custom Wallpaper'; $btnWallpaper.Size=New-Object System.Drawing.Size(180,40); $btnWallpaper.Location=New-Object System.Drawing.Point(310,170)

$tabMaint.Controls.AddRange(@($btnTemp,$btnRP,$btnExpApps,$btnDrv,$lblPrivacy,$btnShutUp,$btnPrivacyFix,$btnDebloat,$lblCustomization,$btnDarkMode,$btnWSL,$btnWallpaper))

$tooltip.SetToolTip($btnTemp, 'Deletes temporary files to free up disk space and improve performance')
$btnTemp.Add_Click({ Set-Status 'Clearing temp files...'; Clear-TempFiles | Out-Null; Set-Status 'Ready.'; Show-ToolkitToast 'Temp files cleared.' })
$tooltip.SetToolTip($btnRP, 'Creates a backup snapshot of your system settings and files')
$btnRP.Add_Click({ Set-Status 'Creating restore point...'; Checkpoint-SystemRestore | Out-Null; Set-Status 'Ready.'; Show-ToolkitToast 'Restore point created.' })
$tooltip.SetToolTip($btnExpApps, 'Creates a list of all installed software and saves it to your desktop')
$tooltip.SetToolTip($btnExpApps, 'Creates a list of all installed software and saves it to your desktop')
$btnExpApps.Add_Click({ Set-Status 'Exporting programs...'; Export-InstalledPrograms | Out-Null; Set-Status 'Programs exported'; Show-ToolkitToast 'Installed programs list has been exported to desktop.' })
$tooltip.SetToolTip($btnDrv, 'Creates a list of all installed device drivers and saves it to your desktop')
$tooltip.SetToolTip($btnDrv, 'Creates a list of all installed device drivers and saves it to your desktop')
$btnDrv.Add_Click({ Set-Status 'Exporting drivers...'; Export-DriverInventory | Out-Null; Set-Status 'Drivers exported'; Show-ToolkitToast 'Driver inventory has been exported to desktop.' })

# Privacy tools tooltips and event handlers
$tooltip.SetToolTip($btnShutUp, 'Downloads and runs O&O ShutUp10++ - comprehensive Windows privacy tool')
$btnShutUp.Add_Click({ Set-Status 'Launching O&O ShutUp10++...'; Start-PrivacyTool 'ShutUp10'; Set-Status 'Ready.' })
$tooltip.SetToolTip($btnPrivacyFix, 'Applies common Windows privacy settings and disables telemetry')
$btnPrivacyFix.Add_Click({ Set-Status 'Applying privacy fixes...'; Start-PrivacyTool 'PrivacyFix'; Set-Status 'Privacy fixes applied'; Show-ToolkitToast 'Windows privacy settings have been applied.' })
$tooltip.SetToolTip($btnDebloat, 'Removes common Windows bloatware and unnecessary apps')
$btnDebloat.Add_Click({ Set-Status 'Debloating Windows...'; Start-PrivacyTool 'Debloat'; Set-Status 'Debloating complete'; Show-ToolkitToast 'Windows debloating completed successfully.' })

# Customization tools tooltips and event handlers
$tooltip.SetToolTip($btnDarkMode, 'Toggles between Windows Dark Mode and Light Mode themes')
$btnDarkMode.Add_Click({ Set-Status 'Toggling Dark Mode...'; Start-CustomizationTool 'DarkMode'; Set-Status 'Dark Mode toggled' })
$tooltip.SetToolTip($btnWSL, 'Installs Windows Subsystem for Linux (WSL) with Ubuntu')
$btnWSL.Add_Click({ Set-Status 'Installing WSL...'; Start-CustomizationTool 'WSL'; Set-Status 'WSL installation initiated' })
$tooltip.SetToolTip($btnWallpaper, 'Browse and set a custom desktop wallpaper image')
$btnWallpaper.Add_Click({ Set-Status 'Setting wallpaper...'; Start-CustomizationTool 'Wallpaper'; Set-Status 'Ready.' })

# --- Setup & Install Tab ---
$tabSetup = New-Object System.Windows.Forms.TabPage
$tabSetup.Text = "Setup & Install"
$tabs.TabPages.Add($tabSetup) | Out-Null

# Driver and Windows Setup section
$lblDrivers = New-Object System.Windows.Forms.Label; $lblDrivers.Text='System Setup:'; $lblDrivers.Location=New-Object System.Drawing.Point(10,10); $lblDrivers.Font=New-Object System.Drawing.Font("Arial",9,[System.Drawing.FontStyle]::Bold); $lblDrivers.Size=New-Object System.Drawing.Size(120,20)
$btnMissingDrivers = New-Object System.Windows.Forms.Button; $btnMissingDrivers.Text='Scan & Install Drivers'; $btnMissingDrivers.Size=New-Object System.Drawing.Size(180,30); $btnMissingDrivers.Location=New-Object System.Drawing.Point(10,30); $btnMissingDrivers.Anchor=[System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left
$btnFeatures = New-Object System.Windows.Forms.Button; $btnFeatures.Text='Install Win Features'; $btnFeatures.Size=New-Object System.Drawing.Size(160,30); $btnFeatures.Location=New-Object System.Drawing.Point(200,30); $btnFeatures.Anchor=[System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left
$btnOptimize = New-Object System.Windows.Forms.Button; $btnOptimize.Text='Optimize Performance'; $btnOptimize.Size=New-Object System.Drawing.Size(160,30); $btnOptimize.Location=New-Object System.Drawing.Point(370,30); $btnOptimize.Anchor=[System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left

# Package Manager section
$lblPkgMgr = New-Object System.Windows.Forms.Label; $lblPkgMgr.Text='Package Managers:'; $lblPkgMgr.Location=New-Object System.Drawing.Point(10,80); $lblPkgMgr.Font=New-Object System.Drawing.Font("Arial",9,[System.Drawing.FontStyle]::Bold); $lblPkgMgr.Size=New-Object System.Drawing.Size(150,20)
$btnWinGet = New-Object System.Windows.Forms.Button; $btnWinGet.Text='Install WinGet'; $btnWinGet.Size=New-Object System.Drawing.Size(110,30); $btnWinGet.Location=New-Object System.Drawing.Point(10,100); $btnWinGet.Anchor=[System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left
$btnWinGetUninstall = New-Object System.Windows.Forms.Button; $btnWinGetUninstall.Text='Uninstall WinGet'; $btnWinGetUninstall.Size=New-Object System.Drawing.Size(110,30); $btnWinGetUninstall.Location=New-Object System.Drawing.Point(10,100); $btnWinGetUninstall.Anchor=[System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left; $btnWinGetUninstall.Visible=$false
$btnChoco = New-Object System.Windows.Forms.Button; $btnChoco.Text='Install Chocolatey'; $btnChoco.Size=New-Object System.Drawing.Size(120,30); $btnChoco.Location=New-Object System.Drawing.Point(140,100); $btnChoco.Anchor=[System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left
$btnChocoUninstall = New-Object System.Windows.Forms.Button; $btnChocoUninstall.Text='Uninstall Chocolatey'; $btnChocoUninstall.Size=New-Object System.Drawing.Size(120,30); $btnChocoUninstall.Location=New-Object System.Drawing.Point(140,100); $btnChocoUninstall.Anchor=[System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left; $btnChocoUninstall.Visible=$false

# Package Search section
$lblSearch = New-Object System.Windows.Forms.Label; $lblSearch.Text='Search for Applications:'; $lblSearch.Location=New-Object System.Drawing.Point(10,150); $lblSearch.Font=New-Object System.Drawing.Font("Arial",9,[System.Drawing.FontStyle]::Bold); $lblSearch.Size=New-Object System.Drawing.Size(170,20)

# Search controls
$lblSearchBox = New-Object System.Windows.Forms.Label; $lblSearchBox.Text='Search:'; $lblSearchBox.Location=New-Object System.Drawing.Point(10,180); $lblSearchBox.Size=New-Object System.Drawing.Size(50,20)
$txtSearch = New-Object System.Windows.Forms.TextBox; $txtSearch.Location=New-Object System.Drawing.Point(70,178); $txtSearch.Size=New-Object System.Drawing.Size(200,22); $txtSearch.Anchor=[System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left
$btnSearch = New-Object System.Windows.Forms.Button; $btnSearch.Text='Search'; $btnSearch.Size=New-Object System.Drawing.Size(80,25); $btnSearch.Location=New-Object System.Drawing.Point(280,177); $btnSearch.Anchor=[System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left

# Package manager selection for search
$lblPkgSelect = New-Object System.Windows.Forms.Label; $lblPkgSelect.Text='Search in:'; $lblPkgSelect.Location=New-Object System.Drawing.Point(380,180); $lblPkgSelect.Size=New-Object System.Drawing.Size(70,20)
$radioPkgWinGet = New-Object System.Windows.Forms.RadioButton; $radioPkgWinGet.Text='WinGet'; $radioPkgWinGet.Location=New-Object System.Drawing.Point(460,178); $radioPkgWinGet.Size=New-Object System.Drawing.Size(80,20); $radioPkgWinGet.Checked=$true
$radioPkgChoco = New-Object System.Windows.Forms.RadioButton; $radioPkgChoco.Text='Chocolatey'; $radioPkgChoco.Location=New-Object System.Drawing.Point(550,178); $radioPkgChoco.Size=New-Object System.Drawing.Size(100,20)

# Install button for search results
$btnInstallSelected = New-Object System.Windows.Forms.Button; $btnInstallSelected.Text='Install Selected'; $btnInstallSelected.Size=New-Object System.Drawing.Size(140,30); $btnInstallSelected.Location=New-Object System.Drawing.Point(170,270); $btnInstallSelected.Anchor=[System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left; $btnInstallSelected.Enabled=$false; $btnInstallSelected.Visible=$false

# Application Management section (shared between search and uninstall)
$lblAppManagement = New-Object System.Windows.Forms.Label; $lblAppManagement.Text='Application Management:'; $lblAppManagement.Location=New-Object System.Drawing.Point(10,250); $lblAppManagement.Font=New-Object System.Drawing.Font("Arial",9,[System.Drawing.FontStyle]::Bold); $lblAppManagement.Size=New-Object System.Drawing.Size(180,20)
$btnShowSearch = New-Object System.Windows.Forms.Button; $btnShowSearch.Text='Show Search Results'; $btnShowSearch.Size=New-Object System.Drawing.Size(150,30); $btnShowSearch.Location=New-Object System.Drawing.Point(10,270); $btnShowSearch.Anchor=[System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left; $btnShowSearch.Visible=$false
$btnRefreshApps = New-Object System.Windows.Forms.Button; $btnRefreshApps.Text='Show Installed Apps'; $btnRefreshApps.Size=New-Object System.Drawing.Size(145,30); $btnRefreshApps.Location=New-Object System.Drawing.Point(10,270); $btnRefreshApps.Anchor=[System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left
$btnUninstallSelected = New-Object System.Windows.Forms.Button; $btnUninstallSelected.Text='Uninstall Selected'; $btnUninstallSelected.Size=New-Object System.Drawing.Size(140,30); $btnUninstallSelected.Location=New-Object System.Drawing.Point(170,270); $btnUninstallSelected.Anchor=[System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left; $btnUninstallSelected.Visible=$false
$btnClearSelection = New-Object System.Windows.Forms.Button; $btnClearSelection.Text='Clear Selection'; $btnClearSelection.Size=New-Object System.Drawing.Size(120,30); $btnClearSelection.Location=New-Object System.Drawing.Point(320,270); $btnClearSelection.Anchor=[System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left


$panelApps = New-Object System.Windows.Forms.Panel
$panelApps.Dock = [System.Windows.Forms.DockStyle]::Fill
$panelApps.Padding = New-Object System.Windows.Forms.Padding(0)
$panelApps.Margin = New-Object System.Windows.Forms.Padding(0)

# Inner padded panel enforces a consistent 10px inset while keeping outer panel docked/responsive
$panelAppsInner = New-Object System.Windows.Forms.Panel
$panelAppsInner.Dock = [System.Windows.Forms.DockStyle]::Fill
$panelAppsInner.Padding = New-Object System.Windows.Forms.Padding(10)
$panelAppsInner.Margin = New-Object System.Windows.Forms.Padding(0)

# Shared apps grid (used for both search results and installed apps)
$gridApps = New-Object System.Windows.Forms.DataGridView
$gridApps.Dock = [System.Windows.Forms.DockStyle]::Fill
$gridApps.ReadOnly = $true
$gridApps.AutoSizeColumnsMode = 'Fill'
$gridApps.RowHeadersVisible = $false
$gridApps.AllowUserToAddRows = $false
$gridApps.SelectionMode = 'FullRowSelect'
$gridApps.MultiSelect = $true
$gridApps.BackgroundColor = [System.Drawing.Color]::White
$gridApps.BorderStyle = 'Fixed3D'
$gridApps.ScrollBars = 'Both'
$gridApps.AutoSizeRowsMode = 'None'
$gridApps.ColumnHeadersHeightSizeMode = 'AutoSize'

$panelAppsInner.Controls.Add($gridApps)
$panelApps.Controls.Add($panelAppsInner)

# Variable to track current mode
$script:currentMode = 'installed'  # 'search' or 'installed'
$global:searchResults = @()
$global:InstalledApps = @()

# Top panel for Setup tab (restore original layout)
$panelSetupTop = New-Object System.Windows.Forms.Panel
$panelSetupTop.Dock = [System.Windows.Forms.DockStyle]::Top
$panelSetupTop.Height = 320
$panelSetupTop.Padding = New-Object System.Windows.Forms.Padding(6)
$panelSetupTop.Margin = New-Object System.Windows.Forms.Padding(0)

# Move setup controls into the top panel (keeps them above the apps grid)
$panelSetupTop.Controls.AddRange(@($lblDrivers,$btnMissingDrivers,$btnFeatures,$btnOptimize,$lblPkgMgr,$btnWinGet,$btnWinGetUninstall,$btnChoco,$btnChocoUninstall,$lblSearch,$lblSearchBox,$txtSearch,$btnSearch,$lblPkgSelect,$radioPkgWinGet,$radioPkgChoco,$btnInstallSelected,$lblAppManagement,$btnShowSearch,$btnRefreshApps,$btnUninstallSelected,$btnClearSelection))

# Add top panel first, then the fill panel so the apps grid does not overlap controls
$tblSetup = New-Object System.Windows.Forms.TableLayoutPanel
$tblSetup.Dock = [System.Windows.Forms.DockStyle]::Fill
$tblSetup.RowCount = 2
$tblSetup.ColumnCount = 1
$tblSetup.AutoSize = $false
$tblSetup.Margin = New-Object System.Windows.Forms.Padding(0)
$null = $tblSetup.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::AutoSize)))
$null = $tblSetup.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent,100)))
$tblSetup.Controls.Add($panelSetupTop,0,0)
$tblSetup.Controls.Add($panelApps,0,1)
$tabSetup.Controls.Add($tblSetup)

# Event handlers for Setup tab
$tooltip.SetToolTip($btnMissingDrivers, 'Scans for missing/outdated drivers and provides installation options via Windows Update or Device Manager')
$btnMissingDrivers.Add_Click({ Set-Status 'Scanning for missing drivers...'; Find-MissingDrivers; Set-Status 'Driver scan complete' })
$tooltip.SetToolTip($btnFeatures, 'Installs useful Windows components like .NET Framework and Media Features')
$btnFeatures.Add_Click({ Set-Status 'Installing Windows features...'; Install-WindowsFeatures | Out-Null; Set-Status 'Features installation complete'; Show-ToolkitToast 'Windows features installation complete. Restart may be required.' })
$tooltip.SetToolTip($btnOptimize, 'Applies Windows settings tweaks to improve system speed and responsiveness')
$btnOptimize.Add_Click({ Set-Status 'Optimizing performance...'; Optimize-WindowsPerformance | Out-Null; Set-Status 'Performance optimization complete'; Show-ToolkitToast 'Windows performance optimization complete.' })

# Function to update package manager button states
# Helper functions for mode switching
function Switch-ToSearchMode {
  $script:currentMode = 'search'
  $btnShowSearch.Visible = $false
  $btnRefreshApps.Visible = $true
  $btnRefreshApps.Text = 'Show Installed Apps'
  $btnInstallSelected.Visible = $true
  $btnUninstallSelected.Visible = $false
  $gridApps.MultiSelect = $true
  $lblAppManagement.Text = 'Search Results:'
}

function Switch-ToInstalledMode {
  $script:currentMode = 'installed'
  $btnShowSearch.Visible = $true
  $btnRefreshApps.Visible = $true
  $btnRefreshApps.Text = 'Refresh Installed Apps'
  $btnInstallSelected.Visible = $false
  $btnUninstallSelected.Visible = $true
  $gridApps.MultiSelect = $true
  $lblAppManagement.Text = 'Installed Applications:'
}

function Update-PackageManagerButtons {
  $wingetInstalled = Test-PackageManager 'winget'
  $chocoInstalled = Test-PackageManager 'choco'
  
  # WinGet buttons
  if ($wingetInstalled) {
    $btnWinGet.Visible = $false
    $btnWinGetUninstall.Visible = $true
    $radioPkgWinGet.Enabled = $true
  } else {
    $btnWinGet.Visible = $true
    $btnWinGetUninstall.Visible = $false
    $radioPkgWinGet.Enabled = $false
    if ($radioPkgWinGet.Checked -and $chocoInstalled) { $radioPkgChoco.Checked = $true }
  }
  
  # Chocolatey buttons
  if ($chocoInstalled) {
    $btnChoco.Visible = $false
    $btnChocoUninstall.Visible = $true
    $radioPkgChoco.Enabled = $true
  } else {
    $btnChoco.Visible = $true
    $btnChocoUninstall.Visible = $false
    $radioPkgChoco.Enabled = $false
    if ($radioPkgChoco.Checked -and $wingetInstalled) { $radioPkgWinGet.Checked = $true }
  }
  
  # Update search and install availability
  $hasAnyPackageManager = ($wingetInstalled -or $chocoInstalled)
  $btnSearch.Enabled = $hasAnyPackageManager
  $btnInstallSelected.Enabled = ($hasAnyPackageManager -and $script:currentMode -eq 'search')
  
  # If no package managers available, clear search results
  if (-not $hasAnyPackageManager) {
    if ($script:currentMode -eq 'search') {
      $gridApps.Columns.Clear()
      $gridApps.Rows.Clear()
    }
  }
}

$tooltip.SetToolTip($btnWinGet, 'Installs Microsoft WinGet - a modern package manager for installing software')
$btnWinGet.Add_Click({ 
  Set-Status 'Installing WinGet...'
  Install-PackageManager 'winget' | Out-Null
  Set-Status 'WinGet installation complete'
  Show-ToolkitToast 'WinGet package manager ready.'
  Update-PackageManagerButtons
})

$tooltip.SetToolTip($btnWinGetUninstall, 'Removes Microsoft WinGet package manager from your system')
$btnWinGetUninstall.Add_Click({
  $confirmation = [System.Windows.Forms.MessageBox]::Show(
    'Are you sure you want to uninstall WinGet package manager?',
    'Confirm Uninstall',
    [System.Windows.Forms.MessageBoxButtons]::YesNo,
    [System.Windows.Forms.MessageBoxIcon]::Warning
  )
  if ($confirmation -eq [System.Windows.Forms.DialogResult]::Yes) {
    Set-Status 'Uninstalling WinGet...'
    Uninstall-PackageManager 'winget' | Out-Null
    Set-Status 'WinGet uninstalled'
    Show-ToolkitToast 'WinGet package manager has been removed.'
    Update-PackageManagerButtons
  }
})

$tooltip.SetToolTip($btnChoco, 'Installs Chocolatey - a popular package manager for Windows software installation')
$btnChoco.Add_Click({ 
  Set-Status 'Installing Chocolatey...'
  Install-PackageManager 'choco' | Out-Null
  Set-Status 'Chocolatey installation complete'
  Show-ToolkitToast 'Chocolatey package manager installed.'
  Update-PackageManagerButtons
})

$tooltip.SetToolTip($btnChocoUninstall, 'Removes Chocolatey package manager from your system')
$btnChocoUninstall.Add_Click({
  $confirmation = [System.Windows.Forms.MessageBox]::Show(
    'Are you sure you want to uninstall Chocolatey package manager?',
    'Confirm Uninstall',
    [System.Windows.Forms.MessageBoxButtons]::YesNo,
    [System.Windows.Forms.MessageBoxIcon]::Warning
  )
  if ($confirmation -eq [System.Windows.Forms.DialogResult]::Yes) {
    Set-Status 'Uninstalling Chocolatey...'
    Uninstall-PackageManager 'choco' | Out-Null
    Set-Status 'Chocolatey uninstalled'
    Show-ToolkitToast 'Chocolatey package manager has been removed.'
    Update-PackageManagerButtons
  }
})

# Add tooltips for search controls
$tooltip.SetToolTip($txtSearch, 'Enter the name of the software you want to find (e.g., "firefox", "steam", "vscode")')
$tooltip.SetToolTip($btnSearch, 'Search for packages in the selected package manager repository')
$tooltip.SetToolTip($radioPkgWinGet, 'Search Microsoft WinGet repository (built into Windows 11)')
$tooltip.SetToolTip($radioPkgChoco, 'Search Chocolatey repository (community packages)')
$tooltip.SetToolTip($gridApps, 'Select packages/applications from the list, then use Install Selected or Uninstall Selected buttons')

# Search event handlers
$btnSearch.Add_Click({
  $searchTerm = $txtSearch.Text.Trim()
  if ([string]::IsNullOrEmpty($searchTerm)) {
    Show-ToolkitToast 'Please enter a search term' 'Search Required'
    return
  }
  
  $packageManager = if ($radioPkgWinGet.Checked) { 'winget' } else { 'choco' }
  
  # Check if selected package manager is available
  if (-not (Test-PackageManager $packageManager)) {
    Show-ToolkitToast "$packageManager is not installed. Please install it first." 'Package Manager Not Found'
    return
  }
  
  Set-Status "Searching $packageManager for '$searchTerm'..."
  try {
    $searchResults = Search-PackageManager -SearchTerm $searchTerm -PackageManager $packageManager
    $global:searchResults = $searchResults
    
    # Switch to search mode
    Switch-ToSearchMode
    
    # Clear existing data and setup columns
    $gridApps.DataSource = $null
    $gridApps.Columns.Clear()
    $gridApps.Rows.Clear()
    
    if ($searchResults -and $searchResults.Count -gt 0) {
      # Add columns based on first result properties
      $firstResult = $searchResults[0]
      $firstResult.PSObject.Properties | ForEach-Object {
        $col = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
        $col.Name = $_.Name
        $col.HeaderText = $_.Name
        
        # Set column widths based on content type
        switch ($_.Name) {
          'Id' { $col.Width = 150 }
          'Name' { $col.Width = 200 }
          'Version' { $col.Width = 100 }
          'Source' { $col.Width = 100 }
          default { $col.AutoSizeMode = 'Fill' }
        }
        $gridApps.Columns.Add($col) | Out-Null
      }
      
      # Add data rows
      $searchResults | ForEach-Object {
        $rowIndex = $gridApps.Rows.Add()
        $currentRow = $gridApps.Rows[$rowIndex]
        $_.PSObject.Properties | ForEach-Object {
          $currentRow.Cells[$_.Name].Value = $_.Value
        }
      }
      
      $btnInstallSelected.Enabled = $true
      Set-Status "Found $($searchResults.Count) packages for '$searchTerm'"
    } else {
      # No results found
      $col = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
      $col.Name = 'Message'
      $col.HeaderText = 'Search Results'
      $col.AutoSizeMode = 'Fill'
      $gridApps.Columns.Add($col) | Out-Null
      $rowIndex = $gridApps.Rows.Add()
      $gridApps.Rows[$rowIndex].Cells['Message'].Value = "No packages found for '$searchTerm' in $packageManager"
      
      $btnInstallSelected.Enabled = $false
      Set-Status "No packages found for '$searchTerm'"
    }
  } catch {
    Set-Status "Search error: $($_.Exception.Message)"
    $gridApps.Columns.Clear()
    $gridApps.Rows.Clear()
    $col = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
    $col.Name = 'Error'
    $col.HeaderText = 'Error'
    $col.AutoSizeMode = 'Fill'
    $gridApps.Columns.Add($col) | Out-Null
    $rowIndex = $gridApps.Rows.Add()
    $gridApps.Rows[$rowIndex].Cells['Error'].Value = $_.Exception.Message
    $btnInstallSelected.Enabled = $false
  }
})

# Allow Enter key to trigger search
$txtSearch.Add_KeyDown({
  if ($_.KeyCode -eq [System.Windows.Forms.Keys]::Enter) {
    $btnSearch.PerformClick()
  }
})
$tooltip.SetToolTip($btnInstallSelected, 'Installs the selected packages from search results using the chosen package manager')
$btnInstallSelected.Add_Click({
  if ($script:currentMode -ne 'search') {
    Show-ToolkitToast 'Please perform a search first to see available packages.' 'No Search Results'
    return
  }
  
  $selectedRows = $gridApps.SelectedRows
  if ($selectedRows.Count -eq 0) {
    Show-ToolkitToast 'Please select at least one package from the search results.' 'No Selection'
    return
  }
  
  $packageManager = if ($radioPkgWinGet.Checked) { 'winget' } else { 'choco' }
  $selectedPackages = @()
  
  foreach ($row in $selectedRows) {
    $packageId = $row.Cells['Id'].Value
    $packageName = $row.Cells['Name'].Value
    if ($packageId) {
      $selectedPackages += [PSCustomObject]@{
        Id = $packageId
        Name = $packageName
      }
    }
  }
  
  if ($selectedPackages.Count -eq 0) {
    Show-ToolkitToast 'No valid packages selected.' 'Invalid Selection'
    return
  }
  
  Set-Status "Installing $($selectedPackages.Count) packages via $packageManager..."
  
  foreach ($package in $selectedPackages) {
    Install-Application -AppName $package.Id -PackageManager $packageManager -DisplayName $package.Name
  }
  
  Set-Status 'Package installation complete'
  Show-ToolkitToast "Installation of $($selectedPackages.Count) packages completed via $packageManager." 'Installation Complete'
})

# Mode switching event handlers
$btnShowSearch.Add_Click({
  if ($global:searchResults -and $global:searchResults.Count -gt 0) {
    Switch-ToSearchMode
    
    # Redisplay search results
    $gridApps.DataSource = $null
    $gridApps.Columns.Clear()
    $gridApps.Rows.Clear()
    
    $firstResult = $global:searchResults[0]
    $firstResult.PSObject.Properties | ForEach-Object {
      $col = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
      $col.Name = $_.Name
      $col.HeaderText = $_.Name
      
      switch ($_.Name) {
        'Id' { $col.Width = 150 }
        'Name' { $col.Width = 200 }
        'Version' { $col.Width = 100 }
        'Source' { $col.Width = 100 }
        default { $col.AutoSizeMode = 'Fill' }
      }
      $gridApps.Columns.Add($col) | Out-Null
    }
    
    $global:searchResults | ForEach-Object {
      $rowIndex = $gridApps.Rows.Add()
      $currentRow = $gridApps.Rows[$rowIndex]
      $_.PSObject.Properties | ForEach-Object {
        $currentRow.Cells[$_.Name].Value = $_.Value
      }
    }
    
    Set-Status "Showing $($global:searchResults.Count) search results"
  } else {
    Show-ToolkitToast 'No search results available. Please perform a search first.' 'No Search Results'
  }
})

# Uninstall event handlers
$tooltip.SetToolTip($btnRefreshApps, 'Scans your computer for all installed programs that can be uninstalled')
$btnRefreshApps.Add_Click({
  if ($script:currentMode -eq 'search') {
    # Switch to installed mode
    Switch-ToInstalledMode
  }
  
  Set-Status 'Loading installed applications...'
  try {
    $global:InstalledApps = Get-InstalledApplications
    
    # Clear and setup grid for installed apps
    $gridApps.DataSource = $null
    $gridApps.Columns.Clear()
    $gridApps.Rows.Clear()
    
    if ($global:InstalledApps -and $global:InstalledApps.Count -gt 0) {
      # Add columns for installed apps
      $colName = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
      $colName.Name = 'Name'
      $colName.HeaderText = 'Application Name'
      $colName.Width = 300
      $gridApps.Columns.Add($colName) | Out-Null
      
      $colVersion = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
      $colVersion.Name = 'Version'
      $colVersion.HeaderText = 'Version'
      $colVersion.Width = 120
      $gridApps.Columns.Add($colVersion) | Out-Null
      
      $colSource = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
      $colSource.Name = 'Source'
      $colSource.HeaderText = 'Source'
      $colSource.Width = 100
      $gridApps.Columns.Add($colSource) | Out-Null
      
      $colPublisher = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
      $colPublisher.Name = 'Publisher'
      $colPublisher.HeaderText = 'Publisher'
      $colPublisher.AutoSizeMode = 'Fill'
      $gridApps.Columns.Add($colPublisher) | Out-Null
      
      # Add data rows
      foreach ($app in $global:InstalledApps) {
        $rowIndex = $gridApps.Rows.Add()
        $gridApps.Rows[$rowIndex].Cells['Name'].Value = $app.Name
        $gridApps.Rows[$rowIndex].Cells['Version'].Value = $app.Version
        $gridApps.Rows[$rowIndex].Cells['Source'].Value = $app.Source
        $gridApps.Rows[$rowIndex].Cells['Publisher'].Value = $app.Publisher
      }
    }
    
    Set-Status "Found $($global:InstalledApps.Count) installed applications"
    Show-ToolkitToast "Found $($global:InstalledApps.Count) installed applications" 'Scan Complete'
  } catch {
    Set-Status "Error loading applications: $($_.Exception.Message)"
    Show-ToolkitToast "Error loading applications: $($_.Exception.Message)" 'Error'
  }
})

$tooltip.SetToolTip($btnUninstallSelected, 'Removes the selected programs from your computer (use with caution)')
$btnUninstallSelected.Add_Click({
  if ($script:currentMode -ne 'installed') {
    Show-ToolkitToast 'Please refresh installed applications first.' 'No Installed Apps'
    return
  }
  
  $selectedRows = $gridApps.SelectedRows
  if ($selectedRows.Count -eq 0) {
    Show-ToolkitToast 'Please select at least one application to uninstall.' 'No Selection'
    return
  }
  
  # Get selected applications
  $selectedItems = @()
  foreach ($row in $selectedRows) {
    $appName = $row.Cells['Name'].Value
    $selectedApp = $global:InstalledApps | Where-Object { $_.Name -eq $appName } | Select-Object -First 1
    if ($selectedApp) {
      $selectedItems += $selectedApp
    }
  }
  
  if ($selectedItems.Count -eq 0) {
    Show-ToolkitToast 'No valid applications selected.' 'Invalid Selection'
    return
  }
  
  # Confirmation dialog
  $appNames = ($selectedItems | ForEach-Object { $_.Name }) -join "`n"
  $confirmation = [System.Windows.Forms.MessageBox]::Show(
    "Are you sure you want to uninstall the following $($selectedItems.Count) application(s)?`n`n$appNames`n`nThis action cannot be undone.",
    'Confirm Uninstall',
    [System.Windows.Forms.MessageBoxButtons]::YesNo,
    [System.Windows.Forms.MessageBoxIcon]::Warning
  )
  
  if ($confirmation -eq [System.Windows.Forms.DialogResult]::Yes) {
    Set-Status "Uninstalling $($selectedItems.Count) applications..."
    
    try {
      $result = Uninstall-SelectedApplications -Applications $selectedItems -Silent
      
      Set-Status 'Uninstall process complete'
      Show-ToolkitToast "Uninstall complete!`nSuccess: $($result.Success)`nFailed: $($result.Failed)`nTotal: $($result.Total)" 'Uninstall Complete'
      
      # Refresh the list after uninstall
      $btnRefreshApps.PerformClick()
    } catch {
      Set-Status "Error during uninstall: $($_.Exception.Message)"
      Show-ToolkitToast "Error during uninstall: $($_.Exception.Message)" 'Error'
    }
  }
})

$tooltip.SetToolTip($btnClearSelection, 'Clears all selected items in the list - useful to start fresh selection')
$btnClearSelection.Add_Click({
  $gridApps.ClearSelection()
  Set-Status 'Selection cleared'
})

$tooltip.SetToolTip($gridApps, 'Select packages/applications from the list, then use Install Selected or Uninstall Selected buttons')

# --- Tools Tab ---
$tabTools = New-Object System.Windows.Forms.TabPage
$tabTools.Text = "Tools & Shortcuts"
$tabs.TabPages.Add($tabTools) | Out-Null

$btnDev = New-Object System.Windows.Forms.Button; $btnDev.Text='Device Manager'; $btnDev.Size=New-Object System.Drawing.Size(160,40); $btnDev.Location=New-Object System.Drawing.Point(10,10)
$btnEvt = New-Object System.Windows.Forms.Button; $btnEvt.Text='Event Viewer';   $btnEvt.Size=New-Object System.Drawing.Size(160,40); $btnEvt.Location=New-Object System.Drawing.Point(180,10)
$btnSrv = New-Object System.Windows.Forms.Button; $btnSrv.Text='Services';        $btnSrv.Size=New-Object System.Drawing.Size(160,40); $btnSrv.Location=New-Object System.Drawing.Point(350,10)
$btnTsk = New-Object System.Windows.Forms.Button; $btnTsk.Text='Task Manager';    $btnTsk.Size=New-Object System.Drawing.Size(160,40); $btnTsk.Location=New-Object System.Drawing.Point(520,10)
$btnWU2 = New-Object System.Windows.Forms.Button; $btnWU2.Text='Windows Update';  $btnWU2.Size=New-Object System.Drawing.Size(160,40); $btnWU2.Location=New-Object System.Drawing.Point(690,10)

$btnStart = New-Object System.Windows.Forms.Button; $btnStart.Text='Startup Apps'; $btnStart.Size=New-Object System.Drawing.Size(160,40); $btnStart.Location=New-Object System.Drawing.Point(10,60)

$tabTools.Controls.AddRange(@($btnDev,$btnEvt,$btnSrv,$btnTsk,$btnWU2,$btnStart))

$tooltip.SetToolTip($btnDev, 'Opens Device Manager to view and manage hardware devices and drivers')
$btnDev.Add_Click({ Start-SystemTool 'DeviceManager' })
$tooltip.SetToolTip($btnEvt, 'Opens Event Viewer to check system logs and troubleshoot issues')
$btnEvt.Add_Click({ Start-SystemTool 'EventViewer' })
$tooltip.SetToolTip($btnSrv, 'Opens Services manager to view and control Windows background services')
$btnSrv.Add_Click({ Start-SystemTool 'Services' })
$tooltip.SetToolTip($btnTsk, 'Opens Task Manager to monitor running programs and system performance')
$btnTsk.Add_Click({ Start-SystemTool 'TaskManager' })
$tooltip.SetToolTip($btnWU2, 'Opens Windows Update settings to check for and install system updates')
$btnWU2.Add_Click({ Start-SystemTool 'WindowsUpdate' })
$tooltip.SetToolTip($btnStart, 'Opens Startup Apps settings to manage which programs start with Windows')
$btnStart.Add_Click({ Start-SystemTool 'StartupApps' })

#endregion

# Preload Overview
$btnRefresh.PerformClick()

# Update package manager button states
Update-PackageManagerButtons

# Initialize in installed apps mode with error handling
try {
  Switch-ToInstalledMode
  
  # Add a small delay to ensure all functions are loaded
  Start-Sleep -Milliseconds 100
  
  Set-Status 'Loading installed applications...'
  $global:InstalledApps = Get-InstalledApplications
  
  if ($global:InstalledApps -and $global:InstalledApps.Count -gt 0) {
    # Clear and setup grid for installed apps
    $gridApps.DataSource = $null
    $gridApps.Columns.Clear()
    $gridApps.Rows.Clear()
    
    # Add columns for installed apps
    $colName = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
    $colName.Name = 'Name'
    $colName.HeaderText = 'Application Name'
    $colName.Width = 300
    $gridApps.Columns.Add($colName) | Out-Null
    
    $colVersion = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
    $colVersion.Name = 'Version'
    $colVersion.HeaderText = 'Version'
    $colVersion.Width = 120
    $gridApps.Columns.Add($colVersion) | Out-Null
    
    $colSource = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
    $colSource.Name = 'Source'
    $colSource.HeaderText = 'Source'
    $colSource.Width = 100
    $gridApps.Columns.Add($colSource) | Out-Null
    
    $colPublisher = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
    $colPublisher.Name = 'Publisher'
    $colPublisher.HeaderText = 'Publisher'
    $colPublisher.AutoSizeMode = 'Fill'
    $gridApps.Columns.Add($colPublisher) | Out-Null
    
    # Add data rows
    foreach ($app in $global:InstalledApps) {
      $rowIndex = $gridApps.Rows.Add()
      $gridApps.Rows[$rowIndex].Cells['Name'].Value = $app.Name
      $gridApps.Rows[$rowIndex].Cells['Version'].Value = $app.Version
      $gridApps.Rows[$rowIndex].Cells['Source'].Value = $app.Source
      $gridApps.Rows[$rowIndex].Cells['Publisher'].Value = if ($app.PSObject.Properties['Publisher']) { $app.Publisher } else { 'Unknown' }
    }
    
    Set-Status "Found $($global:InstalledApps.Count) installed applications"
  } else {
    # Show message if no apps found
    $gridApps.DataSource = $null
    $gridApps.Columns.Clear()
    $gridApps.Rows.Clear()
    
    $col = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
    $col.Name = 'Message'
    $col.HeaderText = 'Status'
    $col.AutoSizeMode = 'Fill'
    $gridApps.Columns.Add($col) | Out-Null
    $rowIndex = $gridApps.Rows.Add()
    $gridApps.Rows[$rowIndex].Cells['Message'].Value = 'No installed applications found. Click "Refresh Installed Apps" to try again.'
    
    Set-Status 'No installed applications found'
  }
} catch {
  Set-Status "Error loading installed applications: $($_.Exception.Message)"
  
  # Show error in grid
  $gridApps.DataSource = $null
  $gridApps.Columns.Clear()
  $gridApps.Rows.Clear()
  
  $col = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
  $col.Name = 'Error'
  $col.HeaderText = 'Error'
  $col.AutoSizeMode = 'Fill'
  $gridApps.Columns.Add($col) | Out-Null
  $rowIndex = $gridApps.Rows.Add()
  $gridApps.Rows[$rowIndex].Cells['Error'].Value = "Error: $($_.Exception.Message). Click 'Refresh Installed Apps' to try again."
}

# Show the form
[void]$form.ShowDialog()
