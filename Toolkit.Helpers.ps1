#region ----- Initialization & Helpers -----

# Ensure WinForms is available
Add-Type -AssemblyName System.Windows.Forms | Out-Null
Add-Type -AssemblyName System.Drawing | Out-Null

# Script root (works when doubleâ€‘clicked or run from console)
$global:ScriptRoot = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
$global:LogDir     = Join-Path $ScriptRoot 'Logs'
$global:OutDir     = Join-Path $ScriptRoot 'Exports'
New-Item -ItemType Directory -Force -Path $LogDir, $OutDir | Out-Null

function Write-Log {
  param(
    [string]$Message,
    [ValidateSet('INFO','WARN','ERROR')][string]$Level='INFO'
  )
  $ts = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
  $line = "[$ts][$Level] $Message"
  $line | Tee-Object -FilePath (Join-Path $LogDir "Toolkit.log") -Append | Out-Null
}

# Admin detection & selfâ€‘elevate
function Test-AdminAndElevate {
  param([string]$MainScriptPath)
  $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
  if (-not $isAdmin) {
    Write-Log "Not elevated. Relaunching as admin..." 'WARN'
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName  = 'powershell.exe'
    # Use the passed main script path instead of the current file path
    $scriptPath = if ($MainScriptPath) { $MainScriptPath } else { $MyInvocation.MyCommand.Path }
    $psi.Arguments = '-NoProfile -ExecutionPolicy Bypass -File "' + $scriptPath + '"'
    $psi.Verb      = 'runas'
    try { [Diagnostics.Process]::Start($psi) | Out-Null } catch { [System.Windows.Forms.MessageBox]::Show('Elevation was canceled. Exiting.','Win11 Tech Toolkit',[Windows.Forms.MessageBoxButtons]::OK,[Windows.Forms.MessageBoxIcon]::Warning) }
    exit
  }
}

# Generic runner for commands
function Invoke-CommandLogged {
  param(
    [Parameter(Mandatory)] [scriptblock]$ScriptBlock,
    [string]$ActionName = 'Action'
  )
  try {
    Write-Log "Started: $ActionName"
    & $ScriptBlock
    Write-Log "Completed: $ActionName"
    return $true
  } catch {
    Write-Log "Failed: $ActionName - $($_.Exception.Message)" 'ERROR'
    return $false
  }
}

# UI helpers
function Show-ToolkitToast {
  param([string]$Text,[string]$Title='Win11 Tech Toolkit',[string]$Icon='Information')
  [System.Windows.Forms.MessageBox]::Show($Text,$Title,[Windows.Forms.MessageBoxButtons]::OK,[Windows.Forms.MessageBoxIcon]::$Icon) | Out-Null
}

# Update management
$global:ToolkitVersion = "1.0.0"
$global:RepoOwner = "JKagiDesignsEng"
$global:RepoName = "jkd-toolkit"
$global:UpdateCheckInterval = 24 # Hours

function Get-ToolkitVersion {
  return $global:ToolkitVersion
}

function Test-InternetConnection {
  try {
    $response = Test-NetConnection -ComputerName "github.com" -Port 443 -InformationLevel Quiet -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
    return $response
  }
  catch {
    return $false
  }
}

function Get-LastUpdateCheck {
  $updateFile = Join-Path $global:ScriptRoot "last_update_check.txt"
  if (Test-Path $updateFile) {
    try {
      $lastCheck = Get-Content $updateFile -Raw
      return [datetime]::Parse($lastCheck)
    }
    catch {
      return [datetime]::MinValue
    }
  }
  return [datetime]::MinValue
}

function Set-LastUpdateCheck {
  $updateFile = Join-Path $global:ScriptRoot "last_update_check.txt"
  (Get-Date).ToString() | Set-Content $updateFile -Force
}

function Get-LatestVersionFromGitHub {
  try {
    $apiUrl = "https://api.github.com/repos/$global:RepoOwner/$global:RepoName/releases/latest"
    $response = Invoke-RestMethod -Uri $apiUrl -UseBasicParsing -TimeoutSec 10 -ErrorAction Stop
    return $response.tag_name -replace '^v', ''
  }
  catch {
    Write-Log "Could not check for updates: $($_.Exception.Message)" 'WARN'
    return $null
  }
}

function Get-LatestCommitFromGitHub {
  try {
    $apiUrl = "https://api.github.com/repos/$global:RepoOwner/$global:RepoName/commits/main"
    $response = Invoke-RestMethod -Uri $apiUrl -UseBasicParsing -TimeoutSec 10 -ErrorAction Stop
    return @{
      Sha = $response.sha.Substring(0, 7)
      Date = [datetime]::Parse($response.commit.committer.date)
      Message = $response.commit.message
    }
  }
  catch {
    Write-Log "Could not check for updates: $($_.Exception.Message)" 'WARN'
    return $null
  }
}

function Compare-Versions {
  param(
    [string]$CurrentVersion,
    [string]$LatestVersion
  )
  
  if (-not $LatestVersion) { return $false }
  
  try {
    $current = [version]$CurrentVersion
    $latest = [version]$LatestVersion
    return $latest -gt $current
  }
  catch {
    # If version parsing fails, compare as strings or use commit date
    return $false
  }
}

function Test-UpdateAvailable {
  param([switch]$Force)
  
  # Check if we should check for updates (every 24 hours unless forced)
  $lastCheck = Get-LastUpdateCheck
  $hoursSinceLastCheck = ((Get-Date) - $lastCheck).TotalHours
  
  if (-not $Force -and $hoursSinceLastCheck -lt $global:UpdateCheckInterval) {
    Write-Log "Skipping update check (last checked $([math]::Round($hoursSinceLastCheck, 1)) hours ago)"
    return $false
  }
  
  if (-not (Test-InternetConnection)) {
    Write-Log "No internet connection available for update check" 'WARN'
    return $false
  }
  
  Write-Log "Checking for updates..."
  
  # Try to get latest release version first
  $latestVersion = Get-LatestVersionFromGitHub
  if ($latestVersion -and (Compare-Versions -CurrentVersion $global:ToolkitVersion -LatestVersion $latestVersion)) {
    Write-Log "Update available: $global:ToolkitVersion -> $latestVersion"
    Set-LastUpdateCheck
    return @{
      Available = $true
      Type = "Release"
      CurrentVersion = $global:ToolkitVersion
      LatestVersion = $latestVersion
    }
  }
  
  # If no release updates, check latest commit
  $latestCommit = Get-LatestCommitFromGitHub
  if ($latestCommit) {
    # Check if the latest commit is newer than our script file
    $scriptFile = Join-Path $global:ScriptRoot "jkd-toolkit-main.ps1"
    if (Test-Path $scriptFile) {
      $scriptDate = (Get-Item $scriptFile).LastWriteTime
      if ($latestCommit.Date -gt $scriptDate.AddHours(1)) { # 1 hour buffer
        Write-Log "Development update available: commit $($latestCommit.Sha)"
        Set-LastUpdateCheck
        return @{
          Available = $true
          Type = "Development"
          CurrentVersion = $global:ToolkitVersion
          LatestCommit = $latestCommit
        }
      }
    }
  }
  
  Set-LastUpdateCheck
  Write-Log "No updates available"
  return $false
}

function Show-UpdateNotification {
  param($UpdateInfo)
  
  if ($UpdateInfo.Type -eq "Release") {
    $message = @"
🚀 JKD-Toolkit Update Available!

Current Version: $($UpdateInfo.CurrentVersion)
Latest Version: $($UpdateInfo.LatestVersion)

Would you like to update now?

• Yes: Download and install the update
• No: Continue with current version
• Cancel: Skip this update check
"@
  }
  else {
    $message = @"
🔄 JKD-Toolkit Development Update Available!

A newer development version is available:
Commit: $($UpdateInfo.LatestCommit.Sha)
Date: $($UpdateInfo.LatestCommit.Date.ToString('yyyy-MM-dd HH:mm'))

Would you like to update now?

• Yes: Download and install the latest development version
• No: Continue with current version
• Cancel: Skip this update check
"@
  }
  
  $result = [System.Windows.Forms.MessageBox]::Show(
    $message,
    'Update Available',
    [System.Windows.Forms.MessageBoxButtons]::YesNoCancel,
    [System.Windows.Forms.MessageBoxIcon]::Information
  )
  
  return $result
}

function Invoke-ToolkitUpdate {
  param($UpdateInfo)
  
  try {
    Write-Log "Starting toolkit update process..."
    
    # Create backup directory
    $backupDir = Join-Path $global:ScriptRoot "Backup_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
    New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
    
    # Backup current files
    $filesToBackup = @("jkd-toolkit-main.ps1", "Toolkit.Helpers.ps1", "Toolkit.Actions.ps1")
    foreach ($file in $filesToBackup) {
      $sourcePath = Join-Path $global:ScriptRoot $file
      if (Test-Path $sourcePath) {
        Copy-Item $sourcePath -Destination $backupDir -Force
      }
    }
    Write-Log "Created backup in: $backupDir"
    
    # Download updated files
    $baseUrl = "https://raw.githubusercontent.com/$global:RepoOwner/$global:RepoName/main"
    $downloadSuccess = $true
    
    foreach ($file in $filesToBackup) {
      try {
        $url = "$baseUrl/$file"
        $outFile = Join-Path $global:ScriptRoot $file
        Write-Log "Downloading: $file"
        
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -Uri $url -OutFile $outFile -UseBasicParsing -ErrorAction Stop
        
        Write-Log "Updated: $file"
      }
      catch {
        Write-Log "Failed to download $file`: $($_.Exception.Message)" 'ERROR'
        $downloadSuccess = $false
      }
    }
    
    if ($downloadSuccess) {
      Write-Log "Update completed successfully"
      Show-ToolkitToast "Update completed successfully!`n`nThe toolkit will restart with the new version.`n`nBackup saved to: $backupDir" "Update Complete"
      
      # Restart the toolkit
      $scriptPath = Join-Path $global:ScriptRoot "jkd-toolkit-main.ps1"
      Start-Process -FilePath "powershell.exe" -ArgumentList "-ExecutionPolicy Bypass -File `"$scriptPath`"" -WorkingDirectory $global:ScriptRoot
      exit
    }
    else {
      Write-Log "Update failed - some files could not be downloaded" 'ERROR'
      Show-ToolkitToast "Update failed!`n`nSome files could not be downloaded. The toolkit will continue with the current version.`n`nBackup available at: $backupDir" "Update Failed" "Warning"
    }
  }
  catch {
    Write-Log "Update process failed: $($_.Exception.Message)" 'ERROR'
    Show-ToolkitToast "Update process failed: $($_.Exception.Message)`n`nThe toolkit will continue with the current version." "Update Error" "Error"
  }
}

function Start-UpdateCheck {
  param([switch]$Force, [switch]$Silent)
  
  $updateInfo = Test-UpdateAvailable -Force:$Force
  
  if ($updateInfo -and $updateInfo.Available) {
    if ($Silent) {
      Write-Log "Update available but running in silent mode"
      return
    }
    
    $userChoice = Show-UpdateNotification -UpdateInfo $updateInfo
    
    switch ($userChoice) {
      'Yes' {
        Invoke-ToolkitUpdate -UpdateInfo $updateInfo
      }
      'No' {
        Write-Log "User declined update"
      }
      'Cancel' {
        Write-Log "User cancelled update check"
      }
    }
  }
  elseif (-not $Silent) {
    if ($Force) {
      Show-ToolkitToast "No updates available.`n`nYou are running the latest version." "Up to Date"
    }
  }
}

#region ----- Driver Management Helpers -----

# Show toast notification with different types
function Show-ToolkitToast {
    param(
        [Parameter(Mandatory)]
        [string]$Message,
        [string]$Title = "JKD Toolkit",
        [ValidateSet('Success', 'Warning', 'Error', 'Info')]
        [string]$Type = 'Info'
    )
    
    $icon = switch ($Type) {
        'Success' { [System.Windows.Forms.MessageBoxIcon]::Information }
        'Warning' { [System.Windows.Forms.MessageBoxIcon]::Warning }
        'Error'   { [System.Windows.Forms.MessageBoxIcon]::Error }
        default   { [System.Windows.Forms.MessageBoxIcon]::Information }
    }
    
    [System.Windows.Forms.MessageBox]::Show($Message, $Title, [System.Windows.Forms.MessageBoxButtons]::OK, $icon) | Out-Null
}

# Enhanced toast notification for driver operations
function Show-DriverToast {
    param(
        [Parameter(Mandatory)]
        [string]$Message,
        [string]$Title = "Driver Management",
        [ValidateSet('Success', 'Warning', 'Error', 'Info')]
        [string]$Type = 'Info'
    )
    
    Write-Log "Driver Toast: [$Type] $Message"
    Show-ToolkitToast -Message $Message -Title $Title -Type $Type
}

# Progress tracking for driver operations
function Update-DriverProgress {
    param(
        [int]$Current,
        [int]$Total,
        [string]$Operation,
        [string]$DeviceName
    )
    
    $percent = [math]::Round(($Current / $Total) * 100, 0)
    Write-Log "Driver Progress: $Operation - $DeviceName ($Current/$Total - $percent%)"
    
    # Return progress info for UI updates
    return @{
        Current = $Current
        Total = $Total
        Percent = $percent
        Operation = $Operation
        DeviceName = $DeviceName
    }
}

# Validate driver package before installation
function Test-DriverPackage {
    param(
        [Parameter(Mandatory)]
        [string]$DriverPath
    )
    
    try {
        if (-not (Test-Path $DriverPath)) {
            Write-Log "Driver package not found: $DriverPath" 'ERROR'
            return $false
        }
        
        $extension = [System.IO.Path]::GetExtension($DriverPath).ToLower()
        $validExtensions = @('.inf', '.cab', '.exe', '.msi')
        
        if ($extension -notin $validExtensions) {
            Write-Log "Invalid driver package type: $extension" 'ERROR'
            return $false
        }
        
        # Additional validation for .inf files
        if ($extension -eq '.inf') {
            $infContent = Get-Content $DriverPath -ErrorAction SilentlyContinue
            if (-not $infContent -or $infContent -notmatch '\[Version\]') {
                Write-Log "Invalid INF file format: $DriverPath" 'ERROR'
                return $false
            }
        }
        
        Write-Log "Driver package validated: $DriverPath"
        return $true
    }
    catch {
        Write-Log "Error validating driver package: $($_.Exception.Message)" 'ERROR'
        return $false
    }
}

# Get driver information from INF file
function Get-DriverInfoFromINF {
    param(
        [Parameter(Mandatory)]
        [string]$INFPath
    )
    
    try {
        if (-not (Test-Path $INFPath)) {
            return $null
        }
        
        $infContent = Get-Content $INFPath
        $driverInfo = @{
            DriverName = [System.IO.Path]::GetFileNameWithoutExtension($INFPath)
            Version = 'Unknown'
            Date = 'Unknown'
            Provider = 'Unknown'
            HardwareIDs = @()
        }
        
        foreach ($line in $infContent) {
            if ($line -match '^DriverVer\s*=\s*(.+)') {
                $verInfo = $matches[1] -split ','
                if ($verInfo.Count -ge 2) {
                    $driverInfo.Date = $verInfo[0].Trim()
                    $driverInfo.Version = $verInfo[1].Trim()
                }
            }
            elseif ($line -match '^Provider\s*=\s*(.+)') {
                $driverInfo.Provider = $matches[1].Trim() -replace '"', ''
            }
        }
        
        return $driverInfo
    }
    catch {
        Write-Log "Error reading INF file $INFPath`: $($_.Exception.Message)" 'ERROR'
        return $null
    }
}

# Create driver installation report
function New-DriverInstallReport {
    param(
        [array]$Results,
        [string]$ReportPath
    )
    
    try {
        $report = @()
        $report += "JKD Toolkit - Driver Installation Report"
        $report += "Generated: $(Get-Date)"
        $report += "=" * 50
        $report += ""
        
        $successful = $Results | Where-Object { $_.Success }
        $failed = $Results | Where-Object { -not $_.Success }
        
        $report += "Summary:"
        $report += "  Total drivers processed: $($Results.Count)"
        $report += "  Successful installations: $($successful.Count)"
        $report += "  Failed installations: $($failed.Count)"
        $report += ""
        
        if ($successful.Count -gt 0) {
            $report += "Successful Installations:"
            $report += "-" * 25
            foreach ($result in $successful) {
                $report += "  ✓ $($result.DeviceName) - $($result.DriverName)"
                if ($result.Version) {
                    $report += "    Version: $($result.Version)"
                }
            }
            $report += ""
        }
        
        if ($failed.Count -gt 0) {
            $report += "Failed Installations:"
            $report += "-" * 20
            foreach ($result in $failed) {
                $report += "  ✗ $($result.DeviceName) - $($result.DriverName)"
                $report += "    Error: $($result.Error)"
            }
            $report += ""
        }
        
        $report | Out-File -FilePath $ReportPath -Encoding UTF8
        Write-Log "Driver installation report saved to: $ReportPath"
        
        return $ReportPath
    }
    catch {
        Write-Log "Error creating driver installation report: $($_.Exception.Message)" 'ERROR'
        return $null
    }
}

# Check if system requires restart after driver installation
function Test-RestartRequired {
    try {
        # Check for pending reboot indicators
        $pendingReboot = $false
        
        # Check registry keys that indicate pending reboot
        $regKeys = @(
            'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired',
            'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending',
            'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\PendingFileRenameOperations'
        )
        
        foreach ($key in $regKeys) {
            if (Test-Path $key) {
                $pendingReboot = $true
                break
            }
        }
        
        # Check for pending driver installations
        $driverPending = Get-WmiObject -Class Win32_SystemDriver | Where-Object { $_.State -eq 'Stopped' -and $_.StartMode -eq 'Manual' }
        if ($driverPending) {
            $pendingReboot = $true
        }
        
        return $pendingReboot
    }
    catch {
        Write-Log "Error checking restart requirements: $($_.Exception.Message)" 'WARN'
        return $false
    }
}

#endregion
#endregion

