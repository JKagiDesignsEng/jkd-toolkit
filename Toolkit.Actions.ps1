#region ----- Actions -----
function Get-SystemInfo {
  Write-Log 'Collecting system info'
  $os   = Get-CimInstance Win32_OperatingSystem
  $cs   = Get-CimInstance Win32_ComputerSystem
  $cpu  = Get-CimInstance Win32_Processor | Select-Object -First 1
  $ramGB= [math]::Round($cs.TotalPhysicalMemory/1GB,2)
  $gpu  = Get-CimInstance Win32_VideoController | Select-Object -First 1
  $ip   = (Get-NetIPAddress -AddressFamily IPv4 -PrefixOrigin Dhcp -ErrorAction SilentlyContinue | Where-Object {$_.IPAddress -ne '127.0.0.1'} | Select-Object -ExpandProperty IPAddress -First 1)
  [PSCustomObject]@{
    ComputerName = $env:COMPUTERNAME
    User         = $env:USERNAME
    OS           = "$($os.Caption) $($os.Version)"
    InstallDate  = if ($os.InstallDate -is [string]) { ([datetime]::Parse($os.InstallDate)).ToString('yyyy-MM-dd') } else { $os.InstallDate.ToString('yyyy-MM-dd') }
    UptimeDays   = if ($os.LastBootUpTime -is [string]) { [math]::Round(((Get-Date) - ([Management.ManagementDateTimeConverter]::ToDateTime($os.LastBootUpTime))).TotalDays,1) } else { [math]::Round(((Get-Date) - $os.LastBootUpTime).TotalDays,1) }
    CPU          = $cpu.Name
    RAM_GB       = $ramGB
    GPU          = $gpu.Name
    IP           = $ip
    Domain       = $cs.Domain
    Chassis      = $cs.Model
  }
}

function Export-SystemReport {
  $report = Get-SystemInfo | ConvertTo-Json -Depth 3
  $path = Join-Path $OutDir ("SystemReport_" + (Get-Date -Format 'yyyyMMdd_HHmmss') + '.json')
  $report | Set-Content -Encoding UTF8 -Path $path
  Write-Log "Exported System Report to $path"
  return $path
}

function Invoke-SFC {
  Invoke-CommandLogged -ActionName 'SFC /SCANNOW' -ScriptBlock {
    Start-Process -FilePath 'sfc.exe' -ArgumentList '/scannow' -Wait -NoNewWindow
  }
}

function Invoke-DISM {
  Invoke-CommandLogged -ActionName 'DISM /RestoreHealth' -ScriptBlock {
    Start-Process -FilePath 'dism.exe' -ArgumentList '/Online /Cleanup-Image /RestoreHealth' -Wait -NoNewWindow
  }
}

function Reset-WindowsUpdateCache {
  Invoke-CommandLogged -ActionName 'Reset Windows Update cache' -ScriptBlock {
    net stop wuauserv | Out-Null
    net stop cryptSvc  | Out-Null
    net stop bits      | Out-Null
    net stop msiserver | Out-Null
    Remove-Item -Path "$env:SystemRoot\SoftwareDistribution" -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -Path "$env:SystemRoot\System32\catroot2" -Recurse -Force -ErrorAction SilentlyContinue
    net start wuauserv | Out-Null
    net start cryptSvc  | Out-Null
    net start bits      | Out-Null
    net start msiserver | Out-Null
  }
}

function Restart-PrintSpooler {
  Invoke-CommandLogged -ActionName 'Restart Print Spooler' -ScriptBlock {
    Stop-Service -Name Spooler -Force -ErrorAction SilentlyContinue
    Start-Service -Name Spooler
  }
}

function Clear-DnsCache { Invoke-CommandLogged { ipconfig /flushdns | Out-Null } -ActionName 'Flush DNS' }
function Update-IpAddress  { Invoke-CommandLogged { ipconfig /release; ipconfig /renew } -ActionName 'Release/Renew IP' }

function Reset-NetworkStack {
  Invoke-CommandLogged -ActionName 'Network Stack Reset' -ScriptBlock {
    netsh winsock reset | Out-Null
    netsh int ip reset | Out-Null
  }
  Show-ToolkitToast 'Network stack reset complete. A reboot is recommended.' 'Network Reset' 'Information'
}

function Test-Connectivity {
  $result = [ordered]@{}
  try {
    $r = Invoke-WebRequest -Uri 'http://www.msftconnecttest.com/connecttest.txt' -UseBasicParsing -TimeoutSec 8
    $result['HTTP Test'] = if ($r.Content -match 'Microsoft') { 'OK' } else { 'Unexpected content' }
  } catch { $result['HTTP Test'] = 'Failed' }
  try {
    $p = Test-Connection 1.1.1.1 -Count 2 -Quiet -ErrorAction Stop
    if ($p) { $result['Ping 1.1.1.1'] = 'OK' } else { $result['Ping 1.1.1.1'] = 'Fail' }
  } catch { $result['Ping 1.1.1.1'] = 'Fail' }
  try {
    $p = Test-Connection 8.8.8.8 -Count 2 -Quiet -ErrorAction Stop
    if ($p) { $result['Ping 8.8.8.8'] = 'OK' } else { $result['Ping 8.8.8.8'] = 'Fail' }
  } catch { $result['Ping 8.8.8.8'] = 'Fail' }
  return [PSCustomObject]$result
}

function Test-HostPing {
  param([string]$TargetHost)
  try { 
    $results = Test-Connection -ComputerName $TargetHost -Count 4 -ErrorAction Stop
    if ($results) {
      $results | Select-Object @{Name='Target';Expression={$TargetHost}}, @{Name='Status';Expression={'Success'}}, @{Name='ResponseTime';Expression={"$($_.ResponseTime)ms"}}, @{Name='IPAddress';Expression={$_.IPV4Address}}
    } else {
      @([PSCustomObject]@{ Target = $TargetHost; Status = 'No Response'; ResponseTime = 'N/A'; IPAddress = 'N/A' })
    }
  }
  catch { 
    Write-Log "Ping failed: $TargetHost - $($_.Exception.Message)" 'WARN'
    @([PSCustomObject]@{ Target = $TargetHost; Status = 'Failed'; ResponseTime = 'N/A'; IPAddress = $_.Exception.Message })
  }
}

function Clear-TempFiles {
  Invoke-CommandLogged -ActionName 'Clear Temp Folders' -ScriptBlock {
    $paths = @($env:TEMP, "$env:WINDIR\Temp") | Sort-Object -Unique
    foreach ($p in $paths) {
      Get-ChildItem -Path $p -Recurse -Force -ErrorAction SilentlyContinue | Remove-Item -Force -Recurse -ErrorAction SilentlyContinue
    }
  }
}

function Checkpoint-SystemRestore {
  Invoke-CommandLogged -ActionName 'Create Restore Point' -ScriptBlock {
    Enable-ComputerRestore -Drive 'C:' -ErrorAction SilentlyContinue
    Checkpoint-Computer -Description "Win11 Toolkit $(Get-Date -Format 'yyyyMMdd_HHmm')" -RestorePointType 'MODIFY_SETTINGS'
  }
}

function Export-InstalledPrograms {
  $keys = @(
    'HKLM:SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
    'HKLM:SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall',
    'HKCU:SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall'
  )
  $list = foreach ($k in $keys) {
    if (Test-Path $k) {
      Get-ChildItem $k | ForEach-Object {
        $d = Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue
        if ($d.DisplayName) {
          [PSCustomObject]@{
            Name        = $d.DisplayName
            Version     = $d.DisplayVersion
            Publisher   = $d.Publisher
            InstallDate = $d.InstallDate
            Uninstall   = $d.UninstallString
          }
        }
      }
    }
  }
  $path = Join-Path $OutDir ("InstalledPrograms_" + (Get-Date -Format 'yyyyMMdd_HHmmss') + '.csv')
  $list | Sort-Object Name | Export-Csv -NoTypeInformation -Encoding UTF8 -Path $path
  Write-Log "Exported installed programs to $path"
  return $path
}

function Export-DriverInventory {
  $path = Join-Path $OutDir ("Drivers_" + (Get-Date -Format 'yyyyMMdd_HHmmss') + '.txt')
  pnputil /enum-drivers | Out-File -FilePath $path -Encoding UTF8
  Write-Log "Exported driver inventory to $path"
  return $path
}

function Reset-WindowsFirewall {
  Invoke-CommandLogged -ActionName 'Reset Windows Firewall' -ScriptBlock { netsh advfirewall reset | Out-Null }
}

# Setup and Installation Functions
function Install-BasicDrivers {
  Invoke-CommandLogged -ActionName 'Install Basic Drivers' -ScriptBlock {
    Write-Log "Starting basic driver installation..."
    # Update Windows to get latest drivers
    Start-Process -FilePath 'ms-settings:windowsupdate' -Wait:$false
    # Run Windows Update driver search
    $updateSession = New-Object -ComObject Microsoft.Update.Session
    $updateSearcher = $updateSession.CreateUpdateSearcher()
    $searchResult = $updateSearcher.Search("IsInstalled=0 and Type='Driver'")
    if ($searchResult.Updates.Count -gt 0) {
      Write-Log "Found $($searchResult.Updates.Count) driver updates"
    } else {
      Write-Log "No driver updates found"
    }
  }
}

function Test-PackageManager {
  param([string]$Manager)
  switch ($Manager) {
    'winget' { 
      try { winget --version | Out-Null; return $true } catch { return $false }
    }
    'choco' { 
      try { choco --version | Out-Null; return $true } catch { return $false }
    }
  }
  return $false
}

function Install-PackageManager {
  param([string]$Manager)
  switch ($Manager) {
    'winget' {
      Invoke-CommandLogged -ActionName 'Install WinGet' -ScriptBlock {
        # WinGet should be included in Windows 11, but check if update needed
        if (!(Test-PackageManager 'winget')) {
          Write-Log "WinGet not found. Please install from Microsoft Store or Windows Features."
        }
      }
    }
    'choco' {
      Invoke-CommandLogged -ActionName 'Install Chocolatey' -ScriptBlock {
        Set-ExecutionPolicy Bypass -Scope Process -Force
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
        Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
      }
    }
  }
}

function Uninstall-PackageManager {
  param([string]$Manager)
  switch ($Manager) {
    'winget' {
      Invoke-CommandLogged -ActionName 'Uninstall WinGet' -ScriptBlock {
        # WinGet is part of Windows 11, so we can't truly uninstall it
        # But we can disable it or clear its cache
        Write-Log "WinGet is built into Windows 11 and cannot be completely removed."
        # Clear WinGet cache and settings
        if (Test-Path "$env:LOCALAPPDATA\Packages\Microsoft.DesktopAppInstaller_8wekyb3d8bbwe") {
          Remove-Item "$env:LOCALAPPDATA\Packages\Microsoft.DesktopAppInstaller_8wekyb3d8bbwe\LocalState" -Recurse -Force -ErrorAction SilentlyContinue
        }
      }
    }
    'choco' {
      Invoke-CommandLogged -ActionName 'Uninstall Chocolatey' -ScriptBlock {
        # Remove Chocolatey
        $chocoPath = "$env:ProgramData\chocolatey"
        if (Test-Path $chocoPath) {
          Remove-Item $chocoPath -Recurse -Force
        }
        
        # Remove from PATH
        $pathItems = [Environment]::GetEnvironmentVariable('PATH', 'Machine') -split ';'
        $newPath = ($pathItems | Where-Object { $_ -notlike '*chocolatey*' }) -join ';'
        [Environment]::SetEnvironmentVariable('PATH', $newPath, 'Machine')
        
        # Remove Chocolatey from current session PATH
        $env:PATH = [System.Environment]::GetEnvironmentVariable("PATH", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("PATH", "User")
        
        Write-Log "Chocolatey has been uninstalled."
      }
    }
  }
}

function Install-Application {
  param(
    [string]$AppName,
    [string]$PackageManager = 'winget',
    [string]$DisplayName = $null  # Optional display name for logging
  )
  
  # Check if AppName is a known application name (legacy support) or direct package ID
  $packages = @{
    'Steam' = @{ winget = 'Valve.Steam'; choco = 'steam' }
    'VSCode' = @{ winget = 'Microsoft.VisualStudioCode'; choco = 'vscode' }
    'OnlyOffice' = @{ winget = 'ONLYOFFICE.DesktopEditors'; choco = 'onlyoffice' }
    'Adobe Reader' = @{ winget = 'Adobe.Acrobat.Reader.64-bit'; choco = 'adobereader' }
    'Firefox' = @{ winget = 'Mozilla.Firefox'; choco = 'firefox' }
    'Chrome' = @{ winget = 'Google.Chrome'; choco = 'googlechrome' }
    'Brave' = @{ winget = 'Brave.Brave'; choco = 'brave' }
    '7-Zip' = @{ winget = '7zip.7zip'; choco = '7zip' }
    'VLC' = @{ winget = 'VideoLAN.VLC'; choco = 'vlc' }
    'Discord' = @{ winget = 'Discord.Discord'; choco = 'discord' }
  }
  
  $packageId = $AppName
  $appDisplayName = if ($DisplayName) { $DisplayName } else { $AppName }
  
  # If it's a known application name, get the package ID
  if ($packages.ContainsKey($AppName)) {
    $packageId = $packages[$AppName][$PackageManager]
    if (-not $packageId) {
      Write-Log "No $PackageManager package found for $AppName" 'ERROR'
      return $false
    }
    $appDisplayName = $AppName
  }
  
  if (-not (Test-PackageManager $PackageManager)) {
    Write-Log "Installing $PackageManager first..."
    Install-PackageManager $PackageManager
    # Refresh PATH
    $env:PATH = [System.Environment]::GetEnvironmentVariable("PATH", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("PATH", "User")
  }
  
  Invoke-CommandLogged -ActionName "Install $appDisplayName via $PackageManager" -ScriptBlock {
    switch ($PackageManager) {
      'winget' {
        winget install --id $packageId --silent --accept-package-agreements --accept-source-agreements
      }
      'choco' {
        choco install $packageId -y
      }
    }
  }
}

function Install-WindowsFeatures {
  Invoke-CommandLogged -ActionName 'Install Common Windows Features' -ScriptBlock {
    # Install common useful Windows features
    $features = @(
      'Microsoft-Windows-Subsystem-Linux',
      'VirtualMachinePlatform',
      'Microsoft-Hyper-V-All'
    )
    
    foreach ($feature in $features) {
      try {
        dism /online /enable-feature /featurename:$feature /all /norestart
        Write-Log "Enabled feature: $feature"
      } catch {
        Write-Log "Failed to enable feature: $feature - $($_.Exception.Message)" 'WARN'
      }
    }
  }
}

function Optimize-WindowsPerformance {
  Invoke-CommandLogged -ActionName 'Optimize Windows Performance' -ScriptBlock {
    # Disable unnecessary services and features for better performance
    $services = @('Fax', 'WSearch', 'TabletInputService')
    foreach ($service in $services) {
      try {
        Set-Service -Name $service -StartupType Disabled -ErrorAction SilentlyContinue
        Write-Log "Disabled service: $service"
      } catch {
        Write-Log "Could not disable service: $service" 'WARN'
      }
    }
    
    # Set power plan to High Performance
    powercfg /setactive 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c
    Write-Log "Set power plan to High Performance"
  }
}

function Start-SystemTool {
  param([ValidateSet('DeviceManager','EventViewer','Services','TaskManager','WindowsUpdate','StartupApps')][string]$Tool)
  switch ($Tool) {
    'DeviceManager' { Start-Process devmgmt.msc }
    'EventViewer'   { Start-Process eventvwr.msc }
    'Services'      { Start-Process services.msc }
    'TaskManager'   { Start-Process taskmgr.exe }
    'WindowsUpdate' { Start-Process 'ms-settings:windowsupdate' }
    'StartupApps'   { Start-Process 'ms-settings:startupapps' }
  }
}

# Uninstall Functions
function Get-InstalledApplications {
  # Get installed programs from multiple sources for comprehensive list
  $results = @()
  
  # WinGet installed apps
  try {
    if (Test-PackageManager 'winget') {
      Write-Log "Getting WinGet installed applications..."
      $wingetOutput = winget list | Out-String
      $lines = $wingetOutput -split "`n" | Where-Object { $_ -and $_ -notmatch '^-+$' -and $_ -notmatch 'Name\s+Id\s+Version' }
      
      foreach ($line in $lines) {
        # Skip header and separator lines
        if ($line -match '^Name\s+Id\s+Version' -or $line -match '^-+' -or [string]::IsNullOrWhiteSpace($line)) {
          continue
        }
        
        # Parse WinGet output format more carefully
        # WinGet format can vary, but typically: Name    Id    Version    Available    Source
        # Sometimes the Name field contains the ID mixed in, so we need to clean it
        
        # Try to parse with standard format first
        if ($line -match '^(.+?)\s{3,}([A-Za-z0-9][A-Za-z0-9\.\-_\\]+)\s{2,}(.+?)(?:\s{2,}(.+?))?(?:\s{2,}(.+?))?$') {
          $name = $matches[1].Trim()
          $id = $matches[2].Trim()
          $version = $matches[3].Trim()
          
          # Clean up the name field - remove any ID info that got mixed in
          # Remove ARP paths, Steam App IDs, etc.
          $cleanName = $name -replace '\s+ARP\\.*$', '' -replace '\s+Steam App \d+.*$', '' -replace '\s{2,}.*$', ''
          $cleanName = $cleanName.Trim()
          
          # Only add if we have a valid clean name
          if ($cleanName -and $cleanName.Length -gt 0) {
            $wingetApp = [PSCustomObject]@{
              Name = $cleanName
              Id = $id
              Version = $version
              Source = 'WinGet'
              Publisher = 'Unknown'
              UninstallMethod = 'winget'
            }
            $results += $wingetApp
          }
        }
      }
    }
  } catch {
    Write-Log "Error getting WinGet apps: $($_.Exception.Message)" 'WARN'
  }
  
  # Registry-based installed programs
  $regKeys = @(
    'HKLM:SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
    'HKLM:SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall',
    'HKCU:SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall'
  )
  
  foreach ($key in $regKeys) {
    if (Test-Path $key) {
      Get-ChildItem $key | ForEach-Object {
        $app = Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue
        if ($app.DisplayName -and $app.UninstallString) {
          $results += [PSCustomObject]@{
            Name = $app.DisplayName
            Id = $app.PSChildName
            Version = $app.DisplayVersion
            Source = 'Registry'
            Publisher = if ($app.Publisher) { $app.Publisher } else { 'Unknown' }
            UninstallMethod = 'registry'
            UninstallString = $app.UninstallString
            QuietUninstallString = $app.QuietUninstallString
          }
        }
      }
    }
  }
  
  # Advanced deduplication - prefer WinGet over Registry entries
  Write-Log "Deduplicating application list (preferring WinGet over Registry)"
  
  # Function to normalize app names for comparison
  function Get-NormalizedName {
    param([string]$name)
    if (-not $name) { return "" }
    
    # Handle encoding issues and truncation - only remove if at word boundaries
    $normalized = $name -replace 'ΓÇª$', ''  # Remove truncation marker at end only
    $normalized = $normalized -replace '…$', ''  # Remove ellipsis at end only
    $normalized = $normalized -replace '\u2026$', ''  # Remove Unicode ellipsis at end only
    $normalized = $normalized -replace 'â€¦$', ''  # Remove UTF-8 encoded ellipsis at end only
    
    # Remove common suffixes and prefixes that might cause mismatches
    $normalized = $normalized -replace '\s*\(.*?\)\s*$', ''  # Remove parentheses at end
    $normalized = $normalized -replace '\s*\[.*?\]\s*$', ''  # Remove brackets at end
    $normalized = $normalized -replace '^\s*Microsoft\s+', ''  # Remove Microsoft prefix
    
    # Remove extra whitespace and normalize case (keep alphanumeric and spaces)
    $normalized = $normalized -replace '\s+', ' '  # Multiple spaces to single
    $normalized = $normalized -replace '[^a-zA-Z0-9\s]', ''  # Remove special chars but keep letters, numbers, spaces
    $normalized = $normalized -replace '^\s+|\s+$', ''  # Trim whitespace
    return $normalized.Trim().ToLower() -replace '\s', ''
  }
  
  # Process apps and deduplicate
  $processedApps = @{}
  $finalResults = @()
  
  foreach ($app in $results) {
    $normalizedName = Get-NormalizedName $app.Name
    
    # Skip apps with empty normalized names
    if ([string]::IsNullOrEmpty($normalizedName)) {
      Write-Log "Skipping app with empty normalized name: '$($app.Name)'"
      continue
    }
    
    if ($processedApps.ContainsKey($normalizedName)) {
      # Exact match found
      $existingApp = $processedApps[$normalizedName]
      
      Write-Log "Duplicate detected: '$($app.Name)' ($($app.Source)) vs '$($existingApp.Name)' ($($existingApp.Source))"
      
      if ($app.Source -eq 'WinGet' -and $existingApp.Source -eq 'Registry') {
        # Replace Registry with WinGet
        Write-Log "Replacing Registry entry '$($existingApp.Name)' with WinGet entry '$($app.Name)'"
        
        # Enhance WinGet with Registry publisher if needed
        if ($app.Publisher -eq 'Unknown' -and $existingApp.Publisher -ne 'Unknown') {
          $app.Publisher = $existingApp.Publisher
          Write-Log "Enhanced WinGet entry with Registry publisher: $($existingApp.Publisher)"
        }
        
        $processedApps[$normalizedName] = $app
      } elseif ($app.Source -eq 'Registry' -and $existingApp.Source -eq 'WinGet') {
        # Keep WinGet, but enhance with Registry info if useful
        Write-Log "Keeping WinGet entry '$($existingApp.Name)' over Registry entry '$($app.Name)'"
        
        if ($existingApp.Publisher -eq 'Unknown' -and $app.Publisher -ne 'Unknown') {
          $existingApp.Publisher = $app.Publisher
          Write-Log "Enhanced existing WinGet entry with Registry publisher: $($app.Publisher)"
        }
        # Keep existing WinGet entry
      } else {
        # Both same source - keep first one
        Write-Log "Both entries same source, keeping first: '$($existingApp.Name)'"
      }
    } else {
      # Check for fuzzy matches (truncation cases)
      $foundTruncatedMatch = $false
      foreach ($existingNormalized in $processedApps.Keys) {
        # Check if one is a substring of the other (indicating potential truncation)
        if (($normalizedName.Length -ge 10 -and $existingNormalized.Length -ge 10) -and 
            (($normalizedName.StartsWith($existingNormalized) -and $normalizedName.Length - $existingNormalized.Length -le 8) -or
             ($existingNormalized.StartsWith($normalizedName) -and $existingNormalized.Length - $normalizedName.Length -le 8))) {
          
          $existingApp = $processedApps[$existingNormalized]
          Write-Log "Truncation match detected: '$($app.Name)' ($($app.Source)) vs '$($existingApp.Name)' ($($existingApp.Source))"
          
          # Prefer the longer, more complete name
          if ($normalizedName.Length -gt $existingNormalized.Length) {
            Write-Log "Replacing truncated entry '$($existingApp.Name)' with fuller entry '$($app.Name)'"
            $processedApps.Remove($existingNormalized)
            $processedApps[$normalizedName] = $app
          } else {
            Write-Log "Keeping fuller entry '$($existingApp.Name)' over truncated '$($app.Name)'"
          }
          $foundTruncatedMatch = $true
          break
        }
      }
      
      if (-not $foundTruncatedMatch) {
        # First occurrence of this app
        $processedApps[$normalizedName] = $app
      }
    }
  }
  
  $finalResults = $processedApps.Values
  
  Write-Log "Application deduplication complete: $($results.Count) → $($finalResults.Count) entries"
  return $finalResults | Sort-Object Name
}

function Uninstall-Application {
  param(
    [Parameter(Mandatory)]
    [PSCustomObject]$Application,
    [switch]$Silent = $true
  )
  
  $appName = $Application.Name
  Write-Log "Starting uninstall for: $appName"
  
  try {
    switch ($Application.UninstallMethod) {
      'winget' {
        if (Test-PackageManager 'winget') {
          # Use exact match to prevent multiple package issues
          $args = @('uninstall', '--exact', '--id', $Application.Id)
          if ($Silent) { $args += '--silent' }
          $args += '--accept-source-agreements'
          
          Write-Log "Executing: winget $($args -join ' ')"
          $process = Start-Process 'winget' -ArgumentList $args -Wait -PassThru -NoNewWindow -WindowStyle Hidden
          
          if ($process.ExitCode -eq 0) {
            Write-Log "Successfully uninstalled $appName via WinGet"
            return $true
          } elseif ($process.ExitCode -eq -1978335189) {
            # Package not found - might have been uninstalled already
            Write-Log "Package $appName not found (may already be uninstalled)" 'WARN'
            return $true
          } else {
            Write-Log "WinGet uninstall failed for $appName (Exit code: $($process.ExitCode))" 'ERROR'
            return $false
          }
        }
      }
      'registry' {
        $uninstallString = if ($Silent -and $Application.QuietUninstallString) { 
          $Application.QuietUninstallString 
        } else { 
          $Application.UninstallString 
        }
        
        if ($uninstallString) {
          # Parse the uninstall string
          if ($uninstallString -match '^"([^"]+)"\s*(.*)$') {
            $executable = $matches[1]
            $arguments = $matches[2].Trim()
          } elseif ($uninstallString -match '^([^\s]+)\s*(.*)$') {
            $executable = $matches[1]
            $arguments = $matches[2].Trim()
          } else {
            $executable = $uninstallString
            $arguments = ''
          }
          
          # Add silent flags for common installers
          if ($Silent) {
            if ($arguments -notmatch '/S|/silent|/quiet|-quiet|-silent') {
              if ($executable -match 'msiexec') {
                $arguments += ' /quiet /norestart'
              } elseif ($executable -match 'unins.*\.exe') {
                $arguments += ' /SILENT'
              } else {
                $arguments += ' /S'
              }
            }
          }
          
          Write-Log "Executing: $executable $arguments"
          $process = Start-Process -FilePath $executable -ArgumentList $arguments -Wait -PassThru -NoNewWindow
          if ($process.ExitCode -eq 0 -or $process.ExitCode -eq 3010) { # 3010 = reboot required
            Write-Log "Successfully uninstalled $appName via registry"
            return $true
          } else {
            Write-Log "Registry uninstall failed for $appName (Exit code: $($process.ExitCode))" 'ERROR'
            return $false
          }
        }
      }
    }
    return $false
  } catch {
    Write-Log "Error uninstalling $appName`: $($_.Exception.Message)" 'ERROR'
    return $false
  }
}

function Search-PackageManager {
  param(
    [Parameter(Mandatory)]
    [string]$SearchTerm,
    [Parameter(Mandatory)]
    [ValidateSet('winget', 'choco')]
    [string]$PackageManager
  )
  
  Write-Log "Searching $PackageManager for '$SearchTerm'"
  
  try {
    if ($PackageManager -eq 'winget') {
      # Search WinGet
      $output = & winget search $SearchTerm --accept-source-agreements | Out-String
      $lines = $output -split "`n" | Where-Object { $_ -and $_ -notmatch '^-+$' -and $_ -notmatch 'Name\s+Id\s+Version' -and $_ -notmatch 'No package found' }
      
      $results = @()
      foreach ($line in $lines) {
        # Skip header and separator lines
        if ($line -match '^Name\s+Id\s+Version' -or $line -match '^-+' -or [string]::IsNullOrWhiteSpace($line)) {
          continue
        }
        
        # Parse WinGet output format: Name    Id    Version    Source
        if ($line -match '^(.+?)\s{2,}(.+?)\s{2,}(.+?)\s{2,}(.+?)$') {
          $results += [PSCustomObject]@{
            Name = $matches[1].Trim()
            Id = $matches[2].Trim()
            Version = $matches[3].Trim()
            Source = $matches[4].Trim()
            Description = ''
          }
        } elseif ($line -match '^(.+?)\s{2,}(.+?)\s{2,}(.+?)$') {
          # Sometimes source is missing
          $results += [PSCustomObject]@{
            Name = $matches[1].Trim()
            Id = $matches[2].Trim()
            Version = $matches[3].Trim()
            Source = 'winget'
            Description = ''
          }
        }
      }
    } else {
      # Search Chocolatey
      $output = & choco search $SearchTerm --limit-output | Out-String
      $lines = $output -split "`n" | Where-Object { $_ -and $_ -notmatch '^Chocolatey' }
      
      $results = @()
      foreach ($line in $lines) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        
        # Parse Chocolatey output format: packagename|version
        $parts = $line -split '\|'
        if ($parts.Count -ge 2) {
          $results += [PSCustomObject]@{
            Name = $parts[0].Trim()
            Id = $parts[0].Trim()
            Version = $parts[1].Trim()
            Source = 'chocolatey'
            Description = if ($parts.Count -gt 2) { $parts[2].Trim() } else { '' }
          }
        }
      }
    }
    
    Write-Log "Found $($results.Count) packages for '$SearchTerm' in $PackageManager"
    return $results | Select-Object -First 20  # Limit to top 20 results
    
  } catch {
    Write-Log "Error searching $PackageManager`: $($_.Exception.Message)" 'ERROR'
    throw
  }
}

function Uninstall-SelectedApplications {
  param(
    [Parameter(Mandatory)]
    [PSCustomObject[]]$Applications,
    [switch]$Silent = $true
  )
  
  $successCount = 0
  $failCount = 0
  
  foreach ($app in $Applications) {
    Write-Log "Uninstalling: $($app.Name)"
    if (Uninstall-Application -Application $app -Silent:$Silent) {
      $successCount++
    } else {
      $failCount++
    }
  }
  
  Write-Log "Uninstall complete. Success: $successCount, Failed: $failCount"
  return @{
    Success = $successCount
    Failed = $failCount
    Total = $Applications.Count
  }
}

function Start-PrivacyTool {
  param(
    [Parameter(Mandatory)]
    [ValidateSet('ShutUp10', 'PrivacyFix', 'Debloat')]
    [string]$Tool
  )
  
  Write-Log "Starting privacy tool: $Tool"
  
  try {
    switch ($Tool) {
      'ShutUp10' {
        # Download and run O&O ShutUp10++
        $url = 'https://dl5.oo-software.com/files/ooshutup10/OOSU10.exe'
        $downloadPath = Join-Path $env:TEMP 'OOSU10.exe'
        
        Write-Log "Downloading O&O ShutUp10++ from $url"
        Invoke-WebRequest -Uri $url -OutFile $downloadPath -UseBasicParsing
        
        if (Test-Path $downloadPath) {
          Write-Log "Launching O&O ShutUp10++"
          Start-Process -FilePath $downloadPath -Wait
          Remove-Item $downloadPath -Force -ErrorAction SilentlyContinue
          Show-ToolkitToast 'O&O ShutUp10++ has been launched. Configure your privacy settings as needed.' 'Privacy Tool Ready'
        }
      }
      
      'PrivacyFix' {
        # Apply basic privacy fixes
        Write-Log "Applying Windows privacy fixes"
        
        # Disable telemetry
        Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection" -Name "AllowTelemetry" -Value 0 -Force -ErrorAction SilentlyContinue
        
        # Disable advertising ID
        if (-not (Test-Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AdvertisingInfo")) {
          New-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AdvertisingInfo" -Force | Out-Null
        }
        Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AdvertisingInfo" -Name "DisabledByGroupPolicy" -Value 1 -Force
        
        # Disable location tracking
        if (-not (Test-Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\LocationAndSensors")) {
          New-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\LocationAndSensors" -Force | Out-Null
        }
        Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\LocationAndSensors" -Name "DisableLocation" -Value 1 -Force
        
        # Disable feedback requests
        if (-not (Test-Path "HKCU:\SOFTWARE\Microsoft\Siuf\Rules")) {
          New-Item -Path "HKCU:\SOFTWARE\Microsoft\Siuf\Rules" -Force | Out-Null
        }
        Set-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Siuf\Rules" -Name "NumberOfSIUFInPeriod" -Value 0 -Force
        
        # Disable Cortana
        if (-not (Test-Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search")) {
          New-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search" -Force | Out-Null
        }
        Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search" -Name "AllowCortana" -Value 0 -Force
        
        Write-Log "Privacy fixes applied successfully"
      }
      
      'Debloat' {
        # Remove common bloatware
        Write-Log "Starting Windows debloating process"
        
        $bloatwarePackages = @(
          "Microsoft.BingNews",
          "Microsoft.BingWeather", 
          "Microsoft.GetHelp",
          "Microsoft.Getstarted",
          "Microsoft.Messaging",
          "Microsoft.Microsoft3DViewer",
          "Microsoft.MicrosoftOfficeHub",
          "Microsoft.MicrosoftSolitaireCollection",
          "Microsoft.MixedReality.Portal",
          "Microsoft.Office.OneNote",
          "Microsoft.People",
          "Microsoft.Print3D",
          "Microsoft.SkypeApp",
          "Microsoft.Wallet",
          "Microsoft.WindowsCamera",
          "microsoft.windowscommunicationsapps",
          "Microsoft.WindowsFeedbackHub",
          "Microsoft.WindowsMaps",
          "Microsoft.WindowsSoundRecorder",
          "Microsoft.Xbox.TCUI",
          "Microsoft.XboxApp",
          "Microsoft.XboxGameOverlay",
          "Microsoft.XboxGamingOverlay",
          "Microsoft.XboxIdentityProvider",
          "Microsoft.XboxSpeechToTextOverlay",
          "Microsoft.YourPhone",
          "Microsoft.ZuneMusic",
          "Microsoft.ZuneVideo"
        )
        
        $removedCount = 0
        foreach ($package in $bloatwarePackages) {
          try {
            $installedPackage = Get-AppxPackage -Name $package -AllUsers -ErrorAction SilentlyContinue
            if ($installedPackage) {
              Write-Log "Removing package: $package"
              Remove-AppxPackage -Package $installedPackage.PackageFullName -ErrorAction SilentlyContinue
              $removedCount++
            }
          } catch {
            Write-Log "Failed to remove $package`: $($_.Exception.Message)" 'WARN'
          }
        }
        
        Write-Log "Debloating complete. Removed $removedCount packages"
      }
    }
  } catch {
    Write-Log "Error running privacy tool $Tool`: $($_.Exception.Message)" 'ERROR'
    Show-ToolkitToast "Error running $Tool`: $($_.Exception.Message)" 'Error'
  }
}

function Start-CustomizationTool {
  param(
    [Parameter(Mandatory)]
    [ValidateSet('DarkMode', 'WSL', 'Wallpaper')]
    [string]$Tool
  )
  
  Write-Log "Starting customization tool: $Tool"
  
  try {
    switch ($Tool) {
      'DarkMode' {
        # Toggle Windows Dark Mode
        $currentTheme = Get-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize" -Name "AppsUseLightTheme" -ErrorAction SilentlyContinue
        
        if ($currentTheme -and $currentTheme.AppsUseLightTheme -eq 0) {
          # Currently Dark Mode, switch to Light Mode
          Write-Log "Switching to Light Mode"
          Set-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize" -Name "AppsUseLightTheme" -Value 1
          Set-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize" -Name "SystemUsesLightTheme" -Value 1
          Show-ToolkitToast 'Switched to Light Mode. Changes will take effect immediately.' 'Theme Changed'
        } else {
          # Currently Light Mode or not set, switch to Dark Mode
          Write-Log "Switching to Dark Mode"
          Set-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize" -Name "AppsUseLightTheme" -Value 0
          Set-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize" -Name "SystemUsesLightTheme" -Value 0
          Show-ToolkitToast 'Switched to Dark Mode. Changes will take effect immediately.' 'Theme Changed'
        }
      }
      
      'WSL' {
        # Install Windows Subsystem for Linux
        Write-Log "Installing Windows Subsystem for Linux (WSL)"
        
        # Check if WSL is already installed
        $wslFeature = Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Windows-Subsystem-Linux -ErrorAction SilentlyContinue
        
        if ($wslFeature -and $wslFeature.State -eq "Enabled") {
          Write-Log "WSL is already installed"
          Show-ToolkitToast 'WSL is already installed on this system. You can install Linux distributions from the Microsoft Store.' 'WSL Already Installed'
        } else {
          # Enable WSL feature
          Write-Log "Enabling WSL feature"
          Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Windows-Subsystem-Linux -All -NoRestart
          
          # Enable Virtual Machine Platform (required for WSL 2)
          Write-Log "Enabling Virtual Machine Platform"
          Enable-WindowsOptionalFeature -Online -FeatureName VirtualMachinePlatform -All -NoRestart
          
          # Install WSL 2 kernel update and set as default
          try {
            Write-Log "Installing WSL 2 kernel update"
            wsl --set-default-version 2 2>$null
          } catch {
            Write-Log "WSL command not available yet - will be available after reboot" 'WARN'
          }
          
          Show-ToolkitToast 'WSL has been installed successfully! Please restart your computer to complete the installation. After restart, you can install Linux distributions from the Microsoft Store.' 'WSL Installation Complete'
        }
      }
      
      'Wallpaper' {
        # Set custom wallpaper
        Write-Log "Opening wallpaper selection dialog"
        
        Add-Type -AssemblyName System.Windows.Forms
        $openFileDialog = New-Object System.Windows.Forms.OpenFileDialog
        $openFileDialog.Title = "Select Wallpaper Image"
        $openFileDialog.Filter = "Image Files|*.jpg;*.jpeg;*.png;*.bmp;*.gif;*.tiff|All Files|*.*"
        $openFileDialog.InitialDirectory = [Environment]::GetFolderPath('MyPictures')
        
        $result = $openFileDialog.ShowDialog()
        
        if ($result -eq [System.Windows.Forms.DialogResult]::OK) {
          $wallpaperPath = $openFileDialog.FileName
          Write-Log "Setting wallpaper to: $wallpaperPath"
          
          # Use Windows API to set wallpaper
          Add-Type -TypeDefinition @"
            using System;
            using System.Runtime.InteropServices;
            public class Wallpaper {
                [DllImport("user32.dll", CharSet = CharSet.Auto)]
                public static extern int SystemParametersInfo(int uAction, int uParam, string lpvParam, int fuWinIni);
                
                public static void SetWallpaper(string path) {
                    SystemParametersInfo(20, 0, path, 3);
                }
            }
"@
          
          [Wallpaper]::SetWallpaper($wallpaperPath)
          
          # Also set wallpaper style to "Fill" for better appearance
          Set-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name "WallpaperStyle" -Value "10"
          Set-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name "TileWallpaper" -Value "0"
          
          Write-Log "Wallpaper set successfully"
          Show-ToolkitToast "Wallpaper has been set successfully!`nPath: $wallpaperPath" 'Wallpaper Changed'
        } else {
          Write-Log "Wallpaper selection cancelled by user"
        }
      }
    }
  } catch {
    Write-Log "Error running customization tool $Tool`: $($_.Exception.Message)" 'ERROR'
    Show-ToolkitToast "Error running $Tool`: $($_.Exception.Message)" 'Error'
  }
}

function Find-MissingDrivers {
  Write-Log "Starting missing driver scan"
  
  try {
    # Check internet connectivity first
    $hasInternet = $false
    try {
      $testConnection = Test-NetConnection -ComputerName "8.8.8.8" -Port 80 -InformationLevel Quiet -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
      $hasInternet = $testConnection
    } catch {
      $hasInternet = $false
    }
    
    # Get all devices with driver issues
    $problemDevices = @()
    $networkDevicesWithIssues = @()
    
    # Get devices with missing drivers (error codes 28, 31, 37, 39, 43)
    $allDevices = Get-CimInstance -ClassName Win32_PnPEntity | Where-Object { 
      $_.ConfigManagerErrorCode -ne 0 -and 
      $_.ConfigManagerErrorCode -in @(28, 31, 37, 39, 43) 
    }
    
    foreach ($device in $allDevices) {
      $errorDescription = switch ($device.ConfigManagerErrorCode) {
        28 { "Drivers not installed" }
        31 { "Device not working properly" }
        37 { "Windows cannot initialize the device driver" }
        39 { "Driver corrupted or missing" }
        43 { "Windows has stopped this device" }
        default { "Unknown driver issue" }
      }
      
      $deviceInfo = [PSCustomObject]@{
        Name = $device.Name
        DeviceID = $device.DeviceID
        ErrorCode = $device.ConfigManagerErrorCode
        ErrorDescription = $errorDescription
        Status = $device.Status
        Manufacturer = $device.Manufacturer
        Service = $device.Service
        IsNetworkDevice = $device.Name -match "Network|Ethernet|Wi-Fi|Wireless|Adapter|NIC" -or $device.DeviceID -match "PCI\\VEN_"
      }
      
      $problemDevices += $deviceInfo
      
      # Track network devices separately
      if ($deviceInfo.IsNetworkDevice) {
        $networkDevicesWithIssues += $deviceInfo
      }
    }
    
    # Also check for unknown devices
    $unknownDevices = Get-CimInstance -ClassName Win32_PnPEntity | Where-Object { 
      $_.Name -like "*Unknown*" -or 
      $_.Name -like "*Other*" -or
      $_.Manufacturer -like "*Unknown*" -or
      $_.Status -eq "Error"
    }
    
    foreach ($device in $unknownDevices) {
      if ($device.DeviceID -notin $problemDevices.DeviceID) {
        $deviceInfo = [PSCustomObject]@{
          Name = $device.Name
          DeviceID = $device.DeviceID
          ErrorCode = if ($device.ConfigManagerErrorCode) { $device.ConfigManagerErrorCode } else { "Unknown" }
          ErrorDescription = "Unknown or unrecognized device"
          Status = $device.Status
          Manufacturer = $device.Manufacturer
          Service = $device.Service
          IsNetworkDevice = $device.Name -match "Network|Ethernet|Wi-Fi|Wireless|Adapter|NIC" -or $device.DeviceID -match "PCI\\VEN_"
        }
        
        $problemDevices += $deviceInfo
        
        if ($deviceInfo.IsNetworkDevice) {
          $networkDevicesWithIssues += $deviceInfo
        }
      }
    }
    
    Write-Log "Found $($problemDevices.Count) devices with driver issues"
    Write-Log "Found $($networkDevicesWithIssues.Count) network devices with issues"
    Write-Log "Internet connectivity: $hasInternet"
    
    if ($problemDevices.Count -eq 0) {
      Show-ToolkitToast "Great news! No missing or problematic drivers were found on your system." 'Driver Scan Complete'
      return
    }
    
    # Create a detailed report
    $reportContent = @"
Missing/Problematic Drivers Report
Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
Computer: $env:COMPUTERNAME
Internet Connection: $(if ($hasInternet) { "Available" } else { "Not Available" })

Found $($problemDevices.Count) device(s) with driver issues:
$(if ($networkDevicesWithIssues.Count -gt 0) { "⚠️  WARNING: $($networkDevicesWithIssues.Count) network device(s) have driver issues!" })

"@
    
    foreach ($device in $problemDevices) {
      $reportContent += @"
Device: $($device.Name)
Manufacturer: $($device.Manufacturer)
Error: $($device.ErrorDescription) (Code: $($device.ErrorCode))
Device ID: $($device.DeviceID)
Status: $($device.Status)
$(if ($device.IsNetworkDevice) { "⚠️  NETWORK DEVICE - Critical for internet connectivity" })
---

"@
    }
    
    if (-not $hasInternet -and $networkDevicesWithIssues.Count -gt 0) {
      $reportContent += @"

🚨 OFFLINE DRIVER INSTALLATION REQUIRED 🚨

Your computer has network driver issues and no internet connection.
You'll need to obtain drivers manually using another computer:

STEP-BY-STEP OFFLINE DRIVER GUIDE:
1. Note your computer's make/model: $(try { (Get-CimInstance Win32_ComputerSystem).Model } catch { "Unknown" })
2. Using another computer with internet:
   - Visit manufacturer's support website
   - Search for your exact computer model
   - Download network/chipset drivers to USB drive
3. Transfer USB drive to this computer
4. Install network drivers first to enable internet
5. Run Windows Update to get remaining drivers

NETWORK DEVICES NEEDING DRIVERS:
"@
      foreach ($netDevice in $networkDevicesWithIssues) {
        $reportContent += "• $($netDevice.Name) - $($netDevice.ErrorDescription)`n"
      }
    }
    
    $reportContent += @"

Recommended Actions:
$(if ($hasInternet) {
"✅ Internet Available - Online Solutions:
1. Use Windows Update to automatically find drivers
2. Visit device manufacturer's website for latest drivers
3. Use Device Manager to update drivers manually"
} else {
"❌ No Internet - Offline Solutions Required:
1. Use another computer to download drivers
2. Focus on network/ethernet drivers first
3. Transfer drivers via USB drive
4. Install network drivers to restore internet access"
})

Note: Always download drivers from official manufacturer websites when possible.
"@
    
    # Save report to desktop
    $reportPath = Join-Path ([Environment]::GetFolderPath('Desktop')) "MissingDrivers_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"
    $reportContent | Out-File -FilePath $reportPath -Encoding UTF8
    
    # Show results with context-appropriate options
    if (-not $hasInternet -and $networkDevicesWithIssues.Count -gt 0) {
      # Offline scenario with network issues
      $message = @"
🚨 CRITICAL: No Internet + Network Driver Issues! 🚨

Found $($problemDevices.Count) device(s) with driver problems, including $($networkDevicesWithIssues.Count) network device(s).

Your computer cannot access the internet due to missing network drivers.

IMMEDIATE ACTIONS NEEDED:
1. Use another computer to download drivers
2. Focus on network/ethernet drivers first  
3. Transfer via USB drive and install manually

Computer Model: $(try { (Get-CimInstance Win32_ComputerSystem).Model } catch { "Unknown" })

Report saved to: $reportPath

Click OK to open Device Manager for manual driver installation.
"@
      
      [System.Windows.Forms.MessageBox]::Show(
        $message,
        'Offline Driver Installation Required',
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Warning
      ) | Out-Null
      
      # Open Device Manager for offline driver installation
      Start-Process devmgmt.msc
      Show-ToolkitToast 'Device Manager opened. Look for network devices with yellow warning icons. Use "Update Driver" > "Browse my computer" to install from USB drive.' 'Offline Driver Mode'
      
    } elseif (-not $hasInternet) {
      # Offline but no network driver issues
      $message = @"
No Internet Connection Detected

Found $($problemDevices.Count) device(s) with driver issues, but network devices appear functional.

Check your network connection:
• Ensure ethernet cable is connected
• Check Wi-Fi settings
• Verify router/modem is working

Report saved to: $reportPath

Click OK to open Network Settings.
"@
      
      [System.Windows.Forms.MessageBox]::Show(
        $message,
        'Network Connection Issue',
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Information
      ) | Out-Null
      
      Start-Process ms-settings:network
      
    } else {
      # Online - normal driver update process
      $message = @"
Driver Scan Complete!

Found $($problemDevices.Count) device(s) with missing or problematic drivers.

Key Issues Found:
"@
      
      $topIssues = $problemDevices | Group-Object ErrorDescription | Sort-Object Count -Descending | Select-Object -First 3
      foreach ($issue in $topIssues) {
        $message += "`n• $($issue.Name): $($issue.Count) device(s)"
      }
      
      $message += @"


Report saved to: $reportPath

Would you like to:
• Run Windows Update to find drivers automatically?
• Open Device Manager to update drivers manually?
"@
      
      $result = [System.Windows.Forms.MessageBox]::Show(
        $message,
        'Missing Drivers Found',
        [System.Windows.Forms.MessageBoxButtons]::YesNoCancel,
        [System.Windows.Forms.MessageBoxIcon]::Information
      )
      
      switch ($result) {
        'Yes' {
          Write-Log "User chose to run Windows Update"
          Start-Process ms-settings:windowsupdate
          Show-ToolkitToast 'Windows Update has been opened. Check for updates to automatically install missing drivers.' 'Windows Update Opened'
        }
        'No' {
          Write-Log "User chose to open Device Manager"
          Start-Process devmgmt.msc
          Show-ToolkitToast 'Device Manager has been opened. Look for devices with yellow warning icons and update their drivers.' 'Device Manager Opened'
        }
        'Cancel' {
          Write-Log "User cancelled driver action"
          Show-ToolkitToast "Driver report saved to desktop for your reference." 'Report Saved'
        }
      }
    }
    
  } catch {
    Write-Log "Error during driver scan: $($_.Exception.Message)" 'ERROR'
    Show-ToolkitToast "Error scanning for drivers: $($_.Exception.Message)" 'Error'
  }
}
#endregion

