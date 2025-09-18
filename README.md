# JKD-Toolkit - Windows 11 Tech Toolkit

A comprehensive PowerShell-based GUI toolkit designed for IT professionals, technicians, and power users to troubleshoot, repair, and set up Windows 11 systems. This portable toolkit provides an intuitive tabbed interface for common system maintenance tasks, driver management, application installation/removal, and system diagnostics.

## 🚀 Features

### 📊 System Overview
- **System Information Display**: Real-time hardware and software details (CPU, RAM, GPU, OS version, uptime)
- **System Report Export**: Generate detailed JSON reports for documentation or support tickets
- **Network Configuration**: Display current IP address, domain, and system specifications

### 🌐 Network Diagnostics & Repair
- **DNS Management**: Flush DNS cache to resolve web browsing issues
- **IP Address Renewal**: Release and renew DHCP IP assignments
- **Network Stack Reset**: Full Winsock and TCP/IP reset for stubborn connectivity problems
- **Connectivity Testing**: Automated tests for HTTP access and ping connectivity (1.1.1.1, 8.8.8.8)
- **Custom Ping Tool**: Test specific hosts with detailed response time and status information

### 🔧 System Repairs
- **SFC (System File Checker)**: Scan and repair corrupted Windows system files
- **DISM RestoreHealth**: Repair Windows image corruption and system health issues
- **Windows Update Cache Reset**: Clear stuck update downloads and reset Windows Update services
- **Print Spooler Restart**: Fix printing problems by restarting the print service
- **Windows Firewall Reset**: Restore firewall settings to defaults

### 🧹 System Maintenance
- **Temporary File Cleanup**: Remove temporary files from system and user directories
- **System Restore Point Creation**: Create backup snapshots before making system changes
- **Installed Programs Export**: Generate CSV reports of all installed software
- **Driver Inventory Export**: Create comprehensive driver lists for documentation

### 🔒 Privacy & Debloating Tools
- **O&O ShutUp10++ Integration**: Download and launch the popular privacy configuration tool
- **Windows Privacy Fixes**: Apply common privacy settings (disable telemetry, advertising ID, location tracking)
- **Windows Debloater**: Remove common bloatware and unnecessary Windows applications
- **Cortana Disable**: Turn off Cortana and related data collection

### 🎨 Windows Customization
- **Dark/Light Mode Toggle**: Switch between Windows themes instantly
- **WSL Installation**: Install Windows Subsystem for Linux with Ubuntu support
- **Custom Wallpaper**: Browse and set desktop wallpapers with proper scaling

### 💾 Software Management
- **Package Manager Support**: Install and manage WinGet and Chocolatey
- **Application Search**: Find and install software from WinGet and Chocolatey repositories
- **Bulk Installation**: Install multiple applications simultaneously
- **Application Uninstaller**: Remove installed programs with advanced deduplication
- **Smart Application Detection**: Comprehensive scanning across WinGet, registry, and system sources

### 🔍 Driver Management
- **Missing Driver Detection**: Scan for missing, corrupted, or problematic drivers
- **Offline Driver Support**: Special guidance for systems without internet connectivity
- **Network Driver Priority**: Identify critical network driver issues that prevent internet access
- **Driver Installation Guidance**: Step-by-step instructions for manual driver installation

### ⚙️ System Setup & Optimization
- **Windows Features Installation**: Enable useful Windows components (WSL, Hyper-V, Virtual Machine Platform)
- **Performance Optimization**: Apply system tweaks for improved speed and responsiveness
- **Service Management**: Disable unnecessary services for better performance
- **Power Plan Optimization**: Set high-performance power settings

### 🛠️ Administrative Tools Launcher
Quick access to essential Windows management tools:
- Device Manager
- Event Viewer
- Services Manager
- Task Manager
- Windows Update Settings
- Startup Apps Manager

## 📋 System Requirements

- **Operating System**: Windows 11 (optimized for, may work on Windows 10)
- **PowerShell**: Version 5.1 or later
- **Privileges**: Administrator rights (toolkit will auto-elevate)
- **Dependencies**: .NET Framework (typically pre-installed)
- **Storage**: Minimal footprint, creates Logs and Exports folders

## 🚦 Getting Started

### Installation
1. Download or clone this repository to your desired location (USB drive recommended for portability)
2. Ensure all three files are in the same directory:
   - `jkd-toolkit-main.ps1` (main application)
   - `Toolkit.Helpers.ps1` (helper functions)
   - `Toolkit.Actions.ps1` (action implementations)
3. Optional: Include `JKD-icon.ico` for custom application icon

### Running the Toolkit

#### Method 1: Right-Click Execution (Recommended)
```
Right-click jkd-toolkit-main.ps1 → "Run with PowerShell"
```

#### Method 2: PowerShell Command Line
```powershell
powershell -ExecutionPolicy Bypass -File ".\jkd-toolkit-main.ps1"
```

#### Method 3: Elevated PowerShell
```powershell
Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process
.\jkd-toolkit-main.ps1
```

> **Note**: The toolkit will automatically request administrator privileges if not already elevated.

## 📁 File Structure

```
jkd-toolkit/
├── jkd-toolkit-main.ps1          # Main GUI application
├── Toolkit.Helpers.ps1            # Helper functions and utilities
├── Toolkit.Actions.ps1            # Core action implementations
├── JKD-icon.ico                   # Application icon (optional)
├── README.md                      # This documentation
├── Logs/                          # Auto-created log directory
│   └── Toolkit.log               # Detailed operation logs
└── Exports/                       # Auto-created export directory
    ├── SystemReport_*.json        # System information exports
    ├── InstalledPrograms_*.csv    # Software inventory exports
    └── Drivers_*.txt              # Driver inventory exports
```

## 🔧 Features Deep Dive

### Package Manager Integration
The toolkit supports both major Windows package managers:

**WinGet (Microsoft Store)**
- Built into Windows 11
- Official Microsoft package repository
- Automatic security verification
- Integration with Microsoft Store apps

**Chocolatey (Community)**
- Large community repository
- Extensive software selection
- Community-maintained packages
- Advanced package management features

### Advanced Application Management
- **Intelligent Deduplication**: Combines WinGet and registry data for comprehensive application lists
- **Source Prioritization**: Prefers WinGet entries over registry for accuracy
- **Truncation Handling**: Resolves name truncation issues in package managers
- **Bulk Operations**: Install or uninstall multiple applications simultaneously
- **Safe Uninstallation**: Confirmation dialogs and detailed logging prevent accidental removal

### Driver Diagnostics
The toolkit provides comprehensive driver analysis:
- **Error Code Detection**: Identifies devices with error codes 28, 31, 37, 39, 43
- **Unknown Device Detection**: Finds unrecognized hardware
- **Network Priority**: Special handling for network adapter issues
- **Offline Support**: Provides manual installation guidance when internet is unavailable
- **Detailed Reporting**: Saves driver reports to desktop for reference

### Privacy & Security
- **Telemetry Disable**: Turn off Windows data collection
- **Advertising ID**: Disable personalized advertising
- **Location Tracking**: Turn off location services
- **Feedback Requests**: Disable Windows feedback prompts
- **Bloatware Removal**: Remove unnecessary pre-installed applications

## 📝 Logging

All operations are automatically logged to `Logs\Toolkit.log` with:
- Timestamp for each operation
- Success/failure status
- Detailed error messages
- User actions and system responses

Log format:
```
[2024-01-15 14:30:25][INFO] Started: SFC /SCANNOW
[2024-01-15 14:35:12][INFO] Completed: SFC /SCANNOW
[2024-01-15 14:36:45][WARN] Not elevated. Relaunching as admin...
```

## 🔐 Security Considerations

- **Administrator Privileges**: Required for system-level operations
- **Auto-Elevation**: Safely requests admin rights when needed
- **Execution Policy**: Bypasses PowerShell restrictions temporarily
- **Source Verification**: Downloads from official sources only
- **Logging**: All actions are logged for audit trails

## 🤝 Contributing

This toolkit is developed by JKagiDesigns LLC. Contributions, bug reports, and feature requests are welcome.

### Development Setup
1. Clone the repository
2. Ensure PowerShell 5.1+ is installed
3. Test changes in isolated environment
4. Verify admin elevation works correctly
5. Update documentation for new features

## ⚠️ Important Notes

- **Internet Connection**: Some features require internet access (driver updates, package installation)
- **Reboot Requirements**: Some operations may require system restart
- **Backup Recommendation**: Create system restore point before major changes
- **Antivirus**: Some antivirus software may flag PowerShell execution
- **USB Friendly**: Designed to run from portable drives

## 🐛 Troubleshooting

### Common Issues

**"Execution Policy Restriction"**
```powershell
Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process
```

**"Access Denied" Errors**
- Ensure running as administrator
- Check antivirus blocking PowerShell
- Verify file permissions

**"Module Not Found" Errors**
- Ensure all three .ps1 files are in same directory
- Check file paths for special characters
- Verify files aren't corrupted

**Network Tools Not Working**
- Check internet connectivity
- Verify Windows firewall settings
- Test with different DNS servers

## 📞 Support

- **Author**: ChatGPT for Josh (JKagiDesigns / Cultivatronics)
- **Purpose**: USB-friendly Windows 11 troubleshooting and setup
- **License**: Proprietary - JKagiDesigns LLC

## 🔄 Version History

### Current Features
- Tabbed WinForms GUI interface
- Comprehensive system diagnostics
- Advanced application management
- Driver detection and management
- Privacy and customization tools
- Automated logging and reporting

### Future Enhancements
- Additional package managers support
- Enhanced driver installation automation
- More customization options
- Scheduled maintenance tasks
- Integration with cloud storage for reports

---

*This toolkit is designed for IT professionals and advanced users. Always test in a safe environment before deploying to production systems.*
