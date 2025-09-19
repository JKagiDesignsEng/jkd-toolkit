# JKD Toolkit (PowerShell WinForms)

A portable PowerShell-based GUI to perform common Windows maintenance, networking, and app management tasks. The UI is built with WinForms and prints results to the console for transparency.

This README documents exactly what the toolkit does today, the commands it runs under the hood, and how to use it.

## Requirements

- Windows 10 or 11
- PowerShell 5.1 or later (Windows PowerShell is fine)
- .NET Framework (preinstalled on Windows)
# JKD Toolkit (PowerShell WinForms)

A portable PowerShell-based GUI to perform common Windows maintenance, networking, and app management tasks. The UI is built with WinForms and prints results to the console for transparency.

This README documents the toolkit's controls, how to use them, and recent additions.

## Requirements

- Windows 10 or 11
- PowerShell 5.1 or later (Windows PowerShell is fine)
- .NET Framework (preinstalled on Windows)
- Administrator privileges for most operations (the app self-elevates)
- Optional: `winget` and/or `choco` on PATH for the Applications tab

## Quick start

Run from an elevated PowerShell console (or allow the app to self-elevate):

```powershell
powershell -ExecutionPolicy Bypass -File ".\jkd-toolkit-main.ps1"
```

Or install quickly with a one-liner (downloads the `v2` branch and installs to `%LOCALAPPDATA%\jkd-toolkit` by default):

```powershell
irm 'https://raw.githubusercontent.com/JKagiDesignsEng/jkd-toolkit/v2/install.ps1' | iex
```

## What’s included (and how it works)

The app opens a single window with two tabs: `Tools` and `Applications`.

### Tools tab

The Tools tab contains three grouped areas: Quick Tools, Maintenance, and Networking.
# JKD Toolkit (PowerShell WinForms)

A portable PowerShell-based GUI to perform common Windows maintenance, networking, and app management tasks. The UI is built with WinForms and prints results to the console for transparency.

This README documents the toolkit's controls, how to use them, and recent additions.

## Requirements

- Windows 10 or 11
- PowerShell 5.1 or later (Windows PowerShell is fine)
- .NET Framework (preinstalled on Windows)
- Administrator privileges for most operations (the app self-elevates)
- Optional: `winget` and/or `choco` on PATH for the Applications tab

## Quick start

Run from an elevated PowerShell console (or allow the app to self-elevate):

```powershell
powershell -ExecutionPolicy Bypass -File ".\jkd-toolkit-main.ps1"
```

Or install quickly with a one-liner (downloads the `v2` branch and installs to `%LOCALAPPDATA%\\jkd-toolkit` by default):

```powershell
irm 'https://raw.githubusercontent.com/JKagiDesignsEng/jkd-toolkit/v2/install.ps1' | iex
```

## What’s included (and how it works)

The app opens a single window with two tabs: `Tools` and `Applications`.

### Tools tab

The Tools tab contains three grouped areas: Quick Tools, Maintenance, and Networking.

#### Quick Tools

- Toggle Dark Mode
  - Switches between light and dark by setting these registry values for the current user:
    - `HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize\\AppsUseLightTheme` (DWORD 0/1)
    - `HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize\\SystemUsesLightTheme` (DWORD 0/1)

- Check/Hide Activation
  - Checks activation with:
    - `cscript.exe //nologo %windir%\\system32\\slmgr.vbs /xpr`
  - Best-effort cosmetic tweak: sets `HKCU:\\Control Panel\\Desktop\\PaintDesktopVersion=0` and refreshes desktop with `RUNDLL32.EXE user32.dll,UpdatePerUserSystemParameters 1, True`.

- Run O&O ShutUp2
  - Launches `Tools\\OOSU2.exe` if present. If missing, tries to install via `winget` or `choco`.

- Set Wallpaper
  - Opens a file dialog and uses the Win32 API `SystemParametersInfo` to set the wallpaper.

- Run Microsoft Update
  - Best-effort workflow to run Windows Update and scan for driver updates:
    - Tries `PSWindowsUpdate` module (installs from PSGallery if missing).
    - Falls back to `UsoClient StartScan/StartDownload/StartInstall` if available.
    # JKD Toolkit (PowerShell WinForms)

    A portable PowerShell-based GUI to perform common Windows maintenance, networking, and app management tasks. The UI is built with WinForms and prints results to the console for transparency.

    This README documents the toolkit's controls, how to use them, and recent additions.

    ## Requirements

    - Windows 10 or 11
    - PowerShell 5.1 or later (Windows PowerShell is fine)
    - .NET Framework (preinstalled on Windows)
    - Administrator privileges for most operations (the app self-elevates)
    - Optional: `winget` and/or `choco` on PATH for the Applications tab

    ## Quick start

    Run from an elevated PowerShell console (or allow the app to self-elevate):

    ```powershell
    powershell -ExecutionPolicy Bypass -File ".\jkd-toolkit-main.ps1"
    ```

    Or install quickly with a one-liner (downloads the `v2` branch and installs to `%LOCALAPPDATA%\\jkd-toolkit` by default):

    ```powershell
    irm 'https://raw.githubusercontent.com/JKagiDesignsEng/jkd-toolkit/v2/install.ps1' | iex
    ```

    ## What’s included (and how it works)

    The app opens a single window with two tabs: `Tools` and `Applications`.

    ### Tools tab

    The Tools tab contains three grouped areas: Quick Tools, Maintenance, and Networking.

    #### Quick Tools

    - Toggle Dark Mode
      - Switches between light and dark by setting these registry values for the current user:
        - `HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize\\AppsUseLightTheme` (DWORD 0/1)
        - `HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize\\SystemUsesLightTheme` (DWORD 0/1)

    - Check/Hide Activation
      - Checks activation with:
        - `cscript.exe //nologo %windir%\\system32\\slmgr.vbs /xpr`
      - Best-effort cosmetic tweak: sets `HKCU:\\Control Panel\\Desktop\\PaintDesktopVersion=0` and refreshes desktop with `RUNDLL32.EXE user32.dll,UpdatePerUserSystemParameters 1, True`.

    - Run O&O ShutUp2
      - Launches `Tools\\OOSU2.exe` if present. If missing, tries to install via `winget` or `choco`.

    - Set Wallpaper
      - Opens a file dialog and uses the Win32 API `SystemParametersInfo` to set the wallpaper.

    - Run Microsoft Update
      - Best-effort workflow to run Windows Update and scan for driver updates:
        - Tries `PSWindowsUpdate` module (installs from PSGallery if missing).
        - Falls back to `UsoClient StartScan/StartDownload/StartInstall` if available.
        - Runs `pnputil /scan-devices` when available for driver scanning.
        - Reports Windows Update service status and common pending-reboot indicators.
      - Notes:
        - Requires administrator rights.
        - Runs in the background and prints progress to the console; it does not force a reboot.
      - New: `Get Update Status` button appears under the main Run Microsoft Update button and queries the background job started by the update workflow. It shows job state and recent output using `Get-Job` and `Receive-Job -Keep`.

    ### Maintenance

    - Image group (DISM)
      - Check Health: `dism.exe /online /Cleanup-Image /CheckHealth` (optional `/LimitAccess`)
      - Restore Health: `dism.exe /online /Cleanup-Image /RestoreHealth` (optional `/LimitAccess`)
      - Restore from ISO: downloads/mounts an ISO and runs DISM with the ISO as source.

    - Disk group
      - Check Disk For Errors: invokes `chkdsk C: /f` (may schedule on reboot if volume is in use).

    ### Networking

    - Ping: `Test-Connection -ComputerName <target> -Count 4`
    - TraceRoute: `Test-NetConnection -ComputerName <target> -TraceRoute`
    - Get Network Configuration: `Get-NetIPConfiguration`
    - Show Network Passwords: uses `netsh wlan show profiles` and `netsh wlan show profile name="<SSID>" key=clear`

    All outputs in the Tools tab print to the console.

    ### Applications tab

    - Installed: lists installed software from registry uninstall keys.
    - Search (winget/choco): queries `winget` and/or `choco` for packages.
    - Install Selected: runs `winget install` or `choco install` as appropriate.
    - Uninstall Selected: runs registry `UninstallString` when available or `winget uninstall` when possible.

    Notes: winget/choco must be installed and on PATH to use those sources.

    ## Console divider behavior and logs

    The toolkit prints a horizontal divider to the console at logical boundaries (for example after activation checks, after ping/traceroute output blocks, and when background jobs flush output). This keeps related output grouped together without adding a divider after every single line.

    If you prefer file logs, I can add automatic job-output capture to a `Logs\\` directory when background jobs complete.

    ## Installer

    - `install.ps1` is provided as a simple bootstrap installer. It downloads the `v2` branch zip from GitHub and copies files to the chosen install directory (defaults to `%LOCALAPPDATA%\\jkd-toolkit`).

    Example one-liner:

    ```powershell
    irm 'https://raw.githubusercontent.com/JKagiDesignsEng/jkd-toolkit/v2/install.ps1' | iex
    ```

    ## Troubleshooting

    - `winget` not recognized: install App Installer from Microsoft or visit [App Installer (winget)](https://learn.microsoft.com/windows/package-manager/winget/)
    - `choco` not recognized: install Chocolatey: [Chocolatey install](https://chocolatey.org/install)
    - Execution policy blocks the script: run with `-ExecutionPolicy Bypass`.
    - Jobs/Receive-Job: jobs are per PowerShell session. If you start the GUI from an elevated console, use that same console to call `Get-Job`/`Receive-Job`.

    ## Repository layout

    ```text
    README.md
    install.ps1
    jkd-toolkit-main.ps1
    Controls/
       ActivationControl.ps1
       CheckDiskControl.ps1
       CheckHealthControl.ps1
       GetInstalledApplicationsControl.ps1
       GetNetworkConfigurationControl.ps1
       NetworkPasswordControl.ps1
       OOSUControl.ps1
       RestoreHealthControl.ps1
       RestoreHealthFromISOControl.ps1
       ToggleDarkModeControl.ps1
       TraceRouteControl.ps1
       WallpaperControl.ps1
       RunMicrosoftUpdateControl.ps1
       Helpers/
          DiskSpaceHelper.ps1
    Resources/
       JKD-icon.ico
    ```

    ## License and attribution

    Copyright © JKagiDesigns LLC. All rights reserved.

    This toolkit is intended for IT professionals and advanced users. Test changes in a safe environment before applying to production systems.
