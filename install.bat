@echo off
:: JKD-Toolkit Quick Installer
:: Automatically elevates to administrator privileges if needed

title JKD-Toolkit Installer

echo.
echo ╔══════════════════════════════════════════════════════════════╗
echo ║                    JKD-Toolkit Installer                    ║
echo ║               Windows 11 Tech Toolkit Setup                 ║
echo ╚══════════════════════════════════════════════════════════════╝
echo.

echo [INFO] Launching PowerShell installer with auto-elevation...
echo [INFO] You may be prompted for administrator privileges.
echo.

:: Run the PowerShell installer (it will handle elevation automatically)
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