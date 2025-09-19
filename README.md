# JKD Toolkit (PowerShell WinForms)

A portable PowerShell-based GUI to perform common Windows maintenance, networking, and app management tasks. The UI is built with WinForms and prints results to the console for transparency.

## Requirements

- Windows 10 or 11
- PowerShell 5.1 (Windows PowerShell) or later
- .NET Framework (preinstalled on Windows)
- Administrator privileges for most operations (the app will prompt to elevate)
- Optional: `winget` and/or `choco` on PATH for the Applications tab

## Quick start

Run from an elevated PowerShell console (or allow the app to self-elevate):

```powershell
powershell -ExecutionPolicy Bypass -File ".\jkd-toolkit-main.ps1"
```

Or install quickly with the provided installer one-liner (v2 branch):

```powershell
irm 'https://raw.githubusercontent.com/JKagiDesignsEng/jkd-toolkit/v2/install.ps1' | iex
```

## What’s included

The app opens a single window with two tabs: `Tools` and `Applications`.

### Tools tab

Grouped areas: Quick Tools, Maintenance, and Networking.

Quick Tools (examples):

- Toggle Dark Mode
- Check/Hide Activation
- Run O&O ShutUp2 (if available)
- Set Wallpaper
- Run Microsoft Update (best-effort workflow)

Maintenance (examples):

- DISM image checks and RestoreHealth (optional `/LimitAccess`)
- Check disk (chkdsk)

Disk tools (new in v2):

- Format Disks: Opens Windows Disk Management so you can partition, format, or prepare drives manually. The toolkit does not perform destructive formatting directly; use Disk Management or dedicated imaging tools for destructive operations.
- Clone Disk: Provides a guided flow to create a VHD/VHDX using `disk2vhd` (Sysinternals) when available, or shows guidance to use Clonezilla for full device-to-device cloning. The button prompts for destination and requires confirmation before running elevated commands. Full device cloning is destructive — double-check targets and backups.
- Create Recovery: Launches the Windows Recovery Drive creation tool (`recoverydrive.exe`) or opens the Settings > Recovery page so you can create a USB recovery drive. Requires a USB drive and explicit confirmation in the system tool.
- Use Recovery: Opens Settings > Recovery so you can boot from or apply existing recovery media.

Networking (examples):

- Ping: `Test-Connection -ComputerName <target> -Count 4`
- TraceRoute: `Test-NetConnection -ComputerName <target> -TraceRoute`
- Get Network Configuration: `Get-NetIPConfiguration`
- Show Network Passwords (uses `netsh wlan`)

All outputs from Tools print to the console.

### Applications tab

- Installed: lists installed software from registry uninstall keys
- Search (winget/choco): queries `winget` and/or `choco` for packages
- Install Selected / Uninstall Selected: runs `winget`/`choco` or uses registry UninstallString

Notes: `winget` and `choco` must be on PATH to use those sources.

## Troubleshooting

- `winget` not recognized: install App Installer from Microsoft
- `choco` not recognized: install Chocolatey
- Execution policy blocks the script: run with `-ExecutionPolicy Bypass`
- Jobs: background jobs are per PowerShell session; use the same console to query job output

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

## License

Copyright © JKagiDesigns LLC. All rights reserved.

This toolkit is intended for IT professionals and advanced users. Test changes in a safe environment before applying to production systems.

Safety notes:

- Always verify the destination drive when performing clone or format operations. Mistargeting can result in data loss.
- `disk2vhd` creates virtual disk images (VHD/VHDX) and is non-destructive to the source, but images can be large — ensure you have sufficient free space.
- For bit-for-bit device cloning use Clonezilla from bootable media; the toolkit offers guidance but does not automate creating Clonezilla media.
