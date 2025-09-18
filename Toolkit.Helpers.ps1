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
#endregion

