<#
Controls\RestoreHealthFromISOControl.ps1

Purpose:
  Provides an alternative RestoreHealth workflow that allows the user to:
    - Download a Windows ISO directly and use it as the DISM source, or
    - Install and run the Media Creation Tool (via winget/choco) to produce an ISO,
      then use that ISO as the DISM source.

Behavior:
  - Prompts the user in the console for which option to use.
  - Downloads via BITS (resume-capable) or falls back to Invoke-WebRequest.
  - Mounts the ISO, selects install.wim or install.esd and uses it as the DISM source
    (WIM: or ESD: syntax), runs DISM RestoreHealth with /LimitAccess, then dismounts.

Notes:
  - This operation requires administrator rights. Ensure the script is elevated.
  - Downloads may be several GB.
#>

function Add-RestoreHealthFromISOButton {
    param(
        [Parameter(Mandatory=$true)][System.Windows.Forms.Control]$Parent,
        [Parameter(Mandatory=$false)][System.Drawing.Point]$Location = $(New-Object System.Drawing.Point(10,40)),
        [Parameter(Mandatory=$false)][System.Drawing.Size]$Size = $(New-Object System.Drawing.Size(160,40))
    )

    $btn = New-Object System.Windows.Forms.Button
    $btn.Text = 'Restore Health (ISO / MediaTool)'
    $btn.Size = $Size
    $btn.Location = $Location
    # Create and attach tooltip describing choices in plain language
    $tt = New-Object System.Windows.Forms.ToolTip
    $tt.AutoPopDelay = 30000
    $tt.InitialDelay = 500
    $tt.ReshowDelay = 100
    $tt.ShowAlways = $true
    $tt.SetToolTip($btn, "Use a Windows installation ISO or the Media Creation Tool to repair system files. Option 1 downloads an ISO file (large download). Option 2 helps you run the official Media Creation Tool so you can make an ISO interactively. This process may take a long time and requires sufficient disk space.")
    $btn.Tag = @{ ToolTip = $tt }

    $btn.Add_Click({
        try {
            Write-Host 'RestoreHealth (ISO / MediaTool) selected.'
            Write-Host 'Options:'
            Write-Host '  1) Provide a direct ISO URL to download and use'
            Write-Host '  2) Install / Run Media Creation Tool and produce an ISO (you must create it interactively)'
            $choice = Read-Host 'Choose option (1 or 2, or Q to cancel)'
            if ($choice -match '^[Qq]$') { Write-Host 'Cancelled.'; return }

            $isoPath = $null

                if ($choice -eq '1') {
                $isoUrl = Read-Host 'Paste direct ISO download URL (or leave blank to abort)'
                if ([string]::IsNullOrWhiteSpace($isoUrl)) { Write-Host 'No URL provided; aborting.'; return }

                    # Pre-flight disk space check: try to HEAD the URL to get Content-Length
                    $requiredBytes = 0
                    try {
                        $head = Invoke-WebRequest -Uri $isoUrl -Method Head -UseBasicParsing -ErrorAction Stop
                        if ($head.Headers['Content-Length']) { $requiredBytes = [int64]$head.Headers['Content-Length'] }
                    } catch {
                        Write-Host "Could not determine remote file size: $($_.Exception.Message). Will use default required space estimate."
                    }
                    if ($requiredBytes -le 0) { $requiredBytes = 8GB }

                    # Use shared helper to check free space on TEMP
                    . "$PSScriptRoot\Helpers\DiskSpaceHelper.ps1"
                    $space = Test-FreeSpace -Path $env:TEMP -RequiredBytes $requiredBytes
                    if (-not $space.Ok) { Write-Host $space.Message; return }

                    $isoPath = Join-Path -Path $env:TEMP -ChildPath ('Win11_download_{0}.iso' -f ([guid]::NewGuid().ToString()))
                    Write-Host "Downloading ISO to $isoPath (this can take a long time)..."
                try {
                    try {
                        Start-BitsTransfer -Source $isoUrl -Destination $isoPath -ErrorAction Stop
                    } catch {
                        Write-Host "Start-BitsTransfer failed: $($_.Exception.Message). Falling back to Invoke-WebRequest..."
                        Invoke-WebRequest -Uri $isoUrl -OutFile $isoPath -UseBasicParsing -ErrorAction Stop
                    }
                } catch {
                    Write-Host "Download failed: $($_.Exception.Message)"; return
                }

            } elseif ($choice -eq '2') {
                Write-Host 'Attempting to install/run Media Creation Tool...'
                $mctExe = $null

                # Try robust winget installation strategies
                $winget = Get-Command winget -ErrorAction SilentlyContinue
                if ($winget) {
                    $wingetAttempts = @(
                        '--id Microsoft.MediaCreationTool',
                        '--name "Media Creation Tool"',
                        'search "Media Creation Tool" | ForEach-Object { $_.Id } | Select-Object -First 1'
                    )
                    foreach ($att in $wingetAttempts) {
                        try {
                            Write-Host "Attempting winget install: $att"
                            if ($att -like 'search*') {
                                # perform a search and try to install the found id
                                $found = & winget search "Media Creation Tool" --source winget 2>$null | Select-Object -First 1
                                if ($found) {
                                    # Try installing by Id if we can parse an id
                                    # Best-effort; fall back to the other attempts
                                    Start-Process -FilePath 'winget' -ArgumentList "install --id $($found.Id) --accept-package-agreements --accept-source-agreements" -NoNewWindow -Wait -ErrorAction Stop
                                }
                            } else {
                                Start-Process -FilePath 'winget' -ArgumentList "install $att --accept-package-agreements --accept-source-agreements" -NoNewWindow -Wait -ErrorAction Stop
                            }
                        } catch {
                            Write-Host "winget attempt failed for '$att': $($_.Exception.Message)"
                        }
                    }
                } else { Write-Host 'winget not available.' }

                # Try Chocolatey next
                if (-not $mctExe) {
                    $choco = Get-Command choco -ErrorAction SilentlyContinue
                    if ($choco) {
                        try {
                            Write-Host 'Attempting Chocolatey install: mediacreationtool'
                            Start-Process -FilePath 'choco' -ArgumentList 'install mediacreationtool -y' -NoNewWindow -Wait -ErrorAction Stop
                        } catch {
                            Write-Host "choco install attempt failed: $($_.Exception.Message)"
                        }
                    } else { Write-Host 'Chocolatey not available.' }
                }

                # Final fallback: download the Media Creation Tool from Microsoft and run it
                if (-not $mctExe) {
                    try {
                        $mctUrl = 'https://go.microsoft.com/fwlink/?LinkId=691209'  # Microsoft MCT (redirects to latest)
                        $dest = Join-Path -Path $env:TEMP -ChildPath 'MediaCreationTool.exe'
                        if (-not (Test-Path $dest)) {
                            Write-Host "Downloading Media Creation Tool to $dest..."
                            try {
                                Start-BitsTransfer -Source $mctUrl -Destination $dest -ErrorAction Stop
                            } catch {
                                Write-Host "BITS download failed: $($_.Exception.Message). Falling back to Invoke-WebRequest..."
                                Invoke-WebRequest -Uri $mctUrl -OutFile $dest -UseBasicParsing -ErrorAction Stop
                            }
                        } else { Write-Host "Using existing file at $dest" }
                        Write-Host 'Launching Media Creation Tool. Use it to create an ISO, then paste the path when prompted.'
                        Start-Process -FilePath $dest
                        # We expect the user to create an ISO interactively now
                    } catch {
                        Write-Host "Failed to download/run Media Creation Tool: $($_.Exception.Message)"
                    }
                }

                # Try to locate a MediaCreationTool-like exe in Program Files or Chocolatey folder
                $possible = @(
                    "$env:ProgramFiles\MediaCreationTool.exe",
                    "$env:ProgramFiles(x86)\MediaCreationTool.exe",
                    (Join-Path -Path $env:ProgramData -ChildPath 'chocolatey\lib\mediacreationtool\tools\MediaCreationTool.exe'),
                    (Join-Path -Path $env:TEMP -ChildPath 'MediaCreationTool.exe')
                )
                foreach ($p in $possible) { if (Test-Path $p) { $mctExe = $p; break } }

                if (-not $mctExe) {
                    Write-Host 'Could not automatically locate the Media Creation Tool executable after installation attempts or download.'
                    Write-Host 'Please run the Media Creation Tool manually (it will ask you to create media) and then supply the ISO path below.'
                    $isoPath = Read-Host 'After creating the ISO interactively, paste the full path to the ISO file (leave blank to cancel)'
                    if ([string]::IsNullOrWhiteSpace($isoPath)) { Write-Host 'No ISO path provided; aborting.'; return }
                    if (-not (Test-Path $isoPath)) { Write-Host "Provided path does not exist: $isoPath"; return }
                } else {
                    Write-Host "Found Media Creation Tool at: $mctExe -- launching it. Create an ISO and return here when finished."
                    Start-Process -FilePath $mctExe
                    $isoPath = Read-Host 'After creating the ISO, paste the full path to the ISO file (leave blank to cancel)'
                    if ([string]::IsNullOrWhiteSpace($isoPath)) { Write-Host 'No ISO path provided; aborting.'; return }
                    if (-not (Test-Path $isoPath)) { Write-Host "Provided path does not exist: $isoPath"; return }
                }

            } else {
                Write-Host 'Invalid choice; aborting.'; return
            }

            # At this point we should have an ISO path in $isoPath
            if (-not (Test-Path -Path $isoPath)) { Write-Host "ISO not found at $isoPath"; return }

            Write-Host "Mounting ISO: $isoPath"
            try {
                Mount-DiskImage -ImagePath $isoPath -ErrorAction Stop
            } catch {
                Write-Host "Failed to mount ISO: $($_.Exception.Message)"; return
            }

            Start-Sleep -Seconds 2
            # Attempt to resolve the drive letter of the mounted ISO
            $di = Get-DiskImage -ImagePath $isoPath -ErrorAction SilentlyContinue
            $driveRoot = $null
            if ($di) {
                $vol = $di | Get-Volume -ErrorAction SilentlyContinue | Where-Object DriveLetter -ne $null | Select-Object -First 1
                if ($vol -and $vol.DriveLetter) { $driveRoot = ("{0}:\" -f $vol.DriveLetter) }
            }
            if (-not $driveRoot) {
                # Fallback: inspect PSDrives to find new mount (best-effort)
                $rootsBefore = (Get-PSDrive -PSProvider FileSystem | Select-Object -ExpandProperty Root) -as [string[]]
                Start-Sleep -Milliseconds 200
                $rootsAfter = (Get-PSDrive -PSProvider FileSystem | Select-Object -ExpandProperty Root) -as [string[]]
                $driveRoot = (Compare-Object -ReferenceObject $rootsBefore -DifferenceObject $rootsAfter | Where-Object { $_.SideIndicator -eq '=>' } | Select-Object -ExpandProperty InputObject) | Select-Object -First 1
            }

            if (-not $driveRoot) { Write-Host 'Could not determine mounted ISO drive. Aborting.'; Dismount-DiskImage -ImagePath $isoPath -ErrorAction SilentlyContinue; return }

            Write-Host "ISO mounted at $driveRoot"
            $sources = Join-Path -Path $driveRoot -ChildPath 'sources'
            $wim = Join-Path -Path $sources -ChildPath 'install.wim'
            $esd = Join-Path -Path $sources -ChildPath 'install.esd'
            $sourceArg = $null
            if (Test-Path $wim) { $sourceArg = "WIM:$wim:1" }
            elseif (Test-Path $esd) { $sourceArg = "ESD:$esd:1" }
            else { Write-Host 'No install.wim or install.esd found on ISO. Aborting.'; Dismount-DiskImage -ImagePath $isoPath -ErrorAction SilentlyContinue; return }

            Write-Host "Running DISM RestoreHealth using source: $sourceArg"
            try {
                $dismArgs = @('/online','/Cleanup-Image','/RestoreHealth','/Source:' + $sourceArg)
                if ($global:LimitAccess) { $dismArgs += '/LimitAccess' }
                & dism.exe @dismArgs
            } catch {
                Write-Host "DISM failed: $($_.Exception.Message)"
            }

            Write-Host 'Dismounting ISO...'
            try { Dismount-DiskImage -ImagePath $isoPath -ErrorAction Stop } catch { Write-Host "Dismount failed: $($_.Exception.Message)" }
            Write-Host 'RestoreHealth (ISO/MediaTool) finished.'

        } catch {
            Write-Host "Error in RestoreHealthFromISO control: $($_.Exception.Message)"
        }
    })

    $Parent.Controls.Add($btn)
    return $btn
}
