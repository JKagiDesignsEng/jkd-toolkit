@echo off
:: JKD-Toolkit Quick Installer
:: Alternative to PowerShell one-liner for users who prefer batch files

title JKD-Toolkit Installer

echo.
echo ╔══════════════════════════════════════════════════════════════╗
echo ║                    JKD-Toolkit Installer                    ║
echo ║               Windows 11 Tech Toolkit Setup                 ║
echo ╚══════════════════════════════════════════════════════════════╝
echo.

:: Check for admin privileges
net session >nul 2>&1
if %errorLevel% neq 0 (
    echo [ERROR] Administrator privileges required!
    echo Please right-click this file and select "Run as administrator"
    echo.
    pause
    exit /b 1
)

echo [INFO] Administrator privileges confirmed
echo [INFO] Launching PowerShell installer...
echo.

:: Run the PowerShell installer
powershell.exe -ExecutionPolicy Bypass -Command "& {irm 'https://raw.githubusercontent.com/JKagiDesignsEng/jkd-toolkit/main/install.ps1' | iex}"

if %errorLevel% equ 0 (
    echo.
    echo [SUCCESS] Installation completed successfully!
    echo You can now find JKD-Toolkit on your desktop.
) else (
    echo.
    echo [ERROR] Installation failed. Please try running the PowerShell command manually.
    echo Command: irm "https://raw.githubusercontent.com/JKagiDesignsEng/jkd-toolkit/main/install.ps1" ^| iex
)

echo.
pause