#Requires -RunAsAdministrator
<#
.SYNOPSIS
    JKD-Toolkit Web Installer
    
.DESCRIPTION
    Downloads and installs the JKD-Toolkit from GitHub repository.
    Can be executed with: irm "https://raw.githubusercontent.com/JKagiDesignsEng/jkd-toolkit/main/install.ps1" | iex
    
.PARAMETER InstallPath
    Directory where the toolkit will be installed. Defaults to C:\Tools\JKD-Toolkit
    
.PARAMETER AutoLaunch
    Automatically launch the toolkit after installation
    
.PARAMETER Force
    Force overwrite existing installation
    
.EXAMPLE
    irm "https://raw.githubusercontent.com/JKagiDesignsEng/jkd-toolkit/main/install.ps1" | iex
    
.EXAMPLE
    irm "https://raw.githubusercontent.com/JKagiDesignsEng/jkd-toolkit/main/install.ps1" | iex -InstallPath "D:\Tools\JKD-Toolkit" -AutoLaunch
    
.NOTES
    Author: JKagiDesigns LLC
    Requires: PowerShell 5.1+, Administrator privileges
#>

[CmdletBinding()]
param(
    [string]$InstallPath = "C:\Tools\JKD-Toolkit",
    [switch]$AutoLaunch,
    [switch]$Force
)

# Configuration
$RepoOwner = "JKagiDesignsEng"
$RepoName = "jkd-toolkit"
$Branch = "main"
$BaseUrl = "https://raw.githubusercontent.com/$RepoOwner/$RepoName/$Branch"

# Required files to download
$RequiredFiles = @(
    "jkd-toolkit-main.ps1",
    "Toolkit.Helpers.ps1", 
    "Toolkit.Actions.ps1",
    "JKD-icon.ico",
    "README.md"
)

# Colors for output
$Colors = @{
    Success = "Green"
    Warning = "Yellow" 
    Error = "Red"
    Info = "Cyan"
    Header = "Magenta"
}

function Write-ColorOutput {
    param(
        [string]$Message,
        [string]$Color = "White"
    )
    Write-Host $Message -ForegroundColor $Colors[$Color]
}

function Test-AdminRights {
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentUser)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Test-InternetConnection {
    try {
        $response = Invoke-WebRequest -Uri "https://github.com" -UseBasicParsing -TimeoutSec 10 -ErrorAction Stop
        return $response.StatusCode -eq 200
    }
    catch {
        return $false
    }
}

function Get-LatestRelease {
    try {
        $apiUrl = "https://api.github.com/repos/$RepoOwner/$RepoName/releases/latest"
        $release = Invoke-RestMethod -Uri $apiUrl -UseBasicParsing -ErrorAction Stop
        return $release
    }
    catch {
        Write-ColorOutput "Note: Could not fetch latest release info, using main branch" "Warning"
        return $null
    }
}

function New-Directory {
    param([string]$Path)
    
    if (Test-Path $Path) {
        if ($Force) {
            Write-ColorOutput "Removing existing installation..." "Warning"
            Remove-Item -Path $Path -Recurse -Force
        }
        else {
            Write-ColorOutput "Installation directory already exists: $Path" "Warning"
            $response = Read-Host "Do you want to overwrite it? (y/N)"
            if ($response -notmatch '^[Yy]') {
                Write-ColorOutput "Installation cancelled by user" "Error"
                exit 1
            }
            Remove-Item -Path $Path -Recurse -Force
        }
    }
    
    try {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
        Write-ColorOutput "Created installation directory: $Path" "Success"
        return $true
    }
    catch {
        Write-ColorOutput "Failed to create directory: $($_.Exception.Message)" "Error"
        return $false
    }
}

function Invoke-FileDownload {
    param(
        [string]$Url,
        [string]$OutFile,
        [string]$Description
    )
    
    try {
        Write-Host "  Downloading $Description..." -NoNewline
        
        # Use TLS 1.2 for compatibility
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        
        Invoke-WebRequest -Uri $Url -OutFile $OutFile -UseBasicParsing -ErrorAction Stop
        
        if (Test-Path $OutFile) {
            $fileSize = (Get-Item $OutFile).Length
            Write-ColorOutput " ✓ ($([math]::Round($fileSize/1KB, 1)) KB)" "Success"
            return $true
        }
        else {
            Write-ColorOutput " ✗ File not created" "Error"
            return $false
        }
    }
    catch {
        Write-ColorOutput " ✗ $($_.Exception.Message)" "Error"
        return $false
    }
}

function Install-JKDToolkit {
    Write-ColorOutput @"

╔══════════════════════════════════════════════════════════════╗
║                    JKD-Toolkit Installer                    ║
║               Windows 11 Tech Toolkit Setup                 ║
╚══════════════════════════════════════════════════════════════╝

"@ "Header"

    # Check prerequisites
    Write-ColorOutput "Checking prerequisites..." "Info"
    
    if (-not (Test-AdminRights)) {
        Write-ColorOutput "❌ Administrator privileges required!" "Error"
        Write-ColorOutput "Please run PowerShell as Administrator and try again." "Error"
        exit 1
    }
    Write-ColorOutput "✓ Administrator privileges confirmed" "Success"
    
    if (-not (Test-InternetConnection)) {
        Write-ColorOutput "❌ Internet connection required!" "Error"
        Write-ColorOutput "Please check your network connection and try again." "Error"
        exit 1
    }
    Write-ColorOutput "✓ Internet connection verified" "Success"
    
    # Get latest release info
    Write-ColorOutput "Checking for latest version..." "Info"
    $latestRelease = Get-LatestRelease
    if ($latestRelease) {
        Write-ColorOutput "✓ Latest version: $($latestRelease.tag_name)" "Success"
        Write-ColorOutput "  Published: $($latestRelease.published_at)" "Info"
    }
    
    # Create installation directory
    Write-ColorOutput "Setting up installation directory..." "Info"
    if (-not (New-Directory -Path $InstallPath)) {
        exit 1
    }
    
    # Download files
    Write-ColorOutput "Downloading JKD-Toolkit files..." "Info"
    $downloadSuccess = $true
    
    foreach ($file in $RequiredFiles) {
        $url = "$BaseUrl/$file"
        $outFile = Join-Path $InstallPath $file
        
        if (-not (Invoke-FileDownload -Url $url -OutFile $outFile -Description $file)) {
            $downloadSuccess = $false
        }
    }
    
    if (-not $downloadSuccess) {
        Write-ColorOutput "❌ Some files failed to download. Installation incomplete." "Error"
        exit 1
    }
    
    # Create additional directories
    $logDir = Join-Path $InstallPath "Logs"
    $exportDir = Join-Path $InstallPath "Exports"
    New-Item -ItemType Directory -Path $logDir, $exportDir -Force | Out-Null
    
    # Create desktop shortcut
    Write-ColorOutput "Creating desktop shortcut..." "Info"
    try {
        $WshShell = New-Object -ComObject WScript.Shell
        $shortcutPath = Join-Path ([Environment]::GetFolderPath("Desktop")) "JKD-Toolkit.lnk"
        $shortcut = $WshShell.CreateShortcut($shortcutPath)
        $shortcut.TargetPath = "powershell.exe"
        $shortcut.Arguments = "-ExecutionPolicy Bypass -File `"$(Join-Path $InstallPath 'jkd-toolkit-main.ps1')`""
        $shortcut.WorkingDirectory = $InstallPath
        $shortcut.Description = "JKD-Toolkit - Windows 11 Tech Toolkit"
        $shortcut.IconLocation = Join-Path $InstallPath "JKD-icon.ico"
        $shortcut.Save()
        Write-ColorOutput "✓ Desktop shortcut created" "Success"
    }
    catch {
        Write-ColorOutput "⚠ Could not create desktop shortcut: $($_.Exception.Message)" "Warning"
    }
    
    # Add to PATH (optional)
    Write-ColorOutput "Adding to system PATH..." "Info"
    try {
        $currentPath = [Environment]::GetEnvironmentVariable("PATH", "Machine")
        if ($currentPath -notlike "*$InstallPath*") {
            $newPath = "$currentPath;$InstallPath"
            [Environment]::SetEnvironmentVariable("PATH", $newPath, "Machine")
            Write-ColorOutput "✓ Added to system PATH" "Success"
        }
        else {
            Write-ColorOutput "✓ Already in system PATH" "Success"
        }
    }
    catch {
        Write-ColorOutput "⚠ Could not add to PATH: $($_.Exception.Message)" "Warning"
    }
    
    # Installation complete
    Write-ColorOutput @"

╔══════════════════════════════════════════════════════════════╗
║                   Installation Complete! ✓                  ║
╚══════════════════════════════════════════════════════════════╝

Installation Details:
• Location: $InstallPath
• Files: $($RequiredFiles.Count) files downloaded
• Shortcuts: Desktop shortcut created
• PATH: Added to system PATH

Usage Options:
1. Double-click desktop shortcut
2. Run from Start Menu: 'JKD-Toolkit'
3. PowerShell: jkd-toolkit-main.ps1
4. Command: powershell -ExecutionPolicy Bypass -File "$InstallPath\jkd-toolkit-main.ps1"

"@ "Success"

    if ($AutoLaunch) {
        Write-ColorOutput "Auto-launching JKD-Toolkit..." "Info"
        Start-Sleep -Seconds 2
        & powershell.exe -ExecutionPolicy Bypass -File (Join-Path $InstallPath "jkd-toolkit-main.ps1")
    }
    else {
        Write-ColorOutput "To launch the toolkit, use the desktop shortcut or run:" "Info"
        Write-ColorOutput "  powershell -ExecutionPolicy Bypass -File `"$InstallPath\jkd-toolkit-main.ps1`"" "Info"
    }
}

# Main execution
try {
    Install-JKDToolkit
}
catch {
    Write-ColorOutput "❌ Installation failed: $($_.Exception.Message)" "Error"
    Write-ColorOutput "Please check the error details above and try again." "Error"
    exit 1
}