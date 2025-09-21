param(
    [string]$InstallDir = "$env:LOCALAPPDATA\jkd-toolkit",
    [switch]$Force
)

function Write-Log { param($m) Write-Host $m }

try {
    Write-Log "JKD Toolkit installer"
    $zipUrl = 'https://github.com/JKagiDesignsEng/jkd-toolkit/archive/refs/heads/v2.zip'
    Write-Log "Downloading release from: $zipUrl"

    $tmpZip = Join-Path $env:TEMP ("jkd-toolkit-" + [guid]::NewGuid().ToString() + ".zip")
    Invoke-WebRequest -Uri $zipUrl -OutFile $tmpZip -UseBasicParsing -ErrorAction Stop

    $extractDir = Join-Path $env:TEMP ("jkd-toolkit-extract-" + [guid]::NewGuid().ToString())
    Expand-Archive -Path $tmpZip -DestinationPath $extractDir -Force

    $rootFolder = Get-ChildItem -Path $extractDir | Where-Object { $_.PSIsContainer } | Select-Object -First 1
    if (-not $rootFolder) { throw 'Archive layout unexpected - cannot find root folder' }

    $sourcePath = $rootFolder.FullName

    if (Test-Path $InstallDir) {
        if ($Force) {
            Write-Log "Removing existing install at $InstallDir (force)."
            Remove-Item -Path $InstallDir -Recurse -Force -ErrorAction SilentlyContinue
        } else {
            Write-Log "Updating existing install at $InstallDir"
        }
    }

    Write-Log "Installing to: $InstallDir"
    New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null

    Write-Log "Copying files..."
    Copy-Item -Path (Join-Path $sourcePath '*') -Destination $InstallDir -Recurse -Force

    # Create a simple launcher script
    $launcher = Join-Path $InstallDir 'run-jkd-toolkit.ps1'
    $launcherContent = @"
# Launcher for JKD Toolkit
Set-Location -Path '$InstallDir'
powershell -NoProfile -ExecutionPolicy Bypass -NoExit -File `"$InstallDir\jkd-toolkit-main.ps1`"
"@
    $launcherContent | Set-Content -Path $launcher -Encoding UTF8

    # Create desktop shortcut
    try {
        $WshShell = New-Object -ComObject WScript.Shell
        $desktopPath = [Environment]::GetFolderPath('Desktop')
        $shortcutPath = Join-Path $desktopPath 'JKD Toolkit.lnk'
        $Shortcut = $WshShell.CreateShortcut($shortcutPath)
        $Shortcut.TargetPath = 'powershell.exe'
        $Shortcut.Arguments = "-NoProfile -ExecutionPolicy Bypass -NoExit -File `"$InstallDir\jkd-toolkit-main.ps1`""
        $Shortcut.WorkingDirectory = $InstallDir
        $Shortcut.Description = 'JKD Toolkit - Windows maintenance and networking tools'
        $iconPath = Join-Path $InstallDir 'Resources\jkd-icon.ico'
        if (Test-Path $iconPath) { $Shortcut.IconLocation = $iconPath }
        $Shortcut.Save()
        Write-Log "Desktop shortcut created: $shortcutPath"
    } catch {
        Write-Log "Warning: Could not create desktop shortcut: $($_.Exception.Message)"
    }

    Write-Log "Installation complete."
    Write-Log "Run the toolkit with:`n  Desktop shortcut: 'JKD Toolkit'`n  PowerShell: & '$launcher'`n  Or: powershell -NoProfile -ExecutionPolicy Bypass -NoExit -File '$InstallDir\jkd-toolkit-main.ps1'"
} catch {
    Write-Host "Installation failed: $($_.Exception.Message)"
    exit 1
} finally {
    try { Remove-Item -Path $tmpZip -ErrorAction SilentlyContinue } catch { }
    try { Remove-Item -Path $extractDir -Recurse -Force -ErrorAction SilentlyContinue } catch { }
}
